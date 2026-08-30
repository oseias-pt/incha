local Timer    = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- â”€â”€ Ability IDs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local VIVIFY           = 186000   -- combatRoute: ACTION_RESULT_EFFECT_FADED â†’ Chimera spawned, reset timers
local PETRIFY          = 185039   -- combatRoute: ACTION_RESULT_EFFECT_GAINED_DURATION â†’ despawning, clear timers
local CHAIN_LIGHTNING  = 183858   -- combatRoute: ACTION_RESULT_BEGIN â†’ Chain Lightning alert, reset chainTimer
local CIRCUIT_CHARGE   = 199235   -- (dead constant â€” no route registered)
local CHIMERA_BOLT     = 186960   -- combatRoute: ACTION_RESULT_BEGIN â†’ Bolt caAlertCast (targeted)
local CHIMERA_MAUL     = 186937   -- (dead constant â€” no route registered)
local CHIMERA_INFERNO  = 186948   -- (dead constant â€” no route registered)
local GRYPHON_WIND_LANCE = 199132 -- combatRoute: ACTION_RESULT_BEGIN â†’ Wind Lance alert
local WAMASU_STORM     = 199119   -- (dead constant â€” no route registered)
local WAMASU_REPULSION = 186995   -- (dead constant â€” no route registered)
local MANTLE_WAMASU    = 184984   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ Wamasu portal (makePortalHandler)
local MANTLE_LION      = 184983   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ Lion portal (makePortalHandler)
local MANTLE_GRYPHON   = 183640   -- combatRoute: ACTION_RESULT_EFFECT_GAINED â†’ Gryphon portal (makePortalHandler)

-- â”€â”€ Timer durations (seconds) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local DESPAWN_CD           = 92   -- Chimera despawns ~92s after spawn
local CHAIN_FIRST_CD       =  5   -- first chain lightning after spawn
local CHAIN_CD             = 20   -- subsequent chain lightning CD

-- â”€â”€ CA colour palettes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local COL_LIGHTNING = { -3, 0, false, { 1, 0.84, 0.4, 0.4 }, { 1, 0.84, 0.4, 0.8 } }  -- yellow

-- â”€â”€ Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) â”€
local FALLBACK_DUR = 2000   -- Lightning Bolt: empirical

local ChimeraEncounter = {}
ChimeraEncounter.__index = ChimeraEncounter

ChimeraEncounter.key               = "chimera"
ChimeraEncounter.nameAliases       = { "Chimera" }
ChimeraEncounter.hmHealthThreshold = 70000000   -- vet ~46.5M, HM ~93.1M
-- location: placeholder â€” Sunken Elder arena AABB not yet captured.
-- Detection falls back to nameAliases (name-based, may fail on non-EN clients).
-- To calibrate: stand in arena, run /script d(GetUnitWorldPosition("boss1"))

ChimeraEncounter.stateSchema = {
    despawnTimer   = function() return Timer.new(DESPAWN_CD) end,
    chainTimer     = function() return Timer.new(CHAIN_CD) end,
    chimeraActive  = false,
    firstChain     = true,
    alertList      = function() return {} end,
}

function ChimeraEncounter.new()
    return BossBase.fromSchema(ChimeraEncounter)
end

-- â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function ChimeraEncounter:onLeave(context)
    self:cleanupAlertList()
end

function ChimeraEncounter:onWipe()
    self:cleanupAlertList()
    self.despawnTimer:clear(); self.chainTimer:clear()
    self.chimeraActive = false; self.firstChain = true
end

-- â”€â”€ Handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Portal mantle: personal alert when assigned to a portal.
local function makePortalHandler(color, label, colorHex)
    return { result = ACTION_RESULT_EFFECT_GAINED,
        fn = function(self, context, alerts, abilityId, unitTag, ...)
        if not IsUnitPlayer(unitTag) then return end
        alerts:showAction(label .. "!")
        CA.alert(nil, label, colorHex, SOUNDS.NONE, 4000)
    end }
end

local function handleVivify(self, context, alerts, abilityId, ...)
    self.chimeraActive = true
    self.firstChain    = true
    self.despawnTimer:reset(DESPAWN_CD)
    self.chainTimer:reset(CHAIN_FIRST_CD)
    alerts:showHeader("Chimera spawned!")
end

local function handlePetrify(self, context, alerts, abilityId, ...)
    self.chimeraActive = false
    self.despawnTimer:clear()
    self.chainTimer:clear()
    alerts:showAction("Chimera despawningâ€¦")
end

local function handleChainLightning(self, context, alerts, abilityId, ...)
    self.firstChain = false
    self.chainTimer:reset(CHAIN_CD)
    alerts:showAction("Chain Lightning!")
    CA.alert(nil, "CHAIN LIGHTNING", 0xFFD666FF, SOUNDS.NONE, 2500)
end

local function handleChimeraBolt(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction("Lightning Bolt â†’ " .. target)
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    local cid = CA.alertCast(abilityId, "Bolt!", dur, COL_LIGHTNING)
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleGryphonWindLance(self, context, alerts, abilityId, ...)
    alerts:showAction("Wind Lance! Move!")
    CA.alert(nil, "WIND LANCE", 0xD1F1F9FF, SOUNDS.NONE, 2000)
end

-- â”€â”€ Routing tables (C3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

ChimeraEncounter.combatRoutes = {
    [VIVIFY]             = { result = ACTION_RESULT_EFFECT_FADED,          fn = handleVivify },
    [PETRIFY]            = { result = ACTION_RESULT_EFFECT_GAINED_DURATION, fn = handlePetrify },
    [CHAIN_LIGHTNING]    = { result = ACTION_RESULT_BEGIN,                  fn = handleChainLightning },
    [CHIMERA_BOLT]       = { result = ACTION_RESULT_BEGIN,                  fn = handleChimeraBolt },
    [GRYPHON_WIND_LANCE] = { result = ACTION_RESULT_BEGIN,                  fn = handleGryphonWindLance },
    -- Portal mantle buffs (factory entries â€” EXEMPT from D7)
    [MANTLE_WAMASU]  = makePortalHandler("green", "Wamasu Portal (Green)", 0x02FF00FF),
    [MANTLE_LION]    = makePortalHandler("red",   "Lion Portal (Red)",     0xFF0000FF),
    [MANTLE_GRYPHON] = makePortalHandler("blue",  "Gryphon Portal (Blue)", 0x0044FFFF),
}

-- â”€â”€ Info-line renderers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Lines 1-2: Chimera despawn countdown and Chain Lightning CD; cleared when inactive.
local function showChimeraLines(self, alerts)
    if self.chimeraActive then
        local rd = self.despawnTimer:remaining()
        local rc = self.chainTimer:remaining()
        alerts:showInfo(1, "Despawn: " .. (rd > 0 and ZO_FormatCountdownTimer(rd) or "imminent"))
        alerts:showInfo(2, "Chain Ltng: " .. (rc > 0 and ZO_FormatCountdownTimer(rc) or "ready"))
    else
        alerts:showInfo(1, "")
        alerts:showInfo(2, "")
    end
end

function ChimeraEncounter:onUpdate(context, alerts)
    showChimeraLines(self, alerts)
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

function ChimeraEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- No HP milestone logic for Chimera.
end

package.loaded["trial.se.boss.ChimeraEncounter"] = ChimeraEncounter
return ChimeraEncounter
