local Trial  = require("core.Trial")
local Panel  = require("ui.Panel")

local Oaxiltso = require("trial.rg.boss.Oaxiltso")
local Bahsei   = require("trial.rg.boss.Bahsei")
local Xalvakka = require("trial.rg.boss.Xalvakka")

local rgTrial = Trial.create({
    id          = "rg",
    zoneId      = 1263,
    eventPrefix = ADDON_PREFIX .. "RG",
    bosses      = { Oaxiltso, Bahsei, Xalvakka },
    bridge      = Panel.bridge,
    alerts      = Panel.alerts,
})

package.loaded["trial.rg.Factory"] = rgTrial
return rgTrial
