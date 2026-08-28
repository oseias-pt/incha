local Trial          = require("core.Trial")
local Panel          = require("ui.Panel")
local CombatHandler  = require("core.CombatHandler")
local OlmsEncounter  = require("trial.as.boss.OlmsEncounter")

local asTrial = Trial.create({
    id              = "as",
    zoneId          = 1000,
    eventPrefix     = "Incha_AS",
    bosses          = { OlmsEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

package.loaded["trial.as.Factory"] = asTrial
return asTrial
