--- ui/DebugPanel.lua — zone-independent /idp debug panel.
---
--- Open/close with:  /incha dp   or   /idp
---
--- Trial selector tabs let you pick any registered trial without being in zone.
--- Boss tabs select the encounter.  Lifecycle buttons (Start Fight / Wipe /
--- End Fight) inject the same events that happen in a real fight.
--- Ability buttons fire individual events via Playback.injectLine.

local ZoneManager = require("core.ZoneManager")
local Log         = require("lib.Log")

local DP = {}

-- ── Layout constants ───────────────────────────────────────────────────────
local WIN_W            = 340
local WIN_H            = 500
local BTN_H            = 26
local BTN_PAD          = 3
local TAB_H            = 24
local TITLE_H          = 30
local TRIAL_ROW_H      = 28
local LIFECYCLE_ROW_H  = 28
local BOSS_TAB_ROW_H   = TAB_H + 6
local SCROLL_S         = BTN_H + BTN_PAD

-- ── Fake-line field stubs ──────────────────────────────────────────────────
local FAKE_SRC  = 34218181
local FAKE_UNIT = 48707525

-- ── Module-level state ────────────────────────────────────────────────────
local _selectedTrial     = nil   -- Trial instance currently shown in the panel
local _ownsTrial         = false -- true if the panel called enable() on _selectedTrial
local _selectedBossClass = nil   -- boss class of the active tab
local _debugBoss         = nil   -- injected temp instance, or nil

-- ── Ability row builder ────────────────────────────────────────────────────
local function abilityRows(bossClass)
    local rows = {}
    if not bossClass.events then return rows end
    local e = bossClass.events

    -- Deduplicate: entries present in both instant and started (e.g. Yandir)
    -- produce one button; started-only entries get a "(cast)" button.
    local instantSet = e.beginCast and e.beginCast.instant or {}
    for id in pairs(instantSet) do
        rows[#rows + 1] = {
            id    = id,
            line  = ("0,BEGIN_CAST,0,F,%d,%d,0"):format(FAKE_SRC, id),
            label = ("[%d] %s  (instant)"):format(id, GetAbilityName(id) or ""),
        }
    end
    for id in pairs(e.beginCast and e.beginCast.started or {}) do
        if not instantSet[id] then
            rows[#rows + 1] = {
                id    = id,
                line  = ("0,BEGIN_CAST,2000,F,%d,%d,0"):format(FAKE_SRC, id),
                label = ("[%d] %s  (cast)"):format(id, GetAbilityName(id) or ""),
            }
        end
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

-- ── Debug-boss / trial lifecycle ───────────────────────────────────────────

local function teardownDebugBoss()
    if not _debugBoss or not _selectedTrial then return end
    _selectedTrial:ejectBoss(_debugBoss)
    _debugBoss = nil
end

-- Only disable the trial if the panel enabled it and the zone hasn't since
-- taken ownership (player entered the zone while the panel was open).
local function disableOwnedTrial()
    if _ownsTrial and _selectedTrial then
        if _selectedTrial ~= ZoneManager.getActiveTrial() then
            _selectedTrial:disable()
        end
    end
    _ownsTrial = false
end

local function selectTrialModule(trial)
    teardownDebugBoss()
    disableOwnedTrial()
    _selectedTrial     = trial
    _selectedBossClass = nil
    _ownsTrial         = false
    if trial and not trial.enabled then
        trial:enable()
        _ownsTrial = true
    end
end

local function setupDebugBoss(bossClass)
    teardownDebugBoss()
    _selectedBossClass = bossClass
    if not _selectedTrial or not bossClass then return end
    if not _selectedTrial.enabled then
        _selectedTrial:enable()
        _ownsTrial = true
    end
    local instance = bossClass.new()
    _selectedTrial:injectBoss(instance)
    _debugBoss = instance
end

-- ── Window state ───────────────────────────────────────────────────────────
local win
local btnPool   = {}   -- ability buttons (reusable)
local tabPool   = {}   -- boss tab buttons (reusable)
local trialPool = {}   -- trial tab buttons (reusable)
local items     = {}   -- current ability rows for selected boss
local bossList  = {}   -- { key, bossClass } for _selectedTrial
local trialList = {}   -- { module, name } from ZoneManager.getTrialList()
local scrollY   = 0

local function contentH()
    return WIN_H - TITLE_H - TRIAL_ROW_H - LIFECYCLE_ROW_H - BOSS_TAB_ROW_H - 8
end

local function maxScroll()
    return math.max(0, #items * (BTN_H + BTN_PAD) - contentH())
end

local function layoutAbilities()
    local h = contentH()
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
                Log.print("%s", tostring(res))
            end
        end)
        btnPool[#btnPool + 1] = btn
    end
end

-- ── Boss tab selection ─────────────────────────────────────────────────────
local function applyBossTabHighlight(activeIdx)
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

local selectBoss  -- forward declaration; assigned below after layoutBossTabs

local function layoutBossTabs()
    if #bossList == 0 then
        for _, tab in ipairs(tabPool) do tab:SetHidden(true) end
        return
    end
    local tabW = math.floor((WIN_W - 8) / #bossList)
    local wm = WINDOW_MANAGER
    for i, entry in ipairs(bossList) do
        local tab = tabPool[i]
        if not tab then
            tab = wm:CreateControl("InchDebugTab" .. i, win.bossTabRow, CT_BUTTON)
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
        tab:SetAnchor(TOPLEFT, win.bossTabRow, TOPLEFT, 2 + (i - 1) * tabW, 1)
        tab:SetHidden(false)
    end
    for i = #bossList + 1, #tabPool do
        tabPool[i]:SetHidden(true)
    end
end

selectBoss = function(idx)
    scrollY = 0
    applyBossTabHighlight(idx)
    local entry = bossList[idx]
    if entry then
        win.titleLbl:SetText("Incha Debug — " .. (entry.key or "?"))
        items = abilityRows(entry.bossClass)
        setupDebugBoss(entry.bossClass)
    else
        win.titleLbl:SetText("Incha Debug")
        items = {}
        teardownDebugBoss()
    end
    ensureAbilityPool(#items)
    layoutAbilities()
end

-- ── Trial tab management ───────────────────────────────────────────────────
local function applyTrialTabHighlight(activeModule)
    for i, tab in ipairs(trialPool) do
        if i <= #trialList then
            if trialList[i].module == activeModule then
                tab:SetNormalFontColor(1, 0.85, 0.35, 1)
            else
                tab:SetNormalFontColor(0.55, 0.65, 0.85, 1)
            end
        end
    end
end

local function rebuildBossListForTrial(trial)
    teardownDebugBoss()
    bossList = {}
    items    = {}
    scrollY  = 0

    if not trial then
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

    layoutBossTabs()

    if #bossList > 0 then
        local autoIdx = 1
        local activeBoss = trial:getActiveBoss()
        if activeBoss and activeBoss.key then
            for i, entry in ipairs(bossList) do
                if entry.key == activeBoss.key then autoIdx = i; break end
            end
        end
        selectBoss(autoIdx)
    else
        layoutAbilities()
    end
end

local function onTrialSelected(idx)
    local entry = trialList[idx]
    if not entry then return end
    selectTrialModule(entry.module)
    applyTrialTabHighlight(entry.module)
    win.titleLbl:SetText("Incha Debug — " .. (entry.name or "?"))
    rebuildBossListForTrial(entry.module)
end

local function layoutTrialTabs()
    if #trialList == 0 then
        for _, tab in ipairs(trialPool) do tab:SetHidden(true) end
        return
    end
    local tabW = math.floor((WIN_W - 8) / #trialList)
    local wm = WINDOW_MANAGER
    for i, entry in ipairs(trialList) do
        local tab = trialPool[i]
        if not tab then
            tab = wm:CreateControl("InchDebugTrialTab" .. i, win.trialRow, CT_BUTTON)
            tab:SetHeight(TAB_H)
            tab:SetFont("ZoFontGameSmall")
            local lbl = tab:GetLabelControl()
            if lbl then lbl:SetHorizontalAlignment(TEXT_ALIGN_CENTER) end
            tab:SetMouseOverFontColor(1, 0.95, 0.4, 1)
            local capturedI = i
            tab:SetHandler("OnClicked", function() onTrialSelected(capturedI) end)
            trialPool[i] = tab
        end
        tab:SetWidth(tabW - 2)
        tab:SetText(entry.name)
        tab:ClearAnchors()
        tab:SetAnchor(TOPLEFT, win.trialRow, TOPLEFT, 2 + (i - 1) * tabW, 1)
        tab:SetHidden(false)
    end
    for i = #trialList + 1, #trialPool do
        trialPool[i]:SetHidden(true)
    end
end

-- ── Full rebuild ───────────────────────────────────────────────────────────
local function rebuild()
    teardownDebugBoss()
    disableOwnedTrial()
    _selectedTrial     = nil
    _selectedBossClass = nil

    trialList = ZoneManager.getTrialList()
    layoutTrialTabs()

    if #trialList == 0 then
        win.titleLbl:SetText("Incha Debug — no trials registered")
        bossList = {}
        items    = {}
        for _, tab in ipairs(tabPool) do tab:SetHidden(true) end
        layoutAbilities()
        return
    end

    -- Auto-select active trial if player is in zone, otherwise first trial
    local activeTrial = ZoneManager.getActiveTrial()
    local autoIdx = 1
    if activeTrial then
        for i, entry in ipairs(trialList) do
            if entry.module == activeTrial then autoIdx = i; break end
        end
    end

    onTrialSelected(autoIdx)
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
    closeBtn:SetText("x")
    closeBtn:SetNormalFontColor(1, 0.4, 0.4, 1)
    closeBtn:SetHandler("OnClicked", function()
        teardownDebugBoss()
        disableOwnedTrial()
        win:SetHidden(true)
    end)

    -- Refresh button
    local refBtn = wm:CreateControl("InchDebugPanelRefresh", win, CT_BUTTON)
    refBtn:SetDimensions(52, 20)
    refBtn:SetAnchor(TOPRIGHT, win, TOPRIGHT, -26, 4)
    refBtn:SetFont("ZoFontGameSmall")
    refBtn:SetText("Refresh")
    refBtn:SetNormalFontColor(0.5, 0.9, 0.5, 1)
    refBtn:SetHandler("OnClicked", rebuild)

    -- ── Trial selector row ─────────────────────────────────────────────────
    local trialBg = wm:CreateControl("InchDebugPanelTrialBg", win, CT_BACKDROP)
    trialBg:SetAnchor(TOPLEFT,  win, TOPLEFT,  0, TITLE_H)
    trialBg:SetAnchor(TOPRIGHT, win, TOPRIGHT, 0, TITLE_H)
    trialBg:SetHeight(TRIAL_ROW_H)
    trialBg:SetCenterColor(0.05, 0.08, 0.14, 0.9)
    trialBg:SetEdgeColor(0.20, 0.25, 0.45, 0.8)
    trialBg:SetInsets(1, 1, -1, -1)

    local trialRow = wm:CreateControl("InchDebugPanelTrialRow", win, CT_CONTROL)
    trialRow:SetAnchor(TOPLEFT,  win, TOPLEFT,  4, TITLE_H + 2)
    trialRow:SetAnchor(TOPRIGHT, win, TOPRIGHT, -4, TITLE_H + 2)
    trialRow:SetHeight(TAB_H)
    win.trialRow = trialRow

    -- ── Lifecycle row ──────────────────────────────────────────────────────
    local lcY = TITLE_H + TRIAL_ROW_H

    local lcBg = wm:CreateControl("InchDebugPanelLCBg", win, CT_BACKDROP)
    lcBg:SetAnchor(TOPLEFT,  win, TOPLEFT,  0, lcY)
    lcBg:SetAnchor(TOPRIGHT, win, TOPRIGHT, 0, lcY)
    lcBg:SetHeight(LIFECYCLE_ROW_H)
    lcBg:SetCenterColor(0.04, 0.09, 0.07, 0.85)
    lcBg:SetEdgeColor(0.15, 0.30, 0.20, 0.8)
    lcBg:SetInsets(1, 1, -1, -1)

    local btnW   = math.floor((WIN_W - 12) / 3)
    local btnTop = lcY + 3

    local startBtn = wm:CreateControl("InchDebugPanelStart", win, CT_BUTTON)
    startBtn:SetDimensions(btnW, 22)
    startBtn:SetAnchor(TOPLEFT, win, TOPLEFT, 4, btnTop)
    startBtn:SetFont("ZoFontGameSmall")
    startBtn:SetText("Start Fight")
    startBtn:SetNormalFontColor(0.3, 1, 0.4, 1)
    startBtn:SetMouseOverFontColor(0.5, 1, 0.6, 1)
    startBtn:SetHandler("OnClicked", function()
        if not _selectedBossClass then
            Log.print("Select a boss tab first")
            return
        end
        setupDebugBoss(_selectedBossClass)
        Log.print("Fight started: %s", _selectedBossClass.key or "?")
    end)

    local wipeBtn = wm:CreateControl("InchDebugPanelWipe", win, CT_BUTTON)
    wipeBtn:SetDimensions(btnW, 22)
    wipeBtn:SetAnchor(TOPLEFT, win, TOPLEFT, 4 + btnW + 2, btnTop)
    wipeBtn:SetFont("ZoFontGameSmall")
    wipeBtn:SetText("Wipe")
    wipeBtn:SetNormalFontColor(1, 0.85, 0.2, 1)
    wipeBtn:SetMouseOverFontColor(1, 0.95, 0.4, 1)
    wipeBtn:SetHandler("OnClicked", function()
        if not _debugBoss or not _selectedTrial then
            Log.print("No active fight")
            return
        end
        if _debugBoss.onWipe then
            _debugBoss:onWipe(_selectedTrial.context, _selectedTrial.alerts)
            Log.print("Wiped")
        end
    end)

    local endBtn = wm:CreateControl("InchDebugPanelEnd", win, CT_BUTTON)
    endBtn:SetDimensions(btnW, 22)
    endBtn:SetAnchor(TOPLEFT, win, TOPLEFT, 4 + (btnW + 2) * 2, btnTop)
    endBtn:SetFont("ZoFontGameSmall")
    endBtn:SetText("End Fight")
    endBtn:SetNormalFontColor(1, 0.4, 0.4, 1)
    endBtn:SetMouseOverFontColor(1, 0.6, 0.5, 1)
    endBtn:SetHandler("OnClicked", function()
        if not _debugBoss then
            Log.print("No active fight")
            return
        end
        teardownDebugBoss()
        Log.print("Fight ended")
    end)

    -- ── Boss tab row ───────────────────────────────────────────────────────
    local bossTabY = TITLE_H + TRIAL_ROW_H + LIFECYCLE_ROW_H

    local bossTabBg = wm:CreateControl("InchDebugPanelTabBg", win, CT_BACKDROP)
    bossTabBg:SetAnchor(TOPLEFT,  win, TOPLEFT,  0, bossTabY)
    bossTabBg:SetAnchor(TOPRIGHT, win, TOPRIGHT, 0, bossTabY)
    bossTabBg:SetHeight(BOSS_TAB_ROW_H)
    bossTabBg:SetCenterColor(0.07, 0.07, 0.14, 0.85)
    bossTabBg:SetEdgeColor(0.25, 0.30, 0.50, 0.8)
    bossTabBg:SetInsets(1, 1, -1, -1)

    local bossTabRow = wm:CreateControl("InchDebugPanelBossTabRow", win, CT_CONTROL)
    bossTabRow:SetAnchor(TOPLEFT,  win, TOPLEFT,  4, bossTabY + 3)
    bossTabRow:SetAnchor(TOPRIGHT, win, TOPRIGHT, -4, bossTabY + 3)
    bossTabRow:SetHeight(TAB_H)
    win.bossTabRow = bossTabRow

    -- ── Ability scroll area ────────────────────────────────────────────────
    local contY = bossTabY + BOSS_TAB_ROW_H + 2

    local cont = wm:CreateControl("InchDebugPanelCont", win, CT_CONTROL)
    cont:SetAnchor(TOPLEFT,     win, TOPLEFT,     4, contY)
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
    if not win then
        local ok, err = pcall(buildWindow)
        if not ok then
            win = nil  -- partial window state; retry on next call
            Log.always("DebugPanel build error: %s", tostring(err))
            return
        end
    end
    if not win then
        Log.always("DebugPanel: failed to create window")
        return
    end
    if win:IsHidden() then
        local ok, err = pcall(rebuild)
        if not ok then
            Log.always("DebugPanel rebuild error: %s", tostring(err))
        end
        win:SetHidden(false)
    else
        teardownDebugBoss()
        disableOwnedTrial()
        win:SetHidden(true)
    end
end

package.loaded["ui.DebugPanel"] = DP
return DP
