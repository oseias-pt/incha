--- Oaxiltso  -  Rockgrove boss 1

local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local RockgroveCommon = require("trial.rg.RockgroveCommon")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local Colors          = require("core.Colors")

-- -- Ability IDs ------------------------------------------------------------
local SAVAGE_BLITZ    = 149414
local SAVAGE_BLITZ_HM = 157932
local NOXIOUS_SLUDGE  = 149190
local SLUDGE_DEBUFF   = 157860
local SUNBURST        = 153181
local CINDER_CLEAVE   = 152688
local EMBER_CHAINS    = 152699
local ADD_SPAWN       = 152365
local BOSS_ENRAGE     = 152502
local MINI_ENRAGE     = 152503

-- Pool reference position (world coords)
local POOL_EX_LEFT = { 91973, 35751, 81764 }

local function distSq(x1, y1, z1, x2, y2, z2)
    local dx, dy, dz = x1 - x2, y1 - y2, z1 - z2
    return dx*dx + dy*dy + dz*dz
end

local Oaxiltso = {}
Oaxiltso.__index = Oaxiltso

Oaxiltso.key               = "oaxiltso"
Oaxiltso.name              = "Oaxiltso"
Oaxiltso.hmHealthThreshold = math.huge

Oaxiltso.stateSchema = {
    lastBlitz          = 0,
    lastSludge         = 0,
    lastPoisonTracker  = 0,
    sludgeTracker1     = 0,
    sludgeTracker1Tag  = false,
    sludgeTracker1Name = false,
    bossEnraged        = false,
    miniEnraged        = false,
    sunburstTimer      = false,
}

function Oaxiltso.new()
    return BossBase.fromSchema(Oaxiltso)
end

function Oaxiltso:onLeave(context)
    self:cancelAfter(self.sunburstTimer)
    self.sunburstTimer = false
end

function Oaxiltso:onWipe(context, alerts)
    self:cancelAfter(self.sunburstTimer)
    self.sunburstTimer      = false
    self.lastBlitz          = 0
    self.lastSludge         = 0
    self.lastPoisonTracker  = 0
    self.sludgeTracker1     = 0
    self.sludgeTracker1Tag  = false
    self.sludgeTracker1Name = false
    self.bossEnraged        = false
    self.miniEnraged        = false
end

-- -- Handlers ---------------------------------------------------------------

local function handleSavageBlitz(boss, ctx, alerts, abilityId, ...)
    boss.lastBlitz = GetGameTimeMilliseconds() / 1000
    CA.bar(abilityId, "Savage Blitz", 2750, 2750, Colors.RED, 0.4)
end

local function handleNoxiousSludge(boss, ctx, alerts, abilityId, ...)
    boss.lastSludge = GetGameTimeMilliseconds() / 1000
    CA.alert(nil, "Noxious Sludge", 0x00CC00D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

local function handleSunburst(boss, ctx, alerts, abilityId, ...)
    boss:cancelAfter(boss.sunburstTimer)
    boss.sunburstTimer = boss:after(2500, function()
        boss.sunburstTimer = false
        if not IsUnitInCombat("player") then return end
        CA.alert(nil, "Meteor. BLOCK!", 0xFF2020FF, SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
    end)
end

-- QRH: hitValue returns ~4 s but actual dodge window is ~2 s; hardcode 2000.
local function handleCinderCleave(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("rg_oaxiltso_dodge_cone"))
    CA.melee(abilityId, sourceUnitName, 2000, Colors.ORANGE)
end

local function handleEmberChains(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    if not IsUnitPlayer(unitTag) then return end
    CA.ranged(abilityId, sourceUnitName, 750, Colors.PURPLE)
end

local function handleAddSpawn(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("rg_oaxiltso_add_spawning"))
end

-- Track first poisoned player; alert with left/right side assignment when pair is complete.
-- The EFFECT_RESULT_GAINED event fires up to 3x per cast when the local player is hit,
-- so a 10 s dedup gate collapses those duplicates into a single slot-1 registration.
local function handleSludgeDebuff(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    local now = GetGameTimeMilliseconds() / 1000

    if boss.sludgeTracker1 == 0 then
        if now - boss.lastPoisonTracker > 10 then
            boss.lastPoisonTracker  = now
            boss.sludgeTracker1     = unitId
            boss.sludgeTracker1Tag  = unitTag
            boss.sludgeTracker1Name = GetUnitDisplayName(unitTag) or unitName or "?"
        end

    elseif unitId ~= boss.sludgeTracker1 then
        local name1 = boss.sludgeTracker1Name
        local name2 = GetUnitDisplayName(unitTag) or unitName or "?"

        local _, x1, y1, z1 = GetUnitWorldPosition(boss.sludgeTracker1Tag)
        local _, x2, y2, z2 = GetUnitWorldPosition(unitTag)

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

        boss.sludgeTracker1     = 0
        boss.sludgeTracker1Tag  = nil
        boss.sludgeTracker1Name = nil
    end
end

local function handleBossEnrageGained(boss, ctx, alerts, abilityId, ...)
    boss.bossEnraged = true
end

local function handleBossEnrageFaded(boss, ctx, alerts, abilityId, ...)
    boss.bossEnraged = false
end

local function handleMiniEnrageGained(boss, ctx, alerts, abilityId, ...)
    boss.miniEnraged = true
end

local function handleMiniEnrageFaded(boss, ctx, alerts, abilityId, ...)
    boss.miniEnraged = false
end

-- -- Event tables ------------------------------------------------------------

local _beginCastEntry = {}
for k, v in pairs(RockgroveCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[SAVAGE_BLITZ]    = { type = AlertTypes.CUSTOM, fn = handleSavageBlitz }
_beginCastEntry[SAVAGE_BLITZ_HM] = { type = AlertTypes.CUSTOM, fn = handleSavageBlitz }
_beginCastEntry[NOXIOUS_SLUDGE]  = { type = AlertTypes.CUSTOM, fn = handleNoxiousSludge }
_beginCastEntry[SUNBURST]        = { type = AlertTypes.CUSTOM, fn = handleSunburst }
_beginCastEntry[CINDER_CLEAVE]   = { type = AlertTypes.CUSTOM, fn = handleCinderCleave }
_beginCastEntry[EMBER_CHAINS]    = { type = AlertTypes.CUSTOM, fn = handleEmberChains }

local _combatOtherEntry = {
    [ADD_SPAWN] = { type = AlertTypes.CUSTOM, fn = handleAddSpawn },
}

local _effectGainedEntry = {}
_effectGainedEntry[SLUDGE_DEBUFF] = { type = AlertTypes.CUSTOM, fn = handleSludgeDebuff }
_effectGainedEntry[BOSS_ENRAGE]   = { type = AlertTypes.CUSTOM, fn = handleBossEnrageGained }
_effectGainedEntry[MINI_ENRAGE]   = { type = AlertTypes.CUSTOM, fn = handleMiniEnrageGained }

local _effectFadedEntry = {}
_effectFadedEntry[BOSS_ENRAGE] = { type = AlertTypes.CUSTOM, fn = handleBossEnrageFaded }
_effectFadedEntry[MINI_ENRAGE] = { type = AlertTypes.CUSTOM, fn = handleMiniEnrageFaded }

Oaxiltso.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Tracker-row renderers ---------------------------------------------------

local function showBlitzLine(self, alerts, now)
    if self.lastBlitz > 0 then
        local T = 36 - (now - self.lastBlitz)
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.FIRE, Lang.t("rg_oaxiltso_next_blitz")), T)
        else
            alerts:setRow(1, Fmt.c(Fmt.FIRE, Lang.t("rg_oaxiltso_next_blitz")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(1)
    end
end

local function showSludgeLine(self, alerts, now)
    if self.lastSludge > 0 then
        local T = 28 - (now - self.lastSludge)
        if T > 0 then
            alerts:setRow(2, Fmt.c(Fmt.POISON, Lang.t("rg_oaxiltso_next_sludge")), T)
        else
            alerts:setRow(2, Fmt.c(Fmt.POISON, Lang.t("rg_oaxiltso_next_sludge")) .. " " .. Fmt.c(Fmt.RED, "INC"), nil)
        end
    else
        alerts:clearRow(2)
    end
end

local function showEnrageLine(self, alerts)
    if self.bossEnraged and self.miniEnraged then
        alerts:setRow(3, Fmt.c(Fmt.RED, Lang.t("rg_oaxiltso_boss_add_enrage")), nil)
    elseif self.bossEnraged then
        alerts:setRow(3, Fmt.c(Fmt.RED, Lang.t("rg_oaxiltso_boss_enraged")), nil)
    elseif self.miniEnraged then
        alerts:setRow(3, Fmt.c(Fmt.ORANGE, Lang.t("rg_oaxiltso_add_enraged")), nil)
    else
        alerts:clearRow(3)
    end
end

function Oaxiltso:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showBlitzLine(self, alerts, now)
    showSludgeLine(self, alerts, now)
    showEnrageLine(self, alerts)
    alerts:clearRow(4)
end

EventDispatcher.build(Oaxiltso)

package.loaded["trial.rg.boss.Oaxiltso"] = Oaxiltso
return Oaxiltso
