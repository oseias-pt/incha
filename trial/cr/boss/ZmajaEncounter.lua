local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
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
ZmajaEncounter.hmHealthThreshold = math.huge

ZmajaEncounter.stateSchema = {
    siroJumpTimer   = function() return Timer.new(SIRO_JUMP_CD) end,
    siroBannerTimer = function() return Timer.new(SIRO_BANNER_CD) end,
    releJumpTimer   = function() return Timer.new(RELE_JUMP_CD) end,
    releBashTimer   = function() return Timer.new(RELE_BASH_CD) end,
    releJoltTimer   = function() return Timer.new(RELE_JOLT_CD) end,
    galeJumpTimer   = function() return Timer.new(GALE_JUMP_CD) end,
    galeBashTimer   = function() return Timer.new(GALE_BASH_CD) end,
    galeDonutTimer  = function() return Timer.new(GALE_DONUT_CD) end,
    portalTimer     = function() return Timer.new(PORTAL_OPEN_DUR) end,
    portalNextTimer = function() return Timer.new(PORTAL_NEXT_CD) end,
    siroActive      = false,
    releActive      = false,
    galeActive      = false,
    portalGroup     = 0,
    portalActive    = false,
    executePhase    = false,
    spearCount      = 0,
    alertList       = function() return {} end,
    coreAlert       = false,
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
        boss.siroActive = false
        boss.siroJumpTimer:clear(); boss.siroBannerTimer:clear()
    elseif unitName and unitName:find("Relequen", 1, true) then
        boss.releActive = false
        boss.releJumpTimer:clear(); boss.releBashTimer:clear(); boss.releJoltTimer:clear()
    elseif unitName and unitName:find("Galenwe", 1, true) then
        boss.galeActive = false
        boss.galeJumpTimer:clear(); boss.galeBashTimer:clear(); boss.galeDonutTimer:clear()
    end
end

-- Roaring Flare: base + execute variant, both → beginCast
local function handleSiroFlare(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.siroActive then boss.siroActive = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_siro_flare", target))
    local dur = CastDur.get(abilityId, math.floor(FLARE_WINDOW * 1000))
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_siro_flare", target), dur, Colors.FIRE)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleSiroHa(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.siroActive then boss.siroActive = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_siro_ha", target))
    local dur = CastDur.get(SIRO_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_siro_ha_bar"), dur, Colors.FIRE)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleSiroJump(boss, ctx, alerts, abilityId, ...)
    if not boss.siroActive then boss.siroActive = true end
    alerts:showAction(Lang.t("cr_zmaja_siro_jump"))
    boss.siroJumpTimer:reset()
end

local function handleSiroBanner(boss, ctx, alerts, abilityId, ...)
    if not boss.siroActive then boss.siroActive = true end
    alerts:showAction(Lang.t("cr_zmaja_siro_banner"))
    boss.siroBannerTimer:reset()
end

local function handleReleHa(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.releActive then boss.releActive = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_rele_ha", target))
    local dur = CastDur.get(RELE_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_rele_ha_bar"), dur, Colors.ICE)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleReleJump(boss, ctx, alerts, abilityId, ...)
    if not boss.releActive then boss.releActive = true end
    alerts:showAction(Lang.t("cr_zmaja_rele_jump"))
    boss.releJumpTimer:reset()
end

local function handleReleDirectCurr(boss, ctx, alerts, abilityId, ...)
    if not boss.releActive then boss.releActive = true end
    alerts:showAction(Lang.t("cr_zmaja_rele_interrupt"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
    boss.releBashTimer:reset()
end

local function handleReleJolt(boss, ctx, alerts, abilityId, ...)
    if not boss.releActive then boss.releActive = true end
    alerts:showAction(Lang.t("cr_zmaja_rele_jolt"))
    boss.releJoltTimer:reset()
end

local function handleGaleHa(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not boss.galeActive then boss.galeActive = true end
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("cr_zmaja_gale_ha", target))
    local dur = CastDur.get(GALE_HA, FALLBACK_HA_DUR)
    local cid = CA.ranged(abilityId, Lang.t("cr_zmaja_gale_ha_bar"), dur, Colors.CYAN)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleGaleJump(boss, ctx, alerts, abilityId, ...)
    if not boss.galeActive then boss.galeActive = true end
    alerts:showAction(Lang.t("cr_zmaja_gale_jump"))
    boss.galeJumpTimer:reset()
end

local function handleGaleGlacial(boss, ctx, alerts, abilityId, ...)
    if not boss.galeActive then boss.galeActive = true end
    alerts:showAction(Lang.t("cr_zmaja_gale_interrupt"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0000FF, SOUNDS.NONE, 2500)
    boss.galeBashTimer:reset()
end

local function handleGaleDonut(boss, ctx, alerts, abilityId, ...)
    if not boss.galeActive then boss.galeActive = true end
    alerts:showAction(Lang.t("cr_zmaja_gale_donut"))
    boss.galeDonutTimer:reset()
end

-- Hoarfrost cast: marks Galenwe active (presence detection only; no alert)
local function handleGaleHoarfrostCast(boss, ctx, alerts, abilityId, ...)
    if not boss.galeActive then boss.galeActive = true end
end

local function handleCrushingDark(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("cr_zmaja_crushing_dark"))
    local dur = CastDur.get(abilityId, FALLBACK_DARK_DUR)
    CA.ranged(abilityId, Lang.t("cr_zmaja_crushing_kite"), dur, Colors.VOID)
end

-- OlorimeSpear: fires on BEGIN only (avoid double-count with EFFECT_GAINED)
local function handleOlorimeSpear(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    boss.spearCount = boss.spearCount + 1
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
    boss.portalActive   = false
    boss.portalTimer:clear()
    boss.portalNextTimer:clear()
    boss.coreAlert      = false
    alerts:showAction(Lang.t("cr_zmaja_portal_reset"))
end

local function handlePortalOpen(boss, ctx, alerts, abilityId, ...)
    boss.portalGroup  = boss.portalGroup + 1
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
    if not boss.siroActive then boss.siroActive = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_siro_root"))
end

local function handleReleOverload1(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.releActive then boss.releActive = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_overload_in"))
end

local function handleReleOverload2(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.releActive then boss.releActive = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_rele_overload_you"))
    CA.alert(nil, Lang.t("cr_zmaja_rele_bar_swap"), 0x3399FFFF, SOUNDS.NONE, 3000)
end

local function handleGaleHoarfrostSy(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.galeActive then boss.galeActive = true end
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("cr_zmaja_gale_drop_frost"))
    CA.alert(nil, Lang.t("cr_zmaja_gale_drop_alert"), 0x00EEEEff, SOUNDS.NONE, 2000)
end

local function handleGaleComet(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.galeActive then boss.galeActive = true end
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
    if not boss.galeActive then boss.galeActive = true end
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
    if not boss.galeActive then boss.galeActive = true end
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

ZmajaEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Info-line renderers ---------------------------------------------------

local function showPortalStatusLine(self, alerts)
    if self.portalActive then
        local r = self.portalTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Lang.t("cr_zmaja_portal_open_label"), r)
        else
            alerts:setRow(1, Lang.t("cr_zmaja_portal_open_label") .. " " .. Lang.t("cr_zmaja_portal_closing"), nil)
        end
    elseif not self.portalNextTimer:isExpired() then
        local r = self.portalNextTimer:remaining()
        alerts:setRow(1, Lang.t("cr_zmaja_portal_next_label"), r)
    else
        alerts:clearRow(1)
    end
end

local function showPortalGroupLine(self, alerts)
    if self.executePhase then
        alerts:setRow(2, Lang.t("cr_zmaja_execute_phase"), nil)
    elseif self.portalGroup > 0 then
        alerts:setRow(2, Lang.t("cr_zmaja_shadow_group", self.portalGroup), nil)
    else
        alerts:clearRow(2)
    end
end

local function showSpearLine(self, alerts)
    if self.spearCount > 0 then
        alerts:setRow(4, Lang.t("cr_zmaja_spears_label") .. self.spearCount, nil)
    else
        alerts:clearRow(4)
    end
end

local function showSiroLine(self, alerts)
    if self.siroActive then
        local j  = self.siroJumpTimer:remaining()
        local b  = self.siroBannerTimer:remaining()
        local jt = j > 0 and (math.ceil(j) .. "s") or Lang.t("common_ready")
        local bt = b > 0 and (math.ceil(b) .. "s") or Lang.t("common_ready")
        alerts:setRow(5, Lang.t("cr_zmaja_siro_label", jt, bt), nil)
    else
        alerts:clearRow(5)
    end
end

local function showReleLine(self, alerts)
    if self.releActive then
        local j  = self.releJumpTimer:remaining()
        local b  = self.releBashTimer:remaining()
        local jt = j > 0 and (math.ceil(j) .. "s") or Lang.t("common_ready")
        local bt = b > 0 and (math.ceil(b) .. "s") or Lang.t("cr_zmaja_bash_due")
        alerts:setRow(6, Lang.t("cr_zmaja_rele_label", jt, bt), nil)
    else
        alerts:clearRow(6)
    end
end

local function showGaleLine(self, alerts)
    if self.galeActive then
        local j  = self.galeJumpTimer:remaining()
        local b  = self.galeBashTimer:remaining()
        local jt = j > 0 and (math.ceil(j) .. "s") or Lang.t("common_ready")
        local bt = b > 0 and (math.ceil(b) .. "s") or Lang.t("cr_zmaja_bash_due")
        alerts:setRow(7, Lang.t("cr_zmaja_gale_label", jt, bt), nil)
    else
        alerts:clearRow(7)
    end
end

function ZmajaEncounter:onWipe(context, alerts)
    self:cleanupAlertList()
    self.siroJumpTimer:clear();   self.siroBannerTimer:clear()
    self.releJumpTimer:clear();   self.releBashTimer:clear();  self.releJoltTimer:clear()
    self.galeJumpTimer:clear();   self.galeBashTimer:clear();  self.galeDonutTimer:clear()
    self.portalTimer:clear();     self.portalNextTimer:clear()
    self.siroActive   = false;    self.releActive   = false;   self.galeActive = false
    self.portalGroup  = 0;        self.portalActive = false
    self.executePhase = false;    self.spearCount   = 0
    self.coreAlert    = false
end

function ZmajaEncounter:onUpdate(context, alerts)
    showPortalStatusLine(self, alerts)
    showPortalGroupLine(self, alerts)
    if self.coreAlert then alerts:setRow(3, self.coreAlert, nil) else alerts:clearRow(3) end
    showSpearLine(self, alerts)
    showSiroLine(self, alerts)
    showReleLine(self, alerts)
    showGaleLine(self, alerts)
end

function ZmajaEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- CR-3: execute threshold pre-warning (if applicable)
end

EventDispatcher.build(ZmajaEncounter)

package.loaded["trial.cr.boss.ZmajaEncounter"] = ZmajaEncounter
return ZmajaEncounter
