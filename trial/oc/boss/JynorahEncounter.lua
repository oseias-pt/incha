local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs (from OsseinCageHelper) ──────────────────────────────────
-- Dragons (Valneer = fire/orange, Myrinax = lightning/blue)
local TITANIC_CLASH   = 232375   -- both dragons rear — BEGIN → major phase alert
local TITANIC_LEAP_1  = 233477   -- dragon leap variants (all share same timer)
local TITANIC_LEAP_2  = 234704
local TITANIC_LEAP_3  = 233452
local TITANIC_LEAP_4  = 233489
local TITANIC_LEAP_5  = 234722
local TITANIC_LEAP_6  = 233466
-- Curse casts
local SPARKING_CURSE_CAST  = 234000   -- BEGIN → which player targeted
local BLAZING_CURSE_CAST   = 234276   -- BEGIN → which player targeted
-- Curse debuffs
local SPARKING_CURSE_DEBUF = 234008   -- EFFECT_GAINED_DURATION on player → "Swap!"
local BLAZING_CURSE_DEBUF  = 234280   -- EFFECT_GAINED_DURATION on player → "Swap!"
-- AoE on player
local COLDFLAME_SURGE  = 234321   -- BEGIN on player → move!
local BRIMSTONE_SURGE  = 234330   -- BEGIN on player → move!
local COLDFLAME_STOMP  = 234521   -- BEGIN → alert (AoE marker)
local BRIMSTONE_STOMP  = 234524   -- BEGIN → alert
-- Dragon breath
local MYRINAX_BREATH   = 234548   -- Goaded Breath — BEGIN on player → MOVE
local VALNEER_BREATH   = 234558   -- Goaded Breath — BEGIN on player → MOVE
-- Tail Slam
local TAIL_SLAM_1      = 235800   -- EFFECT_GAINED → caAlertCast
local TAIL_SLAM_2      = 235803
-- Reflective Scales — on player when standing on wrong side
local REFLECTIVE_1     = 233321   -- EFFECT_GAINED → red border
local REFLECTIVE_2     = 233330

local LEAP_IDS = {
    [TITANIC_LEAP_1]=true, [TITANIC_LEAP_2]=true, [TITANIC_LEAP_3]=true,
    [TITANIC_LEAP_4]=true, [TITANIC_LEAP_5]=true, [TITANIC_LEAP_6]=true,
}

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local LEAP_FIRST_CD = 5.0
local LEAP_CD       = 48.0

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_FIRE      = { -3, 0, false, { 1, 0.4, 0,   0.4 }, { 1, 0.4, 0,   0.8 } }
local COL_ICE       = { -3, 0, false, { 0.3, 0.8, 1, 0.4 }, { 0.3, 0.8, 1, 0.8 } }
local COL_CLASH     = { -3, 0, false, { 1, 0.1, 0.1, 0.4 }, { 1, 0.1, 0.1, 0.8 } }

local JynorahEncounter = {}
JynorahEncounter.__index = JynorahEncounter

JynorahEncounter.key               = "jynorah"
JynorahEncounter.nameAliases       = { "Jynorah", "Skorkhif" }
JynorahEncounter.hmHealthThreshold = 0
JynorahEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

function JynorahEncounter.new()
    return setmetatable({
        leapTimer    = Timer.new(LEAP_CD),
        clashTimer   = Timer.new(37.5),   -- Titanic Clash active phase duration
        firstLeap    = true,
        clashActive  = false,
    }, JynorahEncounter)
end

function JynorahEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if result == ACTION_RESULT_BEGIN then
        if abilityId == TITANIC_CLASH then
            self.clashActive = true
            self.clashTimer:reset(37.5)
            CA.alertCast(abilityId, "TITANIC CLASH! DODGE!", 3500, COL_CLASH)
            alerts:showAction("Titanic Clash — dodge the breath!")

        elseif LEAP_IDS[abilityId] then
            self.firstLeap = false
            self.leapTimer:reset(LEAP_CD)
            alerts:showAction("Titanic Leap!")

        elseif abilityId == SPARKING_CURSE_CAST or abilityId == BLAZING_CURSE_CAST then
            local target = (unitName and unitName ~= "") and unitName or "?"
            local label = (abilityId == SPARKING_CURSE_CAST) and "Sparking" or "Blazing"
            alerts:showAction(label .. " Curse → " .. target)

        elseif abilityId == COLDFLAME_SURGE and IsUnitPlayer(unitTag) then
            CA.alert(nil, "Coldflame on YOU!", 0x44CCFFFF, SOUNDS.NONE, 3000)
            alerts:showAction("Coldflame Surge on you! MOVE!")

        elseif abilityId == BRIMSTONE_SURGE and IsUnitPlayer(unitTag) then
            CA.alert(nil, "Brimstone on YOU!", 0xFF6600FF, SOUNDS.NONE, 3000)
            alerts:showAction("Brimstone Surge on you! MOVE!")

        elseif abilityId == COLDFLAME_STOMP then
            CA.alertCast(abilityId, "Coldflame Stomp!", 2000, COL_ICE)

        elseif abilityId == BRIMSTONE_STOMP then
            CA.alertCast(abilityId, "Brimstone Stomp!", 2000, COL_FIRE)

        elseif abilityId == MYRINAX_BREATH and IsUnitPlayer(unitTag) then
            CA.alert(nil, "BREATH — MOVE!", 0x44CCFFFF, SOUNDS.NONE, 2500)
            alerts:showAction("Myrinax Breath on you! MOVE!")

        elseif abilityId == VALNEER_BREATH and IsUnitPlayer(unitTag) then
            CA.alert(nil, "BREATH — MOVE!", 0xFF8844FF, SOUNDS.NONE, 2500)
            alerts:showAction("Valneer Breath on you! MOVE!")
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED_DURATION and IsUnitPlayer(unitTag) then
        if abilityId == SPARKING_CURSE_DEBUF then
            CA.alert(nil, "Sparking Curse! Swap to fire!", 0x44CCFFFF, SOUNDS.NONE, 4000)
            alerts:showAction("Sparking Curse — swap to Valneer side!")
        elseif abilityId == BLAZING_CURSE_DEBUF then
            CA.alert(nil, "Blazing Curse! Swap to ice!", 0xFF8844FF, SOUNDS.NONE, 4000)
            alerts:showAction("Blazing Curse — swap to Myrinax side!")
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED then
        if (abilityId == REFLECTIVE_1 or abilityId == REFLECTIVE_2) and IsUnitPlayer(unitTag) then
            CA.border(true, 5000, "red")
            alerts:showAction("Wrong side! Reflective Scales!")
        elseif abilityId == TAIL_SLAM_1 or abilityId == TAIL_SLAM_2 then
            local target = (unitName and unitName ~= "") and unitName or "?"
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "Tail Slam → " .. target, dur, COL_CLASH)
        end
    end
end

function JynorahEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
end

function JynorahEncounter:onUpdate(context, alerts)
    -- Line 1: Titanic Clash phase
    if self.clashActive then
        local r = self.clashTimer:remaining()
        if r > 0 then
            alerts:showInfo(1, "|cFF4444CLASH: " .. ZO_FormatCountdownTimer(r) .. "|r")
        else
            self.clashActive = false
            alerts:showInfo(1, "")
        end
    else
        alerts:showInfo(1, "")
    end

    -- Line 2: Titanic Leap CD
    if self.firstLeap then
        alerts:showInfo(2, "Leap: first ~5s")
    else
        local r = self.leapTimer:remaining()
        alerts:showInfo(2, "Leap: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "NOW"))
    end

    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return JynorahEncounter
