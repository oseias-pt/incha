--- test/checks/dispatch.lua  -  EventDispatcher parallel-dispatch validation.
---
--- Replays a KA encounter log through EventDispatcher using auto-generated
--- stub events tables derived from each boss's combatRoutes / effectRoutes.
--- Every declared ability ID is mapped to IGNORE in all subtype buckets, so
--- the only unknown-event warnings that fire are for ability IDs the boss
--- routing tables do not know about (legacy / common handler IDs).
---
--- Reports unknowns per boss, prints a side-by-side count of events the old
--- and new paths each see, and exits non-zero if any unknown warnings fired.
---
--- Usage (from the repository root):
---   luajit test/checks/dispatch.lua <log_file>
---
--- Exit 0 = no unknown-event warnings (new path covers everything old path
---           declares).  Exit 1 = at least one unknown warning.

local SCRIPT_DIR  = debug.getinfo(1, "S").source:match("@?(.+[\\/])") or "./"
local ADDON_ROOT  = SCRIPT_DIR .. "../../"
local HARNESS_DIR = SCRIPT_DIR .. "../"

package.path = ADDON_ROOT .. "?.lua;"
            .. ADDON_ROOT .. "?/init.lua;"
            .. HARNESS_DIR .. "?.lua;"
            .. package.path

-- Load ESO globals first, then modules that need them.
require("harness.eso_api")
local UnitTracker     = require("harness.unit_tracker")
local LogReader       = require("harness.log_reader")
local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")

require("lang.en")

-- -- Arg handling -----------------------------------------------------------

local logPath = arg and arg[1]
if not logPath then
    io.stderr:write("Usage: luajit test/checks/dispatch.lua <log_file>\n")
    os.exit(1)
end

-- -- KA trial configuration -------------------------------------------------

local KA_ZONE = 1196
local KA_HINTS = {
    ["Yandir the Butcher"] = "yandir",
    ["Captain Vrol"]       = "vrol",
    ["Lord Falgravn"]      = "falgravn",
}

-- -- d() capture ------------------------------------------------------------
-- Override the global so we catch [Incha/Dispatcher] unknown warnings without
-- suppressing them from the visible output.

local dispatcherUnknowns = {}   -- { bossKey, abilityId, subPath }
local currentBossKey = nil

local _origD = d
function d(msg)
    local s = tostring(msg)
    if s:find("[Incha/Dispatcher]", 1, true) and s:find("unknown ability", 1, true) then
        dispatcherUnknowns[#dispatcherUnknowns + 1] = {
            boss    = currentBossKey or "?",
            message = s,
        }
    end
    _origD(msg)
end

-- -- Stub events builder -----------------------------------------------------
-- For each declared ability ID (from combatRoutes, effectRoutes, and any
-- common module sets), declare IGNORE in every possible subtype bucket.
-- This suppresses unknown warnings for all IDs the old path handles, so any
-- remaining warnings correspond to IDs the new path would also need to cover.

local function makeAllIgnore(ids)
    local t = {}
    for id in pairs(ids) do
        t[id] = { type = AlertTypes.IGNORE }
    end
    return t
end

local function shallowCopy(src)
    local out = {}
    for k, v in pairs(src) do out[k] = v end
    return out
end

local function buildStubEvents(bossClass)
    local ids = {}
    for id in pairs(bossClass.combatRoutes or {}) do ids[id] = true end
    for id in pairs(bossClass.effectRoutes or {}) do ids[id] = true end
    local common = bossClass.common
    if common then
        for id in pairs(common.combatAbilityIds or {}) do ids[id] = true end
        for id in pairs(common.effectAbilityIds or {}) do ids[id] = true end
    end

    local base = makeAllIgnore(ids)
    return {
        beginCast = {
            instant     = shallowCopy(base),
            started     = shallowCopy(base),
            executed    = shallowCopy(base),
            interrupted = shallowCopy(base),
        },
        effectChanged = {
            gained  = shallowCopy(base),
            faded   = shallowCopy(base),
            updated = shallowCopy(base),
        },
        combatEvent = {
            damage  = shallowCopy(base),
            dodged  = shallowCopy(base),
            blocked = shallowCopy(base),
            other   = shallowCopy(base),
        },
    }
end

-- -- Build KA stub bosses ---------------------------------------------------

local ok, kaTrial = pcall(require, "trial.ka.Factory")
if not ok or not kaTrial then
    io.stderr:write("FATAL: cannot load trial.ka.Factory: " .. tostring(kaTrial) .. "\n")
    os.exit(1)
end

-- stubs[bossKey] = { events = ..., key = bossKey }
-- Also run EventDispatcher.build() on each to catch structural errors.
local stubs = {}
local buildErrors = 0

for _, bossClass in ipairs(kaTrial.registry.bosses) do
    local key    = bossClass.key or "?"
    local events = buildStubEvents(bossClass)
    local stub   = { events = events, key = key }

    local buildOk, buildErr = pcall(EventDispatcher.build, stub)
    if not buildOk then
        io.stderr:write(string.format("  BUILD FAIL  %-12s  %s\n", key, tostring(buildErr)))
        buildErrors = buildErrors + 1
    else
        print(string.format("  build OK  %-12s  (%d ids declared)",
            key, (function()
                local n = 0
                for _ in pairs(bossClass.combatRoutes or {}) do n = n + 1 end
                for _ in pairs(bossClass.effectRoutes or {}) do n = n + 1 end
                return n
            end)()))
    end
    stubs[key] = stub
end

if buildErrors > 0 then
    io.stderr:write(string.format("FATAL: %d EventDispatcher.build() failures — fix before re-running.\n", buildErrors))
    os.exit(1)
end

-- -- Log replay -------------------------------------------------------------

print("\nReading log: " .. logPath)
local entries, parseErrors = LogReader.readFile(logPath)
print(string.format("Parsed %d entries (%d parse errors)\n", #entries, parseErrors))

local tracker = UnitTracker.new()
EsoApi.setZoneId(KA_ZONE)
EsoApi.setTracker(tracker)

-- Per-boss counters: oldPath events seen, newPath events dispatched.
-- Keys: bossKey; value: { old = 0, new = 0 }
local coverage = {}
for key in pairs(stubs) do
    coverage[key] = { old = 0, new = 0 }
end

local stubBoss   = nil    -- current stub boss (nil outside KA zone)
local emptyCtx   = {}
local emptyAlerts = {}

for _, e in ipairs(entries) do
    EsoApi.setCurrentTime(e.ms)
    local et = e.type

    if et == "BEGIN_LOG" then
        tracker:clear()
        stubBoss = nil
        currentBossKey = nil
        EsoApi.setZoneId(0)

    elseif et == "ZONE_CHANGED" then
        EsoApi.setZoneId(e.zoneId)
        if e.zoneId ~= KA_ZONE then
            stubBoss = nil
            currentBossKey = nil
        end

    elseif et == "UNIT_ADDED" and e.unitId then
        tracker:addUnit(e)
        if e.isBoss then
            local key = KA_HINTS[e.name]
            if key and stubs[key] then
                stubBoss       = stubs[key]
                currentBossKey = key
            end
        end

    elseif et == "UNIT_REMOVED" and e.unitId then
        tracker:removeUnit(e.unitId)

    elseif et == "COMBAT_EVENT" and stubBoss and e.abilityId then
        if e.sourceUnitId and e.srcHealthMax > 0 then
            tracker:updateHealth(e.sourceUnitId, e.srcHealthCur, e.srcHealthMax)
        end
        local srcName = tracker:nameById(e.sourceUnitId) or ""
        local key     = currentBossKey

        -- Old path: count ability IDs from combatRoutes (legacy CombatHandler
        -- would have dispatched these; here we just count them).
        local bossClass = kaTrial.registry:getByKey(key)
        if bossClass and bossClass.combatRoutes and bossClass.combatRoutes[e.abilityId] then
            coverage[key].old = coverage[key].old + 1
        end

        -- New path: dispatch through EventDispatcher.
        coverage[key].new = coverage[key].new + 1
        if e.result == ACTION_RESULT_BEGIN then
            local castTime = GetAbilityCastInfo(e.abilityId)
            EventDispatcher.dispatchBeginCast(stubBoss, emptyCtx, emptyAlerts,
                castTime, false, e.sourceUnitId, e.abilityId, srcName)
        else
            EventDispatcher.dispatchCombatEvent(stubBoss, emptyCtx, emptyAlerts,
                e.result, e.abilityId, srcName)
        end

    elseif et == "EFFECT_CHANGED" and stubBoss and e.abilityId and e.changeType ~= 0 then
        local unitName = tracker:nameById(e.unitId) or ""
        local key      = currentBossKey

        local bossClass = kaTrial.registry:getByKey(key)
        if bossClass and bossClass.effectRoutes and bossClass.effectRoutes[e.abilityId] then
            coverage[key].old = coverage[key].old + 1
        end

        coverage[key].new = coverage[key].new + 1
        EventDispatcher.dispatchEffectChanged(stubBoss, emptyCtx, emptyAlerts,
            e.changeType, e.abilityId, unitName)
    end
end

-- -- Report -----------------------------------------------------------------

print("-- Coverage per boss -------------------------------------------------")
print(string.format("  %-14s  %8s  %8s", "Boss", "Old path", "New path"))
for key, counts in pairs(coverage) do
    print(string.format("  %-14s  %8d  %8d", key, counts.old, counts.new))
end

print(string.format("\n-- Unknown-event warnings (%d total) -----------------------", #dispatcherUnknowns))
if #dispatcherUnknowns == 0 then
    print("  none  (all events routed cleanly)")
else
    for _, w in ipairs(dispatcherUnknowns) do
        print(string.format("  [%-10s]  %s", w.boss, w.message))
    end
    print("\nThese IDs appear in the log but are not in combatRoutes/effectRoutes.")
    print("They are likely handled by a common module or a legacy onCombatEvent fallback.")
    print("Declare them in Boss.events or mark them IGNORE when migrating in Phase 2.")
end

local exitCode = (#dispatcherUnknowns > 0 or buildErrors > 0) and 1 or 0
print(string.format("\nExit %d", exitCode))
os.exit(exitCode)
