--- RockgroveCommon — trash-add mechanics shared across all three Rockgrove arenas.
---
--- Nine add abilities appear regardless of which boss is active.
--- Each boss's onCombatEvent calls RockgroveCommon.handle() first, then
--- returns early if it was handled — identical pattern to SunspireCommon.
---
--- Returns true if the event was consumed (caller should return).

local RockgroveCommon = {}

-- ── CombatAlerts helpers ───────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...)       end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)            end end
local function caCastAlertsStart(...) if CombatAlerts then return CombatAlerts.CastAlertsStart(...) end end

-- ── Ability IDs ────────────────────────────────────────────────────────────
local EARTHQUAKE   = 149535   -- Reaver: AoE ground DoT on floor
local SUNDERING    = 149524   -- Reaver: heavy melee on tank
local TAKING_AIM   = 152496   -- Bloodseeker: channeled multi-target ranged
local QUICK_STRIKE = 149313   -- Butcher: targeted melee
local SCALDING     = 153175   -- Fire Behemoth (trash + Bahsei arena): targeted DoT
local PRIME_METEOR = 152414   -- Torchcaster: summons Prime Meteor (10 s to kill)
local MOLTEN_RAIN  = 157482   -- Ash Titan: fire rain to kite

local ASTRAL_SHIELD_IDS = { [149089] = true, [157466] = true }   -- Soulweaver
local ASSAULT_IDS       = { [149268] = true, [149261] = true }   -- Barbarian Hasted Assault

-- ── Fallback cast durations (ms) ──────────────────────────────────────────
local FALL_MELEE    = 1500
local FALL_MOLTEN   = 3000
local FALL_ASSAULT  = 1500

-- ── Barbarian Hasted Assault: dodge window length ─────────────────────────
local DODGE_DUR = GetAbilityDuration(28549) or 0
if DODGE_DUR <= 0 then DODGE_DUR = 650 end

-- ── CA colour palettes ─────────────────────────────────────────────────────
local COL_MELEE    = { -2, 0, false, { 1.0, 0.35, 0.0, 0.4 }, { 1.0, 0.35, 0.0, 0.8 } }
local COL_TANK_INT = { -2, 0, true,  { 0.3, 0.60, 1.0, 0.4 }, { 0.3, 0.60, 1.0, 0.8 } }
local COL_DOT      = { -2, 0, false, { 1.0, 0.10, 0.1, 0.4 }, { 1.0, 0.10, 0.1, 0.8 } }
local COL_FIRE     = { -2, 0, false, { 1.0, 0.50, 0.0, 0.4 }, { 1.0, 0.50, 0.0, 0.8 } }
local COL_ASSAULT  = { 1.0, 0.70, 0.0, 0.5 }
local ACT_ASSAULT  = { DODGE_DUR, "Hold Block!", 0.8, 0.0, 0.0, 0.9, nil }
local ACT_METEOR   = { 10000,     "KILL SUN!",   0.8, 0.0, 0.0, 0.9, nil }

-- ── Public handler ─────────────────────────────────────────────────────────
-- Call at the top of each boss's onCombatEvent.
-- result, abilityId, unitTag, sourceUnitName come straight from the dispatch.
function RockgroveCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName)
    if result ~= ACTION_RESULT_BEGIN then return false end

    -- ── Reaver: Earthquake ────────────────────────────────────────────────
    if abilityId == EARTHQUAKE then
        caAlert(nil, "Earthquake", 0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
        return true
    end

    -- ── Reaver: Sundering (targeted heavy — player only) ─────────────────
    if abilityId == SUNDERING then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = select(1, GetAbilityCastInfo(SUNDERING)) or 0
        if dur <= 0 then dur = FALL_MELEE end
        alerts:showAction("Block! (Sundering)")
        caAlertCast(abilityId, sourceUnitName, dur, COL_MELEE)
        PlaySound(SOUNDS.DUEL_START)
        return true
    end

    -- ── Bloodseeker: Taking Aim (tanks only — multi-target, noisy for DDs) ─
    if abilityId == TAKING_AIM then
        local _, _, isTank = GetPlayerRoles()
        if isTank then
            local dur = select(1, GetAbilityCastInfo(TAKING_AIM)) or 0
            if dur <= 0 then dur = FALL_MELEE end
            caAlertCast(abilityId, sourceUnitName, dur, COL_TANK_INT)
            PlaySound(SOUNDS.DUEL_START)
        end
        return true     -- consume for everyone; QRH notes it's too verbose for DDs
    end

    -- ── Soulweaver: Astral Shield / Remnant ──────────────────────────────
    if ASTRAL_SHIELD_IDS[abilityId] then
        caAlert(nil, "Astral Shield", 0x75E6DAD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
        return true
    end

    -- ── Butcher: Quick Strike (targeted heavy — player only) ─────────────
    if abilityId == QUICK_STRIKE then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = select(1, GetAbilityCastInfo(QUICK_STRIKE)) or 0
        if dur <= 0 then dur = FALL_MELEE end
        caAlertCast(abilityId, sourceUnitName, dur, COL_MELEE)
        return true
    end

    -- ── Fire Behemoth: Scalding (targeted DoT — player only) ─────────────
    -- Same ability ID appears on Bahsei's Fire Behemoth add — handled here.
    if abilityId == SCALDING then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = select(1, GetAbilityCastInfo(SCALDING)) or 0
        if dur <= 0 then dur = FALL_MELEE end
        alerts:showAction("Dodge! (Scalding)")
        caAlertCast(abilityId, sourceUnitName, dur, COL_DOT)
        caAlert(nil, "Scalding", 0xCC0000D9, SOUNDS.DUEL_START, 9000)
        PlaySound(SOUNDS.DUEL_START)
        return true
    end

    -- ── Barbarian: Hasted Assault (group jump — block window) ────────────
    if ASSAULT_IDS[abilityId] then
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = FALL_ASSAULT end
        caCastAlertsStart(abilityId, "Hasted Assault (Barbarian)",
            dur, 4000, COL_ASSAULT, ACT_ASSAULT)
        PlaySound(SOUNDS.DUEL_START)
        return true
    end

    -- ── Torchcaster: Prime Meteor (10 s to kill or wipe) ─────────────────
    if abilityId == PRIME_METEOR then
        caCastAlertsStart(abilityId, "Prime Meteor",
            13500, 13500, COL_ASSAULT, ACT_METEOR)
        PlaySound(SOUNDS.DUEL_START)
        return true
    end

    -- ── Ash Titan: Molten Rain (kite — no dodge text, just bar) ──────────
    if abilityId == MOLTEN_RAIN then
        local dur = select(1, GetAbilityCastInfo(MOLTEN_RAIN)) or 0
        if dur <= 0 then dur = FALL_MOLTEN end
        caAlertCast(abilityId, sourceUnitName, dur, COL_FIRE)
        return true
    end

    return false
end

return RockgroveCommon
