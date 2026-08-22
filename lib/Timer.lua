local Timer = {}
Timer.__index = Timer

--- Creates a new countdown timer with a default duration in seconds.
--- The timer starts in an expired state — call :reset() to arm it.
function Timer.new(duration)
    return setmetatable({
        duration = duration,
        expiresAt = 0,
    }, Timer)
end

--- Arms the timer.  An optional `duration` overrides the default for this
--- reset only (useful when the first spawn has a different delay than
--- subsequent ones, e.g. Vrol's portal: 15 s initial vs 45 s recurring).
function Timer:reset(duration)
    self.expiresAt = os.time() + (duration or self.duration)
end

--- Seconds remaining until the timer fires.  Returns 0 (not negative)
--- once the timer has expired, so callers can safely display the value.
function Timer:remaining()
    local r = self.expiresAt - os.time()
    return r > 0 and r or 0
end

--- True once the timer has fired (expiresAt has passed).
function Timer:isExpired()
    return os.time() >= self.expiresAt
end

--- Raw epoch second at which this timer fires.
--- Exposed for legacy syncing where the old addon reads the raw timestamp
--- (e.g. BSCHTKA.GRYPHON_TIME).  Prefer :remaining()/:isExpired() in
--- new code — they're clearer and don't need caller-side arithmetic.
function Timer:getExpiresAt()
    return self.expiresAt
end

return Timer
