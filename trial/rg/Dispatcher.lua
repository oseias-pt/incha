local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = {
    zoneId = 1263,
}

-- Names of every module pulled in by loading the Factory this time around
-- (Factory itself, its config, any bosses/bridges it requires, etc.),
-- captured automatically so nothing has to be tracked by hand. Cleared on
-- disable so the whole trial's code becomes eligible for GC when the
-- player leaves the zone.
local loadedModules = nil
local activeTrial   = nil

function Dispatcher.enable()
    activeTrial, loadedModules = ModuleLoader.loadScoped("trial.rg.Factory")
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
