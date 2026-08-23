local AlertSink = require("core.AlertSink")
local BossRegistry = require("core.BossRegistry")
local Difficulty = require("core.Difficulty")
local EventPipeline = require("core.EventPipeline")
local HealthRules = require("core.HealthRules")
local Throttle = require("lib.Throttle")
local TrialContext = require("core.TrialContext")

local Trial = {}
Trial.__index = Trial

local function getPlayerZoneId()
    return GetZoneId(GetUnitZoneIndex("player"))
end

--- Boss interface — all methods are optional unless marked REQUIRED.
--- Each boss is a table with __index pointing at the class (prototype).
--- Trial checks for each method before calling; missing methods are no-ops.
---
---   REQUIRED: key (string)          — unique identifier, matches BossRegistry key
---   REQUIRED: name (string)         — display name returned by GetUnitName("bossN"),
---                                     OR nameAliases table listing all unit names
---   REQUIRED: new() → instance      — returns a fresh table, NO carried-over state
---
---   onLeave(context)                — cleanup: stop CA bars, unregister events
---   onEnter(context, alerts)        — boss became active (called after context:setBoss)
---   onCombatState(ctx, inCombat, alerts)
---   onCombatEvent(ctx, alerts, result, abilityId,
---                 unitTag, sourceUnitTag, sourceUnitId, unitId,
---                 sourceUnitName, unitName)
---   onEffectChanged(ctx, alerts, changeType, abilityId,
---                   unitTag, unitId, unitName)
---   onUpdate(ctx, alerts)           — 200 ms tick while boss is active
---   onPowerUpdate(ctx, healthPct, alerts)
---
---   hmHealthThreshold (number)      — max HP above which difficulty = HARDMODE
---   healthRules (table)             — HealthRules table for phase-change callouts
---   hideActionWhenNoRule (boolean)  — clear action slot when no health rule fires
---   location (Location)             — AABB for position-based boss detection
---   stage (number)                  — initial context.stage value (default 1)
---
function Trial.create(options)
    local self = setmetatable({
        id = options.id,
        zoneId = options.zoneId,
        name = options.name or options.id,
        eventPrefix = options.eventPrefix or ("Incha_" .. options.id),
        bridge = options.bridge,
        registry = BossRegistry.new(options.bosses),
        context = TrialContext.new(options.id),
        alerts = AlertSink.new(options.alerts),
        enabled = false,
        -- The live boss instance for the current encounter; nil between bosses.
        -- Always a fresh object created by the boss class's new() factory —
        -- never the class prototype itself.
        activeBoss = nil,
        -- Only gates the cosmetic health-rule text (and the AlertSink calls
        -- it triggers), not boss:onPowerUpdate itself, so mechanic timing
        -- logic still sees every real tick. 1% granularity is safe since
        -- healthRules windows are several points wide.
        healthThrottle = Throttle.new(1),
    }, Trial)

    self.pipeline = EventPipeline.new(self.eventPrefix, {
        onBossesChanged = function(eventCode, forceReset)
            self:onBossesChanged(forceReset)
        end,
        onPowerUpdate = function(eventCode, unitTag, powerIndex, powerType, powerValue, powerMax, powerEffectiveMax)
            self:onPowerUpdate(powerValue, powerMax)
        end,
        -- Always registered — Trial:onCombatState delegates to the active boss
        -- if it has the callback, so no trial-level conditional is needed.
        onCombatState = function(eventCode, inCombat)
            self:onCombatState(inCombat)
        end,
        onCombatEvent = options.onCombatEvent and function(...)
            options.onCombatEvent(self, ...)
        end or nil,
        onEffectChanged = options.onEffectChanged and function(...)
            options.onEffectChanged(self, ...)
        end or nil,
        -- 200ms timer-display loop.  Calls boss:onUpdate(context, alerts) when
        -- a boss is active.  No-op otherwise, so the loop is always registered
        -- without wasting ticks between encounters.
        onUpdate = function()
            self:onUpdate()
        end,
        updateInterval = 200,
    })

    return self
end

function Trial:isActiveZone()
    return getPlayerZoneId() == self.zoneId
end

function Trial:getActiveBoss()
    return self.activeBoss
end

function Trial:onBossesChanged(forceReset)
    if not self:isActiveZone() then
        return
    end

    -- Give the outgoing boss a chance to clean up (stop CA bars, unregister events).
    if self.activeBoss then
        if self.activeBoss.onLeave then
            self.activeBoss:onLeave(self.context)
        end
        self.activeBoss = nil
    end

    self.healthThrottle:reset()

    local _, x, y, z = GetUnitWorldPosition("player")
    local bossClass = self.registry:findAtPosition(x, y, z)

    -- Fallback: name-based detection for trials whose bosses carry a `name`
    -- field instead of (or in addition to) a location bounding box.
    -- Check boss1–boss4 so concurrent-boss encounters (e.g. Ryelaz+Zilyesset)
    -- are detected correctly regardless of which slot the engine assigns first.
    if not bossClass then
        for _, slot in ipairs({"boss1", "boss2", "boss3", "boss4"}) do
            if DoesUnitExist(slot) then
                local candidate = self.registry:findByName(GetUnitName(slot))
                if candidate then
                    bossClass = candidate
                    break
                end
            end
        end
    end

    if bossClass then
        -- Create a fresh instance — no state carried over from previous pulls.
        local instance = bossClass.new()
        self.activeBoss = instance
        self.context:setBoss(instance)

        local _, _, effectiveMax = GetUnitPower("boss1", POWERTYPE_HEALTH)
        self.context:setDifficulty(self.registry:detectDifficulty(bossClass, effectiveMax))

        if instance.onEnter then
            instance:onEnter(self.context, self.alerts)
        end

        if self.bridge and self.bridge.onBossEnter then
            self.bridge.onBossEnter(instance, self.context)
        end
    else
        self.context:setBoss(nil)
        self.context:setDifficulty(Difficulty.NONE)
        self.alerts:clear()

        if self.bridge and self.bridge.onBossExit then
            self.bridge.onBossExit()
        end
    end
end

function Trial:onPowerUpdate(powerValue, powerMax)
    if not self:isActiveZone() then
        return
    end

    local boss = self:getActiveBoss()
    if not boss then
        return
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
            self.alerts:emit("hideAction")
        end
    end

    if not IsUnitInCombat("player") and self.bridge and self.bridge.checkHardmode then
        self.bridge.checkHardmode(self.context)
    end
end

function Trial:onUpdate()
    if not self:isActiveZone() then return end
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
end

function Trial:enable()
    if self.enabled then
        return
    end

    self.enabled = true

    if self.bridge and self.bridge.onEnable then
        self.bridge.onEnable()
    end

    self.pipeline:enable()
    self:onBossesChanged(true)
end

function Trial:disable()
    if not self.enabled then
        return
    end

    self.pipeline:disable()

    if self.activeBoss and self.activeBoss.onLeave then
        self.activeBoss:onLeave(self.context)
    end
    self.activeBoss = nil

    self.context:setBoss(nil)
    self.context:setDifficulty(Difficulty.NONE)
    self.healthThrottle:reset()
    self.alerts:clear()

    if self.bridge and self.bridge.onDisable then
        self.bridge.onDisable()
    end

    self.enabled = false
end

return Trial
