--- core/EventDispatcher.lua  -  Type-driven event dispatcher.
---
--- Ingests a boss's `events` table at load time (EventDispatcher.build),
--- builds O(1) lookups, and exposes three entry points — one per ESO event
--- class — that EventPipeline calls for every registered event.
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
---
--- Bucket-level type contracts (enforced by EventDispatcher.build):
---   beginCast.instant  — CAST_BAR is FORBIDDEN; use DODGE/BLOCK/DEBUFF/CUSTOM.
---                        Instant abilities fire with no window — there is no bar
---                        to show; the handler emits an immediate avoid/react alert.
---   beginCast.started  — DODGE/BLOCK/DEBUFF are FORBIDDEN; use CAST_BAR/CUSTOM.
---                        Cast-started means a bar is showing; a dodge alert here
---                        fires before the cast even lands.  State handlers
---                        (TIMER_RESET, IGNORE) are allowed.

local AlertTypes = require("core.AlertTypes")
local CA         = require("external-api.CombatAlerts")

local EventDispatcher = {}

-- -- Layer-2 routing tables -------------------------------------------------
-- Built at module load time (ESO globals are set before addon modules run).
-- O(1) dispatch from a raw ESO constant to the sub-type bucket name.

local _effectChangeSubtype = {
    [EFFECT_RESULT_GAINED]  = "gained",
    [EFFECT_RESULT_FADED]   = "faded",
    [EFFECT_RESULT_UPDATED] = "updated",
}

-- DAMAGE and CRITICAL_DAMAGE both route to the "damage" bucket.
-- Unknown results fall back to "other" at call time (see dispatchCombatEvent).
local _combatResultSubtype = {
    [ACTION_RESULT_DAMAGE]          = "damage",
    [ACTION_RESULT_CRITICAL_DAMAGE] = "damage",
    [ACTION_RESULT_DODGED]          = "dodged",
    [ACTION_RESULT_BLOCKED_DAMAGE]  = "blocked",
}

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

-- -- State handlers ----------------------------------------------------------
-- Types that mutate boss state or are no-ops.
-- Signature: (boss, context, alerts, entry, abilityId, sourceUnitName, ...)

local function handleIgnore(boss, context, alerts, entry, abilityId, sourceUnitName, ...) end

local function handleCustom(boss, context, alerts, entry, abilityId, sourceUnitName, ...)
    if entry.fn then entry.fn(boss, context, alerts, abilityId, sourceUnitName, ...) end
end

local function handleTimerReset(boss, context, alerts, entry, abilityId, sourceUnitName, ...)
    local timer = entry.timer and boss[entry.timer]
    if timer and timer.reset then timer:reset() end
end

local _bossStateHandler = {
    [AlertTypes.IGNORE]      = handleIgnore,
    [AlertTypes.CUSTOM]      = handleCustom,
    [AlertTypes.TIMER_RESET] = handleTimerReset,
}

-- -- CA output handlers ------------------------------------------------------
-- Types that emit a Combat Alerts bar or notification.
-- Signature: (abilityId, entry, sourceUnitName)

local function caRanged(abilityId, entry, sourceUnitName)
    return CA.ranged(abilityId, entry.text or sourceUnitName or "", entry.dur or 3000, entry.color)
end

local function caInterrupt(abilityId, entry, sourceUnitName)
    return CA.interrupt(abilityId, entry.text or sourceUnitName or "", entry.dur or 2000, entry.color)
end

local function caCastBar(abilityId, entry, sourceUnitName)
    local dur = entry.dur or 3000
    return CA.bar(abilityId, entry.text or "", dur, entry.durMax or dur, entry.color)
end

local _combatAlertHandler = {
    [AlertTypes.DODGE]     = caRanged,
    [AlertTypes.BLOCK]     = caRanged,
    [AlertTypes.DEBUFF]    = caRanged,
    [AlertTypes.INTERRUPT] = caInterrupt,
    [AlertTypes.CAST_BAR]  = caCastBar,
}

-- -- runEntry ----------------------------------------------------------------
-- Single dispatch point for all three entry functions.

local function runEntry(entry, boss, context, alerts, abilityId, sourceUnitName, ...)
    local t = entry.type

    local stateHandler = _bossStateHandler[t]
    if stateHandler then
        return stateHandler(boss, context, alerts, entry, abilityId, sourceUnitName, ...)
    end

    local alertHandler = _combatAlertHandler[t]
    if alertHandler then return alertHandler(abilityId, entry, sourceUnitName) end
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
    castTime = tonumber(castTime) or 0   -- guard: GetAbilityCastInfo may return non-number
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
        local function onInterruptTimerFired()
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
        end
        handle = zo_callLater(onInterruptTimerFired, castTime or 0)
        _pending[key] = { handle = handle }
    end
end

--- Dispatch an EVENT_EFFECT_CHANGED event on a registered ability.
--- changeType: EFFECT_RESULT_GAINED | EFFECT_RESULT_FADED | EFFECT_RESULT_UPDATED
function EventDispatcher.dispatchEffectChanged(boss, context, alerts,
        changeType, abilityId, sourceUnitName, ...)
    if not boss.events or not boss.events.effectChanged then return end
    local bucketName = _effectChangeSubtype[changeType]
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
    local bucketName = _combatResultSubtype[result] or "other"
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

    -- opts.noCastBar  = true  — CAST_BAR is forbidden (instant abilities have no window)
    -- opts.castBarOnly = true — only CAST_BAR or CUSTOM are meaningful (cast-started entries)
    local function validateBucket(bucket, path, opts)
        opts = opts or {}
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
            if opts.noCastBar then
                assert(entry.type ~= AlertTypes.CAST_BAR,
                    "EventDispatcher.build: CAST_BAR is invalid in " .. path
                    .. " — instant abilities fire with no window;"
                    .. " use DODGE/BLOCK/DEBUFF/CUSTOM for ability "
                    .. tostring(abilityId))
            end
            if opts.noDodgeAlert then
                assert(entry.type ~= AlertTypes.DODGE
                        and entry.type ~= AlertTypes.BLOCK
                        and entry.type ~= AlertTypes.DEBUFF,
                    "EventDispatcher.build: DODGE/BLOCK/DEBUFF are invalid in " .. path
                    .. " — the cast is starting, not landing;"
                    .. " use CAST_BAR or CUSTOM for ability "
                    .. tostring(abilityId))
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

    -- instant: ability fires with no cast window → dodge/block/avoid alert only
    validateBucket(bc.instant, "beginCast.instant", { noCastBar = true })
    -- started: cast is in progress → DODGE/BLOCK/DEBUFF are wrong here
    validateBucket(bc.started, "beginCast.started", { noDodgeAlert = true })
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

-- -- Pipeline entry points ---------------------------------------------------
-- Passed to Trial.create as options.*;
-- Trial wraps each one so the first arg it receives at runtime is `trial`.
--
-- Handler signature for CUSTOM fns called from effectChanged buckets:
--   fn(boss, context, alerts, abilityId, unitName, unitTag, unitId, stackCount)
-- Handler signature for CUSTOM fns called from beginCast / combatEvent buckets:
--   fn(boss, context, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)

--- Returns two sets of ability IDs the EventPipeline must register for a boss:
--- { combat ids } and { effect ids }, built from boss.events buckets.
function EventDispatcher.abilityIdsFor(boss)
    local combat, effect = {}, {}
    if not boss then return combat, effect end
    local e = boss.events
    if not e then return combat, effect end

    local bc = e.beginCast or {}
    for _, sub in ipairs({ "instant", "started", "executed", "interrupted" }) do
        for id in pairs(bc[sub] or {}) do combat[id] = true end
    end
    local ce = e.combatEvent or {}
    for _, sub in ipairs({ "damage", "dodged", "blocked", "other" }) do
        for id in pairs(ce[sub] or {}) do combat[id] = true end
    end
    local ec = e.effectChanged or {}
    for _, sub in ipairs({ "gained", "faded", "updated" }) do
        for id in pairs(ec[sub] or {}) do effect[id] = true end
    end

    return combat, effect
end

--- Ability-filtered combat event handler.  Called by EventPipeline for every
--- EVENT_COMBAT_EVENT whose abilityId the boss declared.
--- ESO signature (modern API):
---   eventCode, result, isError, abilityName, abilityGraphic, hitStatus,
---   unitTag, unitName, sourceUnitTag, sourceUnitName,
---   sourceUnitId, unitId, abilityId, overflow
function EventDispatcher.onCombatEventFiltered(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.events then return end
    -- ACTION_RESULT_DIED is handled exclusively by onDiedCombatEvent below.
    if result == ACTION_RESULT_DIED then return end
    local context, alerts = trial.context, trial.alerts
    if result == ACTION_RESULT_BEGIN then
        local castTime = GetAbilityCastInfo(abilityId) or 0
        EventDispatcher.dispatchBeginCast(boss, context, alerts,
            castTime, false, sourceUnitId, abilityId, sourceUnitName,
            unitTag, unitId, sourceUnitId, unitName)
    else
        EventDispatcher.dispatchCombatEvent(boss, context, alerts,
            result, abilityId, sourceUnitName,
            unitTag, unitId, sourceUnitId, unitName)
    end
end

--- Result-filtered combat event handler for ACTION_RESULT_DIED.
function EventDispatcher.onDiedCombatEvent(trial, eventCode,
        result, isError, abilityName, abilityGraphic, hitStatus,
        unitTag, unitName, sourceUnitTag, sourceUnitName,
        sourceUnitId, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.onDied then return end
    boss:onDied(trial.context, trial.alerts,
        unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
end

--- Ability-filtered effect changed handler.
--- ESO signature:
---   eventCode, changeType, effectSlot, effectName, unitTag,
---   beginTime, endTime, stackCount, iconName, buffType, effectType,
---   abilityType, statusEffectType, unitName, unitId, abilityId, sourceType
--- Extra args passed to CUSTOM handlers: unitTag, unitId, stackCount
function EventDispatcher.onEffectChangedFiltered(trial, eventCode,
        changeType, effectSlot, effectName, unitTag,
        beginTime, endTime, stackCount, iconName, buffType, effectType,
        abilityType, statusEffectType, unitName, unitId, abilityId)
    local boss = trial:getActiveBoss()
    if not boss or not boss.events then return end
    EventDispatcher.dispatchEffectChanged(boss, trial.context, trial.alerts,
        changeType, abilityId, unitName,
        unitTag, unitId, stackCount)
end

package.loaded["core.EventDispatcher"] = EventDispatcher
return EventDispatcher
