--- Taleria (Tideborn Taleria)  -  Dreadsail Reef boss 3
---
--- Phase DSR-5: full mechanics
---   RapidDeluge (174959/174960/174961 HM): EFFECT_GAINED + player -> Alert "Move bubble!"
---   CrashingWave (166353 / 174943): BEGIN + player -> AlertCast
---   CoralSlam (163987): BEGIN + player -> AlertCast (heavy)
---   BarnaclesBlade (163901): BEGIN + player -> AlertCast
---   MaelstromCast (166292): BEGIN -> lastMaelstrom; 35 s cycle
---   BehemothSummon (166928): BEGIN -> behemoth summon tracker; 60 s / 45 s HM
---   ArcticAnnihilation (165827): BEGIN -> behemoth slam timer (17 s next)
---   StormWall CW (175447): EFFECT_GAINED -> wind direction CW
---   StormWall CCW (174866): EFFECT_GAINED -> wind direction CCW
---   LureOfTheSea (163952): BEGIN -> CastAlertsStart 4 s + "Break free!" action
---   AspectsOfTerror (174697): BEGIN + player -> AlertCast (fear)
---   Portal opens: VenomEvoker (175132), SeaBoiler (175134), TidalMage (175136)
---   Bridge starts: 166479 / 175279 / 175291 -> 60 s wipe timers
---   Whirlpool (163896): EFFECT_GAINED + player -> AlertBorder green
---   Portal debuffs: nematocyst (174679/169938), sweltering (174689/169936),
---                   suffocating (174691/169935) -> tracked per player

local DreadsailCommon = require("trial.dsr.DreadsailCommon")
local CastDur = require("lib.CastDur")

-- -- Ability IDs -----------------------------------------------------------
local RAPID_DELUGE_N   = 174959   -- effectRoute: EFFECT_RESULT_GAINED + player -> Move bubble alert
local RAPID_DELUGE_V   = 174960   -- effectRoute: EFFECT_RESULT_GAINED + player -> Move bubble alert
local RAPID_DELUGE_HM  = 174961   -- effectRoute: EFFECT_RESULT_GAINED + player -> Move bubble alert
local CRASHING_WAVE_1  = 166353   -- combatRoute: ACTION_RESULT_BEGIN + player -> caAlertCast
local CRASHING_WAVE_2  = 174943   -- combatRoute: ACTION_RESULT_BEGIN + player -> caAlertCast
local CORAL_SLAM       = 163987   -- combatRoute: ACTION_RESULT_BEGIN + player -> caAlertCast (heavy)
local BARNACLE_BLADE   = 163901   -- combatRoute: ACTION_RESULT_BEGIN + player -> caAlertCast
local MAELSTROM_CAST   = 166292   -- combatRoute: ACTION_RESULT_BEGIN -> Maelstrom heal 6s
local BEHEMOTH_SUMMON  = 166928   -- combatRoute: ACTION_RESULT_BEGIN -> behemoth summon tracker
local ARCTIC_ANNIH     = 165827   -- combatRoute: ACTION_RESULT_BEGIN -> slam timer +17s
local STORM_WALL_CW    = 175447   -- effectRoute: EFFECT_RESULT_GAINED -> stormWallCW = true
local STORM_WALL_CCW   = 174866   -- effectRoute: EFFECT_RESULT_GAINED -> stormWallCW = false
local LURE_OF_SEA      = 163952   -- combatRoute: ACTION_RESULT_BEGIN -> CastAlertsStart 4s + Break free
local ASPECT_TERROR    = 174697   -- combatRoute: ACTION_RESULT_BEGIN + player -> caAlertCast (fear)
local VENOM_EVOKER_P   = 175132   -- effectRoute: EFFECT_RESULT_GAINED -> green portal 60s  (makePortalEffectHandler 1)
local SEA_BOILER_P     = 175134   -- effectRoute: EFFECT_RESULT_GAINED -> yellow portal 60s (makePortalEffectHandler 2)
local TIDAL_MAGE_P     = 175136   -- effectRoute: EFFECT_RESULT_GAINED -> purple portal 60s (makePortalEffectHandler 3)
local BRIDGE_1         = 166479   -- combatRoute: ACTION_RESULT_BEGIN -> bridge wipe 60s
local BRIDGE_2         = 175279   -- combatRoute: ACTION_RESULT_BEGIN -> bridge wipe 60s
local BRIDGE_3         = 175291   -- combatRoute: ACTION_RESULT_BEGIN -> bridge wipe 60s
local WHIRLPOOL        = 163896   -- effectRoute: EFFECT_RESULT_GAINED / FADED + player -> green border
-- Portal / aoe debuffs
local NEMATOCYST_P     = 174679   -- green portal debuff
local NEMATOCYST_AOE   = 169938
local SWELTERING_P     = 174689   -- yellow portal debuff
local SWELTERING_AOE   = 169936
local SUFFOCATING_P    = 174691   -- purple portal debuff
local SUFFOCATING_AOE  = 169935

-- -- Timing constants -----------------------------------------------------
local MAELSTROM_CD     = 35    -- s: maelstrom cycle
local MAELSTROM_DUR    = 6     -- s: heal window
local BEHEMOTH_CD_NORM = 60    -- s: behemoth respawn (normal)
local BEHEMOTH_CD_HM   = 45    -- s: behemoth respawn (HM)
local SLAM_CD          = 17    -- s: Arctic Annihilation repeat
local STORM_WALL_DUR   = 45    -- s: storm wall spin window
local BRIDGE_WIPE      = 60    -- s: bridge wipe timer
local MAELSTROM_DODGE  = 1.5   -- s: dodge before maelstrom ends

-- HP thresholds for bridge openings (vet percentages)
local BRIDGE_HP = { 50.9, 35.9, 20.9 }

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")

-- -- CA colour palettes ----------------------------------------------------
local COL_HEAVY  = { -2, 0, false, { 1.0, 0.35, 0.1, 0.4 }, { 1.0, 0.35, 0.1, 0.8 } }
local COL_FEAR   = { 0.6, 0.0, 0.9, 0.5 }
local ACT_BREAK  = { 4000, "Break free!", 0.9, 0.1, 0.1, 0.9, nil }

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_WAVE_DUR  = 2000   -- CrashingWave: empirical
local FALLBACK_SLAM_DUR  = 1500   -- CoralSlam (heavy): empirical
local FALLBACK_BLADE_DUR = 1000   -- BarnacleBlade: empirical
local FALLBACK_FEAR_DUR  = 2000   -- AspectsOfTerror: empirical

-- -- Boss definition -------------------------------------------------------
local Taleria = {}
Taleria.__index = Taleria

Taleria.key              = "taleria"
Taleria.name             = "Tideborn Taleria"   -- TODO: verify via GetUnitName("boss1") in-game
-- location: arena AABB not yet captured  -  detection is name-based.
-- To add AABB: stand in arena, run /script d(GetUnitWorldPosition("boss1"))
Taleria.hmHealthThreshold = 100000001            -- TODO: verify

Taleria.stateSchema = {
    lastMaelstrom     = 0,
    lastBehemothSumm  = 0,
    behemothSlam      = 0,
    lastStormWall     = 0,
    stormWallCW       = true,
    lastPlatformFall  = 0,
    -- Bridge state: index 1/2/3 = green/yellow/purple
    bridgeOpen      = function() return { false, false, false } end,
    bridgeWipeStart = function() return { 0, 0, 0 } end,
    bridgeDone      = function() return { false, false, false } end,
    -- CA cast-bar handle for Lure of the Deep; false = no bar active.
    lureBarId       = false,
}

function Taleria.new()
    return BossBase.fromSchema(Taleria)
end

-- -- Lifecycle -------------------------------------------------------------
function Taleria:onLeave(context)
    CA.castAlertsStop(self.lureBarId)
end

-- -- Routing tables (C3) --------------------------------------------------
-- Shared trash mechanic handler.
Taleria.common = DreadsailCommon

-- Crashing Wave: two IDs, same handler.
local function handleCrashingWave(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_WAVE_DUR)
    CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
end

-- Bridge open: closes over the bridge index.
local function makeBridgeHandler(bridgeIdx)
    return { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        local now = GetGameTimeMilliseconds() / 1000
        self.bridgeOpen[bridgeIdx]      = true
        self.lastPlatformFall           = now
        self.bridgeWipeStart[bridgeIdx] = now
        CA.alert(nil,
            "Bridge " .. bridgeIdx .. " open  -  " .. BRIDGE_WIPE .. " s!",
            0xFF8800D9, SOUNDS.DUEL_START, 5000)
        PlaySound(SOUNDS.DUEL_START)
    end }
end

local function handleCoralSlam(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_SLAM_DUR)
    CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
end

local function handleBarnacleBlade(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_BLADE_DUR)
    CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
end

local function handleMaelstromCast(self, context, alerts, abilityId, ...)
    self.lastMaelstrom = GetGameTimeMilliseconds() / 1000
    CA.alert(nil, "|c66CC66Maelstrom  -  HEAL!|r (6 s)",
        0x66CC66D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 6000)
end

local function handleBehemothSummon(self, context, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    self.lastBehemothSumm = now
    self.behemothSlam     = now + 10   -- first slam ~10 s after summon
    CA.alert(nil, "Sea Behemoth summoned!",
        0xFF8800D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
end

local function handleArcticAnnih(self, context, alerts, abilityId, ...)
    self.behemothSlam = GetGameTimeMilliseconds() / 1000 + SLAM_CD
    CA.alert(nil, "|cFF8800Behemoth SLAM!|r",
        0xFF8800D9, SOUNDS.DUEL_START, 3000)
end

local function handleLureOfSea(self, context, alerts, abilityId, ...)
    CA.castAlertsStop(self.lureBarId)
    self.lureBarId = CA.castAlertsStart(
        abilityId, "Lure of the Sea", 4000, 4000, COL_FEAR, ACT_BREAK)
end

local function handleAspectTerror(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_FEAR_DUR)
    CA.alertCast(abilityId, sourceUnitName, dur, COL_FEAR)
end

Taleria.combatRoutes = {
    [CRASHING_WAVE_1] = { result = ACTION_RESULT_BEGIN, fn = handleCrashingWave },
    [CRASHING_WAVE_2] = { result = ACTION_RESULT_BEGIN, fn = handleCrashingWave },
    [CORAL_SLAM]      = { result = ACTION_RESULT_BEGIN, fn = handleCoralSlam },
    [BARNACLE_BLADE]  = { result = ACTION_RESULT_BEGIN, fn = handleBarnacleBlade },
    [MAELSTROM_CAST]  = { result = ACTION_RESULT_BEGIN, fn = handleMaelstromCast },
    [BEHEMOTH_SUMMON] = { result = ACTION_RESULT_BEGIN, fn = handleBehemothSummon },
    [ARCTIC_ANNIH]    = { result = ACTION_RESULT_BEGIN, fn = handleArcticAnnih },
    [LURE_OF_SEA]     = { result = ACTION_RESULT_BEGIN, fn = handleLureOfSea },
    [ASPECT_TERROR]   = { result = ACTION_RESULT_BEGIN, fn = handleAspectTerror },
    [BRIDGE_1] = makeBridgeHandler(1),
    [BRIDGE_2] = makeBridgeHandler(2),
    [BRIDGE_3] = makeBridgeHandler(3),
}

-- Rapid Deluge: three IDs, same handler.
local function handleRapidDeluge(self, context, alerts, changeType, abilityId,
                                  unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        CA.alert(nil, "|c66AAffMove bubble!|r  -  don't stack",
            0x66AAffD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 5000)
    end
end

local function handleStormWallCw(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        self.lastStormWall = GetGameTimeMilliseconds() / 1000
        self.stormWallCW   = true
    end
end

local function handleStormWallCcw(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        self.lastStormWall = GetGameTimeMilliseconds() / 1000
        self.stormWallCW   = false
    end
end

-- Portal open: factory for the three portal-effect handlers (E6).
-- Each differs only in bridge index, display label, and alert colour.
local PORTAL_LABELS = {
    "|c22CC22Green portal open|r  -  60 s!",
    "|cDDCC00Yellow portal open|r  -  60 s!",
    "|c8822DDPurple portal open|r  -  60 s!",
}
local PORTAL_COLORS = { 0x22CC22D9, 0xDDCC00D9, 0x8822DDD9 }

local function makePortalEffectHandler(idx)
    return function(self, context, alerts, abilityId, ...)
        local now = GetGameTimeMilliseconds() / 1000
        self.bridgeOpen[idx]      = true
        self.bridgeWipeStart[idx] = now
        self.lastPlatformFall     = now
        CA.alert(nil, PORTAL_LABELS[idx], PORTAL_COLORS[idx], SOUNDS.DUEL_START, 4000)
    end
end

local function handleWhirlpool(self, context, alerts, changeType, abilityId,
                                unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
        CA.border(true, 8000, "green")
    elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
        CA.border(false, 0, nil)
    end
end

Taleria.effectRoutes = {
    [RAPID_DELUGE_N]  = handleRapidDeluge,
    [RAPID_DELUGE_V]  = handleRapidDeluge,
    [RAPID_DELUGE_HM] = handleRapidDeluge,
    [STORM_WALL_CW]   = handleStormWallCw,
    [STORM_WALL_CCW]  = handleStormWallCcw,
    [VENOM_EVOKER_P]  = { changeType = EFFECT_RESULT_GAINED, fn = makePortalEffectHandler(1) },
    [SEA_BOILER_P]    = { changeType = EFFECT_RESULT_GAINED, fn = makePortalEffectHandler(2) },
    [TIDAL_MAGE_P]    = { changeType = EFFECT_RESULT_GAINED, fn = makePortalEffectHandler(3) },
    [WHIRLPOOL]       = handleWhirlpool,
}

-- -- Info-line renderers ---------------------------------------------------

-- Info 1: Maelstrom  -  active heal window (dodge cue near end) or countdown to next cast.
local function showMaelstromLine(self, alerts, now)
    if self.lastMaelstrom > 0 then
        local elapsed = now - self.lastMaelstrom
        if elapsed < MAELSTROM_DUR then
            local T = MAELSTROM_DUR - elapsed
            if T <= MAELSTROM_DODGE then
                alerts:showInfo(1, "|cff0000DODGE!|r (Maelstrom ends)")
            else
                alerts:showInfo(1,
                    "|c66CC66HEAL!|r (" .. string.format("%.0f", T) .. "s)")
            end
        else
            local T = MAELSTROM_CD - elapsed
            if T > 0 then
                alerts:showInfo(1,
                    "|c66CC66Maelstrom|r: " .. string.format("%.0f", T) .. "s")
            else
                alerts:showInfo(1, "|c66CC66Maelstrom|r: |cff0000INC|r")
            end
        end
    else
        alerts:showInfo(1, "")
    end
end

-- Info 2: Next Behemoth summon countdown, or imminent slam alert (<= 3 s).
local function showBehemothLine(self, alerts, now, isHM)
    local behCD = isHM and BEHEMOTH_CD_HM or BEHEMOTH_CD_NORM
    if self.lastBehemothSumm > 0 then
        local summonT = behCD - (now - self.lastBehemothSumm)
        local slamT   = (self.behemothSlam > 0) and (self.behemothSlam - now) or -1

        if slamT >= 0 and slamT <= 3 then
            alerts:showInfo(2,
                "|cFF8800Behemoth SLAM|r: " .. string.format("%.0f", slamT) .. "s!")
        elseif summonT > 0 then
            alerts:showInfo(2,
                "|cFF8800Behemoth|r: " .. string.format("%.0f", summonT) .. "s")
        else
            alerts:showInfo(2, "|cFF8800Behemoth|r: |cff0000INC|r")
        end
    else
        alerts:showInfo(2, "")
    end
end

-- Info 3: Storm Wall direction and spin countdown; suppressed during platform-fall window.
local function showStormWallLine(self, alerts, now)
    local suppressStorm = (now - self.lastPlatformFall < BRIDGE_WIPE)
    if self.lastStormWall > 0 and not suppressStorm then
        local T = STORM_WALL_DUR - (now - self.lastStormWall)
        if T > 0 then
            local dir = self.stormWallCW and "CW ->" or "CCW <-"
            alerts:showInfo(3,
                "|cD672F7Storm " .. dir .. "|r  -  " ..
                string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(3, "")
        end
    else
        alerts:showInfo(3, "")
    end
end

-- Info 4: Active bridge wipe timers (red when <= 15 s); or next bridge HP threshold.
local function showBridgeLine(self, alerts, now, context)
    local bridgeLabels = {}
    local names = { "|c22CC22G|r", "|cDDCC00Y|r", "|c8822DDPu|r" }
    for i = 1, 3 do
        if self.bridgeWipeStart[i] > 0 and not self.bridgeDone[i] then
            local T = BRIDGE_WIPE - (now - self.bridgeWipeStart[i])
            if T > 0 then
                local col = (T <= 15) and "|cff0000" or ""
                local end_col = (T <= 15) and "|r" or ""
                table.insert(bridgeLabels,
                    names[i] .. " " .. col .. string.format("%.0f", T) .. "s" .. end_col)
            else
                self.bridgeWipeStart[i] = 0
            end
        end
    end

    if #bridgeLabels > 0 then
        alerts:showInfo(4, table.concat(bridgeLabels, "  "))
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
            alerts:showInfo(4,
                "Next bridge: |cffdd00" .. string.format("%.1f", nextBridge) .. "%%|r")
        else
            alerts:showInfo(4, "")
        end
    end
end

function Taleria:onWipe()
    CA.castAlertsStop(self.lureBarId)
    self.lureBarId        = nil
    self.lastMaelstrom    = 0;    self.lastBehemothSumm = 0
    self.behemothSlam     = 0;    self.lastStormWall    = 0
    self.stormWallCW      = true; self.lastPlatformFall = 0
    self.bridgeOpen       = { false, false, false }
    self.bridgeWipeStart  = { 0, 0, 0 }
    self.bridgeDone       = { false, false, false }
end

-- -- 200 ms display loop ---------------------------------------------------
function Taleria:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showMaelstromLine(self, alerts, now)
    showBehemothLine(self, alerts, now, isHM)
    showStormWallLine(self, alerts, now)
    showBridgeLine(self, alerts, now, context)
end

package.loaded["trial.dsr.boss.Taleria"] = Taleria
return Taleria
