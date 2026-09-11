--- Nahviintaas  -  Sunspire boss 3 (Lightning / Portal)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-5: Nahvii-specific mechanics
---   PowerfulSlam (120542): player or nearby (dist <= 7); CA countdown list
---   Stonefist (120567): player-targeted; CA countdown list
---   SweepingBreath (120188 / 118743): directional caAlert
---   Thrash (118562): CA cast bar + nudge NextMeteor -1.5 s
---   SoulTear (117526): 2 s caAlert "SOUL TEAR"
---   FireStorm (118884): skip-first; stormTime +13.7 s, landing +6.6 s
---   NextMeteor (117251/123067 effectChanged.gained -> +14.5 s; 117308 BEGIN -> +10.5 s)
---   MarkForDeath (117938): nudge NextMeteor +1.5 s
---   Portal (121676): 14 s window + 98 s wipe countdown
---   PortalInterrupt (121436): interrupt countdown -> 20 s pins after bash
---   PortalEnter/Exit (121213/121254): inPortal state; suppress HP display
---   WipeFinished (121216): EFFECT_FADED clears wipe timer
---   NegateField (121411): player-targeted 2.5 s banner
---   Meteor targets (117251/123067): display targeted players for 4 s
---   Boss HP thresholds: 80% / 60% / 40% -> "Can Fly In X%" (suppressed in portal)

local SunspireCommon = require("trial.ss.SunspireCommon")
local BossBase       = require("lib.BossBase")
local MapUtils       = require("lib.MapUtils")
local Timer          = require("lib.Timer")
local Lang           = require("core.Lang")
local Fmt            = require("core.Fmt")
local CA             = require("external-api.CombatAlerts")
local CastDur        = require("lib.CastDur")
local Colors         = require("core.Colors")
local AlertTypes     = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")


-- -- Ability IDs ------------------------------------------------------------
local POWERFUL_SLAM    = 120542   -- beginCast: Block alert (player/nearby 7m)
local STONEFIST        = 120567   -- beginCast: Block alert (player only)
local SWEEP_RIGHT      = 120188   -- beginCast: >>> Sweep Breath alert
local SWEEP_LEFT       = 118743   -- beginCast: <<< Sweep Breath alert
local THRASH           = 118562   -- beginCast: caAlertCast; nextMeteor -1.5s
local SOUL_TEAR        = 117526   -- beginCast: SOUL TEAR alert
local FIRE_STORM       = 118884   -- beginCast: stormTime + 13.7s
local NEXT_METEOR_A    = 117251   -- effectChanged: gained -> +14.5s; faded -> clear target
local NEXT_METEOR_B    = 123067   -- effectChanged: gained -> +14.5s; faded -> clear target
local NEXT_METEOR_C    = 117308   -- beginCast: nextMeteor +10.5s
local MARK_FOR_DEATH   = 117938   -- beginCast: nextMeteor +1.5s
local PORTAL           = 121676   -- beginCast: portal 14s + wipe 98s
local PORTAL_ENTER     = 121213   -- combatEvent.other: EFFECT_GAINED_DURATION -> inPortal
local PORTAL_EXIT      = 121254   -- combatEvent.other: EFFECT_GAINED_DURATION -> exit portal
local PORTAL_INTERRUPT = 121436   -- combatEvent.other: EFFECT_GAINED_DURATION (arm) + INTERRUPT (bash)
local WIPE_FINISHED    = 121216   -- combatEvent.other: EFFECT_FADED -> clear wipeTime
local NEGATE_FIELD     = 121411   -- beginCast: Dodge alert (player only)

-- -- Fallback cast durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_SLAM_DUR      = 2000   -- PowerfulSlam / Stonefist: empirical
local FALLBACK_THRASH_DUR    = 2500   -- Thrash: empirical
local FALLBACK_INTERRUPT_DUR = 6000   -- PortalInterrupt: empirical

-- -- Boss definition -------------------------------------------------------
local Nahvii = {}
Nahvii.__index = Nahvii
setmetatable(Nahvii, {__index = BossBase})

Nahvii.key  = "nahvii"
Nahvii.name = "Nahviintaas"   -- TODO: verify via GetUnitName in-game
-- location: Sunspire arena is one shared room for all three bosses  -  a single AABB
-- would be ambiguous.  Name-based detection is intentional; name is well-established
-- EN string (same client since Elsweyr launch), non-EN risk is low.
-- hmHealthThreshold: math.huge until measured in-game on vet HM.
-- To measure: enter vet HM, then /script d(GetUnitMaxPower("boss1", POWERTYPE_HEALTH))
-- Set threshold between the vet and HM values, recording both in a trailing comment
-- (see AnsuulEncounter.lua for the convention).  /incha debug also prints the resolved
-- difficulty with the pool it compared, so one pull yields the numbers automatically.
Nahvii.hmHealthThreshold = math.huge

Nahvii.stateSchema = {
    alertList           = function() return {} end,
    -- Meteor
    meteorTargets       = function() return {} end,
    meteorDisplayEnd_ms = 0,
    -- NextMeteor / Thrash
    nextMeteorTime      = 0,
    -- FireStorm / landing
    stormTime           = 0,
    landingTime         = 0,
    firstStormTrig      = true,
    -- Portal
    portalTime          = 0,
    wipeTime            = 0,
    cptPortal           = 0,
    inPortal            = false,
    -- Portal interrupt
    interruptTimer      = function() return Timer.new(FALLBACK_INTERRUPT_DUR / 1000) end,
    interruptUnitId     = false,
    pinsTime            = 0,
    -- CA bar handle for the in-flight thrash bar.
    thrashBarId         = false,
}

function Nahvii.new()
    return BossBase.fromSchema(Nahvii)
end

-- -- Lifecycle -------------------------------------------------------------

local function nahvii_cleanup(self)
    self:cleanupAlertList()
    CA.castAlertsStop(self.thrashBarId)
    self.thrashBarId = false
end

function Nahvii:onLeave(context)
    nahvii_cleanup(self)
end

-- Soft reset on wipe: cancel bars immediately and clear all countdown
-- display state so the UI starts clean on the next pull.
function Nahvii:onWipe(context, alerts)
    nahvii_cleanup(self)
    self.nextMeteorTime      = 0
    self.stormTime           = 0
    self.landingTime         = 0
    self.firstStormTrig      = true
    self.portalTime          = 0
    self.wipeTime            = 0
    self.cptPortal           = 0
    self.inPortal            = false
    self.interruptTimer:clear()
    self.interruptUnitId     = false
    self.pinsTime            = 0
    self.meteorTargets       = {}
    self.meteorDisplayEnd_ms = 0
end

-- -- Handlers (new-style: boss as first arg, sourceUnitName before unit args) --

-- NextMeteor A+B: effectChanged handlers
-- Migrated from combatRoute (EFFECT_GAINED_DURATION / EFFECT_FADED via COMBAT_EVENT)
-- to effectChanged (EFFECT_RESULT_GAINED / FADED via EFFECT_CHANGED).
-- TODO: validate in-game that EFFECT_CHANGED fires for NEXT_METEOR_A/B.
local function handleNextMeteorGained(boss, context, alerts, abilityId, unitName,
                                       unitTag, unitId, stackCount)
    boss.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 14.5
    if IsUnitPlayer(unitTag) and unitTag and unitTag ~= "" then
        local name
        if AreUnitsEqual("player", unitTag)
        then name = Fmt.c(Fmt.AMBER, "== YOU ==")
        else name = Fmt.c(Fmt.AMBER, GetUnitDisplayName(unitTag) or unitName or "?")
        end
        boss.meteorTargets[unitTag] = name
        boss.meteorDisplayEnd_ms = GetGameTimeMilliseconds() + 4000
        if AreUnitsEqual("player", unitTag) then
            alerts:showAction(Lang.t("ss_nahvii_you_meteor"))
            CA.alert(nil, "Meteor on YOU!", 0xFF2200FF, SOUNDS.NONE, 4000)
        end
    end
end

local function handleNextMeteorFaded(boss, context, alerts, abilityId, unitName,
                                      unitTag, unitId, stackCount)
    if unitTag then boss.meteorTargets[unitTag] = nil end
end

local function handleNextMeteorC(boss, context, alerts, abilityId, ...)
    boss.nextMeteorTime = GetGameTimeMilliseconds() / 1000 + 10.5
end

local function handleMarkForDeath(boss, context, alerts, abilityId, ...)
    boss.nextMeteorTime = boss.nextMeteorTime + 1.5
end

local function handlePowerfulSlam(boss, context, alerts, abilityId, sourceUnitName,
                                   unitTag, unitId, sourceUnitId, unitName)
    local show = false
    if IsUnitPlayer(unitTag) then
        if AreUnitsEqual("player", unitTag) then
            show = true
        else
            show = MapUtils.isGroupMemberNearby(unitTag, 7)
        end
    end
    if show then
        alerts:showAction(Lang.t("ss_nahvii_block_slam"))
        local dur = CastDur.get(POWERFUL_SLAM, FALLBACK_SLAM_DUR)
        local cid = CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
        if cid and sourceUnitId then boss.alertList[sourceUnitId] = cid end
    end
end

local function handleStonefist(boss, context, alerts, abilityId, sourceUnitName,
                                unitTag, unitId, sourceUnitId, unitName)
    if not (IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag)) then return end
    alerts:showAction(Lang.t("ss_nahvii_block_stonefist"))
    local dur = CastDur.get(STONEFIST, FALLBACK_SLAM_DUR)
    local cid = CA.melee(abilityId, sourceUnitName, dur, Colors.AMBER)
    if cid and sourceUnitId then boss.alertList[sourceUnitId] = cid end
end

local function handleSweepRight(boss, context, alerts, abilityId, ...)
    local dir = Lang.t("ss_nahvii_sweep_right")
    alerts:showAction(dir); CA.alert(nil, dir, 0xFF8833FF, SOUNDS.NONE, 2000)
end

local function handleSweepLeft(boss, context, alerts, abilityId, ...)
    local dir = Lang.t("ss_nahvii_sweep_left")
    alerts:showAction(dir); CA.alert(nil, dir, 0xFF8833FF, SOUNDS.NONE, 2000)
end

local function handleThrash(boss, context, alerts, abilityId, ...)
    local dur = CastDur.get(THRASH, FALLBACK_THRASH_DUR)
    CA.castAlertsStop(boss.thrashBarId)
    boss.thrashBarId = CA.bar(
        abilityId, "Thrash",
        dur, dur, Colors.RED, 0.5,
        { dur, "THRASH!", 0.9, 0.1, 0.1, 0.9, SOUNDS.NONE })
    if boss.nextMeteorTime > 0 then
        boss.nextMeteorTime = boss.nextMeteorTime - 1.5
    end
end

local function handleSoulTear(boss, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ss_nahvii_soul_tear"))
    CA.alert(nil, "SOUL TEAR!", 0x9966FFFF, SOUNDS.NONE, 2000)
end

local function handleFireStorm(boss, context, alerts, abilityId, ...)
    if not boss.firstStormTrig then
        boss.firstStormTrig = true
        return
    end
    boss.firstStormTrig = false
    local now        = GetGameTimeMilliseconds() / 1000
    boss.stormTime   = now + 13.7
    boss.landingTime = boss.stormTime + 6.6
end

local function handlePortal(boss, context, alerts, abilityId, ...)
    local now       = GetGameTimeMilliseconds() / 1000
    boss.portalTime = now + 14
    boss.wipeTime   = now + 98
    boss.cptPortal  = 0
end

local function handlePortalEnter(boss, context, alerts, abilityId, sourceUnitName,
                                  unitTag, unitId, sourceUnitId, unitName)
    if IsUnitPlayer(unitTag) then
        if AreUnitsEqual("player", unitTag) then
            boss.inPortal  = true
            boss.cptPortal = 0
        else
            boss.cptPortal = boss.cptPortal + 1
            if boss.cptPortal >= 3 then
                boss.inPortal  = true
                boss.cptPortal = 0
            end
        end
    end
end

local function handlePortalExit(boss, context, alerts, abilityId, sourceUnitName,
                                 unitTag, unitId, sourceUnitId, unitName)
    if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
        boss.inPortal        = false
        boss.interruptTimer:clear()
        boss.interruptUnitId = false
        boss.pinsTime        = 0
    end
end

-- PortalInterrupt: fires in combatEvent.other for both
--   ACTION_RESULT_EFFECT_GAINED_DURATION (conjurer starts casting) and
--   ACTION_RESULT_INTERRUPT (conjurer is bashed).
-- The two cases are distinguished by whether unitId matches interruptUnitId:
--   no match -> new cast, arm the countdown timer;
--   match    -> bash success, clear timer and start pins countdown.
local function handlePortalInterrupt(boss, context, alerts, abilityId, sourceUnitName,
                                      unitTag, unitId, sourceUnitId, unitName)
    if unitId and unitId == boss.interruptUnitId then
        -- Bash success: conjurer was interrupted
        boss.interruptTimer:clear()
        boss.interruptUnitId = false
        boss.pinsTime        = GetGameTimeMilliseconds() / 1000 + 20
    else
        -- New cast started (ACTION_RESULT_EFFECT_GAINED_DURATION)
        local dur = CastDur.get(PORTAL_INTERRUPT, FALLBACK_INTERRUPT_DUR)
        boss.interruptTimer:reset(dur / 1000)
        boss.interruptUnitId = unitId
        boss.pinsTime        = 0
    end
end

-- WipeFinished fires with ACTION_RESULT_EFFECT_FADED.
-- combatEvent.other is entered for any non-damage/dodged/blocked result,
-- so no result check is needed here.
local function handleWipeFinished(boss, context, alerts, abilityId, ...)
    boss.wipeTime = 0
end

local function handleNegateField(boss, context, alerts, abilityId, sourceUnitName,
                                  unitTag, unitId, sourceUnitId, unitName)
    if IsUnitPlayer(unitTag) and AreUnitsEqual("player", unitTag) then
        alerts:showAction(Lang.t("ss_nahvii_dodge_negate"))
        CA.alert(nil, "Dodge Negate!", 0x9966FFFF, SOUNDS.NONE, 2500)
    end
end

-- -- Events table (replaces combatRoutes / effectRoutes) --------------------
-- PORTAL_ENTER, PORTAL_EXIT, PORTAL_INTERRUPT, WIPE_FINISHED stay in
-- combatEvent.other to preserve their COMBAT_EVENT path.
-- NEXT_METEOR_A/B migrated to effectChanged (validate in-game).

local _beginCastEntry = {
    [NEXT_METEOR_C]  = { type = AlertTypes.CUSTOM, fn = handleNextMeteorC },
    [MARK_FOR_DEATH] = { type = AlertTypes.CUSTOM, fn = handleMarkForDeath },
    [POWERFUL_SLAM]  = { type = AlertTypes.CUSTOM, fn = handlePowerfulSlam },
    [STONEFIST]      = { type = AlertTypes.CUSTOM, fn = handleStonefist },
    [SWEEP_RIGHT]    = { type = AlertTypes.CUSTOM, fn = handleSweepRight },
    [SWEEP_LEFT]     = { type = AlertTypes.CUSTOM, fn = handleSweepLeft },
    [THRASH]         = { type = AlertTypes.CUSTOM, fn = handleThrash },
    [SOUL_TEAR]      = { type = AlertTypes.CUSTOM, fn = handleSoulTear },
    [FIRE_STORM]     = { type = AlertTypes.CUSTOM, fn = handleFireStorm },
    [PORTAL]         = { type = AlertTypes.CUSTOM, fn = handlePortal },
    [NEGATE_FIELD]   = { type = AlertTypes.CUSTOM, fn = handleNegateField },
}

for k, v in pairs(SunspireCommon.beginCastEntries) do
    _beginCastEntry[k] = v
end

Nahvii.events = {
    beginCast = {
        instant = _beginCastEntry,
        started = _beginCastEntry,
    },
    combatEvent = {
        other = {
            [PORTAL_ENTER]     = { type = AlertTypes.CUSTOM, fn = handlePortalEnter },
            [PORTAL_EXIT]      = { type = AlertTypes.CUSTOM, fn = handlePortalExit },
            [PORTAL_INTERRUPT] = { type = AlertTypes.CUSTOM, fn = handlePortalInterrupt },
            [WIPE_FINISHED]    = { type = AlertTypes.CUSTOM, fn = handleWipeFinished },
        },
    },
    effectChanged = {
        gained = {
            [NEXT_METEOR_A] = { type = AlertTypes.CUSTOM, fn = handleNextMeteorGained },
            [NEXT_METEOR_B] = { type = AlertTypes.CUSTOM, fn = handleNextMeteorGained },
        },
        faded = {
            [NEXT_METEOR_A] = { type = AlertTypes.CUSTOM, fn = handleNextMeteorFaded },
            [NEXT_METEOR_B] = { type = AlertTypes.CUSTOM, fn = handleNextMeteorFaded },
        },
    },
}

EventDispatcher.build(Nahvii)

-- -- Tracker-row renderers -------------------------------------------------

-- Row 1: NextMeteor countdown.
local function showNextMeteorLine(self, alerts, now)
    if self.nextMeteorTime > 0 then
        local T = self.nextMeteorTime - now
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.RED, Lang.t("ss_nahvii_next_meteor")), T)
        else
            alerts:clearRow(1)   -- meteor has hit; CombatAlerts handles the alert bar
        end
    else
        alerts:clearRow(1)
    end
end

-- Row 2: Portal window → Interrupt countdown → Pins countdown.
local function showPortalInterruptLine(self, alerts, now)
    local portalLeft = self.portalTime - now
    local interLeft  = self.interruptTimer:remaining()
    local pinsLeft   = self.pinsTime - now

    if interLeft > 0 then
        alerts:setRow(2, Fmt.c(Fmt.AQUA, Lang.t("ss_nahvii_interrupt_in")), interLeft)
    elseif pinsLeft > 0 then
        alerts:setRow(2, Fmt.c(Fmt.AQUA, Lang.t("ss_nahvii_next_pins")),    pinsLeft)
    elseif portalLeft >= 11 then
        -- Enough time has passed that the group should already be inside.
        alerts:setRow(2, Fmt.c(Fmt.RED,    Lang.t("ss_nahvii_portal_urgent")), portalLeft)
    elseif portalLeft > 0 then
        alerts:setRow(2, Fmt.c(Fmt.AQUA, Lang.t("ss_nahvii_portal")),        portalLeft)
    else
        alerts:clearRow(2)
    end
end

-- Row 3: Meteor target names while display window is open; otherwise FireStorm countdown.
local function showMeteorOrStormLine(self, alerts, now, now_ms)
    if now_ms < self.meteorDisplayEnd_ms then
        local names = {}
        for _, name in pairs(self.meteorTargets) do
            names[#names + 1] = name
            if #names >= 3 then break end
        end
        -- Static name-column display: no ETA (targets, not a timer).
        alerts:setRow(3, #names > 0 and table.concat(names, "  ") or "", nil)
    else
        local storm = self.stormTime - now
        if storm >= 5.2 then
            alerts:setRow(3, Fmt.c(Fmt.CRIMSON, Lang.t("ss_nahvii_fire_storm_begin")), storm - 5.2)
        elseif storm >= 0 then
            alerts:setRow(3, Fmt.c(Fmt.CRIMSON, Lang.t("ss_nahvii_fire_storm_end")),   storm)
        else
            alerts:clearRow(3)
        end
    end
end

-- Row 4: Landing → Portal Wipe → HP can-fly threshold.
local function showLandingWipeLine(self, alerts, now, context)
    local landing  = self.landingTime - now
    local wipeLeft = self.wipeTime    - now

    if landing > 0 then
        alerts:setRow(4, Fmt.c(Fmt.LANDING, Lang.t("ss_landing")),          landing)
    elseif wipeLeft > 0 then
        alerts:setRow(4, Fmt.c(Fmt.VOID,    Lang.t("ss_nahvii_portal_wipe")), wipeLeft)
    elseif not self.inPortal then
        local hp = context.healthPercent
        if hp and hp > 39 then
            local flyAt
            if     hp >= 80 then flyAt = 80
            elseif hp >= 60 then flyAt = 60
            elseif hp >= 40 then flyAt = 40
            end
            if flyAt and (hp - flyAt) <= 5 then
                alerts:setRow(4, Fmt.c(Fmt.FLYZONE, Lang.t("ss_can_fly_in") .. Fmt.pct(hp - flyAt, 1)), nil)
            else
                alerts:clearRow(4)
            end
        else
            alerts:clearRow(4)
        end
    else
        alerts:clearRow(4)
    end
end

-- -- 200 ms display loop ---------------------------------------------------
function Nahvii:onUpdate(context, alerts)
    local now_ms = GetGameTimeMilliseconds()
    local now    = now_ms / 1000
    showNextMeteorLine(self, alerts, now)
    showPortalInterruptLine(self, alerts, now)
    showMeteorOrStormLine(self, alerts, now, now_ms)
    showLandingWipeLine(self, alerts, now, context)
end

package.loaded["trial.ss.boss.Nahvii"] = Nahvii
return Nahvii
