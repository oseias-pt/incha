local Trial          = require("core.Trial")
local Panel          = require("ui.Panel")
local CombatHandler  = require("core.CombatHandler")
local OlmsEncounter  = require("trial.as.boss.OlmsEncounter")

local asTrial = Trial.create({
    id              = "as",
    zoneId          = 1000,
    eventPrefix     = ADDON_PREFIX .. "AS",
    bosses          = { OlmsEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = CombatHandler.abilityIdsFor,
    onCombatEventFiltered   = CombatHandler.onCombatEventFiltered,
    onEffectChangedFiltered = CombatHandler.onEffectChangedFiltered,
    onDiedCombatEvent       = CombatHandler.onDiedCombatEvent,
    onLegacyCombatEvent     = CombatHandler.onLegacyCombatEvent,
})

package.loaded["trial.as.Factory"] = asTrial
return asTrial
