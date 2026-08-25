local Location    = require("core.Location")
local HealthRules = require("core.HealthRules")
local Settings    = require("core.Settings")
local Timer       = require("lib.Timer")

local CA = require("lib.CA")
local BossBase = require("lib.BossBase")

-- ── OSI helpers (OdySupportIcons, optional) ───────────────────────────────
-- Textures: pulled from the live ability data so they always match the
-- icon players see in their buff bar.  Evaluated once at load time.
local ICON_PRISON      = GetAbilityIcon(132473)   -- FALGRAVN_PRISON
local ICON_INSTABILITY = GetAbilityIcon(140944)   -- FALGRAVN_INSTABILITY
local ICON_SYNERGY     = GetAbilityIcon(129936)   -- FALGRAVN_BLOPSYNERGIE

local COL_PRISON      = { 0.8, 0.3, 1.0 }   -- lavender
local COL_INSTABILITY = { 1.0, 0.6, 0.0 }   -- amber
local COL_SYNERGY     = { 0.9, 0.1, 0.2 }   -- crimson

-- ── Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) ─
local FALLBACK_DUR = 2000   -- Cleave (FALGRAVN_M_CLEAVE): empirical

local function osiSet(displayName, texture, color)
    if OSI and displayName and displayName ~= "" then
        OSI.SetMechanicIconForUnit(displayName, texture, nil, color, nil, nil)
    end
end

local function osiRemove(displayName)
    if OSI and displayName and displayName ~= "" then
        OSI.RemoveMechanicIconForUnit(displayName)
    end
end

-- ── Ability IDs (from BSCHTKA_Falgraven.lua) ──────────────────────────────
-- Combat event IDs
local INFUSER_CASTS         = 137289  -- Trash infuser cast
local INFUSER_BUFF          = 139961  -- Infuser buff gained by ally
local FALGRAVN_LIGHTNING    = 133428  -- Connect mechanic (90%/80%); OSI floor icons need world coords
local FALGRAVN_OPEN_DOOR    = 136693  -- Open the gates cast
local FALGRAVN_TUT_FEED     = 137314  -- Torturer feeding prisoner
local FALGRAVN_M_MOVE       = 136965  -- Njordal ground move AoE
local FALGRAVN_M_BLOCK      = 136953  -- Njordal charge (triggers heavy; use 137499 for the bar)
local FALGRAVN_M_BLOCK_HEAVY = 137499 -- "Bloody Frenzy" — the actual heavy-attack ability
local FALGRAVN_M_CLEAVE     = 136976  -- Njordal blood cleave
local FALGRAVN_BLOOD_FOUNT  = 140294  -- Blood Fountain cast
local FALGRAVN_TORTURER_ESC = 139633  -- Torturer coming down
local FALGRAVN_START_STAGE2 = 135271  -- Stage 2 start channel
local FALGRAVN_SHATTER_MID  = 136727  -- Floor shatters → Stage 3
local FALGRAVN_INSTABILITY  = 140944  -- Instability cast / effect
local FALGRAVN_UNW_POWER    = 139378  -- Unwavering Power (Falgravn landing)
local FALGRAVN_BLOOTBALL    = 136548  -- Blood Ball effect
local FALGRAVN_PULSE        = 134854  -- Connection pulse (fades → clear icons)
local FALGRAVN_HM           = 137215  -- HM confirmation ability
local FALGRAVN_SACRIFICE    = 139620  -- Prisoner saved
local FALGRAVN_TORTURER_LA  = 136958  -- Torturer light attack (non-tank dodge)

-- Effect change IDs
local FALGRAVN_PRISON       = 132473  -- Prison debuff on player
local FALGRAVN_INSTABILITY2 = 140941  -- Instability (non-HM variant)
local FALGRAVN_PRISONER_F   = 137315  -- Prisoner feeding stacks
local FALGRAVN_BLOPSYNERGIE = 129936  -- Execration synergy on player

-- ── Timer durations ───────────────────────────────────────────────────────
local INSTABILITY_INITIAL_DELAY  = 10
local NEXT_INSTABILITY           = 22
local NEXT_BLOODBALL             = 45
local INITIAL_BLOODBALL_DELAY    = 20   -- after Falgravn lands (UNW_POWER fades)
local INITIAL_OPENGATE_TIME      = 40   -- from floor shatter to first gates
local NEXT_OPENGATE_TIME         = 45   -- recurring between Open Door casts
local NEXT_TORTURER_TP           = 25   -- torturer teleport countdown

-- ── Boss definition ───────────────────────────────────────────────────────

local Falgravn = {}
Falgravn.__index = Falgravn

Falgravn.key                  = "falgravn"
Falgravn.hmHealthThreshold    = 248386060
Falgravn.location             = Location.new(73700, 84500, 6000, 22500, 50200, 61900)
Falgravn.hideActionWhenNoRule = true
Falgravn.healthRules          = HealthRules.register({
    {
        id   = "conga_90",
        min  = 90, max = 93,
        text = "Connect Soon! (90% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI end,
    },
    {
        id   = "conga_80",
        min  = 80, max = 83,
        text = "Connect Soon! (80% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI end,
    },
    {
        id   = "floor_shatter",
        min  = 70, max = 73,
        text = "Dont Ult (Floor Shatter)! (70% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI end,
    },
    {
        id   = "dont_ult",
        min  = 35, max = 38,
        text = "Dont Ult! (35% / {hp}%)",
        when = function(ctx, boss) return boss.showPercentUI and ctx.stage < 3 end,
    },
})

Falgravn.stateSchema = {
    -- Stage / mechanic state
    showPercentUI    = false,
    CURRENT_STAGE    = 1,
    bHM              = false,
    -- Dedup flags for Njordal's recurring mechanics (reset each encounter).
    bMove            = true,
    bBlock           = true,
    bConnect         = true,
    -- Torturer encounter state.
    bStartTorturerCD = true,
    torturerCount    = 8,
    -- [unitId] → CA cast bar ID; cleared on leave/death.
    alertList        = function() return {} end,
    -- OSI mechanic icon tracking: [unitTag] → displayName.
    osiPrison      = function() return {} end,
    osiInstability = function() return {} end,
    osiSynergy     = function() return {} end,
    -- Timers
    instabilityTimer = function() return Timer.new(INSTABILITY_INITIAL_DELAY) end,
    bloodBallTimer   = function() return Timer.new(NEXT_BLOODBALL) end,
    openGatesTimer   = function() return Timer.new(NEXT_OPENGATE_TIME) end,
    torturerTimer    = function() return Timer.new(NEXT_TORTURER_TP) end,
    -- Prisoner tracking: stack count per prisoner name.
    PRISONERS = function() return {
        Brekalda = 0, Thjorlak = 0, Aevar = 0, Triveta = 0,
        Skormgondar = 0, Irthrig = 0, Ama = 0, Sislea = 0,
    } end,
}

function Falgravn.new()
    return BossBase.fromSchema(Falgravn)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────

function Falgravn:onLeave(context)
    -- Stop any lingering CA cast bars.
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    CA.castAlertsStop(self.prisonBarId)
    -- Remove any OSI mechanic icons.
    for _, dn in pairs(self.osiPrison)      do osiRemove(dn) end
    for _, dn in pairs(self.osiInstability) do osiRemove(dn) end
    for _, dn in pairs(self.osiSynergy)     do osiRemove(dn) end
end

-- ── Combat state ──────────────────────────────────────────────────────────

function Falgravn:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.instabilityTimer:reset()
    end
end

function Falgravn:onEnter(context, alerts)
    self.showPercentUI = Settings.trial("ka").showPercent
    context.stage      = self.CURRENT_STAGE
end

function Falgravn:onPowerUpdate(context)
    context.stage      = self.CURRENT_STAGE
    self.showPercentUI = Settings.trial("ka").showPercent
end


-- ── 200ms timer display ───────────────────────────────────────────────────
-- Layout matches BSCHTKA's Falg_UpdateUI:
--   Stage 1 → info1=Instability
--   Stage 2 → info1=Instability, info2=Blood Ball
--   Stage 3 → info1=Open Gates, info2=Torturer TP countdown

function Falgravn:onUpdate(context, alerts)
    local stage = self.CURRENT_STAGE

    if stage == 1 then
        local ti = self.instabilityTimer:remaining()
        alerts:showInfo(1, "Instability: " .. (ti > 0 and ZO_FormatCountdownTimer(ti) or "up!"))

    elseif stage == 2 then
        local ti  = self.instabilityTimer:remaining()
        local tbb = self.bloodBallTimer:remaining()
        alerts:showInfo(1, "Instability: " .. (ti > 0 and ZO_FormatCountdownTimer(ti) or "up!"))
        alerts:showInfo(2, tbb > 0 and ("Blood Ball: " .. ZO_FormatCountdownTimer(tbb)) or "Blood Ball: soon!")

    elseif stage == 3 then
        local tog = self.openGatesTimer:remaining()
        local ttp = self.torturerTimer:remaining()
        alerts:showInfo(1, tog > 0 and ("Open Gates: " .. ZO_FormatCountdownTimer(tog)) or "Open Gates: soon!")
        alerts:showInfo(2, ttp > 0 and ("Torturer TP: " .. ZO_FormatCountdownTimer(ttp)) or "")
    end
end

-- ── Handlers ────────────────────────────────────────────────────────────
-- (Falgravn has no shared common module.)

-- DIED: stop CA bars for the dead unit and its killer.
function Falgravn:onDied(context, alerts,
                          unitTag, sourceUnitTag, sourceUnitId, unitId,
                          sourceUnitName, unitName)
    if unitId then
        CA.castAlertsStop(self.alertList[unitId])
        self.alertList[unitId] = nil
    end
    if sourceUnitId then
        CA.castAlertsStop(self.alertList[sourceUnitId])
        self.alertList[sourceUnitId] = nil
    end
end

local function handleInfuserCasts(self, context, alerts, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId,
                                   sourceUnitName, unitName)
    alerts:showAction("Interrupt Infuser!")
    local cid = CA.alertCast(abilityId, sourceUnitName, 1000,
        { -3, 0, false, { 0.0, 0.0, 1, 0.4 }, { 0.1, 0.1, 1, 0.8 } })
    if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
end

local function handleInfuserBuff(self, context, alerts, abilityId, ...)
    alerts:showAction("Infuser Buff passed!")
    CA.alert(nil, "Infuser Buff passed!", 0xFF8800FF, SOUNDS.DUEL_START, 3000)
end

-- HM confirmation ability (plain entry: receives result).
local function handleFalgravnHm(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        self.bHM = true
        alerts:showHeader(GetUnitName("boss1") .. " [HM: ON]")
    elseif result == ACTION_RESULT_EFFECT_FADED then
        zo_callLater(function()
            if not IsUnitInCombat("player") then self.bHM = false end
        end, 2000)
    end
end

-- Njordal: Move AoE (plain entry; deduped via bMove flag).
local function handleNjordalMove(self, context, alerts, result, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if result == ACTION_RESULT_BEGIN and self.bMove then
        self.bMove = false
        alerts:showAction("Move!")
        local cid = CA.castAlertsStart(abilityId, GetAbilityName(abilityId),
            12000, 12000,
            { 1, 0.7, 0, 0.5 },
            { 12000, "Move!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
    elseif result == ACTION_RESULT_EFFECT_FADED and not self.bMove then
        self.bMove = true
    end
end

-- Njordal: Block Cast (plain entry; deduped; icon uses heavy-attack ID).
local function handleNjordalBlock(self, context, alerts, result, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if result == ACTION_RESULT_BEGIN and self.bBlock then
        self.bBlock = false
        alerts:showAction("Block Cast!")
        local cid = CA.castAlertsStart(FALGRAVN_M_BLOCK_HEAVY, "Bloody Frenzy",
            6500, 6500,
            { 1, 0.7, 0, 0.5 },
            { 6500, "Block Cast!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
    elseif result == ACTION_RESULT_EFFECT_FADED and not self.bBlock then
        self.bBlock = true
    end
end

local function handleBloodCleave(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    alerts:showAction("DODGE!")
    local dur = select(1, GetAbilityCastInfo(FALGRAVN_M_CLEAVE)) or 0
    if dur <= 0 then dur = FALLBACK_DUR end
    CA.castAlertsStart(abilityId, sourceUnitName, dur, dur,
        { 1, 0, 0.6, 0.4 },
        { 700, "DODGE!", 1, 0, 0.6, 0.8, SOUNDS.CHAMPION_POINTS_COMMITTED })
end

local function handleBloodFountain(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    alerts:showAction("Block Blood Fountain!")
    CA.alertCast(FALGRAVN_BLOOD_FOUNT, sourceUnitName, 3033,
        { -3, 0, false, { 1, 0.2, 0.9, 0.4 }, { 1, 0.2, 0.9, 0.8 } })
end

-- Lightning / connection (plain entry; deduped via bConnect flag).
local function handleLightning(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_BEGIN and self.bConnect then
        self.bConnect = false
    elseif result == ACTION_RESULT_EFFECT_FADED and not self.bConnect then
        self.bConnect = true
    end
end

-- Pulse fades → clear connection-node info lines 2-4.
local function handlePulse(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_FADED then
        alerts:showInfo(2, ""); alerts:showInfo(3, ""); alerts:showInfo(4, "")
    end
end

-- Instability timer reset (plain entry: fires on EFFECT_GAINED_DURATION).
local function handleInstabilityCombat(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.instabilityTimer:reset(NEXT_INSTABILITY)
    end
end

local function handleUnwPower(self, context, alerts, abilityId, ...)
    self.bloodBallTimer:reset(INITIAL_BLOODBALL_DELAY)
    self.instabilityTimer:reset(INSTABILITY_INITIAL_DELAY)
end

-- Blood Ball (plain entry: updates Stage 2 state and bloodBallTimer).
local function handleBloodBall(self, context, alerts, result, abilityId, ...)
    if self.CURRENT_STAGE ~= 2 then self.CURRENT_STAGE = 2 end
    if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.bloodBallTimer:reset(30)
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.bloodBallTimer:reset(NEXT_BLOODBALL)
    end
end

local function handleStartStage2(self, context, alerts, abilityId, ...)
    if self.CURRENT_STAGE ~= 2 then self.CURRENT_STAGE = 2 end
end

local function handleShatterMid(self, context, alerts, abilityId, ...)
    if self.CURRENT_STAGE ~= 3 then
        self.CURRENT_STAGE = 3
        self.openGatesTimer:reset(INITIAL_OPENGATE_TIME)
        alerts:showInfo(2, ""); alerts:showInfo(3, ""); alerts:showInfo(4, "")
    end
end

-- Open Gates: recurring timer + 25 s delayed heavy-attack alert for tanks.
local function handleOpenDoor(self, context, alerts, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
    self.openGatesTimer:reset(NEXT_OPENGATE_TIME)
    self.torturerTimer:reset(NEXT_TORTURER_TP)
    alerts:showAction("Open the Gates!")
    CA.alert(nil, "Open the Gates!", 0x991111FF,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 2000)
    local capturedSrc = sourceUnitName or ""
    zo_callLater(function()
        if not IsUnitInCombat("player") then return end
        CA.alertCast(FALGRAVN_OPEN_DOOR, capturedSrc, 7500,
            { -3, 0, false, { 0, 0, 0.7, 0.4 }, { 0, 0, 0.7, 0.8 } })
    end, 25000)
end

-- Torturer feeding: kill countdown (plain entry; deduped per feed cycle).
local function handleTorturerFeed(self, context, alerts, result, abilityId,
                                   unitTag, sourceUnitTag, sourceUnitId, unitId, ...)
    if result == ACTION_RESULT_EFFECT_GAINED then
        if self.bStartTorturerCD then
            self.bStartTorturerCD = false
            alerts:showAction("KILL Torturer!")
            local cid = CA.castAlertsStart(abilityId, GetAbilityName(abilityId),
                10000, 10000,
                { 1, 0.7, 0, 0.5 },
                { 10000, "KILL Torturer!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
            if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
        end
    elseif result == ACTION_RESULT_EFFECT_FADED then
        self.bStartTorturerCD = true
    end
end

-- Prisoner saved (plain entry; decrements torturer count).
local function handleSacrifice(self, ...)
    self.torturerCount = self.torturerCount - 1
end

local function handleTorturerEsc(self, context, alerts, abilityId, ...)
    alerts:showAction("Torturer Comes Down!")
    CA.alert(nil, "Torturer Comes Down!", 0xFF8800FF,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
end

local function handleTorturerLa(self, context, alerts, abilityId, unitTag, ...)
    if IsUnitPlayer(unitTag) and GetSelectedLFGRole() ~= LFG_ROLE_TANK then
        alerts:showAction("DODGE! (Torturer LA)")
        CA.alert("Torturer LA's", "DODGE!", 0xFF0000FF, SOUNDS.DUEL_START, 1000)
    end
end

-- Instability OSI: shared handler for both HM (140944) and non-HM (140941) variants.
local function handleInstabilityEffect(self, context, alerts, changeType, abilityId,
                                        unitTag, unitId, unitName, stackCount)
    if not IsUnitPlayer(unitTag) then return end
    if changeType == EFFECT_RESULT_GAINED then
        local dn = GetUnitDisplayName(unitTag)
        osiSet(dn, ICON_INSTABILITY, COL_INSTABILITY)
        if dn and dn ~= "" then self.osiInstability[unitTag] = dn end
    elseif changeType == EFFECT_RESULT_FADED then
        osiRemove(self.osiInstability[unitTag])
        self.osiInstability[unitTag] = nil
    end
end

local function handlePrisonEffect(self, context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName, stackCount)
    if changeType == EFFECT_RESULT_GAINED then
        alerts:showAction("KILL PRISON!")
        local dur = 8000
        self.prisonBarId = CA.castAlertsStart(
            abilityId, GetAbilityName(abilityId),
            dur, dur,
            { 1, 0.7, 0, 0.5 },
            { dur, "KILL PRISON!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
        local dn = GetUnitDisplayName(unitTag)
        osiSet(dn, ICON_PRISON, COL_PRISON)
        if dn and dn ~= "" then self.osiPrison[unitTag] = dn end
    elseif changeType == EFFECT_RESULT_FADED then
        CA.castAlertsStop(self.prisonBarId)
        self.prisonBarId = nil
        osiRemove(self.osiPrison[unitTag])
        self.osiPrison[unitTag] = nil
    end
end

local function handlePrisonerFeeding(self, context, alerts, abilityId,
                                      unitTag, unitId, unitName, stackCount)
    local name = zo_strformat("<<1>>", unitName)
    if self.PRISONERS[name] ~= nil then
        self.PRISONERS[name] = self.PRISONERS[name] + 1
        if self.PRISONERS[name] == 11 then
            self.torturerCount = self.torturerCount - 1
        end
    end
end

local function handleBlopSynergie(self, context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName, stackCount)
    if not IsUnitPlayer(unitTag) then return end
    if changeType == EFFECT_RESULT_GAINED then
        local dn = GetUnitDisplayName(unitTag)
        osiSet(dn, ICON_SYNERGY, COL_SYNERGY)
        if dn and dn ~= "" then self.osiSynergy[unitTag] = dn end
    elseif changeType == EFFECT_RESULT_FADED then
        osiRemove(self.osiSynergy[unitTag])
        self.osiSynergy[unitTag] = nil
    end
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────

Falgravn.combatRoutes = {
    -- ── Infuser trash ──────────────────────────────────────────────────────
    [INFUSER_CASTS]        = { result = ACTION_RESULT_BEGIN,         fn = handleInfuserCasts },
    [INFUSER_BUFF]         = { result = ACTION_RESULT_EFFECT_GAINED, fn = handleInfuserBuff },
    -- ── HM confirmation ability ────────────────────────────────────────────
    [FALGRAVN_HM]          = handleFalgravnHm,
    -- ── Njordal ────────────────────────────────────────────────────────────
    [FALGRAVN_M_MOVE]      = handleNjordalMove,
    [FALGRAVN_M_BLOCK]     = handleNjordalBlock,
    [FALGRAVN_M_CLEAVE]    = { result = ACTION_RESULT_BEGIN,         fn = handleBloodCleave },
    [FALGRAVN_BLOOD_FOUNT] = { result = ACTION_RESULT_BEGIN,         fn = handleBloodFountain },
    -- ── Lightning / connection ─────────────────────────────────────────────
    [FALGRAVN_LIGHTNING]   = handleLightning,
    [FALGRAVN_PULSE]       = handlePulse,
    -- ── Instability ────────────────────────────────────────────────────────
    [FALGRAVN_INSTABILITY] = handleInstabilityCombat,
    -- ── Stage 2 ────────────────────────────────────────────────────────────
    [FALGRAVN_UNW_POWER]   = { result = ACTION_RESULT_EFFECT_FADED,  fn = handleUnwPower },
    [FALGRAVN_BLOOTBALL]   = handleBloodBall,
    [FALGRAVN_START_STAGE2]= { result = ACTION_RESULT_BEGIN,         fn = handleStartStage2 },
    -- ── Stage 3 ────────────────────────────────────────────────────────────
    [FALGRAVN_SHATTER_MID] = { result = ACTION_RESULT_BEGIN,         fn = handleShatterMid },
    [FALGRAVN_OPEN_DOOR]   = { result = ACTION_RESULT_BEGIN,         fn = handleOpenDoor },
    -- ── Torturer ────────────────────────────────────────────────────────────
    [FALGRAVN_TUT_FEED]    = handleTorturerFeed,
    [FALGRAVN_SACRIFICE]   = handleSacrifice,
    [FALGRAVN_TORTURER_ESC]= { result = ACTION_RESULT_BEGIN,         fn = handleTorturerEsc },
    [FALGRAVN_TORTURER_LA] = { result = ACTION_RESULT_BEGIN,         fn = handleTorturerLa },
}

-- ── Effect routing tables (C3) ───────────────────────────────────────────

Falgravn.effectRoutes = {
    [FALGRAVN_PRISON]       = handlePrisonEffect,
    [FALGRAVN_INSTABILITY]  = handleInstabilityEffect,
    [FALGRAVN_INSTABILITY2] = handleInstabilityEffect,
    [FALGRAVN_PRISONER_F]   = { changeType = EFFECT_RESULT_GAINED, fn = handlePrisonerFeeding },
    [FALGRAVN_BLOPSYNERGIE] = handleBlopSynergie,
}

return Falgravn
