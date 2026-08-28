-- ESO does not expose require() or the package library.  This file MUST be
-- the very first entry in incha.txt.
--
-- Every module file registers itself immediately before its return statement:
--     package.loaded["module.name"] = ExportVar
--     return ExportVar
-- so that later require() calls resolve without file I/O.

package = { loaded = {} }

function require(name)
    local mod = package.loaded[name]
    if mod ~= nil then return mod end
    error("[Incha] require('" .. name .. "'): module not registered. "
        .. "Ensure it appears before its first caller in incha.txt.", 2)
end
