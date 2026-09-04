--- test/checks/globals.lua  -  static scan for unintended global access.
---
--- ESO addons share one Lua environment with every other addon the player has
--- installed, so an accidental global write is a cross-addon bug and an
--- accidental global read is a silent nil.  Both are invisible until the line
--- happens to run mid-fight.
---
--- This catches the class directly:  a missing `local X = require(...)` shows
--- up as a global READ of a name that is not part of the ESO API.
---
--- Usage (from the repository root):
---   luajit test/checks/globals.lua
---
--- Exit code 0 = clean, 1 = at least one finding.
---
--- Requires `luajit` on PATH  -  the scan reads the bytecode listing
--- (`luajit -bl`) rather than parsing Lua source with regexes.

local DIRS = { "core", "lib", "ui", "trial" }

-- Names the addon is allowed to read from the global environment: the ESO API
-- surface, the ADDON_* identity globals set by bootstrap.lua, the optional
-- third-party addons, and the Lua 5.1 standard library.
--
-- Constant families: a plain prefix match is enough, they are SHOUT_CASE.
local ALLOW_PREFIX = {
    "ACTION_RESULT_", "EFFECT_RESULT_", "EVENT_", "REGISTER_FILTER_",
    "POWERTYPE_", "ATTRIBUTE_VISUAL_", "LFG_ROLE_", "CT_", "TEXT_ALIGN_",
    "ADDON_", "zo_", "ZO_",
}

-- ESO API function families.  These need the NEXT character to be uppercase,
-- because a bare prefix match is far too loose: "Set" alone would silently
-- allow "Settings", which is exactly the missing-require bug this check
-- exists to catch (ZmajaEncounter read a nil global `Settings` for months).
--   SetMapToPlayerLocation -> "M" -> ESO API, allowed
--   Settings               -> "t" -> not ESO, reported
local ALLOW_VERB = { "Get", "Is", "Does", "Are", "Set", "Play", "Create" }

local ALLOW_EXACT = {}
for _, name in ipairs({
    -- ESO singletons and constants
    "EVENT_MANAGER", "SCENE_MANAGER", "WINDOW_MANAGER", "SLASH_COMMANDS",
    "GuiRoot", "SOUNDS", "TOPLEFT", "TOPRIGHT", "BOTTOM", "BOTTOMLEFT",
    "BOTTOMRIGHT", "TOP", "LEFT", "RIGHT", "CENTER", "d",
    -- Optional third-party addons  -  every call site must nil-guard these
    "OSI", "CombatAlerts", "LibAddonMenu2", "BSCHTKA",
    -- Lua 5.1 standard library
    "require", "package", "assert", "error", "pairs", "ipairs", "next",
    "select", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal",
    "pcall", "xpcall", "type", "tostring", "tonumber", "unpack", "print",
    "string", "table", "math", "os", "io", "debug", "coroutine", "_G",
}) do ALLOW_EXACT[name] = true end

local function isAllowed(name)
    if ALLOW_EXACT[name] then return true end
    for _, p in ipairs(ALLOW_PREFIX) do
        if name:sub(1, #p) == p then return true end
    end
    for _, p in ipairs(ALLOW_VERB) do
        if name:sub(1, #p) == p then
            local nextChar = name:sub(#p + 1, #p + 1)
            if nextChar:match("%u") then return true end
        end
    end
    return false
end

--- Collect every .lua file under the scanned directories.
local function sourceFiles()
    local files = {}
    for _, dir in ipairs(DIRS) do
        local p = io.popen('find "' .. dir .. '" -name "*.lua" 2>/dev/null')
        if p then
            for line in p:lines() do
                files[#files + 1] = (line:gsub("%s+$", ""))
            end
            p:close()
        end
    end
    table.sort(files)
    return files
end

--- Read GGET (global read) and GSET (global write) operands out of the
--- LuaJIT bytecode listing for one file.
local function scan(path)
    local reads, writes = {}, {}
    local p = io.popen('luajit -bl "' .. path .. '" 2>&1')
    if not p then return reads, writes, "could not run luajit" end
    for line in p:lines() do
        local op, name = line:match("(GGET).-;%s*\"([^\"]+)\"")
        if not op then op, name = line:match("(GSET).-;%s*\"([^\"]+)\"") end
        if op == "GGET" then reads[name] = true
        elseif op == "GSET" then writes[name] = true end
    end
    p:close()
    return reads, writes
end

local findings = 0
for _, path in ipairs(sourceFiles()) do
    local reads, writes = scan(path)

    -- Any global write from addon code is a bug: it leaks into the shared
    -- environment.  The tree currently has zero; keep it that way.
    local wnames = {}
    for name in pairs(writes) do wnames[#wnames + 1] = name end
    table.sort(wnames)
    for _, name in ipairs(wnames) do
        print(string.format("GLOBAL WRITE  %-46s %s", name, path))
        findings = findings + 1
    end

    local rnames = {}
    for name in pairs(reads) do rnames[#rnames + 1] = name end
    table.sort(rnames)
    for _, name in ipairs(rnames) do
        if not isAllowed(name) then
            print(string.format("GLOBAL READ   %-46s %s", name, path))
            print("              ^ not an ESO symbol  -  missing a require?")
            findings = findings + 1
        end
    end
end

if findings == 0 then
    print("globals: clean")
else
    print(string.format("globals: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
