--- RockgroveCommon  -  trash-add mechanics shared across all three Rockgrove arenas.
---
--- Phase 2 (EventDispatcher):
---   Exposes RockgroveCommon.beginCastEntries — a shared table that each boss
---   merges into its own _beginCastEntry so abilityIdsFor includes common IDs.

local AlertTypes = require("core.AlertTypes")
local CA = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")
local Colors = require("core.Colors")
local RockgroveCommon = {}

-- -- Ability IDs ------------------------------------------------------------
local EARTHQUAKE   = 149535   -- Reaver: AoE ground DoT on floor
local SUNDERING    = 149524   -- Reaver: heavy melee on tank
local TAKING_AIM   = 152496   -- Bloodseeker: channeled multi-target ranged
local QUICK_STRIKE = 149313   -- Butcher: targeted melee
local SCALDING     = 153175   -- Fire Behemoth (trash + Bahsei arena): targeted DoT
local PRIME_METEOR = 152414   -- Torchcaster: summons Prime Meteor (10 s to kill)
local MOLTEN_RAIN  = 157482   -- Ash Titan: fire rain to kite

local ASTRAL_SHIELD_IDS = { [149089] = true, [157466] = true }   -- Soulweaver
local ASSAULT_IDS       = { [149268] = true, [149261] = true }   -- Barbarian Hasted Assault

-- -- Fallback cast durations (ms) ------------------------------------------
local FALL_MELEE   = 1500
local FALL_MOLTEN  = 3000
local FALL_ASSAULT = 1500

-- -- Barbarian Hasted Assault: dodge window length -------------------------
local DODGE_DUR = GetAbilityDuration(28549) or 0
if DODGE_DUR <= 0 then DODGE_DUR = 650 end

-- -- CA colour palettes -----------------------------------------------------
local ACT_ASSAULT = { DODGE_DUR, "Hold Block!", 0.8, 0.0, 0.0, 0.9, nil }
local ACT_METEOR  = { 10000,     "KILL SUN!",   0.8, 0.0, 0.0, 0.9, nil }

-- -- Handlers (new-style: boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...) --

local function handleEarthquake(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, "Earthquake", 0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
end

local function handleSundering(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(SUNDERING, FALL_MELEE)
    alerts:showAction(Lang.t("rg_block_sundering"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleTakingAim(boss, ctx, alerts, abilityId, sourceUnitName, ...)
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        local dur = CastDur.get(TAKING_AIM, FALL_MELEE)
        CA.interrupt_melee(abilityId, sourceUnitName, dur, Colors.ICE)
        PlaySound(SOUNDS.DUEL_START)
    end
end

local function handleAstralShield(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, "Astral Shield", 0x75E6DAD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
end

local function handleQuickStrike(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(QUICK_STRIKE, FALL_MELEE)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleScalding(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(SCALDING, FALL_MELEE)
    alerts:showAction(Lang.t("rg_dodge_scalding"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.RED)
    CA.alert(nil, "Scalding", 0xCC0000D9, SOUNDS.DUEL_START, 9000)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleAssault(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALL_ASSAULT)
    CA.bar(abilityId, "Hasted Assault (Barbarian)",
        dur, 4000, Colors.FLYZONE, 0.4, ACT_ASSAULT)
    PlaySound(SOUNDS.DUEL_START)
end

local function handlePrimeMeteor(boss, ctx, alerts, abilityId, ...)
    CA.bar(abilityId, "Prime Meteor",
        13500, 13500, Colors.FLYZONE, 0.4, ACT_METEOR)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleMoltenRain(boss, ctx, alerts, abilityId, sourceUnitName, ...)
    local dur = CastDur.get(MOLTEN_RAIN, FALL_MOLTEN)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

-- -- Shared begin-cast entries -----------------------------------------------
local _beginCastEntries = {
    [EARTHQUAKE]   = { type = AlertTypes.CUSTOM, fn = handleEarthquake },
    [SUNDERING]    = { type = AlertTypes.CUSTOM, fn = handleSundering },
    [TAKING_AIM]   = { type = AlertTypes.CUSTOM, fn = handleTakingAim },
    [QUICK_STRIKE] = { type = AlertTypes.CUSTOM, fn = handleQuickStrike },
    [SCALDING]     = { type = AlertTypes.CUSTOM, fn = handleScalding },
    [PRIME_METEOR] = { type = AlertTypes.CUSTOM, fn = handlePrimeMeteor },
    [MOLTEN_RAIN]  = { type = AlertTypes.CUSTOM, fn = handleMoltenRain },
}
for id in pairs(ASTRAL_SHIELD_IDS) do
    _beginCastEntries[id] = { type = AlertTypes.CUSTOM, fn = handleAstralShield }
end
for id in pairs(ASSAULT_IDS) do
    _beginCastEntries[id] = { type = AlertTypes.CUSTOM, fn = handleAssault }
end

RockgroveCommon.beginCastEntries = _beginCastEntries

package.loaded["trial.rg.RockgroveCommon"] = RockgroveCommon
return RockgroveCommon
