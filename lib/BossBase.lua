--- BossBase — shared lifecycle mixin for boss classes that track CA cast bars.
---
--- Usage:
---   local BossBase = require("lib.BossBase")
---   local Boss = {}
---   Boss.__index = Boss
---   setmetatable(Boss, {__index = BossBase})   -- inherit onDied + cleanupAlertList
---
--- The boss's new() must still initialise   alertList = {}   in the instance table.
--- onLeave (if the boss has extra bars beyond alertList) should call
---   self:cleanupAlertList()
--- then stop those bars manually.

local CA = require("lib.CA")

local BossBase = {}
BossBase.__index = BossBase

--- Stop a source unit's tracked cast bar and remove it from alertList.
--- Called automatically by CombatHandler when ACTION_RESULT_DIED fires.
function BossBase:onDied(context, alerts,
                          unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if unitId and self.alertList then
        CA.castAlertsStop(self.alertList[unitId])
        self.alertList[unitId] = nil
    end
end

--- Stop all bars registered in alertList and clear the table.
--- Call this from onLeave before stopping any additional per-boss bars.
function BossBase:cleanupAlertList()
    if not self.alertList then return end
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    self.alertList = {}
end

return BossBase
