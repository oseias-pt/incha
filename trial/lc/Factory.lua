local Trial             = require("core.Trial")
local Panel             = require("ui.Panel")
local CombatHandler     = require("trial.lc.CombatHandler")
local RyelazEncounter   = require("trial.lc.boss.RyelazEncounter")
local DarielEncounter   = require("trial.lc.boss.DarielEncounter")
local OrphicEncounter   = require("trial.lc.boss.OrphicEncounter")
local XynizataEncounter = require("trial.lc.boss.XynizataEncounter")
local XorynEncounter    = require("trial.lc.boss.XorynEncounter")

local lcTrial = Trial.create({
    id              = "lc",
    zoneId          = 1478,
    eventPrefix     = "Incha_LC",
    bosses          = { RyelazEncounter, DarielEncounter, OrphicEncounter,
                        XynizataEncounter, XorynEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

return lcTrial
