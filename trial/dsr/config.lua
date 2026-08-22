local Location = require("core.Location")

return {
    zoneId = 1344,
    bosses = {
        {
            id = 1,
            key = "lylanar",
            hmHealthThreshold = nil,
            location = Location.new(0, 0, 0, 0, 0, 0),
            healthRules = {},
            reset = function(self, forced) end,
        },
        {
            id = 2,
            key = "reef_guardian",
            hmHealthThreshold = nil,
            location = Location.new(0, 0, 0, 0, 0, 0),
            healthRules = {},
            reset = function(self, forced) end,
        },
        {
            id = 3,
            key = "taleria",
            hmHealthThreshold = nil,
            location = Location.new(0, 0, 0, 0, 0, 0),
            healthRules = {},
            reset = function(self, forced) end,
        },
    },
}
