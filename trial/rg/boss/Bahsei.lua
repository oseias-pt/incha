--- Bahsei (Flame-Herald Bahsei)  -  Rockgrove boss 2

local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local RockgroveCommon = require("trial.rg.RockgroveCommon")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Colors          = require("core.Colors")

-- -- Ability IDs ------------------------------------------------------------
local CURSED_GROUND    = 152475
local SALVO2           = 152463
local SICKLE           = 150067
local HEMORRHAGE       = 150008
local RANCID_HAMMER    = 149922
local DEATH_TOUCH      = 150078
local MALIGNANT_MARROW = 153421
local BITTER_MARROW    = 153423
local METEOR_SWARM     = 155357
local EYE_CW           = 153517
local EYE_CCW          = 153518
-- MT detection IDs (carve/slice/rendflesh)
local MT_CARVE       = 150047
local MT_SLICE       = 150048
local MT_RENDFLESH   = 150065

local ACT_METEOR    = { 10000, "KILL SUN!", 0.8, 0.0, 0.0, 0.9, nil }

local FALLBACK_SALVO_DUR  = 2500
local FALLBACK_SICKLE_DUR = 1500
local FALLBACK_HAMMER_DUR = 2000

local Bahsei = {}
Bahsei.__index = Bahsei

Bahsei.key               = "bahsei"
Bahsei.name              = "Bahsei"
Bahsei.hmHealthThreshold = 100000001

Bahsei.stateSchema = {
    lastCursedGround    = 0,
    nextPortal          = 0,
    portalNumber        = 1,
    selfDoNotPortalTime = 0,
    numPlayersInPortal  = 0,
    portalTracker       = function() return {} end,
    lastDeathTouch      = 0,
    nextMtExplosion     = 0,
    nextSickle          = 0,
    lastPortalCW        = true,
    mtUnitId            = false,
    sunBarId            = false,
}

function Bahsei.new()
    return BossBase.fromSchema(Bahsei)
end

function Bahsei:onLeave(context)
    CA.castAlertsStop(self.sunBarId)
    self.sunBarId = false
end

function Bahsei:onWipe(context, alerts)
    CA.castAlertsStop(self.sunBarId)
    self.sunBarId           = false
    self.lastCursedGround   = 0
    self.nextPortal         = 0
    self.portalNumber       = 1
    self.selfDoNotPortalTime = 0
    self.numPlayersInPortal = 0
    self.portalTracker      = {}
    self.lastDeathTouch     = 0
    self.nextMtExplosion    = 0
    self.nextSickle         = 0
    self.mtUnitId           = false
    self.lastPortalCW       = true
end

function Bahsei:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.nextPortal = GetGameTimeMilliseconds() / 1000 + 20
    end
end

function Bahsei:onDied(context, alerts,
                        unitTag, sourceUnitTag, sourceUnitId, unitId,
                        sourceUnitName, unitName)
    if unitId and self.portalTracker[unitId] then
        self.portalTracker[unitId] = false
        if self.numPlayersInPortal > 0 then
            self.numPlayersInPortal = self.numPlayersInPortal - 1
        end
    end
end

-- -- Handlers ---------------------------------------------------------------

-- MT detection: carve/slice/rendflesh → combatEvent.damage
local function handleMtDetect(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, ...)
    if IsUnitPlayer(unitTag) then boss.mtUnitId = unitId end
end

local function handleCursedGround(boss, ctx, alerts, abilityId, ...)
    boss.lastCursedGround = GetGameTimeMilliseconds() / 1000
    CA.alert(nil, "Cursed Ground", 0xEE82EED9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
end

local function handleSalvo(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        local dur = CastDur.get(SALVO2, FALLBACK_SALVO_DUR)
        CA.interrupt_melee(abilityId, sourceUnitName, dur, Colors.ICE)
        CA.alert(nil, "Interrupt!", 0xFF2020FF, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
    end
end

local function handleSickle(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    boss.nextSickle = GetGameTimeMilliseconds() / 1000 + 15
    if IsUnitPlayer(unitTag) then
        local dur = CastDur.get(SICKLE, FALLBACK_SICKLE_DUR)
        CA.melee(abilityId, sourceUnitName, dur, Colors.VOID)
    end
end

local function handleHemorrhage(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    PlaySound(SOUNDS.DUEL_START)
    CA.alert(nil, "Bleeding", 0xCC0000D9, SOUNDS.DUEL_START, 9000)
end

local function handleRancidHammer(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local _, _, isTank = GetPlayerRoles()
    if isTank then
        local dur = CastDur.get(RANCID_HAMMER, FALLBACK_HAMMER_DUR)
        CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
    end
end

-- Prime Meteor (HM, < ~31% HP): starts a 13.5 s cast bar.
local function handleMeteorSwarm(boss, ctx, alerts, abilityId, ...)
    if not ctx.isHM then return end
    boss.nextSickle = 0
    CA.castAlertsStop(boss.sunBarId)
    boss.sunBarId = CA.bar(
        abilityId, "Prime Meteor",
        13500, 13500, Colors.FLYZONE, 0.4, ACT_METEOR)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleEyeCwGained(boss, ctx, alerts, abilityId, ...)
    boss.lastPortalCW = true
end

local function handleEyeCcwGained(boss, ctx, alerts, abilityId, ...)
    boss.lastPortalCW = false
end

-- effectChanged.gained
local function handleDeathTouch(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        boss.lastDeathTouch = GetGameTimeMilliseconds() / 1000
        CA.border(true, 9000, "blue")
    end
    if unitId and unitId == boss.mtUnitId then
        boss.nextMtExplosion = GetGameTimeMilliseconds() / 1000 + 9
    end
end

-- effectChanged.gained
local function handleMalignantMarrowGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    local now = GetGameTimeMilliseconds() / 1000
    local newPortalTime = now + 50
    if newPortalTime > boss.nextPortal + 5 then
        boss.nextPortal         = newPortalTime
        boss.portalNumber       = 3 - boss.portalNumber   -- 1<->2
        boss.numPlayersInPortal = 0
        boss.portalTracker      = {}
    end
    if AreUnitsEqual("player", unitTag) then
        boss.selfDoNotPortalTime = now + 120
    end
end

-- effectChanged.faded
local function handleMalignantMarrowFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.selfDoNotPortalTime = 0
    end
end

-- effectChanged.gained
local function handleBitterMarrowGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    boss.numPlayersInPortal = boss.numPlayersInPortal + 1
    if unitId then boss.portalTracker[unitId] = true end
end

-- effectChanged.faded
local function handleBitterMarrowFaded(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if boss.numPlayersInPortal > 0 then
        boss.numPlayersInPortal = boss.numPlayersInPortal - 1
    end
    if unitId then boss.portalTracker[unitId] = false end
end

-- -- Event tables ------------------------------------------------------------

local _beginCastEntry = {}
for k, v in pairs(RockgroveCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[CURSED_GROUND] = { type = AlertTypes.CUSTOM, fn = handleCursedGround }
_beginCastEntry[SALVO2]        = { type = AlertTypes.CUSTOM, fn = handleSalvo }
_beginCastEntry[SICKLE]        = { type = AlertTypes.CUSTOM, fn = handleSickle }
_beginCastEntry[HEMORRHAGE]    = { type = AlertTypes.CUSTOM, fn = handleHemorrhage }
_beginCastEntry[RANCID_HAMMER] = { type = AlertTypes.CUSTOM, fn = handleRancidHammer }

local _combatDamageEntry = {
    [MT_CARVE]     = { type = AlertTypes.CUSTOM, fn = handleMtDetect },
    [MT_SLICE]     = { type = AlertTypes.CUSTOM, fn = handleMtDetect },
    [MT_RENDFLESH] = { type = AlertTypes.CUSTOM, fn = handleMtDetect },
}

local _combatOtherEntry = {
    [METEOR_SWARM] = { type = AlertTypes.CUSTOM, fn = handleMeteorSwarm },
    [EYE_CW]       = { type = AlertTypes.CUSTOM, fn = handleEyeCwGained },
    [EYE_CCW]      = { type = AlertTypes.CUSTOM, fn = handleEyeCcwGained },
}

local _effectGainedEntry = {
    [DEATH_TOUCH]      = { type = AlertTypes.CUSTOM, fn = handleDeathTouch },
    [MALIGNANT_MARROW] = { type = AlertTypes.CUSTOM, fn = handleMalignantMarrowGained },
    [BITTER_MARROW]    = { type = AlertTypes.CUSTOM, fn = handleBitterMarrowGained },
}

local _effectFadedEntry = {
    [MALIGNANT_MARROW] = { type = AlertTypes.CUSTOM, fn = handleMalignantMarrowFaded },
    [BITTER_MARROW]    = { type = AlertTypes.CUSTOM, fn = handleBitterMarrowFaded },
}

Bahsei.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = _combatDamageEntry, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Tracker-row renderers ---------------------------------------------------

local function showCursedGroundLine(self, alerts, now)
    if self.lastCursedGround > 0 then
        local T = 28 - (now - self.lastCursedGround)
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.ARCANE, Lang.t("rg_bahsei_next_curse")), T)
        else
            alerts:setRow(1, Fmt.c(Fmt.ARCANE, Lang.t("rg_bahsei_next_curse")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(1)
    end
end

local function showPortalLine(self, alerts, now, isHM)
    if isHM then
        local delta = self.nextPortal - now
        if delta > 0 then
            alerts:setRow(2,
                Fmt.c(Fmt.SKY, "Portal") .. " " ..
                Fmt.c(Fmt.SMOKE, "(" .. self.portalNumber .. ")"),
                delta)
        else
            local dir = self.lastPortalCW
                and Fmt.c("00cc00", Lang.t("rg_bahsei_portal_cw"))
                or  Fmt.c("ff8040", Lang.t("rg_bahsei_portal_ccw"))
            local cnt = self.numPlayersInPortal
            alerts:setRow(2,
                Fmt.c(Fmt.SKY, "Portal") .. " " .. dir ..
                " " .. Fmt.c(Fmt.SMOKE, Lang.t("rg_bahsei_portal_progress")) ..
                (cnt > 0 and (" " .. Fmt.c(Fmt.GRAY, "(" .. cnt .. ")")) or ""),
                nil)
        end
    else
        alerts:clearRow(2)
    end
end

local function showDeathTouchLine(self, alerts, now, isHM)
    local explodeDelta = (self.nextMtExplosion > 0) and (self.nextMtExplosion - now) or -1
    local dtDelta      = (self.lastDeathTouch  > 0) and (9 - (now - self.lastDeathTouch)) or -1
    if explodeDelta >= 0 and explodeDelta <= 3 then
        alerts:setRow(3, Fmt.c(Fmt.RED, Lang.t("rg_bahsei_tank_exploding")), explodeDelta)
    elseif dtDelta > 0 then
        alerts:setRow(3, Fmt.c(Fmt.FROST, Lang.t("rg_bahsei_death_touch")), dtDelta)
    elseif isHM and self.selfDoNotPortalTime > 0 then
        local noPortalDelta = self.selfDoNotPortalTime - now
        if noPortalDelta > 0 then
            alerts:setRow(3, Fmt.c(Fmt.FIRE, Lang.t("rg_bahsei_no_portal")), noPortalDelta)
        else
            alerts:clearRow(3)
        end
    else
        alerts:clearRow(3)
    end
end

local function showSickleLine(self, alerts, now, isHM)
    if isHM and self.nextSickle > 0 then
        local T = self.nextSickle - now
        if T > 0 and T <= 15 then
            alerts:setRow(4, Fmt.c(Fmt.PURPLE, Lang.t("rg_bahsei_next_sickle")), T)
        elseif T <= 0 then
            alerts:setRow(4, Fmt.c(Fmt.PURPLE, Lang.t("rg_bahsei_next_sickle")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        else
            alerts:clearRow(4)
        end
    else
        alerts:clearRow(4)
    end
end

function Bahsei:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showCursedGroundLine(self, alerts, now)
    showPortalLine(self, alerts, now, isHM)
    showDeathTouchLine(self, alerts, now, isHM)
    showSickleLine(self, alerts, now, isHM)
end

EventDispatcher.build(Bahsei)

package.loaded["trial.rg.boss.Bahsei"] = Bahsei
return Bahsei
