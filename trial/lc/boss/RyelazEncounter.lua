local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local Colors          = require("core.Colors")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local BRILLIANT_ANNIHILATION = 214187
local BLEAK_ANNIHILATION     = 214203
local PORCIN_LIGHT           = 219329
local PORCIN_DARK            = 219330
local SUMMON_LIGHTWEAVER     = 218113
local SUMMON_BLACKGUARD      = 218109

local FALLBACK_DUR = 3000

local RyelazEncounter = {}
RyelazEncounter.__index = RyelazEncounter

RyelazEncounter.key               = "ryelaz"
RyelazEncounter.nameAliases       = { "Count Ryelaz", "Zilyesset" }
RyelazEncounter.hmHealthThreshold = 40000000

-- playerSide: "ryelaz" | "zilyesset" | nil
RyelazEncounter.stateSchema = {}

function RyelazEncounter.new()
    return BossBase.fromSchema(RyelazEncounter)
end

-- ── Handlers: beginCast ──────────────────────────────────────────────────
-- (Replacing makeAnnihilHandler factory with 2 individually named functions)

local function handleBrilliantAnnihilation(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_ryelaz_annihil_action"), dur, Colors.FLYZONE)
    alerts:showAction(Lang.t("lc_ryelaz_brilliant"))
end

local function handleBleakAnnihilation(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("lc_ryelaz_annihil_action"), dur, Colors.FLYZONE)
    alerts:showAction(Lang.t("lc_ryelaz_bleak"))
end

local function handleSummonLightweaver(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("lc_ryelaz_add_light"), 0xFFDD44D9, SOUNDS.DUEL_START, 5000)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleSummonBlackguard(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Lang.t("lc_ryelaz_add_dark"), 0x8844FFD9, SOUNDS.DUEL_START, 5000)
    PlaySound(SOUNDS.DUEL_START)
end

-- ── Handlers: combatEvent.other ──────────────────────────────────────────
-- PORCIN_LIGHT fires EFFECT_GAINED_DURATION (entering) and EFFECT_FADED (leaving).
-- Both results reach combatEvent.other; use boolean state toggle to distinguish.
-- combatEvent sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)

local function handlePorcinLight(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    if boss.playerSide ~= "ryelaz" then
        -- EFFECT_GAINED_DURATION: player entering Ryelaz (dark) side
        boss.playerSide = "ryelaz"
    else
        -- EFFECT_FADED: player leaving Ryelaz (dark) side
        boss.playerSide = nil
    end
end

local function handlePorcinDark(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    if boss.playerSide ~= "zilyesset" then
        -- EFFECT_GAINED_DURATION: player entering Zilyesset (light) side
        boss.playerSide = "zilyesset"
    else
        -- EFFECT_FADED: player leaving Zilyesset (light) side
        boss.playerSide = nil
    end
end

-- ── Event tables ─────────────────────────────────────────────────────────

local _beginCastEntry = {
    [BRILLIANT_ANNIHILATION] = { type = AlertTypes.CUSTOM, fn = handleBrilliantAnnihilation },
    [BLEAK_ANNIHILATION]     = { type = AlertTypes.CUSTOM, fn = handleBleakAnnihilation },
    [SUMMON_LIGHTWEAVER]     = { type = AlertTypes.CUSTOM, fn = handleSummonLightweaver },
    [SUMMON_BLACKGUARD]      = { type = AlertTypes.CUSTOM, fn = handleSummonBlackguard },
}

local _combatOtherEntry = {
    [PORCIN_LIGHT] = { type = AlertTypes.CUSTOM, fn = handlePorcinLight },
    [PORCIN_DARK]  = { type = AlertTypes.CUSTOM, fn = handlePorcinDark },
}

RyelazEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = {}, faded = {}, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

function RyelazEncounter:onWipe(context, alerts)
    self.playerSide = nil
end

function RyelazEncounter:onUpdate(context, alerts)
    if self.playerSide == "ryelaz" then
        alerts:setRow(1, Fmt.c(Fmt.AMBER, Lang.t("lc_ryelaz_side_dark")), nil)
    elseif self.playerSide == "zilyesset" then
        alerts:setRow(1, Fmt.c(Fmt.FROST, Lang.t("lc_ryelaz_side_light")), nil)
    else
        alerts:clearRow(1)
    end
end

EventDispatcher.build(RyelazEncounter)

package.loaded["trial.lc.boss.RyelazEncounter"] = RyelazEncounter
return RyelazEncounter
