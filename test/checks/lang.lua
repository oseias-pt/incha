--- test/checks/lang.lua  -  string-table integrity.
---
--- The string table is three things that drift apart on their own: a key
--- defined in lang/<locale>.lua, a call site asking for it, and the value a
--- player reads.  Each way they can disagree fails silently.
---
---   DUPLICATE  Two `M.key = ...` lines for one key.  A Lua table constructor
---              keeps the LAST assignment and discards the earlier one with no
---              error, so the string a translator edited is simply never used.
---              Eight of these shipped before this check existed.
---
---   MISSING    A call site asks for a key the table does not define.
---              Lang.t returns its fallback, so the player sees a raw key or an
---              empty line instead of a callout, and nothing errors.
---
---   ORPHAN     A key nothing references.  Dead weight a translator still has
---              to translate, and usually the residue of a rename where the old
---              name was left behind.
---
--- Reference scanning is deliberately loose: any quoted lowercase string in
--- shipping source counts as a use.  Keys do not always reach Lang.t as a
--- literal first argument -
---
---     Lang.t(stacks ~= 1 and "dsr_reef_stack_p" or "dsr_reef_stack", stacks)
---     local function makePortalHandler(labelKey) ... Lang.t(labelKey) ...
---
--- - so matching only `Lang.t("literal")` would report live keys as orphans.
--- Missing-key detection uses the strict form instead, since a literal sitting
--- directly in a Lang.t call is unambiguous.
---
--- Usage (from the repository root):
---   luajit test/checks/lang.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

local LANG_DIR    = "lang"
local SOURCE_DIRS = "core lib ui trial"

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

local function lines(cmd)
    local out, p = {}, io.popen(cmd)
    if not p then return out end
    for l in p:lines() do out[#out + 1] = (l:gsub("%s+$", "")) end
    p:close()
    return out
end

-- -- Locate the locale files -------------------------------------------------
local localeFiles = lines('find ' .. LANG_DIR .. ' -name "*.lua" 2>/dev/null')
if #localeFiles == 0 then
    print("cannot find any locale file under " .. LANG_DIR
        .. "/  -  run this from the repository root")
    os.exit(1)
end
table.sort(localeFiles)

-- -- Parse each locale file --------------------------------------------------
-- defined[locale] = { key -> line number }, in declaration order.
local defined, order = {}, {}

for _, path in ipairs(localeFiles) do
    local text = read(path)
    if not text then
        fail("READ        cannot read %s", path)
    else
        local keys, seq, lineNo = {}, {}, 0
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            lineNo = lineNo + 1
            local key = line:match("^%s*M%.([%w_]+)%s*=")
            if key then
                if keys[key] then
                    fail("DUPLICATE   %s:%d  M.%s is already defined at line %d  "
                         .. "-  Lua keeps the last, the earlier value is unreachable",
                         path, lineNo, key, keys[key])
                else
                    keys[key] = lineNo
                    seq[#seq + 1] = key
                end
            end
        end
        defined[path] = keys
        order[path]   = seq
    end
end

-- -- Collect references from shipping source ---------------------------------
-- Loose scan: any quoted lowercase_snake string anywhere in the addon source.
local referenced = {}
for _, s in ipairs(lines(
        'grep -rhoE "\\"[a-z][a-z0-9_]*\\"" --include=*.lua ' .. SOURCE_DIRS)) do
    referenced[s:sub(2, -2)] = true
end

-- Strict scan: a literal sitting directly in a Lang.t() call.  Only these can
-- be reported as missing, because only these are unambiguously a lookup.
local requested = {}
for _, s in ipairs(lines(
        'grep -rhoE "Lang\\.t\\(\\"[a-z][a-z0-9_]*\\"" --include=*.lua ' .. SOURCE_DIRS)) do
    requested[s:match('"([%w_]+)"')] = true
end

-- -- The reference locale is the one every other locale is compared against ---
local REFERENCE = LANG_DIR .. "/en.lua"
local refKeys   = defined[REFERENCE]

if not refKeys then
    fail("MISSING     %s not found  -  it is the reference locale", REFERENCE)
    print(string.format("lang: %d finding(s)", findings))
    os.exit(1)
end

-- -- 1. Every requested key must exist in the reference locale ---------------
local missing = {}
for key in pairs(requested) do
    if not refKeys[key] then missing[#missing + 1] = key end
end
table.sort(missing)
for _, key in ipairs(missing) do
    fail("MISSING     Lang.t(%q) has no definition in %s", key, REFERENCE)
end

-- -- 2. Every defined key must be referenced somewhere -----------------------
local orphans = {}
for _, key in ipairs(order[REFERENCE]) do
    if not referenced[key] then orphans[#orphans + 1] = key end
end
for _, key in ipairs(orphans) do
    fail("ORPHAN      %s:%d  M.%s is never referenced in %s",
         REFERENCE, refKeys[key], key, SOURCE_DIRS:gsub(" ", "/, ") .. "/")
end

-- -- 3. Other locales must match the reference key set -----------------------
for _, path in ipairs(localeFiles) do
    if path ~= REFERENCE then
        local keys = defined[path]
        local absent, extra = {}, {}
        for key in pairs(refKeys) do
            if not keys[key] then absent[#absent + 1] = key end
        end
        for key in pairs(keys) do
            if not refKeys[key] then extra[#extra + 1] = key end
        end
        table.sort(absent); table.sort(extra)
        for _, key in ipairs(absent) do
            fail("UNTRANSLATED %s is missing M.%s (defined in %s)", path, key, REFERENCE)
        end
        for _, key in ipairs(extra) do
            fail("STRAY       %s:%d defines M.%s, which %s does not",
                 path, keys[key], key, REFERENCE)
        end
    end
end

-- -- Report ------------------------------------------------------------------
local total = 0
for _ in pairs(refKeys) do total = total + 1 end

if findings == 0 then
    print(string.format("lang: clean (%d keys, %d locale file(s))",
          total, #localeFiles))
else
    print(string.format("lang: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
