local Location = require("core.Location")

local CA = require("lib.CA")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local BRILLIANT_ANNIHILATION = 214187   -- light side room wipe — BEGIN → STACK
local BLEAK_ANNIHILATION     = 214203   -- dark side room wipe  — BEGIN → STACK
local PORCIN_LIGHT           = 219329   -- EFFECT_GAINED_DURATION → player on Ryelaz (dark) side
local PORCIN_DARK            = 219330   -- EFFECT_GAINED_DURATION → player on Zilyesset (light) side

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_ANNIHIL = { -3, 0, false, { 1, 0.65, 0, 0.4 }, { 1, 0.65, 0, 0.8 } }

local RyelazEncounter = {}
RyelazEncounter.__index = RyelazEncounter

RyelazEncounter.key               = "ryelaz"
RyelazEncounter.nameAliases       = { "Count Ryelaz", "Zilyesset" }
RyelazEncounter.hmHealthThreshold = 40000000
RyelazEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

-- ── State ─────────────────────────────────────────────────────────────────
-- "ryelaz"    = player on Ryelaz dark side
-- "zilyesset" = player on Zilyesset light side
-- nil         = assignment unknown (split hasn't happened or effect not yet seen)
function RyelazEncounter.new()
    return setmetatable({
        playerSide = nil,
    }, RyelazEncounter)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Annihilation: shared alertCast, different showAction label.
local function makeAnnihilHandler(label)
    return function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 3000 end
        CA.alertCast(abilityId, "STACK — Annihilation!", dur, COL_ANNIHIL)
        alerts:showAction(label .. " STACK!")
    end
end

-- Porcin FADED: shared for both light/dark — clear playerSide.
local function handlePorcinFaded(self, context, alerts, result, abilityId,
                                  unitTag, ...)
    if result ~= ACTION_RESULT_EFFECT_FADED then return end
    if not IsUnitPlayer(unitTag) then return end
    self.playerSide = nil
end

RyelazEncounter.combatRoutes = {
    [BRILLIANT_ANNIHILATION] = makeAnnihilHandler("Brilliant Annihilation!"),
    [BLEAK_ANNIHILATION]     = makeAnnihilHandler("Bleak Annihilation!"),
    [PORCIN_LIGHT] = function(self, context, alerts, result, abilityId,
                               unitTag, ...)
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
            self.playerSide = "ryelaz"
        elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
            self.playerSide = nil
        end
    end,
    [PORCIN_DARK] = function(self, context, alerts, result, abilityId,
                              unitTag, ...)
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
            self.playerSide = "zilyesset"
        elseif result == ACTION_RESULT_EFFECT_FADED and IsUnitPlayer(unitTag) then
            self.playerSide = nil
        end
    end,
}

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
