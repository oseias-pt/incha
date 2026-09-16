--- test/checks/tracker.lua  -  end-to-end check of the A3 tracker table.
---
--- Runs the shipping ui/Panel.lua through a real core/Trial with a real boss
--- (Yandir) and asserts that the panel ends up VISIBLE with populated rows
--- after the same lifecycle the game drives:
---
---   Trial:enable  ->  bridge.onEnable (build)       panel built, hidden
---   injectBoss    ->  bridge.onBossEnter             panel active + shown
---   onCombatState(true)                              timers armed
---   200 ms onUpdate ticks                            rows written with ETAs
---   HUD scene callbacks (shown / hidden)             panel follows the HUD
---   ejectBoss                                        panel cleared + hidden
---
--- lifecycle.lua stubs SetHidden as a no-op, so it cannot see whether the
--- table would actually be on screen; this check tracks the hidden flag and
--- label text on every control instead.
---
--- Usage (from the repository root):
---   luajit test/checks/tracker.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
local EsoApi = require("harness.eso_api")
require("lang.en")

local findings = 0
local function fail(fmt, ...)
    print("FAIL  " .. string.format(fmt, ...))
    findings = findings + 1
end
local function pass(name) print("ok    " .. name) end
local function assertEq(got, expected, label)
    if got ~= expected then
        fail("%s: expected %s, got %s", label, tostring(expected), tostring(got))
        return false
    end
    return true
end

-- -- UI stubs that remember state --------------------------------------------
local function newControl(name)
    local c = { name = name, hidden = false, text = "" }
    local noop = function() end
    for _, m in ipairs({
        "SetDimensions", "SetClampedToScreen", "SetMouseEnabled", "SetMovable",
        "SetScale", "ClearAnchors", "SetAnchor", "SetHandler", "SetAnchorFill",
        "SetCenterColor", "SetEdgeColor", "SetFont", "SetHorizontalAlignment",
        "SetVerticalAlignment", "SetTexture", "SetColor",
    }) do c[m] = noop end
    c.SetHidden = function(self, h) self.hidden = h end
    c.IsHidden  = function(self) return self.hidden end
    c.SetText   = function(self, t) self.text = t end
    return c
end
WINDOW_MANAGER = { CreateControl = function(_, name) return newControl(name) end }
GuiRoot = { GetWidth = function() return 1920 end }
local sceneCallbacks = {}
SCENE_MANAGER = {
    GetScene = function(_, sceneName)
        return { RegisterCallback = function(_, _, fn) sceneCallbacks[sceneName] = fn end }
    end,
}
TOPLEFT, CENTER, CT_CONTROL, CT_BACKDROP, CT_LABEL, CT_TEXTURE = 1, 2, 3, 4, 5, 6
TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT = 1, 2, 3
function zo_callLater() return 1 end
function zo_removeCallLater() end

-- Real overlay defaults (the harness Settings stub returns {} from get()).
package.loaded["core.Settings"].get = function()
    return { overlay = { locked = false, scale = 1, offsetX = -1, offsetY = -1, alertX = -1, alertY = -1 } }
end

-- Replace the harness's Panel stub with the shipping module.
package.loaded["ui.Panel"] = nil
local Panel = dofile("ui/Panel.lua")
package.loaded["ui.Panel"] = Panel

local Trial  = require("core.Trial")
local Yandir = require("trial.ka.boss.Yandir")

local trial = Trial.create({
    id = "ka", zoneId = 1196, bosses = { Yandir },
    bridge = Panel.bridge, alerts = Panel.alerts,
})

-- -- 1. enable builds the panel, hidden ---------------------------------------
EsoApi.setCurrentTime(1000)
trial:enable()
local c = Panel._inspect()
if not c then
    fail("tracker not built by Panel.bridge.onEnable")
    os.exit(1)
end
assertEq(c.panel.hidden, true, "tracker hidden before any boss")
pass("enable: tracker built and hidden")

-- -- 2. injectBoss shows the panel and the update loop fills rows ------------
trial:injectBoss(Yandir.new())
assertEq(c.active, true,        "tracker active after injectBoss")
assertEq(c.panel.hidden, false, "tracker shown after injectBoss")
assertEq(trial._injected, true, "trial flags the injected boss")

EsoApi.setCurrentTime(1200)
trial:onUpdate()
assertEq(c.rows[1].nameLbl.text, "Totem",   "row 1 label written by Yandir:onUpdate")
assertEq(c.rows[1].etaLbl.text,  "20s",     "row 1 ETA armed by onCombatState(true)")
assertEq(c.rows[2].nameLbl.text, "Gryphon", "row 2 label")
assertEq(c.rows[2].etaLbl.text,  "60s",     "row 2 ETA")
assertEq(c.rows[3].nameLbl.text, "",        "row 3 stays empty")

EsoApi.setCurrentTime(6200)
trial:onUpdate()
assertEq(c.rows[1].etaLbl.text, "15s", "row 1 counts down on later ticks")
pass("injectBoss: tracker visible, rows populated and counting down")

-- -- 3. a real EVENT_BOSSES_CHANGED must not evict the injected boss --------
trial:onBossesChanged(false)
assertEq(trial:getActiveBoss() ~= nil, true, "injected boss survives EVENT_BOSSES_CHANGED")
assertEq(c.panel.hidden, false,             "tracker still shown after EVENT_BOSSES_CHANGED")
pass("injectBoss: EVENT_BOSSES_CHANGED ignored while a debug boss is injected")

-- -- 4. HUD scene state drives visibility ------------------------------------
sceneCallbacks.hud("shown", "hidden")
sceneCallbacks.hudui("shown", "hidden")
assertEq(c.panel.hidden, true, "tracker hidden when both HUD scenes are hidden")
sceneCallbacks.hud("hidden", "showing")
assertEq(c.panel.hidden, false, "tracker back when the HUD is showing")
sceneCallbacks.hud("showing", "shown")
assertEq(c.panel.hidden, false, "tracker stays when the HUD is shown")
pass("hud: tracker follows the hud / hudui scene state")

-- -- 5. ejectBoss clears and hides -------------------------------------------
trial:ejectBoss(trial:getActiveBoss())
assertEq(trial:getActiveBoss(), nil,  "no boss after ejectBoss (nothing to detect)")
assertEq(trial._injected, false,      "injected flag cleared by ejectBoss")
assertEq(c.panel.hidden, true,        "tracker hidden after ejectBoss")
assertEq(c.rows[1].nameLbl.text, "",  "rows blanked after ejectBoss")
pass("ejectBoss: tracker cleared and hidden")

-- -- 6. Playback.injectLine into an explicit trial ----------------------------
local Playback = require("lib.Playback")
-- Harness constant for ACTION_RESULT_BEGIN-based cast lines.
local res = Playback.injectLine("0,BEGIN_CAST,0,F,1,133515,0", trial)   -- Yandir poison totem
assertEq(res:sub(1, 10), "BEGIN_CAST", "injectLine accepted the line: " .. res)
assertEq(trial:getActiveBoss() ~= nil, true, "injectLine spun up a temp boss on the given trial")
assertEq(c.panel.hidden, false, "tracker shown for the temp boss")
EsoApi.setCurrentTime(6400)
trial:onUpdate()
assertEq(c.rows[1].nameLbl.text, "Totem", "temp boss wrote tracker rows")
pass("playback: injectLine targets the trial it is given")

print()
if findings == 0 then
    print("tracker: all checks passed")
    os.exit(0)
end
print(string.format("tracker: %d finding(s)", findings))
os.exit(1)
