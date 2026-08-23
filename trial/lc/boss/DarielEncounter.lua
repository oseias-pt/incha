local Location = require("core.Location")

local CA = require("lib.CA")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local POWERFUL_THROW = 218971   -- BEGIN → caAlertCast; on player → explicit alert

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_THROW = { -3, 0, false, { 1, 0.5, 0, 0.4 }, { 1, 0.5, 0, 0.8 } }

local DarielEncounter = {}
DarielEncounter.__index = DarielEncounter

DarielEncounter.key               = "dariel"
DarielEncounter.nameAliases       = { "Dariel" }
DarielEncounter.hmHealthThreshold = 0
DarielEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

function DarielEncounter.new()
    return setmetatable({}, DarielEncounter)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

DarielEncounter.combatRoutes = {
    [POWERFUL_THROW] = function(self, context, alerts, result, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        local target = (unitName and unitName ~= "") and unitName or "?"
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2500 end
        CA.alertCast(abilityId, "Throw → " .. target, dur, COL_THROW)
        if IsUnitPlayer(unitTag) then
            alerts:showAction("Powerful Throw on YOU!")
        else
            alerts:showAction("Powerful Throw → " .. target)
        end
    end,
}

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
