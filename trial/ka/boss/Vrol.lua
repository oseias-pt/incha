local Location = require("core.Location")
local Timer    = require("lib.Timer")

-- ── Phase 4.2: CombatAlerts helpers ──────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end
local function caCastAlertsStart(...)
    if CombatAlerts then return CombatAlerts.CastAlertsStart(...) end
end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

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
-- Phase 4.2: [unitId] → CA cast bar ID; cleared on reset/death.
Vrol.alertList         = {}
-- Phase 4.2: CA cast bar ID for the portal-kill debuff (started/stopped in onEffectChanged).
Vrol.portalKillBarId   = nil

function Vrol:reset(forced)
    -- First portal always spawns sooner than the recurring interval.
    self.portalTimer:reset(INITIAL_PORTAL_DELAY)
    self.conduitTimer:reset()
    self.fogTimer:reset()
    self.bPORTAL_END = false

    -- Phase 4.2: stop any lingering cast bars from the previous pull.
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
    caCastAlertsStop(self.portalKillBarId)
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
            caCastAlertsStop(self.alertList[unitId])
            self.alertList[unitId] = nil
        end
        if sourceUnitId then
            caCastAlertsStop(self.alertList[sourceUnitId])
            self.alertList[sourceUnitId] = nil
        end
        return
    end

    if abilityId == VROL_PORTAL_CAST and result == ACTION_RESULT_BEGIN then
        self.portalTimer:reset()
        alerts:showAction("KILL Conjurer!")
        -- Use portal kill-time ability ID for the icon (matches BSCHTKA).
        caAlertCast(VROL_PORTAL_KTIME, sourceUnitName, 3000,
            { -3, 0, false, { 0.7, 0.2, 0.9, 0.4 }, { 0.7, 0.2, 0.9, 0.8 } })

    elseif abilityId == VROL_FOG_CAST and result == ACTION_RESULT_BEGIN then
        self.fogTimer:reset()
        alerts:showAction("Dodge/Move! (Fog)")
        local cid = caAlertCast(abilityId, sourceUnitName, 1000,
            { -3, 0, false, { 0.0, 0.0, 1, 0.4 }, { 0.1, 0.1, 1, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == VROL_HARPOON and result == ACTION_RESULT_BEGIN then
        self.conduitTimer:reset()
        alerts:showAction("Kill Harpoon! (~16 s)")
        local cid = caCastAlertsStart(abilityId, GetAbilityName(abilityId),
            16000, 16000,
            { 1, 0.7, 0, 0.5 },
            { 16000, "Harpoon!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == VROL_APOTHECARY and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Apothecary!")
        caAlert(nil, "Interrupt Apothecary!", 0x0099FFFF,
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
        self.portalKillBarId = caCastAlertsStart(
            abilityId, GetAbilityName(abilityId),
            20000, 20000,
            { 1, 0.7, 0, 0.5 },
            { 20000, "KILL Conjurer!", 0.8, 0, 0, 0.9, SOUNDS.NONE })

    elseif changeType == EFFECT_RESULT_FADED then
        -- Stop the cast bar, then show pass/fail result.
        caCastAlertsStop(self.portalKillBarId)
        self.portalKillBarId = nil

        if GetGameTimeMilliseconds() < self.portalKillExpires then
            alerts:showAction("Portal OK!")
            caAlert(nil, "Portal OK!", 0x119911FF, SOUNDS.DUEL_WON, 2000)
        else
            alerts:showAction("Portal Failed!")
            caAlert(nil, "Portal Failed!", 0x991111FF, SOUNDS.DUEL_FORFEIT, 2000)
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
end

return Vrol
