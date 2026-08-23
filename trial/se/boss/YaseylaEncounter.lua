local Location = require("core.Location")
local Timer    = require("lib.Timer")

-- ── CombatAlerts helpers ──────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

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

local YaseylaEncounter = {
    id                = 1,
    key               = "yaseyla",
    nameAliases       = { "Exarchanic Yaseyla" },
    hmHealthThreshold = 80000000,   -- vet ~65M, HM ~97.8M
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
YaseylaEncounter.firebombTimer = Timer.new(FIREBOMB_CD)
YaseylaEncounter.chainTimer    = Timer.new(CHAIN_CD)
YaseylaEncounter.frostTimer    = Timer.new(FROST_CD)

-- ── State ─────────────────────────────────────────────────────────────────
YaseylaEncounter.executePhase     = false
YaseylaEncounter.firstFirebomb    = true
YaseylaEncounter.firstFrost       = true
YaseylaEncounter.shrapnelCount    = 0
YaseylaEncounter.alertList        = {}

function YaseylaEncounter:reset()
    self.firebombTimer:clear()
    self.chainTimer:clear()
    self.frostTimer:clear()
    self.executePhase  = false
    self.firstFirebomb = true
    self.firstFrost    = true
    self.shrapnelCount = 0
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
end

function YaseylaEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if abilityId == FIRE_BOMBS and result == ACTION_RESULT_BEGIN then
        self.firstFirebomb = false
        local cd = self.executePhase and FIREBOMB_EXEC_CD or FIREBOMB_CD
        self.firebombTimer:reset(cd)
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Fire Bombs → " .. target)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        local cid = caAlertCast(abilityId, "Fire Bombs!", dur, COL_FIRE)
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == CHAIN_PULL and result == ACTION_RESULT_BEGIN then
        self.chainTimer:reset(CHAIN_CD)
        alerts:showAction("Chains!")

    elseif (abilityId == FROST_BOMB_1 or abilityId == FROST_BOMB_2)
           and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.firstFrost = false
        self.frostTimer:reset(FROST_CD)
        if IsUnitPlayer(unitTag) then
            alerts:showAction("Frost Bomb on you! Drop it!")
            caAlert(nil, "FROST BOMB — drop!", 0x99CCFFFF, SOUNDS.NONE, 3000)
        elseif unitName and unitName ~= "" then
            alerts:showAction("Frost Bomb → " .. unitName)
        end

    elseif abilityId == IGNITE and result == ACTION_RESULT_EFFECT_GAINED_DURATION
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Ignite on you! Move!")

    elseif abilityId == DEFLECT and result == ACTION_RESULT_BEGIN then
        -- hitValue not available directly; Shrapnel fires at ACTION_RESULT_BEGIN
        self.shrapnelCount = self.shrapnelCount + 1
        alerts:showAction("SHRAPNEL! Stack! (" .. self.shrapnelCount .. ")")
        caAlert(nil, "STACK!", 0xFF0033FF, SOUNDS.NONE, 3000)

    elseif abilityId == WAMASU_CHARGE and result == ACTION_RESULT_BEGIN then
        local target = (unitName and unitName ~= "") and unitName or "?"
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        caAlertCast(abilityId, "Charge → " .. target, dur, COL_FIRE)
    end
end

function YaseylaEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- No persistent effect tracking needed for Yaseyla; handled in onCombatEvent.
end

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
