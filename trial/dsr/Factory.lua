local Trial  = require("core.Trial")
local Panel  = require("ui.Panel")

local CombatHandler  = require("core.CombatHandler")
local Lylanar        = require("trial.dsr.boss.Lylanar")
local ReefGuardian   = require("trial.dsr.boss.ReefGuardian")
local Taleria        = require("trial.dsr.boss.Taleria")

local dsrTrial = Trial.create({
    id              = "dsr",
    zoneId          = 1344,
    eventPrefix     = ADDON_PREFIX .. "DSR",
    bosses          = { Lylanar, ReefGuardian, Taleria },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

package.loaded["trial.dsr.Factory"] = dsrTrial
return dsrTrial
