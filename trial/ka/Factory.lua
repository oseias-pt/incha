local Trial   = require("core.Trial")
local Panel   = require("ui.Panel")

local CombatHandler = require("core.CombatHandler")
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
    abilityIdsFor           = CombatHandler.abilityIdsFor,
    onCombatEventFiltered   = CombatHandler.onCombatEventFiltered,
    onEffectChangedFiltered = CombatHandler.onEffectChangedFiltered,
    onDiedCombatEvent       = CombatHandler.onDiedCombatEvent,
    onLegacyCombatEvent     = CombatHandler.onLegacyCombatEvent,
})

package.loaded["trial.ka.Factory"] = kaTrial
return kaTrial
