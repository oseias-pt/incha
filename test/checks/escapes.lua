--- test/checks/escapes.lua  -  block escape sequences ESO's Lua cannot read.
---
--- ESO ships a Lua 5.1 interpreter.  Lua 5.1 implements \a \b \f \n \r \t \v
--- \\ \" \' \newline and \ddd (decimal, 1-3 digits)  -  and nothing else.  For
--- an unrecognised escape Lua 5.1 silently drops the backslash and keeps the
--- character that follows it, so "\x41" evaluates to the three characters
--- "x41" and "\xe2\x86\x92" to the nine characters "xe2x86x92".  This is not a
--- syntax error: the file compiles, the addon loads, and the string is simply
--- wrong on screen.
---
--- LuaJIT  -  CI, and most developers' editors  -  DOES implement \xHH and
--- \uHHHH.  A string using them is correct everywhere it is checked and wrong
--- everywhere it is played.  This is the class of bug that no compile check can
--- catch, because both engines accept the source and agree that it is valid:
--- they disagree only about what the constant means.
---
--- Concrete instances this check exists for: 7d829fc wrote 147 of these
--- sequences across 53 literals.  Under LuaJIT "\xe2\x86\x92" is an arrow; in the
--- game it is the nine characters "xe2x86x92", so a Cloudrest alert read
--- "Spear xe2x86x92 Target (3)" (lang/en.lua:647 in that commit).  Raw UTF-8 is
--- byte-identical under both engines and is what this addon shipped before the
--- string table existed.
---
--- Usage (from the repository root):
---   luajit test/checks/escapes.lua        (or: lua5.1 test/checks/escapes.lua)
---
--- Exit code 0 = clean, 1 = at least one finding.

-- Escapes Lua 5.1 does not implement.  The first character after the backslash
-- is what decides, so only that character has to be matched.
local BLOCKED = { x = true, X = true, u = true, U = true }

-- Escapes both engines agree on, decoded here only so that the reported
-- "this is what the player sees" string is exact.
local SIMPLE = {
    a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v",
    ["\\"] = "\\", ["\""] = "\"", ["'"] = "'",
}

-- Literals that already use \xHH on master.  This is a ratchet, not a pardon:
-- the unit is the ESCAPE SEQUENCE, not the literal, because otherwise adding
-- more escapes to an already-allowed literal stays under a literal-count
-- ceiling and passes.  Measured in escapes, adding one anywhere fails.
--
-- The reason strings follow the convention in state-reset.lua: the number on
-- its own is not reviewable, the sentence is.
--
-- 7d829fc wrote 147 of these across 53 literals.  lang/en.lua has since been
-- corrected in this repository by writing raw bytes; what is left is Lylanar's
-- four glyphs, and the branch that rewrites them deletes this entry.  STALE
-- prints when what remains is less than the allowance, or when the file stops
-- being scanned at all, so the table cannot quietly rot.
local GRANDFATHERED = {
    ["trial/dsr/boss/Lylanar.lua"] = {
        escapes = 14,
        reason  = "4 glyph literals from 7d829fc; the fix branch rewrites them as raw UTF-8",
    },
}

--- Level and content start of a long bracket opened at i, or nil.
--- A long bracket is  [[  or  [=[=[ ; the character AT i must be the first
--- bracket.  (Testing the character after i instead makes every line comment
--- whose text starts with a bracket  -  "-- [foo]"  -  look like a long
--- comment, which then swallows the rest of the file.)
local function openLong(src, i)
    if src:sub(i, i) ~= "[" then return nil end
    local j, level = i + 1, 0
    while src:sub(j, j) == "=" do level, j = level + 1, j + 1 end
    if src:sub(j, j) == "[" then return j + 1, level end
    return nil
end

--- Index of the long bracket closer for `level`, at or after i, or nil.
local function closeLong(src, i, level)
    return src:find("]" .. string.rep("=", level) .. "]", i, true)
end

--- Newlines in src[a], src[b].
local function newlines(src, a, b)
    if a > b then return 0 end
    local _, count = string.gsub(src:sub(a, b), "\n", "")
    return count
end

--- Report every blocked escape in one file, with the line it starts on.
local function scan(src)
    local found, i, n, line = {}, 1, #src, 1

    while i <= n do
        local c = src:sub(i, i)

        if c == "\n" then
            line = line + 1
            i = i + 1

        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            -- A comment is not code: a \x in a comment is prose, not a bug.
            local o, level = openLong(src, i + 2)
            if o then                                   -- --[[ long comment ]]
                local e = closeLong(src, o, level) or n
                line = line + newlines(src, i, e - 1)
                i = e + 2
            else                                        -- -- line comment
                local e = src:find("\n", i, true) or (n + 1)
                i = e                                   -- the \n counts itself
            end

        elseif c == "[" then                            -- long string / table
            local o, level = openLong(src, i)
            if o then
                local e = closeLong(src, o, level) or n
                line = line + newlines(src, i, e - 1)
                i = e + 2
            else
                i = i + 1
            end

        elseif c == "\"" or c == "'" then
            local delim = c
            local j, blocked = i + 1, 0
            local raw = {}
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then
                    local esc = src:sub(j + 1, j + 1)
                    if BLOCKED[esc] then
                        blocked = blocked + 1
                        -- What Lua 5.1 puts in the string for this escape:
                        -- the backslash is dropped, the letter is kept, and the
                        -- digits that followed become ordinary characters.
                        local width = (esc == "x" or esc == "X") and 2 or 4
                        local digits = ""
                        local k = j + 2
                        -- Test the character directly.  src:match("^[0-9a-fA-F]", k)
                        -- would not work here: in this dialect ^ anchors at the
                        -- real start of the string, not at the init position, so
                        -- with k > 1 it never matches and the loop is dead.
                        while #digits < width do
                            local ch = src:sub(k, k)
                            if ch == "" or not ch:match("^[0-9a-fA-F]$") then break end
                            digits = digits .. ch
                            k = k + 1
                        end
                        raw[#raw + 1] = esc .. digits
                        j = j + 2 + #digits             -- backslash, letter, digits
                    else
                        if esc == "\n" then                -- escaped real newline
                            line = line + 1
                            j = j + 2
                        elseif esc:match("^%d$") then      -- \ddd, agreed by both
                            local digits = src:match("^([0-9]%d?%d?)", j + 1)
                            raw[#raw + 1] = string.char(tonumber(digits) % 256)
                            j = j + 1 + #digits
                        else
                            raw[#raw + 1] = SIMPLE[esc] or esc
                            j = j + 2                     -- skips \" and \\ too
                        end
                    end
                elseif d == delim then
                    j = j + 1
                    break
                elseif d == "\n" then
                    break                               -- unterminated; let the parser complain
                else
                    raw[#raw + 1] = d
                    j = j + 1
                end
            end
            if blocked > 0 then
                found[#found + 1] = {
                    line     = line,
                    count    = blocked,
                    rendered = table.concat(raw),
                }
            end
            i = j

        else
            i = i + 1
        end
    end

    return found
end

--- Every file the addon ships, straight from incha.txt.
---
--- A directory list here was a silent allow-list: bootstrap.lua, incha.lua and
--- the three external-api/ modules are all in the manifest and all outside
--- core/ lib/ ui/ trial/ lang/, so an escape written in one of them was never
--- seen.  The manifest is what manifest.lua enforces and what ESO loads, so it
--- cannot fall behind the tree the way a directory list can.
local function sourceFiles()
    local seen, files = {}, {}
    local fh = io.open("incha.txt", "r")
    if not fh then return nil, "incha.txt not readable" end
    for line in fh:lines() do
        local path = line:match("^%s*([%w_%-%./]+%.lua)%s*$")
        if path and not seen[path] then
            seen[path] = true
            files[#files + 1] = path
        end
    end
    fh:close()
    table.sort(files)
    return files
end

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

local listed, listErr = sourceFiles()
if not listed then
    fail("NO MANIFEST   %s  -  nothing could be scanned", tostring(listErr))
    print("escapes: 1 finding(s)")
    os.exit(1)
end

local files, perFile = 0, {}
for _, path in ipairs(listed) do
    local fh = io.open(path, "rb")
    if not fh then
        fail("UNREADABLE    %s  listed in incha.txt but not on disk", path)
    else
        local src = fh:read("*a")
        fh:close()
        files = files + 1
        local hits = scan(src)
        local escapes = 0
        for _, hit in ipairs(hits) do escapes = escapes + hit.count end
        perFile[path] = escapes
        local allowed = GRANDFATHERED[path]
        local spent = 0
        for _, hit in ipairs(hits) do
            local shown = hit.rendered
            if #shown > 48 then shown = shown:sub(1, 48) .. "..." end
            if allowed and spent + hit.count <= allowed.escapes then
                spent = spent + hit.count
                print(string.format("KNOWN         %s:%d  %d escape(s), grandfathered: %s",
                      path, hit.line, hit.count, allowed.reason))
            else
                fail("ESCAPE        %s:%d  %d \\xHH escape(s) in a string literal  -  ESO will display %q",
                     path, hit.line, hit.count, shown)
            end
        end
    end
end

-- A ratchet that only ever loosens is not a ratchet.  Say when an allowance is
-- larger than what is left, and also when the file it names has stopped being
-- scanned  -  renamed away, or dropped from the manifest  -  because that is how
-- an entry can outlive its own fix without saying so.
for path, allowed in pairs(GRANDFATHERED) do
    local seen = perFile[path]
    if seen == nil then
        print(string.format("STALE         %s  no longer scanned  -  delete this allowance", path))
    elseif seen < allowed.escapes then
        print(string.format("STALE         %s  %d of %d grandfathered escapes remain  -  lower the allowance%s",
              path, seen, allowed.escapes, seen == 0 and " (delete the entry)" or ""))
    end
end

if findings == 0 then
    print(string.format("escapes: clean (%d files; no escapes beyond the grandfathered allowance)", files))
else
    print(string.format("escapes: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
