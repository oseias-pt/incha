local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Colors          = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local POWERFUL_THROW = 218971

local FALLBACK_DUR = 2500

local DarielEncounter = {}
DarielEncounter.__index = DarielEncounter

DarielEncounter.key               = "dariel"
DarielEncounter.nameAliases       = { "Dariel", "Dariel Lemonds" }
DarielEncounter.hmHealthThreshold = math.huge

DarielEncounter.stateSchema = {}

function DarielEncounter.new()
    return BossBase.fromSchema(DarielEncounter)
end

-- ── Handlers: beginCast ──────────────────────────────────────────────────

local function handlePowerfulThrow(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_dariel_throw_target", target), dur, Colors.ORANGE)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("lc_dariel_throw_you"))
    else
        alerts:showAction(Lang.t("lc_dariel_throw_target", target))
    end
end

-- ── Event tables ─────────────────────────────────────────────────────────

local _beginCastEntry = {
    [POWERFUL_THROW] = { type = AlertTypes.CUSTOM, fn = handlePowerfulThrow },
}

DarielEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = {}, faded = {}, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

function DarielEncounter:onWipe(context, alerts)
    -- stateSchema is empty; no state to reset.
end

function DarielEncounter:onUpdate(context, alerts)
    alerts:clearRow(1)
    alerts:clearRow(2)
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

EventDispatcher.build(DarielEncounter)

package.loaded["trial.lc.boss.DarielEncounter"] = DarielEncounter
return DarielEncounter
