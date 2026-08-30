--- test/harness/log_reader.lua
--- Parse ESO encounter log files into a flat list of event tables.
---
--- Supported entry types (others are silently skipped):
---   BEGIN_LOG, ZONE_CHANGED, UNIT_ADDED, UNIT_REMOVED,
---   COMBAT_EVENT, EFFECT_CHANGED, TRIAL_INIT
---
--- Log format reference:
---   Column 1  : ms offset from session start
---   Column 2  : entry type keyword
---   Columns 3+: type-specific fields, comma-separated; string fields quoted
---
--- The first line of an archive file may carry a "vvvvvvvvv" garbage
--- prefix written by the ESO log-rotation mechanism  -  it is stripped.

local LogReader = {}

-- -- ESO result-string -> numeric constant mappings -------------------------
-- Values must stay in sync with eso_api.lua assignments so equality checks
-- inside boss routing tables fire correctly.
local COMBAT_RESULT = {
    BEGIN                  = 4,
    DIED                   = 38,
    DIED_XP                = 38,   -- treat same as DIED for routing purposes
    EFFECT_FADED           = 5,
    EFFECT_GAINED          = 6,
    EFFECT_GAINED_DURATION = 7,
    INTERRUPT              = 65,
}

local EFFECT_CHANGE = {
    GAINED  = 1,
    FADED   = 2,
    UPDATED = 3,
}

-- -- CSV parser -------------------------------------------------------------
-- Handles quoted strings (which may contain commas) and unquoted fields.
-- Quoted strings in the ESO log never contain escaped quotes, so a single
-- closing-quote scan is sufficient.
local function splitFields(line)
    local fields = {}
    local i, len = 1, #line

    while i <= len do
        local c = line:sub(i, i)
        if c == '"' then
            -- Quoted field: scan forward for the matching closing quote.
            local j = line:find('"', i + 1, true)
            if j then
                fields[#fields + 1] = line:sub(i + 1, j - 1)
                i = j + 2  -- skip closing " and the following comma
            else
                -- Unterminated quote  -  take the rest of the line.
                fields[#fields + 1] = line:sub(i + 1)
                break
            end
        else
            -- Unquoted field: scan to next comma (or end of line).
            local j = line:find(",", i, true)
            if j then
                fields[#fields + 1] = line:sub(i, j - 1)
                i = j + 1
            else
                fields[#fields + 1] = line:sub(i)
                break
            end
        end
    end

    return fields
end

-- -- X/Y health field parser ------------------------------------------------
local function parseSlashPair(s)
    local a, b = s:match("^(%d+)/(%d+)$")
    return tonumber(a) or 0, tonumber(b) or 0
end

-- -- Per-type parsers -------------------------------------------------------

local function parseBeginLog(f, ms)
    return {
        type      = "BEGIN_LOG",
        ms        = ms,
        timestamp = tonumber(f[3]),
        version   = f[5] or "",  -- "eso.live.10.3" etc.
    }
end

local function parseZoneChanged(f, ms)
    return {
        type     = "ZONE_CHANGED",
        ms       = ms,
        zoneId   = tonumber(f[3]),
        zoneName = f[4] or "",
    }
end

local function parseUnitAdded(f, ms)
    -- f[3]=unitId  f[4]=unitType  f[5]=isLocal  f[6]=groupIndex
    -- f[7]=monsterId  f[8]=isBoss  f[9]=classId  f[10]=raceId
    -- f[11]=name  f[12]=displayName  f[13]=charId
    -- f[14]=level  f[15]=cp  f[16]=ownerUnitId  f[17]=reaction  f[18]=isGrouped
    if #f < 17 then return nil end
    return {
        type        = "UNIT_ADDED",
        ms          = ms,
        unitId      = tonumber(f[3]),
        unitType    = f[4] or "",
        isLocalPlayer = (f[5] == "T"),
        groupIndex  = tonumber(f[6]) or 0,
        monsterId   = tonumber(f[7]) or 0,
        isBoss      = (f[8] == "T"),
        classId     = tonumber(f[9]) or 0,
        raceId      = tonumber(f[10]) or 0,
        name        = f[11] or "",
        displayName = f[12] or "",
        charId      = f[13] or "",
        level       = tonumber(f[14]) or 0,
        cp          = tonumber(f[15]) or 0,
        ownerUnitId = tonumber(f[16]) or 0,
        reaction    = f[17] or "",
    }
end

local function parseUnitRemoved(f, ms)
    return {
        type   = "UNIT_REMOVED",
        ms     = ms,
        unitId = tonumber(f[3]),
    }
end

local function parseTrialInit(f, ms)
    return {
        type    = "TRIAL_INIT",
        ms      = ms,
        trialId = tonumber(f[3]),
    }
end

local function parseCombatEvent(f, ms)
    -- f[3]=result  f[4]=dmgType  f[5]=value  f[6]=overflow
    -- f[7]=castTrackId  f[8]=eventId  f[9]=abilityId
    -- f[10]=sourceUnitId  f[11..19]=source vitals+pos
    -- f[20]=targetUnitId (* = self-targeted / no target)  f[21+]=target vitals+pos
    if #f < 19 then return nil end

    local sourceUnitId = tonumber(f[10])
    local targetField  = f[20]
    local targetUnitId
    if targetField and targetField ~= "*" then
        targetUnitId = tonumber(targetField)
    else
        -- Self-targeted or no explicit target: treat source as target.
        targetUnitId = sourceUnitId
    end

    -- Parse source health from f[11] ("cur/max").
    local srcHealthCur, srcHealthMax = parseSlashPair(f[11] or "0/0")

    return {
        type         = "COMBAT_EVENT",
        ms           = ms,
        result       = COMBAT_RESULT[f[3]] or 0,
        resultName   = f[3] or "",
        abilityId    = tonumber(f[9]),
        sourceUnitId = sourceUnitId,
        targetUnitId = targetUnitId,
        srcHealthCur = srcHealthCur,
        srcHealthMax = srcHealthMax,
    }
end

local function parseEffectChanged(f, ms)
    -- f[3]=changeType  f[4]=stackCount  f[5]=sourceUnitId (caster)
    -- f[6]=abilityId   f[7]=unitId (unit the effect is ON)
    -- f[8]=health  f[9]=magicka  f[10]=stamina  f[11]=ultimate
    -- f[12]=ww  f[13]=shield  f[14]=x  f[15]=y  f[16]=heading
    -- f[17]=target (* or unitId)
    if #f < 7 then return nil end

    return {
        type           = "EFFECT_CHANGED",
        ms             = ms,
        changeType     = EFFECT_CHANGE[f[3]] or 0,
        changeTypeName = f[3] or "",
        stackCount     = tonumber(f[4]) or 0,
        sourceUnitId   = tonumber(f[5]),
        abilityId      = tonumber(f[6]),
        unitId         = tonumber(f[7]),
    }
end

-- -- Entry dispatch ---------------------------------------------------------

local PARSERS = {
    BEGIN_LOG      = parseBeginLog,
    ZONE_CHANGED   = parseZoneChanged,
    UNIT_ADDED     = parseUnitAdded,
    UNIT_REMOVED   = parseUnitRemoved,
    TRIAL_INIT     = parseTrialInit,
    COMBAT_EVENT   = parseCombatEvent,
    EFFECT_CHANGED = parseEffectChanged,
}

-- -- Public API -------------------------------------------------------------

--- Read an ESO encounter log file and return a list of parsed event tables.
--- Unknown entry types are silently skipped; malformed lines are skipped and
--- counted. Returns entries, errorCount.
function LogReader.readFile(path)
    local f = assert(io.open(path, "r"), "cannot open log: " .. path)

    local entries   = {}
    local errorCount = 0
    local lineNo    = 0

    for line in f:lines() do
        lineNo = lineNo + 1

        -- Strip the "vvvvvvvvv" leader written by ESO's log-rotation on the
        -- very first line of an archive file, and any other leading non-digits.
        if lineNo == 1 or line:sub(1,1) == "v" then
            line = line:match("^[^%d]*(.*)")
        end

        if line and line ~= "" then
            local ok, result = pcall(function()
                local fields = splitFields(line)
                if #fields < 2 then return nil end

                local ms       = tonumber(fields[1])
                local kind     = fields[2]
                if not ms or not kind then return nil end

                local parser = PARSERS[kind]
                if parser then
                    return parser(fields, ms)
                end
                return nil
            end)

            if ok and result then
                entries[#entries + 1] = result
            elseif not ok then
                errorCount = errorCount + 1
                -- Uncomment for debugging: io.stderr:write("line " .. lineNo .. ": " .. tostring(result) .. "\n")
            end
        end
    end

    f:close()
    return entries, errorCount
end

--- Expose the constant maps so callers can inspect them if needed.
LogReader.COMBAT_RESULT = COMBAT_RESULT
LogReader.EFFECT_CHANGE = EFFECT_CHANGE

return LogReader
