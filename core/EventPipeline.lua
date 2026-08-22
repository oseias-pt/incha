local EventPipeline = {}
EventPipeline.__index = EventPipeline

function EventPipeline.new(eventPrefix, handlers)
    return setmetatable({
        eventPrefix = eventPrefix,
        handlers = handlers,
        enabled = false,
    }, EventPipeline)
end

function EventPipeline:enable()
    if self.enabled then
        return
    end

    local prefix = self.eventPrefix
    local handlers = self.handlers

    if handlers.onBossesChanged then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_BOSSES_CHANGED, handlers.onBossesChanged)
    end

    if handlers.onPowerUpdate then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_POWER_UPDATE, handlers.onPowerUpdate)
        EVENT_MANAGER:AddFilterForEvent(prefix, EVENT_POWER_UPDATE, REGISTER_FILTER_POWER_TYPE, POWERTYPE_HEALTH)
        EVENT_MANAGER:AddFilterForEvent(prefix, EVENT_POWER_UPDATE, REGISTER_FILTER_UNIT_TAG_PREFIX, "boss")
    end

    if handlers.onCombatState then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_PLAYER_COMBAT_STATE, handlers.onCombatState)
    end

    if handlers.onCombatEvent then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_COMBAT_EVENT, handlers.onCombatEvent)
    end

    if handlers.onEffectChanged then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_EFFECT_CHANGED, handlers.onEffectChanged)
    end

    -- 200ms UI refresh loop — drives timer countdowns in boss modules.
    -- UnregisterForUpdate in disable() already handles cleanup unconditionally.
    if handlers.onUpdate then
        EVENT_MANAGER:RegisterForUpdate(prefix, handlers.updateInterval or 200, handlers.onUpdate)
    end

    self.enabled = true
end

function EventPipeline:disable()
    if not self.enabled then
        return
    end

    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_BOSSES_CHANGED)
    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_POWER_UPDATE)
    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_PLAYER_COMBAT_STATE)
    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_COMBAT_EVENT)
    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_EFFECT_CHANGED)
    EVENT_MANAGER:UnregisterForUpdate(self.eventPrefix)

    self.enabled = false
end

return EventPipeline
