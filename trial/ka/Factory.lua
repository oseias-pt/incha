local Trial = require("core.Trial")
local LegacyUI = require("trial.ka.bridge.LegacyUI")

local Yandir = require("trial.ka.boss.Yandir")
local Vrol = require("trial.ka.boss.Vrol")
local Falgravn = require("trial.ka.boss.Falgravn")

local kaTrial = Trial.create({
    id = "ka",
    zoneId = 1196,
    eventPrefix = "Incha_KA",
    bosses = { Yandir, Vrol, Falgravn },
    bridge = LegacyUI,
    alerts = LegacyUI.alerts,
})

return kaTrial
