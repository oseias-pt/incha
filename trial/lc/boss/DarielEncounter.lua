
local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- a"EURa"EUR Ability IDs a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR
local POWERFUL_THROW = 218971   -- combatRoute: ACTION_RESULT_BEGIN a+' caAlertCast; on player a+' explicit alert

-- a"EURa"EUR CA colour palettes a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR
local COL_THROW = { -3, 0, false, { 1, 0.5, 0, 0.4 }, { 1, 0.5, 0, 0.8 } }

-- a"EURa"EUR Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) a"EUR
local FALLBACK_DUR = 2500   -- PowerfulThrow: empirical

local DarielEncounter = {}
DarielEncounter.__index = DarielEncounter

DarielEncounter.key               = "dariel"
DarielEncounter.nameAliases       = { "Dariel" }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
DarielEncounter.hmHealthThreshold = math.huge
-- location: placeholder aEUR" Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

DarielEncounter.stateSchema = {}

function DarielEncounter.new()
    return BossBase.fromSchema(DarielEncounter)
end

-- a"EURa"EUR Handlers a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR

local function handlePowerfulThrow(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "Throw a+' " .. target, dur, COL_THROW)
    if IsUnitPlayer(unitTag) then
        alerts:showAction("Powerful Throw on YOU!")
    else
        alerts:showAction("Powerful Throw a+' " .. target)
    end
end

-- a"EURa"EUR Routing tables (C3) a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR

DarielEncounter.combatRoutes = {
    [POWERFUL_THROW] = { result = ACTION_RESULT_BEGIN, fn = handlePowerfulThrow },
}

function DarielEncounter:onWipe()
    -- stateSchema is empty; no state to reset.
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

package.loaded["trial.lc.boss.DarielEncounter"] = DarielEncounter
return DarielEncounter
