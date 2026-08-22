--- KA combat event / effect delegation module.
---
--- Passed as options.onCombatEvent / options.onEffectChanged to Trial.create
--- in Phase 4.4, when the Factory switches from LegacyUI to Panel.
---
--- Each function receives (trial, eventCode, <esо args...>), then delegates
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

local CombatHandler = {}

-- Boss handlers receive a trimmed subset of the raw ESO args to keep their
-- signatures readable.  Extend if a future boss needs additional fields.

function CombatHandler.onCombatEvent(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.onCombatEvent then return end
    -- Phase 4.2: pass sourceUnitName / unitName so boss handlers can build
    -- CombatAlerts cast-bar captions without a separate GetUnitName() lookup.
    boss:onCombatEvent(trial.context, trial.alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
end

function CombatHandler.onEffectChanged(trial, eventCode,
        changeType, effectSlot, effectName, unitTag,
        beginTime, endTime, stackCount, iconName, buffType, effectType,
        abilityType, statusEffectType, unitName, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.onEffectChanged then return end
    boss:onEffectChanged(trial.context, trial.alerts,
        changeType, abilityId, unitTag, unitId, unitName)
end

return CombatHandler
