--- Oaxiltso — Rockgrove boss 1
---
--- Phase RG-2: RockgroveCommon.handle() (trash mechanics) ✓
--- Phase RG-3: Oaxiltso-specific mechanics
---   SavageBlitz  (149414 / 157932 HM): BEGIN → CastAlertsStart 2750 ms; 36 s cycle
---   NoxiousSludge (149190):  BEGIN → Alert; 28 s cycle
---   PoisonedPlayers (157860): EFFECT_GAINED → track 2 players, assign side via
---                             distance to exit-left pool; alert "<< L || R >>"
---   AnnihilatorSunburst (153181): BEGIN → zo_callLater 2500 ms → "Meteor. BLOCK!"
---   CinderCleave (152688): targeted player → AlertCast 2000 ms (hardcoded; QRH note)
---   EmberChains  (152699): targeted player → AlertCast 750 ms, projectile-adjusted
---   AddSpawn     (152365): EFFECT_GAINED → showAction "ADD SPAWNING!"
---   BossEnrage   (152502) / MiniEnrage (152503): EFFECT_GAINED/FADED flags

local RockgroveCommon = require("trial.rg.RockgroveCommon")

-- ── Ability IDs ────────────────────────────────────────────────────────────
local SAVAGE_BLITZ    = 149414
local SAVAGE_BLITZ_HM = 157932   -- fires after boss drops below 50% HP
local NOXIOUS_SLUDGE  = 149190
local SLUDGE_DEBUFF   = 157860   -- debuff placed on two players
local SUNBURST        = 153181   -- Annihilator heavy → meteor block 2.5 s later
local CINDER_CLEAVE   = 152688   -- Annihilator frontal cone
local EMBER_CHAINS    = 152699   -- Annihilator chain to far target
local ADD_SPAWN       = 152365   -- signals Annihilator spawning
local BOSS_ENRAGE     = 152502
local MINI_ENRAGE     = 152503

-- ── Pool reference position (world coords) ────────────────────────────────
-- Exit-left pool — used to assign left/right side to poisoned players.
-- Closer to this point → left cleanse; farther → right cleanse.
local POOL_EX_LEFT = { 91973, 35751, 81764 }

local CA = require("lib.CA")

-- ── CA colour palettes ─────────────────────────────────────────────────────
local COL_BLITZ  = { 0.8, 0.0, 0.0, 0.4 }   -- red fill, no action text (mirrors QRH)
local COL_CONE   = { -2, 0, false, { 1.0, 0.55, 0.0, 0.4 }, { 1.0, 0.55, 0.0, 0.8 } }
local COL_CHAINS = { -3, 0, false, { 0.7, 0.3,  1.0, 0.4 }, { 0.7, 0.3,  1.0, 0.8 } }

-- ── Distance helper (squared, world coords — no sqrt needed for comparison) ─
local function distSq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx*dx + dy*dy + dz*dz
end

-- ── Boss definition ───────────────────────────────────────────────────────
local Oaxiltso = {
    id   = 1,
    key  = "oaxiltso",
    name = "Oaxiltso",   -- TODO: verify exact unit name via GetUnitName("boss1") in-game
}

-- ── State ─────────────────────────────────────────────────────────────────
Oaxiltso.lastBlitz          = 0      -- s: last Savage Blitz cast time
Oaxiltso.lastSludge         = 0      -- s: last Noxious Sludge cast time
Oaxiltso.lastPoisonTracker  = 0      -- s: dedup gate (SLUDGE_DEBUFF fires 3× per cast)
Oaxiltso.sludgeTracker1     = 0      -- unitId   of first poisoned player
Oaxiltso.sludgeTracker1Tag  = nil    -- unitTag  of first poisoned player
Oaxiltso.sludgeTracker1Name = nil    -- display name of first poisoned player
Oaxiltso.bossEnraged        = false
Oaxiltso.miniEnraged        = false

-- ── Lifecycle ─────────────────────────────────────────────────────────────
function Oaxiltso:reset(forced)
    self.lastBlitz          = 0
    self.lastSludge         = 0
    self.lastPoisonTracker  = 0
    self.sludgeTracker1     = 0
    self.sludgeTracker1Tag  = nil
    self.sludgeTracker1Name = nil
    self.bossEnraged        = false
    self.miniEnraged        = false
end

-- ── Combat state ──────────────────────────────────────────────────────────
function Oaxiltso:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.lastBlitz          = 0
        self.lastSludge         = 0
        self.lastPoisonTracker  = 0
        self.sludgeTracker1     = 0
        self.sludgeTracker1Tag  = nil
        self.sludgeTracker1Name = nil
    end
end

-- ── Combat events ─────────────────────────────────────────────────────────
function Oaxiltso:onCombatEvent(context, alerts, result, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    if RockgroveCommon.handle(alerts, result, abilityId, unitTag, sourceUnitName) then
        return
    end

    -- ── Savage Blitz ──────────────────────────────────────────────────────
    if (abilityId == SAVAGE_BLITZ or abilityId == SAVAGE_BLITZ_HM)
       and result == ACTION_RESULT_BEGIN then
        self.lastBlitz = GetGameTimeMilliseconds() / 1000
        CA.castAlertsStart(abilityId, "Savage Blitz", 2750, 2750, COL_BLITZ)
        return
    end

    -- ── Noxious Sludge ────────────────────────────────────────────────────
    if abilityId == NOXIOUS_SLUDGE and result == ACTION_RESULT_BEGIN then
        self.lastSludge = GetGameTimeMilliseconds() / 1000
        CA.alert(nil, "Noxious Sludge", 0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
        return
    end

    -- ── Annihilator Sunburst → delayed Meteor Block alert ─────────────────
    -- Sunburst casts, then ~2.5 s later a meteor hits; alert fires at impact.
    if abilityId == SUNBURST and result == ACTION_RESULT_BEGIN then
        zo_callLater(function()
            CA.alert(nil, "Meteor. BLOCK!", 0xFF2020FF, SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
        end, 2500)
        return
    end

    -- ── Annihilator CinderCleave (frontal cone, player-targeted) ──────────
    -- QRH: hitValue returns ~4 s but actual dodge window is ~2 s; hardcode 2000.
    if abilityId == CINDER_CLEAVE and result == ACTION_RESULT_BEGIN then
        if not IsUnitPlayer(unitTag) then return end
        alerts:showAction("Dodge! (Cone)")
        CA.alertCast(abilityId, sourceUnitName, 2000, COL_CONE)
        return
    end

    -- ── Annihilator EmberChains (projectile chain, player-targeted) ────────
    if abilityId == EMBER_CHAINS and result == ACTION_RESULT_BEGIN then
        if not IsUnitPlayer(unitTag) then return end
        CA.alertCast(abilityId, sourceUnitName, 750, COL_CHAINS)
        return
    end

    -- ── MeteorCrash: Annihilator add spawning ─────────────────────────────
    if abilityId == ADD_SPAWN and result == ACTION_RESULT_EFFECT_GAINED then
        alerts:showAction("ADD SPAWNING!")
        return
    end
end

-- ── Effect changes ────────────────────────────────────────────────────────
function Oaxiltso:onEffectChanged(context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName)
    -- ── Sludge debuff: track two players and assign left/right sides ───────
    if abilityId == SLUDGE_DEBUFF and changeType == EFFECT_RESULT_GAINED then
        local now = GetGameTimeMilliseconds() / 1000

        if self.sludgeTracker1 == 0 then
            -- Slot 1 empty — accept if outside the 10 s dedup window.
            -- (The event fires 3× when the local player is poisoned; this
            -- collapses all three into a single registration.)
            if now - self.lastPoisonTracker > 10 then
                self.lastPoisonTracker  = now
                self.sludgeTracker1     = unitId
                self.sludgeTracker1Tag  = unitTag
                self.sludgeTracker1Name = GetUnitDisplayName(unitTag) or unitName or "?"
            end

        elseif unitId ~= self.sludgeTracker1 then
            -- Slot 1 filled, different player arrived → compute sides.
            local name1 = self.sludgeTracker1Name
            local name2 = GetUnitDisplayName(unitTag) or unitName or "?"

            local _, x1, y1, z1 = GetUnitWorldPosition(self.sludgeTracker1Tag)
            local _, x2, y2, z2 = GetUnitWorldPosition(unitTag)

            -- Whichever player is closer to the exit-left pool goes left.
            local d1 = (x1 ~= nil) and distSq(x1, y1, z1,
                POOL_EX_LEFT[1], POOL_EX_LEFT[2], POOL_EX_LEFT[3]) or math.huge
            local d2 = (x2 ~= nil) and distSq(x2, y2, z2,
                POOL_EX_LEFT[1], POOL_EX_LEFT[2], POOL_EX_LEFT[3]) or math.huge

            local leftName, rightName
            if d1 <= d2 then
                leftName, rightName = name1, name2
            else
                leftName, rightName = name2, name1
            end

            CA.alert(nil,
                "<< " .. leftName .. " << || >> " .. rightName .. " >>",
                0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 5000)

            -- Clear slots for the next cast.
            self.sludgeTracker1     = 0
            self.sludgeTracker1Tag  = nil
            self.sludgeTracker1Name = nil
        end
        return
    end

    -- ── Boss enrage ───────────────────────────────────────────────────────
    if abilityId == BOSS_ENRAGE then
        self.bossEnraged = (changeType == EFFECT_RESULT_GAINED)
        return
    end

    -- ── Add enrage ────────────────────────────────────────────────────────
    if abilityId == MINI_ENRAGE then
        self.miniEnraged = (changeType == EFFECT_RESULT_GAINED)
        return
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Oaxiltso:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000

    -- ── Info 1: Next Savage Blitz (36 s cycle) ─────────────────────────────
    if self.lastBlitz > 0 then
        local T = 36 - (now - self.lastBlitz)
        if T > 0 then
            alerts:showInfo(1, "|cff6030Next Blitz|r: " .. string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(1, "|cff6030Next Blitz|r: |cff0000INC|r")
        end
    else
        alerts:showInfo(1, "")
    end

    -- ── Info 2: Next Noxious Sludge (28 s cycle) ───────────────────────────
    if self.lastSludge > 0 then
        local T = 28 - (now - self.lastSludge)
        if T > 0 then
            alerts:showInfo(2, "|c50c050Next Sludge|r: " .. string.format("%.0f", T) .. "s")
        else
            alerts:showInfo(2, "|c50c050Next Sludge|r: |cff0000INC|r")
        end
    else
        alerts:showInfo(2, "")
    end

    -- ── Info 3: Enrage state ───────────────────────────────────────────────
    if self.bossEnraged and self.miniEnraged then
        alerts:showInfo(3, "|cff2020BOSS + ADD ENRAGED|r")
    elseif self.bossEnraged then
        alerts:showInfo(3, "|cff2020BOSS ENRAGED|r")
    elseif self.miniEnraged then
        alerts:showInfo(3, "|cff6020ADD ENRAGED|r")
    else
        alerts:showInfo(3, "")
    end

    alerts:showInfo(4, "")
end

return Oaxiltso
