--- Yolnahkriin — Sunspire boss 2 (Fire)
---
--- Phase SS-2: Cross-trial alerts via SunspireCommon
--- Phase SS-4: Yolna-specific mechanics
---   AtroSpawn (119549): BEGIN → "Kill Atro!" banner, 4.5 s
---   LavaGeyser (124546): player or nearby group (dist < 2.8) → Dodge! bar
---   NextFlare (121722 / 121459): fight-start +6s / BEGIN +32s / EFFECT_FADED +30s
---   Cataclysm (122598): cast duration CA bar + landing = cataEnd + 6.8 s
---   Boss HP thresholds: 76% / 51% / 26% → "Can Fly In X%"

local SunspireCommon = require("trial.ss.SunspireCommon")

-- ── Ability IDs ────────────────────────────────────────────────────────────
local ATRO_SPAWN    = 119549   -- Yolna summons fire atronarchs
local LAVA_GEYSER   = 124546   -- ground-targeted + player proximity
local NEXT_FLARE_A  = 121722   -- BEGIN → +32 s to next flare
local NEXT_FLARE_B  = 121459   -- EFFECT_FADED → +30 s to next flare
local CATACLYSM     = 122598   -- fire channel while airborne

local CA = require("lib.CA")

-- ── CA colour palettes ─────────────────────────────────────────────────────
local COL_GEYSER = { -2, 0, false, { 1.0, 0.4, 0.0, 0.4 }, { 1.0, 0.4, 0.0, 0.8 } }

-- ── Boss definition ───────────────────────────────────────────────────────
local Yolna = {}
Yolna.__index = Yolna

Yolna.key  = "yolna"
Yolna.name = "Yolnahkriin"

function Yolna.new()
    return setmetatable({
        alertList     = {},   -- [sourceUnitId] → CA bar ID (currently unused; kept for consistency)
        nextFlareTime = 0,    -- s: absolute time when next flare is due
        cataEndTime   = 0,    -- ms: absolute time when cataclysm channel ends
        landingTime   = 0,    -- s: absolute time when boss lands
        cataBarId     = nil,  -- CA CastAlertsStart bar ID
    }, Yolna)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Yolna:onLeave(context)
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    CA.castAlertsStop(self.cataBarId)
end

-- ── Combat state (fight start / wipe) ─────────────────────────────────────
-- Called when EVENT_PLAYER_COMBAT_STATE changes.
-- On fight start (inCombat=true) set the first NextFlare at +6 s (HTS empirical).
function Yolna:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 6
    end
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- Shared cross-trial mechanic handler.
Yolna.common = SunspireCommon

-- DIED: clean up any tracked CA bars.
function Yolna:onDied(context, alerts,
                       unitTag, sourceUnitTag, sourceUnitId, unitId,
                       sourceUnitName, unitName)
    if unitId then CA.castAlertsStop(self.alertList[unitId]); self.alertList[unitId] = nil end
end

Yolna.combatRoutes = {
    [ATRO_SPAWN] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        alerts:showAction("Kill Atro!")
        CA.alert(nil, "Kill Atro!", 0xFF8000FF, SOUNDS.NONE, 4500)
    end,
    [LAVA_GEYSER] = function(self, context, alerts, result, abilityId,
                              unitTag, sourceUnitTag, sourceUnitId, unitId,
                              sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        local show = false
        if IsUnitPlayer(unitTag) then
            if AreUnitsEqual("player", unitTag) then
                show = true
            else
                -- group member — show if within 2.8 map units
                SetMapToPlayerLocation()
                local x1, y1 = GetMapPlayerPosition("player")
                local x2, y2 = GetMapPlayerPosition(unitTag)
                if x2 and y2 and math.sqrt((x1-x2)^2 + (y1-y2)^2) * 1000 < 2.8 then
                    show = true
                end
            end
        end
        if show then
            alerts:showAction("Dodge! (Geyser)")
            local dur = select(1, GetAbilityCastInfo(LAVA_GEYSER)) or 0
            if dur <= 0 then dur = 2500 end
            CA.alertCast(abilityId, sourceUnitName, dur, COL_GEYSER)
        end
    end,
    -- NextFlare: BEGIN → +32 s; EFFECT_FADED → +30 s.
    [NEXT_FLARE_A] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 32
    end,
    [NEXT_FLARE_B] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_EFFECT_FADED then return end
        self.nextFlareTime = GetGameTimeMilliseconds() / 1000 + 30
    end,
    [CATACLYSM] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        local now_ms = GetGameTimeMilliseconds()
        local dur = select(1, GetAbilityCastInfo(CATACLYSM)) or 0
        if dur <= 0 then dur = 4600 end   -- empirical fallback (~4.6 s)
        self.cataEndTime = now_ms + dur
        self.landingTime = (self.cataEndTime / 1000) + 6.8
        CA.castAlertsStop(self.cataBarId)
        self.cataBarId = CA.castAlertsStart(
            abilityId, "Cataclysm",
            dur, dur,
            { 0.9, 0.2, 0.1, 0.5 },
            { dur, "Cata Ends!", 0.9, 0.2, 0.1, 0.9, SOUNDS.NONE })
    end,
}

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Yolna:onUpdate(context, alerts)
    local now_ms = GetGameTimeMilliseconds()
    local now    = now_ms / 1000

    -- ── Info 1: NextFlare countdown ─────────────────────────────────────
    if self.nextFlareTime > 0 then
        local T = self.nextFlareTime - now
        if T > 0 then
            alerts:showInfo(1, "|ce51919Next Flare|r: " .. string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(1, "|ce51919Next Flare|r: |cff0000INC|r")
        end
    else
        alerts:showInfo(1, "")
    end

    -- ── Info 2: Cataclysm channel countdown ─────────────────────────────
    local cataLeft = self.cataEndTime - now_ms
    if cataLeft > 0 then
        alerts:showInfo(2, "|ce51919Cataclysm Ends|r: " ..
            string.format("%.1f", cataLeft / 1000) .. "s")
    else
        alerts:showInfo(2, "")
    end

    alerts:showInfo(3, "")

    -- ── Info 4: Landing → HP "can fly" ──────────────────────────────────
    local landing = self.landingTime - now
    if landing > 0 then
        alerts:showInfo(4, "|c5cd65cLanding|r: " .. string.format("%.0f", landing) .. "s")
    else
        local hp = context.healthPercent
        if hp and hp > 25 then
            local flyAt
            if     hp >= 76 then flyAt = 76
            elseif hp >= 51 then flyAt = 51
            elseif hp >= 26 then flyAt = 26
            end
            if flyAt and (hp - flyAt) <= 5 then
                alerts:showInfo(4, "|cffa500Can Fly In|r: " ..
                    string.format("%.1f", hp - flyAt) .. "%")
            else
                alerts:showInfo(4, "")
            end
        else
            alerts:showInfo(4, "")
        end
    end
end

return Yolna
