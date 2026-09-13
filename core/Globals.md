--- core/Globals.lua  -  Documentation for ESO-injected global constants.
---
--- These values are NOT defined in any Lua file.  ESO sets them before any
--- addon Lua runs, deriving them from the addon manifest (incha.txt):
---
---   ADDON_PREFIX  (string)
---     Built from the addon's ## Title field, stripped of spaces and lowercased
---     by ESO convention.  Used as a namespace prefix for EVENT_MANAGER
---     registrations so they don't collide with other addons.
---     Example value: "Incha_"
---
---   ADDON_TAG  (string)
---     Short display tag prepended to chat output and error messages.
---     Typically "[Incha]" or similar.
---     Example value: "[Incha]"
---
--- Usage notes:
---   - Do not redefine these.  Treat them as read-only constants.
---   - If the manifest ## Title changes, every use of ADDON_PREFIX must be
---     re-verified since the derived value changes too.
---   - New code that needs to print to chat should use lib/Log.lua rather
---     than referencing ADDON_TAG directly, so output is gated by the
---     debug flag and formatted consistently.

-- This file is documentation-only; it exports nothing.
-- Load order: not required to be in incha.txt — no runtime effect.

package.loaded["core.Globals"] = true
return true
