local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = { zoneId = 1478 }

local loadedModules = nil

function Dispatcher.enable()
    local trial
    trial, loadedModules = ModuleLoader.loadScoped("trial.lc.Factory")
    trial:enable()
end

function Dispatcher.disable()
    local factory = package.loaded["trial.lc.Factory"]
    if factory then factory:disable() end
    if loadedModules then
        ModuleLoader.unload(loadedModules)
        loadedModules = nil
    end
end

return Dispatcher
