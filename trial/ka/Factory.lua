local Trial   = require("core.Trial")
local Panel   = require("ui.Panel")

local EventDispatcher = require("core.EventDispatcher")
local Yandir   = require("trial.ka.boss.Yandir")
local Vrol     = require("trial.ka.boss.Vrol")
local Falgravn = require("trial.ka.boss.Falgravn")

local kaTrial = Trial.create({
    id              = "ka",
    zoneId          = 1196,
    eventPrefix     = ADDON_PREFIX .. "KA",
    bosses          = { Yandir, Vrol, Falgravn },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = EventDispatcher.abilityIdsFor,
    onCombatEventFiltered   = EventDispatcher.onCombatEventFiltered,
    onEffectChangedFiltered = EventDispatcher.onEffectChangedFiltered,
    onDiedCombatEvent       = EventDispatcher.onDiedCombatEvent,
})

package.loaded["trial.ka.Factory"] = kaTrial
return kaTrial
