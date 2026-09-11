local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Colors          = require("core.Colors")

-- -- Ability IDs --------------------------------------------------------------------
local SUNBURST        = 199344
local WRACK           = 184621
local WRATHSTORM      = 198759
local CALAMITY        = 186728
local EXECUTE         = 198797
-- Poisoned Mind  -  5 variants
local POISONED_MIND_1 = 184707
local POISONED_MIND_2 = 184709
local POISONED_MIND_3 = 199644
local POISONED_MIND_4 = 184711
local POISONED_MIND_5 = 184710
-- Manic Phobia  -  4 variants
local MANIC_PHOBIA_1  = 185117
local MANIC_PHOBIA_2  = 185123
local MANIC_PHOBIA_3  = 185171
local MANIC_PHOBIA_4  = 185251
-- Enraged Atronachs
local ENRAGED_INFERNO = 183778
local ENRAGED_FLARE   = 183784
-- Phase transitions
local THE_RITUAL      = 183855
local BREAKDOWN_RED   = 188766
local BREAKDOWN_BLUE  = 188768
local BREAKDOWN_GREEN = 188769

-- -- Timer durations (seconds) -----------------------------------------------------
local CALAMITY_FIRST_CD = 9
local CALAMITY_CD       = 25

local FALLBACK_SUNBURST_DUR   = 2000
local FALLBACK_WRATHSTORM_DUR = 4000

local AnsuulEncounter = {}
AnsuulEncounter.__index = AnsuulEncounter

AnsuulEncounter.key               = "ansuul"
AnsuulEncounter.nameAliases       = { "Ansuul the Tormentor" }
AnsuulEncounter.hmHealthThreshold = 100000000

AnsuulEncounter.stateSchema = {
    calamityTimer = function() return Timer.new(CALAMITY_CD) end,
    firstCalamity = true,
    inMaze        = false,
    inTriplet     = false,
    alertList     = function() return {} end,
}

function AnsuulEncounter.new()
    return BossBase.fromSchema(AnsuulEncounter)
end

function AnsuulEncounter:onLeave(context)
    self:cleanupAlertList()
end

function AnsuulEncounter:onWipe(context, alerts)
    self:cleanupAlertList()
    self.calamityTimer:clear()
    self.firstCalamity = true
    self.inMaze        = false
    self.inTriplet     = false
    CA.border(false, 0, "green")
end

-- -- Handlers: beginCast ------------------------------------------------------------

local function handleCalamity(boss, ctx, alerts, abilityId, ...)
    boss.firstCalamity = false
    boss.calamityTimer:reset(CALAMITY_CD)
    alerts:showAction(Lang.t("se_ansuul_calamity_stack"))
end

local function handleWrack(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_ansuul_kite_wrack"))
    CA.alert(nil, Lang.t("se_ansuul_kite_alert"), 0xFFD666FF, SOUNDS.NONE, 3000)
end

local function handleExecute(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_ansuul_interrupt_exec"))
    CA.alert(nil, Lang.t("common_interrupt"), 0xFF0033FF, SOUNDS.NONE, 2500)
end

local function handleSunburst(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_ansuul_sunburst"))
    local dur = CastDur.get(SUNBURST, FALLBACK_SUNBURST_DUR)
    CA.ranged(SUNBURST, Lang.t("se_ansuul_sunburst_bar"), dur, Colors.VOID)
end

local function handleWrathstorm(boss, ctx, alerts, abilityId, ...)
    local dur = CastDur.get(WRATHSTORM, FALLBACK_WRATHSTORM_DUR)
    CA.ranged(WRATHSTORM, Lang.t("se_ansuul_wrathstorm_bar"), dur, Colors.VOID)
end

local function handleEnragedInferno(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_ansuul_interrupt_inf"))
    CA.alert(nil, Lang.t("se_ansuul_inferno_alert"), 0xFF0033FF, SOUNDS.NONE, 2500)
end

local function handleEnragedFlare(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_ansuul_enraged_flare", target))
    CA.alert(nil, Lang.t("se_ansuul_flare_alert"), 0xFF6600FF, SOUNDS.NONE, 2500)
end

-- -- Handlers: combatEvent.other ---------------------------------------------------
-- combatEvent sig: (boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)

-- POISONED_MIND fires as EFFECT_GAINED_DURATION (combat path) → combatEvent.other
local function handlePoisonedMind(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_ansuul_poisoned_mind"))
    CA.border(true, 8000, "green")
end

-- MANIC_PHOBIA fires as EFFECT_GAINED_DURATION (combat path) → combatEvent.other
local function handleManicPhobia(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local name = IsUnitPlayer(unitTag) and Lang.t("common_you") or (unitName or "?")
    alerts:showAction(Lang.t("se_ansuul_manic_phobia", name))
    if IsUnitPlayer(unitTag) then
        CA.alert(nil, Lang.t("se_ansuul_manic_alert"), 0xFF44FFFF, SOUNDS.NONE, 5000)
    end
end

-- THE_RITUAL fires as both EFFECT_GAINED_DURATION and EFFECT_FADED via combat path.
-- Both go to combatEvent.other; use boolean state to distinguish which fired.
local function handleTheRitual(boss, ctx, alerts, abilityId, ...)
    if not boss.inMaze then
        -- EFFECT_GAINED_DURATION: entering maze
        boss.inMaze = true
        alerts:showHeader(Lang.t("se_ansuul_maze_header"))
    else
        -- EFFECT_FADED: maze cleared
        boss.inMaze = false
        boss.firstCalamity = true
        boss.calamityTimer:reset(CALAMITY_FIRST_CD)
        alerts:showAction(Lang.t("se_ansuul_maze_cleared"))
    end
end

-- BREAKDOWN fires as both EFFECT_GAINED and EFFECT_FADED via combat path.
-- Both go to combatEvent.other; use boolean state to distinguish which fired.
local function handleBreakdown(boss, ctx, alerts, abilityId, ...)
    if not boss.inTriplet then
        -- EFFECT_GAINED: entering triplet split phase
        boss.inTriplet = true
        boss.firstCalamity = true
        boss.calamityTimer:reset(CALAMITY_FIRST_CD)
        alerts:showHeader(Lang.t("se_ansuul_triplet_header"))
    else
        -- EFFECT_FADED: triplet split ended
        boss.inTriplet = false
        boss.firstCalamity = true
        boss.calamityTimer:reset(CALAMITY_CD)
        alerts:showAction(Lang.t("se_ansuul_triplet_ended"))
    end
end

-- -- Event tables ------------------------------------------------------------------

local _beginCastEntry = {
    [CALAMITY]        = { type = AlertTypes.CUSTOM, fn = handleCalamity },
    [WRACK]           = { type = AlertTypes.CUSTOM, fn = handleWrack },
    [EXECUTE]         = { type = AlertTypes.CUSTOM, fn = handleExecute },
    [SUNBURST]        = { type = AlertTypes.CUSTOM, fn = handleSunburst },
    [WRATHSTORM]      = { type = AlertTypes.CUSTOM, fn = handleWrathstorm },
    [ENRAGED_INFERNO] = { type = AlertTypes.CUSTOM, fn = handleEnragedInferno },
    [ENRAGED_FLARE]   = { type = AlertTypes.CUSTOM, fn = handleEnragedFlare },
}

local _combatOtherEntry = {
    [POISONED_MIND_1] = { type = AlertTypes.CUSTOM, fn = handlePoisonedMind },
    [POISONED_MIND_2] = { type = AlertTypes.CUSTOM, fn = handlePoisonedMind },
    [POISONED_MIND_3] = { type = AlertTypes.CUSTOM, fn = handlePoisonedMind },
    [POISONED_MIND_4] = { type = AlertTypes.CUSTOM, fn = handlePoisonedMind },
    [POISONED_MIND_5] = { type = AlertTypes.CUSTOM, fn = handlePoisonedMind },
    [MANIC_PHOBIA_1]  = { type = AlertTypes.CUSTOM, fn = handleManicPhobia },
    [MANIC_PHOBIA_2]  = { type = AlertTypes.CUSTOM, fn = handleManicPhobia },
    [MANIC_PHOBIA_3]  = { type = AlertTypes.CUSTOM, fn = handleManicPhobia },
    [MANIC_PHOBIA_4]  = { type = AlertTypes.CUSTOM, fn = handleManicPhobia },
    [THE_RITUAL]      = { type = AlertTypes.CUSTOM, fn = handleTheRitual },
    [BREAKDOWN_RED]   = { type = AlertTypes.CUSTOM, fn = handleBreakdown },
    [BREAKDOWN_BLUE]  = { type = AlertTypes.CUSTOM, fn = handleBreakdown },
    [BREAKDOWN_GREEN] = { type = AlertTypes.CUSTOM, fn = handleBreakdown },
}

AnsuulEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = {}, faded = {}, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Info-line renderers -----------------------------------------------------------

local function showCalamityLine(self, alerts)
    if self.inMaze then
        alerts:setRow(1, Lang.t("se_ansuul_maze_no_cal"), nil)
    elseif self.inTriplet then
        local r = self.calamityTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Lang.t("se_ansuul_triplet_cal"), r)
        else
            alerts:setRow(1, Lang.t("se_ansuul_triplet_cal") .. " " .. Lang.t("se_ansuul_now"), nil)
        end
    elseif self.firstCalamity then
        alerts:setRow(1, Lang.t("se_ansuul_calamity_first"), nil)
    else
        local r = self.calamityTimer:remaining()
        if r > 0 then
            alerts:setRow(1, Lang.t("se_ansuul_calamity_label"), r)
        else
            alerts:setRow(1, Lang.t("se_ansuul_calamity_label") .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

local function showPhaseLine(self, alerts)
    if self.inTriplet then
        alerts:setRow(2, Lang.t("se_ansuul_split_phase"), nil)
    elseif self.inMaze then
        alerts:setRow(2, Lang.t("se_ansuul_navigate_maze"), nil)
    else
        alerts:clearRow(2)
    end
end

function AnsuulEncounter:onUpdate(context, alerts)
    showCalamityLine(self, alerts)
    showPhaseLine(self, alerts)
    alerts:clearRow(3)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

function AnsuulEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- No HP milestone logic for Ansuul.
end

EventDispatcher.build(AnsuulEncounter)

package.loaded["trial.se.boss.AnsuulEncounter"] = AnsuulEncounter
return AnsuulEncounter
