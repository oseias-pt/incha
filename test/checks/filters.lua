--- test/checks/filters.lua  -  invariants for ability-filtered event registration.
---
--- EventPipeline registers EVENT_COMBAT_EVENT and EVENT_EFFECT_CHANGED per
--- ability id rather than unfiltered, so an ability the engine was not told
--- about never reaches Lua at all.  That makes two properties load-bearing:
---
---   1. DISJOINT SETS.  A boss's routing-table ids and its common module's
---      declared ids must not overlap.  The full dispatcher ran the common
---      handler first and let it short-circuit the routes; the filtered
---      handler relies on at most one of the two claiming any given id, so an
---      overlap would silently change which one wins.
---
---   2. A DECLARED SET EXISTS.  A common module that exposes handle() or
---      handleEffect() must declare the matching ability set, or nothing is
---      registered for it and the whole shared-mechanic path goes dark.
---
---   3. A CATCH-ALL IS REACHABLE.  A boss with an onCombatEvent fallback
---      guards on a combat result rather than an ability id, so it needs
---      boss.combatResults for EventPipeline to give it a registration.
---
--- What this check deliberately does NOT do: probe the handlers to discover
--- which abilities they can claim.  Branches gated on IsUnitPlayer,
--- GetPlayerRoles and similar are unreachable under the offline stubs, so a
--- probe reports far fewer ids than the module really handles and would give
--- false confidence.  The gate at the top of each handler is what ties the
--- declared set to dispatch: an id missing from the set is neither registered
--- NOR dispatched, so the failure mode is a dead branch rather than a
--- silently-dropped event.  Dead branches are what the log-replay coverage
--- pass in test/run_log.lua is for.
---
--- Usage (from the repository root):
---   luajit test/checks/filters.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
require("harness.eso_api")

local TRIALS = { "ka", "ss", "rg", "dsr", "as", "cr", "se", "lc", "oc" }

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

local checkedCommons = {}

for _, id in ipairs(TRIALS) do
    local ok, trial = pcall(require, "trial." .. id .. ".Factory")
    if not ok or not trial then
        fail("LOAD  trial.%s.Factory  %s", id, tostring(trial))
    else
        for _, boss in ipairs(trial.registry.bosses) do
            local common = boss.common
            if common then
                local cIds = common.combatAbilityIds or {}
                local eIds = common.effectAbilityIds or {}

                -- 1. Disjointness against this boss's routing tables.
                for abilityId in pairs(boss.combatRoutes or {}) do
                    if cIds[abilityId] then
                        fail("OVERLAP  %s/%s  combat ability %d is in BOTH the "
                             .. "routing table and the common module's set",
                             id, tostring(boss.key), abilityId)
                    end
                end
                for abilityId in pairs(boss.effectRoutes or {}) do
                    if eIds[abilityId] then
                        fail("OVERLAP  %s/%s  effect ability %d is in BOTH the "
                             .. "routing table and the common module's set",
                             id, tostring(boss.key), abilityId)
                    end
                end

                -- 2. The declared set must actually gate the handler, checked
                --    once per common module rather than once per boss.
                if not checkedCommons[common] then
                    checkedCommons[common] = true

                    if common.handle and next(cIds) == nil then
                        fail("NO SET  %s/%s  common declares handle() but no "
                             .. "combatAbilityIds  -  nothing will be registered",
                             id, tostring(boss.key))
                    end
                    if common.handleEffect and next(eIds) == nil then
                        fail("NO SET  %s/%s  common declares handleEffect() but "
                             .. "no effectAbilityIds", id, tostring(boss.key))
                    end

                end
            end

            -- 3. A boss with a catch-all handler must declare the combat
            --    results it guards on, or it gets no registration at all.
            if boss.onCombatEvent and not boss.combatResults then
                fail("NO RESULTS  %s/%s  declares onCombatEvent but no "
                     .. "combatResults  -  the catch-all can never fire",
                     id, tostring(boss.key))
            end
            if boss.onEffectChanged and next(boss.effectRoutes or {}) == nil then
                fail("NO ROUTES  %s/%s  declares onEffectChanged but no "
                     .. "effectRoutes  -  nothing registers it",
                     id, tostring(boss.key))
            end
        end
    end
end

if findings == 0 then
    print("filters: clean")
else
    print(string.format("filters: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
