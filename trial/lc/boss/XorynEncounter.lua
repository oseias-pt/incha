local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local Colors          = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local ARCANE_KNOT         = 213477
local ARCANE_CONVEYANCE   = 223024
local ARCANE_CONV_DEBUFF  = 223060
local FLUCTUATING_CURRENT = 214597
local OVERLOADED_CURRENT  = 214745
local NECROTIC_BARRAGE    = 223198
local ACCELERATING_CHARGE = 214542
local TEMPEST             = 215107
local GLASS_STOMP_CAST    = 219797
local LUSTROUS_JAVELIN    = 223546

local CURRENT_MAX_DUR = 15.0

local FALLBACK_BARRAGE_DUR = 3000
local FALLBACK_DUR         = 2000

local XorynEncounter = {}
XorynEncounter.__index = XorynEncounter

XorynEncounter.key               = "xoryn"
XorynEncounter.nameAliases       = { "Xoryn" }
XorynEncounter.hmHealthThreshold = 100000000

XorynEncounter.stateSchema = {
    currentTimer    = function() return Timer.new(CURRENT_MAX_DUR) end,
    knotCarrierName = false,
    holdingCurrent  = false,
}

function XorynEncounter.new()
    return BossBase.fromSchema(XorynEncounter)
end

-- ── Handlers: beginCast ──────────────────────────────────────────────────

local function handleNecroticBarrage(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_BARRAGE_DUR)
    CA.ranged(abilityId, Lang.t("lc_xoryn_barrage_bar"), dur, Colors.VOID)
end

local function handleAcceleratingCharge(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("lc_xoryn_chain_lightning"), 0xFFFF44FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_xoryn_accel_charge"))
end

local function handleTempest(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_xoryn_tempest_bar"), dur, Colors.ICE)
    alerts:showAction(Lang.t("lc_xoryn_tempest"))
end

local function handleGlassStomp(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_xoryn_atronach_bar", target), dur, Colors.ORANGE)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("lc_xoryn_atronach_aoe"))
    end
end

local function handleLustrousJavelin(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("lc_xoryn_javelin_alert"), 0xFF8844FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_xoryn_lustrous_javelin"))
end

local function handleArcaneConveyance(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("lc_xoryn_tethers_cast"), 0xFF4444FF, SOUNDS.NONE, 3000)
end

-- ── Handlers: combatEvent.other ──────────────────────────────────────────
-- combatEvent sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)

-- ARCANE_CONV_DEBUFF fires as EFFECT_GAINED_DURATION (combat path) → combatEvent.other
local function handleArcaneConvDebuff(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("lc_xoryn_tether_alert"), 0xFF4444FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_xoryn_tether"))
end

-- ARCANE_KNOT fires EFFECT_GAINED_DURATION (picking up) and EFFECT_FADED (releasing).
-- Both reach combatEvent.other; toggle via knotCarrierName truthiness.
local function handleArcaneKnot(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not boss.knotCarrierName then
        -- EFFECT_GAINED_DURATION: player/unit gained knot
        boss.knotCarrierName = GetUnitDisplayName(unitTag) or "?"
        if IsUnitPlayer(unitTag) then
            CA.alert(nil, Lang.t("lc_xoryn_knot_alert"), 0xFFAA44FF, SOUNDS.NONE, 4000)
            alerts:showAction(Lang.t("lc_xoryn_arcane_knot"))
        end
    else
        -- EFFECT_FADED: knot released or transferred
        boss.knotCarrierName = false
    end
end

-- FLUCTUATING_CURRENT fires EFFECT_GAINED_DURATION (gaining) and EFFECT_FADED (dropping).
-- Both reach combatEvent.other; toggle via holdingCurrent flag.
local function handleFluctuatingCurrent(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    if not boss.holdingCurrent then
        -- EFFECT_GAINED_DURATION: player gained current
        boss.holdingCurrent = true
        boss.currentTimer:reset(CURRENT_MAX_DUR)
        CA.alert(nil, Lang.t("lc_xoryn_current_alert"), 0x44CCFFFF, SOUNDS.NONE, 3000)
        alerts:showAction(Lang.t("lc_xoryn_fluctuating"))
    else
        -- EFFECT_FADED: player dropped current
        boss.holdingCurrent = false
        boss.currentTimer:clear()
    end
end

-- OVERLOADED_CURRENT fires as EFFECT_GAINED_DURATION (combat path) → combatEvent.other
local function handleOverloadedCurrent(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.alert(nil, Lang.t("lc_xoryn_drop_alert"), 0xFF0000FF, SOUNDS.NONE, 2000)
    alerts:showAction(Lang.t("lc_xoryn_overloaded"))
end

-- ── Event tables ─────────────────────────────────────────────────────────

local _beginCastEntry = {
    [NECROTIC_BARRAGE]    = { type = AlertTypes.CUSTOM, fn = handleNecroticBarrage },
    [ACCELERATING_CHARGE] = { type = AlertTypes.CUSTOM, fn = handleAcceleratingCharge },
    [TEMPEST]             = { type = AlertTypes.CUSTOM, fn = handleTempest },
    [GLASS_STOMP_CAST]    = { type = AlertTypes.CUSTOM, fn = handleGlassStomp },
    [LUSTROUS_JAVELIN]    = { type = AlertTypes.CUSTOM, fn = handleLustrousJavelin },
    [ARCANE_CONVEYANCE]   = { type = AlertTypes.CUSTOM, fn = handleArcaneConveyance },
}

local _combatOtherEntry = {
    [ARCANE_CONV_DEBUFF]  = { type = AlertTypes.CUSTOM, fn = handleArcaneConvDebuff },
    [ARCANE_KNOT]         = { type = AlertTypes.CUSTOM, fn = handleArcaneKnot },
    [FLUCTUATING_CURRENT] = { type = AlertTypes.CUSTOM, fn = handleFluctuatingCurrent },
    [OVERLOADED_CURRENT]  = { type = AlertTypes.CUSTOM, fn = handleOverloadedCurrent },
}

XorynEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = {}, faded = {}, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- ── Info-line renderers ───────────────────────────────────────────────────

local function showCurrentLine(self, alerts)
    if self.holdingCurrent then
        local r = self.currentTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Fmt.c(Fmt.ICE, Lang.t("lc_xoryn_current")), r)
        else
            alerts:setRow(1, Fmt.c(Fmt.RED, Lang.t("lc_xoryn_drop_now")), nil)
        end
    else
        alerts:clearRow(1)
    end
end

local function showKnotLine(self, alerts)
    if self.knotCarrierName then
        alerts:setRow(2, Fmt.c(Fmt.AMBER, Lang.t("lc_xoryn_knot_carrier", self.knotCarrierName)), nil)
    else
        alerts:clearRow(2)
    end
end

function XorynEncounter:onWipe(context, alerts)
    self.currentTimer:clear()
    self.knotCarrierName = false
    self.holdingCurrent  = false
end

function XorynEncounter:onUpdate(context, alerts)
    showCurrentLine(self, alerts)
    showKnotLine(self, alerts)
end

EventDispatcher.build(XorynEncounter)

package.loaded["trial.lc.boss.XorynEncounter"] = XorynEncounter
return XorynEncounter
