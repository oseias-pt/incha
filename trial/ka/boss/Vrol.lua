local Location = require("core.Location")

local NEXT_PORTAL_TIME = 45
local NEXT_CONDUIT_TIME = 40
local NEXT_FOG_TIME = 30

local Vrol = {
    id = 2,
    key = "vrol",
    hmHealthThreshold = 72769370,
    location = Location.new(110200, 118500, 24500, 29000, 65000, 78800),
}

Vrol.PORTAL_TIME = 0
Vrol.CONDUIT_TIME = 0
Vrol.FOG_TIME = 0
Vrol.bPORTAL_END = false

function Vrol:reset(forced)
    local currentTime = os.time()

    self.PORTAL_TIME = currentTime + 15
    self.CONDUIT_TIME = currentTime + NEXT_CONDUIT_TIME
    self.FOG_TIME = currentTime + NEXT_FOG_TIME
    self.bPORTAL_END = false

    if BSCHTKA and BSCHTKA.SV_ACC and BSCHTKA.SV_ACC.PORTAL_ICON_VROL then
        zo_callLater(function() BSCHTKA.AddPortalIcon() end, 3100)
    end

    self:syncLegacy()
end

function Vrol:syncLegacy()
    if not BSCHTKA then
        return
    end

    BSCHTKA.PORTAL_TIME = self.PORTAL_TIME
    BSCHTKA.CONDUIT_TIME = self.CONDUIT_TIME
    BSCHTKA.FOG_TIME = self.FOG_TIME
    BSCHTKA.bPORTAL_END = self.bPORTAL_END
end

function Vrol:onEnter(context)
    context.extras.legacyFlag = "bVrol"
end

function Vrol:onPowerUpdate(context, healthPercent)
    if healthPercent < 50 then
        self.bPORTAL_END = true
    end

    self:syncLegacy()
end

return Vrol
