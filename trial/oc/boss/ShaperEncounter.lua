
local AlertTypes       = require("core.AlertTypes")
local EventDispatcher  = require("core.EventDispatcher")
local CA               = require("external-api.CombatAlerts")
local BossBase         = require("lib.BossBase")
local CastDur          = require("lib.CastDur")
local OsseinCageCommon = require("trial.oc.OsseinCageCommon")
local Lang             = require("core.Lang")
local Fmt              = require("core.Fmt")
local Colors           = require("core.Colors")

-- ── Ability IDs ──────────────────────────────────────────────────────────────────────────────────
local OGRIM_CHARGE     = 236496   -- beginCast: ACTION_RESULT_BEGIN → MOVE caAlertCast (player)
local SHAPER_SHIELD    = 232511   -- effectChanged.gained/faded → shield state
local CHANNELER_SHIELD = 232510   -- combatEvent.other: ACTION_RESULT_EFFECT_GAINED → channelers alert

-- ── Fallback durations ────────────────────────────────────────────────────────────────────────────
local FALLBACK_DUR = 2000

local ShaperEncounter = {}
ShaperEncounter.__index = ShaperEncounter

ShaperEncounter.key               = "shaper"
ShaperEncounter.nameAliases       = { "Shaper of Flesh" }
ShaperEncounter.hmHealthThreshold = math.huge

ShaperEncounter.stateSchema = {
    shaperShielded = false,
}

function ShaperEncounter.new()
    return BossBase.fromSchema(ShaperEncounter)
end

-- ── Handlers ─────────────────────────────────────────────────────────────────────────────────────

local function handleOgrimCharge(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("oc_shaper_ogrim_bar"), dur, Colors.ORANGE)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("oc_shaper_ogrim_you"))
    else
        alerts:showAction(Lang.t("oc_shaper_ogrim_tgt", target))
    end
end

local function handleShaperShieldGained(boss, ctx, alerts, abilityId, ...)
    boss.shaperShielded = true
    CA.alert(nil, Lang.t("oc_shaper_shielded_alert"), 0xAA44FFFF, SOUNDS.NONE, 4000)
    alerts:showAction(Lang.t("oc_shaper_shielded_kill"))
end

local function handleShaperShieldFaded(boss, ctx, alerts, abilityId, ...)
    boss.shaperShielded = false
    CA.alert(nil, Lang.t("oc_shaper_vulnerable_alert"), 0x44FF88FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("oc_shaper_vulnerable"))
end

local function handleChannelerShield(boss, ctx, alerts, abilityId, ...)
    boss.shaperShielded = true
    alerts:showAction(Lang.t("oc_shaper_channelers_shld"))
end

-- ── Event tables ─────────────────────────────────────────────────────────────────────────────────

local _beginCastEntry = {}
for k, v in pairs(OsseinCageCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[OGRIM_CHARGE] = { type = AlertTypes.CUSTOM, fn = handleOgrimCharge }

local _combatOtherEntry = {
    [CHANNELER_SHIELD] = { type = AlertTypes.CUSTOM, fn = handleChannelerShield },
}

local _effectGainedEntry = {}
for k, v in pairs(OsseinCageCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
_effectGainedEntry[SHAPER_SHIELD] = { type = AlertTypes.CUSTOM, fn = handleShaperShieldGained }

local _effectFadedEntry = {}
for k, v in pairs(OsseinCageCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end
_effectFadedEntry[SHAPER_SHIELD] = { type = AlertTypes.CUSTOM, fn = handleShaperShieldFaded }

ShaperEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

function ShaperEncounter:onWipe(context, alerts)
    OsseinCageCommon.reset()
    self.shaperShielded = false
end

function ShaperEncounter:onUpdate(context, alerts)
    if self.shaperShielded then
        alerts:setRow(1, Fmt.c("AA44FF", Lang.t("oc_shaper_shielded_info")), nil)
    else
        alerts:clearRow(1)
    end
    alerts:clearRow(2)
    OsseinCageCommon.showCarrionInfo(alerts)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

EventDispatcher.build(ShaperEncounter)

package.loaded["trial.oc.boss.ShaperEncounter"] = ShaperEncounter
return ShaperEncounter
