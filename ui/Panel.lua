--- Default overlay panel — implements the AlertSink handler vocabulary
--- using plain WINDOW_MANAGER controls owned entirely by Incha.
---
--- Design rules (from Phase 0 analysis):
---   - Controls are built ONCE on first enable, never per event.
---   - All steady-state updates are :SetText() / :SetHidden() only.
---   - No per-tick allocations anywhere in this file.
---
--- Used by rg/dsr automatically. KA keeps LegacyUI as its bridge for now.

local Settings = require("core.Settings")

local Panel = {}

-- Control bundle — nil until first build(), populated exactly once.
local ctrl = nil

-- Panel dimensions (points, scales with ctrl.panel:SetScale).
local W, H = 320, 90

local function applyPosition(panel)
    local sv = Settings.get().overlay
    if sv.offsetX >= 0 then
        -- User has previously dragged the panel — restore that position.
        panel:ClearAnchors()
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, sv.offsetX, sv.offsetY)
    else
        -- First run: center near the top of the screen.
        panel:ClearAnchors()
        local screenW = GuiRoot:GetWidth()
        panel:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, (screenW - W) / 2, 150)
    end
end

local function build()
    if ctrl then return end

    local sv = Settings.get().overlay

    -- Outer container — the draggable root.
    local panel = WINDOW_MANAGER:CreateControl("InchPanel", GuiRoot, CT_CONTROL)
    panel:SetDimensions(W, H)
    panel:SetClampedToScreen(true)
    panel:SetMouseEnabled(not sv.locked)
    panel:SetMovable(not sv.locked)
    panel:SetHidden(true)
    panel:SetScale(sv.scale)
    applyPosition(panel)

    panel:SetHandler("OnMoveStop", function(c)
        local s = Settings.get().overlay
        s.offsetX = c:GetLeft()
        s.offsetY = c:GetTop()
        -- Re-anchor so scale changes don't drift the saved position.
        applyPosition(c)
    end)

    -- Semi-transparent dark background.
    local bg = WINDOW_MANAGER:CreateControl(nil, panel, CT_BACKDROP)
    bg:SetAnchorFill()
    bg:SetCenterColor(0.04, 0.04, 0.04, 0.82)
    bg:SetEdgeColor(0.35, 0.35, 0.35, 0.9)

    -- Header — boss name / HM status. Small, gold.
    local header = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
    header:SetFont("ZoFontGameSmall")
    header:SetColor(1, 0.82, 0.22, 1)
    header:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    header:SetAnchor(TOP, panel, TOP, 0, 8)
    header:SetDimensions(W - 16, 18)
    header:SetText("")

    -- Action — the prominent mid-fight call-out. Larger, orange.
    local action = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
    action:SetFont("ZoFontGameBold")
    action:SetColor(1, 0.42, 0.08, 1)
    action:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    action:SetAnchor(CENTER, panel, CENTER, 0, 4)
    action:SetDimensions(W - 16, 30)
    action:SetText("")

    -- Progress — secondary info line. Small, grey.
    local progress = WINDOW_MANAGER:CreateControl(nil, panel, CT_LABEL)
    progress:SetFont("ZoFontGameSmall")
    progress:SetColor(0.75, 0.75, 0.75, 1)
    progress:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    progress:SetAnchor(BOTTOM, panel, BOTTOM, 0, -8)
    progress:SetDimensions(W - 16, 18)
    progress:SetText("")

    ctrl = { panel = panel, header = header, action = action, progress = progress }
end

-- ── AlertSink handler table ────────────────────────────────────────────────
-- Implements the same vocabulary as LegacyUI.alerts so Trial.create can
-- accept either without knowing which one it got.

Panel.alerts = {
    header = function(text)
        if ctrl then
            ctrl.header:SetText(text or "")
            ctrl.panel:SetHidden(false)
        end
    end,

    action = function(text)
        if ctrl then
            ctrl.action:SetText(text or "")
            ctrl.panel:SetHidden(false)
        end
    end,

    progress = function(text)
        if ctrl then
            ctrl.progress:SetText(text or "")
            ctrl.panel:SetHidden(false)
        end
    end,

    hideAction = function()
        if ctrl then
            ctrl.action:SetText("")
        end
    end,

    clear = function()
        if not ctrl then return end
        ctrl.header:SetText("")
        ctrl.action:SetText("")
        ctrl.progress:SetText("")
        ctrl.panel:SetHidden(true)
    end,
}

-- ── Bridge lifecycle table ─────────────────────────────────────────────────
-- Implements the same interface as LegacyUI so Trial.create can accept either.

Panel.bridge = {
    onEnable = function()
        build()  -- no-op after first call; safe to call on every zone enter
    end,

    onDisable = function()
        if not ctrl then return end
        ctrl.header:SetText("")
        ctrl.action:SetText("")
        ctrl.progress:SetText("")
        ctrl.panel:SetHidden(true)
    end,

    onBossExit = function()
        if ctrl then ctrl.panel:SetHidden(true) end
    end,
}

-- ── Settings refresh ───────────────────────────────────────────────────────
-- Call after changing overlay settings (lock, scale) so live controls
-- reflect the new values immediately without a reload.

function Panel.refresh()
    if not ctrl then return end
    local sv = Settings.get().overlay
    ctrl.panel:SetMouseEnabled(not sv.locked)
    ctrl.panel:SetMovable(not sv.locked)
    ctrl.panel:SetScale(sv.scale)
    applyPosition(ctrl.panel)
end

return Panel
