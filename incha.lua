local ADDON_NAME = "Incha"

local Settings    = require("core.Settings")
local ZoneManager = require("core.ZoneManager")

ZoneManager.registerTrial(1196, require("trial.ka.Dispatcher"))
ZoneManager.registerTrial(1263, require("trial.rg.Dispatcher"))
ZoneManager.registerTrial(1344, require("trial.dsr.Dispatcher"))

local function OnAddOnLoaded(event, addonName)
    if addonName ~= ADDON_NAME then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    -- Settings must come first — other systems (Log, UI) read from it.
    Settings.init()

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, ZoneManager.onZoneChanged)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ZONE_CHANGED, ZoneManager.onZoneChanged)

    ZoneManager.onZoneChanged()
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
