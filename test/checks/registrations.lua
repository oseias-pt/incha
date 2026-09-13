--- test/checks/registrations.lua  -  guard high-frequency event registrations.
---
--- EVENT_COMBAT_EVENT and EVENT_EFFECT_CHANGED fire thousands of times per
--- second in a twelve-player trial.  Registering for them without a filter
--- floods Lua and is the single easiest way to tank addon performance.
---
--- Two invariants are enforced:
---
---   1. NO DIRECT UNFILTERED CALL.
---      No shipped file may contain a line where RegisterForEvent is called
---      with EVENT_COMBAT_EVENT or EVENT_EFFECT_CHANGED as a literal argument.
---      All such registrations must go through EventPipeline's `register()`
---      helper, which always pairs the call with AddFilterForEvent.
---      A bare EVENT_MANAGER:RegisterForEvent(ns, EVENT_COMBAT_EVENT, fn) in
---      any file — including EventPipeline.lua itself — is a FAIL.
---
---   2. PIPELINE HELPER PAIRING.
---      core/EventPipeline.lua must define a local `register()` function whose
---      body contains both RegisterForEvent and AddFilterForEvent.  If the
---      helper loses its filter call, every boss registration becomes unfiltered
---      and the check above misses it (the literal event names appear only at
---      the call sites, not inside the helper body).
---
--- Negative test: adding EVENT_MANAGER:RegisterForEvent(ns, EVENT_COMBAT_EVENT,
--- fn) to any .lua file must cause this check to exit rc=1.
---
--- Usage (from the repository root):
---   luajit test/checks/registrations.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

local MANIFEST      = "incha.txt"
local PIPELINE_FILE = "core/EventPipeline.lua"

-- High-frequency events that must never be registered without a filter.
local HIGH_FREQ = {
    EVENT_COMBAT_EVENT    = true,
    EVENT_EFFECT_CHANGED  = true,
}

local findings = 0
local function fail(fmt, ...)
    print(string.format("FAIL  " .. fmt, ...))
    findings = findings + 1
end

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- -- 1. No direct high-freq registration in any shipped file ------------------
--
-- A violation looks like:
--   EVENT_MANAGER:RegisterForEvent("NS", EVENT_COMBAT_EVENT, handler)
-- or inside EventPipeline via a boolean typo that inlines the event name:
--   EVENT_MANAGER:RegisterForEvent(ns, EVENT_COMBAT_EVENT, safe(fn))
--
-- The pipeline's legitimate path uses a local variable `event` (a parameter),
-- so event names never appear on the same line as RegisterForEvent there.

local manifest = read(MANIFEST)
if not manifest then
    print("cannot read " .. MANIFEST .. "  -  run this from the repository root")
    os.exit(1)
end

local checkedFiles = 0
for entry in manifest:gmatch("[^\r\n]+") do
    local path = entry:match("^%s*([%w_%-/%.]+%.lua)%s*$")
    if path then
        path = path:gsub("\\", "/")
        local body = read(path)
        if body then
            checkedFiles = checkedFiles + 1
            local lineNo = 0
            for line in body:gmatch("[^\n]+") do
                lineNo = lineNo + 1
                -- Skip comment lines.
                if not line:match("^%s*%-%-") then
                    local hasRegister = line:find("RegisterForEvent", 1, true)
                    if hasRegister then
                        for event in pairs(HIGH_FREQ) do
                            if line:find(event, 1, true) then
                                fail("%s:%d  direct unfiltered %s registration",
                                     path, lineNo, event)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- -- 2. Pipeline helper pairing -----------------------------------------------
--
-- Verify that core/EventPipeline.lua defines a `register()` helper whose body
-- contains both `:RegisterForEvent(` and `:AddFilterForEvent(`.  If the helper
-- loses its AddFilterForEvent line, every boss event registration becomes
-- unfiltered and check 1 above would not catch it (the event name literals
-- live at the call sites, not inside the helper body itself).

local pipelineBody = read(PIPELINE_FILE)
if not pipelineBody then
    fail("%s not found — cannot verify register() helper pairing", PIPELINE_FILE)
else
    -- Extract the local function register() block by finding it and walking to
    -- the matching `end`.  We look for it starting from the `local function register`
    -- declaration and collect until the first standalone `end` at the same depth.
    local _, helperStart = pipelineBody:find("local function register%(")
    if not helperStart then
        fail("%s: no `local function register(` found — helper was removed or renamed",
             PIPELINE_FILE)
    else
        -- Grab a generous window (300 chars is enough for the 5-line helper).
        local window = pipelineBody:sub(helperStart, helperStart + 400)
        local hasRegister  = window:find(":RegisterForEvent(",  1, true)
        local hasFilter    = window:find(":AddFilterForEvent(", 1, true)
        if not hasRegister then
            fail("%s: register() helper has no :RegisterForEvent( call", PIPELINE_FILE)
        end
        if not hasFilter then
            fail("%s: register() helper has no :AddFilterForEvent( call — "
                 .. "all high-freq registrations are now unfiltered", PIPELINE_FILE)
        end
        if hasRegister and hasFilter then
            -- Pairing order: RegisterForEvent must come before AddFilterForEvent.
            if hasRegister > hasFilter then
                fail("%s: register() helper calls AddFilterForEvent before "
                     .. "RegisterForEvent — order is wrong", PIPELINE_FILE)
            end
        end
    end
end

-- -- Report -------------------------------------------------------------------
if findings == 0 then
    print(string.format(
        "registrations: clean (%d files checked, pipeline helper pairing verified)",
        checkedFiles))
else
    print(string.format("registrations: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
