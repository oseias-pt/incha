local Location = require("core.Location")
local Timer = require("lib.Timer")

-- ── Phase 4.2: CombatAlerts helpers ──────────────────────────────────────
-- All calls silently no-op when CombatAlerts is not loaded.
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

-- ── Ability IDs (from BSCHTKA_Yandir.lua) ─────────────────────────────────
local TOTEM_POISION      = 133515  -- Chaurus Totem Spawn + cast  → resets timer + Dodge alert
local TOTEM_POISION_CP   = 133559  -- Second Chaurus poison cast   (delayed 26.8 s CA bar)
local TOTEM_HARPY_SPWN   = 133510  -- Harpy Totem Spawn            → resets timer
local TOTEM_DRAGON_SPWN  = 133045  -- Dragon Totem Spawn           → resets timer
local TOTEM_GARGYL_SPWN  = 133513  -- Gargoyle Totem Spawn         → resets timer
local TOTEM_GARGYL       = 133546  -- Gargoyle Totem cast          → Block alert
local YANDIR_HEALING     = 133242  -- Yandir heal cast             → Healing alert
local YANDIR_JUMP        = 132571  -- Yandir jump                  → Block alert
local SEA_ADDER_BILE_SPRAY = 136591  -- Sea Adder spray (player-targeted) → Dodge alert

-- ── Spawn/cast durations ──────────────────────────────────────────────────
local TOTEM_SPAWN_TIME  = 20
local GRYPHON_SPAWN_TIME = 60

local Yandir = {
    id = 1,
    key = "yandir",
    hmHealthThreshold = 72769370,
    location = Location.new(63200, 68900, 24300, 26300, 90500, 99600),
}

Yandir.totemTimer   = Timer.new(TOTEM_SPAWN_TIME)
Yandir.gryphonTimer = Timer.new(GRYPHON_SPAWN_TIME)
Yandir.bGRYPHON_SKIP      = false
Yandir.bGRYPHON_SKIP_TIME = -1
Yandir.bGRYPHON_SKIP_FAILHP = 0
-- Phase 4.2: [unitId] → CA cast bar ID; cleared and stopped on reset/death.
Yandir.alertList = {}

function Yandir:reset(forced)
    self.totemTimer:reset()
    self.gryphonTimer:reset()
    self.bGRYPHON_SKIP      = false
    self.bGRYPHON_SKIP_TIME = -1
    self.bGRYPHON_SKIP_FAILHP = 0
    self.PosionTotemID = -1
    self.BTotemCall    = false

    -- Phase 4.2: stop any lingering cast bars from the previous pull.
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
end


-- 200ms timer display — writes to info lines 1-2.
-- No-op when sink has no info handler (e.g. LegacyUI during the KA transition).
function Yandir:onUpdate(context, alerts)
    local t1 = self.totemTimer:remaining()
    local t2 = self.gryphonTimer:remaining()
    alerts:showInfo(1, "Totem:   " .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or "ready"))
    alerts:showInfo(2, "Gryphon: " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
end

-- Combat mechanic alerts and timer resets.
-- Phase 4.2: text alerts (showAction) + CombatAlerts cast bars side-by-side.
function Yandir:onCombatEvent(context, alerts, result, abilityId,
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
        -- If the player targeted by the poison totem dies, cancel delayed bar.
        if self.PosionTotemID == unitId or self.PosionTotemID == sourceUnitId then
            self.PosionTotemID = -1
            self.BTotemCall    = false
        end
        return
    end

    -- Any totem spawn resets the recurring spawn countdown.
    if result == ACTION_RESULT_BEGIN and (
        abilityId == TOTEM_POISION    or abilityId == TOTEM_HARPY_SPWN  or
        abilityId == TOTEM_DRAGON_SPWN or abilityId == TOTEM_GARGYL_SPWN)
    then
        self.totemTimer:reset()
    end

    -- Per-ability alerts + CA cast bars.
    if abilityId == TOTEM_POISION and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Dodge! (Poison Totem)")
        local cid = caAlertCast(abilityId, sourceUnitName, 4300,
            { -3, 0, false, { 0, 0.8, 0, 0.4 }, { 0, 0.8, 0, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
        self.PosionTotemID = unitId  -- track for delayed second-poison bar

    elseif abilityId == TOTEM_POISION_CP and result == ACTION_RESULT_EFFECT_GAINED then
        -- Second poison from the same totem ~26.8 s after first cast.
        -- Guard with BTotemCall so only one delayed bar fires per totem spawn.
        if self.BTotemCall then return end
        self.BTotemCall = true
        local capturedSrc  = sourceUnitName or ""
        local capturedSelf = self
        zo_callLater(function()
            if capturedSelf.PosionTotemID ~= -1 and IsUnitInCombat("player") then
                capturedSelf.BTotemCall = false
                caAlertCast(TOTEM_POISION_CP, capturedSrc, 4300,
                    { -3, 0, false, { 0, 0.8, 0, 0.4 }, { 0, 0.8, 0, 0.8 } })
            end
        end, 26800)

    elseif abilityId == TOTEM_GARGYL and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Block! (Gargoyle Totem)")
        local dur = select(1, GetAbilityCastInfo(TOTEM_GARGYL)) or 0
        if dur <= 0 then dur = 5000 end
        local cid = caAlertCast(abilityId, "Block!!", dur,
            { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == YANDIR_HEALING and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Casts Healing!")
        caAlert(nil, "Casts Healing!", 0x991111FF, SOUNDS.NONE, 2000)

    elseif abilityId == YANDIR_JUMP and result == ACTION_RESULT_BEGIN then
        alerts:showAction("(Jump) Block!!")
        local cid = caAlertCast(abilityId, "(Jump) Block!!", 3000,
            { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == SEA_ADDER_BILE_SPRAY and result == ACTION_RESULT_BEGIN
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Dodge! (Sea Adder)")
        local cid = caAlertCast(abilityId, sourceUnitName, 1933,
            { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
    end
end

function Yandir:onPowerUpdate(context, healthPercent)
    if healthPercent < 60 and not self.gryphonTimer:isExpired() then
        if not self.bGRYPHON_SKIP then
            self.bGRYPHON_SKIP_TIME = os.time()
        end
        self.bGRYPHON_SKIP = true
    end

    if healthPercent > 60 and self.gryphonTimer:isExpired() then
        if self.bGRYPHON_SKIP_FAILHP == 0 then
            self.bGRYPHON_SKIP_FAILHP = healthPercent
        end
    end
end

return Yandir
