local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Colors          = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local PIERCING_BEAM = 219165
local VITRIFY       = 219083

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local BEAM_CD    = 32.0
local VITRIFY_CD = 20.0

local FALLBACK_BEAM_DUR    = 2500
local FALLBACK_VITRIFY_DUR = 2000

local XynizataEncounter = {}
XynizataEncounter.__index = XynizataEncounter

XynizataEncounter.key               = "xynizata"
XynizataEncounter.nameAliases       = { "Xynizata", "Jresazzel" }
XynizataEncounter.hmHealthThreshold = math.huge

XynizataEncounter.stateSchema = {
    piercingBeamTimer = function() return Timer.new(BEAM_CD) end,
    vitrifyTimer      = function() return Timer.new(VITRIFY_CD) end,
    firstBeam         = true,
    firstVitrify      = true,
}

function XynizataEncounter.new()
    return BossBase.fromSchema(XynizataEncounter)
end

-- ── Handlers: beginCast ──────────────────────────────────────────────────

local function handlePiercingBeam(boss, ctx, alerts, abilityId, ...)
    boss.firstBeam = false
    boss.piercingBeamTimer:reset(BEAM_CD)
    local dur = CastDur.get(abilityId, FALLBACK_BEAM_DUR)
    CA.ranged(abilityId, Lang.t("lc_xynizata_beam_bar"), dur, Colors.RED)
    alerts:showAction(Lang.t("lc_xynizata_interrupt_beam"))
end

local function handleVitrify(boss, ctx, alerts, abilityId, ...)
    boss.firstVitrify = false
    boss.vitrifyTimer:reset(VITRIFY_CD)
    local dur = CastDur.get(abilityId, FALLBACK_VITRIFY_DUR)
    CA.ranged(abilityId, Lang.t("lc_xynizata_interrupt_vitr"), dur, Colors.RED)
    alerts:showAction(Lang.t("lc_xynizata_interrupt_vitr"))
end

-- ── Event tables ─────────────────────────────────────────────────────────

local _beginCastEntry = {
    [PIERCING_BEAM] = { type = AlertTypes.CUSTOM, fn = handlePiercingBeam },
    [VITRIFY]       = { type = AlertTypes.CUSTOM, fn = handleVitrify },
}

XynizataEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = {}, faded = {}, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

function XynizataEncounter:onWipe(context, alerts)
    self.piercingBeamTimer:clear(); self.vitrifyTimer:clear()
    self.firstBeam = true; self.firstVitrify = true
end

function XynizataEncounter:onUpdate(context, alerts)
    if self.firstBeam then
        alerts:setRow(1, Lang.t("lc_xynizata_beam_first"), nil)
    else
        local r = self.piercingBeamTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Lang.t("lc_xynizata_beam_label"), r)
        else
            alerts:setRow(1, Lang.t("lc_xynizata_beam_label") .. " " .. Lang.t("common_interrupt"), nil)
        end
    end

    if self.firstVitrify then
        alerts:setRow(2, Lang.t("lc_xynizata_vitr_first"), nil)
    else
        local r = self.vitrifyTimer:remaining()
        if r > 0 then
            alerts:setRow(2, Lang.t("lc_xynizata_vitr_label"), r)
        else
            alerts:setRow(2, Lang.t("lc_xynizata_vitr_label") .. " " .. Lang.t("common_interrupt"), nil)
        end
    end

    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

EventDispatcher.build(XynizataEncounter)

package.loaded["trial.lc.boss.XynizataEncounter"] = XynizataEncounter
return XynizataEncounter
