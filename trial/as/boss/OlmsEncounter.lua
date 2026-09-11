local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Settings        = require("core.Settings")
local Colors          = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────────
local OLMS_STORM_THE_HEAVENS  = 98535
local OLMS_TRIAL_BY_FIRE      = 98582
local OLMS_SCALDING_ROAR      = 98683
local OLMS_GUSTS_OF_STEAM     = 98868
local OLMS_EXHAUSTIVE_CHARGES = 95482
local STATIC_SHIELD           = 96010
local LLOTHIS_DEFILING_BLAST   = 95545
local LLOTHIS_OPPRESSIVE_BOLTS = 95585
local FELMS_TELEPORT_STRIKE   = 99138
local DORMANT                 = 99990
local BOSS_EVENT              = 10298

-- ── Timer durations (seconds) ─────────────────────────────────────────────────
local STORM_CD    = 41
local FIRE_CD     = 27
local STEAM_CD    = 28
local CHARGES_CD  = 12
local BLAST_CD    = 21
local BOLTS_CD    = 12
local JUMP_CD     = 21
local SPAWN_DELAY = 12
local JUMP_THRESHOLDS = { 90, 75, 50, 25 }

local FALLBACK_ROAR_DUR   = 2000
local FALLBACK_BLAST_DUR  = 1500
local FALLBACK_STRIKE_DUR = 1000

local OlmsEncounter = {}
OlmsEncounter.__index = OlmsEncounter

OlmsEncounter.key               = "olms"
OlmsEncounter.nameAliases       = { "Saint Olms the Just" }
OlmsEncounter.hmHealthThreshold = math.huge

OlmsEncounter.stateSchema = {
    stormTimer         = function() return Timer.new(STORM_CD) end,
    steamTimer         = function() return Timer.new(STEAM_CD) end,
    chargesTimer       = function() return Timer.new(CHARGES_CD) end,
    fireTimer          = function() return Timer.new(FIRE_CD) end,
    blastTimer         = function() return Timer.new(BLAST_CD) end,
    boltsTimer         = function() return Timer.new(BOLTS_CD) end,
    jumpTimer          = function() return Timer.new(JUMP_CD) end,
    llothisActive      = false,
    felmsActive        = false,
    protectorUp        = false,
    nextJumpThreshold  = 1,
    stormPreWarned     = false,
    alertList          = function() return {} end,
}

function OlmsEncounter.new()
    return BossBase.fromSchema(OlmsEncounter)
end

function OlmsEncounter:onLeave(context)
    self:cleanupAlertList()
end

function OlmsEncounter:onWipe(context, alerts)
    self:cleanupAlertList()
    self.stormTimer:clear()
    self.steamTimer:clear()
    self.chargesTimer:clear()
    self.fireTimer:clear()
    self.blastTimer:clear()
    self.boltsTimer:clear()
    self.jumpTimer:clear()
    self.llothisActive     = false
    self.felmsActive       = false
    self.protectorUp       = false
    self.nextJumpThreshold = 1
    self.stormPreWarned    = false
    self.llothisSpawnGs    = nil
    self.felmsSpawnGs      = nil
end

-- ── Timer seeding helper ─────────────────────────────────────────────────────
local function seedTimer(t, referenceGs)
    local seed = 0
    if referenceGs then
        seed = math.max(0, SPAWN_DELAY - (GetGameTimeMilliseconds() / 1000 - referenceGs))
    end
    t:reset(seed > 0 and seed or t.duration)
end

-- ── Handlers: beginCast ─────────────────────────────────────────────────────

local function handleStormTheHeavens(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("as_olms_kite_storm"))
    CA.alert(nil, "KITE!", 0xFF4400FF, SOUNDS.NONE, 3000)
    boss.stormTimer:reset()
    boss.stormPreWarned = false
end

local function handleScaldingRoar(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, ...)
    alerts:showAction(Lang.t("as_olms_steam_breath"))
    local dur = CastDur.get(OLMS_SCALDING_ROAR, FALLBACK_ROAR_DUR)
    local cid = CA.ranged(abilityId, Lang.t("as_olms_steam_breath"), dur, Colors.FIRE)
    if cid and unitId then boss.alertList[unitId] = cid end
    boss.steamTimer:reset()
end

local function handleExhaustiveCharges(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("as_olms_charges"))
    boss.chargesTimer:reset()
end

local function handleTrialByFire(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("as_olms_trial_by_fire"))
    boss.fireTimer:reset()
end

local function handleGustsOfSteam(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("as_olms_jump_dodge"))
    if boss.nextJumpThreshold <= #JUMP_THRESHOLDS then
        boss.nextJumpThreshold = boss.nextJumpThreshold + 1
    end
end

local function handleDefilingBlast(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("as_olms_blast_target", target))
    local dur = CastDur.get(LLOTHIS_DEFILING_BLAST, FALLBACK_BLAST_DUR)
    local cid = CA.ranged(abilityId, Lang.t("as_olms_blast_bar", target), dur, Colors.VOID)
    if cid and unitId then boss.alertList[unitId] = cid end
    boss.blastTimer:reset()
end

local function handleOppressiveBolts(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("as_olms_interrupt_llothis"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2000)
    boss.boltsTimer:reset()
end

local function handleTeleportStrike(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("as_olms_strike_target", target))
    local dur = CastDur.get(FELMS_TELEPORT_STRIKE, FALLBACK_STRIKE_DUR)
    local cid = CA.ranged(abilityId, Lang.t("as_olms_strike_bar", target), dur, Colors.TEAL)
    if cid and unitId then boss.alertList[unitId] = cid end
    boss.jumpTimer:reset()
end

-- ── Handlers: combatEvent.other ─────────────────────────────────────────────
-- BOSS_EVENT sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
local function handleBossEvent(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if unitName and unitName:find("Llothis") then
        boss.llothisSpawnGs = GetGameTimeMilliseconds() / 1000
        boss.llothisActive  = true
        seedTimer(boss.blastTimer, boss.llothisSpawnGs)
        seedTimer(boss.boltsTimer, boss.llothisSpawnGs)
    elseif unitName and unitName:find("Felms") then
        boss.felmsSpawnGs = GetGameTimeMilliseconds() / 1000
        boss.felmsActive  = true
        seedTimer(boss.jumpTimer, boss.felmsSpawnGs)
    end
end

-- ── Handlers: effectChanged -------------------------------------------------
-- effectChanged sig: (boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)

local function handleDormantGained(boss, ctx, alerts, abilityId, unitName, ...)
    if unitName and unitName:find("Llothis") then
        boss.llothisActive = false
        boss.blastTimer:clear()
        boss.boltsTimer:clear()
    elseif unitName and unitName:find("Felms") then
        boss.felmsActive = false
        boss.jumpTimer:clear()
    end
end

local function handleDormantFaded(boss, ctx, alerts, abilityId, unitName, ...)
    if unitName and unitName:find("Llothis") then
        boss.llothisActive = true
        local wakeGs = GetGameTimeMilliseconds() / 1000
        seedTimer(boss.blastTimer, wakeGs)
        seedTimer(boss.boltsTimer, wakeGs)
    elseif unitName and unitName:find("Felms") then
        boss.felmsActive = true
        local wakeGs = GetGameTimeMilliseconds() / 1000
        seedTimer(boss.jumpTimer, wakeGs)
    end
end

local function handleStaticShieldGained(boss, ctx, alerts, abilityId, ...)
    boss.protectorUp = true
    alerts:showAction(Lang.t("as_olms_kill_protector"))
    CA.alert(nil, Lang.t("as_olms_kill_protector"), 0xFFCC00FF, SOUNDS.NONE, 4000)
end

local function handleStaticShieldFaded(boss, ctx, alerts, abilityId, ...)
    boss.protectorUp = false
    alerts:showAction(Lang.t("as_olms_shield_down"))
end

-- ── Event tables ─────────────────────────────────────────────────────────────

local _beginCastEntry = {
    [OLMS_STORM_THE_HEAVENS]  = { type = AlertTypes.CUSTOM, fn = handleStormTheHeavens },
    [OLMS_SCALDING_ROAR]      = { type = AlertTypes.CUSTOM, fn = handleScaldingRoar },
    [OLMS_EXHAUSTIVE_CHARGES] = { type = AlertTypes.CUSTOM, fn = handleExhaustiveCharges },
    [OLMS_TRIAL_BY_FIRE]      = { type = AlertTypes.CUSTOM, fn = handleTrialByFire },
    [OLMS_GUSTS_OF_STEAM]     = { type = AlertTypes.CUSTOM, fn = handleGustsOfSteam },
    [LLOTHIS_DEFILING_BLAST]   = { type = AlertTypes.CUSTOM, fn = handleDefilingBlast },
    [LLOTHIS_OPPRESSIVE_BOLTS] = { type = AlertTypes.CUSTOM, fn = handleOppressiveBolts },
    [FELMS_TELEPORT_STRIKE]   = { type = AlertTypes.CUSTOM, fn = handleTeleportStrike },
}

local _combatOtherEntry = {
    [BOSS_EVENT] = { type = AlertTypes.CUSTOM, fn = handleBossEvent },
}

local _effectGainedEntry = {
    [DORMANT]       = { type = AlertTypes.CUSTOM, fn = handleDormantGained },
    [STATIC_SHIELD] = { type = AlertTypes.CUSTOM, fn = handleStaticShieldGained },
}

local _effectFadedEntry = {
    [DORMANT]       = { type = AlertTypes.CUSTOM, fn = handleDormantFaded },
    [STATIC_SHIELD] = { type = AlertTypes.CUSTOM, fn = handleStaticShieldFaded },
}

OlmsEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- ── Tracker-row renderers ─────────────────────────────────────────────────────

local function showStormLine(self, alerts)
    if self.protectorUp then
        alerts:setRow(1, Fmt.c(Fmt.YELLOW, Lang.t("as_olms_protector_active")), nil)
        return
    end
    local t = self.stormTimer:remaining()
    if t > 0 and t <= 6 and not self.stormPreWarned then
        self.stormPreWarned = true
        CA.alert(nil, "Storm soon!", 0xFF6600FF, SOUNDS.NONE, 3000)
    elseif t > 6 then
        self.stormPreWarned = false
    end
    if t > 0 then
        alerts:setRow(1, Lang.t("as_olms_storm_label"), t)
    else
        alerts:setRow(1, Lang.t("as_olms_storm_label") .. " " .. Lang.t("common_ready"), nil)
    end
end

local function showOlmsLines(self, alerts)
    local t2 = self.steamTimer:remaining()
    local t3 = self.chargesTimer:remaining()
    local t4 = self.fireTimer:remaining()
    if t2 > 0 then
        alerts:setRow(2, Lang.t("as_olms_steam_label"), t2)
    else
        alerts:setRow(2, Lang.t("as_olms_steam_label") .. " " .. Lang.t("common_ready"), nil)
    end
    if t3 > 0 then
        alerts:setRow(3, Lang.t("as_olms_charges_label"), t3)
    else
        alerts:setRow(3, Lang.t("as_olms_charges_label") .. " " .. Lang.t("common_ready"), nil)
    end
    if t4 > 0 then
        alerts:setRow(4, Lang.t("as_olms_fire_label"), t4)
    else
        alerts:clearRow(4)
    end
end

local function showLlothisLine(self, alerts)
    if self.llothisSpawnGs == nil then
        alerts:clearRow(5)
    elseif not self.llothisActive then
        alerts:setRow(5, Lang.t("as_olms_llothis_dormant"), nil)
    else
        local t = self.blastTimer:remaining()
        if t > 0 then
            alerts:setRow(5, Lang.t("as_olms_blast_label"), t)
        else
            alerts:setRow(5, Lang.t("as_olms_blast_label") .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

local function showBoltsLine(self, alerts)
    if self.llothisActive then
        local t = self.boltsTimer:remaining()
        if t > 0 then
            alerts:setRow(6, Lang.t("as_olms_bolts_label"), t)
        else
            alerts:setRow(6, Lang.t("as_olms_bolts_label") .. " " .. Lang.t("common_interrupt"), nil)
        end
    else
        alerts:clearRow(6)
    end
end

local function showFelmsLine(self, alerts)
    if self.felmsSpawnGs == nil then
        alerts:clearRow(7)
    elseif not self.felmsActive then
        alerts:setRow(7, Lang.t("as_olms_felms_dormant"), nil)
    else
        local t = self.jumpTimer:remaining()
        if t > 0 then
            alerts:setRow(7, Lang.t("as_olms_strike_label"), t)
        else
            alerts:setRow(7, Lang.t("as_olms_strike_label") .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

function OlmsEncounter:onUpdate(context, alerts)
    showStormLine(self, alerts)
    showOlmsLines(self, alerts)
    showLlothisLine(self, alerts)
    showBoltsLine(self, alerts)
    showFelmsLine(self, alerts)
end

function OlmsEncounter:onPowerUpdate(context, healthPercent, alerts)
    if not Settings.trial("as").showPercent then return end
    if self.nextJumpThreshold > #JUMP_THRESHOLDS then return end
    local threshold = JUMP_THRESHOLDS[self.nextJumpThreshold]
    if healthPercent <= threshold + 3 and healthPercent > threshold then
        alerts:setRow(1, Lang.t("as_olms_jump_at", tostring(threshold)), nil)
    end
end

EventDispatcher.build(OlmsEncounter)

package.loaded["trial.as.boss.OlmsEncounter"] = OlmsEncounter
return OlmsEncounter
