local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = {
    zoneId = 1121,
}

-- Loads trial.ss.Factory (and all its dependencies) on first zone entry;
-- unloads everything on zone exit so trial code is eligible for GC.
local loadedModules = nil

function Dispatcher.enable()
    local trial
    trial, loadedModules = ModuleLoader.loadScoped("trial.ss.Factory")
    trial:enable()
end

function Dispatcher.disable()
    local factory = package.loaded["trial.ss.Factory"]
    if factory then
        factory:disable()
    end

    if loadedModules then
        ModuleLoader.unload(loadedModules)
        loadedModules = nil
    end
end

return Dispatcher
