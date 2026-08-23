local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = {
    zoneId = 1121,
}

-- Loads trial.ss.Factory (and all its dependencies) on first zone entry;
-- unloads everything on zone exit so trial code is eligible for GC.
local loadedModules = nil
local activeTrial   = nil

function Dispatcher.enable()
    activeTrial, loadedModules = ModuleLoader.loadScoped("trial.ss.Factory")
    activeTrial:enable()
end

function Dispatcher.disable()
    if activeTrial then activeTrial:disable() end
    activeTrial = nil

    if loadedModules then
        ModuleLoader.unload(loadedModules)
        loadedModules = nil
    end
end

return Dispatcher
