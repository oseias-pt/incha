local Trial   = require("core.Trial")
local Panel   = require("ui.Panel")

local EventDispatcher = require("core.EventDispatcher")
local Lokke  = require("trial.ss.boss.Lokke")
local Yolna  = require("trial.ss.boss.Yolna")
local Nahvii = require("trial.ss.boss.Nahvii")

local ssTrial = Trial.create({
    id              = "ss",
    zoneId          = 1121,
    eventPrefix     = ADDON_PREFIX .. "SS",
    bosses          = { Lokke, Yolna, Nahvii },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = EventDispatcher.abilityIdsFor,
    onCombatEventFiltered   = EventDispatcher.onCombatEventFiltered,
    onEffectChangedFiltered = EventDispatcher.onEffectChangedFiltered,
    onDiedCombatEvent       = EventDispatcher.onDiedCombatEvent,
})

package.loaded["trial.ss.Factory"] = ssTrial
return ssTrial
