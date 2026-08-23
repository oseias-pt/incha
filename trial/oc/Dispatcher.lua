local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = { zoneId = 1548 }

local loadedModules = nil

function Dispatcher.enable()
    local trial
    trial, loadedModules = ModuleLoader.loadScoped("trial.oc.Factory")
    trial:enable()
end

function Dispatcher.disable()
    local factory = package.loaded["trial.oc.Factory"]
    if factory then factory:disable() end
    if loadedModules then
        ModuleLoader.unload(loadedModules)
        loadedModules = nil
    end
end

return Dispatcher
