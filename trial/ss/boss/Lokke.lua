--- Lokkestiiz — Sunspire boss 1 (Ice)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-3: Lokke-specific mechanics
---   GlacialFist · IceTomb state machine · LokkeLaser / landing · HP fly thresholds

local SunspireCommon = require("trial.ss.SunspireCommon")

-- ── Ability IDs ────────────────────────────────────────────────────────────
local GLACIAL_FIST    = 120838   -- ice atronarch cast (player or nearby)
local ICE_TOMB        = 119632   -- combat BEGIN → start tomb cycle
local IN_ICE          = 116044   -- combat EFFECT_GAINED/FADED → player in/out tomb
local LASER_1         = 122820   -- flight #1: laser 40 s → landing +12.8 s
local LASER_2         = 122821   -- flight #2: laser 10 s → landing +54.6 s
local LASER_3         = 122822   -- flight #3: laser 32 s → landing +32.1 s
local ICE_EFFECT_CAST = 124687   -- effect GAINED → TombCast signal
local ICE_EFFECT_ARM  = 119638   -- effect GAINED→TombArmed  FADED→TombFaded

-- ── IceTomb display strings (match HTS palette) ───────────────────────────
local sA    = "[|c00ff00A|r]: "
local sB    = "[|c00ff00B|r]: "
local sTake = "|cd92626Take|r "
local sHeal = "|c00ffffHeal|r "
local sDone = "|c00FF00Done|r"
local sInc  = "|c00ffffinc|r"

local NEXT_TOMB = { [0]=1, [1]=2, [2]=3, [3]=1 }   -- iceNumber → next label

-- ── Local helpers ─────────────────────────────────────────────────────────
local function caAlertCast(...)
    if CombatAlerts then return CombatAlerts.AlertCast(...) end
end
local function caCastAlertsStart(...)
    if CombatAlerts then return CombatAlerts.CastAlertsStart(...) end
end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

local function newTombSlots()
    return {
        [1] = { time=0, cast=false, armed=false, taken=false, clear=false, unit=0 },
        [2] = { time=0, cast=false, armed=false, taken=false, clear=false, unit=0 },
    }
end

local function formatTombLabel(slot, prefix, now)
    if not slot.cast then return "" end
    if slot.clear    then return prefix .. sDone end
    local t = slot.time - now
    if t <= 0        then return "" end
    local T = string.format("%.0f", t) .. "s"
    if slot.taken    then return prefix .. sHeal .. T end
    if slot.armed    then return prefix .. sTake .. T end
    return prefix .. sInc
end

-- ── IceTomb state-machine transitions (take self explicitly) ─────────────
local function clearTombs(self)
    self.tCast       = 0
    self.tArmed      = 0
    self.tFaded      = 0
    self.iGained     = 0
    self.iFaded      = 0
    self.tombsClear  = true
    self.iceDouble   = false
    self.checkDouble = true
    self.iceState    = 0
    self.iceTomb     = newTombSlots()
end

local function tombCast(self, time)
    self.tCast = self.tCast + 1
    local slot = self.iceTomb[self.tCast]
    if slot then
        slot.cast = true
        slot.time = time
    end
end

local function tombArmed(self)
    if self.tArmed < 0 then self.tArmed = 0 end
    self.tArmed = self.tArmed + 1
    local slot = self.iceTomb[self.tArmed]
    if slot then
        slot.armed = true
        slot.time  = GetGameTimeMilliseconds() / 1000 + 10
    end
end

local function tombFaded(self)
    if self.tFaded < 0 then self.tFaded = self.tFaded + 1 end
    self.tFaded = self.tFaded + 1

    -- detect double-tomb: both armed slots faded but only 1 player entered
    if self.checkDouble and self.tFaded == 2 and self.iceTomb[2].unit == 0 then
        self.checkDouble = false
        local s = self
        zo_callLater(function()
            s.iceDouble = (s.iGained == 1)
        end, 100)
    end

    local slot = self.iceTomb[self.tFaded]
    if slot then
        slot.armed = false
        if self.iceState == 1 and self.tFaded == 2 then
            self.iceState = 2
        end
    end
end

local function iceGained(self, unitId)
    self.iGained = self.iGained + 1
    local slot = self.iceTomb[self.iGained]
    if slot then
        slot.time   = GetGameTimeMilliseconds() / 1000 + 8
        slot.taken  = true
        if unitId and unitId ~= 0 then slot.unit = unitId end
    end
end

local function iceFaded(self, unitId)
    self.iFaded = self.iFaded + 1
    local taken, clear = 0, 0
    for _, v in pairs(self.iceTomb) do
        if unitId and v.unit == unitId then v.clear = true end
        if v.clear then clear = clear + 1 end
        if v.taken then taken = taken + 1 end
    end
    if (clear == 2) or (self.tFaded == 2 and taken == 1) or (clear == 1 and self.iceDouble) then
        clearTombs(self)
    end
end

-- ── Boss definition ───────────────────────────────────────────────────────
local Lokke = {
    id   = 1,
    key  = "lokke",
    name = "Lokkestiiz",
    -- hmHealthThreshold: measure in-game
}

-- alertList: [sourceUnitId] → CA bar ID (GlacialFist, keyed by atronarch)
Lokke.alertList     = {}
-- IceTomb machine
Lokke.iceNumber     = 0
Lokke.iceTime       = 0      -- s: tomb cast + 13 (cycle display ref)
Lokke.iceNext       = 0      -- s: expected next tomb (cast + 23)
Lokke.prevIce       = 0      -- ms: when last tomb fired
Lokke.tombsClear    = true
Lokke.iceDouble     = false
Lokke.checkDouble   = true
Lokke.iceState      = 0
Lokke.tCast         = 0
Lokke.tArmed        = 0
Lokke.tFaded        = 0
Lokke.iGained       = 0
Lokke.iFaded        = 0
Lokke.iceTomb       = newTombSlots()
-- Laser / landing
Lokke.laserTime     = 0      -- s: absolute time when laser fires
Lokke.landingTime   = 0      -- s: absolute time when boss lands
Lokke.laserBarId    = nil    -- CA bar ID for laser countdown

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Lokke:reset(forced)
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
    caCastAlertsStop(self.laserBarId)
    self.laserBarId  = nil
    self.laserTime   = 0
    self.landingTime = 0
    clearTombs(self)
    self.iceNumber   = 0
    self.iceTime     = 0
    self.iceNext     = 0
    self.prevIce     = 0
end

-- ── Combat events ─────────────────────────────────────────────────────────
function Lokke:onCombatEvent(context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
    -- cross-trial alerts (HA / Block / Leap / Charge / Breath / Spit)
    if SunspireCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    -- alertList cleanup on death (atronarch dies → stop its GlacialFist bar)
    if result == ACTION_RESULT_DIED then
        if unitId then caCastAlertsStop(self.alertList[unitId]); self.alertList[unitId] = nil end
        return
    end

    -- ── GlacialFist ────────────────────────────────────────────────────
    if abilityId == GLACIAL_FIST and result == ACTION_RESULT_BEGIN then
        local show = false
        if IsUnitPlayer(unitTag) then
            if AreUnitsEqual("player", unitTag) then
                show = true
            else
                -- nearby group member — show within 4.5 map units
                SetMapToPlayerLocation()
                local x1, y1 = GetMapPlayerPosition("player")
                local x2, y2 = GetMapPlayerPosition(unitTag)
                if x2 and y2 and math.sqrt((x1-x2)^2 + (y1-y2)^2) * 1000 <= 4.5 then
                    show = true
                end
            end
        end
        if show then
            alerts:showAction("Block! (Glacial Fist)")
            local dur = select(1, GetAbilityCastInfo(GLACIAL_FIST)) or 0
            if dur <= 0 then dur = 1500 end
            local cid = caAlertCast(abilityId, sourceUnitName, dur,
                { -2, 0, false, { 0.3, 0.7, 1.0, 0.4 }, { 0.3, 0.7, 1.0, 0.8 } })
            if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
        end
        return
    end

    -- ── IceTomb BEGIN: start a new tomb cycle ─────────────────────────
    if abilityId == ICE_TOMB and result == ACTION_RESULT_BEGIN then
        local now = GetGameTimeMilliseconds() / 1000
        self.iceTime     = now + 13
        self.iceNext     = now + 23
        self.prevIce     = GetGameTimeMilliseconds()
        self.iceNumber   = self.iceNumber % 3 + 1
        self.tombsClear  = false
        self.iceState    = 1
        self.checkDouble = true
        return
    end

    -- ── InIce: player entered / exited a tomb ─────────────────────────
    if abilityId == IN_ICE then
        if result == ACTION_RESULT_EFFECT_GAINED then
            iceGained(self, unitId)
        elseif result == ACTION_RESULT_EFFECT_FADED then
            iceFaded(self, unitId)
        end
        return
    end

    -- ── LokkeLaser: boss takes flight ─────────────────────────────────
    if result == ACTION_RESULT_BEGIN then
        local now       = GetGameTimeMilliseconds() / 1000
        local laserDelay, landingAfterLaser

        if     abilityId == LASER_1 then laserDelay = 40;   landingAfterLaser = 12.8
        elseif abilityId == LASER_2 then laserDelay = 10;   landingAfterLaser = 54.6
        elseif abilityId == LASER_3 then laserDelay = 32;   landingAfterLaser = 32.1
        end

        if laserDelay then
            caCastAlertsStop(self.laserBarId)
            self.laserTime   = now + laserDelay
            self.landingTime = self.laserTime + landingAfterLaser

            -- CA bar counts down to laser fire
            self.laserBarId = caCastAlertsStart(
                abilityId, "Laser",
                laserDelay * 1000, laserDelay * 1000,
                { 1, 0.7, 0, 0.5 },
                { laserDelay * 1000, "LASER!", 1, 0.5, 0, 0.9, SOUNDS.NONE })

            -- reset iceNumber once boss is airborne (10 s in)
            local s = self
            zo_callLater(function()
                s.iceNumber = 0
                s.prevIce   = 0
            end, 10000)
        end
    end
end

-- ── Effect changes ────────────────────────────────────────────────────────
function Lokke:onEffectChanged(context, alerts, changeType, abilityId, unitTag, unitId, unitName)
    -- effect 124687: cast signal (gained = tomb is being cast)
    if abilityId == ICE_EFFECT_CAST then
        if changeType == EFFECT_RESULT_GAINED then
            tombCast(self, GetGameTimeMilliseconds() / 1000)
        end
        return
    end

    -- effect 119638: arm/disarm signal (gained = tomb ready to enter, faded = window closed)
    if abilityId == ICE_EFFECT_ARM then
        if     changeType == EFFECT_RESULT_GAINED then tombArmed(self)
        elseif changeType == EFFECT_RESULT_FADED  then tombFaded(self)
        end
        return
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Lokke:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000

    -- ── Info 4: laser → landing → HP "can fly" ─────────────────────────
    local laser   = self.laserTime   - now
    local landing = self.landingTime - now
    if laser > 0 then
        alerts:showInfo(4, "|c7fffd4Laser|r: " .. string.format("%.0f", laser) .. "s")
    elseif landing > 0 then
        alerts:showInfo(4, "|c5cd65cLanding|r: " .. string.format("%.0f", landing) .. "s")
    else
        local hp = context.extras.healthPercent
        if hp and hp > 20 then
            local flyAt
            if     hp >= 81 then flyAt = 81
            elseif hp >= 51 then flyAt = 51
            elseif hp >= 21 then flyAt = 21
            end
            if flyAt and (hp - flyAt) <= 5 then
                alerts:showInfo(4, "|cffa500Can Fly In|r: " ..
                    string.format("%.1f", hp - flyAt) .. "%")
            else
                alerts:showInfo(4, "")
            end
        else
            alerts:showInfo(4, "")
        end
    end

    -- ── Info 1-3: IceTomb display ──────────────────────────────────────
    -- Boss is considered flying when iceNumber==0 or timestamps say so.
    local isFlying = (self.iceNumber == 0)
        or (self.laserTime   > 0 and now < self.laserTime)
        or (self.landingTime > 0 and now < self.landingTime)

    if self.tombsClear then
        if isFlying or not IsUnitInCombat("player") then
            alerts:showInfo(1, "")
            alerts:showInfo(2, "")
            alerts:showInfo(3, "")
        else
            -- grounded, waiting for next tomb
            local T2 = self.iceNext - now
            local iN = NEXT_TOMB[self.iceNumber]
            local header
            if T2 <= 0 then
                header = "|c00ffffIce Tomb|r |cff0000" .. iN .. "|r |cff0000INC|r"
            else
                header = "|c00ffffIce Tomb|r |cff0000" .. iN ..
                         "|r |c00ffffin|r: " .. string.format("%.0f", T2) .. "s"
            end
            alerts:showInfo(1, header)
            alerts:showInfo(2, "")
            alerts:showInfo(3, "")
        end
    else
        -- active tomb cycle: show per-slot status
        alerts:showInfo(1, "|c00ffffIce Tomb|r |cff0000" .. self.iceNumber .. "|r")
        alerts:showInfo(2, formatTombLabel(self.iceTomb[1], sA, now))
        if self.iceDouble then
            alerts:showInfo(3, sB .. "|c00ff00Double|r")
        else
            alerts:showInfo(3, formatTombLabel(self.iceTomb[2], sB, now))
        end
    end
end

return Lokke
