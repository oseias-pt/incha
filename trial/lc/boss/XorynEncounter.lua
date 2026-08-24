local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local ARCANE_KNOT         = 213477   -- EFFECT_GAINED_DURATION on player → carry knot
local ARCANE_CONV_DEBUFF  = 223060   -- EFFECT_GAINED_DURATION on player → tether
local FLUCTUATING_CURRENT = 214597   -- EFFECT_GAINED_DURATION on player → hold (15s max)
local OVERLOADED_CURRENT  = 214745   -- EFFECT_GAINED_DURATION on player → DROP
local NECROTIC_BARRAGE    = 223198   -- BEGIN → caAlertCast
local ACCELERATING_CHARGE = 214542   -- BEGIN → chain lightning incoming
local TEMPEST             = 215107   -- BEGIN → MOVE from mirror line
local GLASS_STOMP_CAST    = 219797   -- BEGIN → Crystal Atronach AOE on tank
local LUSTROUS_JAVELIN    = 223546   -- BEGIN on player → alert

-- ── Constants ─────────────────────────────────────────────────────────────
local CURRENT_MAX_DUR = 15.0   -- holding Fluctuating Current beyond this = death

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_NECROTIC  = { -3, 0, false, { 0.5, 0,   0.9, 0.4 }, { 0.5, 0,   0.9, 0.8 } }
local COL_TEMPEST   = { -3, 0, false, { 0.2, 0.8, 1.0, 0.4 }, { 0.2, 0.8, 1.0, 0.8 } }
local COL_ATRONACH  = { -3, 0, false, { 1,   0.4, 0,   0.4 }, { 1,   0.4, 0,   0.8 } }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_BARRAGE_DUR = 3000   -- NecroticBarrage: empirical
local FALLBACK_DUR         = 2000   -- Tempest / GlassStomp: empirical

local XorynEncounter = {}
XorynEncounter.__index = XorynEncounter

XorynEncounter.key               = "xoryn"
XorynEncounter.nameAliases       = { "Xoryn" }
XorynEncounter.hmHealthThreshold = 100000000
XorynEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

function XorynEncounter.new()
    return setmetatable({
        currentTimer    = Timer.new(CURRENT_MAX_DUR),
        holdingKnot     = false,
        holdingCurrent  = false,
    }, XorynEncounter)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
XorynEncounter.combatRoutes = {
    [NECROTIC_BARRAGE] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALLBACK_BARRAGE_DUR end
        CA.alertCast(abilityId, "Necrotic Barrage!", dur, COL_NECROTIC)
    end },
    [ACCELERATING_CHARGE] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        CA.alert(nil, "Chain Lightning incoming!", 0xFFFF44FF, SOUNDS.NONE, 3000)
        alerts:showAction("Accelerating Charge → Chain Lightning!")
    end },
    [TEMPEST] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALLBACK_DUR end
        CA.alertCast(abilityId, "MOVE from line!", dur, COL_TEMPEST)
        alerts:showAction("Tempest! MOVE from mirror line!")
    end },
    [GLASS_STOMP_CAST] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId,
                      unitTag, sourceUnitTag, sourceUnitId, unitId,
                      sourceUnitName, unitName)
        local target = (unitName and unitName ~= "") and unitName or "?"
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALLBACK_DUR end
        CA.alertCast(abilityId, "Atronach AOE → " .. target, dur, COL_ATRONACH)
        if IsUnitPlayer(unitTag) then
            alerts:showAction("Atronach AOE on YOU!")
        end
    end },
    [LUSTROUS_JAVELIN] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.alert(nil, "Javelin on YOU!", 0xFF8844FF, SOUNDS.NONE, 3000)
        alerts:showAction("Lustrous Javelin on you!")
    end },
    [ARCANE_KNOT] = function(self, context, alerts, result, abilityId, unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
            self.holdingKnot = true
            CA.alert(nil, "Carry knot! Pass it!", 0xFFAA44FF, SOUNDS.NONE, 4000)
            alerts:showAction("Arcane Knot — carry and pass!")
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.holdingKnot = false
        end
    end,
    [ARCANE_CONV_DEBUFF] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,
        fn = function(self, context, alerts, abilityId, unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.alert(nil, "TETHER! Move away!", 0xFF4444FF, SOUNDS.NONE, 3000)
        alerts:showAction("Tether on you! Separate from partner!")
    end },
    [FLUCTUATING_CURRENT] = function(self, context, alerts, result, abilityId, unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
            self.holdingCurrent = true
            self.currentTimer:reset(CURRENT_MAX_DUR)
            CA.alert(nil, "Hold current! Drop at edge!", 0x44CCFFFF, SOUNDS.NONE, 3000)
            alerts:showAction("Fluctuating Current — hold, then drop!")
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.holdingCurrent = false
            self.currentTimer:clear()
        end
    end,
    [OVERLOADED_CURRENT] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,
        fn = function(self, context, alerts, abilityId, unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.alert(nil, "DROP current!", 0xFF0000FF, SOUNDS.NONE, 2000)
        alerts:showAction("Overloaded — DROP the current!")
    end },
}

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Line 1: Fluctuating Current countdown; "DROP NOW!" when the 15 s window expires.
local function showCurrentLine(self, alerts)
    if self.holdingCurrent then
        local r = self.currentTimer:remaining()
        if r > 0 then
            alerts:showInfo(1, "|c44CCFFCurrent: " .. string.format("%.0f", r) .. "s|r")
        else
            alerts:showInfo(1, "|cFF0000DROP NOW!|r")
        end
    else
        alerts:showInfo(1, "")
    end
end

-- Line 2: Arcane Knot carrier indicator.
local function showKnotLine(self, alerts)
    if self.holdingKnot then
        alerts:showInfo(2, "|cFFAA44Carrying Arcane Knot|r")
    else
        alerts:showInfo(2, "")
    end
end

function XorynEncounter:onUpdate(context, alerts)
    showCurrentLine(self, alerts)
    showKnotLine(self, alerts)
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return XorynEncounter
