local ModuleLoader = {}

local function snapshotLoadedKeys()
    local keys = {}
    for name in pairs(package.loaded) do
        keys[name] = true
    end
    return keys
end

--- Requires `moduleName`, capturing every module newly inserted into
--- package.loaded as a side effect (i.e. everything that module and its
--- dependencies pulled in that wasn't already loaded before this call).
--- Modules that were already loaded (shared core/lib code, other active
--- trials, etc.) are correctly excluded, since they're still needed by
--- whoever loaded them first.
---
--- Returns the required module, plus the list of module names to later
--- pass to ModuleLoader.unload() to fully evict this load from the cache.
function ModuleLoader.loadScoped(moduleName)
    local before = snapshotLoadedKeys()

    local mod = require(moduleName)

    local newlyLoaded = {}
    for name in pairs(package.loaded) do
        if not before[name] then
            newlyLoaded[#newlyLoaded + 1] = name
        end
    end

    return mod, newlyLoaded
end

--- Clears package.loaded entries for the given module names, making them
--- eligible for garbage collection (assuming nothing else still holds a
--- reference into them).
function ModuleLoader.unload(moduleNames)
    for _, name in ipairs(moduleNames) do
        package.loaded[name] = nil
    end
end

package.loaded["core.ModuleLoader"] = ModuleLoader
return ModuleLoader
