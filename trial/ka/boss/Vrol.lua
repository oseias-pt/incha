local Location = require("core.Location")
local Settings = require("core.Settings")
local Timer    = require("lib.Timer")

-- ── Ability IDs (from BSCHTKA_Vrol.lua) ───────────────────────────────────
local VROL_PORTAL_CAST  = 133994  -- Portal cast BEGIN → reset portal timer + alert
local VROL_FOG_CAST     = 133808  -- Fog cast BEGIN    → reset fog timer + alert
local VROL_PORTAL_KTIME = 134016  -- Portal kill-time debuff (EVENT_EFFECT_CHANGED, player only)
local VROL_HARPOON      = 133913  -- Shocking Harpoon BEGIN → reset conduit timer + alert
local VROL_APOTHECARY   = 140255  -- Apothecary BEGIN  → Interrupt alert

-- ── Timer durations ───────────────────────────────────────────────────────
local NEXT_PORTAL_TIME  = 45
local NEXT_CONDUIT_TIME = 40
local NEXT_FOG_TIME     = 30

local INITIAL_PORTAL_DELAY = 15  -- first portal is shorter than the recurring interval

local Vrol = {
    id = 2,
    key = "vrol",
    hmHealthThreshold = 72769370,
    location = Location.new(110200, 118500, 24500, 29000, 65000, 78800),
}

-- Timers start expired; reset() arms them when a boss encounter begins.
Vrol.portalTimer       = Timer.new(NEXT_PORTAL_TIME)
Vrol.conduitTimer      = Timer.new(NEXT_CONDUIT_TIME)
Vrol.fogTimer          = Timer.new(NEXT_FOG_TIME)
Vrol.bPORTAL_END       = false
-- Portal kill-timer: ms timestamp when the current portal debuff expires.
-- Set in onEffectChanged(EFFECT_RESULT_GAINED) to detect pass/fail on FADED.
Vrol.portalKillExpires = 0

function Vrol:reset(forced)
    -- First portal always spawns sooner than the recurring interval.
    self.portalTimer:reset(INITIAL_PORTAL_DELAY)
    self.conduitTimer:reset()
    self.fogTimer:reset()
    self.bPORTAL_END = false

    if Settings.trial("ka").portalIconVrol then
        zo_callLater(function() BSCHTKA.AddPortalIcon() end, 3100)
    end

    self:syncLegacy()
end

function Vrol:syncLegacy()
    if not BSCHTKA then
        return
    end

    -- Legacy addon reads raw epoch timestamps, so expose expiresAt.
    BSCHTKA.PORTAL_TIME  = self.portalTimer:getExpiresAt()
    BSCHTKA.CONDUIT_TIME = self.conduitTimer:getExpiresAt()
    BSCHTKA.FOG_TIME     = self.fogTimer:getExpiresAt()
    BSCHTKA.bPORTAL_END  = self.bPORTAL_END
end

function Vrol:onEnter(context)
    context.extras.legacyFlag = "bVrol"
end

-- Combat mechanic alerts and timer resets.
-- NOT registered while KA Factory still uses LegacyUI (Phase 4.4 wires this in).
function Vrol:onCombatEvent(context, alerts, result, abilityId,
                             unitTag, sourceUnitTag, sourceUnitId, unitId)
    if abilityId == VROL_PORTAL_CAST and result == ACTION_RESULT_BEGIN then
        self.portalTimer:reset()
        self:syncLegacy()
        alerts:showAction("KILL Conjurer!")

    elseif abilityId == VROL_FOG_CAST and result == ACTION_RESULT_BEGIN then
        self.fogTimer:reset()
        self:syncLegacy()
        alerts:showAction("Dodge/Move! (Fog)")

    elseif abilityId == VROL_HARPOON and result == ACTION_RESULT_BEGIN then
        self.conduitTimer:reset()
        self:syncLegacy()
        alerts:showAction("Kill Harpoon! (~16 s)")

    elseif abilityId == VROL_APOTHECARY and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Apothecary!")
    end
end

-- Portal kill-timer debuff on the local player (EVENT_EFFECT_CHANGED).
-- GAINED = player entered portal → 20 s to kill the Conjurer.
-- FADED  = debuff removed → check if Conjurer was killed in time.
function Vrol:onEffectChanged(context, alerts, changeType, abilityId, unitTag, unitId, unitName)
    if abilityId ~= VROL_PORTAL_KTIME then return end

    -- Only react to the local player's portal debuff.
    if unitTag ~= GetLocalPlayerGroupUnitTag() then return end

    if changeType == EFFECT_RESULT_GAINED then
        self.portalKillExpires = GetGameTimeMilliseconds() + 20000
        alerts:showAction("KILL Conjurer! (20 s)")

    elseif changeType == EFFECT_RESULT_FADED then
        if GetGameTimeMilliseconds() < self.portalKillExpires then
            alerts:showAction("Portal OK!")
        else
            alerts:showAction("Portal Failed!")
        end
        self.portalKillExpires = 0
    end
end

-- 200ms timer display — writes to info lines 1-3.
function Vrol:onUpdate(context, alerts)
    local t1 = self.fogTimer:remaining()
    local t2 = self.conduitTimer:remaining()
    local t3 = self.portalTimer:remaining()
    alerts:showInfo(1, "Fog:     " .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or "ready"))
    alerts:showInfo(2, "Conduit: " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
    alerts:showInfo(3, "Portal:  " .. (t3 > 0 and ZO_FormatCountdownTimer(t3) or "ready"))
end

function Vrol:onPowerUpdate(context, healthPercent)
    if healthPercent < 50 then
        self.bPORTAL_END = true
    end

    self:syncLegacy()
end

return Vrol
