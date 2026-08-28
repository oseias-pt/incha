local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- â”€â”€ Ability IDs (from AsylumTracker / AsylumPriorityTarget) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Olms
local OLMS_STORM_THE_HEAVENS  = 98535  -- combatRoute: ACTION_RESULT_BEGIN â†’ Kite alert, reset stormTimer
local OLMS_TRIAL_BY_FIRE      = 98582  -- combatRoute: ACTION_RESULT_BEGIN â†’ Trial by Fire alert, reset fireTimer
local OLMS_SCALDING_ROAR      = 98683  -- combatRoute: ACTION_RESULT_BEGIN â†’ Steam Breath caAlertCast, reset steamTimer
local OLMS_GUSTS_OF_STEAM     = 98868  -- combatRoute: ACTION_RESULT_BEGIN â†’ Jump! alert, advance jump threshold
local OLMS_EXHAUSTIVE_CHARGES = 95482  -- combatRoute: ACTION_RESULT_BEGIN â†’ Charges! alert, reset chargesTimer
-- Protector
local STATIC_SHIELD           = 96010  -- effectRoute: (plain) EFFECT_RESULT_GAINED/FADED â†’ protectorUp state + alert
-- Llothis
local LLOTHIS_DEFILING_BLAST   = 95545  -- combatRoute: ACTION_RESULT_BEGIN â†’ Blast caAlertCast (targeted), reset blastTimer
local LLOTHIS_OPPRESSIVE_BOLTS = 95585  -- combatRoute: ACTION_RESULT_BEGIN â†’ Interrupt! alert, reset boltsTimer
-- Felms
local FELMS_TELEPORT_STRIKE   = 99138  -- combatRoute: ACTION_RESULT_BEGIN â†’ Strike caAlertCast (targeted), reset jumpTimer
-- Mini-boss state
local DORMANT                 = 99990  -- effectRoute: (plain) EFFECT_RESULT_GAINED/FADED â†’ mini-boss dormancy + reseed timers
local BOSS_EVENT              = 10298  -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ mini-boss spawn detection + timer seeding

-- â”€â”€ Timer durations (seconds) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local STORM_CD    = 41
local FIRE_CD     = 27
local STEAM_CD    = 28
local CHARGES_CD  = 12
local BLAST_CD    = 21   -- Llothis Defiling Blast
local BOLTS_CD    = 12   -- Llothis Oppressive Bolts (interrupt)
local JUMP_CD     = 21   -- Felms Teleport Strike
local DORMANT_CD  = 45   -- Mini-boss dormant phase duration
local SPAWN_DELAY = 12   -- Seconds after BOSS_EVENT before first mini ability

-- â”€â”€ Jump milestone thresholds (%) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local JUMP_THRESHOLDS = { 90, 75, 50, 25 }

-- â”€â”€ Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) â”€
local FALLBACK_ROAR_DUR   = 2000   -- OlmsScaldingRoar (Steam Breath): empirical
local FALLBACK_BLAST_DUR  = 1500   -- LlothisDefilingBlast: empirical
local FALLBACK_STRIKE_DUR = 1000   -- FelmsTeleportStrike: empirical

local OlmsEncounter = {}
OlmsEncounter.__index = OlmsEncounter

OlmsEncounter.key               = "olms"
OlmsEncounter.nameAliases       = { "Saint Olms the Just" }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
-- To calibrate: pull on vet HM, run /script d(GetUnitPower("boss1", POWERTYPE_HEALTH))
OlmsEncounter.hmHealthThreshold = math.huge
-- location: placeholder â€” Asylum arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

OlmsEncounter.stateSchema = {
    -- Olms
    stormTimer         = function() return Timer.new(STORM_CD) end,
    steamTimer         = function() return Timer.new(STEAM_CD) end,
    chargesTimer       = function() return Timer.new(CHARGES_CD) end,
    fireTimer          = function() return Timer.new(FIRE_CD) end,
    -- Llothis
    blastTimer         = function() return Timer.new(BLAST_CD) end,
    boltsTimer         = function() return Timer.new(BOLTS_CD) end,
    -- Felms
    jumpTimer          = function() return Timer.new(JUMP_CD) end,
    -- state
    llothisActive      = false,
    felmsActive        = false,
    protectorUp        = false,
    nextJumpThreshold  = 1,
    alertList          = function() return {} end,
}

function OlmsEncounter.new()
    return BossBase.fromSchema(OlmsEncounter)
end

-- â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function OlmsEncounter:onLeave(context)
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
end

-- â”€â”€ Timer seeding helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Seeds one timer accounting for the SPAWN_DELAY already elapsed since
-- BOSS_EVENT.  If spawnTime is nil or seed <= 0, falls back to the timer's
-- own full duration so it fires at the next ordinary interval.
local function seedTimer(t, spawnTime)
    local seed = 0
    if spawnTime then
        seed = math.max(0, SPAWN_DELAY - (os.time() - spawnTime))
    end
    t:reset(seed > 0 and seed or t.duration)
end

-- â”€â”€ Handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- (Olms has no shared common module; no per-unit DIED cleanup needed.)

local function handleStormTheHeavens(self, context, alerts, abilityId, ...)
    alerts:showAction("Kite! (Storm the Heavens)")
    CA.alert(nil, "KITE!", 0xFF4400FF, SOUNDS.NONE, 3000)
    self.stormTimer:reset()
end

local function handleScaldingRoar(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    alerts:showAction("Steam Breath! Move!")
    local dur = CastDur.get(OLMS_SCALDING_ROAR, FALLBACK_ROAR_DUR)
    local cid = CA.alertCast(abilityId, "Steam Breath!", dur,
        { -3, 0, false, { 0.8, 0.4, 0, 0.4 }, { 0.8, 0.4, 0, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
    self.steamTimer:reset()
end

local function handleExhaustiveCharges(self, context, alerts, abilityId, ...)
    alerts:showAction("Charges!")
    self.chargesTimer:reset()
end

local function handleTrialByFire(self, context, alerts, abilityId, ...)
    alerts:showAction("Trial by Fire!")
    self.fireTimer:reset()
end

local function handleGustsOfSteam(self, context, alerts, abilityId, ...)
    alerts:showAction("Jump! Dodge!")
    if self.nextJumpThreshold <= #JUMP_THRESHOLDS then
        self.nextJumpThreshold = self.nextJumpThreshold + 1
    end
end

-- Mini-boss spawn detection (Llothis and Felms share BOSS_EVENT ID)
local function handleBossEvent(self, context, alerts, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    if unitName and unitName:find("Llothis") then
        self.llothisSpawnTime = os.time()
        self.llothisActive    = true
        seedTimer(self.blastTimer, self.llothisSpawnTime)
        seedTimer(self.boltsTimer, self.llothisSpawnTime)
    elseif unitName and unitName:find("Felms") then
        self.felmsSpawnTime = os.time()
        self.felmsActive    = true
        seedTimer(self.jumpTimer, self.felmsSpawnTime)
    end
end

local function handleDefilingBlast(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Blast! â†’ " .. target)
    local dur = CastDur.get(LLOTHIS_DEFILING_BLAST, FALLBACK_BLAST_DUR)
    local cid = CA.alertCast(abilityId, "Blast â†’ " .. target, dur,
        { -3, 0, false, { 0.6, 0, 0.8, 0.4 }, { 0.6, 0, 0.8, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
    self.blastTimer:reset()
end

local function handleOppressiveBolts(self, context, alerts, abilityId, ...)
    alerts:showAction("Interrupt Llothis!")
    CA.alert(nil, "Interrupt!", 0xFF0000FF, SOUNDS.NONE, 2000)
    self.boltsTimer:reset()
end

local function handleTeleportStrike(self, context, alerts, abilityId,
                                     unitTag, sourceUnitTag, sourceUnitId, unitId,
                                     sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Strike! â†’ " .. target)
    local dur = CastDur.get(FELMS_TELEPORT_STRIKE, FALLBACK_STRIKE_DUR)
    local cid = CA.alertCast(abilityId, "Strike â†’ " .. target, dur,
        { -3, 0, false, { 0, 0.6, 0.8, 0.4 }, { 0, 0.6, 0.8, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
    self.jumpTimer:reset()
end

-- DORMANT: mini-boss sleep/wake cycle (Llothis and Felms share this ID).
local function handleDormant(self, context, alerts, changeType, abilityId,
                              unitTag, unitId, unitName, stackCount)
    if unitName and unitName:find("Llothis") then
        if changeType == EFFECT_RESULT_GAINED then
            self.llothisActive = false
            self.blastTimer:clear()
            self.boltsTimer:clear()
        elseif changeType == EFFECT_RESULT_FADED then
            self.llothisActive = true
            seedTimer(self.blastTimer, self.llothisSpawnTime)
            seedTimer(self.boltsTimer, self.llothisSpawnTime)
        end
    elseif unitName and unitName:find("Felms") then
        if changeType == EFFECT_RESULT_GAINED then
            self.felmsActive = false
            self.jumpTimer:clear()
        elseif changeType == EFFECT_RESULT_FADED then
            self.felmsActive = true
            seedTimer(self.jumpTimer, self.felmsSpawnTime)
        end
    end
end

-- Static Shield: Protector NPC channels this onto Olms; kill Protector first.
local function handleStaticShield(self, context, alerts, changeType, abilityId, ...)
    if changeType == EFFECT_RESULT_GAINED then
        self.protectorUp = true
        alerts:showAction("Kill the Protector!")
        CA.alert(nil, "PROTECTOR ACTIVE", 0xFFCC00FF, SOUNDS.NONE, 4000)
    elseif changeType == EFFECT_RESULT_FADED then
        self.protectorUp = false
        alerts:showAction("Shield down!")
    end
end

-- â”€â”€ Routing tables (C3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

OlmsEncounter.combatRoutes = {
    -- â”€â”€ Olms â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [OLMS_STORM_THE_HEAVENS]  = { result = ACTION_RESULT_BEGIN,         fn = handleStormTheHeavens },
    [OLMS_SCALDING_ROAR]      = { result = ACTION_RESULT_BEGIN,         fn = handleScaldingRoar },
    [OLMS_EXHAUSTIVE_CHARGES] = { result = ACTION_RESULT_BEGIN,         fn = handleExhaustiveCharges },
    [OLMS_TRIAL_BY_FIRE]      = { result = ACTION_RESULT_BEGIN,         fn = handleTrialByFire },
    [OLMS_GUSTS_OF_STEAM]     = { result = ACTION_RESULT_BEGIN,         fn = handleGustsOfSteam },
    -- â”€â”€ Mini-boss spawn detection (Llothis and Felms share BOSS_EVENT ID) â”€
    [BOSS_EVENT]              = { result = ACTION_RESULT_EFFECT_GAINED,  fn = handleBossEvent },
    -- â”€â”€ Llothis: combat abilities â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [LLOTHIS_DEFILING_BLAST]   = { result = ACTION_RESULT_BEGIN,         fn = handleDefilingBlast },
    [LLOTHIS_OPPRESSIVE_BOLTS] = { result = ACTION_RESULT_BEGIN,         fn = handleOppressiveBolts },
    -- â”€â”€ Felms: combat abilities â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [FELMS_TELEPORT_STRIKE]   = { result = ACTION_RESULT_BEGIN,         fn = handleTeleportStrike },
}

OlmsEncounter.effectRoutes = {
    [DORMANT]       = handleDormant,
    [STATIC_SHIELD] = handleStaticShield,
}

-- â”€â”€ Info-line renderers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Line 1: Storm timer, displaced by Protector warning when the shield is active.
local function showStormLine(self, alerts)
    if self.protectorUp then
        alerts:showInfo(1, "|cffcc00âš  PROTECTOR ACTIVE|r")
    else
        local t = self.stormTimer:remaining()
        alerts:showInfo(1, "Storm:   " .. (t > 0 and ZO_FormatCountdownTimer(t) or "ready"))
    end
end

-- Lines 2-4: Olms core timers (always visible).
local function showOlmsLines(self, alerts)
    local t2 = self.steamTimer:remaining()
    local t3 = self.chargesTimer:remaining()
    local t4 = self.fireTimer:remaining()
    alerts:showInfo(2, "Steam:   " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
    alerts:showInfo(3, "Charges: " .. (t3 > 0 and ZO_FormatCountdownTimer(t3) or "ready"))
    alerts:showInfo(4, t4 > 0 and ("Fire:    " .. ZO_FormatCountdownTimer(t4)) or "")
end

-- Line 5: Llothis â€” not yet spawned, dormant, or blast timer.
local function showLlothisLine(self, alerts)
    if self.llothisSpawnTime == nil then
        alerts:showInfo(5, "")
    elseif not self.llothisActive then
        alerts:showInfo(5, "Llothis: DORMANT")
    else
        local t = self.blastTimer:remaining()
        alerts:showInfo(5, "Blast:   " .. (t > 0 and ZO_FormatCountdownTimer(t) or "ready"))
    end
end

-- Line 6: Llothis interrupt timer (hidden while dormant).
local function showBoltsLine(self, alerts)
    if self.llothisActive then
        local t = self.boltsTimer:remaining()
        alerts:showInfo(6, "Bolts:   " .. (t > 0 and ZO_FormatCountdownTimer(t) or "!INTERRUPT"))
    else
        alerts:showInfo(6, "")
    end
end

-- Line 7: Felms â€” not yet spawned, dormant, or strike timer.
local function showFelmsLine(self, alerts)
    if self.felmsSpawnTime == nil then
        alerts:showInfo(7, "")
    elseif not self.felmsActive then
        alerts:showInfo(7, "Felms:   DORMANT")
    else
        local t = self.jumpTimer:remaining()
        alerts:showInfo(7, "Strike:  " .. (t > 0 and ZO_FormatCountdownTimer(t) or "ready"))
    end
end

-- â”€â”€ 200 ms display update â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function OlmsEncounter:onUpdate(context, alerts)
    showStormLine(self, alerts)
    showOlmsLines(self, alerts)
    showLlothisLine(self, alerts)
    showBoltsLine(self, alerts)
    showFelmsLine(self, alerts)
end

-- â”€â”€ HP milestone pre-warning â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function OlmsEncounter:onPowerUpdate(context, healthPercent, alerts)
    if self.nextJumpThreshold > #JUMP_THRESHOLDS then return end
    local threshold = JUMP_THRESHOLDS[self.nextJumpThreshold]
    if healthPercent <= threshold + 3 and healthPercent > threshold then
        alerts:showInfo(1, "Jump at " .. threshold .. "%!")
    end
end

package.loaded["trial.as.boss.OlmsEncounter"] = OlmsEncounter
return OlmsEncounter
