local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs (from SanitysEdgeHelper data) ────────────────────────────
local DEFLECT         = 184823        -- Shrapnel — BEGIN + hitValue>1000 → STACK
local FIRE_BOMBS      = 183660        -- Fire Bombs — BEGIN on player
local CHAIN_PULL      = 184540        -- Chain Pull — BEGIN → timer
local FROST_BOMB_1    = 185403        -- Frost Bomb applied
local FROST_BOMB_2    = 183783        -- Frost Bomb applied (variant)
local IGNITE          = 188188        -- Ignite — EFFECT_GAINED_DURATION on player
local WAMASU_CHARGE   = 191133        -- Wamasu Charge — BEGIN + hitValue>200
local ARCHER_TRUE_SHOT= 184802        -- Archer True Shot

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local FIREBOMB_FIRST_CD  =  7.5   -- time to first firebombs from combat start
local FIREBOMB_CD        = 23.5   -- pre-execute CD
local FIREBOMB_EXEC_CD   = 11     -- execute-phase CD (after <26% HP)
local FIREBOMB_EXEC_THOLD= 26     -- % HP that marks execute phase
local CHAIN_CD           = 32     -- chain pull CD
local FROST_FIRST_CD     = 17     -- first frost bomb delay
local FROST_CD           = 25     -- subsequent frost bomb CD

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_FIRE  = { -3, 0, false, { 1, 0.34, 0, 0.4 }, { 1, 0.34, 0, 0.8 } }    -- orange-red
local COL_ICE   = { -3, 0, false, { 0.6, 0.8, 1, 0.4 }, { 0.6, 0.8, 1, 0.8 } }  -- pale blue

local YaseylaEncounter = {}
YaseylaEncounter.__index = YaseylaEncounter

YaseylaEncounter.key               = "yaseyla"
YaseylaEncounter.nameAliases       = { "Exarchanic Yaseyla" }
YaseylaEncounter.hmHealthThreshold = 80000000   -- vet ~65M, HM ~97.8M
YaseylaEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

function YaseylaEncounter.new()
    return setmetatable({
        firebombTimer  = Timer.new(FIREBOMB_CD),
        chainTimer     = Timer.new(CHAIN_CD),
        frostTimer     = Timer.new(FROST_CD),
        executePhase   = false,
        firstFirebomb  = true,
        firstFrost     = true,
        shrapnelCount  = 0,
        alertList      = {},
    }, YaseylaEncounter)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function YaseylaEncounter:onLeave(context)
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Frost Bomb: shared handler for both ability IDs.
local function handleFrostBomb(self, context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
    self.firstFrost = false
    self.frostTimer:reset(FROST_CD)
    if IsUnitPlayer(unitTag) then
        alerts:showAction("Frost Bomb on you! Drop it!")
        CA.alert(nil, "FROST BOMB — drop!", 0x99CCFFFF, SOUNDS.NONE, 3000)
    elseif unitName and unitName ~= "" then
        alerts:showAction("Frost Bomb → " .. unitName)
    end
end

YaseylaEncounter.combatRoutes = {
    [FIRE_BOMBS] = function(self, context, alerts, result, abilityId,
                             unitTag, sourceUnitTag, sourceUnitId, unitId,
                             sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.firstFirebomb = false
        local cd = self.executePhase and FIREBOMB_EXEC_CD or FIREBOMB_CD
        self.firebombTimer:reset(cd)
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Fire Bombs → " .. target)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        local cid = CA.alertCast(abilityId, "Fire Bombs!", dur, COL_FIRE)
        if cid and unitId then self.alertList[unitId] = cid end
    end,
    [CHAIN_PULL] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.chainTimer:reset(CHAIN_CD)
        alerts:showAction("Chains!")
    end,
    [FROST_BOMB_1] = handleFrostBomb,
    [FROST_BOMB_2] = handleFrostBomb,
    [IGNITE] = function(self, context, alerts, result, abilityId, unitTag, ...)
        if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
        if not IsUnitPlayer(unitTag) then return end
        alerts:showAction("Ignite on you! Move!")
    end,
    [DEFLECT] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.shrapnelCount = self.shrapnelCount + 1
        alerts:showAction("SHRAPNEL! Stack! (" .. self.shrapnelCount .. ")")
        CA.alert(nil, "STACK!", 0xFF0033FF, SOUNDS.NONE, 3000)
    end,
    [WAMASU_CHARGE] = function(self, context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        local target = (unitName and unitName ~= "") and unitName or "?"
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        CA.alertCast(abilityId, "Charge → " .. target, dur, COL_FIRE)
    end,
}

function YaseylaEncounter:onUpdate(context, alerts)
    -- Line 1: Fire Bombs CD
    if self.firstFirebomb then
        alerts:showInfo(1, "Fire Bombs: first ~7s")
    else
        local r = self.firebombTimer:remaining()
        local label = self.executePhase and "Bombs (exec)" or "Fire Bombs"
        alerts:showInfo(1, label .. ": " .. (r > 0 and ZO_FormatCountdownTimer(r) or "ready"))
    end

    -- Line 2: Chain Pull CD
    local rc = self.chainTimer:remaining()
    alerts:showInfo(2, "Chains: " .. (rc > 0 and ZO_FormatCountdownTimer(rc) or "ready"))

    -- Line 3: Frost Bomb CD
    if self.firstFrost then
        alerts:showInfo(3, "Frost: first ~17s")
    else
        local rf = self.frostTimer:remaining()
        alerts:showInfo(3, "Frost Bomb: " .. (rf > 0 and ZO_FormatCountdownTimer(rf) or "ready"))
    end

    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

function YaseylaEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- Enter execute phase when HP drops below 26%
    if not self.executePhase and healthPercent > 0 and healthPercent < FIREBOMB_EXEC_THOLD then
        self.executePhase = true
        alerts:showAction("Execute! (<26%) Fire Bombs accelerate")
    end
end

return YaseylaEncounter
