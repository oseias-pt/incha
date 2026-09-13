--- LCCommon — cross-encounter mechanics shared across all Lucent Citadel arenas.
---
--- Phase 2 (EventDispatcher):
---   Exposes LCCommon.beginCastEntries and LCCommon.effectChangedEntries
---   which each boss merges into its own event buckets.
---
--- Hindered OSI icon: deferred — unit OSI API requires in-game coordinate
--- measurement.  An alert fires for the tank instead.

local AlertTypes = require("core.AlertTypes")
local CA      = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Lang    = require("core.Lang")
local Colors = require("core.Colors")

local LCCommon = {}

-- ── Ability IDs ────────────────────────────────────────────────────────────
local HINDERED        = 165972   -- tank-swap debuff
local RADIANCE_DEBUFF = 214675   -- red screen border on player
local SOLAR_FLARE     = 222475   -- Dremora Spellcaster cast bar

-- ── Fallback cast duration (ms) ───────────────────────────────────────────
local FALL_SOLAR = 2500   -- Solar Flare: empirical

-- ── Handlers ──────────────────────────────────────────────────────────────

local function handleSolarFlare(boss, ctx, alerts, abilityId, sourceUnitName, ...)
    local dur = CastDur.get(SOLAR_FLARE, FALL_SOLAR)
    CA.melee(abilityId, sourceUnitName or "Solar Flare", dur, Colors.AMBER)
end

local function handleHindered(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        alerts:showAction(Lang.t("lc_swap_hindered"))
        CA.alert(nil, Lang.t("lc_hindered_alert"), 0x4488FFD9, SOUNDS.NONE, 5000)
    end
end

local function handleRadianceGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(true, 8000, "red")
end

local function handleRadianceFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(false, 0, "red")
end

-- ── Shared entries ────────────────────────────────────────────────────────

LCCommon.beginCastEntries = {
    [SOLAR_FLARE] = { type = AlertTypes.CUSTOM, fn = handleSolarFlare },
}

LCCommon.effectChangedEntries = {
    gained = {
        [HINDERED]        = { type = AlertTypes.CUSTOM, fn = handleHindered },
        [RADIANCE_DEBUFF] = { type = AlertTypes.CUSTOM, fn = handleRadianceGained },
    },
    faded = {
        [RADIANCE_DEBUFF] = { type = AlertTypes.CUSTOM, fn = handleRadianceFaded },
    },
}

package.loaded["trial.lc.LCCommon"] = LCCommon
return LCCommon
