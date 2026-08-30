--- CastDur  -  thin wrapper around GetAbilityCastInfo with a per-callsite fallback.
---
--- GetAbilityCastInfo returns 0 for instant-cast or unknown abilities.  Every
--- handler that needs a bar duration supplies its own empirical fallback; this
--- helper centralises the select + guard so callsites stay on one line.
---
--- Usage:
---   local CastDur = require("lib.CastDur")
---   local dur = CastDur.get(abilityId, FALLBACK_MS)

local CastDur = {}

--- Returns the cast duration for abilityId in milliseconds, or fallback if
--- GetAbilityCastInfo returns 0 / nil (instant-cast or unknown ability).
function CastDur.get(abilityId, fallback)
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    return dur > 0 and dur or (fallback or 2000)
end

package.loaded["lib.CastDur"] = CastDur
return CastDur
