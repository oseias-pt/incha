local ADDON_NAME = "incha"  -- ESO fires EVENT_ADD_ON_LOADED with the folder name, not ## Title:

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

-- Fires 3 s after load — confirms incha.lua ran all the way through.
zo_callLater(function()
    d("|cFFD700[Incha]|r probe A: incha.lua executed OK")
end, 3000)

local _callbackFiredCount = 0

local function OnAddOnLoaded(event, addonName)
    _callbackFiredCount = _callbackFiredCount + 1
    local n = _callbackFiredCount

    -- Schedule a deferred message so it survives the UI wipe phase.
    zo_callLater(function()
        d("|cFFD700[Incha]|r probe B[" .. n .. "]: callback fired, addonName=" .. tostring(addonName))
    end, 4000 + n * 10)

    if addonName ~= ADDON_NAME then
        return
    end

    -- Matched our addon — schedule a distinct probe for this path.
    zo_callLater(function()
        d("|cFFD700[Incha]|r probe C: matched ADDON_NAME, running init")
    end, 5000)

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    Settings.init()

    zo_callLater(function()
        d("|cFFD700[Incha]|r probe D: Settings.init() done")
    end, 5500)

    Menu.init()

    zo_callLater(function()
        d("|cFFD700[Incha]|r probe E: Menu.init() done — /incha should work")
    end, 6000)

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, ZoneManager.onZoneChanged)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ZONE_CHANGED, ZoneManager.onZoneChanged)

    ZoneManager.onZoneChanged()

    d("|cFFD700[Incha]|r v0.1.0 ready — /incha debug to enable verbose output")
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
