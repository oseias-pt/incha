--- Bahsei (Flame-Herald Bahsei) — Rockgrove boss 2
---
--- Phase RG-2: RockgroveCommon.handle() call (trash mechanics)
--- Phase RG-4: Bahsei-specific mechanics
---   CursedGround (152475): BEGIN → Alert; 28 s cycle
---   Salvo2/Interrupt (152463): BEGIN, tank-only → AlertCast + Alert("Interrupt!")
---   Sickle (150067): BEGIN → nextSickle +15 s; if targeted → AlertCast
---   FleshAbomHemorrhage (150008): targeted player → Alert("Bleeding") 9 s
---   FleshAbomRancidHammer (149922): tank-only → AlertCast
---   FBehemScalding (153175): targeted player → AlertCast + Alert("Scalding")
---   MT tracking: carve/slice/rendflesh (150047/150048/150065) target → mtUnitId
---   DeathTouch (150078): player self → AlertBorder blue 9 s; MT → nextMtExplosion +9 s
---   MalignantMarrow (153421): exited portal → nextPortal +50 s, flip portalNumber
---   BitterMarrow (153423): entered portal → numPlayersInPortal ±1
---   MeteorSwarm (155357): EFFECT_GAINED_DURATION → CastAlertsStart 13500 ms (HM)
---   EyeCW/CCW (153517/153518): EFFECT_GAINED → track lastPortalCW (HM)
---
--- HM detection: effectiveMaxHealth > 100,000,000 on fight start via
---   context difficulty set by BossRegistry:detectDifficulty
---
--- Note: hmHealthThreshold set below. Verify exact value in-game.

-- ── Boss definition ───────────────────────────────────────────────────────
local Bahsei = {
    id                 = 2,
    key                = "bahsei",
    name               = "Bahsei",      -- TODO: verify; may be "Flame-Herald Bahsei"
    hmHealthThreshold  = 100000001,     -- TODO: verify exact HM health pool in-game
}

-- ── State ─────────────────────────────────────────────────────────────────
Bahsei.lastCursedGround    = 0     -- s
Bahsei.nextPortal          = 0     -- s: absolute time of next portal opening
Bahsei.portalNumber        = 1     -- 1 or 2, alternates each cycle
Bahsei.selfDoNotPortalTime = 0     -- s: until player's malignant marrow expires
Bahsei.numPlayersInPortal  = 0
Bahsei.portalTracker       = {}    -- [unitId] = true/false (in portal)
Bahsei.lastDeathTouch      = 0     -- s: when player received death touch
Bahsei.nextMtExplosion     = 0     -- s: MT explosion at lastDeathTouch+9
Bahsei.mtUnitId            = nil   -- unitId of the current main tank
Bahsei.nextSickle          = 0     -- s
Bahsei.nextSun             = 0     -- s (HM, Meteor Swarm)
Bahsei.lastPortalCW        = true  -- true=clockwise, false=counterclockwise
Bahsei.isHM                = false

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Bahsei:reset(forced)
    self.lastCursedGround    = 0
    self.nextPortal          = 0
    self.portalNumber        = 1
    self.selfDoNotPortalTime = 0
    self.numPlayersInPortal  = 0
    self.portalTracker       = {}
    self.lastDeathTouch      = 0
    self.nextMtExplosion     = 0
    self.mtUnitId            = nil
    self.nextSickle          = 0
    self.nextSun             = 0
    self.lastPortalCW        = true
    self.isHM                = false
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Bahsei:onCombatState(context, inCombat, alerts)
    if inCombat then
        -- Phase RG-4: detect HM, set nextPortal = now+20
        self:reset(false)
    end
end

-- ── Combat events ─────────────────────────────────────────────────────────
function Bahsei:onCombatEvent(context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    -- Phase RG-2: RockgroveCommon.handle() goes here first
    -- Phase RG-4: Bahsei mechanics
end

-- ── Effect changes ────────────────────────────────────────────────────────
function Bahsei:onEffectChanged(context, alerts, changeType, abilityId,
                                unitTag, unitId, unitName)
    -- Phase RG-4: death touch, marrow debuffs, meteor swarm, eye direction
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Bahsei:onUpdate(context, alerts)
    -- Phase RG-4:
    --   info1 = Next Curse (28 s cycle)
    --   info2 = Next Portal (HM): countdown / "In progress... CW/CCW"
    --   info3 = Do Not Portal self-cooldown (HM)
    --   info4 = Next Sickle (HM, 15 s window)
    --   info5 = Next Sun (HM, HP < 31%)
    --   bigtext = Death Touch countdown (9 s window)
    --   bigtext = Tank Exploding (3 s window)
    alerts:showInfo(1, "")
    alerts:showInfo(2, "")
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
end

return Bahsei
