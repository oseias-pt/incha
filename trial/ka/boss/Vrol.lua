local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local Settings = require("core.Settings")

-- ── Ability IDs (from BSCHTKA_Vrol.lua) ───────────────────────────────────
local VROL_PORTAL_CAST  = 133994  -- combatRoute: ACTION_RESULT_BEGIN → reset portal timer + alert
local VROL_FOG_CAST     = 133808  -- combatRoute: ACTION_RESULT_BEGIN → starts fog duration countdown
local VROL_FOG_INCREASE = 133756  -- combatRoute: ACTION_RESULT_BEGIN → extends fog +9s per 3 hits
local VROL_PORTAL_KTIME = 134016  -- effectRoute: EFFECT_RESULT_GAINED / FADED → kill-time debuff
local VROL_HARPOON      = 133913  -- combatRoute: ACTION_RESULT_BEGIN → reset conduit timer + alert
local VROL_APOTHECARY   = 140255  -- combatRoute: ACTION_RESULT_BEGIN → Interrupt alert

-- ── Timer durations ───────────────────────────────────────────────────────
local NEXT_PORTAL_TIME  = 45
local NEXT_CONDUIT_TIME = 40
local NEXT_FOG_TIME     = 30
-- FOG_DURATION: the room stays fogged for ~30 s after the cast lands.
-- HowToKyne reads this from the old-API hitValue field, which is not exposed
-- in the modern EVENT_COMBAT_EVENT format used by incha.  30 s matches both
-- BSCHTKA's NEXT_FOG_TIME constant and empirical observation, so it is safe
-- to keep as a literal.  Revisit if ZOS ever changes the mechanic duration.
local FOG_DURATION      = 30     -- seconds the fog fills the room after the cast lands
local FOG_EXTEND_HITS   = 3      -- pulse hits before fog duration extends
local FOG_EXTEND_SECS   = 9      -- seconds added per extension cycle

local INITIAL_PORTAL_DELAY = 15  -- first portal is shorter than the recurring interval

-- World-coord portal position icon handle.  Stored at module level so it
-- survives across boss-instance replacements (which happen after each wipe).
-- Created in onEnter once per zone visit; discarded in onLeave on zone exit.
local _portalIcon = false

local Vrol = {}
Vrol.__index = Vrol
setmetatable(Vrol, {__index = BossBase})   -- inherit cleanupAlertList, default onDied

Vrol.key               = "vrol"
Vrol.hmHealthThreshold = 72769370
Vrol.location          = Location.new(110200, 118500, 24500, 29000, 65000, 78800)

Vrol.stateSchema = {
    -- Timers start expired; onCombatState arms them when the fight begins.
    portalTimer       = function() return Timer.new(NEXT_PORTAL_TIME) end,
    conduitTimer      = function() return Timer.new(NEXT_CONDUIT_TIME) end,
    fogTimer          = function() return Timer.new(NEXT_FOG_TIME) end,
    bPORTAL_END       = false,
    -- Portal kill-timer: ms timestamp when the current portal debuff expires.
    portalKillExpires = 0,
    -- CA bar ID for the active portal kill-timer debuff (false when not in portal).
    portalKillBarId   = false,
    -- [unitId] → CA cast bar ID; cleared on leave/death.
    alertList         = function() return {} end,
    -- Fog duration tracking: ms timestamp when fog clears (0 = no active fog).
    -- fogHitCount counts VROL_FOG_INCREASE pulses; resets every FOG_EXTEND_HITS.
    fogEndTime        = 0,
    fogHitCount       = 0,
}

function Vrol.new()
    return BossBase.fromSchema(Vrol)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Vrol:onEnter(context, alerts)
    if Settings.trial("ka").portalIconVrol and OSI and OSI.CreatePositionIcon then
        zo_callLater(function()
            if not _portalIcon then
                _portalIcon = OSI.CreatePositionIcon(
                    114624, 25764, 71349,
                    "/esoui/art/icons/malatar_agonizingbolts.dds",
                    100, { 1, 1, 1 })
            end
        end, 3100)
    end
end

function Vrol:onLeave(context)
    self:cleanupAlertList()
    CA.castAlertsStop(self.portalKillBarId)
    self.portalKillBarId = false
    if _portalIcon and OSI and OSI.DiscardPositionIcon then
        OSI.DiscardPositionIcon(_portalIcon)
        _portalIcon = false
    end
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Vrol:onCombatState(context, inCombat, alerts)
    if inCombat then
        -- First portal always spawns sooner than the recurring interval.
        self.portalTimer:reset(INITIAL_PORTAL_DELAY)
        self.conduitTimer:reset()
        self.fogTimer:reset()
    end
end

-- Soft reset on wipe while still inside the Vrol arena.  Stops active bars
-- and clears per-pull state so the next pull starts clean.  The portal world-
-- coord icon is intentionally kept: it marks the fixed spawn location and
-- remains useful at the start of every pull, so discarding it on a wipe
-- would just force a redundant 3.1 s re-creation on the next onEnter.
function Vrol:onWipe(context, alerts)
    self:cleanupAlertList()
    CA.castAlertsStop(self.portalKillBarId)
    self.portalKillBarId   = false
    self.bPORTAL_END       = false
    self.fogEndTime        = 0
    self.fogHitCount       = 0
    self.portalKillExpires = 0
end


-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- DIED: clean up tracked CA cast bars for both the unit and its killer.
function Vrol:onDied(context, alerts,
                      unitTag, sourceUnitTag, sourceUnitId, unitId,
                      sourceUnitName, unitName)
    if unitId then
        CA.castAlertsStop(self.alertList[unitId])
        self.alertList[unitId] = nil
    end
    if sourceUnitId then
        CA.castAlertsStop(self.alertList[sourceUnitId])
        self.alertList[sourceUnitId] = nil
    end
end

local function handlePortalCast(self, context, alerts, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    self.portalTimer:reset()
    alerts:showAction("KILL Conjurer!")
    -- Use portal kill-time ability ID for the icon (matches BSCHTKA).
    CA.alertCast(VROL_PORTAL_KTIME, sourceUnitName, 3000,
        { -3, 0, false, { 0.7, 0.2, 0.9, 0.4 }, { 0.7, 0.2, 0.9, 0.8 } })
end

local function handleFogCast(self, context, alerts, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    self.fogTimer:reset()
    self.fogEndTime  = GetGameTimeMilliseconds() + FOG_DURATION * 1000
    self.fogHitCount = 0
    alerts:showAction("Dodge/Move! (Fog)")
    local cid = CA.alertCast(abilityId, sourceUnitName, 1000,
        { -3, 0, false, { 0.0, 0.0, 1, 0.4 }, { 0.1, 0.1, 1, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleFogIncrease(self, context, alerts, abilityId, ...)
    -- Each group of FOG_EXTEND_HITS pulses extends the active fog by FOG_EXTEND_SECS.
    if self.fogEndTime > 0 then
        self.fogHitCount = self.fogHitCount + 1
        if self.fogHitCount >= FOG_EXTEND_HITS then
            self.fogHitCount = 0
            self.fogEndTime  = self.fogEndTime + FOG_EXTEND_SECS * 1000
        end
    end
end

local function handleHarpoon(self, context, alerts, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    self.conduitTimer:reset()
    alerts:showAction("Kill Harpoon! (~16 s)")
    local cid = CA.castAlertsStart(abilityId, GetAbilityName(abilityId),
        16000, 16000,
        { 1, 0.7, 0, 0.5 },
        { 16000, "Harpoon!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleApothecary(self, context, alerts, abilityId, ...)
    alerts:showAction("Interrupt Apothecary!")
    CA.alert(nil, "Interrupt Apothecary!", 0x0099FFFF,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
end

Vrol.combatRoutes = {
    [VROL_PORTAL_CAST]  = { result = ACTION_RESULT_BEGIN, fn = handlePortalCast },
    [VROL_FOG_CAST]     = { result = ACTION_RESULT_BEGIN, fn = handleFogCast },
    [VROL_FOG_INCREASE] = { result = ACTION_RESULT_BEGIN, fn = handleFogIncrease },
    [VROL_HARPOON]      = { result = ACTION_RESULT_BEGIN, fn = handleHarpoon },
    [VROL_APOTHECARY]   = { result = ACTION_RESULT_BEGIN, fn = handleApothecary },
}

-- Portal kill-timer debuff on the local player (EVENT_EFFECT_CHANGED).
-- GAINED = player entered portal → 20 s to kill the Conjurer.
-- FADED  = debuff removed → check if Conjurer was killed in time.
local function handlePortalKillTime(self, context, alerts, changeType, abilityId,
                                     unitTag, unitId, unitName, stackCount)
    -- Only react to the local player's portal debuff.
    if unitTag ~= GetLocalPlayerGroupUnitTag() then return end

    if changeType == EFFECT_RESULT_GAINED then
        self.portalKillExpires = GetGameTimeMilliseconds() + 20000
        alerts:showAction("KILL Conjurer! (20 s)")
        self.portalKillBarId = CA.castAlertsStart(
            abilityId, GetAbilityName(abilityId),
            20000, 20000,
            { 1, 0.7, 0, 0.5 },
            { 20000, "KILL Conjurer!", 0.8, 0, 0, 0.9, SOUNDS.NONE })

    elseif changeType == EFFECT_RESULT_FADED then
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

Vrol.effectRoutes = {
    [VROL_PORTAL_KTIME] = handlePortalKillTime,
}

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
    alerts:showInfo(2, "Conduit: " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))

    -- Portals stop spawning once Vrol drops below 50% HP.  Suppress the
    -- countdown when bPORTAL_END is set so we don't show stale "ready" text.
    if self.bPORTAL_END then
        alerts:showInfo(3, "")
    else
        local t3 = self.portalTimer:remaining()
        alerts:showInfo(3, "Portal:  " .. (t3 > 0 and ZO_FormatCountdownTimer(t3) or "ready"))
    end
end

function Vrol:onPowerUpdate(context, healthPercent)
    if healthPercent < 50 then
        self.bPORTAL_END = true
    end
end

return Vrol
