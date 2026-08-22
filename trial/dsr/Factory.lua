local Trial = require("core.Trial")
local config = require("trial.dsr.config")

local dsrTrial = Trial.create({
    id = "dsr",
    zoneId = config.zoneId,
    eventPrefix = "Incha_DSR",
    bosses = config.bosses,
})

return dsrTrial
