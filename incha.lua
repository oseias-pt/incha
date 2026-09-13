-- ADDON_NAME and friends are defined in bootstrap.lua (the first file loaded).

local Settings    = require("core.Settings")
local ZoneManager = require("core.ZoneManager")

-- External-API gateways: inject real implementations once ESO globals are live.
-- configure() calls live in OnAddOnLoaded (below) where CombatAlerts and OSI
-- are guaranteed to be available.
local ExtCA = require("external-api.CombatAlerts")
local ExtMI = require("external-api.MechanicIcons")
local ExtPI = require("external-api.PositionIcons")

-- Pre-load ui modules at startup so they are never captured as part of a
-- trial's dependency set  -  the panel must outlive any single trial.
require("ui.Panel")
local Menu  = require("ui.Menu")

-- Every trial is resident for the whole session.  incha.txt executes each
-- file at load time and each Factory builds its Trial at file scope, so the
-- boss classes and routing tables are already reachable before this runs;
-- ZoneManager just decides which Trial is enabled for the current zone.
--
-- Each registration is wrapped in pcall so a single broken Factory (missing
-- file in incha.txt, load-time error, typo'd module path) only loses that
-- trial; the remaining trials still register and function normally.  Without
-- pcall, our custom require() raises at file scope and every trial listed
-- after the failing line is silently never registered (issue #259).
local _trials = {
    { 1196, "trial.ka.Factory",  "ka"  },
    { 1121, "trial.ss.Factory",  "ss"  },
    { 1263, "trial.rg.Factory",  "rg"  },
    { 1344, "trial.dsr.Factory", "dsr" },
    { 1000, "trial.as.Factory",  "as"  },
    { 1051, "trial.cr.Factory",  "cr"  },
    { 1427, "trial.se.Factory",  "se"  },
    { 1478, "trial.lc.Factory",  "lc"  },
    { 1548, "trial.oc.Factory",  "oc"  },
}
local Log = require("lib.Log")
for _, t in ipairs(_trials) do
    local zoneId, mod, id = t[1], t[2], t[3]
    local ok, factory = pcall(require, mod)
    if ok then
        ZoneManager.registerTrial(zoneId, factory, id)
    else
        Log.always("trial %s failed to load: %s", id, tostring(factory))
    end
end

local function OnAddOnLoaded(event, addonName)
    if addonName ~= ADDON_NAME then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED)

    -- Settings must come first  -  other systems (Log, UI) read from it.
    Settings.init()

    -- Wire external-API gateways to real ESO globals now that they are live.
    -- CombatAlerts and OSI are optional third-party addons: passing nil here
    -- leaves the gateway configured as a no-op, which is the safe default.
    ExtCA.configure(CombatAlerts)
    ExtMI.configure(OSI)
    ExtPI.configure(OSI)

    Menu.init()

    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_PLAYER_ACTIVATED, ZoneManager.onZoneChanged)
    EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ZONE_CHANGED, ZoneManager.onZoneChanged)

    ZoneManager.onZoneChanged()

    -- Gate the version banner behind the debug flag so player chat stays clean
    -- by default.  Enable via Settings → debug or ADDON_PREFIX .. ".debug = true".
    Log.debug("%s v%s loaded  -  %s for commands", ADDON_TAG, ADDON_VERSION, ADDON_SLASH)
end

EVENT_MANAGER:RegisterForEvent(ADDON_NAME, EVENT_ADD_ON_LOADED, OnAddOnLoaded)
