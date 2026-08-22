local Location = require("core.Location")
local Settings = require("core.Settings")
local Timer    = require("lib.Timer")

local NEXT_PORTAL_TIME  = 45
local NEXT_CONDUIT_TIME = 40
local NEXT_FOG_TIME     = 30

local INITIAL_PORTAL_DELAY = 15  -- first portal is shorter than the recurring interval

local Vrol = {
    id = 2,
    key = "vrol",
    hmHealthThreshold = 72769370,
    location = Location.new(110200, 118500, 24500, 29000, 65000, 78800),
}

-- Timers start expired; reset() arms them when a boss encounter begins.
Vrol.portalTimer  = Timer.new(NEXT_PORTAL_TIME)
Vrol.conduitTimer = Timer.new(NEXT_CONDUIT_TIME)
Vrol.fogTimer     = Timer.new(NEXT_FOG_TIME)
Vrol.bPORTAL_END  = false

function Vrol:reset(forced)
    -- First portal always spawns sooner than the recurring interval.
    self.portalTimer:reset(INITIAL_PORTAL_DELAY)
    self.conduitTimer:reset()
    self.fogTimer:reset()
    self.bPORTAL_END = false

    if Settings.trial("ka").portalIconVrol then
        zo_callLater(function() BSCHTKA.AddPortalIcon() end, 3100)
    end

    self:syncLegacy()
end

function Vrol:syncLegacy()
    if not BSCHTKA then
        return
    end

    -- Legacy addon reads raw epoch timestamps, so expose expiresAt.
    BSCHTKA.PORTAL_TIME  = self.portalTimer:getExpiresAt()
    BSCHTKA.CONDUIT_TIME = self.conduitTimer:getExpiresAt()
    BSCHTKA.FOG_TIME     = self.fogTimer:getExpiresAt()
    BSCHTKA.bPORTAL_END  = self.bPORTAL_END
end

function Vrol:onEnter(context)
    context.extras.legacyFlag = "bVrol"
end

-- 200ms timer display — writes to info lines 1-3.
function Vrol:onUpdate(context, alerts)
    local t1 = self.fogTimer:remaining()
    local t2 = self.conduitTimer:remaining()
    local t3 = self.portalTimer:remaining()
    alerts:showInfo(1, "Fog:     " .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or "ready"))
    alerts:showInfo(2, "Conduit: " .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or "ready"))
    alerts:showInfo(3, "Portal:  " .. (t3 > 0 and ZO_FormatCountdownTimer(t3) or "ready"))
end

function Vrol:onPowerUpdate(context, healthPercent)
    if healthPercent < 50 then
        self.bPORTAL_END = true
    end

    self:syncLegacy()
end

return Vrol
