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
local Oaxiltso = {}
Oaxiltso.__index = Oaxiltso

Oaxiltso.key  = "oaxiltso"
Oaxiltso.name = "Oaxiltso"   -- TODO: verify exact unit name via GetUnitName("boss1") in-game

function Oaxiltso.new()
    return setmetatable({
        lastBlitz          = 0,     -- s: last Savage Blitz cast time
        lastSludge         = 0,     -- s: last Noxious Sludge cast time
        lastPoisonTracker  = 0,     -- s: dedup gate (SLUDGE_DEBUFF fires 3× per cast)
        sludgeTracker1     = 0,     -- unitId   of first poisoned player
        sludgeTracker1Tag  = nil,   -- unitTag  of first poisoned player
        sludgeTracker1Name = nil,   -- display name of first poisoned player
        bossEnraged        = false,
        miniEnraged        = false,
    }, Oaxiltso)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- Shared trash mechanic handler (interrupt, execute, HA, etc.).
Oaxiltso.common = RockgroveCommon

local function handleSavageBlitz(self, context, alerts, abilityId, ...)
    self.lastBlitz = GetGameTimeMilliseconds() / 1000
    CA.castAlertsStart(abilityId, "Savage Blitz", 2750, 2750, COL_BLITZ)
end

Oaxiltso.combatRoutes = {
    [SAVAGE_BLITZ]    = { result = ACTION_RESULT_BEGIN, fn = handleSavageBlitz },
    [SAVAGE_BLITZ_HM] = { result = ACTION_RESULT_BEGIN, fn = handleSavageBlitz },
    [NOXIOUS_SLUDGE] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        self.lastSludge = GetGameTimeMilliseconds() / 1000
        CA.alert(nil, "Noxious Sludge", 0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
    end },
    -- Sunburst casts, then ~2.5 s later a meteor hits; alert fires at impact.
    [SUNBURST] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId, ...)
        zo_callLater(function()
            CA.alert(nil, "Meteor. BLOCK!", 0xFF2020FF, SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
        end, 2500)
    end },
    -- QRH: hitValue returns ~4 s but actual dodge window is ~2 s; hardcode 2000.
    [CINDER_CLEAVE] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId,
                      unitTag, sourceUnitTag, sourceUnitId, unitId,
                      sourceUnitName, unitName)
        if not IsUnitPlayer(unitTag) then return end
        alerts:showAction("Dodge! (Cone)")
        CA.alertCast(abilityId, sourceUnitName, 2000, COL_CONE)
    end },
    [EMBER_CHAINS] = { result = ACTION_RESULT_BEGIN,
        fn = function(self, context, alerts, abilityId,
                      unitTag, sourceUnitTag, sourceUnitId, unitId,
                      sourceUnitName, unitName)
        if not IsUnitPlayer(unitTag) then return end
        CA.alertCast(abilityId, sourceUnitName, 750, COL_CHAINS)
    end },
    [ADD_SPAWN] = { result = ACTION_RESULT_EFFECT_GAINED,
        fn = function(self, context, alerts, abilityId, ...)
        alerts:showAction("ADD SPAWNING!")
    end },
}

-- Track first poisoned player; alert with left/right side assignment when pair is complete.
-- The EFFECT_RESULT_GAINED event fires up to 3× per cast when the local player is hit,
-- so a 10 s dedup gate collapses those duplicates into a single slot-1 registration.
local function handleSludgeDebuff(self, context, alerts, abilityId,
                                   unitTag, unitId, unitName, stackCount)
    local now = GetGameTimeMilliseconds() / 1000

    if self.sludgeTracker1 == 0 then
        if now - self.lastPoisonTracker > 10 then
            self.lastPoisonTracker  = now
            self.sludgeTracker1     = unitId
            self.sludgeTracker1Tag  = unitTag
            self.sludgeTracker1Name = GetUnitDisplayName(unitTag) or unitName or "?"
        end

    elseif unitId ~= self.sludgeTracker1 then
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

        self.sludgeTracker1     = 0
        self.sludgeTracker1Tag  = nil
        self.sludgeTracker1Name = nil
    end
end

Oaxiltso.effectRoutes = {
    [SLUDGE_DEBUFF] = { changeType = EFFECT_RESULT_GAINED, fn = handleSludgeDebuff },
    [BOSS_ENRAGE] = function(self, context, alerts, changeType, abilityId, ...)
        self.bossEnraged = (changeType == EFFECT_RESULT_GAINED)
    end,
    [MINI_ENRAGE] = function(self, context, alerts, changeType, abilityId, ...)
        self.miniEnraged = (changeType == EFFECT_RESULT_GAINED)
    end,
}

-- ── Info-line renderers ───────────────────────────────────────────────────

-- Info 1: Next Savage Blitz (36 s cycle).
local function showBlitzLine(self, alerts, now)
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
end

-- Info 2: Next Noxious Sludge (28 s cycle).
local function showSludgeLine(self, alerts, now)
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
end

-- Info 3: Enrage state — boss enraged, add enraged, or both.
local function showEnrageLine(self, alerts)
    if self.bossEnraged and self.miniEnraged then
        alerts:showInfo(3, "|cff2020BOSS + ADD ENRAGED|r")
    elseif self.bossEnraged then
        alerts:showInfo(3, "|cff2020BOSS ENRAGED|r")
    elseif self.miniEnraged then
        alerts:showInfo(3, "|cff6020ADD ENRAGED|r")
    else
        alerts:showInfo(3, "")
    end
end

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Oaxiltso:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showBlitzLine(self, alerts, now)
    showSludgeLine(self, alerts, now)
    showEnrageLine(self, alerts)
    alerts:showInfo(4, "")
end

return Oaxiltso
