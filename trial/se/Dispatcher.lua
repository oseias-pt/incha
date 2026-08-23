local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = { zoneId = 1427 }
local loadedModules = nil
local activeTrial   = nil

function Dispatcher.enable()
    activeTrial, loadedModules = ModuleLoader.loadScoped("trial.se.Factory")
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
