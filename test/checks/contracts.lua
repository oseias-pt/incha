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

local bossModules = {}
local p = io.popen('find trial -path "*/boss/*.lua" 2>/dev/null')
for line in p:lines() do
    local m = line:gsub("%s+$", ""):gsub("^%./", ""):gsub("%.lua$", "")
    bossModules[#bossModules + 1] = (m:gsub("[/\\]", "."))
end
p:close()
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

            if inst.cleanupAlertList == nil then
                fail("NO cleanup    %-40s cleanupAlertList unresolved "
                     .. "(class not linked to BossBase)", path)
            end
            if tracksBars and inst.onDied == nil then
                fail("NO onDied     %-40s declares alertList but cannot stop "
                     .. "its bars on death", path)
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
