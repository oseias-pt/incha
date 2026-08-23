local Location = require("core.Location")

-- ── CombatAlerts helpers ──────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end

-- ── Ability IDs ───────────────────────────────────────────────────────────
local POWERFUL_THROW = 218971   -- BEGIN → caAlertCast; on player → explicit alert

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_THROW = { -3, 0, false, { 1, 0.5, 0, 0.4 }, { 1, 0.5, 0, 0.8 } }

local DarielEncounter = {
    id                = 2,
    key               = "dariel",
    nameAliases       = { "Dariel" },
    hmHealthThreshold = 0,
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

function DarielEncounter:reset() end

function DarielEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if result == ACTION_RESULT_BEGIN and abilityId == POWERFUL_THROW then
        local target = (unitName and unitName ~= "") and unitName or "?"
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2500 end
        caAlertCast(abilityId, "Throw → " .. target, dur, COL_THROW)
        if IsUnitPlayer(unitTag) then
            alerts:showAction("Powerful Throw on YOU!")
        else
            alerts:showAction("Powerful Throw → " .. target)
        end
    end
end

function DarielEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
end

function DarielEncounter:onUpdate(context, alerts)
    alerts:showInfo(1, "")
    alerts:showInfo(2, "")
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return DarielEncounter
