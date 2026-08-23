--- Settings UI entry point.
---
--- Registers an in-game settings panel via LibAddonMenu-2.0 (LAM) when it
--- is present, and always registers /incha as a slash-command fallback.
---
--- LAM panel ID: "InchPanel"
--- Slash command: /incha  (debug | lock | scale <n> | reset)

local Log      = require("lib.Log")
local Panel    = require("ui.Panel")
local Settings = require("core.Settings")

local Menu = {}

local PANEL_ID = "InchPanel"

-- ── LAM panel descriptor ───────────────────────────────────────────────────
local PANEL = {
    type                = "panel",
    name                = "Incha",
    displayName         = "|cFFD700Incha|r",
    author              = "Oseias",
    version             = "0.1.0",
    slashCommand        = "/incha",
    registerForRefresh  = false,
    registerForDefaults = false,
}

-- ── Options schema ─────────────────────────────────────────────────────────
-- Each entry is a LAM control descriptor.  getFunc/setFunc read and write
-- directly into the live Settings table so no extra glue is needed.
-- Keep in sync with the defaults in core/Settings.lua.

local OPTIONS = {
    -- Section: general
    {
        type    = "header",
        name    = "General",
    },
    {
        type     = "checkbox",
        name     = "Debug logging",
        tooltip  = "Print internal state to chat. Leave off in normal play.",
        getFunc  = function() return Settings.get().debug end,
        setFunc  = function(v)
            Settings.get().debug = v
            Log.setEnabled(v)
        end,
    },

    -- Section: overlay
    {
        type = "header",
        name = "Overlay",
    },
    {
        type    = "checkbox",
        name    = "Lock position",
        tooltip = "Prevent the overlay from being dragged.",
        getFunc = function() return Settings.get().overlay.locked end,
        setFunc = function(v)
            Settings.get().overlay.locked = v
            Panel.refresh()
        end,
    },
    {
        type        = "slider",
        name        = "Scale",
        tooltip     = "Resize the overlay panel.",
        min         = 0.5,
        max         = 3.0,
        step        = 0.05,
        decimals    = 2,
        getFunc     = function() return Settings.get().overlay.scale end,
        setFunc     = function(v)
            Settings.get().overlay.scale = v
            Panel.refresh()
        end,
    },

    -- Section: Kyne's Aegis
    {
        type = "header",
        name = "Kyne's Aegis",
    },
    {
        type    = "checkbox",
        name    = "Show boss panel",
        tooltip = "Display boss name and hardmode status on enter.",
        getFunc = function() return Settings.get().trials.ka.showBossUI end,
        setFunc = function(v) Settings.get().trials.ka.showBossUI = v end,
    },
    {
        type    = "checkbox",
        name    = "Show % milestones",
        tooltip = "Show action alerts at key health thresholds (Falgravn etc.)",
        getFunc = function() return Settings.get().trials.ka.showPercent end,
        setFunc = function(v) Settings.get().trials.ka.showPercent = v end,
    },
    {
        type    = "checkbox",
        name    = "Vrol portal icon",
        tooltip = "Show a floor marker when Vrol's portal spawns.",
        getFunc = function() return Settings.get().trials.ka.portalIconVrol end,
        setFunc = function(v) Settings.get().trials.ka.portalIconVrol = v end,
    },

    -- Section: Rockgrove
    {
        type = "header",
        name = "Rockgrove",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        getFunc = function() return Settings.get().trials.rg.enabled end,
        setFunc = function(v) Settings.get().trials.rg.enabled = v end,
    },

    -- Section: Dreadsail Reef
    {
        type = "header",
        name = "Dreadsail Reef",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        getFunc = function() return Settings.get().trials.dsr.enabled end,
        setFunc = function(v) Settings.get().trials.dsr.enabled = v end,
    },

    -- Section: Asylum Sanctorium
    {
        type = "header",
        name = "Asylum Sanctorium",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track Olms timers, Llothis/Felms dormant state, and Protector shield.",
        getFunc = function() return Settings.get().trials.as.enabled end,
        setFunc = function(v) Settings.get().trials.as.enabled = v end,
    },

    -- Section: Cloudrest
    {
        type = "header",
        name = "Cloudrest",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track mini-boss timers (Siroria/Relequen/Galenwe), portal countdown, and Z'Maja mechanics.",
        getFunc = function() return Settings.get().trials.cr.enabled end,
        setFunc = function(v) Settings.get().trials.cr.enabled = v end,
    },

    -- Section: Sanity's Edge
    {
        type = "header",
        name = "Sanity's Edge",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track Yaseyla bomb timers, Chimera despawn/chain lightning, and Ansuul calamity/phase alerts.",
        getFunc = function() return Settings.get().trials.se.enabled end,
        setFunc = function(v) Settings.get().trials.se.enabled = v end,
    },

    -- Section: Lucent Citadel
    {
        type = "header",
        name = "Lucent Citadel",
    },
    {
        type    = "checkbox",
        name    = "Enable",
        tooltip = "Track side assignment (Ryelaz/Zilyesset), Orphic Xoryn jump/cone timers, Xynizata interrupt CDs, and Xoryn current/knot alerts.",
        getFunc = function() return Settings.get().trials.lc.enabled end,
        setFunc = function(v) Settings.get().trials.lc.enabled = v end,
    },
}

-- ── Slash command fallback ────────────────────────────────────────────────

local function printHelp()
    d("|cFFD700[Incha]|r Commands:")
    d("  /incha debug         — toggle debug logging")
    d("  /incha lock          — toggle overlay drag lock")
    d("  /incha scale <n>     — set overlay scale (0.5 – 3.0)")
    d("  /incha reset         — reset overlay to default position")
end

local function handleSlash(text)
    local cmd, arg = (text or ""):lower():match("^%s*(%S*)%s*(.*)")
    local sv = Settings.get()

    if cmd == "debug" then
        sv.debug = not sv.debug
        Log.setEnabled(sv.debug)
        d("|cFFD700[Incha]|r Debug " .. (sv.debug and "|c00FF00ON|r" or "|cFF4444OFF|r"))

    elseif cmd == "lock" then
        sv.overlay.locked = not sv.overlay.locked
        Panel.refresh()
        d("|cFFD700[Incha]|r Overlay " .. (sv.overlay.locked and "locked" or "unlocked"))

    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 3.0 then
            sv.overlay.scale = n
            Panel.refresh()
            d("|cFFD700[Incha]|r Scale → " .. n)
        else
            d("|cFFD700[Incha]|r Usage: /incha scale <0.5 – 3.0>")
        end

    elseif cmd == "reset" then
        sv.overlay.offsetX = -1
        sv.overlay.offsetY = -1
        sv.overlay.scale   = 1.0
        Panel.refresh()
        d("|cFFD700[Incha]|r Overlay position reset")

    else
        printHelp()
    end
end

-- ── Public API ─────────────────────────────────────────────────────────────

function Menu.init()
    -- Always register the slash command — useful even when LAM is present
    -- and essential when it is not installed.
    SLASH_COMMANDS["/incha"] = handleSlash

    -- Wire to LibAddonMenu-2.0 when it is loaded.
    -- incha.txt declares ## OptionalDependsOn: LibAddonMenu-2.0 so ESO
    -- loads LAM before Incha when both are present.
    local LAM = LibAddonMenu2
    if LAM then
        LAM:RegisterAddonPanel(PANEL_ID, PANEL)
        LAM:RegisterOptionControls(PANEL_ID, OPTIONS)
    end
end

Menu.options = OPTIONS

return Menu
