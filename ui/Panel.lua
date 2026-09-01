--- Default overlay panel  -  implements the AlertSink handler vocabulary
--- using controls defined in ui/Panel.xml.
---
--- Design rules (from Phase 0 analysis):
---   - Controls are built ONCE on first enable, never per event.
---   - All steady-state updates are :SetText() / :SetHidden() only.
---   - No per-tick allocations anywhere in this file.
---
--- Alert vocabulary:
---   header(text)     -  boss name / HM status, small gold line at top
---   info(n, text)    -  timer countdown lines (grey, small)
---   action(text)     -  prominent mid-fight call-out (orange, bold)
---   hideAction()     -  clears action without hiding panel
---   clear()          -  clears all text and hides the panel
---
--- Used by ka/rg/dsr.

local BridgeBase = require("core.Bridge")
local Settings   = require("core.Settings")

local Panel = {}

-- Control bundle  -  nil until first build(), populated exactly once.
local ctrl = nil

-- Track each HUD scene's state separately to avoid callback-order races.
-- When chat/inventory closes, ESO fires both "hud → showing" and
-- "hudui → hiding" in the same frame.  The one that fires last overwrites
-- the shared variable, so the panel could end up hidden while the HUD is
-- fully visible.  OR logic avoids the race: the panel is live whenever
-- either scene is in its active half ("showing" or "shown").
local hudState   = "showing"   -- most recent state of the "hud" scene
local hudUiState = "showing"   -- most recent state of the "hudui" scene

-- When true the panel is pinned visible regardless of HUD scene state.
-- Set by Panel.setPreviewMode(true) when a preview command fires;
-- cleared by Panel.setPreviewMode(false) on Preview.clear().
-- Prevents rapid LAM-menu / settings-menu scene cycling from flickering
-- the panel away before the player has a chance to see it.
local previewMode = false

-- Panel dimensions (points, scales with ctrl.panel:SetScale).
-- Layout: header(26) at y=10 | 10 info lines(20 each) from y=42 | action(36) at bottom.
local INFO_LINE_COUNT = 10
local W, H = 360, 300

-- Show or hide the panel based on two independent gates:
--   ctrl.active    -  trial/boss content should be on screen
--   hudVisible     -  the hud/hudui scene allows it
-- Call this instead of SetHidden directly so both gates stay in sync.
-- ESO scene lifecycle: "showing" → "shown" → "hiding" → "hidden".
-- The panel is visible while either HUD scene is in the active half.
local function isActive(state)
    return state == "showing" or state == "shown"
end

local function applyVisibility()
    if not ctrl then return end
    -- previewMode pins the panel on screen regardless of scene state.
    if previewMode then
        ctrl.panel:SetHidden(false)
        return
    end
    local hudVisible = isActive(hudState) or isActive(hudUiState)
    ctrl.panel:SetHidden(not (ctrl.active and hudVisible))
end

local function applyPosition(panel)
    local sv = Settings.get().overlay
    panel:ClearAnchors()
    if sv.offsetX >= 0 then
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.offsetX, sv.offsetY)
    else
        local screenW = GuiRoot:GetWidth()
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, (screenW - W) / 2, 150)
    end
end

-- Clear all panel text and deactivate.
-- Callers must guard with `if not ctrl then return end` before calling.
local function panel_clear()
    ctrl.header:SetText("") ; ctrl.headerText = ""
    ctrl.action:SetText("") ; ctrl.actionText = ""
    for i = 1, INFO_LINE_COUNT do
        ctrl.info[i]:SetText("")
        ctrl.infoText[i] = ""
    end
    ctrl.active = false
    applyVisibility()
end

local function build()
    if ctrl then return end

    -- Controls are defined in ui/Panel.xml; ESO creates them during the
    -- loading sequence before any Lua runs.  Grab the globals by name.
    local panel = InchPanel
    if not panel then
        d("[Incha] ERROR: InchPanel XML control missing — check ui/Panel.xml is in AddOns folder and /reloadui")
        return
    end
    if not InchPanelHeader or not InchPanelAction then
        d("[Incha] ERROR: InchPanel child controls missing (Header/Action nil) — XML may have a parse error")
        return
    end

    -- Belt-and-suspenders: ensure the panel renders above all HUD elements.
    panel:SetDrawLayer(DL_OVERLAY)

    local sv = Settings.get().overlay
    panel:SetMouseEnabled(not sv.locked)
    panel:SetMovable(not sv.locked)
    panel:SetScale(sv.scale)
    applyPosition(panel)

    panel:SetHandler("OnMoveStop", function(c)
        local s = Settings.get().overlay
        s.offsetX = c:GetLeft()
        s.offsetY = c:GetTop()
        applyPosition(c)
    end)

    -- Backdrop colours (BackgroundColor/EdgeColor are invalid ESO XML elements;
    -- set them here so the panel is dark rather than the default white).
    if InchPanelBg then
        InchPanelBg:SetCenterColor(0.04, 0.04, 0.04, 0.82)
        InchPanelBg:SetEdgeColor(0.35, 0.35, 0.35, 0.9)
    end

    -- Apply font, colour, and alignment (XML attributes for these are not
    -- reliably parsed across ESO client versions, so we set them here).
    -- Header: large bold gold — boss name should be immediately readable.
    InchPanelHeader:SetFont("ZoFontGameLargeBold")
    InchPanelHeader:SetColor(1, 0.82, 0.22, 1)
    InchPanelHeader:SetHorizontalAlignment(TEXT_ALIGN_CENTER)

    -- Action: large bold orange — mid-fight call-out must dominate the panel.
    InchPanelAction:SetFont("ZoFontGameLargeBold")
    InchPanelAction:SetColor(1, 0.42, 0.08, 1)
    InchPanelAction:SetHorizontalAlignment(TEXT_ALIGN_CENTER)

    -- Collect info-line references from the XML globals and style them.
    -- Info lines use standard game font — readable but secondary to action.
    local info = {}
    for i = 1, INFO_LINE_COUNT do
        local lbl = _G[string.format("InchPanelInfo%02d", i)]
        if lbl then
            lbl:SetFont("ZoFontGame")
            lbl:SetColor(0.75, 0.75, 0.75, 1)
            lbl:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
        end
        info[i] = lbl
    end

    -- Text caches: last string passed to each SetText call.
    local infoText = {}
    for i = 1, INFO_LINE_COUNT do infoText[i] = "" end

    ctrl = {
        panel      = panel,
        header     = InchPanelHeader,
        info       = info,
        action     = InchPanelAction,
        active     = false,  -- gates applyVisibility()
        infoText   = infoText,
        actionText = "",
        headerText = "",
    }

    -- Hide the panel when neither HUD scene is active (escape menu, loading
    -- screen, etc.) and restore it when either returns to "showing".
    SCENE_MANAGER:GetScene("hud"):RegisterCallback("StateChange", function(_, newState)
        hudState = newState
        applyVisibility()
    end)
    SCENE_MANAGER:GetScene("hudui"):RegisterCallback("StateChange", function(_, newState)
        hudUiState = newState
        applyVisibility()
    end)
end

-- -- AlertSink handler table ------------------------------------------------

Panel.alerts = {
    header = function(text)
        if not ctrl then return end
        local s = text or ""
        if ctrl.headerText ~= s then
            ctrl.headerText = s
            ctrl.header:SetText(s)
        end
        if not ctrl.active then
            ctrl.active = true
            applyVisibility()
        end
    end,

    -- info(n, text)  -  timer countdown for slot n (1-7).
    -- Hot path: called up to 7x per 200 ms onUpdate tick.  Skip SetText when
    -- the string is unchanged (LuaJIT interns all strings, so ~= is a pointer
    -- compare).  Skip applyVisibility when the panel is already active.
    info = function(n, text)
        if not ctrl then return end
        local lbl = ctrl.info[n]
        if not lbl then return end
        local s = text or ""
        if ctrl.infoText[n] ~= s then
            ctrl.infoText[n] = s
            lbl:SetText(s)
        end
        if not ctrl.active then
            ctrl.active = true
            applyVisibility()
        end
    end,

    action = function(text)
        if not ctrl then return end
        local s = text or ""
        if ctrl.actionText ~= s then
            ctrl.actionText = s
            ctrl.action:SetText(s)
        end
        if not ctrl.active then
            ctrl.active = true
            applyVisibility()
        end
    end,

    hideAction = function()
        if not ctrl then return end
        ctrl.action:SetText("")
        -- Clear the diff cache too: action() above compares against ctrl.actionText
        -- and skips SetText when the strings match, so leaving the old text cached
        -- makes the next identical callout a no-op. Mirrors panel_clear().
        ctrl.actionText = ""
        -- leave panel visible  -  info lines may still carry timer data
    end,

    clear = function()
        if not ctrl then return end
        panel_clear()
    end,
}

-- -- Bridge lifecycle table -------------------------------------------------
-- Wrapped with BridgeBase so checkHardmode (and any future hook) falls back
-- to the documented no-op rather than silently being absent.

Panel.bridge = BridgeBase.extend({
    onEnable = function()
        build()  -- no-op after first call; safe on every zone enter
    end,

    onDisable = function()
        if not ctrl then return end
        panel_clear()
    end,

    onBossEnter = function(boss, context)
        if ctrl then
            ctrl.active = true
            applyVisibility()
        end
    end,

    onBossExit = function()
        if not ctrl then return end
        panel_clear()
    end,
    -- checkHardmode: inherited no-op from BridgeBase (Panel has no HM logic)
})

-- -- Preview mode -----------------------------------------------------------
-- Called by ui/Preview.lua.  When enabled the panel ignores HUD scene
-- transitions and stays pinned on screen until explicitly cleared.

function Panel.setPreviewMode(enabled)
    previewMode = enabled
    if ctrl then
        if enabled then
            ctrl.active = true
        end
        applyVisibility()
    end
end

-- -- Settings refresh -------------------------------------------------------

function Panel.refresh()
    if not ctrl then return end
    local sv = Settings.get().overlay
    ctrl.panel:SetMouseEnabled(not sv.locked)
    ctrl.panel:SetMovable(not sv.locked)
    ctrl.panel:SetScale(sv.scale)
    applyPosition(ctrl.panel)
end

package.loaded["ui.Panel"] = Panel
return Panel
