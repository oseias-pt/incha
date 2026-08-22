local Location = require("core.Location")
local Settings = require("core.Settings")
local Timer    = require("lib.Timer")

local INSTABILITY_INITIAL_DELAY = 10

local Falgravn = {
    id = 3,
    key = "falgravn",
    hmHealthThreshold = 248386060,
    location = Location.new(73700, 84500, 6000, 22500, 50200, 61900),
    hideActionWhenNoRule = true,
    healthRules = {
        {
            id = "conga_90",
            min = 90,
            max = 93,
            text = "Connect Soon! (90% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI end,
        },
        {
            id = "conga_80",
            min = 80,
            max = 83,
            text = "Connect Soon! (80% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI end,
        },
        {
            id = "floor_shatter",
            min = 70,
            max = 73,
            text = "Dont Ult (Floor Shatter)! (70% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI end,
        },
        {
            id = "dont_ult",
            min = 35,
            max = 38,
            text = "Dont Ult! (35% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI and ctx.stage < 3 end,
        },
    },
}

Falgravn.CURRENT_STAGE   = 1
Falgravn.instabilityTimer = Timer.new(INSTABILITY_INITIAL_DELAY)

-- Placeholders for mechanics not yet fully migrated from the legacy addon.
-- Set to 0 until the corresponding event handlers are implemented.
Falgravn.OPEN_GATES_TIME = 0
Falgravn.TORTURER_TP     = 0
Falgravn.BLOODBALL_TIME  = 0

local PRISONERS = {
    Brekalda = 0, Thjorlak = 0, Aevar    = 0, Triveta      = 0,
    Skormgondar = 0, Irthrig = 0, Ama    = 0, Sislea       = 0,
}

local function resetPrisoners()
    for name in pairs(PRISONERS) do
        PRISONERS[name] = 0
    end
end

function Falgravn:reset(forced)
    self.CURRENT_STAGE = 1
    self.instabilityTimer:reset()
    resetPrisoners()

    if not BSCHTKA then
        return
    end

    BSCHTKAHelperInfoUI:GetNamedChild("Info1"):SetText("")
    BSCHTKAHelperInfoUI:GetNamedChild("Info2"):SetText("")
    BSCHTKAHelperInfoUI:GetNamedChild("Info3"):SetText("")
    BSCHTKAHelperInfoUI:GetNamedChild("Info4"):SetText("")

    if self.DisableAllPosIconBlood then
        self:DisableAllPosIconBlood()
    end
    if self.DisableAllPosIconConn then
        self:DisableAllPosIconConn()
    end
end

function Falgravn:onEnter(context)
    context.extras.legacyFlag    = "bFalgraven"
    context.extras.showPercentUI = Settings.trial("ka").showPercent
    context.stage                = self.CURRENT_STAGE
    self:syncLegacy()
end

-- 200ms timer display — writes to info lines 1-4 depending on stage.
--
-- instabilityTimer is a real Timer object (available now).
-- BLOODBALL_TIME / OPEN_GATES_TIME / TORTURER_TP are raw epoch timestamps
-- written by BSCHTKA's combat events; they become proper Timer objects in
-- Phase 4.1 once those event handlers are migrated.
function Falgravn:onUpdate(context, alerts)
    local stage = self.CURRENT_STAGE

    -- Info 1 — instability countdown (all stages).
    local ti = self.instabilityTimer:remaining()
    alerts:showInfo(1, "Instability: " .. (ti > 0 and ZO_FormatCountdownTimer(ti) or "up!"))

    -- Stage 2: blood ball timer (line 2).
    if stage >= 2 then
        local tbb = self.BLOODBALL_TIME > 0
                    and math.max(self.BLOODBALL_TIME - os.time(), 0) or 0
        alerts:showInfo(2, "Blood Ball: " .. (tbb > 0 and ZO_FormatCountdownTimer(tbb) or "—"))
    end

    -- Stage 3: open gates + torturer teleport timers (lines 3-4).
    if stage >= 3 then
        local tog = self.OPEN_GATES_TIME > 0
                    and math.max(self.OPEN_GATES_TIME - os.time(), 0) or 0
        local ttp = self.TORTURER_TP > 0
                    and math.max(self.TORTURER_TP - os.time(), 0) or 0
        alerts:showInfo(3, "Open Gates:   " .. (tog > 0 and ZO_FormatCountdownTimer(tog) or "—"))
        alerts:showInfo(4, "Torturer TP:  " .. (ttp > 0 and ZO_FormatCountdownTimer(ttp) or "—"))
    end
end

function Falgravn:onPowerUpdate(context)
    context.stage                = self.CURRENT_STAGE
    context.extras.showPercentUI = Settings.trial("ka").showPercent
    self:syncLegacy()
end

function Falgravn:syncLegacy()
    if not BSCHTKA then
        return
    end

    BSCHTKA.CURRENT_STAGE = self.CURRENT_STAGE
end

return Falgravn
