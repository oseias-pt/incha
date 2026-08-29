local Trial          = require("core.Trial")
local Panel          = require("ui.Panel")
local CombatHandler  = require("core.CombatHandler")
local YaseylaEncounter = require("trial.se.boss.YaseylaEncounter")
local ChimeraEncounter = require("trial.se.boss.ChimeraEncounter")
local AnsuulEncounter  = require("trial.se.boss.AnsuulEncounter")

local seTrial = Trial.create({
    id              = "se",
    zoneId          = 1427,
    eventPrefix     = ADDON_PREFIX .. "SE",
    bosses          = { YaseylaEncounter, ChimeraEncounter, AnsuulEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

package.loaded["trial.se.Factory"] = seTrial
return seTrial
