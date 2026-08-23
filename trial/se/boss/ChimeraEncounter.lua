local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local VIVIFY           = 186000   -- Chimera spawns (EFFECT_FADED)
local PETRIFY          = 185039   -- Chimera despawns (EFFECT_GAINED_DURATION)
local CHAIN_LIGHTNING  = 183858   -- Chain Lightning (BEGIN + hitValue>1000)
local CIRCUIT_CHARGE   = 199235   -- Debuff from chain lightning hit
local CHIMERA_BOLT     = 186960   -- Lightning bolt (BEGIN + hitValue>500)
local CHIMERA_MAUL     = 186937   -- Chimera maul (heavy attack)
local CHIMERA_INFERNO  = 186948   -- Chimera inferno cast
local GRYPHON_WIND_LANCE = 199132 -- Gryphon Wind Lance (BEGIN)
local WAMASU_STORM     = 199119   -- Wamasu Impending Storm
local WAMASU_REPULSION = 186995   -- Wamasu Repulsion Shock
local MANTLE_WAMASU    = 184984   -- Player portal buff — green
local MANTLE_LION      = 184983   -- Player portal buff — red
local MANTLE_GRYPHON   = 183640   -- Player portal buff — blue

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local DESPAWN_CD           = 92   -- Chimera despawns ~92s after spawn
local CHAIN_FIRST_CD       =  5   -- first chain lightning after spawn
local CHAIN_CD             = 20   -- subsequent chain lightning CD

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_LIGHTNING = { -3, 0, false, { 1, 0.84, 0.4, 0.4 }, { 1, 0.84, 0.4, 0.8 } }  -- yellow

local ChimeraEncounter = {

    key               = "chimera",
    nameAliases       = { "Chimera" },
    hmHealthThreshold = 70000000,   -- vet ~46.5M, HM ~93.1M
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
ChimeraEncounter.despawnTimer = Timer.new(DESPAWN_CD)
ChimeraEncounter.chainTimer   = Timer.new(CHAIN_CD)

-- ── State ─────────────────────────────────────────────────────────────────
ChimeraEncounter.chimeraActive    = false
ChimeraEncounter.firstChain       = true
ChimeraEncounter.alertList        = {}

function ChimeraEncounter:reset()
    self.despawnTimer:clear()
    self.chainTimer:clear()
    self.chimeraActive = false
    self.firstChain    = true
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    self.alertList = {}
end

function ChimeraEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    -- ── Chimera spawn / despawn ───────────────────────────────────────────
    if abilityId == VIVIFY and result == ACTION_RESULT_EFFECT_FADED then
        self.chimeraActive = true
        self.firstChain    = true
        self.despawnTimer:reset(DESPAWN_CD)
        self.chainTimer:reset(CHAIN_FIRST_CD)
        alerts:showHeader("Chimera spawned!")

    elseif abilityId == PETRIFY and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.chimeraActive = false
        self.despawnTimer:clear()
        self.chainTimer:clear()
        alerts:showAction("Chimera despawning…")

    -- ── Chimera abilities ─────────────────────────────────────────────────
    elseif abilityId == CHAIN_LIGHTNING and result == ACTION_RESULT_BEGIN then
        self.firstChain = false
        self.chainTimer:reset(CHAIN_CD)
        alerts:showAction("Chain Lightning!")
        CA.alert(nil, "CHAIN LIGHTNING", 0xFFD666FF, SOUNDS.NONE, 2500)

    elseif abilityId == CHIMERA_BOLT and result == ACTION_RESULT_BEGIN then
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Lightning Bolt → " .. target)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        local cid = CA.alertCast(abilityId, "Bolt!", dur, COL_LIGHTNING)
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == GRYPHON_WIND_LANCE and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Wind Lance! Move!")
        CA.alert(nil, "WIND LANCE", 0xD1F1F9FF, SOUNDS.NONE, 2000)

    -- ── Portal mantle buffs (player assigned to a portal) ─────────────────
    elseif abilityId == MANTLE_WAMASU and result == ACTION_RESULT_EFFECT_GAINED
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Wamasu Portal (Green)!")
        CA.alert(nil, "WAMASU PORTAL", 0x02FF00FF, SOUNDS.NONE, 4000)

    elseif abilityId == MANTLE_LION and result == ACTION_RESULT_EFFECT_GAINED
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Lion Portal (Red)!")
        CA.alert(nil, "LION PORTAL", 0xFF0000FF, SOUNDS.NONE, 4000)

    elseif abilityId == MANTLE_GRYPHON and result == ACTION_RESULT_EFFECT_GAINED
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Gryphon Portal (Blue)!")
        CA.alert(nil, "GRYPHON PORTAL", 0x0044FFFF, SOUNDS.NONE, 4000)
    end
end

function ChimeraEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- No additional effect tracking needed.
end

function ChimeraEncounter:onUpdate(context, alerts)
    -- Line 1: Despawn countdown (only when Chimera is active)
    if self.chimeraActive then
        local rd = self.despawnTimer:remaining()
        alerts:showInfo(1, "Despawn: " .. (rd > 0 and ZO_FormatCountdownTimer(rd) or "imminent"))
    else
        alerts:showInfo(1, "")
    end

    -- Line 2: Chain Lightning CD
    if self.chimeraActive then
        local rc = self.chainTimer:remaining()
        alerts:showInfo(2, "Chain Ltng: " .. (rc > 0 and ZO_FormatCountdownTimer(rc) or "ready"))
    else
        alerts:showInfo(2, "")
    end

    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

function ChimeraEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- No HP milestone logic for Chimera.
end

return ChimeraEncounter
