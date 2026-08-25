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

-- Sort rules by priority descending at registration time so evaluate()
-- can stay a simple first-match scan.  Call once per boss class, not
-- per encounter — the sorted order is shared across all instances.
-- Rules with no priority field default to 0; table.sort is stable in
-- LuaJIT so equal-priority rules keep their declaration order.
function HealthRules.register(rules)
    table.sort(rules, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)
    return rules
end

-- Returns id, text as plain values (no table) since this runs on the
-- boss-health hot path and Lua multiple-return doesn't allocate.
-- Assumes rules were sorted by HealthRules.register at class load time.
function HealthRules.evaluate(rules, healthPercent, context, boss)
    for _, rule in ipairs(rules or {}) do
        if HealthRules.matches(rule, healthPercent, context, boss) then
            return rule.id, formatText(rule.text, healthPercent)
        end
    end

    return nil
end

return HealthRules
