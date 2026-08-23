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

-- Returns id, text, priority as plain values (no table) since this runs on
-- the boss-health hot path and Lua multiple-return doesn't allocate.
function HealthRules.evaluate(rules, healthPercent, context, boss)
    for _, rule in ipairs(rules or {}) do
        if HealthRules.matches(rule, healthPercent, context, boss) then
            return rule.id, formatText(rule.text, healthPercent), rule.priority or 0
        end
    end

    return nil
end

return HealthRules
