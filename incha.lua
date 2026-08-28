local ADDON_NAME = "Incha"

local Settings    = require("core.Settings")
local ZoneManager = require("core.ZoneManager")

-- Pre-load ui modules at startup so ModuleLoader never captures them as
-- part of a trial's dependency set — the panel must outlive any single trial.
local Panel = require("ui.Panel")
local Menu  = require("ui.Menu")

ZoneManager.registerTrial(1196, require("trial.ka.Dispatcher"))
ZoneManager.registerTrial(1121, require("trial.ss.Dispatcher"))
ZoneManager.registerTrial(1263, require("trial.rg.Dispatcher"))
ZoneManager.registerTrial(1344, require("trial.dsr.Dispatcher"))
ZoneManager.registerTrial(1000, require("trial.as.Dispatcher"))
ZoneManager.registerTrial(1051, require("trial.cr.Dispatcher"))
ZoneManager.registerTrial(1427, require("trial.se.Dispatcher"))
ZoneManager.registerTrial(1478, require("trial.lc.Dispatcher"))
ZoneManager.registerTrial(1548, require("trial.oc.Dispatcher"))

-- Fires 3 s after load regardless of addon events — confirms incha.lua executed.
zo_callLater(function()
    d("|cFFD700[Incha]|r probe: incha.lua executed, awaiting EVENT_ADD_ON_LOADED")
end, 3000)

local function OnAddOnLoaded(event, addonName)
    -- Log every firing so we can see the actual addonName value ESO sends.
    d("|cFFD700[Incha]|r OnAddOnLoaded fired: addonName=" .. tostring(addonName))
    if addonName ~= ADDON_NAME then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    -- Settings must come first — other systems (Log, UI) read from it.
    Settings.init()
    Menu.init()

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, ZoneManager.onZoneChanged)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ZONE_CHANGED, ZoneManager.onZoneChanged)

    ZoneManager.onZoneChanged()

    d("|cFFD700[Incha]|r v0.1.0 ready — /incha debug to enable verbose output")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
