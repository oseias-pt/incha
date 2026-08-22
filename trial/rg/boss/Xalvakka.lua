--- Xalvakka — Rockgrove boss 3
---
--- Three-floor fight:
---   Floor 1: HP 100–70%  (boss escapes at 70%)
---   Floor 2: HP  70–40%  (boss escapes at 40%)
---   Floor 3: HP   0–40%
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) ✓
--- Phase RG-5: Xalvakka-specific mechanics
---   ScathingEvisceration (149180/153448/153450): targeted player → AlertCast
---   Deadstar (149386/149075): BEGIN → Alert("Deadstar!")
---   FlamingPortal/Jump (157390): BEGIN → nextJump +35 s, numJumps++ (HM)
---   SoulResonance (152993): EFFECT_GAINED self → Alert("Purge!"), start timer
---   UnstableCharge/Blob (153164): EFFECT_GAINED/FADED self → AlertBorder green
---   VolatileShell shield (153164+): onShieldUpdated hook on "reticleover"
---   ManifoldDebuff (157290): EFFECT_GAINED/FADED → OSI curse icon (optional)
---   Run timer: HP 70–75% and 40–45% → "RUN IN: X.X%"
---
--- Shield tracking (Volatile Shell):
---   Requires EVENT_UNIT_ATTRIBUTE_VISUAL_* — registered in onEnter, cleaned
---   up in reset(). See Phase RG-5 for implementation. CombatHandler does NOT
---   carry this; it is self-contained in Xalvakka:onEnter / Xalvakka:reset.
---
--- HM detection: effectiveMaxHealth > hmHealthThreshold.
---   TODO: verify exact HM health pool in-game.

local RockgroveCommon  = require("trial.rg.RockgroveCommon")
local SHIELD_EVENT_KEY = "Incha_RG_XalvakkaShield"

-- ── Boss definition ───────────────────────────────────────────────────────
local Xalvakka = {
    id                = 3,
    key               = "xalvakka",
    name              = "Xalvakka",     -- TODO: verify exact unit name in-game
    hmHealthThreshold = 100000001,      -- TODO: verify exact HM health pool
}

-- ── State ─────────────────────────────────────────────────────────────────
Xalvakka.nextJump    = 0      -- s: absolute time of next floor-portal jump
Xalvakka.numJumps    = 0      -- count of jumps this floor-1 phase (hide timer at 4)
Xalvakka.shellShield = 0      -- current Volatile Shell HP (from shield event)
Xalvakka.onBlob      = false  -- player standing on Unstable Charge blob
Xalvakka.soulStart   = 0      -- s: when player gained Soul Resonance debuff
Xalvakka.isHM        = false

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Xalvakka:reset(forced)
    -- Phase RG-5: unregister shield events here
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED)

    self.nextJump    = 0
    self.numJumps    = 0
    self.shellShield = 0
    self.onBlob      = false
    self.soulStart   = 0
    self.isHM        = false
end

-- ── Boss enter ────────────────────────────────────────────────────────────
-- Called by Trial:onBossesChanged when this boss becomes active.
-- Register shield tracking events here so they are scoped to the encounter.
function Xalvakka:onEnter(context, alerts)
    -- Phase RG-5: register EVENT_UNIT_ATTRIBUTE_VISUAL_* here.
    -- Handler: check unitTag=="reticleover" + ATTRIBUTE_VISUAL_POWER_SHIELDING
    --          + name contains "volatile shell" → update self.shellShield.
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Xalvakka:onCombatState(context, inCombat, alerts)
    if inCombat then
        -- Phase RG-5: detect HM, set nextJump = now+30 (first jump), numJumps=0
        self.nextJump    = 0
        self.numJumps    = 0
        self.shellShield = 0
        self.onBlob      = false
        self.soulStart   = 0
    end
end

-- ── Combat events ─────────────────────────────────────────────────────────
function Xalvakka:onCombatEvent(context, alerts, result, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    if RockgroveCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end
    -- Phase RG-5: Xalvakka mechanics
end

-- ── Effect changes ────────────────────────────────────────────────────────
function Xalvakka:onEffectChanged(context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName)
    -- Phase RG-5: soul resonance, unstable charge/blob, manifold debuff
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Xalvakka:onUpdate(context, alerts)
    -- Phase RG-5:
    --   info1 = Next Jump (HM, Floor 1, hide after 4 jumps or HP < 70%)
    --   info2 = Soul Resonance timer
    --   info3 = Volatile Shell shield value ("X.XXM")
    --   bigtext = "RUN IN: X.X%" at HP 70–75% and 40–45%
    --   bigtext = "ON BLOB" while onBlob
    alerts:showInfo(1, "")
    alerts:showInfo(2, "")
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
end

return Xalvakka
