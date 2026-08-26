local ModuleLoader = require("core.ModuleLoader")

local Dispatcher = {
    zoneId = 1196,
}

-- Belt-and-suspenders: all modules that are exclusively private to the KA
-- trial.  loadScoped() already unloads anything it newly loaded, but if one
-- of these was already in package.loaded before the snapshot (e.g. another
-- trial loaded it as a side-effect), it won't appear in the delta.  Listing
-- them here ensures they are always evicted on disable regardless.
local KA_PRIVATE_MODULES = {
    "trial.ka.Factory",
    "trial.ka.boss.Yandir",
    "trial.ka.boss.Vrol",
    "trial.ka.boss.Falgravn",
}

-- Names of every module pulled in by loading the Factory this time around
-- (Factory itself, its config, all boss/bridge modules it requires, etc.),
-- captured automatically so nothing has to be tracked by hand. Cleared on
-- disable so the whole trial's code becomes eligible for GC when the
-- player leaves the zone.
local loadedModules = nil
local activeTrial   = nil

function Dispatcher.enable()
    activeTrial, loadedModules = ModuleLoader.loadScoped("trial.ka.Factory")
    activeTrial:enable()
end

function Dispatcher.disable()
    if activeTrial then activeTrial:disable() end
    activeTrial = nil

    if loadedModules then
        ModuleLoader.unload(loadedModules)
        loadedModules = nil
    end

    -- Explicit eviction of KA-private modules that may have been missed by
    -- the loadScoped delta (e.g. already cached before enable() was called).
    -- Safe to call even if already unloaded — nil-ing a nil key is a no-op.
    ModuleLoader.unload(KA_PRIVATE_MODULES)
end

return Dispatcher
