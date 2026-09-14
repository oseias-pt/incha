local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local SubBoss         = require("lib.SubBoss")
local CA              = require("external-api.CombatAlerts")
local MechanicIcons   = require("external-api.MechanicIcons")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Settings        = require("core.Settings")
local Lang            = require("core.Lang")
local Colors          = require("core.Colors")

-- -- Siroria ---------------------------------------------------------------
local SIRO_HA          = 104755
local SIRO_JUMP        = 106601
local SIRO_BANNER      = 104902
local SIRO_DARK_TALONS = 105765
local SIRO_FLARE       = 103531
local SIRO_FLARE_EXEC  = 110431

-- -- Relequen --------------------------------------------------------------
local RELE_HA          = 105780
local RELE_JUMP        = 105796
local RELE_DIRECT_CURR = 105380
local RELE_JOLT        = 106614
local RELE_OVERLOAD_1  = 103555
local RELE_OVERLOAD_2  = 87346

-- -- Galenwe ---------------------------------------------------------------
local GALE_HA          = 106375
local GALE_JUMP        = 106682
local GALE_GLACIAL     = 106405
local GALE_DONUT       = 106378
local GALE_HOARFROST_C = 105151
local GALE_HOARFROST_C2= 110466
local GALE_HOARFROST   = 103695
local GALE_HOARFROST_2 = 110516
local GALE_HOARFROST_SY= 103697
local GALE_HOARFROST_S2= 110525
local GALE_COMET       = 106374
local GALE_COMET_2     = 106367

-- -- Environment / mini shared ---------------------------------------------
local RAZOR_THORNS     = 106656

-- -- Portal mechanics ------------------------------------------------------
local PORTAL_OPEN      = 103946
local PORTAL_CLOSE_1   = 104057
local PORTAL_CLOSE_2   = 104792
local PORTAL_RESET     = 105890
local PLAYER_EXIT      = 105218

-- -- Z'Maja abilities ------------------------------------------------------
local ZMAJA_JUMP       = 104564
local ZMAJA_HIDE_JUMP  = 104452
local CRUSHING_DARK_1  = 105152
local CRUSHING_DARK_2  = 105172
local CRUSHING_DARK_3  = 105239
local SHADOW_SPLASH    = 105123
local BANEFUL_MARK     = 107196
local ZMAJA_SHACKLE    = 107490
local ZMAJA_RESET_PORT = 107478

-- -- Malevolent Cores / misc -----------------------------------------------
local CORE_EXPOSED     = 103980
local CORE_PICKED_UP   = 103989
local CORE_MISSED      = 110202
local OLORIME_SPEAR    = 104018

-- -- Timer durations (seconds) ---------------------------------------------
local SIRO_JUMP_CD     = 23
local SIRO_BANNER_CD   = 45
local RELE_JUMP_CD     = 19
local RELE_BASH_CD     = 20
local RELE_JOLT_CD     = 15
local GALE_JUMP_CD     = 19
local GALE_BASH_CD     = 22
local GALE_DONUT_CD    = 22
local FLARE_WINDOW     = 7
local PORTAL_OPEN_DUR  = 75
local PORTAL_NEXT_CD   = 46

local FALLBACK_DARK_DUR  = 6000
local FALLBACK_HA_DUR    = 1500
local FALLBACK_SPLASH_DUR= 3000

local ZmajaEncounter = {}
ZmajaEncounter.__index = ZmajaEncounter
setmetatable(ZmajaEncounter, {__index = BossBase})

ZmajaEncounter.key               = "zmaja"
ZmajaEncounter.nameAliases       = { "Z'Maja" }
-- math.huge = always NORMAL difficulty; HM pool not yet measured in-game.
ZmajaEncounter.hmHealthThreshold = math.huge

-- -- P6: module-level string constants — avoid Lang.t calls in onUpdate (60 fps) --
local _STR_PORTAL_OPEN    = Lang.t("cr_zmaja_portal_open_label")
local _STR_PORTAL_CLOSING = Lang.t("cr_zmaja_portal_open_label") .. " " .. Lang.t("cr_zmaja_portal_closing")
local _STR_PORTAL_NEXT    = Lang.t("cr_zmaja_portal_next_label")
local _STR_EXECUTE_PHASE  = Lang.t("cr_zmaja_execute_phase")
local _STR_SPEARS_PREFIX  = Lang.t("cr_zmaja_spears_label")
local _STR_READY          = Lang.t("common_ready")
local _STR_BASH_DUE       = Lang.t("cr_zmaja_bash_due")

-- Mini-boss rows read "Siro: Jump 12s  Bnr 30s".  The two countdowns move
-- once per second, so each SubBoss carries the whole-second key the cached
-- string was built for (`_lineKey`) and the string itself (`_lineStr`);
-- onUpdate reformats only when the key changes, not on every 200 ms tick.
local function miniLine(sb, jumpTimer, secondTimer, now, langKey, secondReadyStr)
    local j = jumpTimer:remainingAt(now)
    local b = secondTimer:remainingAt(now)
    local jc = j > 0 and math.ceil(j) or 0
    local bc = b > 0 and math.ceil(b) or 0
    local key = jc * 1000 + bc
    if key ~= sb._lineKey then
        sb._lineKey = key
        sb._lineStr = Lang.t(langKey,
            jc > 0 and (jc .. "s") or _STR_READY,
            bc > 0 and (bc .. "s") or secondReadyStr)
    end
    return sb._lineStr
end

ZmajaEncounter.stateSchema = {
    -- P2: group each mini's state into a SubBoss — cleaner schema, trivial onWipe.
    -- Single-line SubBoss.new({}) keeps inner keys invisible to the duplicate scanner.
    siro            = function() return SubBoss.new({ jump = Timer.new(SIRO_JUMP_CD), banner = Timer.new(SIRO_BANNER_CD) }) end,
    rele            = function() return SubBoss.new({ jump = Timer.new(RELE_JUMP_CD), bash = Timer.new(RELE_BASH_CD), jolt = Timer.new(RELE_JOLT_CD) }) end,
    gale            = function() return SubBoss.new({ jump = Timer.new(GALE_JUMP_CD), bash = Timer.new(GALE_BASH_CD), donut = Timer.new(GALE_DONUT_CD) }) end,
    portalTimer     = function() return Timer.new(PORTAL_OPEN_DUR) end,
    portalNextTimer = function() return Timer.new(PORTAL_NEXT_CD) end,
    portalGroup     = 0,
    portalActive    = false,
    executePhase    = false,
    spearCount      = 0,
    alertList       = function() return {} end,
    coreAlert       = false,
    -- Row text caches, rebuilt by the handlers that change portalGroup /
    -- spearCount so onUpdate never formats.
    _groupStr       = false,
    _spearStr       = false,
}

function ZmajaEncounter.new()
    return BossBase.fromSchema(ZmajaEncounter)
end

function ZmajaEncounter:onLeave(context)
    self:cleanupAlertList()
end

-- -- Handlers: beginCast ----------------------------------------------------

-- Mini shackle: Z'Maja removes a mini from the fight → combatEvent.other
local function handleShackle(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if unitName and unitName:find("Siroria", 1, true) then
        boss.siro:reset()
    elseif unitName and unitName:find("Relequen", 1, true) then
        boss.rele:reset()
    elseif unitName and unitName:find("Galenwe", 1, true) then
        boss.gale:reset()
    end
end

-- Roaring Flare: base + execute variant, both → beginCast
local function handleSiroFlare(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.siro.active then boss.siro.active = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_siro_flare", target))
    local dur = CastDur.get(abilityId, math.floor(FLARE_WINDOW * 1000))
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_siro_flare", target), dur, Colors.FIRE)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleSiroHa(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.siro.active then boss.siro.active = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_siro_ha", target))
    local dur = CastDur.get(SIRO_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_siro_ha_bar"), dur, Colors.FIRE)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleSiroJump(boss, ctx, alerts, abilityId, ...)
    if not boss.siro.active then boss.siro.active = true end
    alerts:showAction(Lang.t("cr_zmaja_siro_jump"))
    boss.siro.jump:reset()
end

local function handleSiroBanner(boss, ctx, alerts, abilityId, ...)
    if not boss.siro.active then boss.siro.active = true end
    alerts:showAction(Lang.t("cr_zmaja_siro_banner"))
    boss.siro.banner:reset()
end

local function handleReleHa(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.rele.active then boss.rele.active = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_rele_ha", target))
    local dur = CastDur.get(RELE_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_rele_ha_bar"), dur, Colors.ICE)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleReleJump(boss, ctx, alerts, abilityId, ...)
    if not boss.rele.active then boss.rele.active = true end
    alerts:showAction(Lang.t("cr_zmaja_rele_jump"))
    boss.rele.jump:reset()
end

local function handleReleDirectCurr(boss, ctx, alerts, abilityId, ...)
    if not boss.rele.active then boss.rele.active = true end
    alerts:showAction(Lang.t("cr_zmaja_rele_interrupt"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
    boss.rele.bash:reset()
end

local function handleReleJolt(boss, ctx, alerts, abilityId, ...)
    if not boss.rele.active then boss.rele.active = true end
    alerts:showAction(Lang.t("cr_zmaja_rele_jolt"))
    boss.rele.jolt:reset()
end

local function handleGaleHa(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.gale.active then boss.gale.active = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_gale_ha", target))
    local dur = CastDur.get(GALE_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_gale_ha_bar"), dur, Colors.CYAN)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleGaleJump(boss, ctx, alerts, abilityId, ...)
    if not boss.gale.active then boss.gale.active = true end
    alerts:showAction(Lang.t("cr_zmaja_gale_jump"))
    boss.gale.jump:reset()
end

local function handleGaleGlacial(boss, ctx, alerts, abilityId, ...)
    if not boss.gale.active then boss.gale.active = true end
    alerts:showAction(Lang.t("cr_zmaja_gale_interrupt"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
    boss.gale.bash:reset()
end

local function handleGaleDonut(boss, ctx, alerts, abilityId, ...)
    if not boss.gale.active then boss.gale.active = true end
    alerts:showAction(Lang.t("cr_zmaja_gale_donut"))
    boss.gale.donut:reset()
end

-- Hoarfrost cast: marks Galenwe active (presence detection only; no alert)
local function handleGaleHoarfrostCast(boss, ctx, alerts, abilityId, ...)
    if not boss.gale.active then boss.gale.active = true end
end

local function handleCrushingDark(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_crushing_dark"))
    local dur = CastDur.get(abilityId, FALLBACK_DARK_DUR)
    CA.ranged(abilityId, Lang.t("cr_zmaja_crushing_kite"), dur, Colors.VOID)
end

-- OlorimeSpear: fires on BEGIN only (avoid double-count with EFFECT_GAINED)
local function handleOlorimeSpear(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    boss.spearCount = boss.spearCount + 1
    boss._spearStr  = _STR_SPEARS_PREFIX .. boss.spearCount
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_olorime_spear", target, boss.spearCount))
end

local function handlePortalClose(boss, ctx, alerts, abilityId, ...)
    boss.portalActive = false
    boss.portalTimer:clear()
    boss.portalNextTimer:reset(PORTAL_NEXT_CD)
    boss.coreAlert = false
end

local function handlePortalReset(boss, ctx, alerts, abilityId, ...)
    boss.portalGroup    = 0
    boss._groupStr      = false
    boss.portalActive   = false
    boss.portalTimer:clear()
    boss.portalNextTimer:clear()
    boss.coreAlert      = false
    alerts:showAction(Lang.t("cr_zmaja_portal_reset"))
end

local function handlePortalOpen(boss, ctx, alerts, abilityId, ...)
    boss.portalGroup  = boss.portalGroup + 1
    boss._groupStr    = Lang.t("cr_zmaja_shadow_group", boss.portalGroup)
    boss.portalActive = true
    boss.portalTimer:reset(PORTAL_OPEN_DUR)
    boss.portalNextTimer:clear()
    alerts:showHeader(Lang.t("cr_zmaja_shadow_realm", boss.portalGroup))
end

local function handleZmajaJump(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_jump"))
end

local function handleZmajaHideJump(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_hide_jump"))
end

local function handleShadowSplash(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_shadow_splash"))
    local dur = CastDur.get(abilityId, FALLBACK_SPLASH_DUR)
    CA.ranged(abilityId, Lang.t("cr_zmaja_shadow_splash_bar"), dur, Colors.VOID)
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
end

local function handleBanefulMark(boss, ctx, alerts, abilityId, ...)
    boss.executePhase = true
    alerts:showAction(Lang.t("cr_zmaja_baneful_mark"))
    CA.alert(nil, Lang.t("cr_zmaja_baneful_alert"), 0xFF4444FF, SOUNDS.NONE, 4000)
end

local function handleCoreExposed(boss, ctx, alerts, abilityId, ...)
    boss.coreAlert = Lang.t("cr_zmaja_core_out_alert")
    alerts:showAction(Lang.t("cr_zmaja_core_exposed"))
    CA.alert(nil, Lang.t("cr_zmaja_core_out_ca"), 0xFFDD00FF, SOUNDS.NONE, 4000)
end

local function handleCoreMissed(boss, ctx, alerts, abilityId, ...)
    boss.coreAlert = Lang.t("cr_zmaja_core_missed_alert")
    alerts:showAction(Lang.t("cr_zmaja_core_missed"))
    CA.alert(nil, Lang.t("cr_zmaja_core_missed_ca"), 0xFF4444FF, SOUNDS.NONE, 5000)
end

local function handleCorePickedUp(boss, ctx, alerts, abilityId, ...)
    boss.coreAlert = false
    alerts:showAction(Lang.t("cr_zmaja_core_picked"))
end

-- -- Handlers: combatEvent.other -------------------------------------------
-- combatEvent sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)

local function handleSiroDarkTalons(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.siro.active then boss.siro.active = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_siro_root"))
end

local function handleReleOverload1(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.rele.active then boss.rele.active = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_overload_in"))
end

local function handleReleOverload2(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.rele.active then boss.rele.active = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_overload_you"))
    CA.alert(nil, Lang.t("cr_zmaja_rele_bar_swap"), 0x3399FFFF, SOUNDS.NONE, 3000)
end

local function handleGaleHoarfrostSy(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.gale.active then boss.gale.active = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_drop_frost"))
    CA.alert(nil, Lang.t("cr_zmaja_gale_drop_alert"), 0x00EEEEff, SOUNDS.NONE, 2000)
end

local function handleGaleComet(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.gale.active then boss.gale.active = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_comet"))
    CA.alert(nil, Lang.t("cr_zmaja_gale_comet_alert"), 0x00AAFFFF, SOUNDS.NONE, 2500)
end

local function handleRazorThorns(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_creeper_root"))
end

-- -- Handlers: effectChanged -----------------------------------------------
-- effectChanged sig: (boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)

-- Hoarfrost debuff on player: OSI icon + alert (gained), remove icon (faded)
local function handleGaleHoarfrostGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not boss.gale.active then boss.gale.active = true end
    local dname = GetUnitDisplayName and GetUnitDisplayName(unitTag) or nil
    if dname and dname ~= "" and Settings.trial("cr").posIconsZmaja then
        MechanicIcons.set(dname, GetAbilityIcon(abilityId), Colors.CYAN)
    end
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("cr_zmaja_gale_frost_you"))
        CA.alert(nil, Lang.t("cr_zmaja_gale_frost_alert"), 0x00EEEEff, SOUNDS.NONE, 4000)
    elseif unitName and unitName ~= "" then
        alerts:showAction(Lang.t("cr_zmaja_gale_frost_tgt", unitName))
    end
end

local function handleGaleHoarfrostFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not boss.gale.active then boss.gale.active = true end
    local dname = GetUnitDisplayName and GetUnitDisplayName(unitTag) or nil
    if dname and dname ~= "" and Settings.trial("cr").posIconsZmaja then
        MechanicIcons.remove(dname)
    end
end

-- -- Event tables ------------------------------------------------------------

local _beginCastEntry = {
    [SIRO_HA]           = { type = AlertTypes.CUSTOM, fn = handleSiroHa },
    [SIRO_JUMP]         = { type = AlertTypes.CUSTOM, fn = handleSiroJump },
    [SIRO_BANNER]       = { type = AlertTypes.CUSTOM, fn = handleSiroBanner },
    [SIRO_FLARE]        = { type = AlertTypes.CUSTOM, fn = handleSiroFlare },
    [SIRO_FLARE_EXEC]   = { type = AlertTypes.CUSTOM, fn = handleSiroFlare },
    [RELE_HA]           = { type = AlertTypes.CUSTOM, fn = handleReleHa },
    [RELE_JUMP]         = { type = AlertTypes.CUSTOM, fn = handleReleJump },
    [RELE_DIRECT_CURR]  = { type = AlertTypes.CUSTOM, fn = handleReleDirectCurr },
    [RELE_JOLT]         = { type = AlertTypes.CUSTOM, fn = handleReleJolt },
    [GALE_HA]           = { type = AlertTypes.CUSTOM, fn = handleGaleHa },
    [GALE_JUMP]         = { type = AlertTypes.CUSTOM, fn = handleGaleJump },
    [GALE_GLACIAL]      = { type = AlertTypes.CUSTOM, fn = handleGaleGlacial },
    [GALE_DONUT]        = { type = AlertTypes.CUSTOM, fn = handleGaleDonut },
    [GALE_HOARFROST_C]  = { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostCast },
    [GALE_HOARFROST_C2] = { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostCast },
    [PORTAL_OPEN]       = { type = AlertTypes.CUSTOM, fn = handlePortalOpen },
    [PORTAL_CLOSE_1]    = { type = AlertTypes.CUSTOM, fn = handlePortalClose },
    [PORTAL_CLOSE_2]    = { type = AlertTypes.CUSTOM, fn = handlePortalClose },
    [PLAYER_EXIT]       = { type = AlertTypes.CUSTOM, fn = handlePortalClose },
    [PORTAL_RESET]      = { type = AlertTypes.CUSTOM, fn = handlePortalReset },
    [ZMAJA_RESET_PORT]  = { type = AlertTypes.CUSTOM, fn = handlePortalReset },
    [ZMAJA_JUMP]        = { type = AlertTypes.CUSTOM, fn = handleZmajaJump },
    [ZMAJA_HIDE_JUMP]   = { type = AlertTypes.CUSTOM, fn = handleZmajaHideJump },
    [CRUSHING_DARK_1]   = { type = AlertTypes.CUSTOM, fn = handleCrushingDark },
    [CRUSHING_DARK_2]   = { type = AlertTypes.CUSTOM, fn = handleCrushingDark },
    [CRUSHING_DARK_3]   = { type = AlertTypes.CUSTOM, fn = handleCrushingDark },
    [SHADOW_SPLASH]     = { type = AlertTypes.CUSTOM, fn = handleShadowSplash },
    [BANEFUL_MARK]      = { type = AlertTypes.CUSTOM, fn = handleBanefulMark },
    [OLORIME_SPEAR]     = { type = AlertTypes.CUSTOM, fn = handleOlorimeSpear },
    [CORE_EXPOSED]      = { type = AlertTypes.CUSTOM, fn = handleCoreExposed },
    [CORE_MISSED]       = { type = AlertTypes.CUSTOM, fn = handleCoreMissed },
    [CORE_PICKED_UP]    = { type = AlertTypes.CUSTOM, fn = handleCorePickedUp },
}

local _combatOtherEntry = {
    [ZMAJA_SHACKLE]    = { type = AlertTypes.CUSTOM, fn = handleShackle },
    [SIRO_DARK_TALONS] = { type = AlertTypes.CUSTOM, fn = handleSiroDarkTalons },
    [RELE_OVERLOAD_1]  = { type = AlertTypes.CUSTOM, fn = handleReleOverload1 },
    [RELE_OVERLOAD_2]  = { type = AlertTypes.CUSTOM, fn = handleReleOverload2 },
    [GALE_HOARFROST_SY]= { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostSy },
    [GALE_HOARFROST_S2]= { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostSy },
    [GALE_COMET]       = { type = AlertTypes.CUSTOM, fn = handleGaleComet },
    [GALE_COMET_2]     = { type = AlertTypes.CUSTOM, fn = handleGaleComet },
    [RAZOR_THORNS]     = { type = AlertTypes.CUSTOM, fn = handleRazorThorns },
}

local _effectGainedEntry = {
    [GALE_HOARFROST]   = { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostGained },
    [GALE_HOARFROST_2] = { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostGained },
}

local _effectFadedEntry = {
    [GALE_HOARFROST]   = { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostFaded },
    [GALE_HOARFROST_2] = { type = AlertTypes.CUSTOM, fn = handleGaleHoarfrostFaded },
}

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

ZmajaEncounter.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Info-line renderers ---------------------------------------------------

local function showPortalStatusLine(self, alerts, now)
    if self.portalActive then
        local r = self.portalTimer:remainingAt(now)
        if r > 0 then
            alerts:setRow(1, _STR_PORTAL_OPEN, r)
        else
            alerts:setRow(1, _STR_PORTAL_CLOSING, nil)
        end
    else
        local r = self.portalNextTimer:remainingAt(now)
        if r > 0 then
            alerts:setRow(1, _STR_PORTAL_NEXT, r)
        else
            alerts:clearRow(1)
        end
    end
end

local function showPortalGroupLine(self, alerts)
    if self.executePhase then
        alerts:setRow(2, _STR_EXECUTE_PHASE, nil)
    elseif self.portalGroup > 0 and self._groupStr then
        alerts:setRow(2, self._groupStr, nil)
    else
        alerts:clearRow(2)
    end
end

local function showSpearLine(self, alerts)
    if self.spearCount > 0 and self._spearStr then
        alerts:setRow(4, self._spearStr, nil)
    else
        alerts:clearRow(4)
    end
end

local function showSiroLine(self, alerts, now)
    if self.siro.active then
        alerts:setRow(5, miniLine(self.siro, self.siro.jump, self.siro.banner, now,
            "cr_zmaja_siro_label", _STR_READY), nil)
    else
        alerts:clearRow(5)
    end
end

local function showReleLine(self, alerts, now)
    if self.rele.active then
        alerts:setRow(6, miniLine(self.rele, self.rele.jump, self.rele.bash, now,
            "cr_zmaja_rele_label", _STR_BASH_DUE), nil)
    else
        alerts:clearRow(6)
    end
end

local function showGaleLine(self, alerts, now)
    if self.gale.active then
        alerts:setRow(7, miniLine(self.gale, self.gale.jump, self.gale.bash, now,
            "cr_zmaja_gale_label", _STR_BASH_DUE), nil)
    else
        alerts:clearRow(7)
    end
end

function ZmajaEncounter:onWipe(context, alerts)
    self:cleanupAlertList()
    BossBase.resetSchema(self, ZmajaEncounter)
end

function ZmajaEncounter:onUpdate(context, alerts)
    -- One GetGameTimeMilliseconds() per tick shared by all eight timers.
    local now = GetGameTimeMilliseconds() / 1000
    showPortalStatusLine(self, alerts, now)
    showPortalGroupLine(self, alerts)
    if self.coreAlert then alerts:setRow(3, self.coreAlert, nil) else alerts:clearRow(3) end
    showSpearLine(self, alerts)
    showSiroLine(self, alerts, now)
    showReleLine(self, alerts, now)
    showGaleLine(self, alerts, now)
end

EventDispatcher.build(ZmajaEncounter)

package.loaded["trial.cr.boss.ZmajaEncounter"] = ZmajaEncounter
return ZmajaEncounter
