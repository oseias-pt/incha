local Timer    = require("lib.Timer")

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")
local Lang = require("core.Lang")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local PIERCING_BEAM = 219165   -- combatRoute: ACTION_RESULT_BEGIN → INTERRUPT; CD 14s first / 32s steady
local VITRIFY       = 219083   -- combatRoute: ACTION_RESULT_BEGIN → INTERRUPT; CD  9s first / 20s steady

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local BEAM_FIRST_CD    = 14.0
local BEAM_CD          = 32.0
local VITRIFY_FIRST_CD =  9.0
local VITRIFY_CD       = 20.0

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_INTERRUPT = { -3, 0, false, { 1, 0.1, 0.1, 0.4 }, { 1, 0.1, 0.1, 0.8 } }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_BEAM_DUR    = 2500   -- PiercingBeam: empirical
local FALLBACK_VITRIFY_DUR = 2000   -- Vitrify: empirical

local XynizataEncounter = {}
XynizataEncounter.__index = XynizataEncounter

XynizataEncounter.key               = "xynizata"
XynizataEncounter.nameAliases       = { Lang.t("boss_xynizata") }
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- (0 would make detectDifficulty always return HARDMODE.)
XynizataEncounter.hmHealthThreshold = math.huge
-- location: placeholder — Lucent Citadel arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

XynizataEncounter.stateSchema = {
    piercingBeamTimer = function() return Timer.new(BEAM_CD) end,
    vitrifyTimer      = function() return Timer.new(VITRIFY_CD) end,
    firstBeam         = true,
    firstVitrify      = true,
}

function XynizataEncounter.new()
    return BossBase.fromSchema(XynizataEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

local function handlePiercingBeam(self, context, alerts, abilityId, ...)
    self.firstBeam = false
    self.piercingBeamTimer:reset(BEAM_CD)
    local dur = CastDur.get(abilityId, FALLBACK_BEAM_DUR)
    CA.alertCast(abilityId, Lang.t("lc_xynizata_beam_bar"), dur, COL_INTERRUPT)
    alerts:showAction(Lang.t("lc_xynizata_interrupt_beam"))
end

local function handleVitrify(self, context, alerts, abilityId, ...)
    self.firstVitrify = false
    self.vitrifyTimer:reset(VITRIFY_CD)
    local dur = CastDur.get(abilityId, FALLBACK_VITRIFY_DUR)
    CA.alertCast(abilityId, Lang.t("lc_xynizata_interrupt_vitr"), dur, COL_INTERRUPT)
    alerts:showAction(Lang.t("lc_xynizata_interrupt_vitr"))
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

XynizataEncounter.combatRoutes = {
    [PIERCING_BEAM] = { result = ACTION_RESULT_BEGIN, fn = handlePiercingBeam },
    [VITRIFY]       = { result = ACTION_RESULT_BEGIN, fn = handleVitrify },
}

function XynizataEncounter:onWipe()
    self.piercingBeamTimer:clear(); self.vitrifyTimer:clear()
    self.firstBeam = true; self.firstVitrify = true
end

function XynizataEncounter:onUpdate(context, alerts)
    -- Line 1: Piercing Beam CD
    if self.firstBeam then
        alerts:showInfo(1, Lang.t("lc_xynizata_beam_first"))
    else
        local r = self.piercingBeamTimer:remaining()
        alerts:showInfo(1, Lang.t("lc_xynizata_beam_label")
            .. (r > 0 and ZO_FormatCountdownTimer(r) or Lang.t("common_interrupt")))
    end

    -- Line 2: Vitrify CD
    if self.firstVitrify then
        alerts:showInfo(2, Lang.t("lc_xynizata_vitr_first"))
    else
        local r = self.vitrifyTimer:remaining()
        alerts:showInfo(2, Lang.t("lc_xynizata_vitr_label")
            .. (r > 0 and ZO_FormatCountdownTimer(r) or Lang.t("common_interrupt")))
    end

    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

package.loaded["trial.lc.boss.XynizataEncounter"] = XynizataEncounter
return XynizataEncounter
