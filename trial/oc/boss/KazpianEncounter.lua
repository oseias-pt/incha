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

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 2000   -- GiantPulse / VileLeap / SeethingLeap / StormSlam / StormSurge: empirical

local KazpianEncounter = {}
KazpianEncounter.__index = KazpianEncounter

KazpianEncounter.key               = "kazpian"
KazpianEncounter.nameAliases       = { "Overfiend Kazpian" }
KazpianEncounter.hmHealthThreshold = 0
KazpianEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

function KazpianEncounter.new()
    return setmetatable({
        bombDebounce    = Timer.new(5.0),   -- dedup Agonizer Bombs spam
        portalPhase     = 0,
        channelersDead  = 0,
        chainedA        = nil,  -- first chained player name
        chainedB        = nil,  -- second chained player name
    }, KazpianEncounter)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Chains: pairs two chained players and alerts when the pair is formed.
local function handleChains(self, context, alerts, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
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
end

-- Biting Blaze: shared handler for both variants.
local function handleBitingBlaze(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Biting Blaze → " .. target)
end

-- Giant Pulse: shared handler for both variants.
local function handleGiantPulse(self, context, alerts, abilityId, ...)
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    if dur <= 0 then dur = FALLBACK_DUR end
    CA.alertCast(abilityId, "Giant Sword!", dur, COL_SLAM)
end

KazpianEncounter.combatRoutes = {
    -- Leaps
    [VILE_LEAP] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALLBACK_DUR end
        CA.alertCast(abilityId, "Vile Leap!", dur, COL_LEAP)
        alerts:showAction("Vile Leap!")
    end },
    [SEETHING_LEAP] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALLBACK_DUR end
        CA.alertCast(abilityId, "VILE LEAP (enrage)!", dur, COL_LEAP_RED)
        alerts:showAction("Seething Vile Leap!")
    end },
    -- Agonizer Bombs (debounced)
    [AGONIZER_BOMBS] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        if self.bombDebounce:isExpired() then
            self.bombDebounce:reset(5.0)
            CA.alert(nil, "Agonizer Bombs!", 0xFF8844FF, SOUNDS.NONE, 3000)
            alerts:showAction("Agonizer Bombs!")
        end
    end },
    [BITING_BLAZE_1] = { result = ACTION_RESULT_BEGIN, fn = handleBitingBlaze },
    [BITING_BLAZE_2] = { result = ACTION_RESULT_BEGIN, fn = handleBitingBlaze },
    [GIANT_CONES] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        CA.alert(nil, "Dodge cones!", 0xFFFF44FF, SOUNDS.NONE, 2500)
    end },
    [GIANT_PULSE_1] = { result = ACTION_RESULT_BEGIN, fn = handleGiantPulse },
    [GIANT_PULSE_2] = { result = ACTION_RESULT_BEGIN, fn = handleGiantPulse },
    [SHOCK_SPEAR] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        CA.alert(nil, "Dodge spear!", 0x44CCFFFF, SOUNDS.NONE, 2500)
    end },
    [STORM_SLAM] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALLBACK_DUR end
        CA.alertCast(abilityId, "DODGE — Storm Slam!", dur, COL_SLAM)
        alerts:showAction("Molag Kena Storm Slam — DODGE!")
    end },
    [STORM_SURGE] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALLBACK_DUR end
        CA.alertCast(abilityId, "Storm Surge!", dur, COL_SURGE)
    end },
    [HEAVY_SHOCK] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId,
                      unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.alert(nil, "Heavy Shock on YOU!", 0x44CCFFFF, SOUNDS.NONE, 2500)
        alerts:showAction("Molag Kena Heavy Shock on you!")
    end },
    [IMMOLATING_SPHRE] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId,
                      unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.alert(nil, "Immolating Sphere!", 0xFF6600FF, SOUNDS.NONE, 3000)
        alerts:showAction("Immolating Sphere on you!")
    end },
    [VILE_TELEPORT] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        self.portalPhase = self.portalPhase + 1
        alerts:showAction("Portal phase " .. self.portalPhase .. "!")
    end },
    -- Chains (EFFECT_GAINED_DURATION)
    [CHAINS_1] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleChains },
    [CHAINS_2] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleChains },
    [STRICKEN] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,
        fn = function(self, context, alerts, abilityId,
                      unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.alert(nil, "Stricken on YOU!", 0xFF4444FF, SOUNDS.NONE, 4000)
        alerts:showAction("Stricken — tank mechanic!")
    end },
    [FIREBOMB_DEBUF] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,
        fn = function(self, context, alerts, abilityId,
                      unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.alert(nil, "Firebomb on YOU!", 0xFF6600FF, SOUNDS.NONE, 3000)
        alerts:showAction("Firebomb — spread!")
    end },
    -- Tortuous Chains (EFFECT_GAINED)
    [TORTUOUS_CHAINS] = { result = ACTION_RESULT_EFFECT_GAINED,
        fn = function(self, context, alerts, abilityId,
                      unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        CA.border(true, 5000, "red")
        alerts:showAction("Tortuous Chains — run from Kazpian!")
    end },
    -- Channeler ritual (EFFECT_FADED = channeler killed)
    [CHANNELER_RITUAL] = { result = ACTION_RESULT_EFFECT_FADED, fn = function(self, context, alerts, abilityId, ...)
        self.channelersDead = self.channelersDead + 1
        alerts:showAction("Channeler down! (" .. self.channelersDead .. " dead)")
    end },
}

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
