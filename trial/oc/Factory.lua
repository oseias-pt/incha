local Trial            = require("core.Trial")
local Panel            = require("ui.Panel")
local CombatHandler    = require("core.CombatHandler")
local JynorahEncounter = require("trial.oc.boss.JynorahEncounter")
local KazpianEncounter = require("trial.oc.boss.KazpianEncounter")
local ShaperEncounter  = require("trial.oc.boss.ShaperEncounter")

local ocTrial = Trial.create({
    id              = "oc",
    zoneId          = 1548,
    eventPrefix     = ADDON_PREFIX .. "OC",
    bosses          = { JynorahEncounter, KazpianEncounter, ShaperEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = CombatHandler.abilityIdsFor,
    onCombatEventFiltered   = CombatHandler.onCombatEventFiltered,
    onEffectChangedFiltered = CombatHandler.onEffectChangedFiltered,
    onDiedCombatEvent       = CombatHandler.onDiedCombatEvent,
    onLegacyCombatEvent     = CombatHandler.onLegacyCombatEvent,
})

package.loaded["trial.oc.Factory"] = ocTrial
return ocTrial
