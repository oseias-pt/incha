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

local XorynEncounter = {
    id                = 5,
    key               = "xoryn",
    nameAliases       = { "Xoryn" },
    hmHealthThreshold = 100000000,
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
XorynEncounter.currentTimer = Timer.new(CURRENT_MAX_DUR)

-- ── State ─────────────────────────────────────────────────────────────────
XorynEncounter.holdingKnot    = false
XorynEncounter.holdingCurrent = false

function XorynEncounter:reset()
    self.currentTimer:clear()
    self.holdingKnot    = false
    self.holdingCurrent = false
end

function XorynEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if result == ACTION_RESULT_BEGIN then
        if abilityId == NECROTIC_BARRAGE then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 3000 end
            CA.alertCast(abilityId, "Necrotic Barrage!", dur, COL_NECROTIC)

        elseif abilityId == ACCELERATING_CHARGE then
            CA.alert(nil, "Chain Lightning incoming!", 0xFFFF44FF, SOUNDS.NONE, 3000)
            alerts:showAction("Accelerating Charge → Chain Lightning!")

        elseif abilityId == TEMPEST then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "MOVE from line!", dur, COL_TEMPEST)
            alerts:showAction("Tempest! MOVE from mirror line!")

        elseif abilityId == GLASS_STOMP_CAST then
            local target = (unitName and unitName ~= "") and unitName or "?"
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "Atronach AOE → " .. target, dur, COL_ATRONACH)
            if IsUnitPlayer(unitTag) then
                alerts:showAction("Atronach AOE on YOU!")
            end

        elseif abilityId == LUSTROUS_JAVELIN and IsUnitPlayer(unitTag) then
            CA.alert(nil, "Javelin on YOU!", 0xFF8844FF, SOUNDS.NONE, 3000)
            alerts:showAction("Lustrous Javelin on you!")
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        if not IsUnitPlayer(unitTag) then return end

        if abilityId == ARCANE_KNOT then
            self.holdingKnot = true
            CA.alert(nil, "Carry knot! Pass it!", 0xFFAA44FF, SOUNDS.NONE, 4000)
            alerts:showAction("Arcane Knot — carry and pass!")

        elseif abilityId == ARCANE_CONV_DEBUFF then
            CA.alert(nil, "TETHER! Move away!", 0xFF4444FF, SOUNDS.NONE, 3000)
            alerts:showAction("Tether on you! Separate from partner!")

        elseif abilityId == FLUCTUATING_CURRENT then
            self.holdingCurrent = true
            self.currentTimer:reset(CURRENT_MAX_DUR)
            CA.alert(nil, "Hold current! Drop at edge!", 0x44CCFFFF, SOUNDS.NONE, 3000)
            alerts:showAction("Fluctuating Current — hold, then drop!")

        elseif abilityId == OVERLOADED_CURRENT then
            CA.alert(nil, "DROP current!", 0xFF0000FF, SOUNDS.NONE, 2000)
            alerts:showAction("Overloaded — DROP the current!")
        end

    elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
        if abilityId == ARCANE_KNOT then
            self.holdingKnot = false
        elseif abilityId == FLUCTUATING_CURRENT then
            self.holdingCurrent = false
            self.currentTimer:clear()
        end
    end
end

function XorynEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
end

function XorynEncounter:onUpdate(context, alerts)
    -- Line 1: Fluctuating Current countdown (drop before 15s expires)
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

    -- Line 2: Arcane Knot status
    if self.holdingKnot then
        alerts:showInfo(2, "|cFFAA44Carrying Arcane Knot|r")
    else
        alerts:showInfo(2, "")
    end

    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return XorynEncounter
