local Timer = {}
Timer.__index = Timer

--- Creates a new countdown timer with a default duration in seconds.
--- The timer starts in an expired state  -  call :reset() to arm it.
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

--- Alias for reset()  -  preferred name in new boss code.
Timer.start = Timer.reset

--- Seconds remaining until the timer fires.  Returns 0 (not negative)
--- once the timer has expired, so callers can safely display the value.
--- Returns a float  -  ZO_FormatCountdownTimer and string.format("%.0f") both
--- accept fractional seconds, giving sub-second accuracy for urgent timers.
function Timer:remaining()
    local r = self.expiresAt - GetGameTimeMilliseconds() / 1000
    return r > 0 and r or 0
end

--- True once the timer has fired (expiresAt has passed).
--- Note: also returns true for unarmed timers (expiresAt == 0 is in the past).
--- Use isActive() to distinguish "running" from "never started".
function Timer:isExpired()
    return GetGameTimeMilliseconds() / 1000 >= self.expiresAt
end

--- True while the timer has been armed and has not yet fired.
--- This is the primary display-loop predicate: show the countdown only
--- when isActive() is true; hide it when idle (never started) or expired.
function Timer:isActive()
    local e = self.expiresAt
    return e > 0 and GetGameTimeMilliseconds() / 1000 < e
end

--- True when the timer has never been started or was explicitly cleared.
--- Useful to distinguish "not yet armed" from "expired" in display loops:
---   isIdle()    -> expiresAt == 0 (unarmed, never seen an event)
---   isActive()  -> armed and countdown is still running
---   isExpired() -> was armed but time has passed (note: also true when idle)
function Timer:isIdle()
    return self.expiresAt == 0
end

--- Reset the timer to the expired/unarmed state (expiresAt = 0).
--- Call this instead of poking the field directly.
function Timer:clear()
    self.expiresAt = 0
end

--- Raw game-time second at which this timer fires (fractional).
--- Exposed for legacy syncing where callers need the raw timestamp
--- (e.g. BSCHTKA.GRYPHON_TIME).  Prefer :remaining()/:isExpired() in
--- new code  -  they're clearer and don't need caller-side arithmetic.
function Timer:getExpiresAt()
    return self.expiresAt
end

package.loaded["lib.Timer"] = Timer
return Timer
