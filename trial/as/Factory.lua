local Trial          = require("core.Trial")
local Panel          = require("ui.Panel")

local EventDispatcher = require("core.EventDispatcher")
local OlmsEncounter  = require("trial.as.boss.OlmsEncounter")

local asTrial = Trial.create({
    id              = "as",
    zoneId          = 1000,
    eventPrefix     = ADDON_PREFIX .. "AS",
    bosses          = { OlmsEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = EventDispatcher.abilityIdsFor,
    onCombatEventFiltered   = EventDispatcher.onCombatEventFiltered,
    onEffectChangedFiltered = EventDispatcher.onEffectChangedFiltered,
    onDiedCombatEvent       = EventDispatcher.onDiedCombatEvent,
})

package.loaded["trial.as.Factory"] = asTrial
return asTrial
