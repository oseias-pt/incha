local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

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
XynizataEncounter.nameAliases       = { "Xynizata" }
XynizataEncounter.hmHealthThreshold = 0
XynizataEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

function XynizataEncounter.new()
    return setmetatable({
        piercingBeamTimer = Timer.new(BEAM_CD),
        vitrifyTimer      = Timer.new(VITRIFY_CD),
        firstBeam         = true,
        firstVitrify      = true,
    }, XynizataEncounter)
end

-- ── Handlers ────────────────────────────────────────────────────────────

local function handlePiercingBeam(self, context, alerts, abilityId, ...)
    self.firstBeam = false
    self.piercingBeamTimer:reset(BEAM_CD)
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    if dur <= 0 then dur = FALLBACK_BEAM_DUR end
    CA.alertCast(abilityId, "INTERRUPT — Beam!", dur, COL_INTERRUPT)
    alerts:showAction("INTERRUPT — Piercing Beam!")
end

local function handleVitrify(self, context, alerts, abilityId, ...)
    self.firstVitrify = false
    self.vitrifyTimer:reset(VITRIFY_CD)
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    if dur <= 0 then dur = FALLBACK_VITRIFY_DUR end
    CA.alertCast(abilityId, "INTERRUPT — Vitrify!", dur, COL_INTERRUPT)
    alerts:showAction("INTERRUPT — Vitrify!")
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

XynizataEncounter.combatRoutes = {
    [PIERCING_BEAM] = { result = ACTION_RESULT_BEGIN, fn = handlePiercingBeam },
    [VITRIFY]       = { result = ACTION_RESULT_BEGIN, fn = handleVitrify },
}

function XynizataEncounter:onUpdate(context, alerts)
    -- Line 1: Piercing Beam CD
    if self.firstBeam then
        alerts:showInfo(1, "Beam: first ~14s")
    else
        local r = self.piercingBeamTimer:remaining()
        alerts:showInfo(1, "Beam: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "INTERRUPT!"))
    end

    -- Line 2: Vitrify CD
    if self.firstVitrify then
        alerts:showInfo(2, "Vitrify: first ~9s")
    else
        local r = self.vitrifyTimer:remaining()
        alerts:showInfo(2, "Vitrify: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "INTERRUPT!"))
    end

    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return XynizataEncounter
