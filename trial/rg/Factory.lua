local Trial = require("core.Trial")
local config = require("trial.rg.config")

local rgTrial = Trial.create({
    id = "rg",
    zoneId = config.zoneId,
    eventPrefix = "Incha_RG",
    bosses = config.bosses,
})

return rgTrial
