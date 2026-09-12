--- ui/DebugPanel.lua  —  clickable replay panel for in-trial /ip testing.
---
--- Open/close with:  /incha dp   or   /idp
---
--- Boss tabs across the top let you pick which boss to inspect.
--- Ability buttons below inject fake log lines via Playback and print the
--- result to chat so you can confirm the alert fired.

local EventDispatcher = require("core.EventDispatcher")
local ZoneManager     = require("core.ZoneManager")

local DP = {}

-- ── Layout constants ───────────────────────────────────────────────────────
local WIN_W    = 340
local WIN_H    = 460
local BTN_H    = 26
local BTN_PAD  = 3
local TAB_H    = 24
local TITLE_H  = 30     -- title bar + a little breathing room
local TAB_ROW_H = TAB_H + 6
local SCROLL_S = BTN_H + BTN_PAD

-- ── Fake-line field stubs ──────────────────────────────────────────────────
local FAKE_SRC  = 34218181
local FAKE_UNIT = 48707525

-- ── Ability row builder ────────────────────────────────────────────────────
--- Returns a sorted list of { id, line, label } from one boss class.
local function abilityRows(bossClass)
    local rows = {}
    if not bossClass.events then return rows end
    local e = bossClass.events

    for id in pairs(e.beginCast and e.beginCast.instant or {}) do
        rows[#rows + 1] = {
            id    = id,
            line  = ("0,BEGIN_CAST,0,F,%d,%d,0"):format(FAKE_SRC, id),
            label = ("[%d] %s  (instant)"):format(id, GetAbilityName(id) or ""),
        }
    end
    for id in pairs(e.beginCast and e.beginCast.started or {}) do
        rows[#rows + 1] = {
            id    = id,
            line  = ("0,BEGIN_CAST,2000,F,%d,%d,0"):format(FAKE_SRC, id),
            label = ("[%d] %s  (cast)"):format(id, GetAbilityName(id) or ""),
        }
    end
    for id in pairs(e.combatEvent and e.combatEvent.other or {}) do
        rows[#rows + 1] = {
            id    = id,
            line  = ("0,COMBAT_EVENT,EFFECT_GAINED,NONE,0,0,0,0,%d,%d"):format(id, FAKE_SRC),
            label = ("[%d] %s  (other)"):format(id, GetAbilityName(id) or ""),
        }
    end
    for id in pairs(e.effectChanged and e.effectChanged.gained or {}) do
        rows[#rows + 1] = {
            id    = id,
            line  = ("0,EFFECT_CHANGED,GAINED,1,%d,%d,%d"):format(FAKE_SRC, id, FAKE_UNIT),
            label = ("[%d] %s  (effect GAINED)"):format(id, GetAbilityName(id) or ""),
        }
    end
    for id in pairs(e.effectChanged and e.effectChanged.faded or {}) do
        rows[#rows + 1] = {
            id    = id,
            line  = ("0,EFFECT_CHANGED,FADED,1,%d,%d,%d"):format(FAKE_SRC, id, FAKE_UNIT),
            label = ("[%d] %s  (effect FADED)"):format(id, GetAbilityName(id) or ""),
        }
    end

    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

-- ── Window state ───────────────────────────────────────────────────────────
local win
local btnPool    = {}   -- ability buttons (reusable)
local tabPool    = {}   -- boss tab buttons (reusable)
local items      = {}   -- current ability rows for selected boss
local bossList   = {}   -- { key, bossClass } for current trial
local selectedIdx = 0
local scrollY    = 0

local function contH()
    return WIN_H - TITLE_H - TAB_ROW_H - 6
end

local function maxScroll()
    return math.max(0, #items * (BTN_H + BTN_PAD) - contH())
end

local function layoutAbilities()
    local h = contH()
    for i, item in ipairs(items) do
        local btn = btnPool[i]
        if not btn then break end
        local y = (i - 1) * (BTN_H + BTN_PAD) - scrollY
        btn:ClearAnchors()
        btn:SetAnchor(TOPLEFT, win.cont, TOPLEFT, 2, y)
        btn:SetHidden(y + BTN_H < 0 or y > h)
        btn:SetText(item.label)
    end
    for i = #items + 1, #btnPool do
        btnPool[i]:SetHidden(true)
    end
end

local function ensureAbilityPool(n)
    local wm = WINDOW_MANAGER
    for i = #btnPool + 1, n do
        local btn = wm:CreateControl("InchDebugBtn" .. i, win.cont, CT_BUTTON)
        btn:SetDimensions(WIN_W - 18, BTN_H)
        btn:SetFont("ZoFontGameSmall")
        local lbl = btn:GetLabelControl()
        if lbl then lbl:SetHorizontalAlignment(TEXT_ALIGN_LEFT) end
        btn:SetNormalFontColor(0.85, 0.92, 1, 1)
        btn:SetMouseOverFontColor(1, 0.95, 0.4, 1)
        local idx = i
        btn:SetHandler("OnClicked", function()
            local item = items[idx]
            if not item then return end
            local pb = package.loaded["lib.Playback"]
            if pb then
                local res = pb.injectLine(item.line)
                CHAT_SYSTEM:AddMessage("|cAABBFF[Incha]|r " .. tostring(res))
            end
        end)
        btnPool[#btnPool + 1] = btn
    end
end

-- ── Boss tab selection ─────────────────────────────────────────────────────
local function applyTabHighlight(activeIdx)
    for i, tab in ipairs(tabPool) do
        if i <= #bossList then
            if i == activeIdx then
                tab:SetNormalFontColor(1, 0.95, 0.35, 1)
            else
                tab:SetNormalFontColor(0.55, 0.65, 0.85, 1)
            end
        end
    end
end

local function selectBoss(idx)
    selectedIdx = idx
    scrollY = 0
    applyTabHighlight(idx)

    local entry = bossList[idx]
    if entry then
        win.titleLbl:SetText("Incha Debug — " .. (entry.key or "?"))
        items = abilityRows(entry.bossClass)
    else
        win.titleLbl:SetText("Incha Debug")
        items = {}
    end

    ensureAbilityPool(#items)
    layoutAbilities()
end

-- ── Full rebuild (trial changed or panel opened) ───────────────────────────
local function layoutTabs()
    if #bossList == 0 then return end
    local tabW = math.floor((WIN_W - 8) / #bossList)
    local wm = WINDOW_MANAGER

    for i, entry in ipairs(bossList) do
        local tab = tabPool[i]
        if not tab then
            tab = wm:CreateControl("InchDebugTab" .. i, win.tabRow, CT_BUTTON)
            tab:SetHeight(TAB_H)
            tab:SetFont("ZoFontGameSmall")
            local lbl = tab:GetLabelControl()
            if lbl then lbl:SetHorizontalAlignment(TEXT_ALIGN_CENTER) end
            tab:SetMouseOverFontColor(1, 0.95, 0.4, 1)
            local capturedI = i
            tab:SetHandler("OnClicked", function() selectBoss(capturedI) end)
            tabPool[i] = tab
        end
        tab:SetWidth(tabW - 2)
        tab:SetText(entry.key)
        tab:ClearAnchors()
        tab:SetAnchor(TOPLEFT, win.tabRow, TOPLEFT, 2 + (i - 1) * tabW, 1)
        tab:SetHidden(false)
    end
    -- hide leftover tabs from a previous trial with more bosses
    for i = #bossList + 1, #tabPool do
        tabPool[i]:SetHidden(true)
    end
end

local function rebuild()
    items     = {}
    bossList  = {}
    scrollY   = 0

    local trial = ZoneManager.getActiveTrial()
    if not trial then
        win.titleLbl:SetText("Incha Debug — no trial")
        for _, tab in ipairs(tabPool) do tab:SetHidden(true) end
        layoutAbilities()
        return
    end

    for _, bossClass in ipairs(trial.registry.bosses or {}) do
        bossList[#bossList + 1] = {
            key       = bossClass.key or ("boss" .. #bossList + 1),
            bossClass = bossClass,
        }
    end

    if #bossList == 0 then
        win.titleLbl:SetText("Incha Debug — no bosses registered")
        layoutAbilities()
        return
    end

    layoutTabs()

    -- Auto-select the active boss by key match, fallback to first
    local autoIdx = 1
    local activeBoss = trial:getActiveBoss()
    if activeBoss and activeBoss.key then
        for i, entry in ipairs(bossList) do
            if entry.key == activeBoss.key then
                autoIdx = i
                break
            end
        end
    end

    selectBoss(autoIdx)
end

-- ── Window creation ────────────────────────────────────────────────────────
local function buildWindow()
    local wm = WINDOW_MANAGER

    win = wm:CreateTopLevelWindow("InchDebugPanel")
    win:SetDimensions(WIN_W, WIN_H)
    win:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, 120, 180)
    win:SetMouseEnabled(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:SetHidden(true)

    -- Backdrop
    local bg = wm:CreateControl("InchDebugPanelBg", win, CT_BACKDROP)
    bg:SetAnchorFill(win)
    bg:SetCenterColor(0.04, 0.04, 0.09, 0.94)
    bg:SetEdgeColor(0.30, 0.35, 0.55, 1)
    bg:SetInsets(1, 1, -1, -1)

    -- Title bar (drag handle)
    local tb = wm:CreateControl("InchDebugPanelTB", win, CT_CONTROL)
    tb:SetDimensions(WIN_W, 28)
    tb:SetAnchor(TOPLEFT, win, TOPLEFT, 0, 0)
    tb:SetMouseEnabled(true)
    tb:SetHandler("OnMouseDown", function(_, btn)
        if btn == 1 then win:StartMoving() end
    end)
    tb:SetHandler("OnMouseUp", function() win:StopMovingOrResizing() end)

    local titleLbl = wm:CreateControl("InchDebugPanelTitle", win, CT_LABEL)
    titleLbl:SetAnchor(LEFT, tb, LEFT, 8, 0)
    titleLbl:SetFont("ZoFontGameSmall")
    titleLbl:SetColor(0.65, 0.80, 1, 1)
    titleLbl:SetText("Incha Debug")
    win.titleLbl = titleLbl

    -- Close button
    local closeBtn = wm:CreateControl("InchDebugPanelClose", win, CT_BUTTON)
    closeBtn:SetDimensions(22, 22)
    closeBtn:SetAnchor(TOPRIGHT, win, TOPRIGHT, -2, 3)
    closeBtn:SetFont("ZoFontGame")
    closeBtn:SetText("×")
    closeBtn:SetNormalFontColor(1, 0.4, 0.4, 1)
    closeBtn:SetHandler("OnClicked", function() win:SetHidden(true) end)

    -- Refresh button
    local refBtn = wm:CreateControl("InchDebugPanelRefresh", win, CT_BUTTON)
    refBtn:SetDimensions(56, 20)
    refBtn:SetAnchor(TOPRIGHT, win, TOPRIGHT, -26, 4)
    refBtn:SetFont("ZoFontGameSmall")
    refBtn:SetText("Refresh")
    refBtn:SetNormalFontColor(0.5, 0.9, 0.5, 1)
    refBtn:SetHandler("OnClicked", rebuild)

    -- Boss tab row
    local tabBg = wm:CreateControl("InchDebugPanelTabBg", win, CT_BACKDROP)
    tabBg:SetAnchor(TOPLEFT,     win, TOPLEFT,     0, TITLE_H)
    tabBg:SetAnchor(TOPRIGHT,    win, TOPRIGHT,    0, TITLE_H)
    tabBg:SetHeight(TAB_ROW_H)
    tabBg:SetCenterColor(0.07, 0.07, 0.14, 0.85)
    tabBg:SetEdgeColor(0.25, 0.30, 0.50, 0.8)
    tabBg:SetInsets(1, 1, -1, -1)

    local tabRow = wm:CreateControl("InchDebugPanelTabRow", win, CT_CONTROL)
    tabRow:SetAnchor(TOPLEFT,  win, TOPLEFT,  4, TITLE_H + 3)
    tabRow:SetAnchor(TOPRIGHT, win, TOPRIGHT, -4, TITLE_H + 3)
    tabRow:SetHeight(TAB_H)
    win.tabRow = tabRow

    -- Scrollable ability container (clips children)
    local cont = wm:CreateControl("InchDebugPanelCont", win, CT_CONTROL)
    cont:SetAnchor(TOPLEFT,     win, TOPLEFT,     4, TITLE_H + TAB_ROW_H + 4)
    cont:SetAnchor(BOTTOMRIGHT, win, BOTTOMRIGHT, -4, -4)
    cont:SetMouseEnabled(true)
    cont:SetHandler("OnMouseWheel", function(_, delta)
        scrollY = math.max(0, math.min(maxScroll(), scrollY - delta * SCROLL_S))
        layoutAbilities()
    end)
    win.cont = cont
end

-- ── Public API ─────────────────────────────────────────────────────────────

function DP.toggle()
    if not win then buildWindow() end
    if win:IsHidden() then
        rebuild()
        win:SetHidden(false)
    else
        win:SetHidden(true)
    end
end

package.loaded["ui.DebugPanel"] = DP
return DP
