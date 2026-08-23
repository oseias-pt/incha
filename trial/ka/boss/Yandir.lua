local Location = require("core.Location")
local Timer = require("lib.Timer")

local CA = require("lib.CA")

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

local Yandir = {}
Yandir.__index = Yandir

Yandir.key               = "yandir"
Yandir.hmHealthThreshold = 72769370
Yandir.location          = Location.new(63200, 68900, 24300, 26300, 90500, 99600)

function Yandir.new()
    return setmetatable({
        totemTimer           = Timer.new(TOTEM_SPAWN_TIME),
        gryphonTimer         = Timer.new(GRYPHON_SPAWN_TIME),
        bGRYPHON_SKIP        = false,
        bGRYPHON_SKIP_TIME   = -1,
        bGRYPHON_SKIP_FAILHP = 0,
        PosionTotemID        = -1,
        BTotemCall           = false,
        -- Phase 4.2: [unitId] → CA cast bar ID; cleared and stopped on leave/death.
        alertList            = {},
    }, Yandir)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Yandir:onLeave(context)
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
end


-- 200ms timer display — writes to info lines 1-2.
-- No-op when sink has no info handler (e.g. LegacyUI during the KA transition).
function Yandir:onUpdate(context, alerts)
    local t1 = self.totemTimer:remaining()
    local t2 = self.gryphonTimer:remaining()
    alerts:showInfo(1, "Totem:   " .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or "ready"))
    alerts:showInfo(2, "Gryphon: " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- DIED: clean up alertList + totem tracker.
function Yandir:onDied(context, alerts,
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
    -- If the player targeted by the poison totem dies, cancel delayed bar.
    if self.PosionTotemID == unitId or self.PosionTotemID == sourceUnitId then
        self.PosionTotemID = -1
        self.BTotemCall    = false
    end
end

-- Any totem spawn (Harpy/Dragon/Gargoyle spawn IDs) resets the recurring timer.
local function resetTotemTimer(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_BEGIN then self.totemTimer:reset() end
end

Yandir.combatRoutes = {
    [TOTEM_POISION] = function(self, context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.totemTimer:reset()
        alerts:showAction("Dodge! (Poison Totem)")
        local cid = CA.alertCast(abilityId, sourceUnitName, 4300,
            { -3, 0, false, { 0, 0.8, 0, 0.4 }, { 0, 0.8, 0, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
        self.PosionTotemID = unitId  -- track for delayed second-poison bar
    end,
    [TOTEM_POISION_CP] = function(self, context, alerts, result, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
        -- Second poison from the same totem ~26.8 s after first cast.
        -- Guard with BTotemCall so only one delayed bar fires per totem spawn.
        if result ~= ACTION_RESULT_EFFECT_GAINED then return end
        if self.BTotemCall then return end
        self.BTotemCall = true
        local capturedSrc  = sourceUnitName or ""
        local capturedSelf = self
        zo_callLater(function()
            if capturedSelf.PosionTotemID ~= -1 and IsUnitInCombat("player") then
                capturedSelf.BTotemCall = false
                CA.alertCast(TOTEM_POISION_CP, capturedSrc, 4300,
                    { -3, 0, false, { 0, 0.8, 0, 0.4 }, { 0, 0.8, 0, 0.8 } })
            end
        end, 26800)
    end,
    [TOTEM_HARPY_SPWN]  = resetTotemTimer,
    [TOTEM_DRAGON_SPWN] = resetTotemTimer,
    [TOTEM_GARGYL_SPWN] = resetTotemTimer,
    [TOTEM_GARGYL] = function(self, context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        alerts:showAction("Block! (Gargoyle Totem)")
        local dur = select(1, GetAbilityCastInfo(TOTEM_GARGYL)) or 0
        if dur <= 0 then dur = 5000 end
        local cid = CA.alertCast(abilityId, "Block!!", dur,
            { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
    end,
    [YANDIR_HEALING] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        alerts:showAction("Casts Healing!")
        CA.alert(nil, "Casts Healing!", 0x991111FF, SOUNDS.NONE, 2000)
    end,
    [YANDIR_JUMP] = function(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        alerts:showAction("(Jump) Block!!")
        local cid = CA.alertCast(abilityId, "(Jump) Block!!", 3000,
            { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
    end,
    [SEA_ADDER_BILE_SPRAY] = function(self, context, alerts, result, abilityId,
                                       unitTag, sourceUnitTag, sourceUnitId, unitId,
                                       sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        if not IsUnitPlayer(unitTag) then return end
        alerts:showAction("Dodge! (Sea Adder)")
        local cid = CA.alertCast(abilityId, sourceUnitName, 1933,
            { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
    end,
}

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
