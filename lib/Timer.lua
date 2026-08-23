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
    self.expiresAt = GetGameTimeMilliseconds() / 1000 + (duration or self.duration)
end

--- Seconds remaining until the timer fires.  Returns 0 (not negative)
--- once the timer has expired, so callers can safely display the value.
--- Returns a float — ZO_FormatCountdownTimer and string.format("%.0f") both
--- accept fractional seconds, giving sub-second accuracy for urgent timers.
function Timer:remaining()
    local r = self.expiresAt - GetGameTimeMilliseconds() / 1000
    return r > 0 and r or 0
end

--- True once the timer has fired (expiresAt has passed).
function Timer:isExpired()
    return GetGameTimeMilliseconds() / 1000 >= self.expiresAt
end

--- Reset the timer to the expired/unarmed state (expiresAt = 0).
--- Call this instead of poking the field directly.
function Timer:clear()
    self.expiresAt = 0
end

--- Raw game-time second at which this timer fires (fractional).
--- Exposed for legacy syncing where callers need the raw timestamp
--- (e.g. BSCHTKA.GRYPHON_TIME).  Prefer :remaining()/:isExpired() in
--- new code — they're clearer and don't need caller-side arithmetic.
function Timer:getExpiresAt()
    return self.expiresAt
end

return Timer
