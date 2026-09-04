--- Shared map / proximity utilities.

local Log = require("lib.Log")

local MapUtils = {}

--- Returns true when `unitTag` is within `threshold` world-units of the local player.
--- Uses GetUnitWorldPosition for accuracy; avoids the stale-map bug from
--- SetMapToPlayerLocation() + GetMapPlayerPosition().
---
--- GetUnitWorldPosition returns FOUR values: zoneId, x, y, z.  Distance is
--- measured on the horizontal plane (x/z); y is the vertical axis and is
--- deliberately ignored so a player one floor up still counts as "near" in
--- arenas with raised platforms.
---
--- Threshold values are in ESO world units (same scale as GetUnitWorldPosition),
--- NOT the old normalised map scale.  The current call-site values are carried
--- over from the normalised era and still need in-game recalibration:
---   Lokke  Glacial Fist  4.5   trial/ss/boss/Lokke.lua
---   Yolna  Lava Geyser   2.8   trial/ss/boss/Yolna.lua
---   Nahvii Meteor        7     trial/ss/boss/Nahvii.lua
--- Enable debug logging (/incha debug) and read the "proximity" lines printed
--- below to measure real spreads, then replace the three constants.
--- See GitHub issues #29, #30, #31.
function MapUtils.isGroupMemberNearby(unitTag, threshold)
    local _, x1, _, z1 = GetUnitWorldPosition("player")
    local _, x2, _, z2 = GetUnitWorldPosition(unitTag)
    if not x1 or not x2 then return false end

    local dx, dz = x1 - x2, z1 - z2
    local dist = math.sqrt(dx * dx + dz * dz)

    -- Recalibration aid: prints the real world-unit distance next to the
    -- threshold it was tested against, so one trial run yields the numbers
    -- needed to replace the three legacy constants.  No-op unless the debug
    -- flag is on, and Log.debug itself early-returns before formatting.
    if Log.isEnabled() then
        Log.debug("proximity: %s dist=%.1f threshold=%.1f -> %s",
            tostring(unitTag), dist, threshold, tostring(dist <= threshold))
    end

    return dist <= threshold
end

package.loaded["lib.MapUtils"] = MapUtils
return MapUtils
