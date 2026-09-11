local Timer    = require("lib.Timer")

local AlertTypes       = require("core.AlertTypes")
local EventDispatcher  = require("core.EventDispatcher")
local CA               = require("external-api.CombatAlerts")
local BossBase         = require("lib.BossBase")
local CastDur          = require("lib.CastDur")
local OsseinCageCommon = require("trial.oc.OsseinCageCommon")
local Lang             = require("core.Lang")
local Fmt              = require("core.Fmt")
local Colors           = require("core.Colors")

-- -- Ability IDs (from OsseinCageHelper) ----------------------------------------------------------
-- Dragons (Valneer = fire/orange, Myrinax = lightning/blue)
local TITANIC_CLASH   = 232375
local TITANIC_LEAP_1  = 233477
local TITANIC_LEAP_2  = 234704
local TITANIC_LEAP_3  = 233452
local TITANIC_LEAP_4  = 233489
local TITANIC_LEAP_5  = 234722
local TITANIC_LEAP_6  = 233466
-- Clash hits
local TITANIC_CLASH_HIT_V = 232460
local TITANIC_CLASH_HIT_M = 232465
-- Curse casts
local SPARKING_CURSE_CAST  = 234000
local BLAZING_CURSE_CAST   = 234276
-- Curse debuffs (combatEvent.other: EFFECT_GAINED_DURATION)
local SPARKING_CURSE_DEBUF = 234008
local BLAZING_CURSE_DEBUF  = 234280
-- AoE on player
local COLDFLAME_SURGE  = 234321
local BRIMSTONE_SURGE  = 234330
local COLDFLAME_STOMP  = 234521
local BRIMSTONE_STOMP  = 234524
-- Dragon breath
local MYRINAX_BREATH   = 234548
local VALNEER_BREATH   = 234558
-- Heat Rays
local JYN_HEAT_RAY     = 234141
local SKOR_HEAT_RAY    = 234161
-- Tail Slam (combatEvent.other: EFFECT_GAINED)
local TAIL_SLAM_1      = 235800
local TAIL_SLAM_2      = 235803
-- Reflective Scales (effectChanged.gained/faded)
local REFLECTIVE_1     = 233321
local REFLECTIVE_2     = 233330

-- -- Timer durations (seconds) ---------------------------------------------------------------------
local LEAP_CD       = 48.0

-- -- Fallback durations ----------------------------------------------------------------------------
local FALLBACK_DUR = 2000

local JynorahEncounter = {}
JynorahEncounter.__index = JynorahEncounter

JynorahEncounter.key               = "jynorah"
JynorahEncounter.nameAliases       = { "Jynorah", "Skorkhif" }
JynorahEncounter.hmHealthThreshold = math.huge

JynorahEncounter.stateSchema = {
    leapTimer    = function() return Timer.new(LEAP_CD) end,
    clashTimer   = function() return Timer.new(37.5) end,
    firstLeap    = true,
    clashActive  = false,
    playerCurse  = false,
}

function JynorahEncounter.new()
    return BossBase.fromSchema(JynorahEncounter)
end

-- -- Handlers --------------------------------------------------------------------------------------

local function handleLeap(boss, ctx, alerts, abilityId, ...)
    boss.firstLeap = false
    boss.leapTimer:reset(LEAP_CD)
    alerts:showAction(Lang.t("oc_jynorah_titanic_leap"))
end

local function handleReflectiveGained(boss, ctx, alerts, abilityId, ...)
    CA.border(true, 6000, "yellow")
    alerts:showAction(Lang.t("oc_jynorah_reflective"))
end

local function handleReflectiveFaded(boss, ctx, alerts, abilityId, ...)
    CA.border(false, 0, "yellow")
end

local function handleTailSlam(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_jynorah_tail_slam_bar", target), dur, Colors.RED)
end

local function handleTitanicClash(boss, ctx, alerts, abilityId, ...)
    boss.clashActive = true
    boss.clashTimer:reset(37.5)
    CA.ranged(abilityId, Lang.t("oc_jynorah_clash_bar"), 3500, Colors.RED)
    alerts:showAction(Lang.t("oc_jynorah_titanic_clash"))
end

local function handleTitanicClashHitV(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("oc_jynorah_valneer_hit"))
end

local function handleTitanicClashHitM(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("oc_jynorah_myrinax_hit"))
end

local function handleSparkingCurseCast(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if IsUnitPlayer(unitTag) then
        CA.alert(nil, Lang.t("oc_jynorah_curse_alert"), 0x44CCFFFF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("oc_jynorah_sparking_you"))
    else
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction(Lang.t("oc_jynorah_sparking_tgt", target))
    end
end

local function handleBlazingCurseCast(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if IsUnitPlayer(unitTag) then
        CA.alert(nil, Lang.t("oc_jynorah_curse_alert"), 0xFF8844FF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("oc_jynorah_blazing_you"))
    else
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction(Lang.t("oc_jynorah_blazing_tgt", target))
    end
end

local function handleSparkingCurseDebuf(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    boss.playerCurse = "sparking"
    CA.border(true, 30000, "blue")
    CA.alert(nil, Lang.t("oc_jynorah_sparking_blue"), 0x44CCFFFF, SOUNDS.NONE, 4000)
    alerts:showAction(Lang.t("oc_jynorah_sparking_valneer"))
end

local function handleBlazingCurseDebuf(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    boss.playerCurse = "blazing"
    CA.border(true, 30000, "red")
    CA.alert(nil, Lang.t("oc_jynorah_blazing_red"), 0xFF8844FF, SOUNDS.NONE, 4000)
    alerts:showAction(Lang.t("oc_jynorah_blazing_myrinax"))
end

local function handleColdflameSurge(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_surge_alert"), 0x44CCFFFF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_jynorah_coldflame"))
end

local function handleBrimstoneSurge(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_surge_alert"), 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_jynorah_brimstone"))
end

local function handleColdflameStomp(boss, ctx, alerts, abilityId, ...)
    CA.ranged(abilityId, Lang.t("oc_jynorah_stomp_bar"), 2000, Colors.ICE)
end

local function handleBrimstoneStomp(boss, ctx, alerts, abilityId, ...)
    CA.ranged(abilityId, Lang.t("oc_jynorah_stomp_bar"), 2000, Colors.ORANGE)
end

local function handleHeatRay(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_heat_ray_alert"), 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_jynorah_heat_ray"))
end

local function handleMyrinaxBreath(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_breath_alert"), 0x44CCFFFF, SOUNDS.NONE, 2500)
    alerts:showAction(Lang.t("oc_jynorah_myrinax_breath"))
end

local function handleValneerBreath(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_jynorah_breath_alert"), 0xFF8844FF, SOUNDS.NONE, 2500)
    alerts:showAction(Lang.t("oc_jynorah_valneer_breath"))
end

-- -- Event tables ---------------------------------------------------------------------------------

local _beginCastEntry = {}
for k, v in pairs(OsseinCageCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[TITANIC_CLASH]       = { type = AlertTypes.CUSTOM, fn = handleTitanicClash }
_beginCastEntry[TITANIC_CLASH_HIT_V] = { type = AlertTypes.CUSTOM, fn = handleTitanicClashHitV }
_beginCastEntry[TITANIC_CLASH_HIT_M] = { type = AlertTypes.CUSTOM, fn = handleTitanicClashHitM }
_beginCastEntry[TITANIC_LEAP_1]      = { type = AlertTypes.CUSTOM, fn = handleLeap }
_beginCastEntry[TITANIC_LEAP_2]      = { type = AlertTypes.CUSTOM, fn = handleLeap }
_beginCastEntry[TITANIC_LEAP_3]      = { type = AlertTypes.CUSTOM, fn = handleLeap }
_beginCastEntry[TITANIC_LEAP_4]      = { type = AlertTypes.CUSTOM, fn = handleLeap }
_beginCastEntry[TITANIC_LEAP_5]      = { type = AlertTypes.CUSTOM, fn = handleLeap }
_beginCastEntry[TITANIC_LEAP_6]      = { type = AlertTypes.CUSTOM, fn = handleLeap }
_beginCastEntry[SPARKING_CURSE_CAST]  = { type = AlertTypes.CUSTOM, fn = handleSparkingCurseCast }
_beginCastEntry[BLAZING_CURSE_CAST]   = { type = AlertTypes.CUSTOM, fn = handleBlazingCurseCast }
_beginCastEntry[COLDFLAME_SURGE]      = { type = AlertTypes.CUSTOM, fn = handleColdflameSurge }
_beginCastEntry[BRIMSTONE_SURGE]      = { type = AlertTypes.CUSTOM, fn = handleBrimstoneSurge }
_beginCastEntry[COLDFLAME_STOMP]      = { type = AlertTypes.CUSTOM, fn = handleColdflameStomp }
_beginCastEntry[BRIMSTONE_STOMP]      = { type = AlertTypes.CUSTOM, fn = handleBrimstoneStomp }
_beginCastEntry[JYN_HEAT_RAY]         = { type = AlertTypes.CUSTOM, fn = handleHeatRay }
_beginCastEntry[SKOR_HEAT_RAY]        = { type = AlertTypes.CUSTOM, fn = handleHeatRay }
_beginCastEntry[MYRINAX_BREATH]       = { type = AlertTypes.CUSTOM, fn = handleMyrinaxBreath }
_beginCastEntry[VALNEER_BREATH]       = { type = AlertTypes.CUSTOM, fn = handleValneerBreath }

local _combatOtherEntry = {
    [SPARKING_CURSE_DEBUF] = { type = AlertTypes.CUSTOM, fn = handleSparkingCurseDebuf },
    [BLAZING_CURSE_DEBUF]  = { type = AlertTypes.CUSTOM, fn = handleBlazingCurseDebuf },
    [TAIL_SLAM_1]          = { type = AlertTypes.CUSTOM, fn = handleTailSlam },
    [TAIL_SLAM_2]          = { type = AlertTypes.CUSTOM, fn = handleTailSlam },
}

local _effectGainedEntry = {}
for k, v in pairs(OsseinCageCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
_effectGainedEntry[REFLECTIVE_1] = { type = AlertTypes.CUSTOM, fn = handleReflectiveGained }
_effectGainedEntry[REFLECTIVE_2] = { type = AlertTypes.CUSTOM, fn = handleReflectiveGained }

local _effectFadedEntry = {}
for k, v in pairs(OsseinCageCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end
_effectFadedEntry[REFLECTIVE_1] = { type = AlertTypes.CUSTOM, fn = handleReflectiveFaded }
_effectFadedEntry[REFLECTIVE_2] = { type = AlertTypes.CUSTOM, fn = handleReflectiveFaded }

JynorahEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Info-line renderers ----------------------------------------------------------------------------

local function showClashLine(boss, alerts)
    if boss.clashActive then
        local r = boss.clashTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Fmt.c("FF4444", Lang.t("oc_jynorah_clash_timer")), r)
        else
            boss.clashActive = false
            alerts:clearRow(1)
        end
    else
        alerts:clearRow(1)
    end
end

local function showLeapLine(boss, alerts)
    if boss.firstLeap then
        alerts:setRow(2, Lang.t("oc_jynorah_leap_first"), nil)
    else
        local r = boss.leapTimer:remaining()
        if r > 0 then
            alerts:setRow(2, Lang.t("oc_jynorah_leap_label"), r)
        else
            alerts:setRow(2, Lang.t("oc_jynorah_leap_label") .. " " .. Lang.t("common_now"), nil)
        end
    end
end

function JynorahEncounter:onWipe(context, alerts)
    OsseinCageCommon.reset()
    self.leapTimer:clear(); self.clashTimer:clear()
    self.firstLeap  = true; self.clashActive = false
    self.playerCurse = false
    CA.border(false, 0, "blue")
    CA.border(false, 0, "red")
    CA.border(false, 0, "yellow")
end

function JynorahEncounter:onUpdate(context, alerts)
    showClashLine(self, alerts)
    showLeapLine(self, alerts)
    OsseinCageCommon.showCarrionInfo(alerts)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

EventDispatcher.build(JynorahEncounter)

package.loaded["trial.oc.boss.JynorahEncounter"] = JynorahEncounter
return JynorahEncounter
