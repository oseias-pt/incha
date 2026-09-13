--- DreadsailCommon  -  trash-add mechanics shared across all three DSR arenas.
---
--- Phase 2 (EventDispatcher):
---   Exposes DreadsailCommon.beginCastEntries and DreadsailCommon.effectChangedEntries
---   which each boss merges into its own event buckets.

local AlertTypes = require("core.AlertTypes")
local CA = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Colors = require("core.Colors")
local DreadsailCommon = {}

-- -- Ability IDs -----------------------------------------------------------
local SWASH_TARGETED  = 170523   -- Swashbuckler: chase target 6 s
local SWASH_APERTURE  = 171004   -- Swashbuckler: dagger kite 5 s
local CASCADE_BOOT    = 170188   -- Overseer: ice kick (player-targeted)
local STORM_CELL      = 169994   -- Sail Riper: stand-in-donut
local WING_SLICE      = 169991   -- Harpy: heavy melee
local HORN_STRIKE_1   = 169869   -- Bow Breaker: frontal charge 1
local HORN_STRIKE_2   = 169871   -- Bow Breaker: frontal charge 2
local TOXIC_MUCUS     = 169862   -- Bow Breaker: ranged spit

-- -- Fallback cast durations -----------------------------------------------
local DUR_MELEE  = 1500
local DUR_RANGED = 2000

-- -- CA colour palettes ----------------------------------------------------
local ACT_BLOCK  = { 6000, "BLOCK!",     0.9, 0.1, 0.1, 0.9, nil }
local ACT_KITE   = { 5000, "KITE BACK!", 0.9, 0.5, 0.0, 0.9, nil }
local ACT_DONUT  = { 2000, "IN DONUT",   0.9, 0.8, 0.0, 0.9, nil }

-- -- Handlers (combat, new-style) ------------------------------------------

local function handleCascadeBoot(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, DUR_MELEE)
    CA.melee(abilityId, sourceUnitName, dur, Colors.ICE)
end

local function handleStormCell(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, DUR_MELEE)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE, ACT_DONUT)
end

local function handleWingSlice(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, DUR_MELEE)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleHornStrike(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, DUR_MELEE)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleToxicMucus(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, DUR_RANGED)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

-- -- Handlers (effectChanged, new-style) ------------------------------------

local function handleSwashTargetedGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        CA.bar(abilityId, "Swashbuckler targets you!",
            6000, 6000, Colors.LIGHTNING, 0.5, ACT_BLOCK)
        PlaySound(SOUNDS.DUEL_START)
    end
end

local function handleSwashApertureGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        CA.bar(abilityId, "Swashbuckler daggers",
            5000, 5000, Colors.LIGHTNING, 0.5, ACT_KITE)
        PlaySound(SOUNDS.DUEL_START)
    end
end

-- -- Shared entries --------------------------------------------------------

DreadsailCommon.beginCastEntries = {
    [CASCADE_BOOT]  = { type = AlertTypes.CUSTOM, fn = handleCascadeBoot },
    [STORM_CELL]    = { type = AlertTypes.CUSTOM, fn = handleStormCell },
    [WING_SLICE]    = { type = AlertTypes.CUSTOM, fn = handleWingSlice },
    [HORN_STRIKE_1] = { type = AlertTypes.CUSTOM, fn = handleHornStrike },
    [HORN_STRIKE_2] = { type = AlertTypes.CUSTOM, fn = handleHornStrike },
    [TOXIC_MUCUS]   = { type = AlertTypes.CUSTOM, fn = handleToxicMucus },
}

DreadsailCommon.effectChangedEntries = {
    gained = {
        [SWASH_TARGETED] = { type = AlertTypes.CUSTOM, fn = handleSwashTargetedGained },
        [SWASH_APERTURE] = { type = AlertTypes.CUSTOM, fn = handleSwashApertureGained },
    },
    faded   = {},
    updated = {},
}

package.loaded["trial.dsr.DreadsailCommon"] = DreadsailCommon
return DreadsailCommon
