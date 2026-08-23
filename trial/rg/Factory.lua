local Trial  = require("core.Trial")
local Panel  = require("ui.Panel")

local CombatHandler = require("core.CombatHandler")
local Oaxiltso = require("trial.rg.boss.Oaxiltso")
local Bahsei   = require("trial.rg.boss.Bahsei")
local Xalvakka = require("trial.rg.boss.Xalvakka")

local rgTrial = Trial.create({
    id              = "rg",
    zoneId          = 1263,
    eventPrefix     = "Incha_RG",
    bosses          = { Oaxiltso, Bahsei, Xalvakka },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

return rgTrial
