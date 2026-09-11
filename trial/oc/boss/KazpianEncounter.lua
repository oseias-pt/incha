local Timer    = require("lib.Timer")

local AlertTypes       = require("core.AlertTypes")
local EventDispatcher  = require("core.EventDispatcher")
local CA               = require("external-api.CombatAlerts")
local BossBase         = require("lib.BossBase")
local CastDur          = require("lib.CastDur")
local OsseinCageCommon = require("trial.oc.OsseinCageCommon")
local Lang             = require("core.Lang")
local Colors           = require("core.Colors")

-- ── Ability IDs ──────────────────────────────────────────────────────────────────────────────────
-- Chains (combatEvent.other: EFFECT_GAINED_DURATION)
local CHAINS_1        = 232773
local CHAINS_2        = 232775
local TORTUOUS_CHAINS = 236338   -- combatEvent.other: EFFECT_GAINED
-- Vile Leap
local VILE_LEAP       = 235557
local SEETHING_LEAP   = 245208
-- Agonizer Bombs
local AGONIZER_BOMBS  = 237149
-- Biting Blaze
local BITING_BLAZE_1  = 235354
local BITING_BLAZE_2  = 246009
-- Giant Sword / cones
local GIANT_PULSE_1   = 235495
local GIANT_PULSE_2   = 244937
local GIANT_CONES     = 232574
local SHOCK_SPEAR     = 235514
-- Molag Kena adds
local STORM_SLAM      = 235201
local STORM_SURGE     = 235205
local HEAVY_SHOCK     = 235206
-- Portal / teleport
local VILE_TELEPORT   = 232969
-- Channelers (combatEvent.other: EFFECT_FADED)
local CHANNELER_RITUAL = 234349
-- Debuffs on player (combatEvent.other: EFFECT_GAINED_DURATION)
local STRICKEN        = 235594
local FIREBOMB_DEBUF  = 245264
local IMMOLATING_SPHERE= 237011

-- ── Fallback durations ────────────────────────────────────────────────────────────────────────────
local FALLBACK_DUR = 2000

local KazpianEncounter = {}
KazpianEncounter.__index = KazpianEncounter

KazpianEncounter.key               = "kazpian"
KazpianEncounter.nameAliases       = { "Overfiend Kazpian" }
KazpianEncounter.hmHealthThreshold = math.huge

KazpianEncounter.stateSchema = {
    bombDebounce   = function() return Timer.new(5.0) end,
    portalPhase    = 0,
    channelersDead = 0,
    chainedA       = false,
    chainedB       = false,
}

function KazpianEncounter.new()
    return BossBase.fromSchema(KazpianEncounter)
end

-- ── Handlers ─────────────────────────────────────────────────────────────────────────────────────

local function handleChains(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local name = IsUnitPlayer(unitTag) and Lang.t("common_you") or (unitName or "?")
    if not boss.chainedA then
        boss.chainedA = name
    elseif not boss.chainedB then
        boss.chainedB = name
        alerts:showAction(Lang.t("oc_kazpian_chains", boss.chainedA, boss.chainedB))
        if boss.chainedA == Lang.t("common_you") or boss.chainedB == Lang.t("common_you") then
            CA.alert(nil, Lang.t("oc_kazpian_chained_alert"), 0xFF4444FF, SOUNDS.NONE, 4000)
        end
        boss.chainedA = nil
        boss.chainedB = nil
    end
end

local function handleBitingBlaze(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("oc_kazpian_biting_blaze", target))
end

local function handleGiantPulse(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_kazpian_giant_sword_bar"), dur, Colors.FLYZONE)
end

local function handleVileLeap(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_kazpian_vile_leap"), dur, Colors.VOID)
    alerts:showAction(Lang.t("oc_kazpian_vile_leap"))
end

local function handleSeethingLeap(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_kazpian_seething_bar"), dur, Colors.RED)
    alerts:showAction(Lang.t("oc_kazpian_seething_leap"))
end

local function handleAgonizerBombs(boss, ctx, alerts, abilityId, ...)
    if boss.bombDebounce:isExpired() then
        boss.bombDebounce:reset(5.0)
        CA.alert(nil, Lang.t("oc_kazpian_agonizer"), 0xFF8844FF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("oc_kazpian_agonizer"))
    end
end

local function handleGiantCones(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("oc_kazpian_dodge_cones"), 0xFFFF44FF, SOUNDS.NONE, 2500)
end

local function handleShockSpear(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("oc_kazpian_dodge_spear"), 0x44CCFFFF, SOUNDS.NONE, 2500)
end

local function handleStormSlam(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_kazpian_storm_slam_bar"), dur, Colors.FLYZONE)
    alerts:showAction(Lang.t("oc_kazpian_storm_slam"))
end

local function handleStormSurge(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_kazpian_storm_surge_bar"), dur, Colors.LIGHTNING)
end

local function handleHeavyShock(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_kazpian_heavy_shock_alert"), 0x44CCFFFF, SOUNDS.NONE, 2500)
    alerts:showAction(Lang.t("oc_kazpian_heavy_shock"))
end

local function handleImmolating(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_kazpian_immolating_alert"), 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_kazpian_immolating"))
end

local function handleVileTeleport(boss, ctx, alerts, abilityId, ...)
    boss.portalPhase = boss.portalPhase + 1
    alerts:showAction(Lang.t("oc_kazpian_portal_phase", boss.portalPhase))
end

local function handleStricken(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_kazpian_stricken_alert"), 0xFF4444FF, SOUNDS.NONE, 4000)
    alerts:showAction(Lang.t("oc_kazpian_stricken"))
end

local function handleFirebombDebuf(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("oc_kazpian_firebomb_alert"), 0xFF6600FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_kazpian_firebomb"))
end

local function handleTortuousChains(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(true, 5000, "red")
    alerts:showAction(Lang.t("oc_kazpian_tort_chains"))
end

local function handleChannelerRitual(boss, ctx, alerts, abilityId, ...)
    boss.channelersDead = boss.channelersDead + 1
    alerts:showAction(Lang.t("oc_kazpian_channeler_down", boss.channelersDead))
end

-- ── Event tables ─────────────────────────────────────────────────────────────────────────────────

local _beginCastEntry = {}
for k, v in pairs(OsseinCageCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[VILE_LEAP]         = { type = AlertTypes.CUSTOM, fn = handleVileLeap }
_beginCastEntry[SEETHING_LEAP]     = { type = AlertTypes.CUSTOM, fn = handleSeethingLeap }
_beginCastEntry[AGONIZER_BOMBS]    = { type = AlertTypes.CUSTOM, fn = handleAgonizerBombs }
_beginCastEntry[BITING_BLAZE_1]    = { type = AlertTypes.CUSTOM, fn = handleBitingBlaze }
_beginCastEntry[BITING_BLAZE_2]    = { type = AlertTypes.CUSTOM, fn = handleBitingBlaze }
_beginCastEntry[GIANT_CONES]       = { type = AlertTypes.CUSTOM, fn = handleGiantCones }
_beginCastEntry[GIANT_PULSE_1]     = { type = AlertTypes.CUSTOM, fn = handleGiantPulse }
_beginCastEntry[GIANT_PULSE_2]     = { type = AlertTypes.CUSTOM, fn = handleGiantPulse }
_beginCastEntry[SHOCK_SPEAR]       = { type = AlertTypes.CUSTOM, fn = handleShockSpear }
_beginCastEntry[STORM_SLAM]        = { type = AlertTypes.CUSTOM, fn = handleStormSlam }
_beginCastEntry[STORM_SURGE]       = { type = AlertTypes.CUSTOM, fn = handleStormSurge }
_beginCastEntry[HEAVY_SHOCK]       = { type = AlertTypes.CUSTOM, fn = handleHeavyShock }
_beginCastEntry[IMMOLATING_SPHERE] = { type = AlertTypes.CUSTOM, fn = handleImmolating }
_beginCastEntry[VILE_TELEPORT]     = { type = AlertTypes.CUSTOM, fn = handleVileTeleport }

local _combatOtherEntry = {
    [CHAINS_1]         = { type = AlertTypes.CUSTOM, fn = handleChains },
    [CHAINS_2]         = { type = AlertTypes.CUSTOM, fn = handleChains },
    [STRICKEN]         = { type = AlertTypes.CUSTOM, fn = handleStricken },
    [FIREBOMB_DEBUF]   = { type = AlertTypes.CUSTOM, fn = handleFirebombDebuf },
    [TORTUOUS_CHAINS]  = { type = AlertTypes.CUSTOM, fn = handleTortuousChains },
    [CHANNELER_RITUAL] = { type = AlertTypes.CUSTOM, fn = handleChannelerRitual },
}

local _effectGainedEntry = {}
for k, v in pairs(OsseinCageCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
local _effectFadedEntry = {}
for k, v in pairs(OsseinCageCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end

KazpianEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

function KazpianEncounter:onWipe(context, alerts)
    OsseinCageCommon.reset()
    self.bombDebounce:clear()
    self.portalPhase    = 0; self.channelersDead = 0
    self.chainedA       = false; self.chainedB = false
    CA.border(false, 0, "red")
end

function KazpianEncounter:onUpdate(context, alerts)
    if self.portalPhase > 0 then
        alerts:setRow(1, Lang.t("oc_kazpian_portal_label", self.portalPhase), nil)
    else
        alerts:clearRow(1)
    end

    if self.channelersDead > 0 then
        alerts:setRow(2, Lang.t("oc_kazpian_channelers", self.channelersDead), nil)
    else
        alerts:clearRow(2)
    end

    OsseinCageCommon.showCarrionInfo(alerts)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

EventDispatcher.build(KazpianEncounter)

package.loaded["trial.oc.boss.KazpianEncounter"] = KazpianEncounter
return KazpianEncounter
