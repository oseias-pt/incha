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

-- Self-instability 2D icon: animated when the local player has the debuff.
local SELF_INST_FRAMES   = 40
local SELF_INST_INTERVAL = 50
local SELF_INST_KEY      = "Incha_PanelSelfInstAnim"
local _selfInstFrame     = 0
local _selfInstActive    = false

local function selfInstAnimTick()
    if not InchInstIconTex then return end
    _selfInstFrame = (_selfInstFrame % SELF_INST_FRAMES) + 1
    InchInstIconTex:SetTexture(
        string.format("Incha/resources/instability/frame_%02d.dds", _selfInstFrame))
end

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
    -- Stop the self-instability icon animation if running.
    if _selfInstActive then
        EVENT_MANAGER:UnregisterForUpdate(SELF_INST_KEY)
        _selfInstActive = false
    end
    if InchInstIcon then InchInstIcon:SetHidden(true) end
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

    -- Apply font and colour from Lua — the XML color= attribute is silently
    -- ignored in some ESO client builds, which leaves text black on a
    -- transparent background (invisible).  Lua calls are authoritative.
    local FONT_HDR    = "EsoUI/Common/Fonts/univers67.otf|26|soft-shadow-thick"
    local FONT_INFO   = "EsoUI/Common/Fonts/univers67.otf|20|soft-shadow-thick"
    local FONT_ACTION = "EsoUI/Common/Fonts/univers67.otf|36|soft-shadow-thick"

    InchPanelHeader:SetFont(FONT_HDR)
    InchPanelHeader:SetColor(1.0, 0.843, 0.0, 1.0)      -- FFD700 gold
    InchPanelHeader:SetText("")

    for i = 1, INFO_LINE_COUNT do
        local row = info[i]
        if row.name then
            row.name:SetFont(FONT_INFO)
            row.name:SetColor(0.8, 0.8, 0.8, 1.0)       -- CCCCCC grey
            row.name:SetText("")
        end
        if row.time then
            row.time:SetFont(FONT_INFO)
            row.time:SetColor(1.0, 0.522, 0.0, 1.0)     -- FF8500 orange
            row.time:SetText("")
        end
    end

    InchPanelAction:SetFont(FONT_ACTION)
    InchPanelAction:SetColor(1.0, 1.0, 1.0, 1.0)        -- FFFFFF white
    InchPanelAction:SetText("")

    local infoText = {}
    for i = 1, INFO_LINE_COUNT do infoText[i] = "" end

    if InchInstIcon then
        InchInstIcon:SetDrawLayer(DL_OVERLAY)
    end

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

    -- Show the animated instability icon panel (local player has the debuff).
    selfInstOn = function()
        if not InchInstIcon or not InchInstIconTex then return end
        InchInstIconTex:SetTexture("Incha/resources/instability/frame_01.dds")
        InchInstIcon:SetHidden(false)
        _selfInstFrame = 0
        if not _selfInstActive then
            EVENT_MANAGER:RegisterForUpdate(SELF_INST_KEY, SELF_INST_INTERVAL,
                                            selfInstAnimTick)
            _selfInstActive = true
        end
    end,

    -- Stop and hide the instability icon panel.
    selfInstOff = function()
        if _selfInstActive then
            EVENT_MANAGER:UnregisterForUpdate(SELF_INST_KEY)
            _selfInstActive = false
        end
        if InchInstIcon then InchInstIcon:SetHidden(true) end
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

-- -- Debug -------------------------------------------------------------------

function Panel.debugState()
    if not InchPanel then
        d("[Incha] panel debug: InchPanel global is NIL — XML not loaded")
        return
    end
    local hidden  = InchPanel:IsHidden()
    local x, y    = InchPanel:GetLeft(), InchPanel:GetTop()
    local alpha   = InchPanel:GetAlpha()
    local scaleOk = InchPanel:GetScale()
    d(string.format("[Incha] panel: hidden=%s  pos=(%d,%d)  alpha=%.2f  scale=%.2f",
        tostring(hidden), x, y, alpha, scaleOk))
    if not ctrl then
        d("[Incha] panel: ctrl is NIL — build() did not complete")
    else
        d(string.format("[Incha] panel: ctrl OK  active=%s  previewMode=%s  hud=%s  hudui=%s",
            tostring(ctrl.active), tostring(previewMode), hudState, hudUiState))
        d("[Incha] header text: '" .. (ctrl.header:GetText() or "") .. "'")
        d("[Incha] row1 name:  '" .. (ctrl.info[1].name and ctrl.info[1].name:GetText() or "NIL") .. "'")
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
