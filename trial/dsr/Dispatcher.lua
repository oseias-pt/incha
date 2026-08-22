local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = {
    zoneId = 1344,
}

-- Names of every module pulled in by loading the Factory this time around
-- (Factory itself, its config, any bosses/bridges it requires, etc.),
-- captured automatically so nothing has to be tracked by hand. Cleared on
-- disable so the whole trial's code becomes eligible for GC when the
-- player leaves the zone.
local loadedModules = nil

function Dispatcher.enable()
    local trial
    trial, loadedModules = ModuleLoader.loadScoped("trial.dsr.Factory")
    trial:enable()
end

function Dispatcher.disable()
    local factory = package.loaded["trial.dsr.Factory"]
    if factory then
        factory:disable()
    end

    if loadedModules then
        ModuleLoader.unload(loadedModules)
        loadedModules = nil
    end
end

return Dispatcher
