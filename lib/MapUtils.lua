--- Shared map / proximity utilities.

local MapUtils = {}

--- Returns true when `unitTag` is within `threshold` world-units of the local player.
--- Uses GetUnitWorldPosition for accuracy; avoids the stale-map bug from
--- SetMapToPlayerLocation() + GetMapPlayerPosition().
---
--- Threshold values are in ESO world units (same scale as GetUnitWorldPosition).
--- Existing call-sites that relied on the old normalised * 1000 scale must be
--- recalibrated in-game.
--- TODO(ss): recalibrate Yolna threshold (currently 2.8 -- Shadowfen Shipwreck)
--- TODO(ss): recalibrate Lokke threshold (currently 4.5 -- Shadowfen Shipwreck)
--- TODO(ss): recalibrate Nahvii threshold (currently 7.0 -- Shadowfen Shipwreck)
function MapUtils.isGroupMemberNearby(unitTag, threshold)
    local x1, _, z1 = GetUnitWorldPosition("player")
    local x2, _, z2 = GetUnitWorldPosition(unitTag)
    if not x1 or not x2 then return false end
    return math.sqrt((x1 - x2)^2 + (z1 - z2)^2) <= threshold
end

package.loaded["lib.MapUtils"] = MapUtils
return MapUtils
