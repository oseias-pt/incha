local Trial  = require("core.Trial")
local Panel  = require("ui.Panel")

local EventDispatcher = require("core.EventDispatcher")
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
    abilityIdsFor           = EventDispatcher.abilityIdsFor,
    onCombatEventFiltered   = EventDispatcher.onCombatEventFiltered,
    onEffectChangedFiltered = EventDispatcher.onEffectChangedFiltered,
    onDiedCombatEvent       = EventDispatcher.onDiedCombatEvent,
})

package.loaded["trial.dsr.Factory"] = dsrTrial
return dsrTrial
