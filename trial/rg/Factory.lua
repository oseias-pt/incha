local Panel  = require("ui.Panel")   -- already in package.loaded (pre-loaded by incha.lua)
local Trial  = require("core.Trial")
local config = require("trial.rg.config")

local rgTrial = Trial.create({
    id     = "rg",
    zoneId = config.zoneId,
    eventPrefix = "Incha_RG",
    bosses = config.bosses,
    bridge = Panel.bridge,
    alerts = Panel.alerts,
})

return rgTrial
