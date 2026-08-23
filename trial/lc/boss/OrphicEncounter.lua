local Location = require("core.Location")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── Ability IDs ───────────────────────────────────────────────────────────
local THUNDER_THRALL  = 214383   -- Xoryn jump — BEGIN → timer 25.5s; 8s from return
local LIGHTNING_FLOOD = 214355   -- Xoryn cone — BEGIN → timer 21.5s; 3s from return
local COLOR_CHANGE    = 213913   -- mirror switch — EFFECT_GAINED → alert
local BREAKOUT        = 220185   -- crystal prison — BEGIN on player → alert
local SHIELD_THROW    = 221945   -- Crystal Sentinel — BEGIN → caAlertCast
local XORYN_IMMUNE_1  = 217987   -- Xoryn jumps away — EFFECT_GAINED → reset
local XORYN_IMMUNE_2  = 219545   -- Xoryn jumps away (variant)

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local THRALL_FIRST_CD =  8.0    -- first Thrall after Xoryn returns
local THRALL_CD       = 25.5   -- steady-state Thrall CD
local FLOOD_FIRST_CD  =  3.0    -- first Flood after Xoryn returns
local FLOOD_CD        = 21.5   -- steady-state Flood CD

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_LIGHTNING = { -3, 0, false, { 0.9, 0.9, 0.1, 0.4 }, { 0.9, 0.9, 0.1, 0.8 } }
local COL_CRYSTAL   = { -3, 0, false, { 0.7, 0.3, 1.0, 0.4 }, { 0.7, 0.3, 1.0, 0.8 } }

local OrphicEncounter = {
    id                = 3,
    key               = "orphic",
    nameAliases       = { "Orphic Shattered Shard" },
    hmHealthThreshold = 80000000,
    location          = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
OrphicEncounter.thunderThrallTimer  = Timer.new(THRALL_CD)
OrphicEncounter.lightningFloodTimer = Timer.new(FLOOD_CD)

-- ── State ─────────────────────────────────────────────────────────────────
OrphicEncounter.xorynActive  = false
OrphicEncounter.firstThrall  = true   -- true until first Thrall after a Xoryn return
OrphicEncounter.firstFlood   = true

function OrphicEncounter:reset()
    self.thunderThrallTimer:clear()
    self.lightningFloodTimer:clear()
    self.xorynActive = false
    self.firstThrall = true
    self.firstFlood  = true
end

function OrphicEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    if result == ACTION_RESULT_BEGIN then
        if abilityId == THUNDER_THRALL then
            self.xorynActive  = true
            self.firstThrall  = false
            self.thunderThrallTimer:reset(THRALL_CD)
            alerts:showAction("Thunder Thrall (Xoryn jump)")

        elseif abilityId == LIGHTNING_FLOOD then
            self.xorynActive = true
            self.firstFlood  = false
            self.lightningFloodTimer:reset(FLOOD_CD)
            local target = (unitName and unitName ~= "") and unitName or "?"
            alerts:showAction("Lightning Flood → " .. target)

        elseif abilityId == BREAKOUT then
            if IsUnitPlayer(unitTag) then
                CA.alertCast(abilityId, "BREAK OUT!", 3000, COL_CRYSTAL)
                alerts:showAction("Break out of the crystal!")
            end

        elseif abilityId == SHIELD_THROW then
            local target = (unitName and unitName ~= "") and unitName or "?"
            local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
            if dur <= 0 then dur = 2000 end
            CA.alertCast(abilityId, "Shield Throw → " .. target, dur, COL_LIGHTNING)
        end

    elseif result == ACTION_RESULT_EFFECT_GAINED then
        if abilityId == COLOR_CHANGE then
            CA.alert(nil, "Color Change!", 0xFFFF44FF, SOUNDS.NONE, 3000)
            alerts:showAction("Color change! Switch mirror!")

        elseif abilityId == XORYN_IMMUNE_1 or abilityId == XORYN_IMMUNE_2 then
            -- Xoryn jumps away — pause timers until it returns
            self.xorynActive = false
            self.thunderThrallTimer:clear()
            self.lightningFloodTimer:clear()
        end

    elseif result == ACTION_RESULT_EFFECT_FADED then
        if abilityId == XORYN_IMMUNE_1 or abilityId == XORYN_IMMUNE_2 then
            -- Xoryn returns — next abilities reset as "first" for accurate CDs
            self.xorynActive = true
            self.firstThrall = true
            self.firstFlood  = true
        end
    end
end

function OrphicEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
end

function OrphicEncounter:onUpdate(context, alerts)
    if self.xorynActive then
        if self.firstThrall then
            alerts:showInfo(1, "Thrall: first ~8s")
        else
            local r = self.thunderThrallTimer:remaining()
            alerts:showInfo(1, "Thrall: " .. (r > 0 and ZO_FormatCountdownTimer(r) or "NOW"))
        end
        if self.firstFlood then
            alerts:showInfo(2, "Flood:  first ~3s")
        else
            local r = self.lightningFloodTimer:remaining()
            alerts:showInfo(2, "Flood:  " .. (r > 0 and ZO_FormatCountdownTimer(r) or "NOW"))
        end
    else
        alerts:showInfo(1, "")
        alerts:showInfo(2, "")
    end
    alerts:showInfo(3, "")
    alerts:showInfo(4, "")
    alerts:showInfo(5, "")
    alerts:showInfo(6, "")
    alerts:showInfo(7, "")
end

return OrphicEncounter
