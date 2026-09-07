--- test/checks/settings-usage.lua  -  every setting must actually do something.
---
--- A settings entry is three pieces of code that can drift apart on their own:
--- a default in core/Settings.lua, a checkbox in ui/Menu.lua, and a reader in a
--- boss or ui module.  The first two are visible in the settings panel, the
--- third is not  -  so when the reader is deleted (or never written) the player
--- still sees a working checkbox that changes nothing, and nothing anywhere
--- fails.  That is the worst kind of dead code: it is *advertised*.
---
--- Usage (from the repository root):
---   luajit test/checks/settings-usage.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

local SETTINGS = "core/Settings.lua"
local MANIFEST = "incha.txt"

-- Files that define or expose settings and are therefore not "readers".
local NOT_A_READER = {
    ["core/Settings.lua"] = true,   -- declares the schema
    ["ui/Menu.lua"]       = true,   -- draws the checkboxes
}

-- Known findings, kept green on purpose so this check can gate CI from the day
-- it lands and only fail on NEW dead settings.  Remove an entry by fixing it.
local GRANDFATHERED = {
}

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local settingsText = read(SETTINGS)
if not settingsText then
    print("cannot read " .. SETTINGS .. "  -  run this from the repository root")
    os.exit(1)
end

-- -- Collect the per-trial keys ----------------------------------------------
-- Track brace depth from the opening of the trials block:
--
--   trials = {           depth 1 on entry
--       ka = {           depth 2 inside each trial sub-table
--           enabled = true,
--           bosses = {   depth 3 inside the per-boss sub-table (NOT collected)
--               yandir = true,
--           },
--       },
--   }
--
-- A name is a setting when it appears at depth == 2 (direct trial key), or on
-- the trial ID line itself (depth 1, same-line assignments beside the id).
-- Boss name keys nested inside bosses = { } are at depth 3 and are read
-- dynamically in Trial.lua via bosses[bossClass.key], so they are not
-- collected here — only the bosses container key itself is.
local keys, seen = {}, {}
local inTrials, depth = false, 0
for line in settingsText:gmatch("[^\n]+") do
    if not inTrials then
        if line:match("^%s*trials%s*=%s*{") then
            inTrials, depth = true, 1
        end
    else
        local before = depth
        local opens, closes = 0, 0
        for _ in line:gmatch("{") do opens = opens + 1 end
        for _ in line:gmatch("}") do closes = closes + 1 end
        if not line:match("^%s*%-%-") then
            local row = line:match("^%s*(%w+)%s*=%s*{")
            for name in line:gmatch("([%w_]+)%s*=") do
                local isSetting = before == 2 or (before == 1 and row and name ~= row)
                if isSetting and not seen[name] then
                    seen[name] = true
                    keys[#keys + 1] = name
                end
            end
        end
        depth = depth + opens - closes
        if depth <= 0 then inTrials = false end
    end
end
if #keys == 0 then
    print("no per-trial keys found in " .. SETTINGS)
    os.exit(1)
end

-- -- Read every addon source file once ---------------------------------------
local sources = {}
local fileCount = 0
for line in (read(MANIFEST) or ""):gmatch("[^\r\n]+") do
    local entry = line:match("^%s*([%w_%-/%.]+%.lua)%s*$")
    if entry then
        entry = entry:gsub("\\", "/")
        if not NOT_A_READER[entry] then
            local body = read(entry)
            if body then
                sources[#sources + 1] = body
                fileCount = fileCount + 1
            end
        end
    end
end

-- -- A key is live if some other file mentions it as a field -----------------
table.sort(keys)
for _, key in ipairs(keys) do
    local readers = 0
    local pattern = "[%.:]" .. key .. "%W"
    for _, body in ipairs(sources) do
        for _ in body:gmatch(pattern) do
            readers = readers + 1
        end
    end
    if readers == 0 then
        if GRANDFATHERED[key] then
            print(string.format("KNOWN         trials.*.%s has no reader (grandfathered, see the issue)", key))
        else
            fail("DEAD SETTING  trials.*.%s is declared in %s and drawn in ui/Menu.lua but no module reads it",
                 key, SETTINGS)
        end
    end
end

-- -- Report ------------------------------------------------------------------
if findings == 0 then
    print(string.format("settings-usage: clean (%d keys checked against %d source files)",
          #keys, fileCount))
else
    print(string.format("settings-usage: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
