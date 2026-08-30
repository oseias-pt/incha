--- lib/CA.lua  -  thin optional-dependency wrappers for CombatAlerts.
---
--- CombatAlerts (and its Extended variant) are optional third-party addons.
--- Every call in Incha should be guarded so it silently no-ops when the addon
--- is not installed.  This module centralises those guards so individual boss
--- and common files don't each repeat them.
---
--- Usage (at top of any boss or common file):
---   local CA = require("lib.CA")
---   CA.alertCast(abilityId, unitName, duration, colorTable)
---   CA.alert(id, label, color, sound, duration)
---   CA.castAlertsStop(castId)
---   CA.castAlertsStart(castId, label, dur, pauseDur, colorTable, actionTable)
---   CA.border(active, duration, color)
---
--- All functions are silent no-ops when CombatAlerts is not installed.

local CA = {}

function CA.alertCast(...)
    if CombatAlerts then return CombatAlerts.AlertCast(...) end
end

function CA.alert(...)
    if CombatAlerts then return CombatAlerts.Alert(...) end
end

--- Stop a cast bar by its cast ID.
--- Guards against nil id  -  callers can pass the stored id directly without
--- checking it first.
function CA.castAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

function CA.castAlertsStart(...)
    if CombatAlerts then return CombatAlerts.CastAlertsStart(...) end
end

--- Show or hide the screen-edge danger border.
--- @param active boolean       -  true = show, false = hide
--- @param dur    number        -  duration in ms
--- @param color  table|string  -  {r, g, b, a} colour table, or a named-colour
---                              string accepted by CombatAlerts (e.g. "yellow",
---                              "blue", "red", "green").
function CA.border(active, dur, color)
    if CombatAlerts then CombatAlerts.AlertBorder(active, dur, color) end
end

package.loaded["lib.CA"] = CA
return CA
