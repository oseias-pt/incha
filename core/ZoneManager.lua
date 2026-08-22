local ZoneManager = {}

local trials = {}
local activeZoneId = nil
local activeTrial = nil

function ZoneManager.registerTrial(zoneId, trialModule)
    trials[zoneId] = trialModule
end

local function getPlayerZoneId()
    return GetZoneId(GetUnitZoneIndex("player"))
end

local function disableCurrentTrial()
    if activeTrial and activeTrial.disable then
        activeTrial.disable()
    end

    activeTrial = nil
    activeZoneId = nil
end

local function enableTrialForZone(zoneId)
    local trialModule = trials[zoneId]
    if not trialModule then
        disableCurrentTrial()
        return
    end

    if activeZoneId == zoneId and activeTrial then
        return
    end

    disableCurrentTrial()

    activeZoneId = zoneId
    activeTrial = trialModule
    trialModule.enable()
end

function ZoneManager.onZoneChanged()
    enableTrialForZone(getPlayerZoneId())
end

function ZoneManager.getActiveZoneId()
    return activeZoneId
end

return ZoneManager
