local HealthRules = {}

local function formatText(template, healthPercent)
    return (template:gsub("{hp}", string.format("%.1f", healthPercent)))
end

function HealthRules.matches(rule, healthPercent, context)
    if healthPercent < rule.min or healthPercent > rule.max then
        return false
    end

    if rule.when and not rule.when(context) then
        return false
    end

    return true
end

-- Returns id, text, priority as plain values (no table) since this runs on
-- the boss-health hot path and Lua multiple-return doesn't allocate.
function HealthRules.evaluate(rules, healthPercent, context)
    for _, rule in ipairs(rules or {}) do
        if HealthRules.matches(rule, healthPercent, context) then
            return rule.id, formatText(rule.text, healthPercent), rule.priority or 0
        end
    end

    return nil
end

return HealthRules
