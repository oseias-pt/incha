--- Taleria (Tideborn Taleria) — Dreadsail Reef boss 3
---
--- Phase DSR-5: full mechanics
---   RapidDeluge (174959/174960/174961 HM): EFFECT_GAINED + player → Alert "Move bubble!"
---   CrashingWave (166353 / 174943): BEGIN + player → AlertCast
---   CoralSlam (163987): BEGIN + player → AlertCast (heavy)
---   BarnaclesBlade (163901): BEGIN + player → AlertCast
---   MaelstromCast (166292): BEGIN → lastMaelstrom; 35 s cycle
---   BehemothSummon (166928): BEGIN → behemoth summon tracker; 60 s / 45 s HM
---   ArcticAnnihilation (165827): BEGIN → behemoth slam timer (17 s next)
---   StormWall CW (175447): EFFECT_GAINED → wind direction CW
---   StormWall CCW (174866): EFFECT_GAINED → wind direction CCW
---   LureOfTheSea (163952): BEGIN → CastAlertsStart 4 s + "Break free!" action
---   AspectsOfTerror (174697): BEGIN + player → AlertCast (fear)
---   Portal opens: VenomEvoker (175132), SeaBoiler (175134), TidalMage (175136)
---   Bridge starts: 166479 / 175279 / 175291 → 60 s wipe timers
---   Whirlpool (163896): EFFECT_GAINED + player → AlertBorder green
---   Portal debuffs: nematocyst (174679/169938), sweltering (174689/169936),
---                   suffocating (174691/169935) → tracked per player

local Difficulty      = require("core.Difficulty")
local DreadsailCommon = require("trial.dsr.DreadsailCommon")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local RAPID_DELUGE_N   = 174959   -- Rapid Deluge normal
local RAPID_DELUGE_V   = 174960   -- Rapid Deluge vet
local RAPID_DELUGE_HM  = 174961   -- Rapid Deluge HM
local CRASHING_WAVE_1  = 166353   -- Crashing Wave boss cast
local CRASHING_WAVE_2  = 174943   -- Crashing Wave tank entity
local CORAL_SLAM       = 163987   -- heavy melee
local BARNACLE_BLADE   = 163901   -- light + BEGIN targeted
local MAELSTROM_CAST   = 166292   -- Maelstrom channel begin
local BEHEMOTH_SUMMON  = 166928   -- Sea Behemoth summoned
local ARCTIC_ANNIH     = 165827   -- Arctic Annihilation slam
local STORM_WALL_CW    = 175447   -- Storm Wall clockwise spin
local STORM_WALL_CCW   = 174866   -- Storm Wall counter-clockwise spin
local LURE_OF_SEA      = 163952   -- fear cast
local ASPECT_TERROR    = 174697   -- Sea Boiler fear cast
local VENOM_EVOKER_P   = 175132   -- green portal opens (EFFECT_CHANGED)
local SEA_BOILER_P     = 175134   -- yellow portal opens
local TIDAL_MAGE_P     = 175136   -- purple portal opens
local BRIDGE_1         = 166479   -- Bridge 1 BEGIN
local BRIDGE_2         = 175279   -- Bridge 2 BEGIN
local BRIDGE_3         = 175291   -- Bridge 3 BEGIN
local WHIRLPOOL        = 163896   -- pool debuff on player
-- Portal / aoe debuffs
local NEMATOCYST_P     = 174679   -- green portal debuff
local NEMATOCYST_AOE   = 169938
local SWELTERING_P     = 174689   -- yellow portal debuff
local SWELTERING_AOE   = 169936
local SUFFOCATING_P    = 174691   -- purple portal debuff
local SUFFOCATING_AOE  = 169935

-- ── Timing constants ─────────────────────────────────────────────────────
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

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_HEAVY  = { -2, 0, false, { 1.0, 0.35, 0.1, 0.4 }, { 1.0, 0.35, 0.1, 0.8 } }
local COL_FEAR   = { 0.6, 0.0, 0.9, 0.5 }
local ACT_BREAK  = { 4000, "Break free!", 0.9, 0.1, 0.1, 0.9, nil }

-- ── Boss definition ───────────────────────────────────────────────────────
local Taleria = {
    id   = 3,
    key  = "taleria",
    name = "Tideborn Taleria",   -- TODO: verify via GetUnitName("boss1") in-game
    hmHealthThreshold = 100000001,  -- TODO: verify
}

-- ── State ─────────────────────────────────────────────────────────────────
Taleria.lastMaelstrom     = 0     -- s: when maelstrom channel began
Taleria.lastBehemothSumm  = 0     -- s: last behemoth summon
Taleria.behemothSlam      = 0     -- s: expected next slam time
Taleria.lastStormWall     = 0     -- s: when storm wall began spinning
Taleria.stormWallCW       = true  -- true = CW, false = CCW
Taleria.lastPlatformFall  = 0     -- s: when last bridge opened (portal suppresses storm display)

-- Bridge state: index 1/2/3 = green/yellow/purple
Taleria.bridgeOpen      = { false, false, false }
Taleria.bridgeWipeStart = { 0, 0, 0 }          -- s: when wipe timer began
Taleria.bridgeDone      = { false, false, false }

-- Lure of the Sea bar ID for cleanup
Taleria.lureBarId = nil

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Taleria:reset(forced)
    self.lastMaelstrom    = 0
    self.lastBehemothSumm = 0
    self.behemothSlam     = 0
    self.lastStormWall    = 0
    self.stormWallCW      = true
    self.lastPlatformFall = 0

    self.bridgeOpen      = { false, false, false }
    self.bridgeWipeStart = { 0, 0, 0 }
    self.bridgeDone      = { false, false, false }

    CA.castAlertsStop(self.lureBarId)
    self.lureBarId = nil
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Taleria:onCombatState(context, inCombat, alerts)
    if inCombat then
        self:reset(false)
    end
end

-- ── Combat events ─────────────────────────────────────────────────────────
function Taleria:onCombatEvent(context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    if DreadsailCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    if result ~= ACTION_RESULT_BEGIN then return end

    local isHM = (context.difficulty == Difficulty.HARDMODE)

    -- ── Crashing Wave (tank-targeted) ─────────────────────────────────────
    if abilityId == CRASHING_WAVE_1 or abilityId == CRASHING_WAVE_2 then
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
        return
    end

    -- ── Coral Slam (heavy) ────────────────────────────────────────────────
    if abilityId == CORAL_SLAM then
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 1500 end
        CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
        return
    end

    -- ── Barnacle's Blade (light + targeted) ───────────────────────────────
    if abilityId == BARNACLE_BLADE then
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 1000 end
        CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
        return
    end

    -- ── Maelstrom ─────────────────────────────────────────────────────────
    if abilityId == MAELSTROM_CAST then
        self.lastMaelstrom = GetGameTimeMilliseconds() / 1000
        CA.alert(nil, "|c66CC66Maelstrom — HEAL!|r (6 s)",
            0x66CC66D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 6000)
        return
    end

    -- ── Behemoth summon ───────────────────────────────────────────────────
    if abilityId == BEHEMOTH_SUMMON then
        local now = GetGameTimeMilliseconds() / 1000
        self.lastBehemothSumm = now
        self.behemothSlam     = now + 10   -- first slam ~10 s after summon
        CA.alert(nil, "Sea Behemoth summoned!",
            0xFF8800D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
        return
    end

    -- ── Arctic Annihilation (slam) ────────────────────────────────────────
    if abilityId == ARCTIC_ANNIH then
        local now = GetGameTimeMilliseconds() / 1000
        self.behemothSlam = now + SLAM_CD
        CA.alert(nil, "|cFF8800Behemoth SLAM!|r",
            0xFF8800D9, SOUNDS.DUEL_START, 3000)
        return
    end

    -- ── Lure of the Sea (fear) ────────────────────────────────────────────
    if abilityId == LURE_OF_SEA then
        CA.castAlertsStop(self.lureBarId)
        self.lureBarId = CA.castAlertsStart(
            abilityId, "Lure of the Sea", 4000, 4000, COL_FEAR, ACT_BREAK)
        return
    end

    -- ── Aspect of Terror (Sea Boiler fear) ───────────────────────────────
    if abilityId == ASPECT_TERROR then
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        CA.alertCast(abilityId, sourceUnitName, dur, COL_FEAR)
        return
    end

    -- ── Bridge timers: opened on BEGIN ────────────────────────────────────
    -- Each bridge begins at a specific HP threshold; timer starts on the cast.
    local bridgeIdx = nil
    if abilityId == BRIDGE_1 then bridgeIdx = 1
    elseif abilityId == BRIDGE_2 then bridgeIdx = 2
    elseif abilityId == BRIDGE_3 then bridgeIdx = 3
    end
    if bridgeIdx then
        local now = GetGameTimeMilliseconds() / 1000
        self.lastPlatformFall      = now
        self.bridgeWipeStart[bridgeIdx] = now
        CA.alert(nil,
            "Bridge " .. bridgeIdx .. " open — " .. BRIDGE_WIPE .. " s!",
            0xFF8800D9, SOUNDS.DUEL_START, 5000)
        PlaySound(SOUNDS.DUEL_START)
        return
    end
end

-- ── Effect changes ────────────────────────────────────────────────────────
function Taleria:onEffectChanged(context, alerts, changeType, abilityId,
                                  unitTag, unitId, unitName)
    if DreadsailCommon.handleEffect(alerts, changeType, abilityId, unitTag) then
        return
    end

    -- ── Rapid Deluge bubble on player ─────────────────────────────────────
    if abilityId == RAPID_DELUGE_N
       or abilityId == RAPID_DELUGE_V
       or abilityId == RAPID_DELUGE_HM then
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            CA.alert(nil, "|c66AAffMove bubble!|r — don't stack",
                0x66AAffD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 5000)
        end
        return
    end

    -- ── Storm Wall CW ─────────────────────────────────────────────────────
    if abilityId == STORM_WALL_CW then
        if changeType == EFFECT_RESULT_GAINED then
            self.lastStormWall = GetGameTimeMilliseconds() / 1000
            self.stormWallCW   = true
        end
        return
    end

    -- ── Storm Wall CCW ────────────────────────────────────────────────────
    if abilityId == STORM_WALL_CCW then
        if changeType == EFFECT_RESULT_GAINED then
            self.lastStormWall = GetGameTimeMilliseconds() / 1000
            self.stormWallCW   = false
        end
        return
    end

    -- ── Venom Evoker (green) portal opens ────────────────────────────────
    if abilityId == VENOM_EVOKER_P then
        if changeType == EFFECT_RESULT_GAINED then
            local now = GetGameTimeMilliseconds() / 1000
            self.bridgeOpen[1]      = true
            self.bridgeWipeStart[1] = now
            self.lastPlatformFall   = now
            CA.alert(nil, "|c22CC22Green portal open|r — 60 s!",
                0x22CC22D9, SOUNDS.DUEL_START, 4000)
        end
        return
    end

    -- ── Sea Boiler (yellow) portal opens ─────────────────────────────────
    if abilityId == SEA_BOILER_P then
        if changeType == EFFECT_RESULT_GAINED then
            local now = GetGameTimeMilliseconds() / 1000
            self.bridgeOpen[2]      = true
            self.bridgeWipeStart[2] = now
            self.lastPlatformFall   = now
            CA.alert(nil, "|cDDCC00Yellow portal open|r — 60 s!",
                0xDDCC00D9, SOUNDS.DUEL_START, 4000)
        end
        return
    end

    -- ── Tidal Mage (purple) portal opens ─────────────────────────────────
    if abilityId == TIDAL_MAGE_P then
        if changeType == EFFECT_RESULT_GAINED then
            local now = GetGameTimeMilliseconds() / 1000
            self.bridgeOpen[3]      = true
            self.bridgeWipeStart[3] = now
            self.lastPlatformFall   = now
            CA.alert(nil, "|c8822DDPurple portal open|r — 60 s!",
                0x8822DDD9, SOUNDS.DUEL_START, 4000)
        end
        return
    end

    -- ── Whirlpool (pool on player) ────────────────────────────────────────
    if abilityId == WHIRLPOOL then
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            CA.border(true, 8000, "green")
        elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
            CA.border(false, 0, nil)
        end
        return
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Taleria:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = (context.difficulty == Difficulty.HARDMODE)

    -- ── Info 1: Maelstrom heal window / countdown ─────────────────────────
    if self.lastMaelstrom > 0 then
        local elapsed = now - self.lastMaelstrom
        if elapsed < MAELSTROM_DUR then
            -- Active: show heal window remaining (and dodge cue near end)
            local T = MAELSTROM_DUR - elapsed
            if T <= MAELSTROM_DODGE then
                alerts:showInfo(1, "|cff0000DODGE!|r (Maelstrom ends)")
            else
                alerts:showInfo(1,
                    "|c66CC66HEAL!|r (" .. string.format("%.0f", T) .. "s)")
            end
        else
            -- Counting down to next
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

    -- ── Info 2: Next Behemoth summon / slam ───────────────────────────────
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

    -- ── Info 3: Winter Storm — countdown / direction during spin ──────────
    -- Suppress during platform fall (portal active) for 60 s.
    local suppressStorm = (now - self.lastPlatformFall < BRIDGE_WIPE)
    if self.lastStormWall > 0 and not suppressStorm then
        local T = STORM_WALL_DUR - (now - self.lastStormWall)
        if T > 0 then
            local dir = self.stormWallCW and "CW ↻" or "CCW ↺"
            alerts:showInfo(3,
                "|cD672F7Storm " .. dir .. "|r — " ..
                string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(3, "")
        end
    else
        alerts:showInfo(3, "")
    end

    -- ── Info 4: Active bridge wipe timers ─────────────────────────────────
    -- Collect all active bridges.
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
                -- Wipe expired
                self.bridgeWipeStart[i] = 0
            end
        end
    end

    if #bridgeLabels > 0 then
        alerts:showInfo(4, table.concat(bridgeLabels, "  "))
    else
        -- Show next bridge HP threshold if not all done
        local hp = context.extras and context.extras.healthPercent
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

return Taleria
