--- Shared map / proximity utilities.

local MapUtils = {}

--- Returns true when `unitTag` is within `threshold` map-units of the local player.
--- Uses normalised map coordinates multiplied by 1000 to produce a unit scale
--- consistent with the threshold values tuned per-boss.
function MapUtils.isGroupMemberNearby(unitTag, threshold)
    SetMapToPlayerLocation()
    local x1, y1 = GetMapPlayerPosition("player")
    local x2, y2 = GetMapPlayerPosition(unitTag)
    return x2 and y2 and math.sqrt((x1 - x2)^2 + (y1 - y2)^2) * 1000 <= threshold
end

return MapUtils
