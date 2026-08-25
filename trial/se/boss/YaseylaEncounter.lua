local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")

-- ── Ability IDs (from SanitysEdgeHelper data) ────────────────────────────
local DEFLECT         = 184823   -- combatRoute: ACTION_RESULT_BEGIN → Shrapnel stack
local FIRE_BOMBS      = 183660   -- combatRoute: ACTION_RESULT_BEGIN → caAlertCast (targeted)
local CHAIN_PULL      = 184540   -- combatRoute: ACTION_RESULT_BEGIN → Chains alert
local FROST_BOMB_1    = 185403   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → Frost bomb alert
local FROST_BOMB_2    = 183783   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → Frost bomb alert
local IGNITE          = 188188   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION → Move alert (player)
local WAMASU_CHARGE   = 191133   -- combatRoute: ACTION_RESULT_BEGIN → caAlertCast
local ARCHER_TRUE_SHOT= 184802   -- (dead constant — no route registered)

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

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 2000   -- FireBombs / WamasuCharge: empirical

local YaseylaEncounter = {}
YaseylaEncounter.__index = YaseylaEncounter

YaseylaEncounter.key               = "yaseyla"
YaseylaEncounter.nameAliases       = { "Exarchanic Yaseyla" }
YaseylaEncounter.hmHealthThreshold = 80000000   -- vet ~65M, HM ~97.8M
-- location: placeholder — Sunken Elder arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))
YaseylaEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

YaseylaEncounter.stateSchema = {
    firebombTimer  = function() return Timer.new(FIREBOMB_CD) end,
    chainTimer     = function() return Timer.new(CHAIN_CD) end,
    frostTimer     = function() return Timer.new(FROST_CD) end,
    executePhase   = false,
    firstFirebomb  = true,
    firstFrost     = true,
    shrapnelCount  = 0,
    alertList      = function() return {} end,
}

function YaseylaEncounter.new()
    return BossBase.fromSchema(YaseylaEncounter)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function YaseylaEncounter:onLeave(context)
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Frost Bomb: shared handler for both ability IDs.
local function handleFrostBomb(self, context, alerts, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    self.firstFrost = false
    self.frostTimer:reset(FROST_CD)
    if IsUnitPlayer(unitTag) then
        alerts:showAction("Frost Bomb on you! Drop it!")
        CA.alert(nil, "FROST BOMB — drop!", 0x99CCFFFF, SOUNDS.NONE, 3000)
    elseif unitName and unitName ~= "" then
        alerts:showAction("Frost Bomb → " .. unitName)
    end
end

local function handleFireBombs(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    self.firstFirebomb = false
    local cd = self.executePhase and FIREBOMB_EXEC_CD or FIREBOMB_CD
    self.firebombTimer:reset(cd)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Fire Bombs → " .. target)
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    if dur <= 0 then dur = FALLBACK_DUR end
    local cid = CA.alertCast(abilityId, "Fire Bombs!", dur, COL_FIRE)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleChainPull(self, context, alerts, abilityId, ...)
    self.chainTimer:reset(CHAIN_CD)
    alerts:showAction("Chains!")
end

local function handleIgnite(self, context, alerts, abilityId, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction("Ignite on you! Move!")
end

local function handleDeflect(self, context, alerts, abilityId, ...)
    self.shrapnelCount = self.shrapnelCount + 1
    alerts:showAction("SHRAPNEL! Stack! (" .. self.shrapnelCount .. ")")
    CA.alert(nil, "STACK!", 0xFF0033FF, SOUNDS.NONE, 3000)
end

local function handleWamasuCharge(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    if dur <= 0 then dur = FALLBACK_DUR end
    CA.alertCast(abilityId, "Charge → " .. target, dur, COL_FIRE)
end

YaseylaEncounter.combatRoutes = {
    [FIRE_BOMBS]   = { result = ACTION_RESULT_BEGIN,                  fn = handleFireBombs },
    [CHAIN_PULL]   = { result = ACTION_RESULT_BEGIN,                  fn = handleChainPull },
    [FROST_BOMB_1] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [FROST_BOMB_2] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleFrostBomb },
    [IGNITE]       = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleIgnite },
    [DEFLECT]      = { result = ACTION_RESULT_BEGIN,                  fn = handleDeflect },
    [WAMASU_CHARGE]= { result = ACTION_RESULT_BEGIN,                  fn = handleWamasuCharge },
}

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Line 1: Fire Bombs CD; label switches to "Bombs (exec)" once execute phase begins.
local function showFireBombLine(self, alerts)
    if self.firstFirebomb then
        alerts:showInfo(1, "Fire Bombs: first ~7s")
    else
        local r     = self.firebombTimer:remaining()
        local label = self.executePhase and "Bombs (exec)" or "Fire Bombs"
        alerts:showInfo(1, label .. ": " .. (r > 0 and ZO_FormatCountdownTimer(r) or "ready"))
    end
end

-- Line 3: Frost Bomb CD; shows estimated first-cast window before the ability is seen.
local function showFrostBombLine(self, alerts)
    if self.firstFrost then
        alerts:showInfo(3, "Frost: first ~17s")
    else
        local r = self.frostTimer:remaining()
        alerts:showInfo(3, "Frost Bomb: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "ready"))
    end
end

function YaseylaEncounter:onUpdate(context, alerts)
    showFireBombLine(self, alerts)
    local rc = self.chainTimer:remaining()
    alerts:showInfo(2, "Chains: " .. (rc > 0 and ZO_FormatCountdownTimer(rc) or "ready"))
    showFrostBombLine(self, alerts)
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
