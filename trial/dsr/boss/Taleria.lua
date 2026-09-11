--- Taleria (Tideborn Taleria)  -  Dreadsail Reef boss 3

local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local DreadsailCommon = require("trial.dsr.DreadsailCommon")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local Colors          = require("core.Colors")

-- -- Ability IDs -----------------------------------------------------------
local RAPID_DELUGE_N   = 174959
local RAPID_DELUGE_V   = 174960
local RAPID_DELUGE_HM  = 174961
local CRASHING_WAVE_1  = 166353
local CRASHING_WAVE_2  = 174943
local CORAL_SLAM       = 163987
local BARNACLE_BLADE   = 163901
local BARNACLE_BLADE_2 = 174801
local MAELSTROM_CAST   = 166292
local BEHEMOTH_SUMMON  = 166928
local ARCTIC_ANNIH     = 165827
local STORM_WALL_CW    = 175447
local STORM_WALL_CCW   = 174866
local LURE_OF_SEA      = 163952
local ASPECT_TERROR    = 174697
local VENOM_EVOKER_P   = 175132
local SEA_BOILER_P     = 175134
local TIDAL_MAGE_P     = 175136
local BRIDGE_1         = 166479
local BRIDGE_2         = 175279
local BRIDGE_3         = 175291
local WHIRLPOOL        = 163896

-- -- Timing constants --------------------------------------------------------
local MAELSTROM_CD     = 35
local MAELSTROM_DUR    = 6
local BEHEMOTH_CD_NORM = 60
local BEHEMOTH_CD_HM   = 45
local SLAM_CD          = 17
local STORM_WALL_DUR   = 45
local BRIDGE_WIPE      = 60
local MAELSTROM_DODGE  = 1.5
local BRIDGE_HP        = { 50.9, 35.9, 20.9 }

local ACT_BREAK         = { 4000, "Break free!", 0.9, 0.1, 0.1, 0.9, nil }
local FALLBACK_WAVE_DUR  = 2000
local FALLBACK_SLAM_DUR  = 1500
local FALLBACK_BLADE_DUR = 1000
local FALLBACK_FEAR_DUR  = 2000

-- Portal colors (shared between handlers built at module load)
local PORTAL_COLORS = { 0x22CC22D9, 0xDDCC00D9, 0x8822DDD9 }

local Taleria = {}
Taleria.__index = Taleria

Taleria.key               = "taleria"
Taleria.name              = "Tideborn Taleria"
Taleria.hmHealthThreshold = 100000001

Taleria.stateSchema = {
    lastMaelstrom     = 0,
    lastBehemothSumm  = 0,
    behemothSlam      = 0,
    lastStormWall     = 0,
    stormWallCW       = true,
    lastPlatformFall  = 0,
    bridgeOpen      = function() return { false, false, false } end,
    bridgeWipeStart = function() return { 0, 0, 0 } end,
    bridgeDone      = function() return { false, false, false } end,
    lureBarId       = false,
}

function Taleria.new()
    return BossBase.fromSchema(Taleria)
end

function Taleria:onLeave(context)
    CA.castAlertsStop(self.lureBarId)
end

-- -- Handlers: beginCast ----------------------------------------------------

local function handleCrashingWave(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_WAVE_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleCoralSlam(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_SLAM_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleBarnacleBlade(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_BLADE_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleMaelstromCast(boss, ctx, alerts, abilityId, ...)
    boss.lastMaelstrom = GetGameTimeMilliseconds() / 1000
    CA.alert(nil, Fmt.c(Fmt.POISON, Lang.t("dsr_taleria_maelstrom_alert")),
        0x66CC66D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 6000)
end

local function handleBehemothSummon(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    boss.lastBehemothSumm = now
    boss.behemothSlam     = now + 10
    CA.alert(nil, "Sea Behemoth summoned!",
        0xFF8800D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
end

local function handleArcticAnnih(boss, ctx, alerts, abilityId, ...)
    boss.behemothSlam = GetGameTimeMilliseconds() / 1000 + SLAM_CD
    CA.alert(nil, Fmt.c(Fmt.ORANGE, "Behemoth SLAM!"),
        0xFF8800D9, SOUNDS.DUEL_START, 3000)
end

local function handleLureOfSea(boss, ctx, alerts, abilityId, ...)
    CA.castAlertsStop(boss.lureBarId)
    boss.lureBarId = CA.bar(
        abilityId, "Lure of the Sea", 4000, 4000, Colors.VOID, 0.5, ACT_BREAK)
end

local function handleAspectTerror(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_FEAR_DUR)
    CA.ranged(abilityId, sourceUnitName, dur, Colors.VOID)
end

-- Bridge handlers (3 named functions, replaces makeBridgeHandler factory)
local function handleBridge1(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    boss.bridgeOpen[1]      = true
    boss.lastPlatformFall   = now
    boss.bridgeWipeStart[1] = now
    CA.alert(nil, "Bridge 1 open  -  " .. BRIDGE_WIPE .. " s!",
        0xFF8800D9, SOUNDS.DUEL_START, 5000)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleBridge2(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    boss.bridgeOpen[2]      = true
    boss.lastPlatformFall   = now
    boss.bridgeWipeStart[2] = now
    CA.alert(nil, "Bridge 2 open  -  " .. BRIDGE_WIPE .. " s!",
        0xFF8800D9, SOUNDS.DUEL_START, 5000)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleBridge3(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    boss.bridgeOpen[3]      = true
    boss.lastPlatformFall   = now
    boss.bridgeWipeStart[3] = now
    CA.alert(nil, "Bridge 3 open  -  " .. BRIDGE_WIPE .. " s!",
        0xFF8800D9, SOUNDS.DUEL_START, 5000)
    PlaySound(SOUNDS.DUEL_START)
end

-- -- Handlers: effectChanged ------------------------------------------------
-- effectChanged sig: (boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)

-- RapidDeluge: GAINED + player only
local function handleRapidDelugeGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        CA.alert(nil, Fmt.c("66AAff", "Move bubble!") .. "  -  don't stack",
            0x66AAffD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 5000)
    end
end

-- StormWall: GAINED only, no unit args needed
local function handleStormWallCwGained(boss, ctx, alerts, abilityId, ...)
    boss.lastStormWall = GetGameTimeMilliseconds() / 1000
    boss.stormWallCW   = true
end

local function handleStormWallCcwGained(boss, ctx, alerts, abilityId, ...)
    boss.lastStormWall = GetGameTimeMilliseconds() / 1000
    boss.stormWallCW   = false
end

-- Portal effect handlers (3 named functions, replaces makePortalEffectHandler factory)
-- Each is GAINED only; no unit args needed.
-- Labels initialized here so Lang is available (module-level after require).
local PORTAL_LABELS = {
    Fmt.c("22CC22", Lang.t("dsr_taleria_portal_green")),
    Fmt.c("DDCC00", Lang.t("dsr_taleria_portal_yellow")),
    Fmt.c("8822DD", Lang.t("dsr_taleria_portal_purple")),
}

local function handleVenomEvokerPortal(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    boss.bridgeOpen[1]      = true
    boss.bridgeWipeStart[1] = now
    boss.lastPlatformFall   = now
    CA.alert(nil, PORTAL_LABELS[1], PORTAL_COLORS[1], SOUNDS.DUEL_START, 4000)
end

local function handleSeaBoilerPortal(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    boss.bridgeOpen[2]      = true
    boss.bridgeWipeStart[2] = now
    boss.lastPlatformFall   = now
    CA.alert(nil, PORTAL_LABELS[2], PORTAL_COLORS[2], SOUNDS.DUEL_START, 4000)
end

local function handleTidalMagePortal(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    boss.bridgeOpen[3]      = true
    boss.bridgeWipeStart[3] = now
    boss.lastPlatformFall   = now
    CA.alert(nil, PORTAL_LABELS[3], PORTAL_COLORS[3], SOUNDS.DUEL_START, 4000)
end

-- Whirlpool: GAINED + FADED, player only
local function handleWhirlpoolGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        CA.border(true, 8000, "green")
    end
end

local function handleWhirlpoolFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        CA.border(false, 0, nil)
    end
end

-- -- Event tables ------------------------------------------------------------

local _beginCastEntry = {}
for k, v in pairs(DreadsailCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[CRASHING_WAVE_1] = { type = AlertTypes.CUSTOM, fn = handleCrashingWave }
_beginCastEntry[CRASHING_WAVE_2] = { type = AlertTypes.CUSTOM, fn = handleCrashingWave }
_beginCastEntry[CORAL_SLAM]      = { type = AlertTypes.CUSTOM, fn = handleCoralSlam }
_beginCastEntry[BARNACLE_BLADE]  = { type = AlertTypes.CUSTOM, fn = handleBarnacleBlade }
_beginCastEntry[BARNACLE_BLADE_2]= { type = AlertTypes.CUSTOM, fn = handleBarnacleBlade }
_beginCastEntry[MAELSTROM_CAST]  = { type = AlertTypes.CUSTOM, fn = handleMaelstromCast }
_beginCastEntry[BEHEMOTH_SUMMON] = { type = AlertTypes.CUSTOM, fn = handleBehemothSummon }
_beginCastEntry[ARCTIC_ANNIH]    = { type = AlertTypes.CUSTOM, fn = handleArcticAnnih }
_beginCastEntry[LURE_OF_SEA]     = { type = AlertTypes.CUSTOM, fn = handleLureOfSea }
_beginCastEntry[ASPECT_TERROR]   = { type = AlertTypes.CUSTOM, fn = handleAspectTerror }
_beginCastEntry[BRIDGE_1]        = { type = AlertTypes.CUSTOM, fn = handleBridge1 }
_beginCastEntry[BRIDGE_2]        = { type = AlertTypes.CUSTOM, fn = handleBridge2 }
_beginCastEntry[BRIDGE_3]        = { type = AlertTypes.CUSTOM, fn = handleBridge3 }

local _effectGainedEntry = {}
for k, v in pairs(DreadsailCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
_effectGainedEntry[RAPID_DELUGE_N]  = { type = AlertTypes.CUSTOM, fn = handleRapidDelugeGained }
_effectGainedEntry[RAPID_DELUGE_V]  = { type = AlertTypes.CUSTOM, fn = handleRapidDelugeGained }
_effectGainedEntry[RAPID_DELUGE_HM] = { type = AlertTypes.CUSTOM, fn = handleRapidDelugeGained }
_effectGainedEntry[STORM_WALL_CW]   = { type = AlertTypes.CUSTOM, fn = handleStormWallCwGained }
_effectGainedEntry[STORM_WALL_CCW]  = { type = AlertTypes.CUSTOM, fn = handleStormWallCcwGained }
_effectGainedEntry[VENOM_EVOKER_P]  = { type = AlertTypes.CUSTOM, fn = handleVenomEvokerPortal }
_effectGainedEntry[SEA_BOILER_P]    = { type = AlertTypes.CUSTOM, fn = handleSeaBoilerPortal }
_effectGainedEntry[TIDAL_MAGE_P]    = { type = AlertTypes.CUSTOM, fn = handleTidalMagePortal }
_effectGainedEntry[WHIRLPOOL]       = { type = AlertTypes.CUSTOM, fn = handleWhirlpoolGained }

local _effectFadedEntry = {}
for k, v in pairs(DreadsailCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end
_effectFadedEntry[WHIRLPOOL] = { type = AlertTypes.CUSTOM, fn = handleWhirlpoolFaded }

Taleria.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

-- -- Info-line renderers ---------------------------------------------------

local function showMaelstromLine(self, alerts, now)
    if self.lastMaelstrom > 0 then
        local elapsed = now - self.lastMaelstrom
        if elapsed < MAELSTROM_DUR then
            local T = MAELSTROM_DUR - elapsed
            if T <= MAELSTROM_DODGE then
                alerts:setRow(1, Fmt.c(Fmt.RED, Lang.t("dsr_taleria_dodge_maelstrom")), nil)
            else
                alerts:setRow(1, Fmt.c(Fmt.POISON, Lang.t("dsr_taleria_heal")), T)
            end
        else
            local T = MAELSTROM_CD - elapsed
            if T > 0 then
                alerts:setRow(1, Fmt.c(Fmt.POISON, Lang.t("dsr_taleria_maelstrom")), T)
            else
                alerts:setRow(1,
                    Fmt.c(Fmt.POISON, Lang.t("dsr_taleria_maelstrom")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
            end
        end
    else
        alerts:clearRow(1)
    end
end

local function showBehemothLine(self, alerts, now, isHM)
    local behCD = isHM and BEHEMOTH_CD_HM or BEHEMOTH_CD_NORM
    if self.lastBehemothSumm > 0 then
        local summonT = behCD - (now - self.lastBehemothSumm)
        local slamT   = (self.behemothSlam > 0) and (self.behemothSlam - now) or -1

        if slamT >= 0 and slamT <= 3 then
            alerts:setRow(2, Fmt.c(Fmt.ORANGE, Lang.t("dsr_taleria_behemoth_slam")), slamT)
        elseif summonT > 0 then
            alerts:setRow(2, Fmt.c(Fmt.ORANGE, Lang.t("dsr_taleria_behemoth")), summonT)
        else
            alerts:setRow(2,
                Fmt.c(Fmt.ORANGE, Lang.t("dsr_taleria_behemoth")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(2)
    end
end

local function showStormWallLine(self, alerts, now)
    local suppressStorm = (now - self.lastPlatformFall < BRIDGE_WIPE)
    if self.lastStormWall > 0 and not suppressStorm then
        local T = STORM_WALL_DUR - (now - self.lastStormWall)
        if T > 0 then
            alerts:setRow(3, Fmt.c(Fmt.PURPLE, Lang.t(
                self.stormWallCW and "dsr_taleria_storm_cw" or "dsr_taleria_storm_ccw")), T)
        else
            alerts:clearRow(3)
        end
    else
        alerts:clearRow(3)
    end
end

local function showBridgeLine(self, alerts, now, context)
    local bridgeLabels = {}
    local names = {
        Fmt.c("22CC22", Lang.t("dsr_taleria_bridge_label_1")),
        Fmt.c("DDCC00", Lang.t("dsr_taleria_bridge_label_2")),
        Fmt.c("8822DD", Lang.t("dsr_taleria_bridge_label_3")),
    }
    for i = 1, 3 do
        if self.bridgeWipeStart[i] > 0 and not self.bridgeDone[i] then
            local T = BRIDGE_WIPE - (now - self.bridgeWipeStart[i])
            if T > 0 then
                local tStr = string.format("%.0f", T) .. "s"
                table.insert(bridgeLabels,
                    names[i] .. " " .. ((T <= 15) and Fmt.c(Fmt.RED, tStr) or tStr))
            else
                self.bridgeWipeStart[i] = 0
            end
        end
    end

    if #bridgeLabels > 0 then
        alerts:setRow(4, table.concat(bridgeLabels, "  "), nil)
    else
        local hp = context.healthPercent
        local nextBridge = nil
        if hp then
            for i = 1, 3 do
                if not self.bridgeOpen[i] then
                    nextBridge = BRIDGE_HP[i]
                    break
                end
            end
        end
        if nextBridge then
            alerts:setRow(4, Fmt.c(Fmt.YELLOW,
                Lang.t("dsr_taleria_next_bridge") .. Fmt.pct(nextBridge, 1)), nil)
        else
            alerts:clearRow(4)
        end
    end
end

function Taleria:onWipe(context, alerts)
    CA.castAlertsStop(self.lureBarId)
    self.lureBarId        = nil
    self.lastMaelstrom    = 0;    self.lastBehemothSumm = 0
    self.behemothSlam     = 0;    self.lastStormWall    = 0
    self.stormWallCW      = true; self.lastPlatformFall = 0
    self.bridgeOpen       = { false, false, false }
    self.bridgeWipeStart  = { 0, 0, 0 }
    self.bridgeDone       = { false, false, false }
    CA.border(false, 0, "green")
end

function Taleria:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showMaelstromLine(self, alerts, now)
    showBehemothLine(self, alerts, now, isHM)
    showStormWallLine(self, alerts, now)
    showBridgeLine(self, alerts, now, context)
end

EventDispatcher.build(Taleria)

package.loaded["trial.dsr.boss.Taleria"] = Taleria
return Taleria
