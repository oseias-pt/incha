local Trial         = require("core.Trial")
local Panel         = require("ui.Panel")
local CombatHandler = require("core.CombatHandler")
local ZmajaEncounter = require("trial.cr.boss.ZmajaEncounter")

local crTrial = Trial.create({
    id              = "cr",
    zoneId          = 1051,
    eventPrefix     = ADDON_PREFIX .. "CR",
    bosses          = { ZmajaEncounter },
    bridge          = Panel.bridge,
    alerts          = Panel.alerts,
    onCombatEvent   = CombatHandler.onCombatEvent,
    onEffectChanged = CombatHandler.onEffectChanged,
})

package.loaded["trial.cr.Factory"] = crTrial
return crTrial
