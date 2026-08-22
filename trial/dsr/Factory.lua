local Panel  = require("ui.Panel")   -- already in package.loaded (pre-loaded by incha.lua)
local Trial  = require("core.Trial")
local config = require("trial.dsr.config")

local dsrTrial = Trial.create({
    id     = "dsr",
    zoneId = config.zoneId,
    eventPrefix = "Incha_DSR",
    bosses = config.bosses,
    bridge = Panel.bridge,
    alerts = Panel.alerts,
})

return dsrTrial
