local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- â”€â”€ Ability IDs (from OsseinCageHelper) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Dragons (Valneer = fire/orange, Myrinax = lightning/blue)
local TITANIC_CLASH   = 232375   -- combatRoute: ACTION_RESULT_BEGIN â†’ CLASH phase caAlertCast
local TITANIC_LEAP_1  = 233477   -- combatRoute: ACTION_RESULT_BEGIN â†’ Leap alert, reset leapTimer
local TITANIC_LEAP_2  = 234704   -- combatRoute: ACTION_RESULT_BEGIN â†’ Leap alert, reset leapTimer
local TITANIC_LEAP_3  = 233452   -- combatRoute: ACTION_RESULT_BEGIN â†’ Leap alert, reset leapTimer
local TITANIC_LEAP_4  = 233489   -- combatRoute: ACTION_RESULT_BEGIN â†’ Leap alert, reset leapTimer
local TITANIC_LEAP_5  = 234722   -- combatRoute: ACTION_RESULT_BEGIN â†’ Leap alert, reset leapTimer
local TITANIC_LEAP_6  = 233466   -- combatRoute: ACTION_RESULT_BEGIN â†’ Leap alert, reset leapTimer
-- Curse casts
local SPARKING_CURSE_CAST  = 234000   -- combatRoute: ACTION_RESULT_BEGIN â†’ curse cast announcement (targeted)
local BLAZING_CURSE_CAST   = 234276   -- combatRoute: ACTION_RESULT_BEGIN â†’ curse cast announcement (targeted)
-- Curse debuffs
local SPARKING_CURSE_DEBUF = 234008   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION â†’ Swap! alert (player)
local BLAZING_CURSE_DEBUF  = 234280   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION â†’ Swap! alert (player)
-- AoE on player
local COLDFLAME_SURGE  = 234321   -- combatRoute: ACTION_RESULT_BEGIN â†’ Coldflame on YOU! (player)
local BRIMSTONE_SURGE  = 234330   -- combatRoute: ACTION_RESULT_BEGIN â†’ Brimstone on YOU! (player)
local COLDFLAME_STOMP  = 234521   -- combatRoute: ACTION_RESULT_BEGIN â†’ Coldflame Stomp caAlertCast
local BRIMSTONE_STOMP  = 234524   -- combatRoute: ACTION_RESULT_BEGIN â†’ Brimstone Stomp caAlertCast
-- Dragon breath
local MYRINAX_BREATH   = 234548   -- combatRoute: ACTION_RESULT_BEGIN â†’ BREATH MOVE! alert (player)
local VALNEER_BREATH   = 234558   -- combatRoute: ACTION_RESULT_BEGIN â†’ BREATH MOVE! alert (player)
-- Tail Slam
local TAIL_SLAM_1      = 235800   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ Tail Slam caAlertCast
local TAIL_SLAM_2      = 235803   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ Tail Slam caAlertCast
-- Reflective Scales â€” on player when standing on wrong side
local REFLECTIVE_1     = 233321   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ red border (player)
local REFLECTIVE_2     = 233330   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ red border (player)

local LEAP_IDS = {
    [TITANIC_LEAP_1]=true, [TITANIC_LEAP_2]=true, [TITANIC_LEAP_3]=true,
    [TITANIC_LEAP_4]=true, [TITANIC_LEAP_5]=true, [TITANIC_LEAP_6]=true,
}

-- â”€â”€ Timer durations (seconds) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local LEAP_FIRST_CD = 5.0
local LEAP_CD       = 48.0

-- â”€â”€ CA colour palettes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local COL_FIRE      = { -3, 0, false, { 1, 0.4, 0,   0.4 }, { 1, 0.4, 0,   0.8 } }
local COL_ICE       = { -3, 0, false, { 0.3, 0.8, 1, 0.4 }, { 0.3, 0.8, 1, 0.8 } }
local COL_CLASH     = { -3, 0, false, { 1, 0.1, 0.1, 0.4 }, { 1, 0.1, 0.1, 0.8 } }

-- â”€â”€ Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) â”€
local FALLBACK_DUR = 2000   -- Tail Slam: empirical

local JynorahEncounter = {}
JynorahEncounter.__index = JynorahEncounter

JynorahEncounter.key               = "jynorah"
JynorahEncounter.nameAliases       = { "Jynorah", "Skorkhif" }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
JynorahEncounter.hmHealthThreshold = math.huge
-- location: placeholder â€” Oathsworn Pit arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

JynorahEncounter.stateSchema = {
    leapTimer    = function() return Timer.new(LEAP_CD) end,
    clashTimer   = function() return Timer.new(37.5) end,
    firstLeap    = true,
    clashActive  = false,
}

function JynorahEncounter.new()
    return BossBase.fromSchema(JynorahEncounter)
end

-- â”€â”€ Handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Titanic Leap: shared handler for all 6 leap variant IDs.
local function handleLeap(self, context, alerts, abilityId, ...)
    self.firstLeap = false
    self.leapTimer:reset(LEAP_CD)
    alerts:showAction("Titanic Leap!")
end

-- Reflective Scales: red border for player on wrong side.
local function handleReflective(self, context, alerts, abilityId,
                                  unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(true, 5000, "red")
    alerts:showAction("Wrong side! Reflective Scales!")
end

-- Tail Slam: shared handler for both variants.
local function handleTailSlam(self, context, alerts, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.alertCast(abilityId, "Tail Slam â†’ " .. target, dur, COL_CLASH)
end

local function handleTitanicClash(self, context, alerts, abilityId, ...)
    self.clashActive = true
    self.clashTimer:reset(37.5)
    CA.alertCast(abilityId, "TITANIC CLASH! DODGE!", 3500, COL_CLASH)
    alerts:showAction("Titanic Clash â€” dodge the breath!")
end

local function handleSparkingCurseCast(self, context, alerts, abilityId,
                                        unitTag, sourceUnitTag, sourceUnitId, unitId,
                                        sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Sparking Curse â†’ " .. target)
end

local function handleBlazingCurseCast(self, context, alerts, abilityId,
                                       unitTag, sourceUnitTag, sourceUnitId, unitId,
                                       sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Blazing Curse â†’ " .. target)
end

local function handleSparkingCurseDebuf(self, context, alerts, abilityId,
                                         unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Sparking Curse! Swap to fire!", 0x44CCFFFF, SOUNDS.NONE, 4000)
    alerts:showAction("Sparking Curse â€” swap to Valneer side!")
end

local function handleBlazingCurseDebuf(self, context, alerts, abilityId,
                                        unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Blazing Curse! Swap to ice!", 0xFF8844FF, SOUNDS.NONE, 4000)
    alerts:showAction("Blazing Curse â€” swap to Myrinax side!")
end

local function handleColdflameSurge(self, context, alerts, abilityId,
                                     unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Coldflame on YOU!", 0x44CCFFFF, SOUNDS.NONE, 3000)
    alerts:showAction("Coldflame Surge on you! MOVE!")
end

local function handleBrimstoneSurge(self, context, alerts, abilityId,
                                     unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "Brimstone on YOU!", 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction("Brimstone Surge on you! MOVE!")
end

local function handleColdflameStomp(self, context, alerts, abilityId, ...)
    CA.alertCast(abilityId, "Coldflame Stomp!", 2000, COL_ICE)
end

local function handleBrimstoneStomp(self, context, alerts, abilityId, ...)
    CA.alertCast(abilityId, "Brimstone Stomp!", 2000, COL_FIRE)
end

local function handleMyrinaxBreath(self, context, alerts, abilityId,
                                    unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "BREATH â€” MOVE!", 0x44CCFFFF, SOUNDS.NONE, 2500)
    alerts:showAction("Myrinax Breath on you! MOVE!")
end

local function handleValneerBreath(self, context, alerts, abilityId,
                                    unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, "BREATH â€” MOVE!", 0xFF8844FF, SOUNDS.NONE, 2500)
    alerts:showAction("Valneer Breath on you! MOVE!")
end

-- â”€â”€ Routing tables (C3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

JynorahEncounter.combatRoutes = {
    [TITANIC_CLASH]       = { result = ACTION_RESULT_BEGIN,                  fn = handleTitanicClash },
    -- Titanic Leap (6 variants)
    [TITANIC_LEAP_1]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_2]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_3]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_4]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_5]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    [TITANIC_LEAP_6]      = { result = ACTION_RESULT_BEGIN,                  fn = handleLeap },
    -- Curse casts
    [SPARKING_CURSE_CAST]  = { result = ACTION_RESULT_BEGIN,                 fn = handleSparkingCurseCast },
    [BLAZING_CURSE_CAST]   = { result = ACTION_RESULT_BEGIN,                 fn = handleBlazingCurseCast },
    -- Curse debuffs on player (swap sides)
    [SPARKING_CURSE_DEBUF] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleSparkingCurseDebuf },
    [BLAZING_CURSE_DEBUF]  = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handleBlazingCurseDebuf },
    -- AoE surges (player targeted)
    [COLDFLAME_SURGE]      = { result = ACTION_RESULT_BEGIN,                 fn = handleColdflameSurge },
    [BRIMSTONE_SURGE]      = { result = ACTION_RESULT_BEGIN,                 fn = handleBrimstoneSurge },
    [COLDFLAME_STOMP]      = { result = ACTION_RESULT_BEGIN,                 fn = handleColdflameStomp },
    [BRIMSTONE_STOMP]      = { result = ACTION_RESULT_BEGIN,                 fn = handleBrimstoneStomp },
    -- Dragon breaths (player targeted)
    [MYRINAX_BREATH]       = { result = ACTION_RESULT_BEGIN,                 fn = handleMyrinaxBreath },
    [VALNEER_BREATH]       = { result = ACTION_RESULT_BEGIN,                 fn = handleValneerBreath },
    -- Reflective Scales (wrong side)
    [REFLECTIVE_1]         = { result = ACTION_RESULT_EFFECT_GAINED,         fn = handleReflective },
    [REFLECTIVE_2]         = { result = ACTION_RESULT_EFFECT_GAINED,         fn = handleReflective },
    -- Tail Slam (caAlertCast)
    [TAIL_SLAM_1]          = { result = ACTION_RESULT_EFFECT_GAINED,         fn = handleTailSlam },
    [TAIL_SLAM_2]          = { result = ACTION_RESULT_EFFECT_GAINED,         fn = handleTailSlam },
}

-- â”€â”€ Info-line renderers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Line 1: Titanic Clash active phase countdown; auto-clears when expired.
local function showClashLine(self, alerts)
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
end

-- Line 2: Titanic Leap cooldown; shows "first ~5s" before the first leap is seen.
local function showLeapLine(self, alerts)
    if self.firstLeap then
        alerts:showInfo(2, "Leap: first ~5s")
    else
        local r = self.leapTimer:remaining()
        alerts:showInfo(2, "Leap: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "NOW"))
    end
end

function JynorahEncounter:onUpdate(context, alerts)
    showClashLine(self, alerts)
    showLeapLine(self, alerts)
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

package.loaded["trial.oc.boss.JynorahEncounter"] = JynorahEncounter
return JynorahEncounter
