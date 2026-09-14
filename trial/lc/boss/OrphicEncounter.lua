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
local THUNDER_THRALL  = 214383
local LIGHTNING_FLOOD = 214355
local COLOR_CHANGE    = 213913
local BREAKOUT        = 220185
local SHIELD_THROW    = 221945
local XORYN_IMMUNE_1  = 217987
local XORYN_IMMUNE_2  = 219545

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local THRALL_CD = 25.5
local FLOOD_CD  = 21.5

local FALLBACK_DUR = 2000

-- P6: module-level string constants — avoid Lang.t calls in onUpdate (60 fps)
local _STR_THRALL_FIRST = Lang.t("lc_orphic_thrall_first")
local _STR_THRALL_LABEL = Lang.t("lc_orphic_thrall_label")
local _STR_THRALL_NOW   = Lang.t("lc_orphic_thrall_label") .. " " .. Lang.t("common_now")
local _STR_FLOOD_FIRST  = Lang.t("lc_orphic_flood_first")
local _STR_FLOOD_LABEL  = Lang.t("lc_orphic_flood_label")
local _STR_FLOOD_NOW    = Lang.t("lc_orphic_flood_label") .. " " .. Lang.t("common_now")

local OrphicEncounter = {}
OrphicEncounter.__index = OrphicEncounter

OrphicEncounter.key               = "orphic"
OrphicEncounter.nameAliases       = { "Orphic Shattered Shard" }
-- Health-pool threshold between NM and HM; re-verify after major patches.
OrphicEncounter.hmHealthThreshold = 80000000

OrphicEncounter.stateSchema = {
    thunderThrallTimer  = function() return Timer.new(THRALL_CD) end,
    lightningFloodTimer = function() return Timer.new(FLOOD_CD) end,
    xorynActive         = false,
    firstThrall         = true,
    firstFlood          = true,
}

function OrphicEncounter.new()
    return BossBase.fromSchema(OrphicEncounter)
end

-- ── Handlers: beginCast ──────────────────────────────────────────────────

local function handleThunderThrall(boss, ctx, alerts, abilityId, ...)
    boss.xorynActive = true
    boss.firstThrall = false
    boss.thunderThrallTimer:reset(THRALL_CD)
    alerts:showAction(Lang.t("lc_orphic_thunder_thrall"))
end

local function handleLightningFlood(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    boss.xorynActive = true
    boss.firstFlood  = false
    boss.lightningFloodTimer:reset(FLOOD_CD)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("lc_orphic_lightning_flood", target))
end

local function handleBreakout(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.ranged(abilityId, Lang.t("lc_orphic_break_out_bar"), 3000, Colors.ARCANE)
    alerts:showAction(Lang.t("lc_orphic_break_crystal"))
end

local function handleShieldThrow(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_orphic_shield_throw", target), dur, Colors.LIGHTNING)
end

-- ── Handlers: combatEvent.other ──────────────────────────────────────────
-- combatEvent sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)

-- COLOR_CHANGE fires as EFFECT_GAINED (combat path) → combatEvent.other
local function handleColorChange(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("lc_orphic_color_change_alert"), 0xFFFF44FF, SOUNDS.NONE, 3000)
    alerts:showAction(Lang.t("lc_orphic_color_change"))
end

-- XORYN_IMMUNE fires EFFECT_GAINED (Xoryn leaving) and EFFECT_FADED (Xoryn returning).
-- Both results reach combatEvent.other; use xorynActive toggle to distinguish.
local function handleXorynImmune(boss, ctx, alerts, abilityId, ...)
    if boss.xorynActive then
        -- EFFECT_GAINED: Xoryn leaving
        boss.xorynActive = false
        boss.thunderThrallTimer:clear()
        boss.lightningFloodTimer:clear()
    else
        -- EFFECT_FADED: Xoryn returning
        boss.xorynActive = true
        boss.firstThrall = true
        boss.firstFlood  = true
    end
end

-- ── Event tables ─────────────────────────────────────────────────────────

-- Shared LC mechanics (Solar Flare cast bar, Hindered tank swap, Radiance
-- border) come from LCCommon and are merged into this boss's buckets.
local _beginCastEntry = {}
for k, v in pairs(LCCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[THUNDER_THRALL]  = { type = AlertTypes.CUSTOM, fn = handleThunderThrall }
_beginCastEntry[LIGHTNING_FLOOD] = { type = AlertTypes.CUSTOM, fn = handleLightningFlood }
_beginCastEntry[BREAKOUT]        = { type = AlertTypes.CUSTOM, fn = handleBreakout }
_beginCastEntry[SHIELD_THROW]    = { type = AlertTypes.CUSTOM, fn = handleShieldThrow }

local _effectGainedEntry = {}
for k, v in pairs(LCCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
local _effectFadedEntry = {}
for k, v in pairs(LCCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end

local _combatOtherEntry = {
    [COLOR_CHANGE]   = { type = AlertTypes.CUSTOM, fn = handleColorChange },
    [XORYN_IMMUNE_1] = { type = AlertTypes.CUSTOM, fn = handleXorynImmune },
    [XORYN_IMMUNE_2] = { type = AlertTypes.CUSTOM, fn = handleXorynImmune },
}

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

OrphicEncounter.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

function OrphicEncounter:onWipe(context, alerts)
    self.thunderThrallTimer:clear(); self.lightningFloodTimer:clear()
    self.xorynActive = false; self.firstThrall = true; self.firstFlood = true
end

function OrphicEncounter:onUpdate(context, alerts)
    if self.xorynActive then
        local now = GetGameTimeMilliseconds() / 1000
        if self.firstThrall then
            alerts:setRow(1, _STR_THRALL_FIRST, nil)
        else
            local r = self.thunderThrallTimer:remainingAt(now)
            if r > 0 then
                alerts:setRow(1, _STR_THRALL_LABEL, r)
            else
                alerts:setRow(1, _STR_THRALL_NOW, nil)
            end
        end
        if self.firstFlood then
            alerts:setRow(2, _STR_FLOOD_FIRST, nil)
        else
            local r = self.lightningFloodTimer:remainingAt(now)
            if r > 0 then
                alerts:setRow(2, _STR_FLOOD_LABEL, r)
            else
                alerts:setRow(2, _STR_FLOOD_NOW, nil)
            end
        end
    else
        alerts:clearRow(1)
        alerts:clearRow(2)
    end
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

EventDispatcher.build(OrphicEncounter)

package.loaded["trial.lc.boss.OrphicEncounter"] = OrphicEncounter
return OrphicEncounter
