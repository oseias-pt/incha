
local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- a"EURa"EUR Ability IDs a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR
local BRILLIANT_ANNIHILATION = 214187   -- combatRoute: ACTION_RESULT_BEGIN a+' light side room wipe; STACK
local BLEAK_ANNIHILATION     = 214203   -- combatRoute: ACTION_RESULT_BEGIN a+' dark side room wipe; STACK
local PORCIN_LIGHT           = 219329   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION / FADED a+' player on Ryelaz (dark) side
local PORCIN_DARK            = 219330   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION / FADED a+' player on Zilyesset (light) side

-- a"EURa"EUR CA colour palettes a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR
local COL_ANNIHIL = { -3, 0, false, { 1, 0.65, 0, 0.4 }, { 1, 0.65, 0, 0.8 } }

-- a"EURa"EUR Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) a"EUR
local FALLBACK_DUR = 3000   -- Annihilation channel: empirical

local RyelazEncounter = {}
RyelazEncounter.__index = RyelazEncounter

RyelazEncounter.key               = "ryelaz"
RyelazEncounter.nameAliases       = { "Count Ryelaz", "Zilyesset" }
RyelazEncounter.hmHealthThreshold = 40000000
-- location: placeholder aEUR" Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

-- a"EURa"EUR State a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR
-- "ryelaz"    = player on Ryelaz dark side
-- "zilyesset" = player on Zilyesset light side
-- nil         = assignment unknown (split hasn't happened or effect not yet seen)
RyelazEncounter.stateSchema = {}

function RyelazEncounter.new()
    return BossBase.fromSchema(RyelazEncounter)
end

-- a"EURa"EUR Routing tables (C3) a"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EURa"EUR

-- Annihilation: shared alertCast, different showAction label.
local function makeAnnihilHandler(label)
    return { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        local dur = CastDur.get(abilityId, FALLBACK_DUR)
        CA.alertCast(abilityId, "STACK aEUR" Annihilation!", dur, COL_ANNIHIL)
        alerts:showAction(label .. " STACK!")
    end }
end

local function handlePorcinLight(self, context, alerts, result, abilityId, unitTag, ...)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
        self.playerSide = "ryelaz"
    elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
        self.playerSide = nil
    end
end

local function handlePorcinDark(self, context, alerts, result, abilityId, unitTag, ...)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
        self.playerSide = "zilyesset"
    elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
        self.playerSide = nil
    end
end

RyelazEncounter.combatRoutes = {
    [BRILLIANT_ANNIHILATION] = makeAnnihilHandler("Brilliant Annihilation!"),
    [BLEAK_ANNIHILATION]     = makeAnnihilHandler("Bleak Annihilation!"),
    [PORCIN_LIGHT]           = handlePorcinLight,
    [PORCIN_DARK]            = handlePorcinDark,
}

function RyelazEncounter:onWipe()
    self.playerSide = nil
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

package.loaded["trial.lc.boss.RyelazEncounter"] = RyelazEncounter
return RyelazEncounter
