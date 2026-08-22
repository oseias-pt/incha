local Location = require("core.Location")
local Timer = require("lib.Timer")

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
    context.extras.legacyFlag = "bFalgraven"
    context.extras.showPercentUI = BSCHTKA and BSCHTKA.SV_ACC and BSCHTKA.SV_ACC.SHOW_UI_PERCENT
    context.stage = self.CURRENT_STAGE
    self:syncLegacy()
end

function Falgravn:onPowerUpdate(context)
    context.stage = self.CURRENT_STAGE
    context.extras.showPercentUI = BSCHTKA and BSCHTKA.SV_ACC and BSCHTKA.SV_ACC.SHOW_UI_PERCENT
    self:syncLegacy()
end

function Falgravn:syncLegacy()
    if not BSCHTKA then
        return
    end

    BSCHTKA.CURRENT_STAGE = self.CURRENT_STAGE
end

return Falgravn
