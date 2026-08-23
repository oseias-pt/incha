local Location = require("core.Location")
local Timer    = require("lib.Timer")

-- ── CombatAlerts helpers ──────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

-- ── Ability IDs (from AsylumTracker / AsylumPriorityTarget) ───────────────
-- Olms
local OLMS_STORM_THE_HEAVENS  = 98535  -- Kite! ~41 s repeat
local OLMS_TRIAL_BY_FIRE      = 98582  -- Below 25% HP, ~27 s repeat
local OLMS_SCALDING_ROAR      = 98683  -- Steam breath, ~28 s repeat
local OLMS_GUSTS_OF_STEAM     = 98868  -- Jumps at 90/75/50/25%
local OLMS_EXHAUSTIVE_CHARGES = 95482  -- ~12 s repeat
-- Protector
local STATIC_SHIELD           = 96010  -- Protector gives Olms a shield
-- Llothis
local LLOTHIS_DEFILING_BLAST   = 95545  -- Cone attack — target name alert
local LLOTHIS_OPPRESSIVE_BOLTS = 95585  -- Interrupt!
-- Felms
local FELMS_TELEPORT_STRIKE   = 99138  -- Jump — target name alert
-- Mini-boss state
local DORMANT                 = 99990  -- GAINED = mini sleeps; FADED = mini wakes
local BOSS_EVENT              = 10298  -- hitValue=1 marks exact mini-boss spawn time

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local STORM_CD    = 41
local FIRE_CD     = 27
local STEAM_CD    = 28
local CHARGES_CD  = 12
local BLAST_CD    = 21   -- Llothis Defiling Blast
local BOLTS_CD    = 12   -- Llothis Oppressive Bolts (interrupt)
local JUMP_CD     = 21   -- Felms Teleport Strike
local DORMANT_CD  = 45   -- Mini-boss dormant phase duration
local SPAWN_DELAY = 12   -- Seconds after BOSS_EVENT before first mini ability

-- ── Jump milestone thresholds (%) ────────────────────────────────────────
-- Olms jumps at 90/75/50/25%; track the NEXT milestone still approaching.
local JUMP_THRESHOLDS = { 90, 75, 50, 25 }

local OlmsEncounter = {
    id           = 1,
    key          = "olms",
    nameAliases  = { "Saint Olms the Just" },
    -- hmHealthThreshold: TBD — verify in-game on vet HM
    hmHealthThreshold = 0,
    -- Location: entire arena — name-based detection is used instead.
    location = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
OlmsEncounter.stormTimer   = Timer.new(STORM_CD)
OlmsEncounter.steamTimer   = Timer.new(STEAM_CD)
OlmsEncounter.chargesTimer = Timer.new(CHARGES_CD)
OlmsEncounter.fireTimer    = Timer.new(FIRE_CD)

-- ── State ─────────────────────────────────────────────────────────────────
OlmsEncounter.llothisActive    = false
OlmsEncounter.felmsActive      = false
OlmsEncounter.protectorUp      = false
-- Spawn timestamps ([unitId] = GetGameTimeSeconds()) from BOSS_EVENT
OlmsEncounter.spawnTimes       = {}
-- Next un-hit jump milestone index (1-based into JUMP_THRESHOLDS)
OlmsEncounter.nextJumpThreshold = 1
-- Phase 4.2-style CA cast-bar tracking: [unitId] → cid
OlmsEncounter.alertList = {}

function OlmsEncounter:reset()
    self.stormTimer:reset()
    self.steamTimer:reset()
    self.chargesTimer:reset()
    self.fireTimer:reset()
    self.llothisActive      = false
    self.felmsActive        = false
    self.protectorUp        = false
    self.spawnTimes         = {}
    self.nextJumpThreshold  = 1
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
end

-- ── Combat events ─────────────────────────────────────────────────────────
function OlmsEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    -- ── Olms ──────────────────────────────────────────────────────────────
    if abilityId == OLMS_STORM_THE_HEAVENS and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Kite! (Storm the Heavens)")
        caAlert(nil, "KITE!", 0xFF4400FF, SOUNDS.NONE, 3000)
        self.stormTimer:reset()

    elseif abilityId == OLMS_SCALDING_ROAR and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Steam Breath! Move!")
        local dur = select(1, GetAbilityCastInfo(OLMS_SCALDING_ROAR)) or 0
        if dur <= 0 then dur = 2000 end
        local cid = caAlertCast(abilityId, "Steam Breath!", dur,
            { -3, 0, false, { 0.8, 0.4, 0, 0.4 }, { 0.8, 0.4, 0, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
        self.steamTimer:reset()

    elseif abilityId == OLMS_EXHAUSTIVE_CHARGES and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Charges!")
        self.chargesTimer:reset()

    elseif abilityId == OLMS_TRIAL_BY_FIRE and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Trial by Fire!")
        self.fireTimer:reset()

    elseif abilityId == OLMS_GUSTS_OF_STEAM and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Jump! Dodge!")
        -- Advance past this milestone so the next pre-warning is correct.
        if self.nextJumpThreshold <= #JUMP_THRESHOLDS then
            self.nextJumpThreshold = self.nextJumpThreshold + 1
        end

    -- ── AS-3: Llothis mechanics ───────────────────────────────────────────
    -- (placeholder — implemented in AS-3)

    -- ── AS-4: Felms mechanics ─────────────────────────────────────────────
    -- (placeholder — implemented in AS-4)

    -- ── AS-5: Protector / Static Shield ──────────────────────────────────
    -- (placeholder — implemented in AS-5)
    end
end

-- ── Effect changed ────────────────────────────────────────────────────────
function OlmsEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- AS-3/4: DORMANT tracking for Llothis and Felms
end

-- ── 200 ms display update ─────────────────────────────────────────────────
function OlmsEncounter:onUpdate(context, alerts)
    local t1 = self.stormTimer:remaining()
    local t2 = self.steamTimer:remaining()
    local t3 = self.chargesTimer:remaining()

    alerts:showInfo(1, "Storm:   " .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or "ready"))
    alerts:showInfo(2, "Steam:   " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
    alerts:showInfo(3, "Charges: " .. (t3 > 0 and ZO_FormatCountdownTimer(t3) or "ready"))

    -- Fire timer only meaningful below 25%; hide it above.
    local t4 = self.fireTimer:remaining()
    if t4 > 0 then
        alerts:showInfo(4, "Fire:    " .. ZO_FormatCountdownTimer(t4))
    else
        alerts:showInfo(4, "")
    end
    -- Lines 5-7 reserved for mini-boss timers (AS-3/4)
end

-- ── HP milestone pre-warning ──────────────────────────────────────────────
function OlmsEncounter:onPowerUpdate(context, healthPercent, alerts)
    if self.nextJumpThreshold > #JUMP_THRESHOLDS then return end
    local threshold = JUMP_THRESHOLDS[self.nextJumpThreshold]

    -- Warn when within 3% above the next milestone.
    if healthPercent <= threshold + 3 and healthPercent > threshold then
        alerts:showInfo(1, "Jump at " .. threshold .. "%!")
    end
end

return OlmsEncounter
