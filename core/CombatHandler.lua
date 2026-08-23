--- Shared combat event / effect delegation module.
---
--- Passed as options.onCombatEvent / options.onEffectChanged to Trial.create
--- by every trial Factory.  A single copy here replaces the nine identical
--- per-trial copies that previously lived in trial/xx/CombatHandler.lua.
---
--- Each function receives (trial, eventCode, <eso args...>), then delegates
--- to the currently active boss's handler — if it has one.
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
--- C3: Boss classes may now declare routing tables instead of monolithic handlers:
---
---   Boss.combatRoutes = {
---       [abilityId] = function(self, context, alerts, result, abilityId,
---                              unitTag, sourceUnitTag, sourceUnitId, unitId,
---                              sourceUnitName, unitName) ... end,
---   }
---   Boss.effectRoutes = {
---       [abilityId] = function(self, context, alerts, changeType, abilityId,
---                              unitTag, unitId, unitName, stackCount) ... end,
---   }
---   Boss.onDied = function(self, context, alerts,
---                          unitTag, sourceUnitTag, sourceUnitId, unitId,
---                          sourceUnitName, unitName) ... end
---
---   Boss.common = module   -- optional; must expose:
---       .handle(alerts, result, abilityId, unitTag, sourceUnitName) → bool
---       .handleEffect(alerts, changeType, abilityId, unitTag) → bool  (optional)
---
--- Legacy Boss.onCombatEvent / Boss.onEffectChanged remain as fallback for
--- bosses not yet migrated to routing tables.  A boss may have routing tables
--- for some abilities and a fallback method for catch-all cases (e.g. result-
--- only guards with no abilityId filter); the fallback fires only when no
--- combatRoutes entry matches.

local CombatHandler = {}

-- Boss handlers receive a trimmed subset of the raw ESO args to keep their
-- signatures readable.  Extend if a future boss needs additional fields.

function CombatHandler.onCombatEvent(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss then return end
    local context, alerts = trial.context, trial.alerts

    -- 1. Shared common handler (e.g. SunspireCommon, RockgroveCommon) —
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
    --    Routing functions receive the same args as the legacy onCombatEvent.
    if boss.combatRoutes then
        local fn = boss.combatRoutes[abilityId]
        if fn then
            fn(boss, context, alerts,
               result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
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
    if boss.common and boss.common.handleEffect
    and boss.common.handleEffect(alerts, changeType, abilityId, unitTag) then
        return
    end

    -- 2. Route by abilityId via effectRoutes table.
    --    stackCount is now forwarded so effect handlers can read it directly.
    if boss.effectRoutes then
        local fn = boss.effectRoutes[abilityId]
        if fn then
            fn(boss, context, alerts,
               changeType, abilityId, unitTag, unitId, unitName, stackCount)
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

return CombatHandler
