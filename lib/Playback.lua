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
---   BEGIN_CAST    -> result=ACTION_RESULT_BEGIN  via CombatHandler.onCombatEvent
---   EFFECT_CHANGED (GAINED / FADED / UPDATED)   via CombatHandler.onEffectChanged
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

local CombatHandler = require("core.CombatHandler")
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
        local routes = isCombat and bossClass.combatRoutes or bossClass.effectRoutes
        if routes and routes[abilityId] then
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
    if CAST_RESULT[kind] then
        if #f < 6 then
            return kind .. ": need >= 6 fields, got " .. #f
        end
        local abilityId    = tonumber(f[6])
        local sourceUnitId = tonumber(f[5])
        if not abilityId then
            return kind .. ": abilityId (f[6]) is not numeric: " .. tostring(f[6])
        end

        local trial = ZoneManager.getActiveTrial()
        if not trial then
            return "no active trial — enter a trial zone first"
        end

        local _, restore, err = prepareBoss(trial, abilityId, true)
        if err then return err end

        local result = CAST_RESULT[kind]
        CombatHandler.onCombatEvent(trial, 0,
            result, false, "", nil, nil,
            "player",  "Player",
            "boss1",   "Boss",
            sourceUnitId or 0, 0,
            abilityId)

        if restore then restore() end

        return kind .. " | abilityId=" .. abilityId .. "  result=" .. result

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

        CombatHandler.onEffectChanged(trial, 0,
            changeType, 0, "", "player",
            0, 0, stackCount, "", 0, 0,
            0, 0, "Player", unitId, abilityId)

        if restore then restore() end

        return "EFFECT_CHANGED | abilityId=" .. abilityId
            .. "  " .. changeName .. "  stacks=" .. stackCount

    else
        return "unsupported type: " .. tostring(kind)
            .. "  (supported: BEGIN_CAST, EFFECT_CHANGED)"
    end
end

package.loaded["lib.Playback"] = Playback
return Playback
