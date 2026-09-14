local Settings = require("core.Settings")

local ZoneManager = {}

local trials      = {}
local activeZoneId  = nil
local activeTrial   = nil

--- Register a trial module for a zone.
--- @param zoneId      number   ESO zone ID
--- @param trialModule table    Must expose enable() / disable().
--- @param trialId     string   Optional.  When provided, the trial's Settings entry
---                             is checked at zone-enter time; if .enabled == false
---                             the trial stays inactive even while the player is in zone.
---
--- NOTE ON MEMORY: every trial is resident for the whole session, by
--- construction.  ESO executes each file listed in incha.txt at load time,
--- each Factory builds its Trial at file scope, and the Trial object is held
--- here in trials[zoneId].module so re-entering a zone needs no re-require.
--- That keeps every boss class, routing table and constant table reachable.
--- Reducing it would mean building Trials lazily on zone entry, which the
--- manifest load model does not allow without restructuring the Factories.
--- See decision A2 in docs/decisions/architecture.md.
function ZoneManager.registerTrial(zoneId, trialModule, trialId)
    trials[zoneId] = { module = trialModule, trialId = trialId }
end

local function getPlayerZoneId()
    return GetZoneId(GetUnitZoneIndex("player"))
end

local function disableCurrentTrial()
    if activeTrial and activeTrial.disable then
        activeTrial:disable()
    end

    activeTrial  = nil
    activeZoneId = nil
end

-- Per-trial Settings.enabled flag.  Read at zone-enter time and on
-- Settings changes, both after Settings.init() has run, so Settings.get()
-- is always safe here.
local function isTrialEnabledInSettings(entry)
    if not entry.trialId then return true end
    local sv  = Settings.get()
    local tsv = sv and sv.trials[entry.trialId]
    return not (tsv and tsv.enabled == false)
end

local function enableTrialForZone(zoneId)
    local entry = trials[zoneId]
    if not entry then
        disableCurrentTrial()
        return
    end

    if activeZoneId == zoneId and activeTrial then
        return
    end

    disableCurrentTrial()

    if not isTrialEnabledInSettings(entry) then
        return
    end

    activeZoneId = zoneId
    activeTrial  = entry.module
    entry.module:enable()
end

function ZoneManager.onZoneChanged()
    enableTrialForZone(getPlayerZoneId())
end

--- Re-apply the per-trial Settings.enabled flag without a zone change.
--- Called by the settings menu when a trial's Enable checkbox is toggled so
--- the change takes effect immediately while the player is already in the
--- zone: disables the running trial when it was just turned off, and enables
--- the zone's trial when it was just turned on.
function ZoneManager.refresh()
    local zoneId = getPlayerZoneId()
    local entry  = trials[zoneId]
    if not entry then
        disableCurrentTrial()
        return
    end

    local wanted = isTrialEnabledInSettings(entry)
    local running = (activeZoneId == zoneId and activeTrial ~= nil)
    if running and not wanted then
        disableCurrentTrial()
    elseif wanted and not running then
        enableTrialForZone(zoneId)
    end
end

function ZoneManager.getActiveZoneId()
    return activeZoneId
end

--- Return the currently active Trial instance, or nil when not in a trial zone.
function ZoneManager.getActiveTrial()
    return activeTrial
end

package.loaded["core.ZoneManager"] = ZoneManager
return ZoneManager
