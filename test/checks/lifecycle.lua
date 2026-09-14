--- test/checks/lifecycle.lua  -  unit tests for core lifecycle and hot-path
--- behaviour that the log replay cannot observe.
---
--- Covers:
---   1. EventDispatcher arms the interrupt-detection timer ONLY when the boss
---      declares an `interrupted` entry, and forwards the unit args to it
---   2. BossRegistry.findByName resolves name, aliases and ESO name markup
---      through the pre-built lookup
---   3. Trial:injectBoss / ejectBoss run the full boss lifecycle
---   4. ZoneManager.refresh applies a Settings.enabled toggle in-zone
---   5. Panel.setRow updates the row record in place (no per-tick table) and
---      only touches SetText when the displayed second changes
---   6. Fmt.timer / Fmt.pct output for the cached precisions
---
--- Usage (from the repository root):
---   luajit test/checks/lifecycle.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
local EsoApi = require("harness.eso_api")

local findings = 0
local function fail(fmt, ...)
    print("FAIL  " .. string.format(fmt, ...))
    findings = findings + 1
end
local function pass(name)
    print(string.format("ok    %s", name))
end
local function assertEq(got, expected, label)
    if got ~= expected then
        fail("%s: expected %s, got %s", label, tostring(expected), tostring(got))
        return false
    end
    return true
end

-- Record zo_callLater calls so the tests can assert on them and fire them.
local _scheduled = {}
function zo_callLater(fn, ms)
    local h = #_scheduled + 1
    _scheduled[h] = { fn = fn, ms = ms, cancelled = false }
    return h
end
function zo_removeCallLater(h)
    if _scheduled[h] then _scheduled[h].cancelled = true end
end
local function scheduledCount()
    local n = 0
    for _, s in ipairs(_scheduled) do if not s.cancelled then n = n + 1 end end
    return n
end

local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local BossRegistry    = require("core.BossRegistry")
local Trial           = require("core.Trial")
local Fmt             = require("core.Fmt")

-- -- 1. Interrupt timer is gated on an `interrupted` entry --------------------
do
    local startedHits, interruptedArgs = 0, nil
    local function onStarted() startedHits = startedHits + 1 end
    local function onInterrupted(boss, ctx, alerts, abilityId, srcName, unitTag, unitId, sourceUnitId, unitName)
        interruptedArgs = { abilityId, srcName, unitTag, unitId, sourceUnitId, unitName }
    end

    local NoInterrupt = {
        key = "noint",
        events = { beginCast = { started = { [100] = { type = AlertTypes.CUSTOM, fn = onStarted } } } },
    }
    EventDispatcher.build(NoInterrupt)
    EventDispatcher.dispatchBeginCast(NoInterrupt, {}, {}, 2000, false, 7, 100, "Src",
        "player", 1, 7, "Player")
    assertEq(startedHits, 1, "started handler ran")
    assertEq(scheduledCount(), 0, "no interrupt timer without an interrupted entry")
    pass("dispatcher: no zo_callLater when boss has no interrupted entry")

    local WithInterrupt = {
        key = "withint",
        events = { beginCast = {
            started     = { [100] = { type = AlertTypes.CUSTOM, fn = onStarted } },
            interrupted = { [100] = { type = AlertTypes.CUSTOM, fn = onInterrupted } },
        } },
    }
    EventDispatcher.build(WithInterrupt)
    EventDispatcher.dispatchBeginCast(WithInterrupt, {}, {}, 2000, false, 7, 100, "Src",
        "player", 1, 7, "Player")
    assertEq(scheduledCount(), 1, "interrupt timer armed when an interrupted entry exists")
    -- No T event arrives: fire the timer, the interrupted handler must run
    -- with the unit args the started handler saw.
    _scheduled[#_scheduled].fn()
    if interruptedArgs then
        assertEq(interruptedArgs[1], 100,      "interrupted: abilityId forwarded")
        assertEq(interruptedArgs[3], "player", "interrupted: unitTag forwarded")
        assertEq(interruptedArgs[4], 1,        "interrupted: unitId forwarded")
        assertEq(interruptedArgs[5], 7,        "interrupted: sourceUnitId forwarded")
        assertEq(interruptedArgs[6], "Player", "interrupted: unitName forwarded")
    else
        fail("interrupted handler did not run when the timer fired")
    end
    pass("dispatcher: interrupted handler receives the started event's unit args")

    -- T event cancels the pending timer.
    interruptedArgs = nil
    EventDispatcher.dispatchBeginCast(WithInterrupt, {}, {}, 2000, false, 8, 100, "Src")
    local before = scheduledCount()
    EventDispatcher.dispatchBeginCast(WithInterrupt, {}, {}, 2000, true, 8, 100, "Src")
    assertEq(scheduledCount(), before - 1, "T event cancels the pending interrupt timer")
    EventDispatcher.clearPending()
    pass("dispatcher: T event cancels the pending timer")
end

-- -- 2. BossRegistry name lookup ---------------------------------------------
do
    local A = { key = "a", name = "Alpha" }
    local B = { key = "b", name = "Beta", nameAliases = { "Beta Prime", "Gamma" } }
    local reg = BossRegistry.new({ A, B })
    assertEq(reg:findByName("Alpha"), A, "findByName: primary name")
    assertEq(reg:findByName("Gamma"), B, "findByName: alias")
    assertEq(reg:findByName("Beta Prime^Fx"), B, "findByName: strips ESO gender markup")
    assertEq(reg:findByName("Nobody"), nil, "findByName: unknown -> nil")
    assertEq(reg:findByName(""), nil, "findByName: empty -> nil")
    pass("registry: pre-built name lookup resolves names, aliases and markup")
end

-- -- 3. Trial:injectBoss / ejectBoss -----------------------------------------
do
    local calls = {}
    local Fake = {}
    Fake.__index = Fake
    Fake.key  = "fake"
    Fake.name = "Fake Boss"
    Fake.events = { beginCast = { instant = { [1] = { type = AlertTypes.IGNORE } } } }
    function Fake.new() return setmetatable({}, Fake) end
    function Fake:onEnter()             calls[#calls + 1] = "enter"  end
    function Fake:onCombatState(_, inC) calls[#calls + 1] = inC and "combat" or "nocombat" end
    function Fake:onLeave()             calls[#calls + 1] = "leave"  end
    function Fake:cancelPending()       calls[#calls + 1] = "cancel" end
    EventDispatcher.build(Fake)

    local trial = Trial.create({ id = "ka", zoneId = 1, bosses = { Fake } })
    local inst = Fake.new()
    trial:injectBoss(inst)
    assertEq(trial:getActiveBoss(), nil, "injectBoss is a no-op while the trial is disabled")

    trial:enable()
    trial:injectBoss(inst)
    assertEq(trial:getActiveBoss(), inst, "injectBoss makes the instance active")
    assertEq(trial.context.bossKey, "fake", "injectBoss sets context.bossKey")
    assertEq(table.concat(calls, ","), "enter,combat", "injectBoss runs onEnter then onCombatState(true)")

    calls = {}
    trial:ejectBoss({})   -- a different instance: must be ignored
    assertEq(trial:getActiveBoss(), inst, "ejectBoss ignores a non-active instance")
    trial:ejectBoss(inst)
    assertEq(trial:getActiveBoss(), nil, "ejectBoss clears the active boss")
    assertEq(trial.context.bossKey, nil, "ejectBoss clears context.bossKey")
    assertEq(table.concat(calls, ","), "leave,cancel", "ejectBoss runs onLeave then cancelPending")
    trial:disable()
    pass("trial: injectBoss / ejectBoss run the full boss lifecycle")
end

-- -- 4. ZoneManager.refresh --------------------------------------------------
do
    -- Real Settings module: the harness pre-stubs core.Settings with a table
    -- that has no `trials` field, so build a minimal live one here.
    package.loaded["core.Settings"] = nil
    local Settings = dofile("core/Settings.lua")
    Settings.init()
    package.loaded["core.ZoneManager"] = nil
    local ZoneManager = dofile("core/ZoneManager.lua")

    local state = {}
    local fakeTrial = {
        enable  = function() state.enabled = true  end,
        disable = function() state.enabled = false end,
    }
    ZoneManager.registerTrial(4242, fakeTrial, "ka")
    EsoApi.setZoneId(4242)

    ZoneManager.onZoneChanged()
    assertEq(state.enabled, true, "trial enabled on zone entry")

    Settings.get().trials.ka.enabled = false
    ZoneManager.refresh()
    assertEq(state.enabled, false, "refresh disables a running trial when its flag is turned off")
    assertEq(ZoneManager.getActiveTrial(), nil, "refresh clears the active trial")

    Settings.get().trials.ka.enabled = true
    ZoneManager.refresh()
    assertEq(state.enabled, true, "refresh enables the zone's trial when its flag is turned on")
    assertEq(ZoneManager.getActiveTrial(), fakeTrial, "refresh restores the active trial")

    ZoneManager.refresh()
    assertEq(state.enabled, true, "refresh with no change is a no-op")
    pass("zone manager: refresh applies the Settings.enabled toggle in-zone")
end

-- -- 5. Panel row records and SetText frequency ------------------------------
do
    -- Minimal control stubs: count SetText / SetColor calls per control.
    local function newControl()
        local c = { setText = 0, setColor = 0 }
        local noop = function() end
        c.SetDimensions = noop; c.SetClampedToScreen = noop; c.SetMouseEnabled = noop
        c.SetMovable = noop; c.SetHidden = noop; c.SetScale = noop; c.ClearAnchors = noop
        c.SetAnchor = noop; c.SetHandler = noop; c.SetAnchorFill = noop
        c.SetCenterColor = noop; c.SetEdgeColor = noop; c.SetFont = noop
        c.SetHorizontalAlignment = noop; c.SetVerticalAlignment = noop
        c.SetTexture = noop
        c.SetText  = function(self) self.setText  = self.setText  + 1 end
        c.SetColor = function(self) self.setColor = self.setColor + 1 end
        return c
    end
    WINDOW_MANAGER = { CreateControl = function() return newControl() end }
    GuiRoot = { GetWidth = function() return 1920 end }
    SCENE_MANAGER = { GetScene = function() return { RegisterCallback = function() end } end }
    TOPLEFT, CENTER, CT_CONTROL, CT_BACKDROP, CT_LABEL, CT_TEXTURE = 1, 2, 3, 4, 5, 6
    TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT = 1, 2, 3

    package.loaded["ui.Panel"] = nil
    local Panel = dofile("ui/Panel.lua")
    Panel.bridge.onEnable()

    local c = Panel._inspect()

    Panel.alerts.setRow("t", "Timer", 12.4)
    local rec1 = c.rowData["t"]
    Panel.alerts.setRow("t", "Timer", 12.2)
    local rec2 = c.rowData["t"]
    assertEq(rec1, rec2, "setRow reuses the existing row record (no per-tick table)")
    assertEq(rec2.eta, 12.2, "setRow updates eta in place")

    local etaLbl = c.rows[1].etaLbl
    local setTextBefore = etaLbl.setText
    Panel.alerts.setRow("t", "Timer", 12.1)   -- same whole second (13s) -> no SetText
    assertEq(etaLbl.setText - setTextBefore, 0, "ETA SetText skipped while the displayed second is unchanged")
    Panel.alerts.setRow("t", "Timer", 11.9)   -- crosses to 12s -> one SetText
    assertEq(etaLbl.setText - setTextBefore, 1, "ETA SetText fires when the displayed second changes")

    -- Colour bucket: grey (>10 s) -> orange (3-10 s) -> red (<3 s), each once.
    local colorBefore = etaLbl.setColor
    Panel.alerts.setRow("t", "Timer", 9.5)
    Panel.alerts.setRow("t", "Timer", 9.2)
    Panel.alerts.setRow("t", "Timer", 2.5)
    assertEq(etaLbl.setColor - colorBefore, 2, "SetColor fires once per bucket transition")

    Panel.alerts.clearRow("t")
    assertEq(c.rowData["t"], nil, "clearRow drops the record")
    pass("panel: rows update in place; ETA label is rewritten once per second")
end

-- -- 6. Fmt cached formats ----------------------------------------------------
do
    assertEq(Fmt.timer(3.7),    "4s",    "Fmt.timer default precision")
    assertEq(Fmt.timer(3.7, 1), "3.7s",  "Fmt.timer one decimal")
    assertEq(Fmt.pct(54.3),     "54%",   "Fmt.pct default precision")
    assertEq(Fmt.pct(37.5, 1),  "37.5%", "Fmt.pct one decimal")
    assertEq(Fmt.pct(1.2345, 3), "1.234%", "Fmt.pct uncached precision falls back")
    pass("fmt: timer / pct formats")
end

print("")
if findings == 0 then
    print("lifecycle: clean (all assertions passed)")
else
    print(string.format("lifecycle: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
