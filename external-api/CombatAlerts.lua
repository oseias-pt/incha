--- external-api/CombatAlerts.lua  -  dependency-injected gateway for CombatAlerts.
---
--- Replaces lib/CA.lua.  All methods are silent no-ops until configure() is
--- called with the real CombatAlerts global (or a test stub).
---
--- Bootstrap (incha.lua OnAddOnLoaded):
---   require("external-api.CombatAlerts").configure(CombatAlerts)
---
--- Usage (at top of any boss or common file):
---   local CA = require("external-api.CombatAlerts")
---   CA.alert(id, label, color, sound, duration)
---   CA.alertCast(abilityId, label, duration, colorTable)
---   CA.castAlertsStop(castId)
---   CA.castAlertsStart(castId, label, dur, pauseDur, colorTable, actionTable)
---   CA.border(active, duration, color)

local CA = {}

local _impl = nil

--- Inject the real CombatAlerts global (or a test stub).
--- Called once from OnAddOnLoaded after ESO globals are available.
function CA.configure(impl)
    _impl = impl
end

function CA.alertCast(...)
    if _impl then return _impl.AlertCast(...) end
end

function CA.alert(...)
    if _impl then return _impl.Alert(...) end
end

--- Stop a cast bar by its cast ID.
--- Guards against nil id  -  callers can pass the stored id directly without
--- checking it first.
function CA.castAlertsStop(id)
    if _impl and id then _impl.CastAlertsStop(id) end
end

function CA.castAlertsStart(...)
    if _impl then return _impl.CastAlertsStart(...) end
end

--- Show or hide the screen-edge danger border.
--- @param active boolean       -  true = show, false = hide
--- @param dur    number        -  duration in ms
--- @param color  table|string  -  {r, g, b, a} colour table, or a named-colour
---                              string accepted by CombatAlerts (e.g. "yellow",
---                              "blue", "red", "green").
function CA.border(active, dur, color)
    if _impl then _impl.AlertBorder(active, dur, color) end
end

package.loaded["external-api.CombatAlerts"] = CA
return CA
