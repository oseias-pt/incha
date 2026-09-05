--- external-api/MechanicIcons.lua  -  dependency-injected gateway for
--- OdySupportIcons unit mechanic-icon calls.
---
--- All methods are silent no-ops until configure() is called with the real
--- OSI global (or a test stub).
---
--- Bootstrap (incha.lua OnAddOnLoaded):
---   require("external-api.MechanicIcons").configure(OSI)
---
--- Usage:
---   local MechanicIcons = require("external-api.MechanicIcons")
---   MechanicIcons.set(displayName, texture, color)
---   MechanicIcons.remove(displayName)

local MechanicIcons = {}

local _impl = nil

--- Inject the real OSI global (or a test stub).
--- Called once from OnAddOnLoaded after ESO globals are available.
function MechanicIcons.configure(impl)
    _impl = impl
end

--- Place or update a mechanic icon over a unit's head.
--- Size is derived from OSI.GetIconSize() automatically (BSCHTKA convention:
--- 2 × GetIconSize()).  Falls back to nil if GetIconSize is unavailable.
--- Silent no-op when not configured or displayName is empty.
function MechanicIcons.set(displayName, texture, color)
    if not (_impl and displayName and displayName ~= "") then return end
    local sz = _impl.GetIconSize and (2 * _impl.GetIconSize()) or nil
    _impl.SetMechanicIconForUnit(displayName, texture, sz, color, nil, nil)
end

--- Remove the mechanic icon from a unit's head.
--- Silent no-op when not configured or displayName is empty.
function MechanicIcons.remove(displayName)
    if not (_impl and displayName and displayName ~= "") then return end
    _impl.RemoveMechanicIconForUnit(displayName)
end

package.loaded["external-api.MechanicIcons"] = MechanicIcons
return MechanicIcons
