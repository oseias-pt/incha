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

local CombatHandler = {}

-- Boss handlers receive a trimmed subset of the raw ESO args to keep their
-- signatures readable.  Extend if a future boss needs additional fields.

function CombatHandler.onCombatEvent(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.onCombatEvent then return end
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
