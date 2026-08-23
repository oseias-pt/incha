local Trial          = require("core.Trial")
local Panel          = require("ui.Panel")
local CombatHandler  = require("trial.se.CombatHandler")
local YaseylaEncounter = require("trial.se.boss.YaseylaEncounter")
local ChimeraEncounter = require("trial.se.boss.ChimeraEncounter")
local AnsuulEncounter  = require("trial.se.boss.AnsuulEncounter")

local seTrial = Trial.create({
    id              = "se",
    zoneId          = 1427,
    eventPrefix     = "Incha_SE",
    bosses          = { YaseylaEncounter, ChimeraEncounter, AnsuulEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

return seTrial
