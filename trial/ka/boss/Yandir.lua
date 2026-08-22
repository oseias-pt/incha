local Location = require("core.Location")
local Timer = require("lib.Timer")

-- ── Ability IDs (from BSCHTKA_Yandir.lua) ─────────────────────────────────
local TOTEM_POISION      = 133515  -- Chaurus Totem Spawn + cast  → resets timer + Dodge alert
local TOTEM_POISION_CP   = 133559  -- Second Chaurus poison cast   (delayed alert, TODO Phase 4.2)
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

function Yandir:reset(forced)
    self.totemTimer:reset()
    self.gryphonTimer:reset()
    self.bGRYPHON_SKIP      = false
    self.bGRYPHON_SKIP_TIME = -1
    self.bGRYPHON_SKIP_FAILHP = 0
    self.PosionTotemID   = -1
    self.PosionTotemIDSC = -1
    self.BTotemCall      = false

    self:syncLegacy()
end

function Yandir:syncLegacy()
    if not BSCHTKA then
        return
    end

    -- Legacy addon reads raw epoch timestamps, so expose expiresAt.
    BSCHTKA.GRYPHON_TIME         = self.gryphonTimer:getExpiresAt()
    BSCHTKA.TOTEM_TIME           = self.totemTimer:getExpiresAt()
    BSCHTKA.bGRYPHON_SKIP        = self.bGRYPHON_SKIP
    BSCHTKA.bGRYPHON_SKIP_TIME   = self.bGRYPHON_SKIP_TIME
    BSCHTKA.bGRYPHON_SKIP_FAILHP = self.bGRYPHON_SKIP_FAILHP
end

function Yandir:onEnter(context, alerts)
    context.extras.legacyFlag = "bYandir"
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
-- Phase 4.1: text-only (showAction).  Phase 4.2 adds CombatAlerts cast bars.
-- NOT registered while KA Factory still uses LegacyUI (Phase 4.4 wires this in).
function Yandir:onCombatEvent(context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId)
    -- Any totem spawn resets the recurring spawn countdown.
    if result == ACTION_RESULT_BEGIN and (
        abilityId == TOTEM_POISION    or abilityId == TOTEM_HARPY_SPWN  or
        abilityId == TOTEM_DRAGON_SPWN or abilityId == TOTEM_GARGYL_SPWN)
    then
        self.totemTimer:reset()
        self:syncLegacy()
    end

    -- Per-ability alerts.
    if abilityId == TOTEM_POISION and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Dodge! (Poison Totem)")

    elseif abilityId == TOTEM_GARGYL and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Block! (Gargoyle Totem)")

    elseif abilityId == YANDIR_HEALING and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Casts Healing!")

    elseif abilityId == YANDIR_JUMP and result == ACTION_RESULT_BEGIN then
        alerts:showAction("(Jump) Block!!")

    elseif abilityId == SEA_ADDER_BILE_SPRAY and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Dodge! (Sea Adder)")
    end

    -- TODO Phase 4.2: TOTEM_POISION_CP (133559) — BSCHTKA fires a second
    -- CombatAlerts cast bar ~26.8 s after the totem gains its poison effect,
    -- if the totem is still alive.  Implement once CombatAlerts is available.
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

    self:syncLegacy()
end

return Yandir
