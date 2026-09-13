--- Gated debug logger.  Off by default so no d() calls leak into
--- production.  Enable via Log.setEnabled(true) during development,
--- or wire it to a SavedVariable in Settings.
---
--- Log level summary:
---
---   Log.always(template, ...)
---       ALWAYS emitted to chat.  Use for player-visible unexpected
---       conditions: runtime callback errors, unknown abilities, boss
---       detection failures, bad in-game state.  If in doubt, use
---       Log.warn() — only escalate to always() when a player genuinely
---       needs to see the message without enabling debug mode.
---
---   Log.warn(template, ...)
---       Debug-gated.  Use for developer diagnostics: load-time checks,
---       locale fallback notes, detection detail when debugging a mismatch.
---
---   Log.debug(template, ...)
---       Debug-gated.  Use for verbose per-tick or per-event tracing.
---
--- Usage:
---   local Log = require("lib.Log")
---   Log.debug("boss: %s hp: %.1f", boss.key, hp)
---   Log.warn("load-time diagnostic in %s", context.trialId)
---   Log.always("runtime error in %s: %s", boss.key, err)

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

--- Debug-gated diagnostic.  Use for developer-visible information (load-time
--- checks, locale fallback, detection detail) that players should not see
--- in production.  Enable with /incha debug.
function Log.warn(template, ...)
    if not enabled then
        return
    end
    d(PREFIX .. "[warn] " .. string.format(template, ...))
end

--- Always emitted to chat regardless of the debug flag.  Use for unexpected
--- runtime conditions that a player genuinely needs to see: callback errors,
--- unknown ability ids, missing units, detection failures.
function Log.always(template, ...)
    d(PREFIX .. "[warn] " .. string.format(template, ...))
end

package.loaded["lib.Log"] = Log
return Log
