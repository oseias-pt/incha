local Log = require("lib.Log")

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
                Log.always("event callback: %s", tostring(err))
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
    --
    -- Wrap the per-boss handlers once here.  setActiveBoss registers the same
    -- function under ~40 namespaces per boss; wrapping inside that loop would
    -- allocate a fresh closure per ability id on every boss change.
    self.safeHandlers = {
        onCombatEventFiltered   = handlers.onCombatEventFiltered   and safe(handlers.onCombatEventFiltered),
        onDiedCombatEvent       = handlers.onDiedCombatEvent       and safe(handlers.onDiedCombatEvent),
        onLegacyCombatEvent     = handlers.onLegacyCombatEvent     and safe(handlers.onLegacyCombatEvent),
        onEffectChangedFiltered = handlers.onEffectChangedFiltered and safe(handlers.onEffectChangedFiltered),
    }

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
--- Four disjoint slices:
---   combat, per ability id   boss.events + the common module's declared set
---   combat, ACTION_RESULT_DIED   boss.onDied
---   combat, per boss.combatResults   the legacy onCombatEvent catch-all
---   effect, per ability id   boss.events effectChanged + the common module's effect set
---
--- Call with nil to tear the registrations down between bosses.
function EventPipeline:setActiveBoss(boss)
    self:clearBossFilters()
    if not boss or not self.enabled then return end

    local h = self.handlers
    local prefix = self.eventPrefix
    local combatIds, effectIds = h.abilityIdsFor(boss)
    local names = self.bossNamespaces
    local safeHandlers = self.safeHandlers

    -- Namespaces are strings ESO uses as registration keys; the (ns, event)
    -- pairs are recorded so clearBossFilters can unregister exactly what was
    -- armed.  The wrapped handler closures are built once in enable(), not
    -- once per ability id, so a boss change allocates only the namespace
    -- strings and record tables.
    local function register(ns, event, fn, filterType, filterValue)
        EVENT_MANAGER:RegisterForEvent(ns, event, fn)
        EVENT_MANAGER:AddFilterForEvent(ns, event, filterType, filterValue)
        names[#names + 1] = { ns = ns, event = event }
    end

    if safeHandlers.onCombatEventFiltered then
        for id in pairs(combatIds) do
            register(prefix .. "c" .. id, EVENT_COMBAT_EVENT,
                safeHandlers.onCombatEventFiltered, REGISTER_FILTER_ABILITY_ID, id)
        end
    end

    if safeHandlers.onDiedCombatEvent and boss.onDied then
        register(prefix .. "cDied", EVENT_COMBAT_EVENT,
            safeHandlers.onDiedCombatEvent, REGISTER_FILTER_COMBAT_RESULT, ACTION_RESULT_DIED)
    end

    -- Bosses whose catch-all guards on a combat result rather than an ability
    -- id declare that result here, so they still get a narrow registration
    -- instead of forcing an unfiltered one for the whole trial.
    if safeHandlers.onLegacyCombatEvent and boss.onCombatEvent and boss.combatResults then
        for _, result in ipairs(boss.combatResults) do
            register(prefix .. "cRes" .. result, EVENT_COMBAT_EVENT,
                safeHandlers.onLegacyCombatEvent, REGISTER_FILTER_COMBAT_RESULT, result)
        end
    end

    if safeHandlers.onEffectChangedFiltered then
        for id in pairs(effectIds) do
            register(prefix .. "e" .. id, EVENT_EFFECT_CHANGED,
                safeHandlers.onEffectChangedFiltered, REGISTER_FILTER_ABILITY_ID, id)
        end
    end
end

--- Drop every per-boss registration made by setActiveBoss.
--- Calls handlers.onClearPending (if set) so the caller can cancel any
--- in-flight timers (e.g. EventDispatcher interrupt-detection callbacks)
--- before the new boss's filters are armed.
function EventPipeline:clearBossFilters()
    local names = self.bossNamespaces
    for i = #names, 1, -1 do
        local entry = names[i]
        EVENT_MANAGER:UnregisterForEvent(entry.ns, entry.event)
        names[i] = nil
    end
    if self.handlers.onClearPending then
        self.handlers.onClearPending()
    end
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
