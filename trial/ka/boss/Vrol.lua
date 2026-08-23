local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs (from BSCHTKA_Vrol.lua) ───────────────────────────────────
local VROL_PORTAL_CAST  = 133994  -- Portal cast BEGIN → reset portal timer + alert
local VROL_FOG_CAST     = 133808  -- Fog cast BEGIN    → starts fog duration countdown
local VROL_FOG_INCREASE = 133756  -- Fog pulse hit     → every 3 hits extends fog by +9 s
local VROL_PORTAL_KTIME = 134016  -- Portal kill-time debuff (EVENT_EFFECT_CHANGED, player only)
local VROL_HARPOON      = 133913  -- Shocking Harpoon BEGIN → reset conduit timer + alert
local VROL_APOTHECARY   = 140255  -- Apothecary BEGIN  → Interrupt alert

-- ── Timer durations ───────────────────────────────────────────────────────
local NEXT_PORTAL_TIME  = 45
local NEXT_CONDUIT_TIME = 40
local NEXT_FOG_TIME     = 30
local FOG_DURATION      = 30     -- seconds the fog fills the room after the cast lands
local FOG_EXTEND_HITS   = 3      -- pulse hits before fog duration extends
local FOG_EXTEND_SECS   = 9      -- seconds added per extension cycle

local INITIAL_PORTAL_DELAY = 15  -- first portal is shorter than the recurring interval

local Vrol = {

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
-- [unitId] → CA cast bar ID; cleared on reset/death.
Vrol.alertList         = {}
-- CA cast bar ID for the portal-kill debuff (started/stopped in onEffectChanged).
Vrol.portalKillBarId   = nil
-- Fog duration tracking: ms timestamp when the current fog clears (0 = no active fog).
-- fogHitCount counts VROL_FOG_INCREASE pulses; resets every FOG_EXTEND_HITS.
Vrol.fogEndTime  = 0
Vrol.fogHitCount = 0

function Vrol:reset()
    -- First portal always spawns sooner than the recurring interval.
    self.portalTimer:reset(INITIAL_PORTAL_DELAY)
    self.conduitTimer:reset()
    self.fogTimer:reset()
    self.bPORTAL_END = false
    self.fogEndTime  = 0
    self.fogHitCount = 0

    -- Stop any lingering cast bars from the previous pull.
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    self.alertList = {}
    CA.castAlertsStop(self.portalKillBarId)
    self.portalKillBarId   = nil
    self.portalKillExpires = 0
end


-- Combat mechanic alerts and timer resets.
-- Phase 4.2: text alerts + CombatAlerts cast bars.
function Vrol:onCombatEvent(context, alerts, result, abilityId,
                             unitTag, sourceUnitTag, sourceUnitId, unitId,
                             sourceUnitName, unitName)
    -- Stop any tracked CA cast bars when the associated unit dies.
    if result == ACTION_RESULT_DIED then
        if unitId then
            CA.castAlertsStop(self.alertList[unitId])
            self.alertList[unitId] = nil
        end
        if sourceUnitId then
            CA.castAlertsStop(self.alertList[sourceUnitId])
            self.alertList[sourceUnitId] = nil
        end
        return
    end

    if abilityId == VROL_PORTAL_CAST and result == ACTION_RESULT_BEGIN then
        self.portalTimer:reset()
        alerts:showAction("KILL Conjurer!")
        -- Use portal kill-time ability ID for the icon (matches BSCHTKA).
        CA.alertCast(VROL_PORTAL_KTIME, sourceUnitName, 3000,
            { -3, 0, false, { 0.7, 0.2, 0.9, 0.4 }, { 0.7, 0.2, 0.9, 0.8 } })

    elseif abilityId == VROL_FOG_CAST and result == ACTION_RESULT_BEGIN then
        self.fogTimer:reset()
        self.fogEndTime  = GetGameTimeMilliseconds() + FOG_DURATION * 1000
        self.fogHitCount = 0
        alerts:showAction("Dodge/Move! (Fog)")
        local cid = CA.alertCast(abilityId, sourceUnitName, 1000,
            { -3, 0, false, { 0.0, 0.0, 1, 0.4 }, { 0.1, 0.1, 1, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == VROL_FOG_INCREASE and result == ACTION_RESULT_BEGIN then
        -- Each group of FOG_EXTEND_HITS pulses extends the active fog by FOG_EXTEND_SECS.
        if self.fogEndTime > 0 then
            self.fogHitCount = self.fogHitCount + 1
            if self.fogHitCount >= FOG_EXTEND_HITS then
                self.fogHitCount = 0
                self.fogEndTime  = self.fogEndTime + FOG_EXTEND_SECS * 1000
            end
        end

    elseif abilityId == VROL_HARPOON and result == ACTION_RESULT_BEGIN then
        self.conduitTimer:reset()
        alerts:showAction("Kill Harpoon! (~16 s)")
        local cid = CA.castAlertsStart(abilityId, GetAbilityName(abilityId),
            16000, 16000,
            { 1, 0.7, 0, 0.5 },
            { 16000, "Harpoon!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == VROL_APOTHECARY and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Apothecary!")
        CA.alert(nil, "Interrupt Apothecary!", 0x0099FFFF,
            SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
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
        -- Phase 4.2: CA cast bar for the full 20 s portal window.
        self.portalKillBarId = CA.castAlertsStart(
            abilityId, GetAbilityName(abilityId),
            20000, 20000,
            { 1, 0.7, 0, 0.5 },
            { 20000, "KILL Conjurer!", 0.8, 0, 0, 0.9, SOUNDS.NONE })

    elseif changeType == EFFECT_RESULT_FADED then
        -- Stop the cast bar, then show pass/fail result.
        CA.castAlertsStop(self.portalKillBarId)
        self.portalKillBarId = nil

        if GetGameTimeMilliseconds() < self.portalKillExpires then
            alerts:showAction("Portal OK!")
            CA.alert(nil, "Portal OK!", 0x119911FF, SOUNDS.DUEL_WON, 2000)
        else
            alerts:showAction("Portal Failed!")
            CA.alert(nil, "Portal Failed!", 0x991111FF, SOUNDS.DUEL_FORFEIT, 2000)
        end
        self.portalKillExpires = 0
    end
end

-- 200ms timer display — writes to info lines 1-3.
function Vrol:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds()

    -- Info 1: fog duration while active, otherwise countdown to next cast.
    local fogRemMs = self.fogEndTime - now
    if fogRemMs > 0 then
        local s = fogRemMs / 1000
        local col = (s <= 5) and "|cff6666" or "|c6699ff"
        alerts:showInfo(1, col .. "Fog clears:|r " .. string.format("%.1f", s) .. "s")
    else
        if self.fogEndTime > 0 then self.fogEndTime = 0 end   -- auto-clear stale timestamp
        local t1 = self.fogTimer:remaining()
        alerts:showInfo(1, "Next fog: " .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or "soon!"))
    end

    local t2 = self.conduitTimer:remaining()
    local t3 = self.portalTimer:remaining()
    alerts:showInfo(2, "Conduit: " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
    alerts:showInfo(3, "Portal:  " .. (t3 > 0 and ZO_FormatCountdownTimer(t3) or "ready"))
end

function Vrol:onPowerUpdate(context, healthPercent)
    if healthPercent < 50 then
        self.bPORTAL_END = true
    end
end

return Vrol
