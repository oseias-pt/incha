local Trial   = require("core.Trial")
local Panel   = require("ui.Panel")

local CombatHandler = require("core.CombatHandler")
local Lokke  = require("trial.ss.boss.Lokke")
local Yolna  = require("trial.ss.boss.Yolna")
local Nahvii = require("trial.ss.boss.Nahvii")

local ssTrial = Trial.create({
    id              = "ss",
    zoneId          = 1121,
    eventPrefix     = "Incha_SS",
    bosses          = { Lokke, Yolna, Nahvii },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

package.loaded["trial.ss.Factory"] = ssTrial
return ssTrial
