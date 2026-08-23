local Location = require("core.Location")

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
local LLOTHIS_DEFILING_BLAST  = 95545  -- Cone attack — target name alert
local LLOTHIS_OPPRESSIVE_BOLTS = 95585 -- Interrupt!
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

local OlmsEncounter = {
    id           = 1,
    key          = "olms",
    nameAliases  = { "Saint Olms the Just" },
    -- hmHealthThreshold: TBD — verify in-game on vet HM
    hmHealthThreshold = 0,
    -- Location: entire arena — name-based detection is used instead.
    location = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── State ─────────────────────────────────────────────────────────────────
-- Mini-boss presence
OlmsEncounter.llothisActive  = false
OlmsEncounter.felmsActive    = false
OlmsEncounter.protectorUp    = false
-- Spawn timestamps ([unitId] = GetGameTimeSeconds()) from BOSS_EVENT
OlmsEncounter.spawnTimes     = {}

function OlmsEncounter:reset()
    self.llothisActive  = false
    self.felmsActive    = false
    self.protectorUp    = false
    self.spawnTimes     = {}
end

function OlmsEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
    -- AS-2: Olms mechanics
    -- AS-3: Llothis mechanics
    -- AS-4: Felms mechanics
    -- AS-5: Protector / Static Shield
end

function OlmsEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- AS-3/4: DORMANT tracking for Llothis and Felms
end

function OlmsEncounter:onUpdate(context, alerts)
    -- AS-6: countdown displays
end

function OlmsEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- AS-2: HP milestone jump pre-warnings (90/75/50/25%)
end

return OlmsEncounter
