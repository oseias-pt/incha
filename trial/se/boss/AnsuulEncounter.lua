local Location = require("core.Location")
local Timer    = require("lib.Timer")

-- ── CombatAlerts helpers ──────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end
local function caAlertBorder(active, dur, color)
    if CombatAlerts then CombatAlerts.AlertBorder(active, dur, color) end
end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

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

local AnsuulEncounter = {
    id                = 3,
    key               = "ansuul",
    nameAliases       = { "Ansuul the Tormentor" },
    hmHealthThreshold = 100000000,  -- vet ~69M, HM ~160.7M
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
AnsuulEncounter.calamityTimer = Timer.new(CALAMITY_CD)

-- ── State ─────────────────────────────────────────────────────────────────
AnsuulEncounter.firstCalamity  = true
AnsuulEncounter.inMaze         = false    -- TheRitual active
AnsuulEncounter.inTriplet      = false    -- Breakdown active (split phase)
AnsuulEncounter.alertList      = {}

function AnsuulEncounter:reset()
    self.calamityTimer:clear()
    self.firstCalamity = true
    self.inMaze        = false
    self.inTriplet     = false
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
end

function AnsuulEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if abilityId == CALAMITY and result == ACTION_RESULT_BEGIN then
        self.firstCalamity = false
        self.calamityTimer:reset(CALAMITY_CD)
        alerts:showAction("Calamity! Stack!")

    elseif abilityId == WRACK and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Kite! Wrack incoming!")
        caAlert(nil, "KITE!", 0xFFD666FF, SOUNDS.NONE, 3000)

    elseif abilityId == EXECUTE and result == ACTION_RESULT_BEGIN then
        alerts:showAction("INTERRUPT! Execute!")
        caAlert(nil, "INTERRUPT!", 0xFF0033FF, SOUNDS.NONE, 2500)

    elseif abilityId == SUNBURST and result == ACTION_RESULT_BEGIN
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Sunburst on you! Dodge!")
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 2000 end
        caAlertCast(abilityId, "SUNBURST", dur, COL_VOID)

    elseif abilityId == WRATHSTORM and result == ACTION_RESULT_BEGIN then
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 4000 end
        caAlertCast(abilityId, "Wrathstorm!", dur, COL_VOID)

    elseif abilityId == POISONED_MIND
           and result == ACTION_RESULT_EFFECT_GAINED_DURATION
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Poisoned Mind on you!")
        caAlertBorder(true, 8000, "green")

    elseif abilityId == THE_RITUAL then
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
            self.inMaze = true
            alerts:showHeader("Maze phase!")
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.inMaze = false
            -- Reset calamity timer: first calamity comes ~9s after maze ends
            self.firstCalamity = true
            self.calamityTimer:reset(CALAMITY_FIRST_CD)
            alerts:showAction("Maze cleared! Calamity in ~9s")
        end

    elseif (abilityId == BREAKDOWN_RED or abilityId == BREAKDOWN_BLUE
            or abilityId == BREAKDOWN_GREEN) then
        if result == ACTION_RESULT_EFFECT_GAINED then
            if not self.inTriplet then
                self.inTriplet = true
                -- Red clone performs calamity; reset timer for triplet
                self.firstCalamity = true
                self.calamityTimer:reset(CALAMITY_FIRST_CD)
                alerts:showHeader("TRIPLET PHASE!")
            end
        elseif result == ACTION_RESULT_EFFECT_FADED then
            -- All three FADED events fire; only clear on last
            -- Safe to clear on any: if it fires, triplet is ending
            self.inTriplet = false
            self.firstCalamity = true
            self.calamityTimer:reset(CALAMITY_CD)
            alerts:showAction("Triplet ended!")
        end
    end
end

function AnsuulEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- No additional effect tracking beyond onCombatEvent.
end

function AnsuulEncounter:onUpdate(context, alerts)
    -- Line 1: Calamity countdown
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

    -- Line 2: Phase label
    if self.inTriplet then
        alerts:showInfo(2, "Split phase — equalize HP!")
    elseif self.inMaze then
        alerts:showInfo(2, "Navigate the maze")
    else
        alerts:showInfo(2, "")
    end

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
