--- SunspireCommon — mechanics shared across all three Sunspire boss arenas.
---
--- These abilities appear regardless of which boss (Lokke/Yolna/Nahvii) is
--- active: boss heavy attacks, cat and 2H-add interrupts, shield charge,
--- dragon breaths, and fire spit.
---
--- Each boss's onCombatEvent calls SunspireCommon.handle() first, then
--- continues into its own mechanic handlers.
---
--- hitValue unavailability note (old API → modern):
---   HTS used hitValue for cast-duration timers.  Modern API lacks it; we use
---   GetAbilityCastInfo(abilityId) with a per-ability fallback constant instead.

local SunspireCommon = {}

-- ── CombatAlerts helpers ───────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end

-- ── Ability ID sets ────────────────────────────────────────────────────────
-- Heavy Attacks: all bosses + shared adds (iron servant, 1H&Shield add, cone)
local HA_IDS = {
    [115723] = true,   -- Lokkestiiz HA
    [123026] = true,   -- Lokkestiiz Wing Thrash
    [122124] = true,   -- Yolnahkriin HA
    [121833] = true,   -- Yolnahkriin Wing Thrash
    [121849] = true,   -- Yolnahkriin Wing Thrash (alt)
    [115443] = true,   -- Nahviintaas HA
    [119796] = true,   -- Nahviintaas Wing Thrash
    [121422] = true,   -- Cone-portal HA
    [117071] = true,   -- 1H & Shield add HA
    [119817] = true,   -- Iron Servant Anvil Cracker
}

-- Cat (Senche) jump attacks — all three arenas
local BLOCK_IDS = {
    [120890] = true,   -- red cat jump
    [122012] = true,   -- white cat jump
}

-- Dragonbreath types across all three bosses
local BREATH_IDS = {
    [119283] = true,   -- Frost Breath  (Lokke)
    [121723] = true,   -- Fire Breath   (Yolna)
    [121980] = true,   -- Searing Breath (Nahvii)
}

-- Fire Spit → incoming atronach; value = post-cast travel offset in ms
local SPIT_IDS = {
    [118860] = 900,    -- spit during Lokke/Yolna phases
    [115592] = 700,    -- spit during Nahvii phase
}

local SHIELD_CHARGE = 117075   -- 1H & Shield add charge
local LEAP          = 116836   -- 2H add leap

-- ── Fallback cast durations (ms) ──────────────────────────────────────────
-- Used when GetAbilityCastInfo returns 0 (instant / unknown).
local HA_FALLBACK     = 1400
local BLOCK_FALLBACK  =  800   -- cat / 2H-add jump travel
local BREATH_FALLBACK = 3000
local SPIT_FALLBACK   = 1200
local CHARGE_FALLBACK = 1200

-- ── CA bar colour palette ─────────────────────────────────────────────────
-- { dodgeTiming, dodgeText, bool, fillColor, actionColor }
local COL_HA     = { -2, 0, false, { 1.0, 0.35, 0.0, 0.4 }, { 1.0, 0.35, 0.0, 0.8 } }
local COL_BLOCK  = { -2, 0, false, { 0.9, 0.85, 0.0, 0.4 }, { 0.9, 0.85, 0.0, 0.8 } }
local COL_BREATH = { -3, 0, false, { 0.3, 0.75, 1.0, 0.4 }, { 0.3, 0.75, 1.0, 0.8 } }
local COL_SPIT   = { -3, 0, false, { 1.0, 0.50, 0.0, 0.4 }, { 1.0, 0.50, 0.0, 0.8 } }
local COL_CHARGE = { -2, 0, false, { 0.2, 0.60, 1.0, 0.4 }, { 0.2, 0.60, 1.0, 0.8 } }

-- ── Public handler ─────────────────────────────────────────────────────────
-- Call from each boss's onCombatEvent before boss-specific logic.
-- Returns true if the event was handled so the caller can skip further checks
-- for the same abilityId; returns false otherwise.
function SunspireCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName)
    if result ~= ACTION_RESULT_BEGIN then return false end

    -- ── Heavy Attack (player-targeted) ─────────────────────────────────
    if HA_IDS[abilityId] then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = HA_FALLBACK end
        alerts:showAction("Block! (Heavy Attack)")
        caAlertCast(abilityId, sourceUnitName, dur, COL_HA)
        return true
    end

    -- ── Cat jump (Block) ──────────────────────────────────────────────
    -- HTS delayed the alert by hitValue (jump travel time).  Without that value
    -- we show immediately; the CA bar covers the remaining travel window.
    if BLOCK_IDS[abilityId] then
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = BLOCK_FALLBACK end
        alerts:showAction("Block! (Jump)")
        caAlertCast(abilityId, sourceUnitName, dur, COL_BLOCK)
        return true
    end

    -- ── 2H add Leap (Dodge) ───────────────────────────────────────────
    if abilityId == LEAP then
        local dur = select(1, GetAbilityCastInfo(LEAP)) or 0
        if dur <= 0 then dur = BLOCK_FALLBACK end
        alerts:showAction("Dodge! (Leap)")
        caAlertCast(abilityId, sourceUnitName, dur, COL_BLOCK)
        return true
    end

    -- ── Shield Charge (player-targeted) ──────────────────────────────
    if abilityId == SHIELD_CHARGE then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = select(1, GetAbilityCastInfo(SHIELD_CHARGE)) or 0
        if dur <= 0 then dur = CHARGE_FALLBACK end
        alerts:showAction("Block! (Shield Charge)")
        caAlertCast(abilityId, sourceUnitName, dur, COL_CHARGE)
        return true
    end

    -- ── Dragon Breath (player-targeted) ──────────────────────────────
    if BREATH_IDS[abilityId] then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = BREATH_FALLBACK end
        alerts:showAction("Dodge! (Breath)")
        caAlertCast(abilityId, sourceUnitName, dur, COL_BREATH)
        return true
    end

    -- ── Fire Spit → atronach incoming (player-targeted) ──────────────
    -- HTS added a post-cast travel offset (+900 ms / +700 ms) to hitValue.
    -- We replicate that by extending the CA bar beyond the cast time.
    local spitOffset = SPIT_IDS[abilityId]
    if spitOffset then
        if not IsUnitPlayer(unitTag) then return false end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = SPIT_FALLBACK end
        alerts:showAction("Atro incoming! (Spit)")
        caAlertCast(abilityId, sourceUnitName, dur + spitOffset, COL_SPIT)
        return true
    end

    return false
end

return SunspireCommon
