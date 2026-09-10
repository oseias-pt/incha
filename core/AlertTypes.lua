--- core/AlertTypes.lua  -  Alert type enum.
---
--- The single source of truth for alert type *names*.  Boss event tables,
--- the EventDispatcher, and tests all reference types through this module so
--- a typo produces a load-time error rather than a silent no-op at runtime.
---
---   local AlertTypes = require("core.AlertTypes")
---
---   Boss.events = {
---     beginCast = {
---       instant = {
---         [ABILITY_ID] = { type = AlertTypes.DODGE, text = "Dodge!", ... },
---       },
---     },
---   }
---
--- The dispatcher calls AlertTypes.isValid(entry.type) during EventDispatcher.build()
--- and asserts on any unrecognised string.

local AlertTypes = {}

-- Show a dodge bar via CA.ranged.
AlertTypes.DODGE       = "DODGE"

-- Show a block bar via CA.ranged.
AlertTypes.BLOCK       = "BLOCK"

-- Show an interrupt alert via CA.alert.
AlertTypes.INTERRUPT   = "INTERRUPT"

-- Show a countdown cast bar via CA.bar.
AlertTypes.CAST_BAR    = "CAST_BAR"

-- Show a debuff bar when an effect is gained on a target.
AlertTypes.DEBUFF      = "DEBUFF"

-- Reset a named timer on the boss (no UI output of its own).
AlertTypes.TIMER_RESET = "TIMER_RESET"

-- Known event, intentionally silent.  Suppresses the unknown-event warning.
AlertTypes.IGNORE      = "IGNORE"

-- Call entry.fn(boss, context, alerts, event) for bespoke handling.
AlertTypes.CUSTOM      = "CUSTOM"

-- -- Validation ---------------------------------------------------------------

local _valid = {}
for _, v in pairs(AlertTypes) do
    _valid[v] = true
end

--- Returns true when t is a recognised AlertTypes constant.
--- Called by EventDispatcher.build() on every event-table entry at load time.
function AlertTypes.isValid(t)
    return _valid[t] == true
end

package.loaded["core.AlertTypes"] = AlertTypes
return AlertTypes
