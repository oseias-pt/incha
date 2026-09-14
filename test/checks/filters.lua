--- test/checks/filters.lua  -  invariants for ability-filtered event registration.
---
--- EventPipeline registers EVENT_COMBAT_EVENT and EVENT_EFFECT_CHANGED per
--- ability id rather than unfiltered, so an ability the engine was not told
--- about never reaches Lua at all.  That makes these properties load-bearing:
---
---   1. SHARED MECHANICS ARE MERGED.  A trial's <X>Common module exposes
---      `beginCastEntries` and/or `effectChangedEntries`; every boss in that
---      trial must copy those entries into its own events buckets (see
---      trial/rg/boss/*.lua for the pattern).  A common module that is loaded
---      but never merged is silent for the whole trial — no registration, no
---      dispatch, no warning in game.  That is exactly what happened to
---      LCCommon before this check existed.
---
---   2. A CATCH-ALL IS REACHABLE.  A boss with an onCombatEvent fallback
---      guards on a combat result rather than an ability id, so it needs
---      boss.combatResults for EventPipeline to give it a registration.
---
---   3. NO DUPLICATE KEYS in one routing / schema table (source scan below).
---
--- What this check deliberately does NOT do: probe the handlers to discover
--- which abilities they can claim.  Branches gated on IsUnitPlayer,
--- GetPlayerRoles and similar are unreachable under the offline stubs, so a
--- probe reports far fewer ids than the module really handles and would give
--- false confidence.  Dead branches are what the log-replay coverage pass in
--- test/run_log.lua is for.
---
--- Usage (from the repository root):
---   luajit test/checks/filters.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
require("harness.eso_api")

local TRIALS = { "ka", "ss", "rg", "dsr", "as", "cr", "se", "lc", "oc" }

-- trial id -> module path of its shared-mechanics module (nil = none).
local COMMON_MODULES = {
    ss  = "trial.ss.SunspireCommon",
    rg  = "trial.rg.RockgroveCommon",
    dsr = "trial.dsr.DreadsailCommon",
    lc  = "trial.lc.LCCommon",
    oc  = "trial.oc.OsseinCageCommon",
}

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

-- Every (abilityId, entry) pair in `expected` must be present, by identity,
-- in `bucket` (the boss's merged table).  Identity rather than equality:
-- the boss must reference the shared entry table, so a later fix to the
-- common handler reaches every boss.
local function assertMerged(trialId, bossKey, bucketPath, bucket, expected)
    for abilityId, entry in pairs(expected or {}) do
        local got = bucket and bucket[abilityId]
        if got == nil then
            fail("NOT MERGED  %s/%s  %s lacks common ability %d  -  the shared "
                 .. "handler is never registered for this boss",
                 trialId, bossKey, bucketPath, abilityId)
        elseif got ~= entry then
            fail("SHADOWED  %s/%s  %s[%d] is a boss-local entry that hides the "
                 .. "common module's handler", trialId, bossKey, bucketPath, abilityId)
        end
    end
end

for _, id in ipairs(TRIALS) do
    local ok, trial = pcall(require, "trial." .. id .. ".Factory")
    if not ok or not trial then
        fail("LOAD  trial.%s.Factory  %s", id, tostring(trial))
    else
        local common = COMMON_MODULES[id] and package.loaded[COMMON_MODULES[id]]
        if COMMON_MODULES[id] and not common then
            fail("LOAD  %s  common module %s is not loaded by the Factory",
                 id, COMMON_MODULES[id])
        end

        for _, boss in ipairs(trial.registry.bosses) do
            local e = boss.events or {}

            -- 1. Shared mechanics must be merged into every boss of the trial.
            if common then
                local bc = e.beginCast or {}
                assertMerged(id, boss.key, "beginCast.instant", bc.instant, common.beginCastEntries)
                assertMerged(id, boss.key, "beginCast.started", bc.started, common.beginCastEntries)
                local ece = common.effectChangedEntries
                if ece then
                    local ec = e.effectChanged or {}
                    assertMerged(id, boss.key, "effectChanged.gained",  ec.gained,  ece.gained)
                    assertMerged(id, boss.key, "effectChanged.faded",   ec.faded,   ece.faded)
                    assertMerged(id, boss.key, "effectChanged.updated", ec.updated, ece.updated)
                end
            end

            -- 2. A boss with a catch-all handler must declare the combat
            --    results it guards on, or it gets no registration at all.
            if boss.onCombatEvent and not boss.combatResults then
                fail("NO RESULTS  %s/%s  declares onCombatEvent but no "
                     .. "combatResults  -  the catch-all can never fire",
                     id, tostring(boss.key))
            end
        end
    end
end

-- -- 3. No duplicate ability ids inside one routing table --------------------
--
-- This has to be a SOURCE scan, not a runtime one.  A Lua table constructor
-- with the same key twice keeps the last entry and discards the first with no
-- error, so by the time the module is loaded the duplicate is already gone and
-- nothing can observe it.  The result is a handler that was written, reviewed
-- and registered, and simply never runs.
--
-- Same failure mode the string table had: eight shadowed keys shipped before
-- anything looked for them.
--
-- Keys are matched as written (`[SOME_CONSTANT]` or `[123456]`), so two
-- differently-named constants holding the same id are not caught here -
-- registration would still work for both, and the routes check above covers
-- whether an id is claimed twice across boss and common tables.

local ROUTE_TABLES = { "stateSchema" }

-- Discover boss source files from the manifest (cross-platform; avoids
-- Unix-only io.popen('find ...')).  Matches the approach in state-reset.lua.
local function bossSourceFiles()
    local files = {}
    local mf = io.open("incha.txt", "r")
    if mf then
        for line in mf:read("*a"):gmatch("[^\r\n]+") do
            local entry = line:match("^%s*(trial/[%w_]+/boss/[%w_]+%.lua)%s*$")
            if entry then files[#files + 1] = entry end
        end
        mf:close()
    end
    table.sort(files)
    return files
end

for _, path in ipairs(bossSourceFiles()) do
    local f = io.open(path, "r")
    if f then
        local current, seen, lineNo = nil, nil, 0
        for line in (f:read("*a") .. "\n"):gmatch("([^\n]*)\n") do
            lineNo = lineNo + 1

            if not current then
                for _, name in ipairs(ROUTE_TABLES) do
                    if line:match("%." .. name .. "%s*=%s*{") then
                        current, seen = name, {}
                        break
                    end
                end
            elseif line:match("^}") then
                current = nil
            else
                -- `[KEY] =` for routes, `key =` for stateSchema.
                local key = line:match("^%s*%[%s*([%w_]+)%s*%]%s*=")
                          or line:match("^%s*([%w_]+)%s*=")
                if key then
                    if seen[key] then
                        fail("DUPLICATE  %s:%d  %s already lists %s at line %d  -  "
                             .. "Lua keeps the last, the earlier entry never runs",
                             path, lineNo, current, key, seen[key])
                    else
                        seen[key] = lineNo
                    end
                end
            end
        end
        f:close()
    end
end

if findings == 0 then
    print("filters: clean")
else
    print(string.format("filters: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
