local Location = require("core.Location")
local Timer = require("lib.Timer")

local TOTEM_SPAWN_TIME  = 20
local GRYPHON_SPAWN_TIME = 60

local Yandir = {
    id = 1,
    key = "yandir",
    hmHealthThreshold = 72769370,
    location = Location.new(63200, 68900, 24300, 26300, 90500, 99600),
}

Yandir.totemTimer   = Timer.new(TOTEM_SPAWN_TIME)
Yandir.gryphonTimer = Timer.new(GRYPHON_SPAWN_TIME)
Yandir.bGRYPHON_SKIP      = false
Yandir.bGRYPHON_SKIP_TIME = -1
Yandir.bGRYPHON_SKIP_FAILHP = 0

function Yandir:reset(forced)
    self.totemTimer:reset()
    self.gryphonTimer:reset()
    self.bGRYPHON_SKIP      = false
    self.bGRYPHON_SKIP_TIME = -1
    self.bGRYPHON_SKIP_FAILHP = 0
    self.PosionTotemID   = -1
    self.PosionTotemIDSC = -1
    self.BTotemCall      = false

    self:syncLegacy()
end

function Yandir:syncLegacy()
    if not BSCHTKA then
        return
    end

    -- Legacy addon reads raw epoch timestamps, so expose expiresAt.
    BSCHTKA.GRYPHON_TIME         = self.gryphonTimer:getExpiresAt()
    BSCHTKA.TOTEM_TIME           = self.totemTimer:getExpiresAt()
    BSCHTKA.bGRYPHON_SKIP        = self.bGRYPHON_SKIP
    BSCHTKA.bGRYPHON_SKIP_TIME   = self.bGRYPHON_SKIP_TIME
    BSCHTKA.bGRYPHON_SKIP_FAILHP = self.bGRYPHON_SKIP_FAILHP
end

function Yandir:onEnter(context, alerts)
    context.extras.legacyFlag = "bYandir"
end

function Yandir:onPowerUpdate(context, healthPercent)
    if healthPercent < 60 and not self.gryphonTimer:isExpired() then
        if not self.bGRYPHON_SKIP then
            self.bGRYPHON_SKIP_TIME = os.time()
        end
        self.bGRYPHON_SKIP = true
    end

    if healthPercent > 60 and self.gryphonTimer:isExpired() then
        if self.bGRYPHON_SKIP_FAILHP == 0 then
            self.bGRYPHON_SKIP_FAILHP = healthPercent
        end
    end

    self:syncLegacy()
end

return Yandir
