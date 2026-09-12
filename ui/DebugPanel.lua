--- ui/DebugPanel.lua  —  clickable replay panel for in-trial /ip testing.
---
--- Open/close with:  /incha dp
---
--- Shows one button per routed ability for the current active boss (when in
--- a boss arena) or all bosses in the trial registry (between arenas).
--- Clicking a button fires Playback.injectLine() with a generated fake log
--- line matching each route's expected trigger type, then prints the result
--- to chat so you can confirm the replay message.
---
--- Press "Refresh" (or close + reopen) after entering a new arena to update
--- the list.

local EventDispatcher = require("core.EventDispatcher")
local ZoneManager     = require("core.ZoneManager")

local DP = {}

-- ── Layout constants ───────────────────────────────────────────────────────
local WIN_W    = 340
local WIN_H    = 460
local BTN_H    = 26
local BTN_PAD  = 3
local SCROLL_S = BTN_H + BTN_PAD   -- pixels per wheel tick

-- ── Fake-line field stubs ──────────────────────────────────────────────────
local FAKE_SRC  = 34218181
local FAKE_UNIT = 48707525

-- ── Ability row builder ────────────────────────────────────────────────────
--- Returns a sorted list of { id, line, label } from one boss class.
--- Reads boss.events buckets; generates a fake log line that Playback can inject.
---   beginCast.instant  → BEGIN_CAST castDuration=0
---   beginCast.started  → BEGIN_CAST castDuration=2000
---   combatEvent.other  → COMBAT_EVENT EFFECT_GAINED  (routes to "other" bucket)
---   effectChanged.gained/faded → EFFECT_CHANGED GAINED/FADED
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
local win          -- top-level control (created once)
local btnPool = {} -- reusable CT_BUTTON controls
local items   = {} -- current { id, line, label } list
local scrollY = 0  -- scroll offset in pixels

local function contH()
    return WIN_H - 34
end

local function maxScroll()
    return math.max(0, #items * (BTN_H + BTN_PAD) - contH())
end

local function layout()
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

local function ensurePool(n)
    local wm = WINDOW_MANAGER
    for i = #btnPool + 1, n do
        local btn = wm:CreateControl("InchDebugBtn" .. i, win.cont, CT_BUTTON)
        btn:SetDimensions(WIN_W - 18, BTN_H)
        btn:SetFont("ZoFontGameSmall")
        local lbl = btn:GetLabelControl()
        if lbl then
            lbl:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        end
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

local function rebuild()
    items  = {}
    scrollY = 0

    local trial = ZoneManager.getActiveTrial()
    if not trial then
        win.titleLbl:SetText("Incha Debug — no trial")
        layout()
        return
    end

    local boss = trial:getActiveBoss()
    if boss then
        win.titleLbl:SetText("Incha Debug — " .. (boss.key or "?"))
        items = abilityRows(boss)
    else
        win.titleLbl:SetText("Incha Debug — " .. (trial.key or "trial") .. " (all bosses)")
        for _, bc in ipairs(trial.registry.bosses or {}) do
            for _, row in ipairs(abilityRows(bc)) do
                row.label = "[" .. (bc.key or "?") .. "] " .. row.label
                items[#items + 1] = row
            end
        end
    end

    ensurePool(#items)
    layout()
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

    -- Scrollable container (clips children)
    local cont = wm:CreateControl("InchDebugPanelCont", win, CT_CONTROL)
    cont:SetAnchor(TOPLEFT, win, TOPLEFT, 4, 30)
    cont:SetAnchor(BOTTOMRIGHT, win, BOTTOMRIGHT, -4, -4)
    cont:SetMouseEnabled(true)
    cont:SetHandler("OnMouseWheel", function(_, delta)
        scrollY = math.max(0, math.min(maxScroll(), scrollY - delta * SCROLL_S))
        layout()
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
