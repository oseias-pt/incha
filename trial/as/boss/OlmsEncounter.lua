local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local SubBoss         = require("lib.SubBoss")
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

-- ── Module-level string constants (P6: avoid per-tick Lang.t allocations) ─────
local _STR_PROTECTOR_ACTIVE = Fmt.c(Fmt.YELLOW, Lang.t("as_olms_protector_active"))
local _STR_STORM            = Lang.t("as_olms_storm_label")
local _STR_STORM_READY      = Lang.t("as_olms_storm_label") .. " " .. Lang.t("common_ready")
local _STR_STEAM            = Lang.t("as_olms_steam_label")
local _STR_STEAM_READY      = Lang.t("as_olms_steam_label") .. " " .. Lang.t("common_ready")
local _STR_CHARGES          = Lang.t("as_olms_charges_label")
local _STR_CHARGES_READY    = Lang.t("as_olms_charges_label") .. " " .. Lang.t("common_ready")
local _STR_FIRE             = Lang.t("as_olms_fire_label")
local _STR_LLOTHIS_DORMANT  = Lang.t("as_olms_llothis_dormant")
local _STR_BLAST            = Lang.t("as_olms_blast_label")
local _STR_BLAST_READY      = Lang.t("as_olms_blast_label") .. " " .. Lang.t("common_ready")
local _STR_BOLTS            = Lang.t("as_olms_bolts_label")
local _STR_BOLTS_DUE        = Lang.t("as_olms_bolts_label") .. " " .. Lang.t("common_interrupt")
local _STR_FELMS_DORMANT    = Lang.t("as_olms_felms_dormant")
local _STR_STRIKE           = Lang.t("as_olms_strike_label")
local _STR_STRIKE_READY     = Lang.t("as_olms_strike_label") .. " " .. Lang.t("common_ready")
local _STR_STORM_SOON       = Lang.t("as_olms_storm_soon")
-- "Jump at N%!" per threshold index; built once since JUMP_THRESHOLDS is constant.
local _STR_JUMP_AT = {}
for i, threshold in ipairs(JUMP_THRESHOLDS) do
    _STR_JUMP_AT[i] = Lang.t("as_olms_jump_at", tostring(threshold))
end

local OlmsEncounter = {}
OlmsEncounter.__index = OlmsEncounter
setmetatable(OlmsEncounter, {__index = BossBase})

OlmsEncounter.key               = "olms"
OlmsEncounter.nameAliases       = { "Saint Olms the Just" }
-- math.huge = always NORMAL difficulty; HM pool not yet measured in-game.
OlmsEncounter.hmHealthThreshold = math.huge

-- P2 (SubBoss): Llothis and Felms are sub-bosses with their own timers and
-- active/spawnGs state.  BossBase.resetSchema re-creates them fresh on wipe,
-- making onWipe a two-liner.
OlmsEncounter.stateSchema = {
    stormTimer        = function() return Timer.new(STORM_CD) end,
    steamTimer        = function() return Timer.new(STEAM_CD) end,
    chargesTimer      = function() return Timer.new(CHARGES_CD) end,
    fireTimer         = function() return Timer.new(FIRE_CD) end,
    protectorUp       = false,
    nextJumpThreshold = 1,
    stormPreWarned    = false,
    -- Row-1 override while the boss sits inside a jump pre-warn window
    -- (threshold .. threshold+3 %).  Set by onPowerUpdate, drawn by
    -- showStormLine, so only one writer touches row 1.
    jumpWarnText      = false,
    alertList         = function() return {} end,
    llothis           = function()
        return SubBoss.new({ blast = Timer.new(BLAST_CD), bolts = Timer.new(BOLTS_CD) })
    end,
    felms             = function()
        return SubBoss.new({ jump = Timer.new(JUMP_CD) })
    end,
}

function OlmsEncounter.new()
    return BossBase.fromSchema(OlmsEncounter)
end

function OlmsEncounter:onLeave(context)
    self:cleanupAlertList()
end

function OlmsEncounter:onWipe(context, alerts)
    self:cleanupAlertList()
    BossBase.resetSchema(self, OlmsEncounter)
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
    boss.llothis.blast:reset()
end

local function handleOppressiveBolts(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("as_olms_interrupt_llothis"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2000)
    boss.llothis.bolts:reset()
end

local function handleTeleportStrike(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("as_olms_strike_target", target))
    local dur = CastDur.get(FELMS_TELEPORT_STRIKE, FALLBACK_STRIKE_DUR)
    local cid = CA.ranged(abilityId, Lang.t("as_olms_strike_bar", target), dur, Colors.TEAL)
    if cid and unitId then boss.alertList[unitId] = cid end
    boss.felms.jump:reset()
end

-- ── Handlers: combatEvent.other ─────────────────────────────────────────────
-- BOSS_EVENT sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
local function handleBossEvent(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if unitName and unitName:find("Llothis") then
        local spawnGs = GetGameTimeMilliseconds() / 1000
        boss.llothis:activate(spawnGs)
        seedTimer(boss.llothis.blast, spawnGs)
        seedTimer(boss.llothis.bolts, spawnGs)
    elseif unitName and unitName:find("Felms") then
        local spawnGs = GetGameTimeMilliseconds() / 1000
        boss.felms:activate(spawnGs)
        seedTimer(boss.felms.jump, spawnGs)
    end
end

-- ── Handlers: effectChanged -------------------------------------------------
-- effectChanged sig: (boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)

local function handleDormantGained(boss, ctx, alerts, abilityId, unitName, ...)
    if unitName and unitName:find("Llothis") then
        boss.llothis:deactivate()
        boss.llothis.blast:clear()
        boss.llothis.bolts:clear()
    elseif unitName and unitName:find("Felms") then
        boss.felms:deactivate()
        boss.felms.jump:clear()
    end
end

local function handleDormantFaded(boss, ctx, alerts, abilityId, unitName, ...)
    if unitName and unitName:find("Llothis") then
        local wakeGs = GetGameTimeMilliseconds() / 1000
        boss.llothis:activate(wakeGs)
        seedTimer(boss.llothis.blast, wakeGs)
        seedTimer(boss.llothis.bolts, wakeGs)
    elseif unitName and unitName:find("Felms") then
        local wakeGs = GetGameTimeMilliseconds() / 1000
        boss.felms:activate(wakeGs)
        seedTimer(boss.felms.jump, wakeGs)
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

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

OlmsEncounter.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- ── Tracker-row renderers ─────────────────────────────────────────────────────

local function showStormLine(self, alerts, now)
    if self.protectorUp then
        alerts:setRow(1, _STR_PROTECTOR_ACTIVE, nil)
        return
    end
    if self.jumpWarnText then
        -- Jump pre-warn takes the slot; onPowerUpdate clears it when the
        -- boss leaves the window or the jump fires.
        alerts:setRow(1, self.jumpWarnText, nil)
        return
    end
    local t = self.stormTimer:remainingAt(now)
    if t > 0 and t <= 6 and not self.stormPreWarned then
        self.stormPreWarned = true
        CA.alert(nil, _STR_STORM_SOON, 0xFF6600FF, SOUNDS.NONE, 3000)
    elseif t > 6 then
        self.stormPreWarned = false
    end
    if t > 0 then
        alerts:setRow(1, _STR_STORM, t)
    else
        alerts:setRow(1, _STR_STORM_READY, nil)
    end
end

local function showOlmsLines(self, alerts, now)
    local t2 = self.steamTimer:remainingAt(now)
    local t3 = self.chargesTimer:remainingAt(now)
    local t4 = self.fireTimer:remainingAt(now)
    alerts:setRow(2, t2 > 0 and _STR_STEAM or _STR_STEAM_READY, t2 > 0 and t2 or nil)
    alerts:setRow(3, t3 > 0 and _STR_CHARGES or _STR_CHARGES_READY, t3 > 0 and t3 or nil)
    if t4 > 0 then
        alerts:setRow(4, _STR_FIRE, t4)
    else
        alerts:clearRow(4)
    end
end

local function showLlothisLine(self, alerts, now)
    if self.llothis.spawnGs == nil then
        alerts:clearRow(5)
    elseif not self.llothis.active then
        alerts:setRow(5, _STR_LLOTHIS_DORMANT, nil)
    else
        local t = self.llothis.blast:remainingAt(now)
        alerts:setRow(5, t > 0 and _STR_BLAST or _STR_BLAST_READY, t > 0 and t or nil)
    end
end

local function showBoltsLine(self, alerts, now)
    if self.llothis.active then
        local t = self.llothis.bolts:remainingAt(now)
        alerts:setRow(6, t > 0 and _STR_BOLTS or _STR_BOLTS_DUE, t > 0 and t or nil)
    else
        alerts:clearRow(6)
    end
end

local function showFelmsLine(self, alerts, now)
    if self.felms.spawnGs == nil then
        alerts:clearRow(7)
    elseif not self.felms.active then
        alerts:setRow(7, _STR_FELMS_DORMANT, nil)
    else
        local t = self.felms.jump:remainingAt(now)
        alerts:setRow(7, t > 0 and _STR_STRIKE or _STR_STRIKE_READY, t > 0 and t or nil)
    end
end

function OlmsEncounter:onUpdate(context, alerts)
    -- One GetGameTimeMilliseconds() per tick shared by all seven timers.
    local now = GetGameTimeMilliseconds() / 1000
    showStormLine(self, alerts, now)
    showOlmsLines(self, alerts, now)
    showLlothisLine(self, alerts, now)
    showBoltsLine(self, alerts, now)
    showFelmsLine(self, alerts, now)
end

-- Jump pre-warn: while the boss sits in the (threshold, threshold+3] window
-- the pre-built "Jump at N%!" string is handed to showStormLine, which owns
-- row 1.  Only the flag changes here; no string is built per power tick.
function OlmsEncounter:onPowerUpdate(context, healthPercent, alerts)
    if not Settings.trial("as").showPercent then
        self.jumpWarnText = false
        return
    end
    local idx = self.nextJumpThreshold
    if idx > #JUMP_THRESHOLDS then
        self.jumpWarnText = false
        return
    end
    local threshold = JUMP_THRESHOLDS[idx]
    if healthPercent <= threshold + 3 and healthPercent > threshold then
        self.jumpWarnText = _STR_JUMP_AT[idx]
    else
        self.jumpWarnText = false
    end
end

EventDispatcher.build(OlmsEncounter)

package.loaded["trial.as.boss.OlmsEncounter"] = OlmsEncounter
return OlmsEncounter
