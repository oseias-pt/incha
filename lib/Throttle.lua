local Throttle = {}
Throttle.__index = Throttle

--- Bucket-change detector. shouldUpdate(value) returns true the first time
--- it's called, and again whenever `value` has moved into a different
--- bucket of size `stepSize` since the last time it returned true.
---
--- Intended for gating work that only needs to happen when a fast-firing
--- value (e.g. boss health percent, which can tick many times per second)
--- has meaningfully changed, rather than on every raw event.
function Throttle.new(stepSize)
    return setmetatable({
        stepSize = stepSize or 1,
        lastBucket = nil,
    }, Throttle)
end

function Throttle:shouldUpdate(value)
    local bucket = math.floor(value / self.stepSize)

    if bucket ~= self.lastBucket then
        self.lastBucket = bucket
        return true
    end

    return false
end

--- Forces the next shouldUpdate() call to return true regardless of value.
--- Call this whenever the thing being tracked changes identity (e.g. a new
--- boss becomes active) so a stale bucket from the previous boss doesn't
--- suppress the first real check for the new one.
function Throttle:reset()
    self.lastBucket = nil
end

package.loaded["lib.Throttle"] = Throttle
return Throttle
