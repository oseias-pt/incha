--- SunspireCommon  -  mechanics shared across all three Sunspire boss arenas.
---
--- These abilities appear regardless of which boss (Lokke/Yolna/Nahvii) is
--- active: boss heavy attacks, cat and 2H-add interrupts, shield charge,
--- dragon breaths, and fire spit.
---
--- Phase 2 (EventDispatcher):
---   Exposes SunspireCommon.beginCastEntries — a shared table that each boss
---   merges into its own _beginCastEntry so abilityIdsFor includes common IDs.
---
--- hitValue unavailability note (old API -> modern):
---   HTS used hitValue for cast-duration timers.  Modern API lacks it; we use
---   GetAbilityCastInfo(abilityId) with a per-ability fallback constant instead.

local AlertTypes = require("core.AlertTypes")
local CA         = require("external-api.CombatAlerts")
local CastDur    = require("lib.CastDur")
local Lang       = require("core.Lang")
local Colors     = require("core.Colors")

local SunspireCommon = {}

-- -- Ability ID sets --------------------------------------------------------
-- Heavy Attacks: all bosses + shared adds (iron servant, 1H&Shield add, cone)
local HA_IDS = {
    [115723] = true,   -- Lokkestiiz HA
    [123026] = true,   -- Lokkestiiz Wing Thrash
    [122124] = true,   -- Yolnahkriin HA
    [121833] = true,   -- Yolnahkriin Wing Thrash
    [121849] = true,   -- Yolnahkriin Wing Thrash (alt)
    [115443] = true,   -- Nahviintaas HA
    [119796] = true,   -- Nahviintaas Wing Thrash
    [121422] = true,   -- Cone-portal HA
    [117071] = true,   -- 1H & Shield add HA
    [119817] = true,   -- Iron Servant Anvil Cracker
}

-- Cat (Senche) jump attacks  -  all three arenas
local BLOCK_IDS = {
    [120890] = true,   -- red cat jump
    [122012] = true,   -- white cat jump
}

-- Dragonbreath types across all three bosses
local BREATH_IDS = {
    [119283] = true,   -- Frost Breath  (Lokke)
    [121723] = true,   -- Fire Breath   (Yolna)
    [121980] = true,   -- Searing Breath (Nahvii)
}

-- Fire Spit -> incoming atronach; value = post-cast travel offset in ms
local SPIT_IDS = {
    [118860] = 900,    -- spit during Lokke/Yolna phases
    [115592] = 700,    -- spit during Nahvii phase
}

local SHIELD_CHARGE = 117075   -- 1H & Shield add charge
local LEAP          = 116836   -- 2H add leap

-- -- Fallback cast durations (ms) ------------------------------------------
-- Used when GetAbilityCastInfo returns 0 (instant / unknown).
local HA_FALLBACK     = 1400
local BLOCK_FALLBACK  =  800   -- cat / 2H-add jump travel
local BREATH_FALLBACK = 3000
local SPIT_FALLBACK   = 1200
local CHARGE_FALLBACK = 1200

-- -- Handlers (new-style: boss, context, alerts, abilityId, sourceUnitName, unitTag, ...) --

local function handleHeavyAttack(boss, context, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, HA_FALLBACK)
    alerts:showAction(Lang.t("ss_block_heavy_attack"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleCatJump(boss, context, alerts, abilityId, sourceUnitName, ...)
    local dur = CastDur.get(abilityId, BLOCK_FALLBACK)
    alerts:showAction(Lang.t("ss_block_jump"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.LIGHTNING)
end

local function handleLeap(boss, context, alerts, abilityId, sourceUnitName, ...)
    local dur = CastDur.get(LEAP, BLOCK_FALLBACK)
    alerts:showAction(Lang.t("ss_dodge_leap"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.LIGHTNING)
end

local function handleShieldCharge(boss, context, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(SHIELD_CHARGE, CHARGE_FALLBACK)
    alerts:showAction(Lang.t("ss_block_shield_charge"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.ICE)
end

local function handleBreath(boss, context, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, BREATH_FALLBACK)
    alerts:showAction(Lang.t("ss_dodge_breath"))
    CA.ranged(abilityId, sourceUnitName, dur, Colors.ICE)
end

-- Fire Spit: uses the per-ability travel offset stored in SPIT_IDS.
-- HTS added the offset to hitValue; here we look it up from the table.
local function handleSpit(boss, context, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local offset = SPIT_IDS[abilityId] or 900
    local dur    = CastDur.get(abilityId, SPIT_FALLBACK)
    alerts:showAction(Lang.t("ss_atro_incoming"))
    CA.ranged(abilityId, sourceUnitName, dur + offset, Colors.ORANGE)
end

-- -- Shared begin-cast entries -----------------------------------------------
-- Each SS boss merges this table into its own _beginCastEntry so that all
-- common-mechanic ability IDs are included in EventDispatcher.abilityIdsFor.
-- Built by iterating the ID sets rather than restating each ID individually,
-- so the two cannot disagree (same contract as the old combatAbilityIds set).
local _beginCastEntries = {
    [SHIELD_CHARGE] = { type = AlertTypes.CUSTOM, fn = handleShieldCharge },
    [LEAP]          = { type = AlertTypes.CUSTOM, fn = handleLeap },
}
for id in pairs(HA_IDS)    do _beginCastEntries[id] = { type = AlertTypes.CUSTOM, fn = handleHeavyAttack } end
for id in pairs(BLOCK_IDS) do _beginCastEntries[id] = { type = AlertTypes.CUSTOM, fn = handleCatJump }     end
for id in pairs(BREATH_IDS) do _beginCastEntries[id] = { type = AlertTypes.CUSTOM, fn = handleBreath }     end
for id in pairs(SPIT_IDS)  do _beginCastEntries[id] = { type = AlertTypes.CUSTOM, fn = handleSpit }        end

SunspireCommon.beginCastEntries = _beginCastEntries

package.loaded["trial.ss.SunspireCommon"] = SunspireCommon
return SunspireCommon
