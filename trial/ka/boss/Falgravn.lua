local Location = require("core.Location")
local Settings = require("core.Settings")
local Timer    = require("lib.Timer")

local CA = require("lib.CA")

-- ── OSI helpers (OdySupportIcons, optional) ───────────────────────────────
-- Textures: pulled from the live ability data so they always match the
-- icon players see in their buff bar.  Evaluated once at load time.
local ICON_PRISON      = GetAbilityIcon(132473)   -- FALGRAVN_PRISON
local ICON_INSTABILITY = GetAbilityIcon(140944)   -- FALGRAVN_INSTABILITY
local ICON_SYNERGY     = GetAbilityIcon(129936)   -- FALGRAVN_BLOPSYNERGIE

local COL_PRISON      = { 0.8, 0.3, 1.0 }   -- lavender
local COL_INSTABILITY = { 1.0, 0.6, 0.0 }   -- amber
local COL_SYNERGY     = { 0.9, 0.1, 0.2 }   -- crimson

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

local Falgravn = {

    key = "falgravn",
    hmHealthThreshold = 248386060,
    location = Location.new(73700, 84500, 6000, 22500, 50200, 61900),
    hideActionWhenNoRule = true,
    healthRules = {
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
    },
}

-- ── Stage / mechanic state ────────────────────────────────────────────────
Falgravn.showPercentUI    = false  -- reflects Settings.trial("ka").showPercent; read by healthRules.when()
Falgravn.CURRENT_STAGE    = 1
Falgravn.bHM              = false
-- Dedup flags for Njordal's recurring mechanics (reset each encounter).
Falgravn.bMove            = true
Falgravn.bBlock           = true
Falgravn.bConnect         = true
-- Torturer encounter state.
Falgravn.bStartTorturerCD = true
Falgravn.torturerCount    = 8
-- [unitId] → CA cast bar ID; cleared on reset/death.
Falgravn.alertList        = {}
-- CA cast bar for the Prison debuff (single-slot; matches BSCHTKA pattern).
Falgravn.prisonBarId      = nil
-- OSI mechanic icon tracking: [unitTag] → displayName.
-- Populated on EFFECT_RESULT_GAINED, cleared on FADED or reset.
Falgravn.osiPrison      = {}
Falgravn.osiInstability = {}
Falgravn.osiSynergy     = {}

-- ── Timers ────────────────────────────────────────────────────────────────
-- instabilityTimer is armed in reset() (begins on boss entry).
-- The other three are armed only by specific combat events.
Falgravn.instabilityTimer = Timer.new(INSTABILITY_INITIAL_DELAY)
Falgravn.bloodBallTimer   = Timer.new(NEXT_BLOODBALL)
Falgravn.openGatesTimer   = Timer.new(NEXT_OPENGATE_TIME)
Falgravn.torturerTimer    = Timer.new(NEXT_TORTURER_TP)

-- ── Prisoner tracking ─────────────────────────────────────────────────────
local PRISONERS = {
    Brekalda = 0, Thjorlak = 0, Aevar       = 0, Triveta = 0,
    Skormgondar = 0, Irthrig = 0, Ama        = 0, Sislea  = 0,
}
local function resetPrisoners()
    for name in pairs(PRISONERS) do PRISONERS[name] = 0 end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────

function Falgravn:reset()
    self.CURRENT_STAGE    = 1
    self.bHM              = false
    self.bMove            = true
    self.bBlock           = true
    self.bConnect         = true
    self.bStartTorturerCD = true
    self.torturerCount    = 8
    self.instabilityTimer:reset()
    -- Combat-event-armed timers: clear to expired so :remaining() returns 0.
    self.bloodBallTimer:clear()
    self.openGatesTimer:clear()
    self.torturerTimer:clear()
    resetPrisoners()

    -- Stop any lingering CA cast bars from the previous pull.
    for _, cid in pairs(self.alertList) do CA.castAlertsStop(cid) end
    self.alertList   = {}
    CA.castAlertsStop(self.prisonBarId)
    self.prisonBarId = nil

    -- Remove any OSI mechanic icons left over from the previous pull.
    for _, dn in pairs(self.osiPrison)      do osiRemove(dn) end
    for _, dn in pairs(self.osiInstability) do osiRemove(dn) end
    for _, dn in pairs(self.osiSynergy)     do osiRemove(dn) end
    self.osiPrison      = {}
    self.osiInstability = {}
    self.osiSynergy     = {}
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

-- ── Combat event handler ──────────────────────────────────────────────────
function Falgravn:onCombatEvent(context, alerts, result, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    -- Phase 4.2: stop any tracked CA cast bars when the associated unit dies.
    if result == ACTION_RESULT_DIED then
        if unitId then
            CA.castAlertsStop(self.alertList[unitId])
            self.alertList[unitId] = nil
        end
        if sourceUnitId then
            CA.castAlertsStop(self.alertList[sourceUnitId])
            self.alertList[sourceUnitId] = nil
        end
        return
    end

    -- ── Infuser trash ──────────────────────────────────────────────────
    if abilityId == INFUSER_CASTS and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Infuser!")
        local cid = CA.alertCast(abilityId, sourceUnitName, 1000,
            { -3, 0, false, { 0.0, 0.0, 1, 0.4 }, { 0.1, 0.1, 1, 0.8 } })
        -- Key by sourceUnitId so the bar stops if the infuser dies.
        if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
        return
    end
    if abilityId == INFUSER_BUFF and result == ACTION_RESULT_EFFECT_GAINED then
        alerts:showAction("Infuser Buff passed!")
        CA.alert(nil, "Infuser Buff passed!", 0xFF8800FF, SOUNDS.DUEL_START, 3000)
        return
    end

    -- ── HM confirmation ability ────────────────────────────────────────
    -- Complements the health-threshold detection in BossRegistry:detectDifficulty.
    if abilityId == FALGRAVN_HM then
        if result == ACTION_RESULT_EFFECT_GAINED then
            self.bHM = true
            alerts:showHeader(GetUnitName("boss1") .. " [HM: ON]")
        elseif result == ACTION_RESULT_EFFECT_FADED then
            zo_callLater(function()
                if not IsUnitInCombat("player") then self.bHM = false end
            end, 2000)
        end
        return
    end

    -- ── Njordal mechanics ──────────────────────────────────────────────
    -- Move (dedup: only alert on BEGIN while bMove=true, clear on FADED)
    if abilityId == FALGRAVN_M_MOVE then
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
        return
    end
    -- Block Cast (same dedup pattern).
    -- The charge (136953) immediately precedes the heavy attack (137499 "Bloody Frenzy");
    -- use the heavy's ability ID for the cast bar so the icon/name match the telegraphed hit.
    if abilityId == FALGRAVN_M_BLOCK then
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
        return
    end
    -- Blood Cleave (no dedup — short animation; use ability cast info for duration)
    if abilityId == FALGRAVN_M_CLEAVE and result == ACTION_RESULT_BEGIN then
        alerts:showAction("DODGE!")
        local dur = select(1, GetAbilityCastInfo(FALGRAVN_M_CLEAVE)) or 0
        if dur <= 0 then dur = 2000 end
        CA.castAlertsStart(abilityId, sourceUnitName, dur, dur,
            { 1, 0, 0.6, 0.4 },
            { 700, "DODGE!", 1, 0, 0.6, 0.8, SOUNDS.CHAMPION_POINTS_COMMITTED })
        return
    end
    -- Blood Fountain
    if abilityId == FALGRAVN_BLOOD_FOUNT and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Block Blood Fountain!")
        CA.alertCast(FALGRAVN_BLOOD_FOUNT, sourceUnitName, 3033,
            { -3, 0, false, { 1, 0.2, 0.9, 0.4 }, { 1, 0.2, 0.9, 0.8 } })
        return
    end

    -- ── Lightning / connection mechanic ───────────────────────────────
    -- TODO (OSI floor icons): CreatePositionIcon at each connection-node
    -- world position when bConnect transitions false → true, and
    -- DiscardPositionIcon on EFFECT_FADED / FALGRAVN_PULSE fade.
    -- Measure node coords in-game with OSI.PrintMyPosition().
    if abilityId == FALGRAVN_LIGHTNING then
        if result == ACTION_RESULT_BEGIN and self.bConnect then
            self.bConnect = false
        elseif result == ACTION_RESULT_EFFECT_FADED and not self.bConnect then
            self.bConnect = true
        end
        return
    end
    -- Pulse fades → clear any connection-node position icons (TODO above).
    if abilityId == FALGRAVN_PULSE and result == ACTION_RESULT_EFFECT_FADED then
        alerts:showInfo(2, "")
        alerts:showInfo(3, "")
        alerts:showInfo(4, "")
        return
    end

    -- ── Instability timer reset ────────────────────────────────────────
    if abilityId == FALGRAVN_INSTABILITY and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.instabilityTimer:reset(NEXT_INSTABILITY)
        return
    end

    -- ── Stage 2 onset — Unwavering Power fades (Falgravn lands) ───────
    if abilityId == FALGRAVN_UNW_POWER and result == ACTION_RESULT_EFFECT_FADED then
        self.bloodBallTimer:reset(INITIAL_BLOODBALL_DELAY)
        self.instabilityTimer:reset(INSTABILITY_INITIAL_DELAY)
        -- TODO (OSI floor icons): CreatePositionIcon for each blood-fountain
        -- spawn position when Falgravn lands.  Measure coords in-game.
        return
    end
    -- Blood Ball effect drives stage 2 and its recurring timer
    if abilityId == FALGRAVN_BLOOTBALL then
        if self.CURRENT_STAGE ~= 2 then
            self.CURRENT_STAGE = 2
        end
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
            self.bloodBallTimer:reset(30)
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.bloodBallTimer:reset(NEXT_BLOODBALL)
        end
        return
    end
    -- Secondary stage-2 trigger
    if abilityId == FALGRAVN_START_STAGE2 and result == ACTION_RESULT_BEGIN then
        if self.CURRENT_STAGE ~= 2 then
            self.CURRENT_STAGE = 2
        end
        return
    end

    -- ── Stage 3 onset — floor shatters ────────────────────────────────
    if abilityId == FALGRAVN_SHATTER_MID and result == ACTION_RESULT_BEGIN then
        if self.CURRENT_STAGE ~= 3 then
            self.CURRENT_STAGE = 3
            self.openGatesTimer:reset(INITIAL_OPENGATE_TIME)
            alerts:showInfo(2, "")
            alerts:showInfo(3, "")
            alerts:showInfo(4, "")
            -- TODO (OSI floor icons): CreatePositionIcon for each torturer
            -- spawn/walk position.  Measure world coords in-game.
        end
        return
    end
    -- Open the Gates — recurring cast + timer reset.
    -- 25 s after each gate opens the active torturer does a heavy attack on the tank;
    -- schedule a CA cast bar so tanks know to block in time.
    if abilityId == FALGRAVN_OPEN_DOOR and result == ACTION_RESULT_BEGIN then
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
        return
    end
    -- Torturer feeding: start kill countdown (deduped per feed cycle)
    if abilityId == FALGRAVN_TUT_FEED then
        if result == ACTION_RESULT_EFFECT_GAINED then
            if self.bStartTorturerCD then
                self.bStartTorturerCD = false
                alerts:showAction("KILL Torturer!")
                local cid = CA.castAlertsStart(abilityId, GetAbilityName(abilityId),
                    10000, 10000,
                    { 1, 0.7, 0, 0.5 },
                    { 10000, "KILL Torturer!", 0.8, 0, 0, 0.9, SOUNDS.NONE })
                -- Store by the torturer's sourceUnitId so the bar stops if it dies.
                if cid and sourceUnitId then self.alertList[sourceUnitId] = cid end
            end
            -- TODO (OSI floor icon): mark the active torturer's world position.
            -- Torturers are NPCs so SetMechanicIconForUnit won't work; use
            -- CreatePositionIcon with measured coords per torturer slot instead.
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.bStartTorturerCD = true
        end
        return
    end
    -- Prisoner saved — decrement torturer count
    if abilityId == FALGRAVN_SACRIFICE then
        self.torturerCount = self.torturerCount - 1
        return
    end
    -- Torturer coming down
    if abilityId == FALGRAVN_TORTURER_ESC and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Torturer Comes Down!")
        CA.alert(nil, "Torturer Comes Down!", 0xFF8800FF,
            SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
        return
    end
    -- Torturer light attack — only alert non-tanks when they are targeted
    if abilityId == FALGRAVN_TORTURER_LA and result == ACTION_RESULT_BEGIN then
        if IsUnitPlayer(unitTag) and GetSelectedLFGRole() ~= LFG_ROLE_TANK then
            alerts:showAction("DODGE! (Torturer LA)")
            CA.alert("Torturer LA's", "DODGE!", 0xFF0000FF, SOUNDS.DUEL_START, 1000)
        end
        return
    end
end

-- ── Effect change handler ─────────────────────────────────────────────────

function Falgravn:onEffectChanged(context, alerts, changeType, abilityId, unitTag, unitId, unitName)
    -- Prison debuff on a player: kill-countdown alert + OSI mechanic icon.
    if abilityId == FALGRAVN_PRISON then
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
        return
    end

    -- Instability debuff on a player: OSI mechanic icon.
    if abilityId == FALGRAVN_INSTABILITY or abilityId == FALGRAVN_INSTABILITY2 then
        if not IsUnitPlayer(unitTag) then return end
        if changeType == EFFECT_RESULT_GAINED then
            local dn = GetUnitDisplayName(unitTag)
            osiSet(dn, ICON_INSTABILITY, COL_INSTABILITY)
            if dn and dn ~= "" then self.osiInstability[unitTag] = dn end
        elseif changeType == EFFECT_RESULT_FADED then
            osiRemove(self.osiInstability[unitTag])
            self.osiInstability[unitTag] = nil
        end
        return
    end

    -- Prisoner stack tracking — 11 stacks means that torturer's prisoner is lost
    if abilityId == FALGRAVN_PRISONER_F and changeType == EFFECT_RESULT_GAINED then
        local name = zo_strformat("<<1>>", unitName)
        if PRISONERS[name] ~= nil then
            PRISONERS[name] = PRISONERS[name] + 1
            if PRISONERS[name] == 11 then
                self.torturerCount = self.torturerCount - 1
                    -- (see torturer-feeding TODO above)
            end
        end
        return
    end

    -- Execration synergy on a player: OSI mechanic icon.
    if abilityId == FALGRAVN_BLOPSYNERGIE then
        if not IsUnitPlayer(unitTag) then return end
        if changeType == EFFECT_RESULT_GAINED then
            local dn = GetUnitDisplayName(unitTag)
            osiSet(dn, ICON_SYNERGY, COL_SYNERGY)
            if dn and dn ~= "" then self.osiSynergy[unitTag] = dn end
        elseif changeType == EFFECT_RESULT_FADED then
            osiRemove(self.osiSynergy[unitTag])
            self.osiSynergy[unitTag] = nil
        end
        return
    end
end

return Falgravn
