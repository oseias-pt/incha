local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Colors          = require("core.Colors")

-- -- Ability IDs --------------------------------------------------------------------
local VIVIFY           = 186000
local PETRIFY          = 185039
-- Chain Lightning  -  13 variants
local CHAIN_LIGHTNING_1  = 183858
local CHAIN_LIGHTNING_2  = 183898
local CHAIN_LIGHTNING_3  = 183911
local CHAIN_LIGHTNING_4  = 183913
local CHAIN_LIGHTNING_5  = 184033
local CHAIN_LIGHTNING_6  = 184028
local CHAIN_LIGHTNING_7  = 184036
local CHAIN_LIGHTNING_8  = 184032
local CHAIN_LIGHTNING_9  = 184029
local CHAIN_LIGHTNING_10 = 184030
local CHAIN_LIGHTNING_11 = 183915
local CHAIN_LIGHTNING_12 = 183917
local CHAIN_LIGHTNING_13 = 183885
-- Chain Circuit debuffs on players  -  4 variants
local CHAIN_CIRCUIT_1  = 184063
local CHAIN_CIRCUIT_2  = 184068
local CHAIN_CIRCUIT_3  = 184066
local CHAIN_CIRCUIT_4  = 184067
-- Arctic Shred (~5.5 s cooldown)
local ARCTIC_SHRED     = 184275
-- Sub-boss abilities
local LION_DOUBLE_STRIKE = 186969
local GRYPHON_PECK       = 187002
local CHIMERA_BOLT     = 186960
local GRYPHON_WIND_LANCE = 199132
-- Portal mantle buffs (assigned portal type on player)
local MANTLE_WAMASU    = 184984
local MANTLE_LION      = 184983
local MANTLE_GRYPHON   = 183640

-- -- Timer durations (seconds) -----------------------------------------------------
local DESPAWN_CD     = 92
local CHAIN_FIRST_CD =  5
local CHAIN_CD       = 20

local FALLBACK_DUR      = 2000
local FALLBACK_SHRED_DUR = 1500

local ChimeraEncounter = {}
ChimeraEncounter.__index = ChimeraEncounter

ChimeraEncounter.key               = "chimera"
ChimeraEncounter.nameAliases       = { "Chimera" }
ChimeraEncounter.hmHealthThreshold = 70000000

ChimeraEncounter.stateSchema = {
    despawnTimer  = function() return Timer.new(DESPAWN_CD) end,
    chainTimer    = function() return Timer.new(CHAIN_CD) end,
    chimeraActive = false,
    firstChain    = true,
    alertList     = function() return {} end,
}

function ChimeraEncounter.new()
    return BossBase.fromSchema(ChimeraEncounter)
end

function ChimeraEncounter:onLeave(context)
    self:cleanupAlertList()
end

function ChimeraEncounter:onWipe(context, alerts)
    self:cleanupAlertList()
    self.despawnTimer:clear(); self.chainTimer:clear()
    self.chimeraActive = false; self.firstChain = true
end

-- -- Handlers: beginCast ------------------------------------------------------------

local function handleChainLightning(boss, ctx, alerts, abilityId, ...)
    boss.firstChain = false
    boss.chainTimer:reset(CHAIN_CD)
    alerts:showAction(Lang.t("se_chimera_chain_lightning"))
    CA.alert(nil, Lang.t("se_chimera_chain_lightning_alert"), 0xFFD666FF, SOUNDS.NONE, 2500)
end

local function handleArcticShred(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_chimera_arctic_shred", target))
    local dur = CastDur.get(abilityId, FALLBACK_SHRED_DUR)
    CA.ranged(abilityId, Lang.t("se_chimera_arctic_shred_bar"), dur, Colors.ICE)
end

local function handleLionDoubleStrike(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_chimera_lion_double_bar"), dur, Colors.ORANGE)
    alerts:showAction(Lang.t("se_chimera_lion_double"))
end

local function handleGryphonPeck(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_chimera_gryphon_peck_bar"), dur, Colors.ICE)
    alerts:showAction(Lang.t("se_chimera_gryphon_peck"))
end

local function handleChimeraBolt(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_chimera_lightning_bolt", target))
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    local cid = CA.ranged(abilityId, Lang.t("se_chimera_bolt_bar"), dur, Colors.GOLD)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleGryphonWindLance(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_chimera_wind_lance"))
    CA.alert(nil, Lang.t("se_chimera_wind_lance_alert"), 0xD1F1F9FF, SOUNDS.NONE, 2000)
end

-- -- Handlers: combatEvent.other ---------------------------------------------------
-- combatEvent sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)

-- VIVIFY fires as EFFECT_FADED (combat path) → combatEvent.other
local function handleVivify(boss, ctx, alerts, abilityId, ...)
    boss.chimeraActive = true
    boss.firstChain    = true
    boss.despawnTimer:reset(DESPAWN_CD)
    boss.chainTimer:reset(CHAIN_FIRST_CD)
    alerts:showHeader(Lang.t("se_chimera_header"))
end

-- PETRIFY fires as EFFECT_GAINED_DURATION (combat path) → combatEvent.other
local function handlePetrify(boss, ctx, alerts, abilityId, ...)
    boss.chimeraActive = false
    boss.despawnTimer:clear()
    boss.chainTimer:clear()
    alerts:showAction(Lang.t("se_chimera_despawning"))
end

-- CHAIN_CIRCUIT fires as EFFECT_GAINED_DURATION (combat path) → combatEvent.other
local function handleChainCircuit(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_chimera_chain_circuit"))
    CA.alert(nil, Lang.t("se_chimera_chain_circuit_alert"), 0xFFD666FF, SOUNDS.NONE, 3000)
end

-- Portal mantle buffs: EFFECT_GAINED (combat path) → combatEvent.other
-- (Replacing makePortalHandler factory with 3 individually named functions)
local function handleMantleWamasu(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local label = Lang.t("se_chimera_portal_wamasu")
    alerts:showAction(label .. "!")
    CA.alert(nil, label, 0x02FF00FF, SOUNDS.NONE, 4000)
end

local function handleMantleLion(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local label = Lang.t("se_chimera_portal_lion")
    alerts:showAction(label .. "!")
    CA.alert(nil, label, 0xFF0000FF, SOUNDS.NONE, 4000)
end

local function handleMantleGryphon(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local label = Lang.t("se_chimera_portal_gryphon")
    alerts:showAction(label .. "!")
    CA.alert(nil, label, 0x0044FFFF, SOUNDS.NONE, 4000)
end

-- -- Event tables ------------------------------------------------------------------

local _beginCastEntry = {
    [CHAIN_LIGHTNING_1]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_2]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_3]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_4]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_5]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_6]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_7]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_8]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_9]  = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_10] = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_11] = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_12] = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [CHAIN_LIGHTNING_13] = { type = AlertTypes.CUSTOM, fn = handleChainLightning },
    [ARCTIC_SHRED]       = { type = AlertTypes.CUSTOM, fn = handleArcticShred },
    [LION_DOUBLE_STRIKE] = { type = AlertTypes.CUSTOM, fn = handleLionDoubleStrike },
    [GRYPHON_PECK]       = { type = AlertTypes.CUSTOM, fn = handleGryphonPeck },
    [CHIMERA_BOLT]       = { type = AlertTypes.CUSTOM, fn = handleChimeraBolt },
    [GRYPHON_WIND_LANCE] = { type = AlertTypes.CUSTOM, fn = handleGryphonWindLance },
}

local _combatOtherEntry = {
    [VIVIFY]         = { type = AlertTypes.CUSTOM, fn = handleVivify },
    [PETRIFY]        = { type = AlertTypes.CUSTOM, fn = handlePetrify },
    [CHAIN_CIRCUIT_1]= { type = AlertTypes.CUSTOM, fn = handleChainCircuit },
    [CHAIN_CIRCUIT_2]= { type = AlertTypes.CUSTOM, fn = handleChainCircuit },
    [CHAIN_CIRCUIT_3]= { type = AlertTypes.CUSTOM, fn = handleChainCircuit },
    [CHAIN_CIRCUIT_4]= { type = AlertTypes.CUSTOM, fn = handleChainCircuit },
    [MANTLE_WAMASU]  = { type = AlertTypes.CUSTOM, fn = handleMantleWamasu },
    [MANTLE_LION]    = { type = AlertTypes.CUSTOM, fn = handleMantleLion },
    [MANTLE_GRYPHON] = { type = AlertTypes.CUSTOM, fn = handleMantleGryphon },
}

ChimeraEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = {}, faded = {}, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Info-line renderers -----------------------------------------------------------

local function showChimeraLines(self, alerts)
    if self.chimeraActive then
        local rd = self.despawnTimer:remaining()
        local rc = self.chainTimer:remaining()
        if rd > 0 then
            alerts:setRow(1, Lang.t("se_chimera_despawn_label"), rd)
        else
            alerts:setRow(1, Lang.t("se_chimera_despawn_label") .. " " .. Lang.t("common_imminent"), nil)
        end
        if rc > 0 then
            alerts:setRow(2, Lang.t("se_chimera_chain_label"), rc)
        else
            alerts:setRow(2, Lang.t("se_chimera_chain_label") .. " " .. Lang.t("common_ready"), nil)
        end
    else
        alerts:clearRow(1)
        alerts:clearRow(2)
    end
end

function ChimeraEncounter:onUpdate(context, alerts)
    showChimeraLines(self, alerts)
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

function ChimeraEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- No HP milestone logic for Chimera.
end

EventDispatcher.build(ChimeraEncounter)

package.loaded["trial.se.boss.ChimeraEncounter"] = ChimeraEncounter
return ChimeraEncounter
