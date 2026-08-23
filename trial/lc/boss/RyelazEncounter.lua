local Location = require("core.Location")

-- ── CombatAlerts helpers ──────────────────────────────────────────────────
local function caAlert(...)     if CombatAlerts then CombatAlerts.Alert(...)     end end
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end

-- ── Ability IDs ───────────────────────────────────────────────────────────
local BRILLIANT_ANNIHILATION = 214187   -- light side room wipe — BEGIN → STACK
local BLEAK_ANNIHILATION     = 214203   -- dark side room wipe  — BEGIN → STACK
local PORCIN_LIGHT           = 219329   -- EFFECT_GAINED_DURATION → player on Ryelaz (dark) side
local PORCIN_DARK            = 219330   -- EFFECT_GAINED_DURATION → player on Zilyesset (light) side

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_ANNIHIL = { -3, 0, false, { 1, 0.65, 0, 0.4 }, { 1, 0.65, 0, 0.8 } }

local RyelazEncounter = {
    id                = 1,
    key               = "ryelaz",
    nameAliases       = { "Count Ryelaz", "Zilyesset" },
    hmHealthThreshold = 40000000,
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── State ─────────────────────────────────────────────────────────────────
-- "ryelaz" = player on Ryelaz dark side
-- "zilyesset" = player on Zilyesset light side
-- nil = assignment unknown (split hasn't happened or effect not yet seen)
RyelazEncounter.playerSide = nil

function RyelazEncounter:reset()
    self.playerSide = nil
end

function RyelazEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if result == ACTION_RESULT_BEGIN then
        if abilityId == BRILLIANT_ANNIHILATION then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 3000 end
            caAlertCast(abilityId, "STACK — Annihilation!", dur, COL_ANNIHIL)
            alerts:showAction("Brilliant Annihilation! STACK!")

        elseif abilityId == BLEAK_ANNIHILATION then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 3000 end
            caAlertCast(abilityId, "STACK — Annihilation!", dur, COL_ANNIHIL)
            alerts:showAction("Bleak Annihilation! STACK!")
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
        if abilityId == PORCIN_LIGHT then
            self.playerSide = "ryelaz"
        elseif abilityId == PORCIN_DARK then
            self.playerSide = "zilyesset"
        end

    elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
        if abilityId == PORCIN_LIGHT or abilityId == PORCIN_DARK then
            self.playerSide = nil
        end
    end
end

function RyelazEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- Side assignment is tracked via onCombatEvent.
end

function RyelazEncounter:onUpdate(context, alerts)
    if self.playerSide == "ryelaz" then
        alerts:showInfo(1, "|cFFAA44Ryelaz side (dark)|r")
    elseif self.playerSide == "zilyesset" then
        alerts:showInfo(1, "|c8888FFZilyesset side (light)|r")
    else
        alerts:showInfo(1, "")
    end
    alerts:showInfo(2, "")
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return RyelazEncounter
