--- test/checks/lang-keys.lua  -  every string key a call site asks for must exist.
---
--- Lang.t() answers an unknown key by returning the key itself.  For a sentence
--- that is merely ugly  -  a player sees "ss_lokke_tomb_take" where an alert
--- should read "Take the tomb!"  -  loud enough to notice.
---
--- For a BOSS NAME it is not loud at all.  Bosses declare
---
---     Lokke.name = Lang.t("boss_lokkestiiz")
---
--- and core/BossRegistry.lua matches that value against GetUnitName().  If the
--- key does not resolve, the name to match is the literal text
--- "boss_lokkestiiz", no unit is ever called that, the boss is never detected,
--- and every alert in the module stops firing.  Nothing logs, nothing throws,
--- CI stays green.  That is the failure this check exists for.
---
--- The second, quieter one: core/Lang.lua:21 selects ONE table per client
--- language and has no per-key fallback, so if a locale file is added and only
--- half translated, lang/de.lua say, the missing keys show as raw keys to a
--- German player while the rest of the file is fine.  Locale parity against
--- en.lua is checked for that reason; today lang/ holds en.lua alone, so the
--- parity branch has never had anything to say.
---
--- Usage (from the repository root):
---   luajit test/checks/lang-keys.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

local LANG_DIR = "lang"
local BASE_LOCALE = "en"

-- Patterns for a quoted literal.  Each quote character is written once, inside
-- a string literal delimited by the other kind, so none of them needs escaping.
local LIT_DOUBLE = '"([%w_]+)"'          -- in a 'single quoted' Lua string
local LIT_SINGLE = "'([%w_]+)'"          -- in a "double quoted" Lua string

-- The same two, anchored after "Lang.t"  -  any amount of whitespace, then the
-- opening paren, then the key.  Written this way so that a bare `Lang.t` used
-- as a value rather than a call is not mistaken for a call site.
local AFTER_DOUBLE = '^%s*%(%s*"([%w_]+)"'
local AFTER_SINGLE = "^%s*%(%s*'([%w_]+)'"

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

--- Byte offset -> line number, for reporting.
local function lineOf(src, pos)
    local _, n = string.gsub(src:sub(1, pos - 1), "\n", "")
    return n + 1
end

--- Bounds of a parenthesised argument list whose "(" is at or after `from`.
--- Nests, and skips the inside of nested string literals, so a ")" that sits in
--- a string or in a call inside the arguments does not end the list early.
--- Returns nil when there is no "(", and a nil second value when it never
--- closes (an unclosed paren is the parser's problem, not this check's).
local function argSpan(src, from)
    local i = from
    while i <= #src and src:sub(i, i) ~= "(" do i = i + 1 end
    if i > #src then return nil end

    local depth, j = 0, i
    while j <= #src do
        local ch = src:sub(j, j)
        if ch == "\"" or ch == "'" then
            local quote = ch
            j = j + 1
            while j <= #src do
                local d = src:sub(j, j)
                if d == "\\" then
                    j = j + 2
                elseif d == quote then
                    break
                elseif d == "\n" then
                    break
                else
                    j = j + 1
                end
            end
        elseif ch == "(" then
            depth = depth + 1
        elseif ch == ")" then
            depth = depth - 1
            if depth == 0 then return i + 1, j - 1 end
        end
        j = j + 1
    end
    return i + 1, nil
end

--- The files ESO will actually load, taken from the manifest rather than from a
--- directory walk: a key in a file that never loads is not a finding, and a
--- file that is not listed is manifest.lua's problem, not this check's.
local function manifestFiles()
    local files = {}
    local fh = io.open("incha.txt", "r")
    if not fh then return nil, "incha.txt not readable" end
    for line in fh:lines() do
        local path = line:match("^%s*([%w_%-%./]+%.lua)%s*$")
        if path then files[#files + 1] = path end
    end
    fh:close()
    table.sort(files)
    return files
end

local function readAll(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("*a")
    fh:close()
    return s
end

--- Keys a locale file defines.  Every pattern ends in "=[^=]" so that a
--- comparison (M.k == "x") is not read as a definition.  The bracket forms take
--- M["k"] = and M['k'] = , which en.lua does not use but a generated locale
--- file plausibly would.
local function definedKeys(path)
    local keys, src = {}, readAll(path)
    if not src then return nil end
    local Q = '"'
    for key in src:gmatch("M%.([%w_]+)%s*=[^=]") do keys[key] = true end
    for key in src:gmatch("%[" .. Q .. "([%w_]+)" .. Q .. "%]%s*=[^=]") do keys[key] = true end
    for key in src:gmatch("%['([%w_]+)'%]%s*=[^=]") do keys[key] = true end
    return keys
end

local function localeFiles()
    local out = {}
    local p = io.popen('find "' .. LANG_DIR .. '" -maxdepth 1 -name "*.lua" 2>/dev/null | sort')
    if not p then return out end
    for line in p:lines() do
        local path = (line:gsub("%s+$", ""))
        local code = path:match("([%w_-]+)%.lua$")
        if code then out[#out + 1] = { path = path, code = code } end
    end
    p:close()
    return out
end

-- -- 1. what each locale defines ----------------------------------------------
local locales = localeFiles()
local byCode = {}
for _, loc in ipairs(locales) do
    local keys = definedKeys(loc.path)
    if not keys then
        fail("UNREADABLE    %s", loc.path)
    else
        byCode[loc.code] = keys
    end
end

local base = byCode[BASE_LOCALE]
if not base then
    fail("NO BASE       lang/%s.lua defines no keys  -  nothing can fall back to it", BASE_LOCALE)
end

-- -- 2. every key a literal call site asks for -------------------------------
local files, skipped = manifestFiles()
if not files then
    fail("NO MANIFEST   %s", tostring(skipped))
    print(string.format("lang-keys: %d finding(s)", findings))
    os.exit(1)
end

local askedFor = {}   -- key -> { "file:line", ... }
local unproven = {}   -- { path = , line = , text = , candidates = {} }
local filesScanned = 0

for _, path in ipairs(files) do
    -- The string tables define keys, they do not ask for them.
    if path:sub(1, #LANG_DIR + 1) ~= LANG_DIR .. "/" then
        local src = readAll(path)
        if not src then
            fail("UNREADABLE    %s  listed in incha.txt but not on disk", path)
        else
            filesScanned = filesScanned + 1
            local pos = 1
            while true do
                -- Plain search: with the last argument set, find() takes the
                -- second argument as literal text, not as a pattern.
                local s = src:find("Lang.t", pos, true)
                if not s then break end
                -- Match over the whole file rather than line by line: a call
                -- may break across lines and the key is still a literal.
                local after = src:sub(s + 6, s + 90)
                local key = after:match(AFTER_DOUBLE) or after:match(AFTER_SINGLE)
                if key then
                    local seen = askedFor[key] or {}
                    seen[#seen + 1] = string.format("%s:%d", path, lineOf(src, s))
                    askedFor[key] = seen
                    pos = s + 7
                elseif after:match("^%s*%(") then
                    -- The key is not a literal here: a variable, or a choice
                    -- between two literals.  Read the WHOLE argument list and
                    -- look its literals up anyway.
                    --
                    -- The first version of this took src:sub(s+7, s+90) and
                    -- stopped at the first ")".  Both cut the candidate list,
                    -- silently: an argument containing a nested call such as
                    -- Fmt.timer(T) ended the span early, and the 90-byte window
                    -- truncated the alternative, so a typo'd second key printed
                    -- as "all defined" and the build stayed green.  Truncating
                    -- for DISPLAY is fine; truncating what you TEST is not.
                    local a, b = argSpan(src, s + 6)
                    local text = a and src:sub(a, b or #src):gsub("%s+", " ") or ""
                    local cand = {}
                    for _, pat in ipairs({ LIT_DOUBLE, LIT_SINGLE }) do
                        for c in text:gmatch(pat) do cand[#cand + 1] = c end
                    end
                    unproven[#unproven + 1] = {
                        path = path, line = lineOf(src, s), text = text, candidates = cand,
                    }
                    pos = s + 7
                else
                    -- Lang.t used as a value, not called  -  e.g. the export
                    -- in core/Lang.lua or an alias.  Nothing to resolve.
                    pos = s + 6
                end
            end
        end
    end
end

local keys = {}
for key in pairs(askedFor) do keys[#keys + 1] = key end
table.sort(keys)

for _, key in ipairs(keys) do
    if base and not base[key] then
        local sites = askedFor[key]
        if key:match("^boss_") then
            -- Not cosmetic: the value becomes the key text, which cannot match
            -- a unit name, so the boss goes undetected.  See the header.
            fail("DETECTION     %s  asked for at %s  -  not in lang/%s.lua, so .name cannot match GetUnitName()",
                 key, table.concat(sites, ", "), BASE_LOCALE)
        else
            fail("MISSING KEY   %s  asked for at %s  -  not in lang/%s.lua, the player sees the key",
                 key, table.concat(sites, ", "), BASE_LOCALE)
        end
    end
end

-- -- 3. sites this check cannot prove ----------------------------------------
-- A key chosen at run time is not verifiable statically.  Where the choice is
-- made from literals (Lang.t(vet and "k_a" or "k_b", n)) the candidates can
-- still be looked up, so an outright typo is caught even though the site is not
-- provable.
for _, site in ipairs(unproven) do
    local unknown = {}
    for _, c in ipairs(site.candidates) do
        if base and not base[c] then unknown[#unknown + 1] = c end
    end
    if #unknown > 0 then
        fail("UNKNOWN KEY   %s:%d  Lang.t(%s)  -  %s not in lang/%s.lua",
             site.path, site.line, site.text, table.concat(unknown, ", "), BASE_LOCALE)
    else
        print(string.format("UNPROVEN      %s:%d  Lang.t(%s)%s",
              site.path, site.line,
              #site.text > 96 and site.text:sub(1, 96) .. "..." or site.text,
              #site.candidates > 0
                  and string.format("  (%d candidate key(s), all defined)", #site.candidates)
                  or "  (key chosen at run time)"))
    end
end

-- -- 3b. aliases: Lang.t reached under another name --------------------------
-- The scan looks for the token "Lang.t".  An alias (local T = Lang.t) hides
-- every key reached through it.  None exists in the tree today; if one is added
-- it is named here so the gap is disclosed rather than silently widening.
for _, path in ipairs(files) do
    if path:sub(1, #LANG_DIR + 1) ~= LANG_DIR .. "/" then
        local src = readAll(path)
        if src then
            local line = 0
            for text in src:gmatch("[^\n]*\n?") do
                line = line + 1
                local name = text:match("^%s*local%s+([%w_]+)%s*=%s*Lang%.t%s*$")
                if name then
                    print(string.format("UNPROVEN      %s:%d  Lang.t aliased as %s()  -  keys reached through it are not visible to this check", path, line, name))
                end
            end
        end
    end
end

-- -- 4. every other locale covers the base key set ---------------------------
local baseCount = 0
if base then for _ in pairs(base) do baseCount = baseCount + 1 end end

for _, loc in ipairs(locales) do
    local keysHere = byCode[loc.code]
    if keysHere and loc.code ~= BASE_LOCALE and base then
        local missing = {}
        for key in pairs(base) do
            if not keysHere[key] then missing[#missing + 1] = key end
        end
        if #missing > 0 then
            table.sort(missing)
            local shown = {}
            for i = 1, math.min(#missing, 8) do shown[#shown + 1] = missing[i] end
            if #missing > 8 then shown[#shown + 1] = string.format("(+%d more)", #missing - 8) end
            fail("PARTIAL LOCALE lang/%s.lua is missing %d key(s) lang/%s.lua has  -  %s",
                 loc.code, #missing, BASE_LOCALE, table.concat(shown, ", "))
        end
    end
end

-- -- Report -------------------------------------------------------------------
if findings == 0 then
    print(string.format("lang-keys: clean (%d keys in lang/%s.lua, %d asked for by %d files, %d site(s) not provable here, %d locale(s))",
          baseCount, BASE_LOCALE, #keys, filesScanned, #unproven, #locales))
else
    print(string.format("lang-keys: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
