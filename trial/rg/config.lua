local Location = require("core.Location")

-- Skeleton boss definitions for Rockgrove.
-- Add healthRules and onCombatEvent handlers as mechanics are migrated.
return {
    zoneId = 1263,
    bosses = {
        {
            id = 1,
            key = "oaxiltso",
            hmHealthThreshold = nil,
            location = Location.new(0, 0, 0, 0, 0, 0),
            healthRules = {
                -- Example: { min = 48, max = 52, text = "HM phase soon ({hp}%)" },
            },
            reset = function(self, forced) end,
        },
        {
            id = 2,
            key = "bahsei",
            hmHealthThreshold = nil,
            location = Location.new(0, 0, 0, 0, 0, 0),
            healthRules = {},
            reset = function(self, forced) end,
        },
        {
            id = 3,
            key = "xalvakka",
            hmHealthThreshold = nil,
            location = Location.new(0, 0, 0, 0, 0, 0),
            healthRules = {},
            reset = function(self, forced) end,
        },
    },
}
