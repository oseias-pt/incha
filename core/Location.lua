local Location = {}
Location.__index = Location

function Location.new(x1, x2, y1, y2, z1, z2)
    return setmetatable({
        x1 = x1, x2 = x2,
        y1 = y1, y2 = y2,
        z1 = z1, z2 = z2,
    }, Location)
end

function Location:contains(x, y, z)
    return self.x1 < x and x < self.x2
        and self.y1 < y and y < self.y2
        and self.z1 < z and z < self.z2
end

return Location
