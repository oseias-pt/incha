local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs (from OsseinCageHelper) ──────────────────────────────────
-- Chains
local CHAINS_1        = 232773   -- EFFECT_GAINED_DURATION → player chained
local CHAINS_2        = 232775   -- variant
local TORTUOUS_CHAINS = 236338   -- EFFECT_GAINED on player → red border
-- Vile Leap
local VILE_LEAP       = 235557   -- BEGIN → caAlertCast; purple
local SEETHING_LEAP   = 245208   -- enrage variant → caAlertCast; red
-- Agonizer Bombs
local AGONIZER_BOMBS  = 237149   -- BEGIN → alert (debounced 5s)
-- Biting Blaze (6-target fire)
local BITING_BLAZE_1  = 235354
local BITING_BLAZE_2  = 246009
-- Giant Sword / cones
local GIANT_PULSE_1   = 235495
local GIANT_PULSE_2   = 244937
local GIANT_CONES     = 232574   -- BEGIN → "Dodge cones!"
local SHOCK_SPEAR     = 235514   -- BEGIN → "Dodge spear!"
-- Molag Kena adds
local STORM_SLAM      = 235201   -- BEGIN → caAlertCast "Dodge!"
local STORM_SURGE     = 235205   -- BEGIN → caAlertCast
local HEAVY_SHOCK     = 235206   -- BEGIN on player → alert
-- Portal / teleport
local VILE_TELEPORT   = 232969   -- BEGIN → portal phase++
-- Channelers (each EFFECT_FADED = one channeler killed)
local CHANNELER_RITUAL = 234349
-- Debuffs on player
local STRICKEN        = 235594   -- EFFECT_GAINED_DURATION on player → alert
local FIREBOMB_DEBUF  = 245264   -- EFFECT_GAINED_DURATION on player → alert
local IMMOLATING_SPHRE= 237011   -- BEGIN on player → alert

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_LEAP     = { -3, 0, false, { 0.6, 0,   0.9, 0.4 }, { 0.6, 0,   0.9, 0.8 } }
local COL_LEAP_RED = { -3, 0, false, { 1,   0.1, 0.1, 0.4 }, { 1,   0.1, 0.1, 0.8 } }
local COL_SLAM     = { -3, 0, false, { 1,   0.7, 0,   0.4 }, { 1,   0.7, 0,   0.8 } }
local COL_SURGE    = { -3, 0, false, { 0.9, 0.9, 0.1, 0.4 }, { 0.9, 0.9, 0.1, 0.8 } }

local KazpianEncounter = {
    id                = 2,
    key               = "kazpian",
    nameAliases       = { "Overfiend Kazpian" },
    hmHealthThreshold = 0,
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
KazpianEncounter.bombDebounce = Timer.new(5.0)   -- dedup Agonizer Bombs spam

-- ── State ─────────────────────────────────────────────────────────────────
KazpianEncounter.portalPhase     = 0
KazpianEncounter.channelersDead  = 0
KazpianEncounter.chainedA        = nil   -- first chained player name
KazpianEncounter.chainedB        = nil   -- second chained player name

function KazpianEncounter:reset()
    self.bombDebounce:clear()
    self.portalPhase    = 0
    self.channelersDead = 0
    self.chainedA       = nil
    self.chainedB       = nil
end

function KazpianEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if result == ACTION_RESULT_BEGIN then
        if abilityId == VILE_LEAP then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "Vile Leap!", dur, COL_LEAP)
            alerts:showAction("Vile Leap!")

        elseif abilityId == SEETHING_LEAP then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "VILE LEAP (enrage)!", dur, COL_LEAP_RED)
            alerts:showAction("Seething Vile Leap!")

        elseif abilityId == AGONIZER_BOMBS then
            if self.bombDebounce:isExpired() then
                self.bombDebounce:reset(5.0)
                CA.alert(nil, "Agonizer Bombs!", 0xFF8844FF, SOUNDS.NONE, 3000)
                alerts:showAction("Agonizer Bombs!")
            end

        elseif abilityId == BITING_BLAZE_1 or abilityId == BITING_BLAZE_2 then
            local target = (unitName and unitName ~= "") and unitName or "?"
            alerts:showAction("Biting Blaze → " .. target)

        elseif abilityId == GIANT_CONES then
            CA.alert(nil, "Dodge cones!", 0xFFFF44FF, SOUNDS.NONE, 2500)

        elseif abilityId == GIANT_PULSE_1 or abilityId == GIANT_PULSE_2 then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "Giant Sword!", dur, COL_SLAM)

        elseif abilityId == SHOCK_SPEAR then
            CA.alert(nil, "Dodge spear!", 0x44CCFFFF, SOUNDS.NONE, 2500)

        elseif abilityId == STORM_SLAM then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "DODGE — Storm Slam!", dur, COL_SLAM)
            alerts:showAction("Molag Kena Storm Slam — DODGE!")

        elseif abilityId == STORM_SURGE then
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "Storm Surge!", dur, COL_SURGE)

        elseif abilityId == HEAVY_SHOCK and IsUnitPlayer(unitTag) then
            CA.alert(nil, "Heavy Shock on YOU!", 0x44CCFFFF, SOUNDS.NONE, 2500)
            alerts:showAction("Molag Kena Heavy Shock on you!")

        elseif abilityId == IMMOLATING_SPHRE and IsUnitPlayer(unitTag) then
            CA.alert(nil, "Immolating Sphere!", 0xFF6600FF, SOUNDS.NONE, 3000)
            alerts:showAction("Immolating Sphere on you!")

        elseif abilityId == VILE_TELEPORT then
            self.portalPhase = self.portalPhase + 1
            alerts:showAction("Portal phase " .. self.portalPhase .. "!")
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        if (abilityId == CHAINS_1 or abilityId == CHAINS_2) then
            local name = IsUnitPlayer(unitTag) and "YOU" or (unitName or "?")
            if not self.chainedA then
                self.chainedA = name
            elseif not self.chainedB then
                self.chainedB = name
                alerts:showAction("Chains: " .. self.chainedA .. " ↔ " .. self.chainedB)
                if self.chainedA == "YOU" or self.chainedB == "YOU" then
                    CA.alert(nil, "CHAINED — pull apart!", 0xFF4444FF, SOUNDS.NONE, 4000)
                end
                self.chainedA = nil
                self.chainedB = nil
            end

        elseif abilityId == STRICKEN and IsUnitPlayer(unitTag) then
            CA.alert(nil, "Stricken on YOU!", 0xFF4444FF, SOUNDS.NONE, 4000)
            alerts:showAction("Stricken — tank mechanic!")

        elseif abilityId == FIREBOMB_DEBUF and IsUnitPlayer(unitTag) then
            CA.alert(nil, "Firebomb on YOU!", 0xFF6600FF, SOUNDS.NONE, 3000)
            alerts:showAction("Firebomb — spread!")
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED and IsUnitPlayer(unitTag) then
        if abilityId == TORTUOUS_CHAINS then
            CA.border(true, 5000, "red")
            alerts:showAction("Tortuous Chains — run from Kazpian!")
        end

    elseif result == ACTION_RESULT_EFFECT_FADED then
        if abilityId == CHANNELER_RITUAL then
            self.channelersDead = self.channelersDead + 1
            alerts:showAction("Channeler down! (" .. self.channelersDead .. " dead)")
        end
    end
end

function KazpianEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
end

function KazpianEncounter:onUpdate(context, alerts)
    -- Line 1: portal phase
    if self.portalPhase > 0 then
        alerts:showInfo(1, "Portal: phase " .. self.portalPhase)
    else
        alerts:showInfo(1, "")
    end

    -- Line 2: channelers dead
    if self.channelersDead > 0 then
        alerts:showInfo(2, "Channelers dead: " .. self.channelersDead)
    else
        alerts:showInfo(2, "")
    end

    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return KazpianEncounter
