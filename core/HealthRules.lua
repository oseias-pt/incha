local HealthRules = {}

local function formatText(template, healthPercent)
    return (template:gsub("{hp}", string.format("%.1f", healthPercent)))
end

-- `boss` is the active boss instance (or singleton).  Passed through to
-- rule.when() as a second argument so predicates can read boss state
-- (e.g. a per-trial setting flag) without polluting TrialContext.
-- Legacy when(ctx) predicates that ignore the second arg still work fine.
function HealthRules.matches(rule, healthPercent, context, boss)
    if healthPercent < rule.min or healthPercent > rule.max then
        return false
    end

    if rule.when and not rule.when(context, boss) then
        return false
    end

    return true
end

-- Returns id, text of the highest-priority matching rule as plain values
-- (no table) since this runs on the boss-health hot path and Lua
-- multiple-return doesn't allocate.
--
-- When multiple rules overlap the same HP range, the one with the largest
-- `priority` field wins.  Rules with no `priority` field default to 0.
-- Array order acts as a tiebreaker: the first entry seen at equal priority
-- is kept.
function HealthRules.evaluate(rules, healthPercent, context, boss)
    if not rules then return nil end

    local bestId, bestText, bestPriority = nil, nil, nil

    for _, rule in ipairs(rules) do
        if HealthRules.matches(rule, healthPercent, context, boss) then
            local p = rule.priority or 0
            if bestPriority == nil or p > bestPriority then
                bestId       = rule.id
                bestText     = formatText(rule.text, healthPercent)
                bestPriority = p
            end
        end
    end

    return bestId, bestText
end

return HealthRules
