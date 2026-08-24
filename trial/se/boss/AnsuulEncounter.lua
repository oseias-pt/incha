local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local SUNBURST         = 199344   -- BEGIN on player → alert
local WRACK            = 184621   -- BEGIN → Kite!
local WRATHSTORM       = 198759   -- AoE storm — caAlertCast
local CALAMITY         = 186728   -- BEGIN → timer reset, 25 s CD (9 s first)
local EXECUTE          = 198797   -- BEGIN → INTERRUPT!
local POISONED_MIND    = 184710   -- EFFECT_GAINED_DURATION on player → green border
local MANIC_PHOBIA     = 185117   -- fear effect on player
local THE_RITUAL       = 183855   -- Ansuul buff during maze phase
local BREAKDOWN_RED    = 188766   -- Ansuul splits — red
local BREAKDOWN_BLUE   = 188768   -- Ansuul splits — blue
local BREAKDOWN_GREEN  = 188769   -- Ansuul splits — green

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local CALAMITY_FIRST_CD = 9    -- first calamity after combat start / maze end
local CALAMITY_CD       = 25   -- subsequent calamity CD

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_VOID = { -3, 0, false, { 0.5, 0, 0.7, 0.4 }, { 0.5, 0, 0.7, 0.8 } }  -- purple

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_SUNBURST_DUR   = 2000   -- Sunburst: empirical
local FALLBACK_WRATHSTORM_DUR = 4000   -- Wrathstorm: empirical

local AnsuulEncounter = {}
AnsuulEncounter.__index = AnsuulEncounter

AnsuulEncounter.key               = "ansuul"
AnsuulEncounter.nameAliases       = { "Ansuul the Tormentor" }
AnsuulEncounter.hmHealthThreshold = 100000000  -- vet ~69M, HM ~160.7M
AnsuulEncounter.location          = Location.new(0, 0, 0, 0, 0, 0)

function AnsuulEncounter.new()
    return setmetatable({
        calamityTimer  = Timer.new(CALAMITY_CD),
        firstCalamity  = true,
        inMaze         = false,   -- TheRitual active
        inTriplet      = false,   -- Breakdown active (split phase)
        alertList      = {},
    }, AnsuulEncounter)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

-- Breakdown (split phase): shared handler for red/blue/green clones.
local function handleBreakdown(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        if not self.inTriplet then
            self.inTriplet = true
            self.firstCalamity = true
            self.calamityTimer:reset(CALAMITY_FIRST_CD)
            alerts:showHeader("TRIPLET PHASE!")
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.inTriplet = false
        self.firstCalamity = true
        self.calamityTimer:reset(CALAMITY_CD)
        alerts:showAction("Triplet ended!")
    end
end

AnsuulEncounter.combatRoutes = {
    [CALAMITY] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.firstCalamity = false
        self.calamityTimer:reset(CALAMITY_CD)
        alerts:showAction("Calamity! Stack!")
    end,
    [WRACK] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        alerts:showAction("Kite! Wrack incoming!")
        CA.alert(nil, "KITE!", 0xFFD666FF, SOUNDS.NONE, 3000)
    end,
    [EXECUTE] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        alerts:showAction("INTERRUPT! Execute!")
        CA.alert(nil, "INTERRUPT!", 0xFF0033FF, SOUNDS.NONE, 2500)
    end,
    [SUNBURST] = function(self, context, alerts, result, abilityId, unitTag, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        if not IsUnitPlayer(unitTag) then return end
        alerts:showAction("Sunburst on you! Dodge!")
        local dur = select(1, GetAbilityCastInfo(SUNBURST)) or 0
        if dur <= 0 then dur = FALLBACK_SUNBURST_DUR end
        CA.alertCast(SUNBURST, "SUNBURST", dur, COL_VOID)
    end,
    [WRATHSTORM] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        local dur = select(1, GetAbilityCastInfo(WRATHSTORM)) or 0
        if dur <= 0 then dur = FALLBACK_WRATHSTORM_DUR end
        CA.alertCast(WRATHSTORM, "Wrathstorm!", dur, COL_VOID)
    end,
    [POISONED_MIND] = function(self, context, alerts, result, abilityId,
                                unitTag, ...)
        if result ~= ACTION_RESULT_EFFECT_GAINED_DURATION then return end
        if not IsUnitPlayer(unitTag) then return end
        alerts:showAction("Poisoned Mind on you!")
        CA.border(true, 8000, "green")
    end,
    [THE_RITUAL] = function(self, context, alerts, result, abilityId, ...)
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
            self.inMaze = true
            alerts:showHeader("Maze phase!")
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.inMaze = false
            self.firstCalamity = true
            self.calamityTimer:reset(CALAMITY_FIRST_CD)
            alerts:showAction("Maze cleared! Calamity in ~9s")
        end
    end,
    [BREAKDOWN_RED]   = handleBreakdown,
    [BREAKDOWN_BLUE]  = handleBreakdown,
    [BREAKDOWN_GREEN] = handleBreakdown,
}

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Line 1: Calamity countdown — context-aware: maze suppression, triplet urgency, or normal CD.
local function showCalamityLine(self, alerts)
    if self.inMaze then
        alerts:showInfo(1, "Maze phase (no Calamity)")
    elseif self.inTriplet then
        local r = self.calamityTimer:remaining()
        alerts:showInfo(1, "TRIPLET — Calamity: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "now!"))
    elseif self.firstCalamity then
        alerts:showInfo(1, "Calamity: first ~9s")
    else
        local r = self.calamityTimer:remaining()
        alerts:showInfo(1, "Calamity: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "ready"))
    end
end

-- Line 2: Current phase label (triplet split or maze navigation).
local function showPhaseLine(self, alerts)
    if self.inTriplet then
        alerts:showInfo(2, "Split phase — equalize HP!")
    elseif self.inMaze then
        alerts:showInfo(2, "Navigate the maze")
    else
        alerts:showInfo(2, "")
    end
end

function AnsuulEncounter:onUpdate(context, alerts)
    showCalamityLine(self, alerts)
    showPhaseLine(self, alerts)
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

function AnsuulEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- No HP milestone logic for Ansuul.
end

return AnsuulEncounter
