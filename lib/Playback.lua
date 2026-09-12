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
---   BEGIN_CAST    -> result=ACTION_RESULT_BEGIN  via EventDispatcher.onCombatEventFiltered
---   EFFECT_CHANGED (GAINED / FADED / UPDATED)   via EventDispatcher.onEffectChangedFiltered
---
--- Field layout (ESO encounter-log reference):
---   BEGIN_CAST:    f[1]=ms  f[2]=BEGIN_CAST  f[3]=castDuration  f[4]=channeled
---                  f[5]=sourceUnitId  f[6]=abilityId  ...
---   EFFECT_CHANGED: f[1]=ms  f[2]=EFFECT_CHANGED  f[3]=changeType
---                  f[4]=stackCount  f[5]=sourceUnitId  f[6]=abilityId  f[7]=unitId  ...
---
--- If no boss is currently active (player not in arena), Playback searches the
--- trial's boss registry for the class that owns the abilityId, creates a fresh
--- temporary instance, and dispatches through it so alerts fire without needing
--- a live pull.  The temp instance is discarded immediately after the call.
---
--- unitTag / unitName / sourceUnitName are faked; routing tables key on
--- abilityId + result/changeType so the correct handler still fires.

local EventDispatcher = require("core.EventDispatcher")
local ZoneManager   = require("core.ZoneManager")

local Playback = {}

-- ── Field splitter ─────────────────────────────────────────────────────────
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

-- ── ESO-constant maps (resolved at module-load time) ─────────────────────
local CAST_RESULT = {
    BEGIN_CAST = ACTION_RESULT_BEGIN,
}

-- COMBAT_EVENT log field layout (from log_reader.lua):
--   f[3]=result  f[4]=dmgType  f[5]=value  f[6]=overflow
--   f[7]=castTrackId  f[8]=eventId  f[9]=abilityId  f[10]=sourceUnitId
local COMBAT_EVENT_RESULT = {
    BEGIN                  = ACTION_RESULT_BEGIN,
    EFFECT_GAINED          = ACTION_RESULT_EFFECT_GAINED,
    EFFECT_FADED           = ACTION_RESULT_EFFECT_FADED,
    EFFECT_GAINED_DURATION = ACTION_RESULT_EFFECT_GAINED_DURATION,
    INTERRUPT              = ACTION_RESULT_INTERRUPT,
    DIED                   = ACTION_RESULT_DIED,
}

local EFFECT_CHANGE = {
    GAINED  = EFFECT_RESULT_GAINED,
    FADED   = EFFECT_RESULT_FADED,
    UPDATED = EFFECT_RESULT_UPDATED,
}

-- ── Boss lookup ────────────────────────────────────────────────────────────
--- Return the first boss class in the trial whose combatRoutes or effectRoutes
--- table contains abilityId.  Returns nil when no boss claims the ability.
local function findBossClass(trial, abilityId, isCombat)
    for _, bossClass in ipairs(trial.registry.bosses) do
        local combat, effect = EventDispatcher.abilityIdsFor(bossClass)
        local ids = isCombat and combat or effect
        if ids[abilityId] then
            return bossClass
        end
    end
    return nil
end

--- Ensure an active boss instance exists for dispatching.
--- If one is already active, returns it untouched (restore = nil).
--- If none is active and the abilityId belongs to a boss in the registry,
--- creates a fresh temp instance, injects it, and returns it + a restore fn.
--- Returns (instance, restore_fn, err_string).
local function prepareBoss(trial, abilityId, isCombat)
    local existing = trial:getActiveBoss()
    if existing then
        return existing, nil, nil
    end

    local bossClass = findBossClass(trial, abilityId, isCombat)
    if not bossClass then
        return nil, nil,
            "abilityId=" .. abilityId .. " is not in any boss's routing table"
            .. " for this trial"
    end

    local tempInstance = bossClass.new()
    trial.activeBosses[1] = tempInstance

    local function restore()
        trial.activeBosses[1] = nil
    end

    return tempInstance, restore, nil
end

-- ── Public API ─────────────────────────────────────────────────────────────

--- Parse and inject one raw encounter-log line into the active trial.
--- Returns a short status string suitable for printing to chat.
function Playback.injectLine(line)
    line = line:gsub("^%s+", ""):gsub("%s+$", "")   -- trim (no lazy patterns)
    if not line or line == "" then return "empty line" end

    local f = split(line)
    if #f < 3 then
        return "too few fields (" .. #f .. ")"
    end

    local kind = f[2]

    -- ── BEGIN_CAST ──────────────────────────────────────────────────────────
    if kind == "BEGIN_CAST" then
        if #f < 6 then
            return "BEGIN_CAST: need >= 6 fields, got " .. #f
        end
        local castDuration = tonumber(f[3]) or 0   -- use log-line value, not GetAbilityCastInfo
        local abilityId    = tonumber(f[6])
        local sourceUnitId = tonumber(f[5]) or 0
        if not abilityId then
            return "BEGIN_CAST: abilityId (f[6]) is not numeric: " .. tostring(f[6])
        end

        local trial = ZoneManager.getActiveTrial()
        if not trial then
            return "no active trial — enter a trial zone first"
        end

        local boss, restore, err = prepareBoss(trial, abilityId, true)
        if err then return err end

        -- Call dispatchBeginCast directly so the cast duration from the log line
        -- is used instead of GetAbilityCastInfo (which returns 0 for unloaded abilities).
        EventDispatcher.dispatchBeginCast(boss, trial.context, trial.alerts,
            castDuration, false, sourceUnitId, abilityId, "Boss")

        if restore then restore() end

        return "BEGIN_CAST | abilityId=" .. abilityId .. "  castDuration=" .. castDuration

    -- ── EFFECT_CHANGED ──────────────────────────────────────────────────────
    elseif kind == "EFFECT_CHANGED" then
        if #f < 7 then
            return "EFFECT_CHANGED: need >= 7 fields, got " .. #f
        end
        local changeName = (f[3] or ""):upper()
        local changeType = EFFECT_CHANGE[changeName]
        if not changeType then
            return "EFFECT_CHANGED: unknown changeType: " .. tostring(f[3])
        end
        local stackCount = tonumber(f[4]) or 0
        local abilityId  = tonumber(f[6])
        local unitId     = tonumber(f[7]) or 0
        if not abilityId then
            return "EFFECT_CHANGED: abilityId (f[6]) not numeric: " .. tostring(f[6])
        end

        local trial = ZoneManager.getActiveTrial()
        if not trial then
            return "no active trial — enter a trial zone first"
        end

        local _, restore, err = prepareBoss(trial, abilityId, false)
        if err then return err end

        EventDispatcher.onEffectChangedFiltered(trial, 0,
            changeType, 0, "", "player",
            0, 0, stackCount, "", 0, 0,
            0, 0, "Player", unitId, abilityId)

        if restore then restore() end

        return "EFFECT_CHANGED | abilityId=" .. abilityId
            .. "  " .. changeName .. "  stacks=" .. stackCount

    -- ── COMBAT_EVENT ────────────────────────────────────────────────────────
    elseif kind == "COMBAT_EVENT" then
        -- f[3]=result  f[9]=abilityId  f[10]=sourceUnitId
        if #f < 10 then
            return "COMBAT_EVENT: need >= 10 fields, got " .. #f
        end
        local resultName = (f[3] or ""):upper()
        local result     = COMBAT_EVENT_RESULT[resultName]
        if not result then
            return "COMBAT_EVENT: unknown result: " .. tostring(f[3])
        end
        local abilityId    = tonumber(f[9])
        local sourceUnitId = tonumber(f[10])
        if not abilityId then
            return "COMBAT_EVENT: abilityId (f[9]) not numeric: " .. tostring(f[9])
        end

        local trial = ZoneManager.getActiveTrial()
        if not trial then return "no active trial — enter a trial zone first" end

        local _, restore, err = prepareBoss(trial, abilityId, true)
        if err then return err end

        EventDispatcher.onCombatEventFiltered(trial, 0,
            result, false, "", nil, nil,
            "player",  "Player",
            "boss1",   "Boss",
            sourceUnitId or 0, 0,
            abilityId)

        if restore then restore() end

        return "COMBAT_EVENT | abilityId=" .. abilityId
            .. "  result=" .. resultName

    else
        return "unsupported type: " .. tostring(kind)
            .. "  (supported: BEGIN_CAST, COMBAT_EVENT, EFFECT_CHANGED)"
    end
end

package.loaded["lib.Playback"] = Playback
return Playback
