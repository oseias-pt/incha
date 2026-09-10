--- core/EventDispatcher.lua  -  Type-driven event dispatcher.
---
--- Ingests a boss's `events` table at load time (EventDispatcher.build),
--- builds O(1) lookups, and exposes three entry points — one per ESO event
--- class — that EventPipeline calls in parallel to the old CombatHandler
--- (Phase 1.3 parallel mode) and exclusively once a trial is cut over.
---
--- Boss event table shape (see .plan/event-dispatch-migration.md for full spec):
---
---   Boss.events = {
---     beginCast    = { instant={}, started={}, executed={}, interrupted={} },
---     effectChanged = { gained={},  faded={},   updated={} },
---     combatEvent  = { damage={},  dodged={},  blocked={},  other={} },
---   }
---
---   Each leaf bucket maps abilityId -> { type = AlertTypes.X, ... }
---
--- Entry fields by type:
---   DODGE / BLOCK / DEBUFF  : text, dur, color
---   INTERRUPT               : text, dur, color
---   CAST_BAR                : text, dur, durMax (optional, defaults to dur), color
---   TIMER_RESET             : timer (string key on boss)
---   IGNORE                  : (none)
---   CUSTOM                  : fn = function(boss, context, alerts, abilityId, sourceUnitName, ...)
---
---   started entries may also carry: noExecute = true
---   (signals that this ability never fires a "cast completed" T event —
---    the dispatcher skips arming the interrupted timer for it)

local AlertTypes = require("core.AlertTypes")
local CA         = require("external-api.CombatAlerts")

local EventDispatcher = {}

-- -- Layer-2 routing tables -------------------------------------------------
-- Built at module load time (ESO globals are set before addon modules run).
-- O(1) dispatch from a raw ESO constant to the sub-type bucket name.

local _effectBucket = {
    [EFFECT_RESULT_GAINED]  = "gained",
    [EFFECT_RESULT_FADED]   = "faded",
    [EFFECT_RESULT_UPDATED] = "updated",
}

-- DAMAGE and CRITICAL_DAMAGE both route to the "damage" bucket.
-- Unknown results fall back to "other" at call time (see dispatchCombatEvent).
local _combatBucket = {
    [ACTION_RESULT_DAMAGE]          = "damage",
    [ACTION_RESULT_CRITICAL_DAMAGE] = "damage",
    [ACTION_RESULT_DODGED]          = "dodged",
    [ACTION_RESULT_BLOCKED_DAMAGE]  = "blocked",
}

--- Controlled by EventPipeline (Phase 1.3).
--- When true, all CA calls are suppressed; unknown-event warnings still fire.
--- Defaults to true so the dispatcher is safe to build before Phase 1.3 wires it in.
EventDispatcher.silenced = true

-- -- Pending-cast registry ---------------------------------------------------
-- Tracks in-flight delayed casts to detect interrupts when no T event arrives.
-- Key  : tostring(sourceUnitId) .. ":" .. tostring(abilityId)
-- Value: { handle = zo_callLater handle }
--
-- The key includes sourceUnitId so that two enemies casting the same ability
-- simultaneously (e.g. Infuser trash in Falgravn) each get their own slot.
local _pending = {}

local function pendingKey(sourceUnitId, abilityId)
    return tostring(sourceUnitId) .. ":" .. tostring(abilityId)
end

local function cancelPending(key)
    local p = _pending[key]
    if p then
        if p.handle then zo_removeCallLater(p.handle) end
        _pending[key] = nil
    end
end

-- -- Logging -----------------------------------------------------------------

local function warnUnknown(subPath, abilityId)
    d("[Incha/Dispatcher] unknown ability " .. tostring(abilityId) .. " in " .. subPath)
end

-- -- Standard type handlers --------------------------------------------------
-- runEntry is the single dispatch point from all three entry functions.
-- abilityId and sourceUnitName are always available; remaining varargs are
-- event-specific and passed through to CUSTOM handlers unchanged.

local function runEntry(entry, boss, context, alerts, abilityId, sourceUnitName, ...)
    local t = entry.type

    if t == AlertTypes.IGNORE then
        return

    elseif t == AlertTypes.CUSTOM then
        if entry.fn then
            entry.fn(boss, context, alerts, abilityId, sourceUnitName, ...)
        end
        return

    elseif t == AlertTypes.TIMER_RESET then
        local timer = entry.timer and boss[entry.timer]
        if timer and timer.reset then timer:reset() end
        return
    end

    -- All remaining types produce CA output — suppressed in parallel mode.
    if EventDispatcher.silenced then return end

    if t == AlertTypes.DODGE then
        return CA.ranged(abilityId, entry.text or sourceUnitName or "", entry.dur or 3000, entry.color)

    elseif t == AlertTypes.BLOCK then
        return CA.ranged(abilityId, entry.text or sourceUnitName or "", entry.dur or 3000, entry.color)

    elseif t == AlertTypes.DEBUFF then
        return CA.ranged(abilityId, entry.text or sourceUnitName or "", entry.dur or 3000, entry.color)

    elseif t == AlertTypes.INTERRUPT then
        return CA.interrupt(abilityId, entry.text or sourceUnitName or "", entry.dur or 2000, entry.color)

    elseif t == AlertTypes.CAST_BAR then
        local dur = entry.dur or 3000
        return CA.bar(abilityId, entry.text or "", dur, entry.durMax or dur, entry.color)
    end
end

local function lookupAndRun(bucket, subPath, boss, context, alerts, abilityId, sourceUnitName, ...)
    if not bucket then return end
    local entry = bucket[abilityId]
    if entry == nil then
        warnUnknown(subPath, abilityId)
        return
    end
    return runEntry(entry, boss, context, alerts, abilityId, sourceUnitName, ...)
end

-- -- Dispatch entry points ---------------------------------------------------

--- Dispatch a BEGIN_CAST event.
--- castTime : ms (0 for instant abilities)
--- didFire  : false = cast started (F); true = cast completed (T)
--- sourceUnitId, abilityId: from the ESO event
--- sourceUnitName: display name used as CA bar label
function EventDispatcher.dispatchBeginCast(boss, context, alerts,
        castTime, didFire, sourceUnitId, abilityId, sourceUnitName, ...)
    if not boss.events or not boss.events.beginCast then return end
    local bc  = boss.events.beginCast
    local key = pendingKey(sourceUnitId, abilityId)

    if didFire then
        -- T event: cast completed — cancel the interrupted timer, run executed.
        cancelPending(key)
        lookupAndRun(bc.executed, "beginCast.executed",
            boss, context, alerts, abilityId, sourceUnitName, ...)

    elseif castTime == 0 then
        -- F + castTime=0: instant — fires immediately, no timer needed.
        lookupAndRun(bc.instant, "beginCast.instant",
            boss, context, alerts, abilityId, sourceUnitName, ...)

    else
        -- F + castTime>0: cast started — run started handler, arm interrupted timer.
        lookupAndRun(bc.started, "beginCast.started",
            boss, context, alerts, abilityId, sourceUnitName, ...)

        -- noExecute = true: ability is scripted never to fire a T event (e.g. a
        -- boss cast that is always interrupted by design).  Skip the timer so we
        -- don't emit spurious interrupt events every castTime ms.
        local startedEntry = bc.started and bc.started[abilityId]
        if startedEntry and startedEntry.noExecute then return end

        -- Capture the interrupted entry and boss state now; the timer callback
        -- closes over these rather than re-looking them up after a potential
        -- boss change.
        local interruptedEntry = bc.interrupted and bc.interrupted[abilityId]
        local capturedBoss     = boss
        local capturedContext  = context
        local capturedAlerts   = alerts

        local handle
        handle = zo_callLater(function()
            -- Guard against a T event that arrived and cancelled us between
            -- the timer firing and the callback running.
            local p = _pending[key]
            if p and p.handle == handle then
                _pending[key] = nil
                if interruptedEntry then
                    runEntry(interruptedEntry, capturedBoss, capturedContext, capturedAlerts,
                        abilityId, sourceUnitName)
                end
            end
        end, castTime)

        _pending[key] = { handle = handle }
    end
end

--- Dispatch an EVENT_EFFECT_CHANGED event on a registered ability.
--- changeType: EFFECT_RESULT_GAINED | EFFECT_RESULT_FADED | EFFECT_RESULT_UPDATED
function EventDispatcher.dispatchEffectChanged(boss, context, alerts,
        changeType, abilityId, sourceUnitName, ...)
    if not boss.events or not boss.events.effectChanged then return end
    local bucketName = _effectBucket[changeType]
    if not bucketName then return end
    local ec = boss.events.effectChanged
    lookupAndRun(ec[bucketName], "effectChanged." .. bucketName,
        boss, context, alerts, abilityId, sourceUnitName, ...)
end

--- Dispatch an EVENT_COMBAT_EVENT (non-BEGIN_CAST result) on a registered ability.
--- result: one of the ACTION_RESULT_* constants (DAMAGE, DODGED, BLOCKED_DAMAGE, …)
--- Unknown results fall through to the "other" bucket.
function EventDispatcher.dispatchCombatEvent(boss, context, alerts,
        result, abilityId, sourceUnitName, ...)
    if not boss.events or not boss.events.combatEvent then return end
    local bucketName = _combatBucket[result] or "other"
    local ce = boss.events.combatEvent
    lookupAndRun(ce[bucketName], "combatEvent." .. bucketName,
        boss, context, alerts, abilityId, sourceUnitName, ...)
end

-- -- Load-time validation ---------------------------------------------------

--- Validate a boss's `events` table at load time.
--- Call at the bottom of each boss file: EventDispatcher.build(Boss)
--- Asserts on unknown alert types or malformed CUSTOM/TIMER_RESET entries.
--- Emits a console warning for any sub-type bucket that is declared but empty.
function EventDispatcher.build(boss)
    assert(boss.events,
        "EventDispatcher.build: boss.events is nil (" .. tostring(boss.key or boss) .. ")")

    local function validateBucket(bucket, path)
        if not bucket then return end
        local empty = true
        for abilityId, entry in pairs(bucket) do
            empty = false
            assert(type(entry) == "table",
                "EventDispatcher.build: entry for ability " .. tostring(abilityId)
                .. " in " .. path .. " must be a table, got " .. type(entry))
            assert(AlertTypes.isValid(entry.type),
                "EventDispatcher.build: unknown type '" .. tostring(entry.type)
                .. "' for ability " .. tostring(abilityId) .. " in " .. path)
            if entry.type == AlertTypes.CUSTOM then
                assert(type(entry.fn) == "function",
                    "EventDispatcher.build: CUSTOM entry for ability " .. tostring(abilityId)
                    .. " in " .. path .. " has no .fn function")
            end
            if entry.type == AlertTypes.TIMER_RESET then
                assert(type(entry.timer) == "string",
                    "EventDispatcher.build: TIMER_RESET entry for ability " .. tostring(abilityId)
                    .. " in " .. path .. " missing .timer string key")
            end
        end
        if empty then
            d("[Incha/Dispatcher] warning: empty bucket at " .. path)
        end
    end

    local e  = boss.events
    local bc = e.beginCast     or {}
    local ec = e.effectChanged or {}
    local ce = e.combatEvent   or {}

    validateBucket(bc.instant,     "beginCast.instant")
    validateBucket(bc.started,     "beginCast.started")
    validateBucket(bc.executed,    "beginCast.executed")
    validateBucket(bc.interrupted, "beginCast.interrupted")
    validateBucket(ec.gained,      "effectChanged.gained")
    validateBucket(ec.faded,       "effectChanged.faded")
    validateBucket(ec.updated,     "effectChanged.updated")
    validateBucket(ce.damage,      "combatEvent.damage")
    validateBucket(ce.dodged,      "combatEvent.dodged")
    validateBucket(ce.blocked,     "combatEvent.blocked")
    validateBucket(ce.other,       "combatEvent.other")
end

package.loaded["core.EventDispatcher"] = EventDispatcher
return EventDispatcher
