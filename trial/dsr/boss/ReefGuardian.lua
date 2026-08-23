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

-- ── Boss definition ───────────────────────────────────────────────────────
local ReefGuardian = {
    id   = 2,
    key  = "reef_guardian",
    name = "Reef Guardian",   -- TODO: verify via GetUnitName("boss1") in-game
    hmHealthThreshold = 100000001,  -- TODO: verify
}

-- ── State ─────────────────────────────────────────────────────────────────
ReefGuardian.buildingStaticStacks   = 0
ReefGuardian.buildingStaticEndTime  = 0
ReefGuardian.volatileResidueStacks  = 0
ReefGuardian.volatileResidueEndTime = 0
ReefGuardian.playerSheltered        = false
ReefGuardian.lastShelteredTime      = 0   -- for brief "CLEANSED" label in info1/2

-- Reef portals: up to 3 can be open simultaneously.
-- Each entry: { openTime, wipeActive }
ReefGuardian.reefPortals   = {}   -- table of open reef timers
ReefGuardian.reefNum       = 0    -- total reefs opened (sequential)

ReefGuardian.acidicVulnLast = 0   -- time GAINED; 0 when inactive
ReefGuardian.acidRefluxBarId = nil

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function ReefGuardian:reset(forced)
    self.buildingStaticStacks   = 0
    self.buildingStaticEndTime  = 0
    self.volatileResidueStacks  = 0
    self.volatileResidueEndTime = 0
    self.playerSheltered        = false
    self.lastShelteredTime      = 0
    self.reefPortals            = {}
    self.reefNum                = 0
    self.acidicVulnLast         = 0
    CA.castAlertsStop(self.acidRefluxBarId)
    self.acidRefluxBarId        = nil
end

-- ── Combat state ──────────────────────────────────────────────────────────
function ReefGuardian:onCombatState(context, inCombat, alerts)
    if inCombat then
        self:reset(false)
    end
end

-- ── Combat events ─────────────────────────────────────────────────────────
function ReefGuardian:onCombatEvent(context, alerts, result, abilityId,
                                     unitTag, sourceUnitTag, sourceUnitId, unitId,
                                     sourceUnitName, unitName)
    if DreadsailCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    if result == ACTION_RESULT_BEGIN then
        -- ── Reef portal opening (Heartburn cast) ──────────────────────────
        if abilityId == HEARTBURN then
            self.reefNum = self.reefNum + 1
            local idx = self.reefNum
            self.reefPortals[idx] = { openTime = GetGameTimeMilliseconds() / 1000,
                                      wipeActive = false }
            CA.alert(nil, "Reef " .. idx .. ": OPEN — 60 s!",
                0xFFD700D9, SOUNDS.DUEL_START, 5000)
            PlaySound(SOUNDS.DUEL_START)
            return
        end

        -- ── Acid Reflux channel ───────────────────────────────────────────
        if abilityId == ACID_REFLUX then
            CA.castAlertsStop(self.acidRefluxBarId)
            self.acidRefluxBarId = CA.castAlertsStart(
                abilityId, "Acid Reflux", 10000, 10000, COL_ACID, ACT_ACID)
            -- Chain 5 × acid pool alerts, each 1750 ms apart
            for i = 1, ACID_COUNT do
                local delay = i * ACID_INTERVAL
                zo_callLater(function()
                    CA.alert(nil,
                        "Acid pool " .. i .. "/" .. ACID_COUNT .. " — MOVE!",
                        0x44DD22D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 1500)
                end, delay)
            end
            return
        end

        -- ── Replication ───────────────────────────────────────────────────
        if abilityId == REPLICATION then
            CA.alert(nil, "Replication!", 0xFF8800D9,
                SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
            return
        end

        -- ── Heavy / targeted attacks (player only) ────────────────────────
        if abilityId == CRAB_MONSTROUS_CLAW
           or abilityId == CRAB_SWIPE
           or abilityId == CRUSH
           or abilityId == CLAW_ATTACK
           or abilityId == CRACKDOWN then
            if not IsUnitPlayer(unitTag) then return end
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 1500 end
            CA.alertCast(abilityId, sourceUnitName, dur, COL_HEAVY)
            return
        end
    end
end

-- ── Effect changes ────────────────────────────────────────────────────────
function ReefGuardian:onEffectChanged(context, alerts, changeType, abilityId,
                                       unitTag, unitId, unitName, stackCount)
    if DreadsailCommon.handleEffect(alerts, changeType, abilityId, unitTag) then
        return
    end

    -- ── Building Static (lightning stacks) ───────────────────────────────
    if abilityId == BUILDING_STATIC_1 or abilityId == BUILDING_STATIC_2 then
        if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
            if AreUnitsEqual("player", unitTag) then
                self.buildingStaticStacks  = stackCount or 1
                self.buildingStaticEndTime = GetGameTimeMilliseconds() / 1000 + 10
            end
        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.buildingStaticStacks = 0
                self.buildingStaticEndTime = 0
            end
        end
        return
    end

    -- ── Volatile Residue (poison stacks) ─────────────────────────────────
    if abilityId == VOLATILE_RESIDUE_1 or abilityId == VOLATILE_RESIDUE_2 then
        if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
            if AreUnitsEqual("player", unitTag) then
                self.volatileResidueStacks  = stackCount or 1
                self.volatileResidueEndTime = GetGameTimeMilliseconds() / 1000 + 10
            end
        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.volatileResidueStacks = 0
                self.volatileResidueEndTime = 0
            end
        end
        return
    end

    -- ── Sheltered (cleansing aura — resets stacks) ────────────────────────
    if abilityId == SHELTERED then
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            self.playerSheltered   = true
            self.lastShelteredTime = GetGameTimeMilliseconds() / 1000
            -- Stacks reset when sheltered
            self.buildingStaticStacks  = 0
            self.volatileResidueStacks = 0
        elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
            self.playerSheltered = false
        end
        return
    end

    -- ── Heartburn effect changed (reef portal wipe timer start) ───────────
    if abilityId == HEARTBURN_EFFECT then
        if changeType == EFFECT_RESULT_GAINED then
            -- Associate with the most recently opened reef (simple heuristic)
            local now = GetGameTimeMilliseconds() / 1000
            for i = self.reefNum, 1, -1 do
                local reef = self.reefPortals[i]
                if reef and not reef.wipeActive and (now - reef.openTime) < 5 then
                    reef.wipeActive = true
                    reef.wipeStart  = now
                    break
                end
            end
        end
        return
    end

    -- ── King Orgnum fire debuff ───────────────────────────────────────────
    if abilityId == KING_ORGNUM_FIRE_DBF then
        if changeType == EFFECT_RESULT_GAINED
           and AreUnitsEqual("player", unitTag) then
            CA.alert(nil, "|cFF5500King Orgnum fire — MOVE!|r",
                0xFF5500D9, SOUNDS.DUEL_START, 5000)
        end
        return
    end

    -- ── Acidic Vulnerability ─────────────────────────────────────────────
    if abilityId == ACIDIC_VULN then
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            self.acidicVulnLast = GetGameTimeMilliseconds() / 1000
        elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
            self.acidicVulnLast = 0
        end
        return
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function ReefGuardian:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000

    -- ── Info 1: Lightning stacks (Building Static) ────────────────────────
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

    -- ── Info 2: Poison stacks (Volatile Residue) ──────────────────────────
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

    -- ── Info 3 + 4: Open reef wipe timers ─────────────────────────────────
    -- Collect active wipe timers in order.
    local timers = {}
    for i = 1, self.reefNum do
        local reef = self.reefPortals[i]
        if reef and reef.wipeActive then
            local remaining = PORTAL_WIPE_TIME - (now - reef.wipeStart)
            if remaining > 0 then
                table.insert(timers, { idx = i, t = remaining })
            else
                -- Wipe expired — treat as failed (display briefly)
                reef.wipeActive = false
            end
        end
    end

    if timers[1] then
        local t1   = timers[1]
        local col  = (t1.t <= 15) and "|cff0000" or "|cFFD700"
        alerts:showInfo(3,
            col .. "Reef " .. t1.idx .. ": " ..
            string.format("%.0f", t1.t) .. "s|r")
    else
        alerts:showInfo(3, "")
    end

    if timers[2] then
        local t2   = timers[2]
        local col  = (t2.t <= 15) and "|cff0000" or "|cFFD700"
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

return ReefGuardian
