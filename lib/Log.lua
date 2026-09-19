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

--- Always emitted to chat, no tag suffix.  Use for user-facing confirmations
--- from slash commands (toggle state, help text, position saves) where the
--- "[warn]" suffix of Log.always would be misleading.
function Log.print(template, ...)
    d(PREFIX .. string.format(template, ...))
end

-- -- Verbose alert tracing ---------------------------------------------------
-- Controlled by Settings.verboseDebug (separate from the debug flag).
-- EventDispatcher sets the dispatch context before each lookupAndRun so that
-- CA and AlertSink log lines know which bucket and ability triggered them.

local _verbose    = false
local _vBucket    = nil
local _vAbilityId = 0

function Log.setVerbose(value)
    _verbose = value == true
end

function Log.isVerbose()
    return _verbose
end

--- Set by EventDispatcher before each dispatch so CA/AlertSink can annotate
--- their log lines with the triggering bucket and ability.
function Log.setDispatchContext(abilityId, bucket)
    _vAbilityId = abilityId or 0
    _vBucket    = bucket
end

--- Emit one verbose alert line when verboseDebug is enabled.
---   incha - [timestamp][abilityId][bucket][dur] message
--- abilityId: the ability (defaults to last dispatch context if nil).
--- durMs: display duration in ms; nil emits "action" for text-only alerts.
function Log.verboseAlert(abilityId, durMs, message)
    if not _verbose then return end
    local ts  = GetGameTimeMilliseconds and GetGameTimeMilliseconds() or 0
    local id  = abilityId or _vAbilityId
    local bkt = _vBucket or "?"
    local dur = durMs and string.format("%.1fs", durMs / 1000) or "action"
    d(string.format("incha - [%d][%d][%s][%s] %s", ts, id, bkt, dur, tostring(message or "")))
end

package.loaded["lib.Log"] = Log
return Log
