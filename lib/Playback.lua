--- lib/Playback.lua  —  inject raw ESO encounter-log lines as live events.
---
--- Lets you replay a single line pasted from a live log file to verify that
--- the corresponding alert fires correctly without needing a full raid pull.
---
--- Usage (from /ip slash command):
---   /ip 225534,BEGIN_CAST,2000,F,34218181,133515,...
---   /ip 12345,EFFECT_CHANGED,GAINED,0,34218181,132473,48707525,...
---
--- Supported entry types:
---   BEGIN_CAST    -> CombatHandler.onCombatEvent with result=ACTION_RESULT_BEGIN
---   EFFECT_CHANGED (GAINED / FADED / UPDATED)
---                 -> CombatHandler.onEffectChanged
---
--- Field layout (from ESO encounter-log reference):
---
---   BEGIN_CAST:
---     f[1]=ms  f[2]=BEGIN_CAST  f[3]=castDuration  f[4]=channeled(T/F)
---     f[5]=sourceUnitId  f[6]=abilityId  ...
---
---   EFFECT_CHANGED:
---     f[1]=ms  f[2]=EFFECT_CHANGED  f[3]=changeType(GAINED/FADED/UPDATED)
---     f[4]=stackCount  f[5]=sourceUnitId  f[6]=abilityId  f[7]=unitId  ...
---
--- unitTag / unitName / sourceUnitTag / sourceUnitName are faked because the
--- log does not store runtime unit tags.  Routing tables key on abilityId and
--- result/changeType, so the correct handler still fires; CA bars will show
--- "Boss"/"Player" as placeholder names.
---
--- Requires: core.CombatHandler  core.ZoneManager  (both must be loaded first)

local CombatHandler = require("core.CombatHandler")
local ZoneManager   = require("core.ZoneManager")

local Playback = {}

-- ── Field splitter ────────────────────────────────────────────────────────
-- ESO log lines never quote numeric fields; only UNIT_ADDED name fields are
-- quoted, and we do not parse those here.
local function split(line)
    local fields = {}
    local i, len = 1, #line
    while i <= len do
        local j = line:find(",", i, true)
        if j then
            fields[#fields + 1] = line:sub(i, j - 1)
            i = j + 1
        else
            fields[#fields + 1] = line:sub(i)
            break
        end
    end
    return fields
end

-- ── ESO-constant maps (resolved at module-load time so the globals are live) ──
-- ACTION_RESULT_* come from ESO; values match what boss routing tables compare.
local CAST_RESULT = {
    BEGIN_CAST = ACTION_RESULT_BEGIN,
    -- END_CAST produces no useful routing target — boss handlers
    -- check ACTION_RESULT_BEGIN, not ACTION_RESULT_COMPLETED.
}

-- EFFECT_RESULT_* values (1/2/3) match the log's GAINED/FADED/UPDATED strings
-- AND the ESO EFFECT_RESULT_* globals in ESO's real API.
local EFFECT_CHANGE = {
    GAINED  = EFFECT_RESULT_GAINED,
    FADED   = EFFECT_RESULT_FADED,
    UPDATED = EFFECT_RESULT_UPDATED,
}

-- ── Public API ────────────────────────────────────────────────────────────

--- Parse and inject one raw encounter-log line into the active trial.
--- Returns a short status string suitable for printing to chat.
function Playback.injectLine(line)
    line = line:match("^%s*(.-)%s*$")  -- trim whitespace
    if not line or line == "" then return "empty line" end

    local f = split(line)
    if #f < 3 then
        return "too few fields (" .. #f .. ")"
    end

    local kind = f[2]

    -- ── BEGIN_CAST ────────────────────────────────────────────────────────
    if CAST_RESULT[kind] then
        -- f[5]=sourceUnitId  f[6]=abilityId
        if #f < 6 then
            return kind .. ": need >= 6 fields, got " .. #f
        end
        local abilityId    = tonumber(f[6])
        local sourceUnitId = tonumber(f[5])
        if not abilityId then
            return kind .. ": abilityId (f[6]) is not numeric: " .. tostring(f[6])
        end

        local trial = ZoneManager.getActiveTrial()
        if not trial then return "no active trial — enter a trial zone first" end

        local result = CAST_RESULT[kind]
        -- unitTag/sourceUnitTag are faked; routing tables key on abilityId+result only.
        CombatHandler.onCombatEvent(trial, 0,
            result, false, "", nil, nil,
            "player",   "Player",
            "boss1",    "Boss",
            sourceUnitId or 0, 0,
            abilityId)

        return kind .. " | abilityId=" .. abilityId
            .. "  result=" .. result
            .. (ZoneManager.getActiveTrial():getActiveBoss() and "" or
                "  (warning: no boss detected — enter boss arena)")

    -- ── EFFECT_CHANGED ────────────────────────────────────────────────────
    elseif kind == "EFFECT_CHANGED" then
        -- f[3]=changeType  f[4]=stackCount  f[5]=sourceUnitId
        -- f[6]=abilityId   f[7]=unitId
        if #f < 7 then
            return "EFFECT_CHANGED: need >= 7 fields, got " .. #f
        end
        local changeName = (f[3] or ""):upper()
        local changeType = EFFECT_CHANGE[changeName]
        if not changeType then
            return "EFFECT_CHANGED: unknown changeType: " .. tostring(f[3])
        end
        local stackCount   = tonumber(f[4]) or 0
        local abilityId    = tonumber(f[6])
        local unitId       = tonumber(f[7]) or 0
        if not abilityId then
            return "EFFECT_CHANGED: abilityId (f[6]) is not numeric: " .. tostring(f[6])
        end

        local trial = ZoneManager.getActiveTrial()
        if not trial then return "no active trial — enter a trial zone first" end

        CombatHandler.onEffectChanged(trial, 0,
            changeType, 0, "", "player",
            0, 0, stackCount, "", 0, 0,
            0, 0, "Player", unitId, abilityId)

        return "EFFECT_CHANGED | abilityId=" .. abilityId
            .. "  changeType=" .. changeName
            .. "  stacks=" .. stackCount

    else
        return "unsupported type: " .. tostring(kind)
            .. "  (supported: BEGIN_CAST, EFFECT_CHANGED)"
    end
end

package.loaded["lib.Playback"] = Playback
return Playback
