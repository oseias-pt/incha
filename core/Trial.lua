local AlertSink       = require("core.AlertSink")
local BossRegistry    = require("core.BossRegistry")
local Difficulty      = require("core.Difficulty")
local EventDispatcher = require("core.EventDispatcher")
local EventPipeline   = require("core.EventPipeline")
local HealthRules  = require("core.HealthRules")
local Log          = require("lib.Log")
local Settings     = require("core.Settings")
local Throttle     = require("lib.Throttle")
local TrialContext = require("core.TrialContext")
local BridgeBase   = require("core.Bridge")

local Trial = {}
Trial.__index = Trial

--- Boss interface  -  all methods are optional unless marked REQUIRED.
--- Each boss is a table with __index pointing at the class (prototype).
--- Trial checks for each method before calling; missing methods are no-ops.
---
---   REQUIRED: key (string)           -  unique identifier, matches BossRegistry key
---   REQUIRED: name (string)          -  display name returned by GetUnitName("bossN"),
---                                     OR nameAliases table listing all unit names
---   REQUIRED: new() -> instance       -  returns a fresh table, NO carried-over state
---
---   onLeave(context)                 -  full teardown on zone exit: stop bars,
---                                     discard position icons, unregister events
---   onEnter(context, alerts)         -  boss became active (called after context:setBoss)
---   onCombatState(ctx, inCombat, alerts)
---   onWipe(ctx, alerts)              -  soft reset on wipe while still in zone:
---                                     stop active bars, clear per-pull flags and
---                                     OSI mechanic icons; keep long-lived position
---                                     icons so they survive into the next pull
---   onCombatEvent(ctx, alerts, result, abilityId,
---                 unitTag, sourceUnitTag, sourceUnitId, unitId,
---                 sourceUnitName, unitName)
---   onEffectChanged(ctx, alerts, changeType, abilityId,
---                   unitTag, unitId, unitName)
---   onUpdate(ctx, alerts)            -  200 ms tick while boss is active
---   onPowerUpdate(ctx, healthPct, alerts)
---
---   hmHealthThreshold (number)       -  max HP above which difficulty = HARDMODE
---   healthRules (table)              -  HealthRules table for phase-change callouts
---   hideActionWhenNoRule (boolean)   -  clear action slot when no health rule fires
---   location (Location)              -  AABB for position-based boss detection
---   stage (number)                   -  initial context.stage value (default 1)
---
function Trial.create(options)
    local self = setmetatable({
        id = options.id,
        zoneId = options.zoneId,
        name = options.name or options.id,
        eventPrefix = options.eventPrefix or (ADDON_PREFIX .. options.id),
        -- Default to BridgeBase so every hook can be called unconditionally.
        bridge = options.bridge or BridgeBase,
        registry = BossRegistry.new(options.bosses),
        context = TrialContext.new(options.id),
        alerts = AlertSink.new(options.alerts),
        enabled = false,
        -- The active boss instance, or nil between encounters.
        -- Always a fresh object from the boss class's new() factory, never the
        -- class prototype.  Compound-boss encounters (future work, #129/#130)
        -- will require extending this to multiple instances.
        _activeBoss = nil,
        -- True while _activeBoss came from injectBoss (debug tooling) rather
        -- than detection; see Trial:onBossesChanged.
        _injected = false,
        -- Only gates the cosmetic health-rule text (and the AlertSink calls
        -- it triggers), not boss:onPowerUpdate itself, so mechanic timing
        -- logic still sees every real tick. 1% granularity is safe since
        -- healthRules windows are several points wide.
        healthThrottle = Throttle.new(1),
    }, Trial)

    -- Resolve the dispatcher callbacks once.  These run on the hottest path in
    -- the addon (one call per admitted combat / effect event), so the
    -- `options.x or default` choice is made here, not inside each closure.
    local onCombatEventFiltered   = options.onCombatEventFiltered   or EventDispatcher.onCombatEventFiltered
    local onEffectChangedFiltered = options.onEffectChangedFiltered or EventDispatcher.onEffectChangedFiltered
    local onDiedCombatEvent       = options.onDiedCombatEvent       or EventDispatcher.onDiedCombatEvent
    local onLegacyCombatEvent     = options.onLegacyCombatEvent

    self.pipeline = EventPipeline.new(self.eventPrefix, {
        onBossesChanged = function(eventCode, forceReset)
            self:onBossesChanged(forceReset)
        end,
        onPowerUpdate = function(eventCode, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)
            self:onPowerUpdate(powerValue, powerMax, unitTag, powerEffectiveMax)
        end,
        -- Always registered  -  Trial:onCombatState delegates to the active boss
        -- if it has the callback, so no trial-level conditional is needed.
        onCombatState = function(eventCode, inCombat)
            self:onCombatState(inCombat)
        end,
        -- Combat / effect events are registered per ability id and per combat
        -- result by EventPipeline:setActiveBoss, so these are the narrow
        -- entry points rather than one unfiltered dispatcher.  Each filtered
        -- registration admits a disjoint slice; see core/EventDispatcher.lua.
        -- The four EventDispatcher callbacks default to the standard dispatcher
        -- functions so individual factories only need to pass them when they
        -- override the default behaviour.
        abilityIdsFor = options.abilityIdsFor or EventDispatcher.abilityIdsFor,
        onCombatEventFiltered   = function(...) onCombatEventFiltered(self, ...) end,
        onEffectChangedFiltered = function(...) onEffectChangedFiltered(self, ...) end,
        onDiedCombatEvent       = function(...) onDiedCombatEvent(self, ...) end,
        onLegacyCombatEvent     = onLegacyCombatEvent
            and function(...) onLegacyCombatEvent(self, ...) end or nil,
        -- 200ms timer-display loop.  Calls boss:onUpdate(context, alerts) when
        -- a boss is active.  No-op otherwise, so the loop is always registered
        -- without wasting ticks between encounters.
        onUpdate = function()
            self:onUpdate()
        end,
        updateInterval = 200,
        -- Cancel all in-flight EventDispatcher interrupt-detection timers
        -- whenever boss filters are cleared (boss change or zone exit), so
        -- zo_callLater callbacks from the outgoing boss cannot fire phantom
        -- alerts against the new boss or a nil context.
        onClearPending = EventDispatcher.clearPending,
    })

    return self
end

-- Returns the active boss instance, or nil between encounters.
function Trial:getActiveBoss()
    return self._activeBoss
end

-- Tear down the current boss instance: onLeave, cancel deferred callbacks,
-- drop the reference.  Shared by the real detection path (onBossesChanged),
-- disable(), and the debug-injection path (ejectBoss).
local function retireActiveBoss(self)
    local outgoing = self._activeBoss
    if not outgoing then return end
    if outgoing.onLeave then
        outgoing:onLeave(self.context)
    end
    -- Drop any :after() callbacks the outgoing boss still had in flight,
    -- so they cannot fire against a discarded instance.  Runs after
    -- onLeave so the boss can still schedule teardown work if it needs to.
    if outgoing.cancelPending then
        outgoing:cancelPending()
    end
    self._activeBoss = nil
    self._injected   = false
end

--- Debug tooling entry point (ui/DebugPanel, lib/Playback): make `instance`
--- the active boss without waiting for EVENT_BOSSES_CHANGED.  Runs the same
--- lifecycle a detected boss gets — context, panel, event filters, onEnter,
--- onCombatState(true) — so timers arm and tracker rows populate exactly as
--- they would in a live pull.  Any previously active boss is retired first.
--- No-op when the trial is not enabled (player not in the zone).
function Trial:injectBoss(instance)
    if not self.enabled or not instance then return end
    retireActiveBoss(self)
    self.healthThrottle:reset()
    self.alerts:clear()

    self._activeBoss = instance
    -- Flag so a real EVENT_BOSSES_CHANGED (add spawning, boss bar refresh)
    -- cannot silently retire the injected instance mid-test.  Cleared by
    -- retireActiveBoss, so ejectBoss / disable restore normal detection.
    self._injected   = true
    self.context:setBoss(instance)
    -- Injected bosses have no health sample; leave the difficulty at the
    -- sentinel so gated mechanics read as "not HM" rather than a stale value.
    self.context:setDifficulty(self.registry:detectDifficulty(instance, nil))
    self.pipeline:setActiveBoss(instance)
    if instance.onEnter then
        instance:onEnter(self.context, self.alerts)
    end
    self.bridge.onBossEnter(instance, self.context)
    if instance.onCombatState then
        instance:onCombatState(self.context, true, self.alerts)
    end
end

--- Debug tooling exit: retire `instance` if it is still the active boss and
--- re-run normal detection, so a real boss the injection displaced comes
--- back, or — with no boss in range — filters, pending timers and the panel
--- are cleared through the same path a zone transition uses.  Safe to call
--- when a real boss has since replaced the instance (no-op) or when nothing
--- is active.
function Trial:ejectBoss(instance)
    if not instance or self._activeBoss ~= instance then return end
    retireActiveBoss(self)
    self:onBossesChanged(true)
end

-- boss<N> unit tags probed by name-based detection.  Module constant so the
-- table is not rebuilt on every EVENT_BOSSES_CHANGED.
local BOSS_SLOTS = { "boss1", "boss2", "boss3", "boss4" }

function Trial:onBossesChanged(forceReset)
    if not self.enabled then
        return
    end

    -- A debug-injected boss owns the trial until it is ejected; the game's
    -- boss-list churn must not replace it with (usually) nothing.
    if self._injected then
        Log.debug("s: EVENT_BOSSES_CHANGED ignored — debug boss q injected",
            self.id, self._activeBoss and self._activeBoss.key or "?")
        return
    end

    -- Give the outgoing boss a chance to clean up (stop CA bars, unregister events).
    retireActiveBoss(self)

    self.healthThrottle:reset()

    local _, x, y, z = GetUnitWorldPosition("player")
    local bossClass = self.registry:findAtPosition(x, y, z)

    -- Fallback: name-based detection for trials whose bosses carry a `name`
    -- field instead of (or in addition to) a location bounding box.
    -- Check boss1-boss4 so concurrent-boss encounters (e.g. Ryelaz+Zilyesset)
    -- are detected correctly regardless of which slot the engine assigns first.
    -- Which boss<N> slot the encounter was recognised in.  Health samples for
    -- difficulty detection must come from that unit, not unconditionally from
    -- boss1, or a concurrent-boss encounter reads the wrong health pool.
    local detectedSlot = "boss1"

    if not bossClass then
        for _, slot in ipairs(BOSS_SLOTS) do
            if DoesUnitExist(slot) then
                local candidate = self.registry:findByName(GetUnitName(slot))
                if candidate then
                    bossClass = candidate
                    detectedSlot = slot
                    break
                end
            end
        end
    end

    -- Detection succeeds: log the matched unit name so one vet-normal pull with
    -- /incha debug confirms the name string against GetUnitName() without needing
    -- a deliberate mismatch.  See #122 for the verification checklist.
    if bossClass and Log.isEnabled() then
        if bossClass.location then
            Log.debug("%s: matched %q via location (%.0f, %.0f, %.0f)",
                self.id, bossClass.key, x or 0, y or 0, z or 0)
        else
            Log.debug("%s: matched %q via name %q (slot %s)",
                self.id, bossClass.key, GetUnitName(detectedSlot), detectedSlot)
        end
    end

    -- Per-boss enable gate.  A disabled boss is treated as undetected: no
    -- alerts, no panel, and no event subscriptions for this encounter.
    if bossClass and Settings.trial(self.id).bosses[bossClass.key] == false then
        Log.debug("%s: boss %q is disabled in settings", self.id, bossClass.key)
        bossClass = nil
    end

    -- Detection failing is silent by design  -  no boss, no panel, no error  -
    -- which is exactly why a wrong name literal or a stale AABB can sit in the
    -- tree unnoticed.  Behind the debug flag, report what the game actually
    -- reported so one run through a trial yields the whole correction list.
    if not bossClass and Log.isEnabled() then
        local present = {}
        for _, slot in ipairs(BOSS_SLOTS) do
            if DoesUnitExist(slot) then
                present[#present + 1] = string.format("%s=%q", slot, GetUnitName(slot))
            end
        end
        if #present > 0 then
            Log.warn("%s: no boss matched. Game reports %s",
                self.id, table.concat(present, "  "))
            Log.warn("  registry expects: %s",
                table.concat(self.registry:knownNames(), " | "))
            Log.warn("  player at %.0f / %.0f / %.0f (no AABB contains this)",
                x or 0, y or 0, z or 0)
        end
    end

    -- Blank the panel before either branch runs.  The outgoing boss owned
    -- whatever is currently on screen, and the incoming one only rewrites the
    -- info slots it actually uses  -  so without this, walking straight from
    -- one boss to the next leaves the previous boss's countdown lines up
    -- until (or unless) the new boss happens to write those same slots.
    self.alerts:clear()

    if bossClass then
        -- Create a fresh instance  -  no state carried over from previous pulls.
        local instance = bossClass.new()
        self._activeBoss = instance
        self.context:setBoss(instance)

        -- First sample.  This can legitimately read 0 on the frame the boss
        -- appears, in which case detectDifficulty returns NONE and
        -- onPowerUpdate re-resolves from the next real health tick.
        self.bossSlot = detectedSlot
        local _, _, effectiveMax = GetUnitPower(detectedSlot, POWERTYPE_HEALTH)
        self.context:setDifficulty(self.registry:detectDifficulty(bossClass, effectiveMax))

        -- Narrow the combat / effect event registrations to the abilities and
        -- results this boss can actually act on.  Done before onEnter so a
        -- boss that fires alerts from onEnter is already wired up.
        self.pipeline:setActiveBoss(instance)

        if instance.onEnter then
            instance:onEnter(self.context, self.alerts)
        end

        self.bridge.onBossEnter(instance, self.context)
    else
        self.context:setBoss(nil)
        self.context:setDifficulty(Difficulty.NONE)
        self.pipeline:setActiveBoss(nil)

        self.bridge.onBossExit()
    end
end

function Trial:onPowerUpdate(powerValue, powerMax, unitTag, powerEffectiveMax)
    if not self.enabled then
        return
    end
    -- powerMax can be 0 briefly during boss transitions; skip the tick to
    -- avoid a divide-by-zero producing nan in health rules.
    if powerMax == 0 then
        return
    end

    local boss = self:getActiveBoss()
    if not boss then
        return
    end

    -- Second chance at difficulty detection.  The sample taken in
    -- onBossesChanged can read 0 on the frame the boss appears, which leaves
    -- difficulty at NONE; this event carries an authoritative effective-max
    -- for free, so re-resolve until it is known.  Restricted to the slot the
    -- encounter was recognised in, since the POWER_UPDATE filter admits every
    -- boss<N> tag and a concurrent boss has a different health pool.
    --
    -- context.isHM gates real mechanics (Xalvakka's jump timer, Taleria's
    -- behemoth line), so getting this right matters beyond the header text.
    -- Only re-resolve while the difficulty is genuinely unknown (NONE = transient,
    -- NO_HM = permanent sentinel meaning this boss has no hard mode).
    if self.context.difficulty == Difficulty.NONE
    and (unitTag == nil or unitTag == self.bossSlot) then
        local sample = powerEffectiveMax
        if not sample or sample <= 0 then sample = powerMax end
        local resolved = self.registry:detectDifficulty(boss, sample)
        if resolved ~= Difficulty.NONE then
            self.context:setDifficulty(resolved)
            Log.debug("%s: difficulty resolved to %s (max hp %d, threshold %s)",
                self.id,
                resolved == Difficulty.HARDMODE and "HARDMODE" or "NORMAL",
                sample, tostring(boss.hmHealthThreshold))
        end
    end

    local healthPercent = powerValue / powerMax * 100
    self.context.healthPercent = healthPercent

    -- Boss mechanic callbacks run on every real tick regardless of
    -- throttling below - mechanic timing shouldn't depend on UI granularity.
    if boss.onPowerUpdate then
        boss:onPowerUpdate(self.context, healthPercent, self.alerts)
    end

    -- The health-rule text/alert display only needs to react when the
    -- rounded percent actually changes, not on every raw power-update tick
    -- (which can fire many times per second). This avoids re-running
    -- rule evaluation and re-touching the UI when nothing visible changed.
    if self.healthThrottle:shouldUpdate(healthPercent) then
        local id, text = HealthRules.evaluate(boss.healthRules, healthPercent, self.context, boss)
        if id then
            self.alerts:showAction(text)
        elseif boss.hideActionWhenNoRule then
            self.alerts:hideAction()
        end
    end

    -- Use the context flag maintained by onCombatState rather than calling the
    -- ESO API on every tick  -  avoids one C->Lua round-trip per power update.
    if not self.context.inCombat then
        self.bridge.checkHardmode(self.context)
    end
end

function Trial:onUpdate()
    if not self.enabled then return end
    local boss = self:getActiveBoss()
    if not boss or not boss.onUpdate then return end
    boss:onUpdate(self.context, self.alerts)
end

function Trial:onCombatState(inCombat)
    self.context.inCombat = inCombat

    local boss = self:getActiveBoss()
    if boss and boss.onCombatState then
        boss:onCombatState(self.context, inCombat, self.alerts)
    end

    -- On wipe (inCombat = false, boss still active), give the boss a chance
    -- to soft-reset without a full zone-exit teardown: stop active cast bars,
    -- clear per-pull flags, hide position icons  -  but keep long-lived icons
    -- created in onEnter so they're still visible at the start of the next pull.
    if not inCombat and boss then
        -- Cancel in-flight :after() callbacks first, so a delayed alert from
        -- the pull that just ended cannot fire into the reset.  onWipe runs
        -- afterwards and may schedule new ones.
        if boss.cancelPending then
            boss:cancelPending()
        end
        if boss.onWipe then
            boss:onWipe(self.context, self.alerts)
        end
    end
end

function Trial:enable()
    if self.enabled then
        return
    end

    self.enabled = true

    self.bridge.onEnable()

    self.pipeline:enable()
    self:onBossesChanged(true)
end

function Trial:disable()
    if not self.enabled then
        return
    end

    self.pipeline:disable()

    retireActiveBoss(self)

    self.context:setBoss(nil)
    self.context:setDifficulty(Difficulty.NONE)
    self.healthThrottle:reset()
    self.alerts:clear()

    self.bridge.onDisable()

    self.enabled = false
end

package.loaded["core.Trial"] = Trial
return Trial
