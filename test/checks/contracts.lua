--- test/checks/contracts.lua  -  load every module and assert the boss contract.
---
--- Two things are checked, both of which have already shipped as live bugs:
---
---   1. Every trial Factory loads, and registers at least one boss.
---      RockgroveCommon once called an unstubbed ESO function at file scope,
---      which made all three RG bosses unloadable without anything failing.
---
---   2. Every boss class resolves the BossBase lifecycle helpers.
---      OlmsEncounter, AnsuulEncounter, ChimeraEncounter and YaseylaEncounter
---      called self:cleanupAlertList() while never linking their class to
---      BossBase, so the method was nil and every wipe and zone exit threw.
---      Any class whose stateSchema declares `alertList` additionally needs
---      onDied, or its cast bars are never stopped when the unit dies.
---
--- Usage (from the repository root):
---   luajit test/checks/contracts.lua
---
--- Exit code 0 = clean, 1 = at least one finding.

package.path = "./?.lua;./test/?.lua;" .. package.path
require("harness.eso_api")

local TRIALS = { "ka", "ss", "rg", "dsr", "as", "cr", "se", "lc", "oc" }

local findings = 0
local function fail(fmt, ...)
    print(string.format(fmt, ...))
    findings = findings + 1
end

-- -- 1. Factories -----------------------------------------------------------
local seen = {}   -- boss class -> owning trial id, to catch a class shared by two trials

for _, id in ipairs(TRIALS) do
    local path = "trial." .. id .. ".Factory"
    local ok, trial = pcall(require, path)

    if not ok or not trial then
        fail("FACTORY LOAD  %-28s %s", path, tostring(trial))
    elseif not trial.registry or #trial.registry.bosses == 0 then
        fail("FACTORY EMPTY %-28s registered no bosses", path)
    else
        local keys = {}
        for i, boss in ipairs(trial.registry.bosses) do
            keys[i] = tostring(boss.key)

            if not boss.key then
                fail("BOSS KEY      %-28s boss #%d has no .key", path, i)
            end

            -- A boss must be detectable by SOMETHING, or the encounter can
            -- never activate: an arena bounding box, a name, or aliases.
            if not (boss.location or boss.name or boss.nameAliases) then
                fail("UNDETECTABLE  %-28s %s has no location, name or nameAliases",
                     path, tostring(boss.key))
            end

            if seen[boss] and seen[boss] ~= id then
                fail("SHARED CLASS  %-28s %s is also registered by %s "
                     .. "(BossRegistry mutates boss.id, so ids would collide)",
                     path, tostring(boss.key), seen[boss])
            end
            seen[boss] = id
        end
        print(string.format("ok  %-22s %d boss(es): %s",
              path, #trial.registry.bosses, table.concat(keys, ", ")))
    end
end

-- -- 2. Boss lifecycle contract ---------------------------------------------
print("")

-- Discover boss modules from the manifest (cross-platform; avoids Unix-only
-- io.popen('find ...')).  The same technique used by test/checks/state-reset.lua.
local bossModules = {}
local mf = io.open("incha.txt", "r")
if not mf then
    fail("cannot read incha.txt  -  run this from the repository root")
    os.exit(1)
end
for line in mf:read("*a"):gmatch("[^\r\n]+") do
    local entry = line:match("^%s*(trial/[%w_]+/boss/[%w_]+%.lua)%s*$")
    if entry then
        -- Convert path separators and strip .lua extension to get a require path.
        local m = entry:gsub("%.lua$", ""):gsub("[/\\]", ".")
        bossModules[#bossModules + 1] = m
    end
end
mf:close()
table.sort(bossModules)

if #bossModules == 0 then
    fail("no boss modules found  -  run this from the repository root")
end

for _, path in ipairs(bossModules) do
    local ok, class = pcall(require, path)
    if not ok or not class then
        fail("BOSS LOAD     %-40s %s", path, tostring(class))
    elseif type(class.new) ~= "function" then
        fail("NO new()      %-40s boss classes must expose new()", path)
    else
        local instOk, inst = pcall(class.new)
        if not instOk then
            fail("new() THREW   %-40s %s", path, tostring(inst))
        else
            local tracksBars = (class.stateSchema or {}).alertList ~= nil
            local bc = (class.events or {}).beginCast or {}

            -- P1: instant/started symmetry.
            -- Every key in instant must also be in started and vice versa;
            -- an asymmetry almost certainly means a copy-paste omission.
            local instant = bc.instant or {}
            local started = bc.started or {}
            for id in pairs(instant) do
                if not started[id] then
                    fail("BC ASYMMETRY  %-40s id %s in instant but not started",
                         path, tostring(id))
                end
            end
            for id in pairs(started) do
                if not instant[id] then
                    fail("BC ASYMMETRY  %-40s id %s in started but not instant",
                         path, tostring(id))
                end
            end

            if inst.cleanupAlertList == nil then
                fail("NO cleanup    %-40s cleanupAlertList unresolved "
                     .. "(class not linked to BossBase)", path)
            end
            if tracksBars and inst.onDied == nil then
                fail("NO onDied     %-40s declares alertList but cannot stop "
                     .. "its bars on death", path)
            end

            -- P3: onWipe cleanup contract.
            -- Any boss that tracks CA bars (alertList in schema) should declare
            -- onWipe; without it, a wipe leaves bars running into the next pull.
            -- BossBase.cancelPending() handles zo_callLater handles but not CA bars.
            if tracksBars and class.onWipe == nil then
                fail("NO onWipe     %-40s declares alertList but has no onWipe "
                     .. "(bars may survive a wipe)", path)
            end

            -- P8: nameAliases must be plain strings, not Lang.t calls.
            -- (Lang.t returns the key itself when missing, which is also a string,
            -- so the check here is structural: catch non-string values.)
            for _, alias in ipairs(class.nameAliases or {}) do
                if type(alias) ~= "string" then
                    fail("BAD ALIAS     %-40s nameAliases entry is %s, expected string",
                         path, type(alias))
                end
            end
            if type(class.name) ~= "string" and class.name ~= nil then
                fail("BAD NAME      %-40s .name is %s, expected string or nil",
                     path, type(class.name))
            end

            if inst.cleanupAlertList and (not tracksBars or inst.onDied) then
                print(string.format("ok  %-40s alertList=%s",
                      path, tostring(tracksBars)))
            end
        end
    end
end

print("")
if findings == 0 then
    print(string.format("contracts: clean (%d boss modules)", #bossModules))
else
    print(string.format("contracts: %d finding(s)", findings))
end
os.exit(findings == 0 and 0 or 1)
