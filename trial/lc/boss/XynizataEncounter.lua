local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Colors          = require("core.Colors")
local LCCommon        = require("trial.lc.LCCommon")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local PIERCING_BEAM = 219165
local VITRIFY       = 219083

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local BEAM_CD    = 32.0
local VITRIFY_CD = 20.0

local FALLBACK_BEAM_DUR    = 2500
local FALLBACK_VITRIFY_DUR = 2000

-- P6: module-level string constants — avoid Lang.t calls in onUpdate (60 fps)
local _STR_BEAM_FIRST    = Lang.t("lc_xynizata_beam_first")
local _STR_BEAM_LABEL    = Lang.t("lc_xynizata_beam_label")
local _STR_BEAM_INC      = Lang.t("lc_xynizata_beam_label") .. " " .. Lang.t("common_interrupt")
local _STR_VITR_FIRST    = Lang.t("lc_xynizata_vitr_first")
local _STR_VITR_LABEL    = Lang.t("lc_xynizata_vitr_label")
local _STR_VITR_INC      = Lang.t("lc_xynizata_vitr_label") .. " " .. Lang.t("common_interrupt")

local XynizataEncounter = {}
XynizataEncounter.__index = XynizataEncounter

XynizataEncounter.key               = "xynizata"
XynizataEncounter.nameAliases       = { "Xynizata", "Jresazzel" }
-- math.huge = always NORMAL difficulty; HM pool not yet measured in-game.
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

-- Shared LC mechanics (Solar Flare cast bar, Hindered tank swap, Radiance
-- border) come from LCCommon and are merged into this boss's buckets.
local _beginCastEntry = {}
for k, v in pairs(LCCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[PIERCING_BEAM] = { type = AlertTypes.CUSTOM, fn = handlePiercingBeam }
_beginCastEntry[VITRIFY]       = { type = AlertTypes.CUSTOM, fn = handleVitrify }

local _effectGainedEntry = {}
for k, v in pairs(LCCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
local _effectFadedEntry = {}
for k, v in pairs(LCCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

XynizataEncounter.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

function XynizataEncounter:onWipe(context, alerts)
    self.piercingBeamTimer:clear(); self.vitrifyTimer:clear()
    self.firstBeam = true; self.firstVitrify = true
end

function XynizataEncounter:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    if self.firstBeam then
        alerts:setRow(1, _STR_BEAM_FIRST, nil)
    else
        local r = self.piercingBeamTimer:remainingAt(now)
        if r > 0 then
            alerts:setRow(1, _STR_BEAM_LABEL, r)
        else
            alerts:setRow(1, _STR_BEAM_INC, nil)
        end
    end

    if self.firstVitrify then
        alerts:setRow(2, _STR_VITR_FIRST, nil)
    else
        local r = self.vitrifyTimer:remainingAt(now)
        if r > 0 then
            alerts:setRow(2, _STR_VITR_LABEL, r)
        else
            alerts:setRow(2, _STR_VITR_INC, nil)
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
