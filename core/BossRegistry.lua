local Difficulty = require("core.Difficulty")

local BossRegistry = {}
BossRegistry.__index = BossRegistry

function BossRegistry.new(bosses)
    local self = setmetatable({
        bosses = bosses or {},
        byId = {},
        byKey = {},
    }, BossRegistry)

    for _, boss in ipairs(self.bosses) do
        self.byId[boss.id] = boss
        self.byKey[boss.key] = boss
    end

    return self
end

function BossRegistry:getById(id)
    return self.byId[id]
end

function BossRegistry:getByKey(key)
    return self.byKey[key]
end

function BossRegistry:findAtPosition(x, y, z)
    for _, boss in ipairs(self.bosses) do
        if boss.location and boss.location:contains(x, y, z) then
            return boss
        end
    end

    return nil
end

-- Name-based fallback for trials whose bosses have no location bounding box.
-- Matches boss.name against GetUnitName("boss1") (caller should guard existence).
function BossRegistry:findByName(unitName)
    if not unitName or unitName == "" then return nil end
    for _, boss in ipairs(self.bosses) do
        if boss.name == unitName then
            return boss
        end
    end
    return nil
end

function BossRegistry:detectDifficulty(boss, effectiveMaxHealth)
    if not boss or not boss.hmHealthThreshold then
        return Difficulty.NONE
    end

    if effectiveMaxHealth >= boss.hmHealthThreshold then
        return Difficulty.HARDMODE
    end

    return Difficulty.NORMAL
end

function BossRegistry:resetAll(forced)
    for _, boss in ipairs(self.bosses) do
        if boss.reset then
            boss:reset(forced)
        end
    end
end

return BossRegistry
