local EventPipeline = {}
EventPipeline.__index = EventPipeline

function EventPipeline.new(eventPrefix, handlers)
    return setmetatable({
        eventPrefix = eventPrefix,
        handlers = handlers,
        enabled = false,
        -- {ns, event} pairs registered by setActiveBoss, torn down on the
        -- next boss change or on disable().
        bossNamespaces = {},
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

    -- EVENT_COMBAT_EVENT and EVENT_EFFECT_CHANGED are the two loudest events
    -- in the game  -  thousands per second between them in a twelve-player
    -- trial.  They are NOT registered here; setActiveBoss() registers them
    -- per ability id (and per combat result) once a boss is known, so the
    -- engine rejects everything else before it reaches Lua.  See below.
    self.safe = safe

    -- 200ms UI refresh loop  -  drives timer countdowns in boss modules.
    -- UnregisterForUpdate in disable() already handles cleanup unconditionally.
    if handlers.onUpdate then
        EVENT_MANAGER:RegisterForUpdate(prefix, handlers.updateInterval or 200, safe(handlers.onUpdate))
    end

    self.enabled = true
end

--- Register the combat / effect events for `boss`, filtered so the engine
--- discards everything the boss cannot act on.
---
--- ESO applies filters per (namespace, event) pair, so one ability id needs
--- one namespace.  A boss routes at most ~43 abilities, and only one trial is
--- active at a time, so the registration count stays small while the rejected
--- volume  -  every damage, heal, miss, block and dodge event in a
--- twelve-player raid  -  never crosses into Lua at all.
---
--- Four disjoint slices, matching the four CombatHandler entry points:
---   combat, per ability id   routes + the common module's declared set
---   combat, ACTION_RESULT_DIED   boss.onDied
---   combat, per boss.combatResults   the legacy onCombatEvent catch-all
---   effect, per ability id   effectRoutes + the common module's effect set
---
--- Call with nil to tear the registrations down between bosses.
function EventPipeline:setActiveBoss(boss)
    self:clearBossFilters()
    if not boss or not self.enabled then return end

    local h = self.handlers
    local prefix, safe = self.eventPrefix, self.safe
    local combatIds, effectIds = h.abilityIdsFor(boss)
    local names = self.bossNamespaces

    local function register(ns, event, fn, filterType, filterValue)
        EVENT_MANAGER:RegisterForEvent(ns, event, safe(fn))
        EVENT_MANAGER:AddFilterForEvent(ns, event, filterType, filterValue)
        names[#names + 1] = { ns = ns, event = event }
    end

    if h.onCombatEventFiltered then
        for id in pairs(combatIds) do
            register(prefix .. "c" .. id, EVENT_COMBAT_EVENT,
                h.onCombatEventFiltered, REGISTER_FILTER_ABILITY_ID, id)
        end
    end

    if h.onDiedCombatEvent and boss.onDied then
        register(prefix .. "cDied", EVENT_COMBAT_EVENT,
            h.onDiedCombatEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DIED)
    end

    -- Bosses whose catch-all guards on a combat result rather than an ability
    -- id declare that result here, so they still get a narrow registration
    -- instead of forcing an unfiltered one for the whole trial.
    if h.onLegacyCombatEvent and boss.onCombatEvent and boss.combatResults then
        for _, result in ipairs(boss.combatResults) do
            register(prefix .. "cRes" .. result, EVENT_COMBAT_EVENT,
                h.onLegacyCombatEvent, REGISTER_FILTER_COMBAT_RESULT, result)
        end
    end

    if h.onEffectChangedFiltered then
        for id in pairs(effectIds) do
            register(prefix .. "e" .. id, EVENT_EFFECT_CHANGED,
                h.onEffectChangedFiltered, REGISTER_FILTER_ABILITY_ID, id)
        end
    end
end

--- Drop every per-boss registration made by setActiveBoss.
function EventPipeline:clearBossFilters()
    for _, entry in ipairs(self.bossNamespaces) do
        EVENT_MANAGER:UnregisterForEvent(entry.ns, entry.event)
    end
    self.bossNamespaces = {}
end

function EventPipeline:disable()
    if not self.enabled then
        return
    end

    self:clearBossFilters()

    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_BOSSES_CHANGED)
    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_POWER_UPDATE)
    EVENT_MANAGER:UnregisterForEvent(self.eventPrefix, EVENT_PLAYER_COMBAT_STATE)
    EVENT_MANAGER:UnregisterForUpdate(self.eventPrefix)

    self.enabled = false
end

package.loaded["core.EventPipeline"] = EventPipeline
return EventPipeline
