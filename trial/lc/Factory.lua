local Trial             = require("core.Trial")
local Panel             = require("ui.Panel")

local EventDispatcher   = require("core.EventDispatcher")
local RyelazEncounter   = require("trial.lc.boss.RyelazEncounter")
local DarielEncounter   = require("trial.lc.boss.DarielEncounter")
local OrphicEncounter   = require("trial.lc.boss.OrphicEncounter")
local XynizataEncounter = require("trial.lc.boss.XynizataEncounter")
local XorynEncounter    = require("trial.lc.boss.XorynEncounter")

local lcTrial = Trial.create({
    id              = "lc",
    zoneId          = 1478,
    eventPrefix     = ADDON_PREFIX .. "LC",
    bosses          = { RyelazEncounter, DarielEncounter, OrphicEncounter,
                        XynizataEncounter, XorynEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    abilityIdsFor           = EventDispatcher.abilityIdsFor,
    onCombatEventFiltered   = EventDispatcher.onCombatEventFiltered,
    onEffectChangedFiltered = EventDispatcher.onEffectChangedFiltered,
    onDiedCombatEvent       = EventDispatcher.onDiedCombatEvent,
})

package.loaded["trial.lc.Factory"] = lcTrial
return lcTrial
