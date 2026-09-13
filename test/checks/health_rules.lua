--- test/checks/health_rules.lua  -  unit tests for core/HealthRules.
---
--- Covers:
---   1. register() sort by priority (descending)
---   2. register() pre-compiles _staticText for rules without {hp}
---   3. evaluate() returns nil for empty / nil rules
---   4. evaluate() returns first match (priority order)
---   5. evaluate() respects min/max boundaries (inclusive)
---   6. evaluate() runs when() predicate correctly
---   7. evaluate() formats {hp} placeholder via string.format
---   8. evaluate() returns cached _staticText when no {hp}
---
--- Usage (from the repository root):
---   luajit test/checks/health_rules.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
require("harness.eso_api")

local HealthRules = require("core.HealthRules")

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

-- -- 1. register() priority sort -------------------------------------------

local rules1 = HealthRules.register({
    { id = "low",  text = "low",  min = 0,  max = 100, priority = 0  },
    { id = "high", text = "high", min = 0,  max = 100, priority = 10 },
    { id = "mid",  text = "mid",  min = 0,  max = 100, priority = 5  },
})

if rules1[1].id == "high" and rules1[2].id == "mid" and rules1[3].id == "low" then
    pass("register sorts by priority descending")
else
    fail("register sort wrong: got %s, %s, %s", rules1[1].id, rules1[2].id, rules1[3].id)
end

-- -- 2. register() _staticText pre-compilation -----------------------------

local rules2 = HealthRules.register({
    { id = "static",  text = "No placeholder here", min = 0, max = 100 },
    { id = "dynamic", text = "HP is {hp}%%",         min = 0, max = 100 },
})

if rules2[1]._staticText == "No placeholder here" then
    pass("register pre-compiles _staticText for static rules")
else
    fail("register _staticText: expected 'No placeholder here', got %s",
         tostring(rules2[1]._staticText))
end

if rules2[2]._staticText == nil then
    pass("register leaves _staticText nil for rules with {hp}")
else
    fail("register _staticText should be nil for dynamic rule, got %s",
         tostring(rules2[2]._staticText))
end

-- -- 3. evaluate() nil/empty rules -----------------------------------------

local id, text = HealthRules.evaluate(nil, 50, {})
if id == nil and text == nil then
    pass("evaluate(nil rules) returns nil,nil")
else
    fail("evaluate(nil): expected nil,nil got %s,%s", tostring(id), tostring(text))
end

local id2, text2 = HealthRules.evaluate({}, 50, {})
if id2 == nil and text2 == nil then
    pass("evaluate({} empty rules) returns nil,nil")
else
    fail("evaluate({}): expected nil,nil got %s,%s", tostring(id2), tostring(text2))
end

-- -- 4. evaluate() first-match in priority order ----------------------------

local rules4 = HealthRules.register({
    { id = "phase2", text = "Phase 2", min = 0,  max = 50,  priority = 5 },
    { id = "phase1", text = "Phase 1", min = 51, max = 100, priority = 5 },
    { id = "any",    text = "Any",     min = 0,  max = 100, priority = 0 },
})

local id4a, text4a = HealthRules.evaluate(rules4, 75, {})
assertEq(id4a,   "phase1", "evaluate at 75 → phase1 id")
assertEq(text4a, "Phase 1", "evaluate at 75 → Phase 1 text")

local id4b, text4b = HealthRules.evaluate(rules4, 30, {})
assertEq(id4b,   "phase2", "evaluate at 30 → phase2 id")
assertEq(text4b, "Phase 2", "evaluate at 30 → Phase 2 text")

if findings == 0 then pass("evaluate first-match priority order") end

-- -- 5. evaluate() min/max boundaries (inclusive) ---------------------------

local rules5 = HealthRules.register({
    { id = "exact", text = "Exact", min = 50, max = 50, priority = 0 },
})

local id5a = HealthRules.evaluate(rules5, 50, {})
assertEq(id5a, "exact", "evaluate at exact boundary min==max==50 matches")

local id5b = HealthRules.evaluate(rules5, 49.9, {})
assertEq(id5b, nil, "evaluate at 49.9 misses [50,50]")

local id5c = HealthRules.evaluate(rules5, 50.1, {})
assertEq(id5c, nil, "evaluate at 50.1 misses [50,50]")

if id5a == "exact" and id5b == nil and id5c == nil then
    pass("evaluate respects min/max boundaries inclusively")
end

-- -- 6. evaluate() when() predicate ----------------------------------------

local ctx6 = { stage = 2 }

local rules6 = HealthRules.register({
    { id = "stage2_only", text = "Stage 2", min = 0, max = 100, priority = 10,
      when = function(ctx) return ctx.stage == 2 end },
    { id = "fallback",    text = "Any",     min = 0, max = 100, priority = 0 },
})

local id6a = HealthRules.evaluate(rules6, 50, ctx6)
assertEq(id6a, "stage2_only", "evaluate when() passes for stage==2")

local id6b = HealthRules.evaluate(rules6, 50, { stage = 1 })
assertEq(id6b, "fallback", "evaluate when() fails → falls through to fallback")

if id6a == "stage2_only" and id6b == "fallback" then
    pass("evaluate runs when() predicate correctly")
end

-- -- 7. evaluate() {hp} placeholder substitution ---------------------------

local rules7 = HealthRules.register({
    { id = "pct", text = "HP: {hp}%", min = 0, max = 100 },
})

local _, text7 = HealthRules.evaluate(rules7, 72.3, {})
-- formatText does gsub("{hp}", "72.3") — no string.format on the template,
-- so a literal % in the template stays as %, not %%
assertEq(text7, "HP: 72.3%", "evaluate substitutes {hp} placeholder")
if text7 == "HP: 72.3%" then pass("{hp} substitution produces correct string") end

-- -- 8. evaluate() returns cached _staticText for static rules --------------

local rules8 = HealthRules.register({
    { id = "s", text = "Static label", min = 0, max = 100 },
})
local cached = rules8[1]._staticText
local _, text8a = HealthRules.evaluate(rules8, 50, {})
local _, text8b = HealthRules.evaluate(rules8, 80, {})
-- Both calls should return the exact same string object (rawequal), not copies.
if rawequal(text8a, cached) and rawequal(text8b, cached) then
    pass("evaluate returns same _staticText object (no allocation) for static rules")
else
    fail("evaluate returned different string objects for static rule (expected _staticText)")
end

-- -- also: evaluate passes boss as second arg to when() -------------------

local rules9 = HealthRules.register({
    { id = "boss_gate", text = "Boss gate", min = 0, max = 100, priority = 0,
      when = function(ctx, boss) return boss and boss.inPhase2 end },
})

local id9a = HealthRules.evaluate(rules9, 50, {}, { inPhase2 = true })
assertEq(id9a, "boss_gate", "when() receives boss as second arg")
local id9b = HealthRules.evaluate(rules9, 50, {}, { inPhase2 = false })
assertEq(id9b, nil, "when() boss.inPhase2=false skips rule")
if id9a == "boss_gate" and id9b == nil then
    pass("evaluate passes boss to when() predicate")
end

-- -- Report -----------------------------------------------------------------

print("")
if findings == 0 then
    print("health_rules: clean (all assertions passed)")
else
    print(string.format("health_rules: %d failure(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
