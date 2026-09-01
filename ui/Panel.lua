--- Default overlay panel  -  implements the AlertSink handler vocabulary
--- using controls defined in ui/Panel.xml.
---
--- Design (matches QcellDreadsailReefHelper convention):
---   - No backdrop: transparent TopLevelControl.  Text readable via
---     soft-shadow-thick in the font path.
---   - Two labels per info row: name (left-aligned) and timer (right-aligned).
---     text passed to alerts.info(n, text) is split on ": " into two fields.
---   - All font/colour/alignment set in XML as attributes (confirmed valid
---     in ESO XML parser by the reference addon).
---
--- Alert vocabulary:
---   header(text)      -  boss name / HM status
---   info(n, text)     -  timer line; text format "Mechanic: 12s" → two cols
---   action(text)      -  prominent mid-fight call-out (large, white)
---   hideAction()      -  clears action without hiding panel
---   clear()           -  clears all text and hides the panel

local BridgeBase = require("core.Bridge")
local Settings   = require("core.Settings")

local Panel = {}

-- Control bundle  -  nil until first build(), populated exactly once.
local ctrl = nil

-- Track each HUD scene's state separately to avoid callback-order races.
local hudState   = "showing"
local hudUiState = "showing"

-- When true the panel is pinned visible regardless of HUD scene state.
local previewMode = false

-- Panel dimensions (container size for drag/move hit-testing).
-- Layout: header(34) at y=0 | 10 rows × 28 px from y=38 | action(42) at bottom.
local INFO_LINE_COUNT = 10
local W, H = 320, 380

local function isActive(state)
    return state == "showing" or state == "shown"
end

local function applyVisibility()
    if not ctrl then return end
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

local function panel_clear()
    ctrl.header:SetText("") ; ctrl.headerText = ""
    ctrl.action:SetText("") ; ctrl.actionText = ""
    for i = 1, INFO_LINE_COUNT do
        ctrl.info[i].name:SetText("")
        ctrl.info[i].time:SetText("")
        ctrl.infoText[i] = ""
    end
    ctrl.active = false
    applyVisibility()
end

local function build()
    if ctrl then return end

    local panel = InchPanel
    if not panel then
        d("[Incha] ERROR: InchPanel XML control missing — check ui/Panel.xml is in AddOns folder and /reloadui")
        return
    end
    if not InchPanelHeader or not InchPanelAction then
        d("[Incha] ERROR: InchPanel child controls missing — XML may have a parse error")
        return
    end

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

    -- Collect info-row label pairs from XML globals.
    -- Each row has a Name label (mechanic description) and a Time label (timer).
    local info = {}
    for i = 1, INFO_LINE_COUNT do
        local nameLbl = _G[string.format("InchPanelInfo%02dName", i)]
        local timeLbl = _G[string.format("InchPanelInfo%02dTime", i)]
        info[i] = { name = nameLbl, time = timeLbl }
    end

    local infoText = {}
    for i = 1, INFO_LINE_COUNT do infoText[i] = "" end

    ctrl = {
        panel      = panel,
        header     = InchPanelHeader,
        info       = info,
        action     = InchPanelAction,
        active     = false,
        infoText   = infoText,
        actionText = "",
        headerText = "",
    }

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

    -- info(n, text) — text format: "Mechanic: 12s" is split into two columns.
    -- If no ": " is present the full text goes into the name column.
    -- Hot path: called up to 10x per 200 ms tick.
    info = function(n, text)
        if not ctrl then return end
        local row = ctrl.info[n]
        if not row or not row.name then return end
        local s = text or ""
        if ctrl.infoText[n] == s then return end
        ctrl.infoText[n] = s
        -- Split "Mechanic: 12s" into name and timer halves.
        local mechName, timer = s:match("^(.-)%s*:%s*(.-)%s*$")
        if mechName then
            row.name:SetText(mechName)
            row.time:SetText(timer or "")
        else
            row.name:SetText(s)
            if row.time then row.time:SetText("") end
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

Panel.bridge = BridgeBase.extend({
    onEnable = function()
        build()
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
})

-- -- Preview mode -----------------------------------------------------------

function Panel.setPreviewMode(enabled)
    previewMode = enabled
    if ctrl then
        if enabled then ctrl.active = true end
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
