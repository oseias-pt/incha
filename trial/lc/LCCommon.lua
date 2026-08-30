--- LCCommon  -  cross-encounter mechanics shared across all Lucent Citadel arenas.
---
--- Three abilities appear regardless of which boss is active:
---   HINDERED        (165972): tank-swap debuff -> alert on player
---   RADIANCE_DEBUFF (214675): red screen border while debuff is active
---   SOLAR_FLARE     (222475): Dremora Spellcaster cast bar
---
--- Interface (same contract as OsseinCageCommon / RockgroveCommon):
---   .handle(alerts, result, abilityId, unitTag, sourceUnitName) -> bool
---       Called by CombatHandler before combatRoutes; true short-circuits routing.
---   .handleEffect(alerts, changeType, abilityId, unitTag, stackCount) -> bool
---       Called by CombatHandler before effectRoutes; true short-circuits routing.
---
--- Hindered OSI icon: deferred  -  unit OSI API requires in-game coordinate
--- measurement.  An alert fires for the tank instead.

local CA      = require("lib.CA")
local CastDur = require("lib.CastDur")

local LCCommon = {}

-- -- Ability IDs ------------------------------------------------------------
local HINDERED        = 165972   -- tank-swap debuff
local RADIANCE_DEBUFF = 214675   -- red screen border on player
local SOLAR_FLARE     = 222475   -- Dremora Spellcaster cast bar

-- -- Fallback cast duration (ms) -------------------------------------------
local FALL_SOLAR = 2500   -- Solar Flare: empirical

-- -- CA colour palette ------------------------------------------------------
local COL_SOLAR = { -2, 0, false, { 1.0, 0.6, 0.0, 0.4 }, { 1.0, 0.6, 0.0, 0.8 } }

-- -- Combat-event handler ---------------------------------------------------
-- Handles ACTION_RESULT_BEGIN events shared across all LC encounters.
-- Returning true short-circuits the boss combatRoutes lookup.
function LCCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName)
    if result ~= ACTION_RESULT_BEGIN then return false end

    -- Dremora Spellcaster: Solar Flare (cast bar) --------------------------
    if abilityId == SOLAR_FLARE then
        local dur = CastDur.get(SOLAR_FLARE, FALL_SOLAR)
        CA.alertCast(abilityId, sourceUnitName or "Solar Flare", dur, COL_SOLAR)
        return true
    end

    return false
end

-- -- Effect-changed handler -------------------------------------------------
-- Handles EVENT_EFFECT_CHANGED events shared across all LC encounters.
-- Returning true short-circuits the boss effectRoutes lookup.
function LCCommon.handleEffect(alerts, changeType, abilityId, unitTag, stackCount)
    -- Hindered: tank-swap debuff (tank player only) ------------------------
    -- OSI mechanic icon is deferred; alert fires for the tank instead.
    if abilityId == HINDERED then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType ~= EFFECT_RESULT_FADED then
            local _, _, isTank = GetPlayerRoles()
            if isTank then
                alerts:showAction("SWAP! (Hindered)")
                CA.alert(nil, "Tank swap  -  Hindered!", 0x4488FFD9, SOUNDS.NONE, 5000)
            end
        end
        return true
    end

    -- Radiance: red screen border while debuff is active (player only) -----
    if abilityId == RADIANCE_DEBUFF then
        if not IsUnitPlayer(unitTag) then return false end
        if changeType == EFFECT_RESULT_FADED then
            CA.border(false, 0, "red")
        else
            CA.border(true, 8000, "red")
        end
        return true
    end

    return false
end

package.loaded["trial.lc.LCCommon"] = LCCommon
return LCCommon
