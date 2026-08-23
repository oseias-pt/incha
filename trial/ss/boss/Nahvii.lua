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

-- ── Boss definition ───────────────────────────────────────────────────────
local Nahvii = {
    id   = 3,
    key  = "nahvii",
    name = "Nahviintaas",
}

Nahvii.alertList        = {}    -- [sourceUnitId] → CA bar (Slam/Stonefist)
-- Meteor
Nahvii.meteorTargets    = {}    -- [unitTag] → displayName
Nahvii.meteorDisplayEnd = 0     -- ms: when to stop showing meteor targets
-- NextMeteor / Thrash
Nahvii.nextMeteorTime   = 0     -- s: when next meteor is due
-- FireStorm / landing
Nahvii.stormTime        = 0     -- s: absolute time when storm ends (FireStorm begins + 13.7)
Nahvii.landingTime      = 0     -- s: stormTime + 6.6
Nahvii.firstStormTrig   = true  -- skip-first dedup
-- Portal
Nahvii.portalTime       = 0     -- s: portal window expires (open + 14)
Nahvii.wipeTime         = 0     -- s: raid wipe (portal open + 98)
Nahvii.cptPortal        = 0     -- group members who entered portal this cycle
Nahvii.inPortal         = false
-- Portal interrupt
Nahvii.interruptTime    = 0     -- ms: interrupt window expires
Nahvii.interruptUnitId  = nil   -- unitId of eternal servant being interrupted
Nahvii.pinsTime         = 0     -- s: next pins attack (after bash + 20)
-- Misc CA bars
Nahvii.thrashBarId      = nil

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Nahvii:reset(forced)
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    self.alertList        = {}
    CA.castAlertsStop(self.thrashBarId)
    self.thrashBarId      = nil
    self.meteorTargets    = {}
    self.meteorDisplayEnd = 0
    self.nextMeteorTime   = 0
    self.stormTime        = 0
    self.landingTime      = 0
    self.firstStormTrig   = true
    self.portalTime       = 0
    self.wipeTime         = 0
    self.cptPortal        = 0
    self.inPortal         = false
    self.interruptTime    = 0
    self.interruptUnitId  = nil
    self.pinsTime         = 0
end

-- ── Combat events ─────────────────────────────────────────────────────────
function Nahvii:onCombatEvent(context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    -- cross-trial alerts (HA, Block, Leap, Charge, Breath, Spit)
    if SunspireCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    -- alertList cleanup on unit death
    if result == ACTION_RESULT_DIED then
        if unitId then CA.castAlertsStop(self.alertList[unitId]); self.alertList[unitId] = nil end
        return
    end

    -- ── Meteor target tracking (117251/123067 EFFECT_GAINED_DURATION) ──
    if (abilityId == NEXT_METEOR_A or abilityId == NEXT_METEOR_B)
    and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        -- NextMeteor timer: same IDs
        self.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 14.5

        -- track targeted player (DPS only, matching HTS behavior)
        if IsUnitPlayer(unitTag) and unitTag and unitTag ~= "" then
            local name
            if AreUnitsEqual("player", unitTag)
            then name = "|cff9900== YOU ==|r"
            else name = "|cff9900" .. (GetUnitDisplayName(unitTag) or unitName or "?") .. "|r"
            end
            self.meteorTargets[unitTag]  = name
            self.meteorDisplayEnd = GetGameTimeMilliseconds() + 4000

            if AreUnitsEqual("player", unitTag) then
                alerts:showAction("YOU → Meteor!")
                CA.alert(nil, "Meteor on YOU!", 0xFF2200FF, SOUNDS.NONE, 4000)
            end
        end
        return
    end

    -- EFFECT_FADED: remove meteor target
    if (abilityId == NEXT_METEOR_A or abilityId == NEXT_METEOR_B)
    and result == ACTION_RESULT_EFFECT_FADED then
        if unitTag then self.meteorTargets[unitTag] = nil end
        return
    end

    -- ── NextMeteor phase-4 entry (117308 BEGIN) ──────────────────────
    if abilityId == NEXT_METEOR_C and result == ACTION_RESULT_BEGIN then
        self.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 10.5
        return
    end

    -- ── MarkForDeath: nudge NextMeteor forward ────────────────────────
    if abilityId == MARK_FOR_DEATH and result == ACTION_RESULT_BEGIN then
        self.nextMeteorTime = self.nextMeteorTime + 1.5
        return
    end

    -- ── PowerfulSlam: player or nearby group member ───────────────────
    if abilityId == POWERFUL_SLAM and result == ACTION_RESULT_BEGIN then
        local show = false
        if IsUnitPlayer(unitTag) then
            if AreUnitsEqual("player", unitTag) then
                show = true
            else
                SetMapToPlayerLocation()
                local x1, y1 = GetMapPlayerPosition("player")
                local x2, y2 = GetMapPlayerPosition(unitTag)
                if x2 and y2 and math.sqrt((x1-x2)^2 + (y1-y2)^2) * 1000 <= 7 then
                    show = true
                end
            end
        end
        if show then
            alerts:showAction("Block! (Slam)")
            local dur = select(1, GetAbilityCastInfo(POWERFUL_SLAM)) or 0
            if dur <= 0 then dur = 2000 end
            local cid = CA.alertCast(abilityId, sourceUnitName, dur, COL_SLAM)
            if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
        end
        return
    end

    -- ── Stonefist: player targeted ────────────────────────────────────
    if abilityId == STONEFIST and result == ACTION_RESULT_BEGIN then
        if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
            alerts:showAction("Block! (Stonefist)")
            local dur = select(1, GetAbilityCastInfo(STONEFIST)) or 0
            if dur <= 0 then dur = 2000 end
            local cid = CA.alertCast(abilityId, sourceUnitName, dur, COL_STONE)
            if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
        end
        return
    end

    -- ── Sweeping Breath: directional alert ───────────────────────────
    if (abilityId == SWEEP_RIGHT or abilityId == SWEEP_LEFT) and result == ACTION_RESULT_BEGIN then
        local dir = (abilityId == SWEEP_LEFT) and "<<< Sweep Breath <" or "> Sweep Breath >>>"
        alerts:showAction(dir)
        CA.alert(nil, dir, 0xFF8833FF, SOUNDS.NONE, 2000)
        return
    end

    -- ── Thrash: CA duration bar + nudge NextMeteor ────────────────────
    if abilityId == THRASH and result == ACTION_RESULT_BEGIN then
        local dur = select(1, GetAbilityCastInfo(THRASH)) or 0
        if dur <= 0 then dur = 2500 end
        CA.castAlertsStop(self.thrashBarId)
        self.thrashBarId = CA.castAlertsStart(
            abilityId, "Thrash",
            dur, dur,
            { 0.9, 0.1, 0.1, 0.5 },
            { dur, "THRASH!", 0.9, 0.1, 0.1, 0.9, SOUNDS.NONE })
        if self.nextMeteorTime > 0 then
            self.nextMeteorTime = self.nextMeteorTime - 1.5
        end
        return
    end

    -- ── SoulTear: 2 s banner ──────────────────────────────────────────
    if abilityId == SOUL_TEAR and result == ACTION_RESULT_BEGIN then
        alerts:showAction("SOUL TEAR!")
        CA.alert(nil, "SOUL TEAR!", 0x9966FFFF, SOUNDS.NONE, 2000)
        return
    end

    -- ── FireStorm: skip first; set storm + landing timers ────────────
    if abilityId == FIRE_STORM and result == ACTION_RESULT_BEGIN then
        if not self.firstStormTrig then
            self.firstStormTrig = true
            return
        end
        self.firstStormTrig = false
        local now            = GetGameTimeMilliseconds() / 1000
        self.stormTime       = now + 13.7
        self.landingTime     = self.stormTime + 6.6
        return
    end

    -- ── Portal: window + wipe countdown ──────────────────────────────
    if abilityId == PORTAL and result == ACTION_RESULT_BEGIN then
        local now        = GetGameTimeMilliseconds() / 1000
        self.portalTime  = now + 14
        self.wipeTime    = now + 98
        self.cptPortal   = 0
        return
    end

    -- ── Portal Enter: track inPortal state ───────────────────────────
    if abilityId == PORTAL_ENTER and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        if IsUnitPlayer(unitTag) then
            if AreUnitsEqual("player", unitTag) then
                self.inPortal    = true
                self.cptPortal   = 0
            else
                self.cptPortal = self.cptPortal + 1
                if self.cptPortal >= 3 then
                    self.inPortal  = true
                    self.cptPortal = 0
                end
            end
        end
        return
    end

    -- ── Portal Exit: clear inPortal ───────────────────────────────────
    if abilityId == PORTAL_EXIT and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
            self.inPortal        = false
            self.interruptTime   = 0
            self.interruptUnitId = nil
            self.pinsTime        = 0
        end
        return
    end

    -- ── Portal Interrupt: eternal servant channels wipe ──────────────
    if abilityId == PORTAL_INTERRUPT and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        local dur = select(1, GetAbilityCastInfo(PORTAL_INTERRUPT)) or 0
        if dur <= 0 then dur = 6000 end
        self.interruptTime   = GetGameTimeMilliseconds() + dur
        self.interruptUnitId = unitId
        self.pinsTime        = 0
        return
    end

    -- ── Bash detection: player interrupted the servant ───────────────
    -- Fires when any unit is interrupted; match against tracked servant.
    if result == ACTION_RESULT_INTERRUPT and unitId and unitId == self.interruptUnitId then
        self.interruptTime   = 0
        self.interruptUnitId = nil
        self.pinsTime        = GetGameTimeMilliseconds() / 1000 + 20
        return
    end

    -- ── Wipe mechanism cleared ────────────────────────────────────────
    if abilityId == WIPE_FINISHED and result == ACTION_RESULT_EFFECT_FADED then
        self.wipeTime = 0
        return
    end

    -- ── NegateField: player targeted ─────────────────────────────────
    if abilityId == NEGATE_FIELD and result == ACTION_RESULT_BEGIN then
        if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
            alerts:showAction("Dodge! (Negate)")
            CA.alert(nil, "Dodge Negate!", 0x9966FFFF, SOUNDS.NONE, 2500)
        end
        return
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Nahvii:onUpdate(context, alerts)
    local now_ms = GetGameTimeMilliseconds()
    local now    = now_ms / 1000

    -- ── Info 1: NextMeteor countdown ─────────────────────────────────
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

    -- ── Info 2: Portal window → Interrupt countdown → Pins countdown ──
    local portalLeft = self.portalTime - now
    local interLeft  = self.interruptTime - now_ms
    local pinsLeft   = self.pinsTime - now

    if interLeft > 0 then
        -- interrupt is active in portal
        alerts:showInfo(2, "|c7fffd4Interrupt in|r: |cff0000" ..
            string.format("%.1f", interLeft / 1000) .. "s|r")
    elseif pinsLeft > 0 then
        -- servant pinned, track next attack
        alerts:showInfo(2, "|c7fffd4Next Pins|r: |cffcc00" ..
            string.format("%.0f", pinsLeft) .. "s|r")
    elseif portalLeft > 0 then
        -- portal window open
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

    -- ── Info 3: Meteor targets → FireStorm begin/end ─────────────────
    if now_ms < self.meteorDisplayEnd then
        -- collect up to 3 target names
        local names = {}
        for _, name in pairs(self.meteorTargets) do
            names[#names + 1] = name
            if #names >= 3 then break end
        end
        if #names > 0 then
            alerts:showInfo(3, table.concat(names, "  "))
        else
            alerts:showInfo(3, "")
        end
    else
        -- FireStorm display
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

    -- ── Info 4: Landing → Wipe → HP "can fly" ────────────────────────
    local landing  = self.landingTime - now
    local wipeLeft = self.wipeTime    - now

    if landing > 0 then
        alerts:showInfo(4, "|c5cd65cLanding|r: " .. string.format("%.0f", landing) .. "s")
    elseif wipeLeft > 0 then
        alerts:showInfo(4, "|c8a2be2Portal Wipe|r: " .. string.format("%.0f", wipeLeft) .. "s")
    elseif not self.inPortal then
        local hp = context.extras.healthPercent
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

return Nahvii
