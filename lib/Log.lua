--- Gated debug logger.  Off by default so no d() calls leak into
--- production.  Enable via Log.setEnabled(true) during development,
--- or wire it to a SavedVariable in Phase 2 (Settings).
---
--- Usage:
---   local Log = require("lib.Log")
---   Log.debug("boss: %s hp: %.1f", boss.key, hp)
---   Log.warn("unexpected state in %s", context.trialId)

local Log = {}

local enabled = false
local PREFIX = "[Incha] "

function Log.setEnabled(value)
    enabled = value == true
end

function Log.isEnabled()
    return enabled
end

--- Formatted debug message.  Uses string.format() so callers can write
--- Log.debug("hp: %.1f stage: %d", hp, stage) instead of concatenating.
function Log.debug(template, ...)
    if not enabled then
        return
    end
    d(PREFIX .. string.format(template, ...))
end

--- Same as debug but survives a future "warn-only" mode where debug is
--- suppressed.  Warn if something is unexpected but not fatal.
function Log.warn(template, ...)
    if not enabled then
        return
    end
    d(PREFIX .. "[WARN] " .. string.format(template, ...))
end

package.loaded["lib.Log"] = Log
return Log
