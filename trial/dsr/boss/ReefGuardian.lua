--- ReefGuardian — Dreadsail Reef boss 2
---
--- Phase DSR-4: full mechanics
---   BuildingStatic (163575 / 169688): GAINED/UPDATED/FADED → stack tracker
---   VolatileResidue (174835 / 174932): GAINED/UPDATED/FADED → stack tracker
---   Sheltered (163571): GAINED → playerSheltered = true; FADED → false
---   Heartburn (163692): BEGIN → portal opened (reef opening begins)
---   HeartburnEffect (166036): EFFECT_GAINED → 60 s wipe timer starts
---   AcidReflux (163702): BEGIN → CastAlertsStart 10 s + 5 acid pool bars
---   CrabMonstrousClaw (166582): BEGIN + player → AlertCast
---   Crush (166019) / Claw (166020): BEGIN + player → AlertCast
---   CoralDriftBearCrackdown (166586): BEGIN + player → AlertCast
---   KingOrnumFireDebuff (175832): EFFECT_GAINED + player → Alert
---   AcidicVulnerability (174659): GAINED/FADED → track for info4

local DreadsailCommon = require("trial.dsr.DreadsailCommon")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local BUILDING_STATIC_1    = 163575   -- lightning stack effect 1
local BUILDING_STATIC_2    = 169688   -- lightning stack effect 2
local VOLATILE_RESIDUE_1   = 174835   -- poison stack effect 1
local VOLATILE_RESIDUE_2   = 174932   -- poison stack effect 2
local SHELTERED            = 163571   -- cleanse / immunity aura
local HEARTBURN            = 163692   -- reef portal cast (BEGIN)
local HEARTBURN_EFFECT     = 166036   -- reef portal tick (EFFECT_CHANGED)
local ACID_REFLUX          = 163702   -- acid channel cast
local ACID_POOL            = 165987   -- acid pool placed by reflux
local CRAB_MONSTROUS_CLAW  = 166582   -- portal crab heavy
local CRAB_SWIPE           = 166584   -- portal crab swipe
local CRUSH                = 166019   -- main boss heavy 1
local CLAW_ATTACK          = 166020   -- main boss heavy 2
local CRACKDOWN            = 166586   -- bear-crab heavy
local KING_ORGNUM_FIRE_DBF = 175832   -- debuff placed by Orgnum fire orb
local ACIDIC_VULN          = 174659   -- vulnerability debuff (5 s)
local REPLICATION          = 163701   -- boss replication cast

-- ── Timing constants ─────────────────────────────────────────────────────
local PORTAL_WIPE_TIME     = 60       -- s: portal wipe timer after opening
local ACID_INTERVAL        = 1750     -- ms: acid pool spacing
local ACID_COUNT           = 5        -- number of acid pools per Reflux
local SHELTERED_WINDOW     = 3        -- s: keep "CLEANSED" label brief

local CA = require("lib.CA")

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_HEAVY   = { -2, 0, false, { 1.0, 0.35, 0.1, 0.4 }, { 1.0, 0.35, 0.1, 0.8 } }
local COL_ACID    = { 0.4, 0.9, 0.2, 0.5 }
local ACT_ACID    = { 8000, "MOVE OUT!", 0.3, 0.9, 0.1, 0.9, nil }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 1500   -- heavy melee (Crush/Claw/Crackdown): empirical

-- ── Boss definition ───────────────────────────────────────────────────────
local ReefGuardian = {}
ReefGuardian.__index = ReefGuardian
ReefGuardian.common = DreadsailCommon   -- C3: common mechanic dispatch

ReefGuardian.key              = "reef_guardian"
ReefGuardian.name             = "Reef Guardian"   -- TODO: verify via GetUnitName("boss1") in-game
ReefGuardian.hmHealthThreshold = 100000001         -- TODO: verify

function ReefGuardian.new()
    return setmetatable({
        buildingStaticStacks   = 0,
        buildingStaticEndTime  = 0,
        volatileResidueStacks  = 0,
        volatileResidueEndTime = 0,
        playerSheltered        = false,
        lastShelteredTime      = 0,   -- for brief "CLEANSED" label in info1/2

        -- Reef portals: up to 3 can be open simultaneously.
        -- Each entry: { openTime, wipeActive }
        reefPortals   = {},   -- table of open reef timers
        reefNum       = 0,    -- total reefs opened (sequential)

        acidicVulnLast  = 0,   -- time GAINED; 0 when inactive
        acidRefluxBarId = nil,
    }, ReefGuardian)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function ReefGuardian:onLeave(context)
    CA.castAlertsStop(self.acidRefluxBarId)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- (No onDied needed — ReefGuardian has no alertList.)

-- Heavy / player-targeted attacks: shared handler for 5 ability IDs.
local function handleHeavy(self, context, alerts, abilityId,
                            unitTag, sourceUnitTag, sourceUnitId, unitId,
                            sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    if dur <= 0 then dur = FALLBACK_DUR end
    CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
end

ReefGuardian.combatRoutes = {
    -- Reef portal opening
    [HEARTBURN] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        self.reefNum = self.reefNum + 1
        local idx = self.reefNum
        self.reefPortals[idx] = { openTime = GetGameTimeMilliseconds() / 1000,
                                  wipeActive = false }
        CA.alert(nil, "Reef " .. idx .. ": OPEN — 60 s!",
            0xFFD700D9, SOUNDS.DUEL_START, 5000)
        PlaySound(SOUNDS.DUEL_START)
    end },
    -- Acid Reflux channel + 5 pool alerts
    [ACID_REFLUX] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        CA.castAlertsStop(self.acidRefluxBarId)
        self.acidRefluxBarId = CA.castAlertsStart(
            abilityId, "Acid Reflux", 10000, 10000, COL_ACID, ACT_ACID)
        for i = 1, ACID_COUNT do
            local delay = i * ACID_INTERVAL
            zo_callLater(function()
                CA.alert(nil,
                    "Acid pool " .. i .. "/" .. ACID_COUNT .. " — MOVE!",
                    0x44DD22D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 1500)
            end, delay)
        end
    end },
    -- Boss replication
    [REPLICATION] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        CA.alert(nil, "Replication!", 0xFF8800D9,
            SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
    end },
    -- Heavy / targeted attacks (5 IDs, shared handler)
    [CRAB_MONSTROUS_CLAW] = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CRAB_SWIPE]          = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CRUSH]               = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CLAW_ATTACK]         = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
    [CRACKDOWN]           = { result = ACTION_RESULT_BEGIN, fn = handleHeavy },
}

-- Building Static: shared handler for both lightning stack IDs.
local function handleBuildingStatic(self, context, alerts, changeType, abilityId,
                                     unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
        if AreUnitsEqual("player", unitTag) then
            self.buildingStaticStacks  = stackCount or 1
            self.buildingStaticEndTime = GetGameTimeMilliseconds() / 1000 + 10
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.buildingStaticStacks  = 0
            self.buildingStaticEndTime = 0
        end
    end
end

-- Volatile Residue: shared handler for both poison stack IDs.
local function handleVolatileResidue(self, context, alerts, changeType, abilityId,
                                      unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
        if AreUnitsEqual("player", unitTag) then
            self.volatileResidueStacks  = stackCount or 1
            self.volatileResidueEndTime = GetGameTimeMilliseconds() / 1000 + 10
        end
    elseif changeType == EFFECT_RESULT_FADED then
        if AreUnitsEqual("player", unitTag) then
            self.volatileResidueStacks  = 0
            self.volatileResidueEndTime = 0
        end
    end
end

ReefGuardian.effectRoutes = {
    [BUILDING_STATIC_1]  = handleBuildingStatic,
    [BUILDING_STATIC_2]  = handleBuildingStatic,
    [VOLATILE_RESIDUE_1] = handleVolatileResidue,
    [VOLATILE_RESIDUE_2] = handleVolatileResidue,
    [SHELTERED] = function(self, context, alerts, changeType, abilityId,
                            unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            self.playerSheltered   = true
            self.lastShelteredTime = GetGameTimeMilliseconds() / 1000
            self.buildingStaticStacks  = 0
            self.volatileResidueStacks = 0
        elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
            self.playerSheltered = false
        end
    end,
    -- Heartburn effect: reef portal wipe timer start.
    [HEARTBURN_EFFECT] = { changeType = EFFECT_RESULT_GAINED,
        fn = function(self, context, alerts, abilityId, ...)
        local now = GetGameTimeMilliseconds() / 1000
        for i = self.reefNum, 1, -1 do
            local reef = self.reefPortals[i]
            if reef and not reef.wipeActive and (now - reef.openTime) < 5 then
                reef.wipeActive = true
                reef.wipeStart  = now
                break
            end
        end
    end },
    [KING_ORGNUM_FIRE_DBF] = function(self, context, alerts, changeType, abilityId,
                                       unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            CA.alert(nil, "|cFF5500King Orgnum fire — MOVE!|r",
                0xFF5500D9, SOUNDS.DUEL_START, 5000)
        end
    end,
    [ACIDIC_VULN] = function(self, context, alerts, changeType, abilityId,
                              unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            self.acidicVulnLast = GetGameTimeMilliseconds() / 1000
        elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
            self.acidicVulnLast = 0
        end
    end,
}

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Info 1: Building Static (lightning) stacks; shows CLEANSED during shelter window.
local function showLightningStacksLine(self, alerts, now)
    local stacks = self.buildingStaticStacks
    if stacks > 0 then
        local warn = (stacks >= 7) and " |cff0000!|r" or ""
        if self.playerSheltered
           or (now - self.lastShelteredTime < SHELTERED_WINDOW) then
            alerts:showInfo(1, "|cFFD666⚡ CLEANSED|r")
        else
            alerts:showInfo(1,
                "|cFFD666⚡ " .. stacks .. " stack" ..
                (stacks ~= 1 and "s" or "") .. warn .. "|r")
        end
    else
        alerts:showInfo(1, "")
    end
end

-- Info 2: Volatile Residue (poison) stacks; shows CLEANSED during shelter window.
local function showPoisonStacksLine(self, alerts, now)
    local vstacks = self.volatileResidueStacks
    if vstacks > 0 then
        local warn = (vstacks >= 7) and " |cff0000!|r" or ""
        if self.playerSheltered
           or (now - self.lastShelteredTime < SHELTERED_WINDOW) then
            alerts:showInfo(2, "|c66CC66☣ CLEANSED|r")
        else
            alerts:showInfo(2,
                "|c66CC66☣ " .. vstacks .. " stack" ..
                (vstacks ~= 1 and "s" or "") .. warn .. "|r")
        end
    else
        alerts:showInfo(2, "")
    end
end

-- Info 3+4: Active reef wipe timers (red when ≤ 15 s); info4 falls back to Acidic Vuln window.
local function showReefWipeLines(self, alerts, now)
    local timers = {}
    for i = 1, self.reefNum do
        local reef = self.reefPortals[i]
        if reef and reef.wipeActive then
            local remaining = PORTAL_WIPE_TIME - (now - reef.wipeStart)
            if remaining > 0 then
                table.insert(timers, { idx = i, t = remaining })
            else
                reef.wipeActive = false
            end
        end
    end

    if timers[1] then
        local t1  = timers[1]
        local col = (t1.t <= 15) and "|cff0000" or "|cFFD700"
        alerts:showInfo(3,
            col .. "Reef " .. t1.idx .. ": " ..
            string.format("%.0f", t1.t) .. "s|r")
    else
        alerts:showInfo(3, "")
    end

    if timers[2] then
        local t2  = timers[2]
        local col = (t2.t <= 15) and "|cff0000" or "|cFFD700"
        alerts:showInfo(4,
            col .. "Reef " .. t2.idx .. ": " ..
            string.format("%.0f", t2.t) .. "s|r")
    elseif self.acidicVulnLast > 0 then
        local T = 5 - (now - self.acidicVulnLast)
        if T > 0 then
            alerts:showInfo(4,
                "|cff8800Acidic Vuln|r: " .. string.format("%.1f", T) .. "s")
        else
            self.acidicVulnLast = 0
            alerts:showInfo(4, "")
        end
    else
        alerts:showInfo(4, "")
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function ReefGuardian:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showLightningStacksLine(self, alerts, now)
    showPoisonStacksLine(self, alerts, now)
    showReefWipeLines(self, alerts, now)
end

return ReefGuardian
