local Location = require("core.Location")
local Timer    = require("lib.Timer")

-- ── CombatAlerts helpers ──────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

-- ── Ability IDs (from AsylumTracker / AsylumPriorityTarget) ───────────────
-- Olms
local OLMS_STORM_THE_HEAVENS  = 98535  -- Kite! ~41 s repeat
local OLMS_TRIAL_BY_FIRE      = 98582  -- Below 25% HP, ~27 s repeat
local OLMS_SCALDING_ROAR      = 98683  -- Steam breath, ~28 s repeat
local OLMS_GUSTS_OF_STEAM     = 98868  -- Jumps at 90/75/50/25%
local OLMS_EXHAUSTIVE_CHARGES = 95482  -- ~12 s repeat
-- Protector
local STATIC_SHIELD           = 96010  -- Protector gives Olms a shield
-- Llothis
local LLOTHIS_DEFILING_BLAST   = 95545  -- Cone attack — target name alert
local LLOTHIS_OPPRESSIVE_BOLTS = 95585  -- Interrupt!
-- Felms
local FELMS_TELEPORT_STRIKE   = 99138  -- Jump — target name alert
-- Mini-boss state
local DORMANT                 = 99990  -- GAINED = mini sleeps; FADED = mini wakes
local BOSS_EVENT              = 10298  -- EFFECT_GAINED marks exact mini-boss spawn time

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local STORM_CD    = 41
local FIRE_CD     = 27
local STEAM_CD    = 28
local CHARGES_CD  = 12
local BLAST_CD    = 21   -- Llothis Defiling Blast
local BOLTS_CD    = 12   -- Llothis Oppressive Bolts (interrupt)
local JUMP_CD     = 21   -- Felms Teleport Strike
local DORMANT_CD  = 45   -- Mini-boss dormant phase duration
local SPAWN_DELAY = 12   -- Seconds after BOSS_EVENT before first mini ability

-- ── Jump milestone thresholds (%) ────────────────────────────────────────
local JUMP_THRESHOLDS = { 90, 75, 50, 25 }

local OlmsEncounter = {
    id           = 1,
    key          = "olms",
    nameAliases  = { "Saint Olms the Just" },
    -- hmHealthThreshold: TBD — verify in-game on vet HM
    hmHealthThreshold = 0,
    -- Location: entire arena — name-based detection is used instead.
    location = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
-- Olms
OlmsEncounter.stormTimer   = Timer.new(STORM_CD)
OlmsEncounter.steamTimer   = Timer.new(STEAM_CD)
OlmsEncounter.chargesTimer = Timer.new(CHARGES_CD)
OlmsEncounter.fireTimer    = Timer.new(FIRE_CD)
-- Llothis
OlmsEncounter.blastTimer   = Timer.new(BLAST_CD)
OlmsEncounter.boltsTimer   = Timer.new(BOLTS_CD)

-- ── State ─────────────────────────────────────────────────────────────────
OlmsEncounter.llothisActive    = false
OlmsEncounter.llothisSpawnTime = nil    -- os.time() at BOSS_EVENT for Llothis
OlmsEncounter.felmsActive      = false
OlmsEncounter.felmsSpawnTime   = nil    -- os.time() at BOSS_EVENT for Felms
OlmsEncounter.protectorUp      = false
OlmsEncounter.nextJumpThreshold = 1
-- CA cast-bar tracking: [unitId] → cid
OlmsEncounter.alertList = {}

function OlmsEncounter:reset()
    self.stormTimer:reset()
    self.steamTimer:reset()
    self.chargesTimer:reset()
    self.fireTimer:reset()
    self.blastTimer:clear()
    self.boltsTimer:clear()
    self.llothisActive      = false
    self.llothisSpawnTime   = nil
    self.felmsActive        = false
    self.felmsSpawnTime     = nil
    self.protectorUp        = false
    self.nextJumpThreshold  = 1
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
end

-- ── Timer seeding helpers ─────────────────────────────────────────────────
-- Seeds a timer pair accounting for SPAWN_DELAY elapsed since BOSS_EVENT.
-- If spawnTime is nil (no BOSS_EVENT seen), seeds with 0 (fires immediately).
local function seedMiniTimers(t1, t2, spawnTime)
    local seed = 0
    if spawnTime then
        seed = math.max(0, SPAWN_DELAY - (os.time() - spawnTime))
    end
    t1:reset(seed > 0 and seed or t1.duration)
    t2:reset(seed > 0 and seed or t2.duration)
end

-- ── Combat events ─────────────────────────────────────────────────────────
function OlmsEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    -- ── Olms ──────────────────────────────────────────────────────────────
    if abilityId == OLMS_STORM_THE_HEAVENS and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Kite! (Storm the Heavens)")
        caAlert(nil, "KITE!", 0xFF4400FF, SOUNDS.NONE, 3000)
        self.stormTimer:reset()

    elseif abilityId == OLMS_SCALDING_ROAR and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Steam Breath! Move!")
        local dur = select(1, GetAbilityCastInfo(OLMS_SCALDING_ROAR)) or 0
        if dur <= 0 then dur = 2000 end
        local cid = caAlertCast(abilityId, "Steam Breath!", dur,
            { -3, 0, false, { 0.8, 0.4, 0, 0.4 }, { 0.8, 0.4, 0, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
        self.steamTimer:reset()

    elseif abilityId == OLMS_EXHAUSTIVE_CHARGES and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Charges!")
        self.chargesTimer:reset()

    elseif abilityId == OLMS_TRIAL_BY_FIRE and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Trial by Fire!")
        self.fireTimer:reset()

    elseif abilityId == OLMS_GUSTS_OF_STEAM and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Jump! Dodge!")
        if self.nextJumpThreshold <= #JUMP_THRESHOLDS then
            self.nextJumpThreshold = self.nextJumpThreshold + 1
        end

    -- ── Llothis: spawn detection ──────────────────────────────────────────
    -- BOSS_EVENT (10298) fires when a mini-boss materialises. unitName identifies
    -- which mini-boss received the effect. We record the timestamp and seed the
    -- ability timers with the SPAWN_DELAY offset so the first timer expires at
    -- roughly the same time as Llothis's first cast.
    elseif abilityId == BOSS_EVENT and result == ACTION_RESULT_EFFECT_GAINED
           and unitName and unitName:find("Llothis") then
        self.llothisSpawnTime = os.time()
        self.llothisActive    = true
        seedMiniTimers(self.blastTimer, self.boltsTimer, self.llothisSpawnTime)

    -- ── Llothis: combat abilities ─────────────────────────────────────────
    elseif abilityId == LLOTHIS_DEFILING_BLAST and result == ACTION_RESULT_BEGIN then
        -- Cone attack: alert with the targeted player's name so the group
        -- knows who to move away from.
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Blast! → " .. target)
        local dur = select(1, GetAbilityCastInfo(LLOTHIS_DEFILING_BLAST)) or 0
        if dur <= 0 then dur = 1500 end
        local cid = caAlertCast(abilityId, "Blast → " .. target, dur,
            { -3, 0, false, { 0.6, 0, 0.8, 0.4 }, { 0.6, 0, 0.8, 0.8 } })
        if cid and unitId then self.alertList[unitId] = cid end
        self.blastTimer:reset()

    elseif abilityId == LLOTHIS_OPPRESSIVE_BOLTS and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Llothis!")
        caAlert(nil, "Interrupt!", 0xFF0000FF, SOUNDS.NONE, 2000)
        self.boltsTimer:reset()

    -- ── AS-4: Felms mechanics ─────────────────────────────────────────────
    -- (implemented in AS-4)

    -- ── AS-5: Protector / Static Shield ──────────────────────────────────
    -- (implemented in AS-5)
    end
end

-- ── Effect changed ────────────────────────────────────────────────────────
function OlmsEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)

    if abilityId ~= DORMANT then return end

    -- ── Llothis dormant state ─────────────────────────────────────────────
    if unitName and unitName:find("Llothis") then
        if changeType == EFFECT_RESULT_GAINED then
            -- Llothis goes to sleep
            self.llothisActive = false
            self.blastTimer:clear()
            self.boltsTimer:clear()
        elseif changeType == EFFECT_RESULT_FADED then
            -- Llothis wakes up; re-seed timers from original spawn timestamp.
            -- If BOSS_EVENT fired again on this wake, spawnTime is already fresh;
            -- otherwise seed = 0 and the timers start immediately.
            self.llothisActive = true
            seedMiniTimers(self.blastTimer, self.boltsTimer, self.llothisSpawnTime)
        end
        return
    end

    -- ── Felms dormant state ───────────────────────────────────────────────
    -- (AS-4: implemented in AS-4)
end

-- ── 200 ms display update ─────────────────────────────────────────────────
function OlmsEncounter:onUpdate(context, alerts)
    -- Lines 1-4: Olms timers
    local t1 = self.stormTimer:remaining()
    local t2 = self.steamTimer:remaining()
    local t3 = self.chargesTimer:remaining()
    alerts:showInfo(1, "Storm:   " .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or "ready"))
    alerts:showInfo(2, "Steam:   " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
    alerts:showInfo(3, "Charges: " .. (t3 > 0 and ZO_FormatCountdownTimer(t3) or "ready"))
    local t4 = self.fireTimer:remaining()
    alerts:showInfo(4, t4 > 0 and ("Fire:    " .. ZO_FormatCountdownTimer(t4)) or "")

    -- Line 5: Llothis status
    if self.llothisSpawnTime == nil then
        -- Llothis has not yet spawned this pull
        alerts:showInfo(5, "")
    elseif not self.llothisActive then
        alerts:showInfo(5, "Llothis: DORMANT")
    else
        local t5 = self.blastTimer:remaining()
        alerts:showInfo(5, "Blast:   " .. (t5 > 0 and ZO_FormatCountdownTimer(t5) or "ready"))
    end

    -- Line 6: Llothis interrupt timer (hidden while dormant)
    if self.llothisActive then
        local t6 = self.boltsTimer:remaining()
        alerts:showInfo(6, "Bolts:   " .. (t6 > 0 and ZO_FormatCountdownTimer(t6) or "!INTERRUPT"))
    else
        alerts:showInfo(6, "")
    end

    -- Line 7: reserved for Felms (AS-4)
end

-- ── HP milestone pre-warning ──────────────────────────────────────────────
function OlmsEncounter:onPowerUpdate(context, healthPercent, alerts)
    if self.nextJumpThreshold > #JUMP_THRESHOLDS then return end
    local threshold = JUMP_THRESHOLDS[self.nextJumpThreshold]
    if healthPercent <= threshold + 3 and healthPercent > threshold then
        alerts:showInfo(1, "Jump at " .. threshold .. "%!")
    end
end

return OlmsEncounter
