--- test/harness/unit_tracker.lua
--- Tracks units added/removed during ESO encounter log replay.
---
--- Translates numeric unit IDs from the log into ESO-style unit tags
--- (e.g. "player", "group3", "boss1") so the stub functions DoesUnitExist,
--- GetUnitName, GetUnitDisplayName etc. return realistic values.
---
--- Boss slot assignment (boss1..boss4) follows encounter log order: the
--- first boss-flagged UNIT_ADDED in a zone gets "boss1", the second "boss2",
--- and so on.  Slots reset when clear() is called (zone change).

local UnitTracker = {}
UnitTracker.__index = UnitTracker

function UnitTracker.new()
    return setmetatable({
        byId    = {},  -- [unitId]  -> info
        byTag   = {},  -- [tag]     -> info
        bossSlot = 0,  -- next boss slot index (1-4)
    }, UnitTracker)
end

--- Register a unit from a UNIT_ADDED log entry.
--- @param e table  parsed UNIT_ADDED entry from log_reader
--- @return table   the info table stored for this unit
function UnitTracker:addUnit(e)
    local tag
    if e.isLocalPlayer then
        tag = "player"
    elseif e.unitType == "PLAYER" then
        -- Group members indexed by their group slot.
        tag = "group" .. math.max(1, e.groupIndex)
    elseif e.isBoss then
        self.bossSlot = math.min(self.bossSlot + 1, 4)
        tag = "boss" .. self.bossSlot
    else
        -- Generic NPC / companion  -  use a unique synthetic tag.
        tag = "npc_" .. e.unitId
    end

    local info = {
        id          = e.unitId,
        tag         = tag,
        name        = e.name,
        displayName = e.displayName,
        unitType    = e.unitType,
        isBoss      = e.isBoss,
        groupIndex  = e.groupIndex,
        reaction    = e.reaction,
        health      = nil,  -- populated from combat events when available
    }

    self.byId[e.unitId] = info
    self.byTag[tag]     = info
    return info
end

--- Remove a unit from the tracker (UNIT_REMOVED log entry).
function UnitTracker:removeUnit(unitId)
    local info = self.byId[unitId]
    if info then
        self.byTag[info.tag] = nil
        self.byId[unitId]    = nil
        if info.isBoss then
            -- Allow the slot to be reused if the same boss re-spawns (e.g. wipe).
            self.bossSlot = math.max(0, self.bossSlot - 1)
        end
    end
end

--- Look up a unit by its numeric log ID.
function UnitTracker:getById(unitId)
    return self.byId[unitId]
end

--- Look up a unit by its ESO tag ("player", "boss1", "group3", ...).
function UnitTracker:getByTag(tag)
    return self.byTag[tag]
end

--- Resolve a numeric log unit ID to an ESO tag string.
function UnitTracker:tagById(unitId)
    local info = self.byId[unitId]
    return info and info.tag or ("unknown_" .. tostring(unitId))
end

--- Resolve a numeric log unit ID to a unit name.
function UnitTracker:nameById(unitId)
    local info = self.byId[unitId]
    return info and (info.name or "") or ""
end

--- Update the stored health for a unit (called from COMBAT_EVENT source data).
function UnitTracker:updateHealth(unitId, cur, max)
    local info = self.byId[unitId]
    if info then
        info.health = { cur = cur, max = max }
    end
end

--- Reset boss-slot counter and clear all units (called on zone change).
function UnitTracker:clear()
    self.byId     = {}
    self.byTag    = {}
    self.bossSlot = 0
end

return UnitTracker
