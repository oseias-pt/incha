--- Bahsei (Flame-Herald Bahsei) — Rockgrove boss 2
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) ✓
--- Phase RG-4: Bahsei-specific mechanics
---
--- onCombatEvent:
---   CursedGround    (152475): BEGIN → Alert; 28 s cycle
---   Salvo2/Interrupt(152463): BEGIN, tank-only → AlertCast + "Interrupt!" Alert
---   Sickle          (150067): BEGIN → nextSickle +15 s; if targeted → AlertCast
---   Hemorrhage      (150008): targeted player → "Bleeding" Alert 9 s
---   RancidHammer    (149922): BEGIN, tank-only → AlertCast
---   MT detection: carve/slice/rendflesh (150047/150048/150065) target → mtUnitId
---   MeteorSwarm     (155357): EFFECT_GAINED_DURATION → CastAlertsStart 13.5 s (HM)
---   EyeCW/CCW       (153517/153518): EFFECT_GAINED → track portal direction (HM)
---
--- onEffectChanged:
---   DeathTouch (150078): GAINED on self → AlertBorder blue 9 s;
---                        GAINED on mtUnitId → nextMtExplosion +9 s
---   MalignantMarrow (153421): GAINED → nextPortal +50 s, flip portalNumber;
---                             self GAINED → selfDoNotPortalTime +120 s;
---                             self FADED  → clear selfDoNotPortalTime
---   BitterMarrow (153423): GAINED → numPlayersInPortal++; FADED → --
---
--- Note: Scalding (153175) on Fire Behemoth add is handled by RockgroveCommon.
---
--- HM detection: context.difficulty == Difficulty.HARDMODE
---   (set by BossRegistry:detectDifficulty via hmHealthThreshold=100000001)

local Difficulty      = require("core.Difficulty")
local RockgroveCommon = require("trial.rg.RockgroveCommon")

-- ── Ability IDs ────────────────────────────────────────────────────────────
local CURSED_GROUND    = 152475
local SALVO2           = 152463   -- channeled cast → interrupt prompt (tanks)
local SICKLE           = 150067   -- ground AoE scythe; also targeted occasionally
local HEMORRHAGE       = 150008   -- Flesh Abomination: places bleed DoT
local RANCID_HAMMER    = 149922   -- Flesh Abomination: AoE slam (tanks)
local MT_ATTACK_IDS    = { [150047]=true, [150048]=true, [150065]=true }
                                   -- Bahsei carve/slice/rendflesh → MT detection
local DEATH_TOUCH      = 150078   -- curse: explodes on the player after ~9 s
local MALIGNANT_MARROW = 153421   -- debuff: exited portal; next portal in 50 s
local BITTER_MARROW    = 153423   -- debuff: currently in portal
local METEOR_SWARM     = 155357   -- Prime Meteor cast (HM, HP < ~31%)
local EYE_CW           = 153517   -- portal rotation direction: clockwise
local EYE_CCW          = 153518   -- portal rotation direction: counter-clockwise

-- ── CombatAlerts helpers ───────────────────────────────────────────────────
local function caAlertCast(...)       if CombatAlerts then return CombatAlerts.AlertCast(...)        end end
local function caAlert(...)           if CombatAlerts then return CombatAlerts.Alert(...)             end end
local function caCastAlertsStart(...) if CombatAlerts then return CombatAlerts.CastAlertsStart(...)  end end
local function caCastAlertsStop(id)   if CombatAlerts and id then CombatAlerts.CastAlertsStop(id)    end end
local function caAlertBorder(...)     if CombatAlerts then return CombatAlerts.AlertBorder(...)      end end

-- ── CA colour palettes ─────────────────────────────────────────────────────
local COL_INTERRUPT = { -2, 0, true,  { 0.3, 0.6, 1.0, 0.4 }, { 0.3, 0.6, 1.0, 0.8 } }
local COL_SICKLE    = { -2, 0, false, { 0.7, 0.2, 0.9, 0.4 }, { 0.7, 0.2, 0.9, 0.8 } }
local COL_HAMMER    = { -2, 0, false, { 1.0, 0.5, 0.1, 0.4 }, { 1.0, 0.5, 0.1, 0.8 } }
local COL_METEOR    = { 1.0, 0.70, 0.0, 0.5 }
local ACT_METEOR    = { 10000, "KILL SUN!", 0.8, 0.0, 0.0, 0.9, nil }

-- ── Boss definition ───────────────────────────────────────────────────────
local Bahsei = {
    id                = 2,
    key               = "bahsei",
    name              = "Bahsei",      -- TODO: verify; may be "Flame-Herald Bahsei"
    hmHealthThreshold = 100000001,     -- TODO: verify exact HM health pool in-game
}

-- ── State ─────────────────────────────────────────────────────────────────
Bahsei.lastCursedGround    = 0      -- s: last Cursed Ground cast time
Bahsei.nextPortal          = 0      -- s: absolute time of next portal opening
Bahsei.portalNumber        = 1      -- 1 or 2, alternates each cycle
Bahsei.selfDoNotPortalTime = 0      -- s: until player's Malignant Marrow expires
Bahsei.numPlayersInPortal  = 0
Bahsei.portalTracker       = {}     -- [unitId] = true while in portal
Bahsei.lastDeathTouch      = 0      -- s: when the local player received death touch
Bahsei.nextMtExplosion     = 0      -- s: expected MT explosion time (lastDT + 9)
Bahsei.mtUnitId            = nil    -- unitId of current main tank
Bahsei.nextSickle          = 0      -- s: absolute time of next expected sickle
Bahsei.sunBarId            = nil    -- CA CastAlertsStart bar for Prime Meteor
Bahsei.lastPortalCW        = true   -- true=clockwise, false=CCW

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Bahsei:reset(forced)
    caCastAlertsStop(self.sunBarId)
    self.sunBarId              = nil
    self.lastCursedGround      = 0
    self.nextPortal            = 0
    self.portalNumber          = 1
    self.selfDoNotPortalTime   = 0
    self.numPlayersInPortal    = 0
    self.portalTracker         = {}
    self.lastDeathTouch        = 0
    self.nextMtExplosion       = 0
    self.mtUnitId              = nil
    self.nextSickle            = 0
    self.lastPortalCW          = true
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Bahsei:onCombatState(context, inCombat, alerts)
    if inCombat then
        caCastAlertsStop(self.sunBarId)
        self.sunBarId              = nil
        self.lastCursedGround      = 0
        self.portalNumber          = 1
        self.numPlayersInPortal    = 0
        self.portalTracker         = {}
        self.lastDeathTouch        = 0
        self.nextMtExplosion       = 0
        self.nextSickle            = 0
        self.selfDoNotPortalTime   = 0

        -- First portal opens ~20 s into the fight.
        -- HM only — nextPortal is displayed only when context.difficulty == HARDMODE.
        self.nextPortal = GetGameTimeMilliseconds() / 1000 + 20
    end
end

-- ── Combat events ─────────────────────────────────────────────────────────
function Bahsei:onCombatEvent(context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if RockgroveCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    -- ── Main tank detection ───────────────────────────────────────────────
    -- Bahsei's direct attacks on a player identify them as the MT.
    if MT_ATTACK_IDS[abilityId] and IsUnitPlayer(unitTag) then
        self.mtUnitId = unitId
    end

    -- ── Dead players: clean up portal tracker ─────────────────────────────
    if result == ACTION_RESULT_DIED then
        if unitId and self.portalTracker[unitId] then
            self.portalTracker[unitId] = false
            if self.numPlayersInPortal > 0 then
                self.numPlayersInPortal = self.numPlayersInPortal - 1
            end
        end
        return
    end

    -- ── Cursed Ground ─────────────────────────────────────────────────────
    if abilityId == CURSED_GROUND and result == ACTION_RESULT_BEGIN then
        self.lastCursedGround = GetGameTimeMilliseconds() / 1000
        caAlert(nil, "Cursed Ground", 0xEE82EED9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
        return
    end

    -- ── Salvo2: channeled cast → tanks interrupt ──────────────────────────
    if abilityId == SALVO2 and result == ACTION_RESULT_BEGIN then
        local _, _, isTank = GetPlayerRoles()
        if isTank then
            local dur = select(1, GetAbilityCastInfo(SALVO2)) or 0
            if dur <= 0 then dur = 2500 end
            caAlertCast(abilityId, sourceUnitName, dur, COL_INTERRUPT)
            caAlert(nil, "Interrupt!", 0xFF2020FF, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
        end
        return
    end

    -- ── Sickle ────────────────────────────────────────────────────────────
    if abilityId == SICKLE and result == ACTION_RESULT_BEGIN then
        self.nextSickle = GetGameTimeMilliseconds() / 1000 + 15
        if IsUnitPlayer(unitTag) then
            local dur = select(1, GetAbilityCastInfo(SICKLE)) or 0
            if dur <= 0 then dur = 1500 end
            caAlertCast(abilityId, sourceUnitName, dur, COL_SICKLE)
        end
        return
    end

    -- ── Flesh Abomination: Hemorrhage (bleed DoT on player) ──────────────
    if abilityId == HEMORRHAGE and result == ACTION_RESULT_BEGIN then
        if not IsUnitPlayer(unitTag) then return end
        PlaySound(SOUNDS.DUEL_START)
        PlaySound(SOUNDS.DUEL_START)
        caAlert(nil, "Bleeding", 0xCC0000D9, SOUNDS.DUEL_START, 9000)
        return
    end

    -- ── Flesh Abomination: Rancid Hammer (AoE slam, tanks) ───────────────
    if abilityId == RANCID_HAMMER and result == ACTION_RESULT_BEGIN then
        local _, _, isTank = GetPlayerRoles()
        if isTank then
            local dur = select(1, GetAbilityCastInfo(RANCID_HAMMER)) or 0
            if dur <= 0 then dur = 2000 end
            caAlertCast(abilityId, sourceUnitName, dur, COL_HAMMER)
        end
        return
    end

    -- ── Meteor Swarm: Prime Meteor (HM, < ~31% HP) ───────────────────────
    if abilityId == METEOR_SWARM
       and result == ACTION_RESULT_EFFECT_GAINED_DURATION
       and context.difficulty == Difficulty.HARDMODE then
        self.nextSickle = 0   -- sickle irrelevant from here; free the slot
        caCastAlertsStop(self.sunBarId)
        self.sunBarId = caCastAlertsStart(
            abilityId, "Prime Meteor",
            13500, 13500, COL_METEOR, ACT_METEOR)
        PlaySound(SOUNDS.DUEL_START)
        return
    end

    -- ── Portal eye direction (HM) ─────────────────────────────────────────
    if abilityId == EYE_CW  and result == ACTION_RESULT_EFFECT_GAINED then
        self.lastPortalCW = true;  return
    end
    if abilityId == EYE_CCW and result == ACTION_RESULT_EFFECT_GAINED then
        self.lastPortalCW = false; return
    end
end

-- ── Effect changes ────────────────────────────────────────────────────────
function Bahsei:onEffectChanged(context, alerts, changeType, abilityId,
                                unitTag, unitId, unitName)
    -- ── Death Touch ───────────────────────────────────────────────────────
    if abilityId == DEATH_TOUCH and changeType == EFFECT_RESULT_GAINED then
        -- Personal border: player received the curse
        if AreUnitsEqual("player", unitTag) then
            self.lastDeathTouch = GetGameTimeMilliseconds() / 1000
            caAlertBorder(true, 9000, "blue")
        end
        -- MT explosion: track whose curse will detonate first
        if unitId and unitId == self.mtUnitId then
            self.nextMtExplosion = GetGameTimeMilliseconds() / 1000 + 9
        end
        return
    end

    -- ── Malignant Marrow (exited portal) ──────────────────────────────────
    if abilityId == MALIGNANT_MARROW then
        if changeType == EFFECT_RESULT_GAINED then
            -- Event fires up to 3 times — accept only once per 5 s window.
            local now = GetGameTimeMilliseconds() / 1000
            local newPortalTime = now + 50
            if newPortalTime > self.nextPortal + 5 then
                self.nextPortal         = newPortalTime
                self.portalNumber       = 3 - self.portalNumber   -- 1↔2
                self.numPlayersInPortal = 0
                self.portalTracker      = {}
            end
            if AreUnitsEqual("player", unitTag) then
                self.selfDoNotPortalTime = now + 120
            end

        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.selfDoNotPortalTime = 0
            end
        end
        return
    end

    -- ── Bitter Marrow (in portal) ─────────────────────────────────────────
    if abilityId == BITTER_MARROW then
        if changeType == EFFECT_RESULT_GAINED then
            self.numPlayersInPortal = self.numPlayersInPortal + 1
            if unitId then self.portalTracker[unitId] = true end

        elseif changeType == EFFECT_RESULT_FADED then
            if self.numPlayersInPortal > 0 then
                self.numPlayersInPortal = self.numPlayersInPortal - 1
            end
            if unitId then self.portalTracker[unitId] = false end
        end
        return
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Bahsei:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    local isHM = (context.difficulty == Difficulty.HARDMODE)

    -- ── Info 1: Next Cursed Ground (28 s cycle) ────────────────────────────
    if self.lastCursedGround > 0 then
        local T = 28 - (now - self.lastCursedGround)
        if T > 0 then
            alerts:showInfo(1, "|caa50ffNext Curse|r: " .. string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(1, "|caa50ffNext Curse|r: |cff0000INC|r")
        end
    else
        alerts:showInfo(1, "")
    end

    -- ── Info 2 (HM): Next Portal ───────────────────────────────────────────
    if isHM then
        local delta = self.nextPortal - now
        if delta > 0 then
            alerts:showInfo(2,
                "|c38bdf8Portal|r |c7b82a0(" .. self.portalNumber .. ")|r: " ..
                string.format("%.0f", delta) .. "s")
        else
            local dir = self.lastPortalCW and "|c00cc00CW|r" or "|cff8040CCW|r"
            alerts:showInfo(2, "|c38bdf8Portal|r " .. dir .. " |c7b82a0in progress|r")
        end
    else
        alerts:showInfo(2, "")
    end

    -- ── Info 3: Death Touch personal countdown, then Do-Not-Portal ────────
    local dtDelta = (self.lastDeathTouch > 0) and (9 - (now - self.lastDeathTouch)) or -1
    if dtDelta > 0 then
        alerts:showInfo(3, "|c6699ffDeath Touch|r: " ..
            string.format("%.1f", dtDelta) .. "s")
    elseif isHM and self.selfDoNotPortalTime > 0 then
        local noPortalDelta = self.selfDoNotPortalTime - now
        if noPortalDelta > 0 then
            alerts:showInfo(3, "|cff6030No Portal|r: " ..
                string.format("%.0f", noPortalDelta) .. "s")
        else
            alerts:showInfo(3, "")
        end
    else
        alerts:showInfo(3, "")
    end

    -- ── Info 4 (HM): Next Sickle (15 s window) ────────────────────────────
    if isHM and self.nextSickle > 0 then
        local T = self.nextSickle - now
        if T > 0 and T <= 15 then
            alerts:showInfo(4, "|ccc80ffNext Sickle|r: " .. string.format("%.0f", T) .. "s")
        elseif T <= 0 then
            alerts:showInfo(4, "|ccc80ffNext Sickle|r: |cff0000INC|r")
        else
            alerts:showInfo(4, "")
        end
    else
        alerts:showInfo(4, "")
    end

    -- ── showAction: Tank Exploding (3 s critical window) ──────────────────
    if self.nextMtExplosion > 0 then
        local explodeDelta = self.nextMtExplosion - now
        if explodeDelta >= 0 and explodeDelta <= 3 then
            alerts:showAction("TANK EXPLODING: " ..
                string.format("%.0f", explodeDelta) .. "s!")
        end
    end
end

return Bahsei
