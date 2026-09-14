local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Colors          = require("core.Colors")
local LCCommon        = require("trial.lc.LCCommon")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local POWERFUL_THROW = 218971

local FALLBACK_DUR = 2500

local DarielEncounter = {}
DarielEncounter.__index = DarielEncounter

DarielEncounter.key               = "dariel"
DarielEncounter.nameAliases       = { "Dariel", "Dariel Lemonds" }
-- math.huge = always NORMAL difficulty; HM pool not yet measured in-game.
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

-- Shared LC mechanics (Solar Flare cast bar, Hindered tank swap, Radiance
-- border) come from LCCommon and are merged into this boss's buckets.
local _beginCastEntry = {}
for k, v in pairs(LCCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[POWERFUL_THROW] = { type = AlertTypes.CUSTOM, fn = handlePowerfulThrow }

local _effectGainedEntry = {}
for k, v in pairs(LCCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
local _effectFadedEntry = {}
for k, v in pairs(LCCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

DarielEncounter.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
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
