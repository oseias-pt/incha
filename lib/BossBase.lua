--- BossBase  -  shared lifecycle mixin for boss classes that track CA cast bars.
---
--- Usage:
---   local BossBase = require("lib.BossBase")
---   local Boss = {}
---   Boss.__index = Boss
---   function Boss.new() return BossBase.fromSchema(Boss) end
---
--- fromSchema links the class to BossBase itself, so onDied and
--- cleanupAlertList resolve without each boss file having to remember
---   setmetatable(Boss, {__index = BossBase})
--- An explicit setmetatable is still honoured (fromSchema leaves any class
--- that already has a metatable alone), so existing boss files keep working.
---
--- Declare   alertList = function() return {} end   in Boss.stateSchema for
--- any boss that tracks CA cast bars.  onLeave (if the boss has extra bars
--- beyond alertList) should call
---   self:cleanupAlertList()
--- then stop those bars manually.

local CA = require("lib.CA")

local BossBase = {}
BossBase.__index = BossBase

--- Build a fresh boss instance from Boss.stateSchema.
--- Schema values that are functions are called to produce the field value
--- (so Timer.new / DebuffTracker.new / table constructors run per-instance,
--- not once at class load).  Static values are copied directly.
--- Fields initialized to nil in the original new() are simply omitted from
--- the schema  -  they remain nil by default via the metatable lookup.
--- Also links `class` to BossBase on first use when the boss file did not do
--- it explicitly.  Without this, a class that calls self:cleanupAlertList()
--- or relies on the default onDied but forgot the setmetatable line resolves
--- both to nil and throws on wipe / zone exit  -  a mistake four boss classes
--- had already made.  The guard leaves an explicitly-set metatable untouched.
function BossBase.fromSchema(class)
    if getmetatable(class) == nil then
        setmetatable(class, {__index = BossBase})
    end
    local inst = {}
    for k, v in pairs(class.stateSchema or {}) do
        inst[k] = type(v) == "function" and v() or v
    end
    return setmetatable(inst, class)
end

--- Stop tracked cast bars for both the dead unit and its killer, then
--- remove both from alertList.  Called automatically by CombatHandler when
--- ACTION_RESULT_DIED fires.  Boss overrides that need extra cleanup should
--- call this via BossBase.onDied(self, ...) or replicate the two-key pattern.
function BossBase:onDied(context, alerts,
                          unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if not self.alertList then return end
    if unitId then
        CA.castAlertsStop(self.alertList[unitId])
        self.alertList[unitId] = nil
    end
    if sourceUnitId then
        CA.castAlertsStop(self.alertList[sourceUnitId])
        self.alertList[sourceUnitId] = nil
    end
end

--- Stop all bars registered in alertList and clear the table.
--- Call this from onLeave before stopping any additional per-boss bars.
function BossBase:cleanupAlertList()
    if not self.alertList then return end
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    self.alertList = {}
end

package.loaded["lib.BossBase"] = BossBase
return BossBase
