--- Oaxiltso — Rockgrove boss 1
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) ✓
--- Phase RG-3: Oaxiltso-specific mechanics
---   SavageBlitz (149414 / 157932 HM): BEGIN → CastAlertsStart 2750 ms; 36 s cycle
---   NoxiousSludge (149190): BEGIN → Alert; 28 s cycle
---   PoisonedPlayers (157860 debuff): track 2 poisoned players + side via pool distance
---   AnnihilatorSunburst (153181): BEGIN → zo_callLater 2500 ms → "Meteor. BLOCK!"
---   CinderCleave (152688): targeted player → AlertCast 2000 ms
---   EmberChains (152699): targeted player → AlertCast 750 ms
---   MeteorCrash/AddSpawn (152365): EFFECT_GAINED → "ADD SPAWNING!" 3 s
---   BossEnrage (152502) / MiniEnrage (152503): EFFECT_GAINED/FADED flags

local RockgroveCommon = require("trial.rg.RockgroveCommon")

-- ── Boss definition ───────────────────────────────────────────────────────
local Oaxiltso = {
    id   = 1,
    key  = "oaxiltso",
    name = "Oaxiltso",   -- TODO: verify exact unit name from GetUnitName("boss1")
}

-- ── State ─────────────────────────────────────────────────────────────────
Oaxiltso.lastBlitz        = 0   -- s: last Savage Blitz cast time
Oaxiltso.lastSludge       = 0   -- s: last Noxious Sludge cast time
Oaxiltso.lastPoisonTracker= 0   -- s: dedup cooldown for sludge debuff event
Oaxiltso.sludgeTracker1   = 0   -- unitId of first poisoned player
Oaxiltso.sludgeTracker2   = 0   -- unitId of second poisoned player
Oaxiltso.bossEnraged      = false
Oaxiltso.miniEnraged      = false

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Oaxiltso:reset(forced)
    self.lastBlitz         = 0
    self.lastSludge        = 0
    self.lastPoisonTracker = 0
    self.sludgeTracker1    = 0
    self.sludgeTracker2    = 0
    self.bossEnraged       = false
    self.miniEnraged       = false
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Oaxiltso:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.lastBlitz         = 0
        self.lastSludge        = 0
        self.lastPoisonTracker = 0
        self.sludgeTracker1    = 0
        self.sludgeTracker2    = 0
    end
end

-- ── Combat events ─────────────────────────────────────────────────────────
-- Filled in Phase RG-3. Signature:
--   self, context, alerts, result, abilityId,
--   unitTag, sourceUnitTag, sourceUnitId, unitId,
--   sourceUnitName, unitName
function Oaxiltso:onCombatEvent(context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
    if RockgroveCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end
    -- Phase RG-3: Oaxiltso mechanics
end

-- ── Effect changes ────────────────────────────────────────────────────────
-- Filled in Phase RG-3. Signature:
--   self, context, alerts, changeType, abilityId, unitTag, unitId, unitName
function Oaxiltso:onEffectChanged(context, alerts, changeType, abilityId,
                                  unitTag, unitId, unitName)
    -- Phase RG-3: sludge debuff side logic + enrage flags
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Oaxiltso:onUpdate(context, alerts)
    -- Phase RG-3: info1=NextBlitz, info2=NextSludge, info3=Enrage
    alerts:showInfo(1, "")
    alerts:showInfo(2, "")
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
end

return Oaxiltso
