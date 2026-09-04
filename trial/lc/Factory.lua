local Trial             = require("core.Trial")
local Panel             = require("ui.Panel")
local CombatHandler     = require("core.CombatHandler")
local LCCommon          = require("trial.lc.LCCommon")
local RyelazEncounter   = require("trial.lc.boss.RyelazEncounter")
local DarielEncounter   = require("trial.lc.boss.DarielEncounter")
local OrphicEncounter   = require("trial.lc.boss.OrphicEncounter")
local XynizataEncounter = require("trial.lc.boss.XynizataEncounter")
local XorynEncounter    = require("trial.lc.boss.XorynEncounter")

RyelazEncounter.common   = LCCommon
DarielEncounter.common   = LCCommon
OrphicEncounter.common   = LCCommon
XynizataEncounter.common = LCCommon
XorynEncounter.common    = LCCommon

local lcTrial = Trial.create({
    id              = "lc",
    zoneId          = 1478,
    eventPrefix     = ADDON_PREFIX .. "LC",
    bosses          = { RyelazEncounter, DarielEncounter, OrphicEncounter,
                        XynizataEncounter, XorynEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = CombatHandler.abilityIdsFor,
    onCombatEventFiltered   = CombatHandler.onCombatEventFiltered,
    onEffectChangedFiltered = CombatHandler.onEffectChangedFiltered,
    onDiedCombatEvent       = CombatHandler.onDiedCombatEvent,
    onLegacyCombatEvent     = CombatHandler.onLegacyCombatEvent,
})

package.loaded["trial.lc.Factory"] = lcTrial
return lcTrial
