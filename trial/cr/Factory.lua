local Trial         = require("core.Trial")
local Panel         = require("ui.Panel")

local EventDispatcher = require("core.EventDispatcher")
local ZmajaEncounter = require("trial.cr.boss.ZmajaEncounter")

local crTrial = Trial.create({
    id              = "cr",
    zoneId          = 1051,
    eventPrefix     = ADDON_PREFIX .. "CR",
    bosses          = { ZmajaEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = EventDispatcher.abilityIdsFor,
    onCombatEventFiltered   = EventDispatcher.onCombatEventFiltered,
    onEffectChangedFiltered = EventDispatcher.onEffectChangedFiltered,
    onDiedCombatEvent       = EventDispatcher.onDiedCombatEvent,
})

package.loaded["trial.cr.Factory"] = crTrial
return crTrial
