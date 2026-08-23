local Location = require("core.Location")

local CA = require("lib.CA")

-- ── Ability IDs (from OsseinCageHelper) ──────────────────────────────────
local OGRIM_CHARGE     = 236496   -- BEGIN on player → MOVE alert + caAlertCast
local SHAPER_SHIELD    = 232511   -- EFFECT_GAINED → shaper protected; FADED → vulnerable
local CHANNELER_SHIELD = 232510   -- EFFECT_GAINED → channelers shielding Shaper

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_CHARGE = { -3, 0, false, { 1, 0.4, 0, 0.4 }, { 1, 0.4, 0, 0.8 } }

local ShaperEncounter = {

    key               = "shaper",
    nameAliases       = { "Shaper of Flesh" },
    hmHealthThreshold = 0,
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── State ─────────────────────────────────────────────────────────────────
ShaperEncounter.shaperShielded = false

function ShaperEncounter:reset()
    self.shaperShielded = false
end

function ShaperEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if result == ACTION_RESULT_BEGIN then
        if abilityId == OGRIM_CHARGE then
            local target = (unitName and unitName ~= "") and unitName or "?"
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "MOVE — Ogrim Charge!", dur, COL_CHARGE)
            if IsUnitPlayer(unitTag) then
                alerts:showAction("Ogrim Charge on YOU! Move!")
            else
                alerts:showAction("Ogrim Charge → " .. target)
            end
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED then
        if abilityId == SHAPER_SHIELD then
            self.shaperShielded = true
            CA.alert(nil, "Shaper shielded — kill channelers!", 0xAA44FFFF, SOUNDS.NONE, 4000)
            alerts:showAction("Shaper of Flesh shielded — kill channelers!")

        elseif abilityId == CHANNELER_SHIELD then
            self.shaperShielded = true
            alerts:showAction("Channelers shielding Shaper — eliminate them!")
        end

    elseif result == ACTION_RESULT_EFFECT_FADED then
        if abilityId == SHAPER_SHIELD then
            self.shaperShielded = false
            CA.alert(nil, "Shaper vulnerable!", 0x44FF88FF, SOUNDS.NONE, 3000)
            alerts:showAction("Shaper vulnerable — BURN!")
        end
    end
end

function ShaperEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
end

function ShaperEncounter:onUpdate(context, alerts)
    -- Line 1: Shaper shield status
    if self.shaperShielded then
        alerts:showInfo(1, "|cAA44FFShaper: SHIELDED|r")
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

return ShaperEncounter
