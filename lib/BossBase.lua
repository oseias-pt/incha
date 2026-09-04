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

--- Schedule `fn` to run in `ms` milliseconds, tied to this boss instance.
---
--- Prefer this over a bare zo_callLater in boss code.  Trial replaces the
--- boss instance on every encounter, so a raw deferred closure outlives the
--- pull that scheduled it: it either fires into a reset raid (five "Acid
--- pool 3/5 - MOVE!" alerts through a wipe) or reads a guard flag on the
--- discarded instance rather than the live one.
---
--- Handles are recorded on the instance and cancelled by cancelPending(),
--- which Trial calls automatically on wipe and on boss exit / zone change.
--- The wrapper also drops the handle before invoking fn, so a callback that
--- has already run is never cancelled twice.
---
--- @param ms number    delay in milliseconds
--- @param fn function   called with no arguments; capture what it needs
--- @return number|nil   the zo_callLater handle, or nil if scheduling failed
function BossBase:after(ms, fn)
    self._pending = self._pending or {}
    local pending = self._pending

    local handle
    handle = zo_callLater(function()
        if handle then pending[handle] = nil end
        fn()
    end, ms)

    if handle then pending[handle] = true end
    return handle
end

--- Cancel one callback scheduled through :after(), by its handle.
--- Use this for mechanics that re-arm: store the handle, cancel the previous
--- one, schedule the next.  Safe to call with nil or an already-fired handle.
function BossBase:cancelAfter(handle)
    if not handle then return end
    zo_removeCallLater(handle)
    if self._pending then self._pending[handle] = nil end
end

--- Cancel every callback scheduled through :after() that has not yet fired.
--- Called by Trial on wipe and on boss exit; safe to call when nothing is
--- pending, and safe to call more than once.
function BossBase:cancelPending()
    local pending = self._pending
    if not pending then return end
    for handle in pairs(pending) do
        zo_removeCallLater(handle)
    end
    self._pending = nil
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
