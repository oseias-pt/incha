--- Shared combat event / effect delegation module.
---
--- Passed as options.onCombatEvent / options.onEffectChanged to Trial.create
--- by every trial Factory.  A single copy here replaces the nine identical
--- per-trial copies that previously lived in trial/xx/CombatHandler.lua.
---
--- Each function receives (trial, eventCode, <eso args...>), then delegates
--- to the currently active boss's handler  -  if it has one.
---
--- ESO EVENT_COMBAT_EVENT signature (modern API):
---   eventCode, result, isError, abilityName, abilityGraphic, hitStatus,
---   unitTag, unitName, sourceUnitTag, sourceUnitName,
---   sourceUnitId, unitId, abilityId, overflow
---
--- ESO EVENT_EFFECT_CHANGED signature:
---   eventCode, changeType, effectSlot, effectName, unitTag,
---   beginTime, endTime, stackCount, iconName, buffType, effectType,
---   abilityType, statusEffectType, unitName, unitId, abilityId, sourceType
---
--- C3 / D6 / D7: Boss classes declare pure routing tables instead of monolithic
--- handlers.  See dispatchCombatEntry / dispatchEffectEntry below for the two
--- entry shapes (plain function and D6 filter shorthand).
---
---   Boss.combatRoutes = { [abilityId] = fn | { result=CONST, fn=fn }, ... }
---   Boss.effectRoutes = { [abilityId] = fn | { changeType=CONST, fn=fn }, ... }
---   Boss.onDied = function(self, context, alerts,
---                          unitTag, sourceUnitTag, sourceUnitId, unitId,
---                          sourceUnitName, unitName) ... end
---
---   Boss.common = module   -- optional; must expose:
---       .handle(alerts, result, abilityId, unitTag, sourceUnitName) -> bool
---       .handleEffect(alerts, changeType, abilityId, unitTag) -> bool  (optional)
---
--- Legacy Boss.onCombatEvent / Boss.onEffectChanged remain as fallback for
--- bosses not yet migrated to routing tables.  A boss may have routing tables
--- for some abilities and a fallback method for catch-all cases (e.g. result-
--- only guards with no abilityId filter); the fallback fires only when no
--- combatRoutes entry matches.

local CombatHandler = {}

-- -- D8: dispatch helpers --------------------------------------------------
-- Extracted from the identical type(entry) branches in onCombatEvent and
-- onEffectChanged.  Each helper calls the plain function or, for a D6
-- shorthand table, pre-checks the filter value before calling fn.

local function dispatchCombatEntry(boss, context, alerts, entry, result,
        abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
    if type(entry) == "table" then
        -- { result = CONST, fn = fn }: pre-filter; fn does not receive result.
        if result == entry.result then
            entry.fn(boss, context, alerts,
                abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
                sourceUnitName, unitName)
        end
    else
        entry(boss, context, alerts,
            result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
            sourceUnitName, unitName)
    end
end

local function dispatchEffectEntry(boss, context, alerts, entry, changeType,
        abilityId, unitTag, unitId, unitName, stackCount)
    if type(entry) == "table" then
        -- { changeType = CONST, fn = fn }: pre-filter; fn does not receive changeType.
        if changeType == entry.changeType then
            entry.fn(boss, context, alerts,
                abilityId, unitTag, unitId, unitName, stackCount)
        end
    else
        entry(boss, context, alerts,
            changeType, abilityId, unitTag, unitId, unitName, stackCount)
    end
end

-- Boss handlers receive a trimmed subset of the raw ESO args to keep their
-- signatures readable.  Extend if a future boss needs additional fields.

--- Full dispatcher: common -> DIED -> routes -> legacy, in that order, with
--- each stage short-circuiting the next.
---
--- EventPipeline no longer registers this against an unfiltered
--- EVENT_COMBAT_EVENT; it registers the four narrow entry points below
--- against separate ability- and result-filtered registrations instead, which
--- between them cover exactly the same events.  This function is kept as the
--- reference definition of the ordering, and is what the offline log-replay
--- harness drives (the harness has no ESO event filtering to reproduce).
function CombatHandler.onCombatEvent(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss then return end
    local context, alerts = trial.context, trial.alerts

    -- 1. Shared common handler (SunspireCommon, RockgroveCommon, DreadsailCommon, ...)  -
    --    runs before boss routing; returning true short-circuits everything.
    if boss.common and boss.common.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    -- 2. ACTION_RESULT_DIED has no meaningful abilityId filter; route to
    --    boss.onDied if declared, then stop (routing table does not run).
    if result == ACTION_RESULT_DIED then
        if boss.onDied then
            boss:onDied(context, alerts,
                unitTag, sourceUnitTag, sourceUnitId, unitId,
                sourceUnitName, unitName)
        end
        return
    end

    -- 3. Route by abilityId via combatRoutes table (O(1) lookup).
    --    Entry may be a plain function or a D6 filter shorthand table.
    if boss.combatRoutes then
        local entry = boss.combatRoutes[abilityId]
        if entry then
            dispatchCombatEntry(boss, context, alerts, entry, result,
                abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
                sourceUnitName, unitName)
            return
        end
    end

    -- 4. Legacy fallback for bosses not yet migrated to routing tables, or
    --    for catch-all cases (guards on result only, no abilityId filter).
    if boss.onCombatEvent then
        boss:onCombatEvent(context, alerts,
            result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
            sourceUnitName, unitName)
    end
end

-- -- Narrow entry points for filtered registrations -------------------------
-- Each is bound to a registration that admits a disjoint slice of the event
-- stream, so every event is handled exactly once and the stage ordering above
-- is preserved without any stage having to inspect the others:
--
--   common  <- ability-filtered on boss.common.combatAbilityIds
--   died    <- result-filtered on ACTION_RESULT_DIED
--   routed  <- ability-filtered on keys(boss.combatRoutes)
--   legacy  <- result-filtered on boss.combatResults
--
-- The common and routed sets are disjoint (asserted by test/checks/filters.lua),
-- which is what makes "common short-circuits routes" hold without the routed
-- path having to re-run the common handler.

--- Ability-filtered combat events: the common handler and the routing table.
--- One handler serves both because their ability sets are disjoint (asserted
--- by test/checks/filters.lua), so ordering between them cannot matter  -  at
--- most one of the two can claim any given id.
function CombatHandler.onCombatEventFiltered(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss then return end

    -- DIED takes precedence over the routing table, as in the full
    -- dispatcher.  It has its own result-filtered registration, so this
    -- branch only has to suppress the route.
    if result == ACTION_RESULT_DIED then return end

    local context, alerts = trial.context, trial.alerts

    if boss.common and boss.common.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    local entry = boss.combatRoutes and boss.combatRoutes[abilityId]
    if not entry then return end
    dispatchCombatEntry(boss, context, alerts, entry, result,
        abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
end

function CombatHandler.onDiedCombatEvent(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.onDied then return end
    boss:onDied(trial.context, trial.alerts,
        unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
end

function CombatHandler.onLegacyCombatEvent(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.onCombatEvent then return end

    -- Preserve the full dispatcher's exclusivity: the legacy catch-all only
    -- ran when no route matched and the result was not DIED.  Without these
    -- guards a result-filtered registration could double-dispatch an event
    -- the routed registration already handled.
    if result == ACTION_RESULT_DIED then return end
    if boss.combatRoutes and boss.combatRoutes[abilityId] then return end

    boss:onCombatEvent(trial.context, trial.alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
end

function CombatHandler.onEffectChanged(trial, eventCode,
        changeType, effectSlot, effectName, unitTag,
        beginTime, endTime, stackCount, iconName, buffType, effectType,
        abilityType, statusEffectType, unitName, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss then return end
    local context, alerts = trial.context, trial.alerts

    -- 1. Shared common effect handler (optional; not all common modules expose it).
    --    stackCount is passed as a 5th arg so common modules can read debuff stacks
    --    (e.g. OsseinCageCommon Caustic Carrion) without routing through effectRoutes.
    if boss.common and boss.common.handleEffect
    and boss.common.handleEffect(alerts, changeType, abilityId, unitTag, stackCount) then
        return
    end

    -- 2. Route by abilityId via effectRoutes table.
    --    Entry may be a plain function or a D6 filter shorthand table.
    if boss.effectRoutes then
        local entry = boss.effectRoutes[abilityId]
        if entry then
            dispatchEffectEntry(boss, context, alerts, entry, changeType,
                abilityId, unitTag, unitId, unitName, stackCount)
            return
        end
    end

    -- 3. Legacy fallback.  stackCount added here so existing onEffectChanged
    --    methods that declare it (e.g. Lylanar) receive a real value.
    if boss.onEffectChanged then
        boss:onEffectChanged(context, alerts,
            changeType, abilityId, unitTag, unitId, unitName, stackCount)
    end
end

-- -- Narrow entry points, effect side ---------------------------------------
-- Same split as above: common gets its own ability-filtered registration
-- (boss.common.effectAbilityIds), routes get theirs (keys(boss.effectRoutes)),
-- and the two sets are disjoint.  There is no effect-side legacy result
-- filter because boss.onEffectChanged fallbacks are keyed by ability too.

function CombatHandler.onEffectChangedFiltered(trial, eventCode,
        changeType, effectSlot, effectName, unitTag,
        beginTime, endTime, stackCount, iconName, buffType, effectType,
        abilityType, statusEffectType, unitName, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss then return end

    if boss.common and boss.common.handleEffect
    and boss.common.handleEffect(trial.alerts, changeType, abilityId, unitTag, stackCount) then
        return
    end

    local entry = boss.effectRoutes and boss.effectRoutes[abilityId]
    if entry then
        dispatchEffectEntry(boss, trial.context, trial.alerts, entry, changeType,
            abilityId, unitTag, unitId, unitName, stackCount)
        return
    end

    if boss.onEffectChanged then
        boss:onEffectChanged(trial.context, trial.alerts,
            changeType, abilityId, unitTag, unitId, unitName, stackCount)
    end
end

--- Ability ids EventPipeline must register for a boss, as two sets.
--- Union of the boss's own routing-table keys and its common module's
--- declared sets.  Returned as sets so the caller can register one filtered
--- handler per id without deduplicating.
function CombatHandler.abilityIdsFor(boss)
    local combat, effect = {}, {}
    if not boss then return combat, effect end

    for id in pairs(boss.combatRoutes or {}) do combat[id] = true end
    for id in pairs(boss.effectRoutes or {}) do effect[id] = true end

    local common = boss.common
    if common then
        for id in pairs(common.combatAbilityIds or {}) do combat[id] = true end
        for id in pairs(common.effectAbilityIds or {}) do effect[id] = true end
    end

    return combat, effect
end

package.loaded["core.CombatHandler"] = CombatHandler
return CombatHandler
