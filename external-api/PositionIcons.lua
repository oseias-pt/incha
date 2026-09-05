--- external-api/PositionIcons.lua  -  dependency-injected gateway for
--- OdySupportIcons world-space position-icon calls.
---
--- All methods are silent no-ops until configure() is called with the real
--- OSI global (or a test stub).
---
--- Bootstrap (incha.lua OnAddOnLoaded):
---   require("external-api.PositionIcons").configure(OSI)
---
--- Usage:
---   local PositionIcons = require("external-api.PositionIcons")
---   local handle = PositionIcons.create(x, y, z, texture, size, color)
---   PositionIcons.discard(handle)
---   PositionIcons.update(handle, texture, color)
---   PositionIcons.discardAll(iconTable)
---   if PositionIcons.isAvailable() then ... end

local PositionIcons = {}

local _impl = nil

--- Inject the real OSI global (or a test stub).
--- Called once from OnAddOnLoaded after ESO globals are available.
function PositionIcons.configure(impl)
    _impl = impl
end

--- Returns true when the implementation is configured and supports position icons.
function PositionIcons.isAvailable()
    return _impl ~= nil and _impl.CreatePositionIcon ~= nil
end

--- Create a world-space position icon.  Returns an icon handle, or nil when
--- not configured.
function PositionIcons.create(x, y, z, texture, size, color)
    if not PositionIcons.isAvailable() then return nil end
    return _impl.CreatePositionIcon(x, y, z, texture, size, color)
end

--- Discard a single icon handle.  Silent no-op on nil handle or when not
--- configured.
function PositionIcons.discard(handle)
    if _impl and handle and _impl.DiscardPositionIcon then
        _impl.DiscardPositionIcon(handle)
    end
end

--- Update the texture and color of an existing icon.
--- Silent no-op on nil handle or when not configured.
function PositionIcons.update(handle, texture, color)
    if _impl and handle and _impl.UpdateIconData then
        _impl.UpdateIconData(handle, texture, nil, color)
    end
end

--- Discard all icon handles stored in a table.
--- Silent no-op when not configured or iconTable is falsy.
function PositionIcons.discardAll(iconTable)
    if not (iconTable and _impl and _impl.DiscardPositionIcon) then return end
    for _, icon in pairs(iconTable) do _impl.DiscardPositionIcon(icon) end
end

package.loaded["external-api.PositionIcons"] = PositionIcons
return PositionIcons
