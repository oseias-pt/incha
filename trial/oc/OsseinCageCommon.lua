--- OsseinCageCommon  -  trash-add and cross-boss mechanics for all Ossein Cage arenas.
---
--- Phase 2 (EventDispatcher):
---   Exposes OsseinCageCommon.beginCastEntries and OsseinCageCommon.effectChangedEntries
---   which each boss merges into its own event buckets.
---   .showCarrionInfo(alerts) and .reset() are retained as public helpers called from
---   each boss's onUpdate and onWipe respectively.
---
--- Hindered OSI icon: deferred  -  the unit OSI API requires in-game coordinate
--- measurement.  An alert fires for tanks instead.

local AlertTypes = require("core.AlertTypes")
local CA      = require("external-api.CombatAlerts")
local CastDur = require("lib.CastDur")
local Lang    = require("core.Lang")
local Fmt     = require("core.Fmt")
local Colors = require("core.Colors")

local OsseinCageCommon = {}

-- -- Ability IDs ------------------------------------------------------------
local HINDERED         = 165972   -- tank-swap debuff (Hindered)
local SKULLSTORM       = 236631   -- Skullmancer -> cast bar
local TOXIC_IRE        = 160007   -- Spectral Revenant -> debounced "you" alert
local CORVID_SWARM     = 236947   -- Murder Corvid -> purple screen border
local CURSED_TERRAIN   = 236571   -- Tormented Deadraiser -> green screen border
local DETONATE_SOUL_DB = 236778   -- Soul Devourer debuff on player -> cast bar + alert
local LIFE_DRAIN       = 236751   -- Soul Devourer combat hit on player -> alert

-- Both Caustic Carrion variants share the same stack-tracking logic.
local CAUSTIC_CARRION = { [240708] = true, [241089] = true }
--   240708: Trash / Boss 1 / Boss 3 portal debuff
--   241089: Boss 2 portal debuff

-- -- Debounce: Toxic Ire once per 10 s -------------------------------------
local _toxicIreLastMs = 0

-- -- Caustic Carrion: current player stack count ---------------------------
-- Stored at module level so showCarrionInfo can read it from boss:onUpdate.
local _carrionStacks = 0

-- -- Fallback cast durations (ms) ------------------------------------------
local FALL_SKULL    = 2500   -- Skullstorm: empirical
local FALL_DETONATE = 3000   -- Detonate Soul: empirical

-- -- Caustic Carrion: colour gradient (6 / 8 / 10 thresholds) --------------
local function carrionColorCode(n)
    if     n >= 10 then return "ff2222"    -- red  -  critical
    elseif n >=  8 then return "ff8800"    -- orange  -  danger
    elseif n >=  6 then return "ffcc00"    -- yellow  -  warning
    else                 return "66cc44"   -- green  -  safe
    end
end

-- -- Public: reset on wipe ---------------------------------------------------
-- Call from every OC boss onWipe so module-level state doesn't bleed into
-- the next pull.  Clears both _carrionStacks and the Toxic Ire debounce.
function OsseinCageCommon.reset()
    _carrionStacks  = 0
    _toxicIreLastMs = 0
end

-- -- Public: write Caustic Carrion info to panel line 3 --------------------
-- Call from each OC boss's onUpdate in place of alerts:clearRow(3).
function OsseinCageCommon.showCarrionInfo(alerts)
    if _carrionStacks > 0 then
        local col = carrionColorCode(_carrionStacks)
        alerts:setRow(3, Fmt.c(col, Lang.t("oc_carrion_label", _carrionStacks)), nil)
    else
        alerts:clearRow(3)
    end
end

-- -- Handlers (combat, new-style) ------------------------------------------

local function handleSkullstorm(boss, ctx, alerts, abilityId, sourceUnitName, ...)
    local dur = CastDur.get(SKULLSTORM, FALL_SKULL)
    CA.melee(abilityId, sourceUnitName or "Skullstorm", dur, Colors.VOID)
end

local function handleLifeDrain(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("oc_move_life_drain"))
    CA.alert(nil, Lang.t("oc_life_drain_alert"), 0xCC44FFD9, SOUNDS.NONE, 3000)
end

-- -- Handlers (effectChanged, new-style) ------------------------------------

local function handleHindered(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        alerts:showAction(Lang.t("oc_swap_hindered"))
        CA.alert(nil, Lang.t("oc_hindered_swap_alert"), 0x4488FFD9, SOUNDS.NONE, 5000)
    end
end

local function handleToxicIreGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local now = GetGameTimeMilliseconds()
    if now - _toxicIreLastMs >= 10000 then
        _toxicIreLastMs = now
        alerts:showAction(Lang.t("oc_toxic_ire"))
        CA.alert(nil, Lang.t("oc_toxic_ire_alert"), 0x44CC44D9, SOUNDS.NONE, 4000)
    end
end

local function handleCorvidSwarmGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(true, 8000, "purple")
end

local function handleCorvidSwarmFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(false, 0, "purple")
end

local function handleCursedTerrainGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(true, 8000, "green")
end

local function handleCursedTerrainFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    CA.border(false, 0, "green")
end

local function handleDetonateSoulGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(DETONATE_SOUL_DB, FALL_DETONATE)
    alerts:showAction(Lang.t("oc_detonate_soul"))
    CA.ranged(DETONATE_SOUL_DB, Lang.t("oc_detonate_soul_bar"), dur, Colors.FIRE)
    CA.alert(nil, Lang.t("oc_detonate_soul_bar"), 0xFF4400D9, SOUNDS.NONE, dur)
end

local function handleCarrionGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if not IsUnitPlayer(unitTag) then return end
    _carrionStacks = stackCount or (_carrionStacks + 1)
    OsseinCageCommon.showCarrionInfo(alerts)
    local s = _carrionStacks
    if s == 6 or s == 8 or s == 10 then
        local hex = s >= 10 and 0xFF2222D9 or s >= 8 and 0xFF8800D9 or 0xFFCC00D9
        CA.alert(nil, Lang.t("oc_carrion_alert", s), hex, SOUNDS.NONE, 3000)
    end
end

local function handleCarrionFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    _carrionStacks = 0
    OsseinCageCommon.showCarrionInfo(alerts)
end

-- -- Shared entries --------------------------------------------------------

OsseinCageCommon.beginCastEntries = {
    [SKULLSTORM] = { type = AlertTypes.CUSTOM, fn = handleSkullstorm },
    [LIFE_DRAIN] = { type = AlertTypes.CUSTOM, fn = handleLifeDrain },
}

local _effectGainedEntries = {
    [HINDERED]         = { type = AlertTypes.CUSTOM, fn = handleHindered },
    [TOXIC_IRE]        = { type = AlertTypes.CUSTOM, fn = handleToxicIreGained },
    [CORVID_SWARM]     = { type = AlertTypes.CUSTOM, fn = handleCorvidSwarmGained },
    [CURSED_TERRAIN]   = { type = AlertTypes.CUSTOM, fn = handleCursedTerrainGained },
    [DETONATE_SOUL_DB] = { type = AlertTypes.CUSTOM, fn = handleDetonateSoulGained },
}
local _effectFadedEntries = {
    [CORVID_SWARM]   = { type = AlertTypes.CUSTOM, fn = handleCorvidSwarmFaded },
    [CURSED_TERRAIN] = { type = AlertTypes.CUSTOM, fn = handleCursedTerrainFaded },
}
for id in pairs(CAUSTIC_CARRION) do
    _effectGainedEntries[id] = { type = AlertTypes.CUSTOM, fn = handleCarrionGained }
    _effectFadedEntries[id]  = { type = AlertTypes.CUSTOM, fn = handleCarrionFaded }
end

OsseinCageCommon.effectChangedEntries = {
    gained = _effectGainedEntries,
    faded  = _effectFadedEntries,
}

package.loaded["trial.oc.OsseinCageCommon"] = OsseinCageCommon
return OsseinCageCommon
