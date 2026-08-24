--- Nahviintaas — Sunspire boss 3 (Lightning / Portal)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-5: Nahvii-specific mechanics
---   PowerfulSlam (120542): player or nearby (dist ≤ 7); CA countdown list
---   Stonefist (120567): player-targeted; CA countdown list
---   SweepingBreath (120188 / 118743): directional caAlert
---   Thrash (118562): CA cast bar + nudge NextMeteor −1.5 s
---   SoulTear (117526): 2 s caAlert "SOUL TEAR"
---   FireStorm (118884): skip-first; stormTime +13.7 s, landing +6.6 s
---   NextMeteor (117251/123067 EFFECT_GAINED_DURATION → +14.5 s; 117308 BEGIN → +10.5 s)
---   MarkForDeath (117938): nudge NextMeteor +1.5 s
---   Portal (121676): 14 s window + 98 s wipe countdown
---   PortalInterrupt (121436): interrupt countdown → 20 s pins after bash
---   PortalEnter/Exit (121213/121254): inPortal state; suppress HP display
---   WipeFinished (121216): EFFECT_FADED clears wipe timer
---   NegateField (121411): player-targeted 2.5 s banner
---   Meteor targets (117251/123067): display targeted players for 4 s
---   Boss HP thresholds: 80% / 60% / 40% → "Can Fly In X%" (suppressed in portal)

local SunspireCommon = require("trial.ss.SunspireCommon")
local BossBase       = require("lib.BossBase")
local MapUtils       = require("lib.MapUtils")
local Timer          = require("lib.Timer")

-- ── Ability IDs ────────────────────────────────────────────────────────────
local POWERFUL_SLAM    = 120542
local STONEFIST        = 120567
local SWEEP_RIGHT      = 120188   -- >>> (right-to-left run)
local SWEEP_LEFT       = 118743   -- <<< (left-to-right run)
local THRASH           = 118562
local SOUL_TEAR        = 117526
local FIRE_STORM       = 118884
local NEXT_METEOR_A    = 117251   -- EFFECT_GAINED_DURATION → +14.5 s
local NEXT_METEOR_B    = 123067   -- EFFECT_GAINED_DURATION → +14.5 s
local NEXT_METEOR_C    = 117308   -- BEGIN → +10.5 s
local MARK_FOR_DEATH   = 117938
local PORTAL           = 121676
local PORTAL_ENTER     = 121213
local PORTAL_EXIT      = 121254
local PORTAL_INTERRUPT = 121436
local WIPE_FINISHED    = 121216
local NEGATE_FIELD     = 121411

local CA = require("lib.CA")

-- ── CA colour palettes ─────────────────────────────────────────────────────
local COL_SLAM   = { -2, 0, false, { 1.0, 0.27, 0.0, 0.4 }, { 1.0, 0.27, 0.0, 0.8 } }
local COL_STONE  = { -2, 0, false, { 0.7, 0.52, 0.0, 0.4 }, { 0.7, 0.52, 0.0, 0.8 } }
local COL_THRASH = { -2, 0, false, { 0.9, 0.1,  0.1, 0.4 }, { 0.9, 0.1,  0.1, 0.8 } }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_SLAM_DUR      = 2000   -- PowerfulSlam / Stonefist: empirical
local FALLBACK_THRASH_DUR    = 2500   -- Thrash: empirical
local FALLBACK_INTERRUPT_DUR = 6000   -- PortalInterrupt: empirical

-- ── Boss definition ───────────────────────────────────────────────────────
local Nahvii = {}
Nahvii.__index = Nahvii
setmetatable(Nahvii, {__index = BossBase})

Nahvii.key  = "nahvii"
Nahvii.name = "Nahviintaas"

function Nahvii.new()
    return setmetatable({
        alertList        = {},    -- [sourceUnitId] → CA bar (Slam/Stonefist)
        -- Meteor
        meteorTargets       = {},  -- [unitTag] → displayName
        meteorDisplayEnd_ms = 0,   -- ms: when to stop showing meteor targets
        -- NextMeteor / Thrash
        nextMeteorTime   = 0,     -- s: when next meteor is due
        -- FireStorm / landing
        stormTime        = 0,     -- s: absolute time when storm ends (FireStorm begins + 13.7)
        landingTime      = 0,     -- s: stormTime + 6.6
        firstStormTrig   = true,  -- skip-first dedup
        -- Portal
        portalTime       = 0,     -- s: portal window expires (open + 14)
        wipeTime         = 0,     -- s: raid wipe (portal open + 98)
        cptPortal        = 0,     -- group members who entered portal this cycle
        inPortal         = false,
        -- Portal interrupt
        interruptTimer   = Timer.new(FALLBACK_INTERRUPT_DUR / 1000), -- interrupt window countdown
        interruptUnitId  = nil,   -- unitId of eternal servant being interrupted
        pinsTime         = 0,     -- s: next pins attack (after bash + 20)
        -- Misc CA bars
        thrashBarId      = nil,
    }, Nahvii)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Nahvii:onLeave(context)
    self:cleanupAlertList()
    CA.castAlertsStop(self.thrashBarId)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- Shared cross-trial mechanic handler.
Nahvii.common = SunspireCommon

-- NextMeteor A+B share: EFFECT_GAINED_DURATION → timer + target tracking;
-- EFFECT_FADED → remove target entry.
local function handleNextMeteor(self, context, alerts, result, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 14.5
        if IsUnitPlayer(unitTag) and unitTag and unitTag ~= "" then
            local name
            if AreUnitsEqual("player", unitTag)
            then name = "|cff9900== YOU ==|r"
            else name = "|cff9900" .. (GetUnitDisplayName(unitTag) or unitName or "?") .. "|r"
            end
            self.meteorTargets[unitTag] = name
            self.meteorDisplayEnd_ms = GetGameTimeMilliseconds() + 4000
            if AreUnitsEqual("player", unitTag) then
                alerts:showAction("YOU → Meteor!")
                CA.alert(nil, "Meteor on YOU!", 0xFF2200FF, SOUNDS.NONE, 4000)
            end
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        if unitTag then self.meteorTargets[unitTag] = nil end
    end
end

Nahvii.combatRoutes = {
    [NEXT_METEOR_A] = handleNextMeteor,
    [NEXT_METEOR_B] = handleNextMeteor,
    [NEXT_METEOR_C] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        self.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 10.5
    end },
    [MARK_FOR_DEATH] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        self.nextMeteorTime = self.nextMeteorTime + 1.5
    end },
    [POWERFUL_SLAM] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId,
                      unitTag, sourceUnitTag, sourceUnitId, unitId,
                      sourceUnitName, unitName)
        local show = false
        if IsUnitPlayer(unitTag) then
            if AreUnitsEqual("player", unitTag) then
                show = true
            else
                show = MapUtils.isGroupMemberNearby(unitTag, 7)
            end
        end
        if show then
            alerts:showAction("Block! (Slam)")
            local dur = select(1, GetAbilityCastInfo(POWERFUL_SLAM)) or 0
            if dur <= 0 then dur = FALLBACK_SLAM_DUR end
            local cid = CA.alertCast(abilityId, sourceUnitName, dur, COL_SLAM)
            if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
        end
    end },
    [STONEFIST] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId,
                      unitTag, sourceUnitTag, sourceUnitId, unitId,
                      sourceUnitName, unitName)
        if not (IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag)) then return end
        alerts:showAction("Block! (Stonefist)")
        local dur = select(1, GetAbilityCastInfo(STONEFIST)) or 0
        if dur <= 0 then dur = FALLBACK_SLAM_DUR end
        local cid = CA.alertCast(abilityId, sourceUnitName, dur, COL_STONE)
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
    end },
    [SWEEP_RIGHT] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local dir = "> Sweep Breath >>>"
        alerts:showAction(dir); CA.alert(nil, dir, 0xFF8833FF, SOUNDS.NONE, 2000)
    end },
    [SWEEP_LEFT] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local dir = "<<< Sweep Breath <"
        alerts:showAction(dir); CA.alert(nil, dir, 0xFF8833FF, SOUNDS.NONE, 2000)
    end },
    [THRASH] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local dur = select(1, GetAbilityCastInfo(THRASH)) or 0
        if dur <= 0 then dur = FALLBACK_THRASH_DUR end
        CA.castAlertsStop(self.thrashBarId)
        self.thrashBarId = CA.castAlertsStart(
            abilityId, "Thrash",
            dur, dur,
            { 0.9, 0.1, 0.1, 0.5 },
            { dur, "THRASH!", 0.9, 0.1, 0.1, 0.9, SOUNDS.NONE })
        if self.nextMeteorTime > 0 then
            self.nextMeteorTime = self.nextMeteorTime - 1.5
        end
    end },
    [SOUL_TEAR] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        alerts:showAction("SOUL TEAR!")
        CA.alert(nil, "SOUL TEAR!", 0x9966FFFF, SOUNDS.NONE, 2000)
    end },
    [FIRE_STORM] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        if not self.firstStormTrig then
            self.firstStormTrig = true
            return
        end
        self.firstStormTrig = false
        local now        = GetGameTimeMilliseconds() / 1000
        self.stormTime   = now + 13.7
        self.landingTime = self.stormTime + 6.6
    end },
    [PORTAL] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, ...)
        local now       = GetGameTimeMilliseconds() / 1000
        self.portalTime = now + 14
        self.wipeTime   = now + 98
        self.cptPortal  = 0
    end },
    [PORTAL_ENTER] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,
        fn = function(self, context, alerts, abilityId, unitTag, ...)
        if IsUnitPlayer(unitTag) then
            if AreUnitsEqual("player", unitTag) then
                self.inPortal  = true
                self.cptPortal = 0
            else
                self.cptPortal = self.cptPortal + 1
                if self.cptPortal >= 3 then
                    self.inPortal  = true
                    self.cptPortal = 0
                end
            end
        end
    end },
    [PORTAL_EXIT] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,
        fn = function(self, context, alerts, abilityId, unitTag, ...)
        if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
            self.inPortal        = false
            self.interruptTimer:clear()
            self.interruptUnitId = nil
            self.pinsTime        = 0
        end
    end },
    [PORTAL_INTERRUPT] = { result = ACTION_RESULT_EFFECT_GAINED_DURATION,
        fn = function(self, context, alerts, abilityId,
                      unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
        local dur = select(1, GetAbilityCastInfo(PORTAL_INTERRUPT)) or 0
        if dur <= 0 then dur = FALLBACK_INTERRUPT_DUR end
        self.interruptTimer:reset(dur / 1000)
        self.interruptUnitId = unitId
        self.pinsTime        = 0
    end },
    [WIPE_FINISHED] = function(self, context, alerts, result, abilityId, ...)
        if result == ACTION_RESULT_EFFECT_FADED then self.wipeTime = 0 end
    end,
    [NEGATE_FIELD] = { result = ACTION_RESULT_BEGIN, fn = function(self, context, alerts, abilityId, unitTag, ...)
        if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
            alerts:showAction("Dodge! (Negate)")
            CA.alert(nil, "Dodge Negate!", 0x9966FFFF, SOUNDS.NONE, 2500)
        end
    end },
}

-- Catch-all fallback: bash detection has no abilityId filter and cannot be routed.
-- CombatHandler invokes this ONLY when abilityId is not in combatRoutes.
function Nahvii:onCombatEvent(context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if result == ACTION_RESULT_INTERRUPT and unitId and unitId == self.interruptUnitId then
        self.interruptTimer:clear()
        self.interruptUnitId = nil
        self.pinsTime        = GetGameTimeMilliseconds() / 1000 + 20
    end
end

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Info 1: NextMeteor countdown.
local function showNextMeteorLine(self, alerts, now)
    if self.nextMeteorTime > 0 then
        local T = self.nextMeteorTime - now
        if T > 0 then
            alerts:showInfo(1, "|cf51414Next Meteor|r: " .. string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(1, "|cf51414Next Meteor|r: |cff0000INC|r")
        end
    else
        alerts:showInfo(1, "")
    end
end

-- Info 2: Portal window → Interrupt countdown → Pins countdown.
local function showPortalInterruptLine(self, alerts, now)
    local portalLeft = self.portalTime - now
    local interLeft  = self.interruptTimer:remaining()
    local pinsLeft   = self.pinsTime - now

    if interLeft > 0 then
        alerts:showInfo(2, "|c7fffd4Interrupt in|r: |cff0000" ..
            string.format("%.1f", interLeft) .. "s|r")
    elseif pinsLeft > 0 then
        alerts:showInfo(2, "|c7fffd4Next Pins|r: |cffcc00" ..
            string.format("%.0f", pinsLeft) .. "s|r")
    elseif portalLeft > 0 then
        if portalLeft >= 11 then
            alerts:showInfo(2, "|c7fffd4Portal|r: |cff0000" ..
                string.format("%.0f", portalLeft) .. "s|r")
        else
            alerts:showInfo(2, "|c7fffd4Portal|r: " ..
                string.format("%.0f", portalLeft) .. "s")
        end
    else
        alerts:showInfo(2, "")
    end
end

-- Info 3: Meteor targets while display window is open; otherwise FireStorm countdown.
local function showMeteorOrStormLine(self, alerts, now, now_ms)
    if now_ms < self.meteorDisplayEnd_ms then
        local names = {}
        for _, name in pairs(self.meteorTargets) do
            names[#names + 1] = name
            if #names >= 3 then break end
        end
        alerts:showInfo(3, #names > 0 and table.concat(names, "  ") or "")
    else
        local storm = self.stormTime - now
        if storm >= 5.2 then
            alerts:showInfo(3, "|ce51919Fire Storm Begin|r: " ..
                string.format("%.1f", storm - 5.2) .. "s")
        elseif storm >= 0 then
            alerts:showInfo(3, "|ce51919Fire Storm End|r: " ..
                string.format("%.1f", storm) .. "s")
        else
            alerts:showInfo(3, "")
        end
    end
end

-- Info 4: Landing countdown → Portal Wipe → HP "can fly" threshold.
local function showLandingWipeLine(self, alerts, now, context)
    local landing  = self.landingTime - now
    local wipeLeft = self.wipeTime    - now

    if landing > 0 then
        alerts:showInfo(4, "|c5cd65cLanding|r: " .. string.format("%.0f", landing) .. "s")
    elseif wipeLeft > 0 then
        alerts:showInfo(4, "|c8a2be2Portal Wipe|r: " .. string.format("%.0f", wipeLeft) .. "s")
    elseif not self.inPortal then
        local hp = context.healthPercent
        if hp and hp > 39 then
            local flyAt
            if     hp >= 80 then flyAt = 80
            elseif hp >= 60 then flyAt = 60
            elseif hp >= 40 then flyAt = 40
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
    else
        alerts:showInfo(4, "")
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Nahvii:onUpdate(context, alerts)
    local now_ms = GetGameTimeMilliseconds()
    local now    = now_ms / 1000
    showNextMeteorLine(self, alerts, now)
    showPortalInterruptLine(self, alerts, now)
    showMeteorOrStormLine(self, alerts, now, now_ms)
    showLandingWipeLine(self, alerts, now, context)
end

return Nahvii
