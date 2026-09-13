--- lib/SubBoss.lua  -  Per-unit state group for compound encounters.
---
--- Compound encounters (OlmsEncounter, ZmajaEncounter, …) track multiple
--- independent named units within one class object.  Without a shared
--- abstraction each sub-boss's active flag, timers and spawn timestamp live
--- as scattered top-level fields, making onWipe error-prone and the schema
--- hard to read.
---
--- SubBoss groups one unit's state together.  Declare it in stateSchema:
---
---   Boss.stateSchema = {
---       -- Keep SubBoss.new({}) on ONE line: test/checks/filters.lua scans for
---       -- duplicate stateSchema keys by matching "identifier =" at line start,
---       -- and inner timer keys on separate lines read as duplicate schema entries.
---       siro = function() return SubBoss.new({ jump = Timer.new(23), banner = Timer.new(45) }) end,
---       rele = function() return SubBoss.new({ jump = Timer.new(19), bash = Timer.new(20) }) end,
---       alertList = function() return {} end,
---   }
---
--- BossBase.fromSchema and resetSchema call the function to produce a fresh
--- SubBoss instance (all timers idle, active = false).
---
--- Field access:
---   boss.siro.active           -- true while the unit is alive/active
---   boss.siro.jump:remaining() -- timer access by name
---   boss.siro.spawnGs          -- game-time second when the unit spawned (nil until set)
---
--- Helper methods (call on the sub-boss object):
---   sb:activate([spawnGs])  -- mark unit active; record optional spawn timestamp
---   sb:deactivate()         -- mark unit inactive, clear spawnGs
---   sb:resetTimers()        -- clear all registered timers (active state unchanged)
---   sb:reset()              -- full reset: deactivate + clear all timers
---
--- onWipe pattern:
---   function Boss:onWipe()
---       self:cleanupAlertList()
---       BossBase.resetSchema(self, Boss)  -- re-creates all SubBoss instances
---   end
---
--- Note: alertList is not stored inside SubBoss.  Most compound encounters use
--- a single shared alertList keyed by unitId, which naturally covers all
--- sub-bosses.  If a boss needs per-sub-boss alertLists, add them to the schema
--- as separate function() return {} end entries and clean them manually in onLeave.

local SubBoss = {}
SubBoss.__index = SubBoss

--- Create a new SubBoss with the given named timers.
---
--- @param timers table   { name = Timer instance, … }  Timer instances for
---                       each mechanic tracked for this unit.  Keys become
---                       direct fields on the SubBoss object (e.g. sb.jump).
--- @return SubBoss
function SubBoss.new(timers)
    local sb = setmetatable({
        active  = false,
        spawnGs = nil,
    }, SubBoss)
    -- Expose each timer as a direct field so callers can write sb.jump:remaining()
    -- rather than sb._timers.jump:remaining().
    sb._timerKeys = {}
    for name, timer in pairs(timers or {}) do
        sb[name] = timer
        sb._timerKeys[#sb._timerKeys + 1] = name
    end
    return sb
end

--- Mark this unit as active.  Optionally records the game-time second (from
--- GetGameTimeMilliseconds() / 1000) when the unit spawned, for seeding timers
--- with a delay accounting for load time.
---
--- @param spawnGs number|nil   optional spawn game-time (seconds)
function SubBoss:activate(spawnGs)
    self.active  = true
    self.spawnGs = spawnGs or nil
end

--- Mark this unit as inactive and clear the spawn timestamp.
--- Does NOT clear timers — call resetTimers() separately if needed.
function SubBoss:deactivate()
    self.active  = false
    self.spawnGs = nil
end

--- Clear all registered timers (set each to idle / expiresAt == 0).
--- Does not change the active flag.
function SubBoss:resetTimers()
    for _, name in ipairs(self._timerKeys) do
        self[name]:clear()
    end
end

--- Full reset: deactivate this unit and clear all its timers.
--- This is what BossBase.resetSchema calls indirectly (by replacing the whole
--- SubBoss via the schema function), so you only need to call reset() explicitly
--- when you want partial cleanup without going through the schema.
function SubBoss:reset()
    self:deactivate()
    self:resetTimers()
end

package.loaded["lib.SubBoss"] = SubBoss
return SubBoss
