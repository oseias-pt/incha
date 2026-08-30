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

    -- Isolate every registered callback so a Lua error in a boss module
    -- never propagates into the ESO event system or crashes other addons.
    -- Errors are printed to chat via d() and then swallowed.
    local function safe(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                d("[Incha] " .. tostring(err))
            end
        end
    end

    if handlers.onBossesChanged then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_BOSSES_CHANGED, safe(handlers.onBossesChanged))
    end

    if handlers.onPowerUpdate then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_POWER_UPDATE, safe(handlers.onPowerUpdate))
        EVENT_MANAGER:AddFilterForEvent(prefix, EVENT_POWER_UPDATE, REGISTER_FILTER_POWER_TYPE, POWERTYPE_HEALTH)
        EVENT_MANAGER:AddFilterForEvent(prefix, EVENT_POWER_UPDATE, REGISTER_FILTER_UNIT_TAG_PREFIX, "boss")
    end

    if handlers.onCombatState then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_PLAYER_COMBAT_STATE, safe(handlers.onCombatState))
    end

    if handlers.onCombatEvent then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_COMBAT_EVENT, safe(handlers.onCombatEvent))
    end

    if handlers.onEffectChanged then
        EVENT_MANAGER:RegisterForEvent(prefix, EVENT_EFFECT_CHANGED, safe(handlers.onEffectChanged))
    end

    -- 200ms UI refresh loop  -  drives timer countdowns in boss modules.
    -- UnregisterForUpdate in disable() already handles cleanup unconditionally.
    if handlers.onUpdate then
        EVENT_MANAGER:RegisterForUpdate(prefix, handlers.updateInterval or 200, safe(handlers.onUpdate))
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

package.loaded["core.EventPipeline"] = EventPipeline
return EventPipeline
