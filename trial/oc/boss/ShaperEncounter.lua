
local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- â”€â”€ Ability IDs (from OsseinCageHelper) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local OGRIM_CHARGE     = 236496   -- combatRoute: ACTION_RESULT_BEGIN â†’ MOVE caAlertCast (player)
local SHAPER_SHIELD    = 232511   -- combatRoute: (plain) EFFECT_RESULT_GAINED/FADED â†’ shield state
local CHANNELER_SHIELD = 232510   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ channelers alert

-- â”€â”€ CA colour palettes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local COL_CHARGE = { -3, 0, false, { 1, 0.4, 0, 0.4 }, { 1, 0.4, 0, 0.8 } }

-- â”€â”€ Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) â”€
local FALLBACK_DUR = 2000   -- Ogrim Charge: empirical

local ShaperEncounter = {}
ShaperEncounter.__index = ShaperEncounter

ShaperEncounter.key               = "shaper"
ShaperEncounter.nameAliases       = { "Shaper of Flesh" }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
ShaperEncounter.hmHealthThreshold = math.huge
-- location: placeholder â€” Oathsworn Pit arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

ShaperEncounter.stateSchema = {
    shaperShielded = false,
}

function ShaperEncounter.new()
    return BossBase.fromSchema(ShaperEncounter)
end

-- â”€â”€ Handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local function handleOgrimCharge(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "MOVE â€” Ogrim Charge!", dur, COL_CHARGE)
    if IsUnitPlayer(unitTag) then
        alerts:showAction("Ogrim Charge on YOU! Move!")
    else
        alerts:showAction("Ogrim Charge â†’ " .. target)
    end
end

local function handleShaperShield(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        self.shaperShielded = true
        CA.alert(nil, "Shaper shielded â€” kill channelers!", 0xAA44FFFF, SOUNDS.NONE, 4000)
        alerts:showAction("Shaper of Flesh shielded â€” kill channelers!")
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.shaperShielded = false
        CA.alert(nil, "Shaper vulnerable!", 0x44FF88FF, SOUNDS.NONE, 3000)
        alerts:showAction("Shaper vulnerable â€” BURN!")
    end
end

local function handleChannelerShield(self, context, alerts, abilityId, ...)
    self.shaperShielded = true
    alerts:showAction("Channelers shielding Shaper â€” eliminate them!")
end

-- â”€â”€ Routing tables (C3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ShaperEncounter.combatRoutes = {
    [OGRIM_CHARGE]     = { result = ACTION_RESULT_BEGIN,         fn = handleOgrimCharge },
    [SHAPER_SHIELD]    = handleShaperShield,
    [CHANNELER_SHIELD] = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleChannelerShield },
}

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

package.loaded["trial.oc.boss.ShaperEncounter"] = ShaperEncounter
return ShaperEncounter
