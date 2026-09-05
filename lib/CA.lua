--- lib/CA.lua  -  DEPRECATED shim.
---
--- All callers have been migrated to require("external-api.CombatAlerts").
--- This file is no longer listed in incha.txt and is kept only as a safety
--- net for any require("lib.CA") that may have slipped through the rename.
--- It will be removed in a future cleanup commit.

local CA = require("external-api.CombatAlerts")
package.loaded["lib.CA"] = CA
return CA
