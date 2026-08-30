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

package.loaded["core.CombatHandler"] = CombatHandler
return CombatHandler
