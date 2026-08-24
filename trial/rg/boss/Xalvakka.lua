--- Xalvakka — Rockgrove boss 3
---
--- Three-floor fight:
---   Floor 1: HP 100–70%  (boss escapes at 70%)
---   Floor 2: HP  70–40%  (boss escapes at 40%)
---   Floor 3: HP   0–40%
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) ✓
--- Phase RG-5: Xalvakka-specific mechanics ✓
---   ScathingEvisceration (149180/153448/153450): targeted player → AlertCast
---   Deadstar (149386/149075): BEGIN → Alert("Deadstar!")
---   FlamingPortal/Jump (157390): BEGIN → nextJump +35 s, numJumps++ (HM)
---   SoulResonance (152993): EFFECT_GAINED self → Alert("Purge!"), start timer
---   UnstableCharge/Blob (153164): EFFECT_GAINED/FADED self → AlertBorder green; info4
---   VolatileShell shield: EVENT_UNIT_ATTRIBUTE_VISUAL_* on "reticleover" → shellShield
---   Run timer: HP 70–75% and 40–45% → info4 countdown
--- Phase RG-6: ManifoldDebuff (157290) ✓
---   EFFECT_GAINED self   → AlertBorder purple + "Manifold Curse!" caAlert
---   EFFECT_GAINED others → name tracked in manifoldOthers[]
---   EFFECT_FADED self    → border cleared, selfManifold = false
---   EFFECT_FADED others  → removed from manifoldOthers[]
---   onUpdate info3       → manifold list (priority) > shell shield value
---
--- Shield tracking (Volatile Shell):
---   Registered in onEnter (scoped to the encounter), cleaned up in onLeave().
---   CombatHandler does NOT carry EVENT_UNIT_ATTRIBUTE_VISUAL_*; registration
---   is self-contained here using key SHIELD_EVENT_KEY.
---
---   TODO: Verify ATTRIBUTE_VISUAL_POWER_SHIELDING constant and event parameter
---         order against the live ESO API before publishing.
---
--- HM detection: context.isHM (pre-computed by TrialContext from hmHealthThreshold)
---   (set by BossRegistry:detectDifficulty via hmHealthThreshold=100000001)
---   TODO: verify exact HM health pool in-game.

local RockgroveCommon = require("trial.rg.RockgroveCommon")

local SHIELD_EVENT_KEY = "Incha_RG_XalvakkaShield"

-- ── Ability IDs ────────────────────────────────────────────────────────────
local SCATHING1       = 149180   -- ScathingEvisceration (base)
local SCATHING2       = 153448   -- ScathingEvisceration HM variant 1
local SCATHING3       = 153450   -- ScathingEvisceration HM variant 2
local DEADSTAR1       = 149386   -- Deadstar add-explosion
local DEADSTAR2       = 149075   -- Deadstar variant
local FLAMING_PORTAL  = 157390   -- Boss repositioning jump (HM)
local SOUL_RESONANCE  = 152993   -- Player debuff: purge required
local UNSTABLE_CHARGE = 153164   -- Blob player debuff (Unstable Charge orb)
local MANIFOLD_DEBUFF = 157290   -- Curse: spread from cursed player, AlertBorder + tracker

local SCATHING_IDS = { [149180]=true, [153448]=true, [153450]=true }
local DEADSTAR_IDS = { [149386]=true, [149075]=true }

-- Soul resonance display window after GAINED (seconds); approximate; verify in-game.
local SOUL_WINDOW = 9

-- HP % ranges that trigger the run timer display.
local RUN1_TOP = 75    -- first transition: boss flees at 70%
local RUN1_BOT = 70
local RUN2_TOP = 45    -- second transition: boss flees at 40%
local RUN2_BOT = 40

local CA = require("lib.CA")

-- ── CA colour palettes ─────────────────────────────────────────────────────
local COL_SCATHING = { -2, 0, false, { 0.9, 0.2, 0.9, 0.4 }, { 0.9, 0.2, 0.9, 0.8 } }

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_SCATHING_DUR = 1500   -- ScathingEvisceration: empirical

-- ── Shield value formatter ─────────────────────────────────────────────────
local function fmtShield(v)
    if v >= 1000000 then
        return string.format("%.2fM", v / 1000000)
    elseif v >= 1000 then
        return string.format("%.1fk", v / 1000)
    else
        return tostring(math.floor(v))
    end
end

-- ── Boss definition ───────────────────────────────────────────────────────
local Xalvakka = {}
Xalvakka.__index = Xalvakka
Xalvakka.common = RockgroveCommon   -- C3: common mechanic dispatch

Xalvakka.key               = "xalvakka"
Xalvakka.name              = "Xalvakka"     -- TODO: verify exact unit name via GetUnitName("boss1")
Xalvakka.hmHealthThreshold = 100000001      -- TODO: verify exact HM health pool

function Xalvakka.new()
    return setmetatable({
        nextJump       = 0,     -- s: absolute time of next expected jump
        numJumps       = 0,     -- jump count; hide timer when ≥ 4
        shellShield    = 0,     -- current Volatile Shell HP (from shield events)
        onBlob         = false, -- true while player carries Unstable Charge debuff
        soulStart      = 0,     -- s: when player gained Soul Resonance; 0 = inactive
        selfManifold   = false, -- true while local player carries Manifold Curse
        manifoldOthers = {},    -- [unitTag] → displayName for other players cursed
    }, Xalvakka)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Xalvakka:onLeave(context)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED)
end

-- ── Boss enter ────────────────────────────────────────────────────────────
-- Called by Trial:onBossesChanged when Xalvakka becomes the active boss.
-- Self-registers Volatile Shell shield tracking so it is encounter-scoped.
function Xalvakka:onEnter(context, alerts)
    -- Unregister first; onEnter may fire again after a soft-reset / floor transition.
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED)
    EVENT_MANAGER:UnregisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED)

    -- ESO event parameters (verify against live API):
    --   eventCode, unitTag, attributeType, powerType, value, max, shieldPoolIndex
    -- ATTRIBUTE_VISUAL_POWER_SHIELDING tracks absorb shields on a unit's health bar.
    EVENT_MANAGER:RegisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_ADDED,
        function(eventCode, unitTag, attributeType, powerType, value, max, poolIndex)
            if unitTag ~= "reticleover" then return end
            if attributeType == ATTRIBUTE_VISUAL_POWER_SHIELDING then
                self.shellShield = value or 0
            end
        end)

    EVENT_MANAGER:RegisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_UPDATED,
        function(eventCode, unitTag, attributeType, powerType, value, max, poolIndex)
            if unitTag ~= "reticleover" then return end
            if attributeType == ATTRIBUTE_VISUAL_POWER_SHIELDING then
                self.shellShield = value or 0
            end
        end)

    EVENT_MANAGER:RegisterForEvent(SHIELD_EVENT_KEY, EVENT_UNIT_ATTRIBUTE_VISUAL_REMOVED,
        function(eventCode, unitTag, attributeType, powerType, value, max, poolIndex)
            if unitTag ~= "reticleover" then return end
            if attributeType == ATTRIBUTE_VISUAL_POWER_SHIELDING then
                self.shellShield = 0
            end
        end)
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Xalvakka:onCombatState(context, inCombat, alerts)
    if inCombat then
        -- First jump expected ~35 s after pull in HM; same interval as subsequent jumps.
        -- TODO: verify first-jump timing in-game (may differ from subsequent 35 s interval).
        self.nextJump = GetGameTimeMilliseconds() / 1000 + 35
        self.numJumps = 0
    end
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- (No onDied needed — Xalvakka has no alertList.)

-- ScathingEvisceration: player-targeted frontal heavy (3 IDs, shared handler).
local function handleScathing(self, context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    if result ~= ACTION_RESULT_BEGIN then return end
    if not IsUnitPlayer(unitTag) then return end
    local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
    if dur <= 0 then dur = FALLBACK_SCATHING_DUR end
    CA.alertCast(abilityId, sourceUnitName, dur, COL_SCATHING)
end

-- Deadstar add explosion (2 IDs, shared handler).
local function handleDeadstar(self, context, alerts, result, abilityId, ...)
    if result ~= ACTION_RESULT_BEGIN then return end
    CA.alert(nil, "Deadstar!", 0xFFCC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

Xalvakka.combatRoutes = {
    -- ScathingEvisceration (base + two HM variants)
    [SCATHING1] = handleScathing,
    [SCATHING2] = handleScathing,
    [SCATHING3] = handleScathing,
    -- Deadstar add-explosion (two variants)
    [DEADSTAR1] = handleDeadstar,
    [DEADSTAR2] = handleDeadstar,
    -- Flaming Portal (repositioning jump, HM only)
    [FLAMING_PORTAL] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        if not context.isHM then return end
        local now = GetGameTimeMilliseconds() / 1000
        self.numJumps = self.numJumps + 1
        self.nextJump = now + 35
    end,
}

Xalvakka.effectRoutes = {
    -- Soul Resonance: personal purge alert.
    [SOUL_RESONANCE] = function(self, context, alerts, changeType, abilityId,
                                 unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            self.soulStart = GetGameTimeMilliseconds() / 1000
            CA.alert(nil, "Purge Soul Resonance!", 0xFF6600D9, SOUNDS.DUEL_START, 4000)
            PlaySound(SOUNDS.DUEL_START)
        elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
            self.soulStart = 0
        end
    end,
    -- Unstable Charge / Blob: green border while standing on orb.
    [UNSTABLE_CHARGE] = function(self, context, alerts, changeType, abilityId,
                                  unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            self.onBlob = true
            CA.border(true, 8000, "green")
        elseif changeType == EFFECT_RESULT_FADED and AreUnitsEqual("player", unitTag) then
            self.onBlob = false
            CA.border(false, 0, nil)
        end
    end,
    -- Manifold Curse: purple border for self, name tracker for others.
    [MANIFOLD_DEBUFF] = function(self, context, alerts, changeType, abilityId,
                                  unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED then
            if AreUnitsEqual("player", unitTag) then
                self.selfManifold = true
                CA.border(true, 20000, "purple")
                CA.alert(nil, "|cAA44ffManifold Curse|r on YOU — spread!",
                    0xAA44FFD9, SOUNDS.DUEL_START, 5000)
                PlaySound(SOUNDS.DUEL_START)
            elseif IsUnitPlayer(unitTag) then
                self.manifoldOthers[unitTag] =
                    GetUnitDisplayName(unitTag) or unitName or "?"
            end
        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.selfManifold = false
                CA.border(false, 0, nil)
            else
                self.manifoldOthers[unitTag] = nil
            end
        end
    end,
}

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Info 1 (HM): Next jump timer; hidden once numJumps ≥ 4 (pattern established).
local function showJumpLine(self, alerts, now, isHM)
    if isHM and self.nextJump > 0 and self.numJumps < 4 then
        local T = self.nextJump - now
        if T > 0 then
            alerts:showInfo(1,
                "|cffaa40Next Jump|r: " .. string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(1, "|cffaa40Next Jump|r: |cff0000INC|r")
        end
    else
        alerts:showInfo(1, "")
    end
end

-- Info 2: Soul Resonance personal countdown; auto-clears when window expires.
local function showSoulLine(self, alerts, now)
    if self.soulStart > 0 then
        local T = SOUL_WINDOW - (now - self.soulStart)
        if T > 0 then
            alerts:showInfo(2,
                "|cff6600Soul Resonance|r: " .. string.format("%.1f", T) .. "s")
        else
            self.soulStart = 0
            alerts:showInfo(2, "")
        end
    else
        alerts:showInfo(2, "")
    end
end

-- Info 3: Manifold Curse holders (priority) > Volatile Shell shield value.
local function showManifoldLine(self, alerts)
    local hasManifold = self.selfManifold or (next(self.manifoldOthers) ~= nil)
    if hasManifold then
        local parts = {}
        if self.selfManifold then
            parts[#parts + 1] = "|cAA44ffYOU|r"
        end
        for _, name in pairs(self.manifoldOthers) do
            parts[#parts + 1] = "|cAA44ff" .. name .. "|r"
        end
        alerts:showInfo(3, "Manifold: " .. table.concat(parts, ", "))
    elseif self.shellShield > 0 then
        alerts:showInfo(3, "|c75E6DAShield|r: " .. fmtShield(self.shellShield))
    else
        alerts:showInfo(3, "")
    end
end

-- Info 4: Run timer near floor-transition HP thresholds (priority) > Blob indicator.
-- Uses info4, not showAction, to avoid clobbering reactive event alerts.
local function showRunLine(self, alerts, context)
    local hp = context.healthPercent
    if hp and hp > RUN1_BOT and hp <= RUN1_TOP then
        alerts:showInfo(4, "|cffdd00RUN IN|r: " ..
            string.format("%.1f%%", hp - RUN1_BOT))
    elseif hp and hp > RUN2_BOT and hp <= RUN2_TOP then
        alerts:showInfo(4, "|cffdd00RUN IN|r: " ..
            string.format("%.1f%%", hp - RUN2_BOT))
    elseif self.onBlob then
        alerts:showInfo(4, "|c66ff66ON BLOB|r — stand still!")
    else
        alerts:showInfo(4, "")
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Xalvakka:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showJumpLine(self, alerts, now, isHM)
    showSoulLine(self, alerts, now)
    showManifoldLine(self, alerts)
    showRunLine(self, alerts, context)
end

return Xalvakka
