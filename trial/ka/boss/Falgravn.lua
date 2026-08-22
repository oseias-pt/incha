local Location = require("core.Location")
local Settings = require("core.Settings")
local Timer    = require("lib.Timer")

-- ── Ability IDs (from BSCHTKA_Falgraven.lua) ──────────────────────────────
-- Combat event IDs
local INFUSER_CASTS         = 137289  -- Trash infuser cast
local INFUSER_BUFF          = 139961  -- Infuser buff gained by ally
local FALGRAVN_LIGHTNING    = 133428  -- Connect mechanic (90%/80%)  → OSI icons (Phase 4.3)
local FALGRAVN_OPEN_DOOR    = 136693  -- Open the gates cast
local FALGRAVN_TUT_FEED     = 137314  -- Torturer feeding prisoner
local FALGRAVN_M_MOVE       = 136965  -- Njordal ground move AoE
local FALGRAVN_M_BLOCK      = 136953  -- Njordal charge cast
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
    id = 3,
    key = "falgravn",
    hmHealthThreshold = 248386060,
    location = Location.new(73700, 84500, 6000, 22500, 50200, 61900),
    hideActionWhenNoRule = true,
    healthRules = {
        {
            id   = "conga_90",
            min  = 90, max = 93,
            text = "Connect Soon! (90% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI end,
        },
        {
            id   = "conga_80",
            min  = 80, max = 83,
            text = "Connect Soon! (80% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI end,
        },
        {
            id   = "floor_shatter",
            min  = 70, max = 73,
            text = "Dont Ult (Floor Shatter)! (70% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI end,
        },
        {
            id   = "dont_ult",
            min  = 35, max = 38,
            text = "Dont Ult! (35% / {hp}%)",
            when = function(ctx) return ctx.extras.showPercentUI and ctx.stage < 3 end,
        },
    },
}

-- ── Stage / mechanic state ────────────────────────────────────────────────
Falgravn.CURRENT_STAGE    = 1
Falgravn.bHM              = false
-- Dedup flags for Njordal's recurring mechanics (reset each encounter).
Falgravn.bMove            = true
Falgravn.bBlock           = true
Falgravn.bConnect         = true
-- Torturer encounter state.
Falgravn.bStartTorturerCD = true
Falgravn.torturerCount    = 8

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

function Falgravn:reset(forced)
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
    self:syncLegacy()

    -- Clear BSCHTKA's info lines if still loaded alongside Incha.
    if BSCHTKAHelperInfoUI then
        BSCHTKAHelperInfoUI:GetNamedChild("Info1"):SetText("")
        BSCHTKAHelperInfoUI:GetNamedChild("Info2"):SetText("")
        BSCHTKAHelperInfoUI:GetNamedChild("Info3"):SetText("")
        BSCHTKAHelperInfoUI:GetNamedChild("Info4"):SetText("")
    end
    if self.DisableAllPosIconBlood then self:DisableAllPosIconBlood() end
    if self.DisableAllPosIconConn  then self:DisableAllPosIconConn()  end
end

function Falgravn:onEnter(context, alerts)
    context.extras.legacyFlag    = "bFalgraven"
    context.extras.showPercentUI = Settings.trial("ka").showPercent
    context.stage                = self.CURRENT_STAGE
    self:syncLegacy()
end

function Falgravn:onPowerUpdate(context)
    context.stage                = self.CURRENT_STAGE
    context.extras.showPercentUI = Settings.trial("ka").showPercent
    self:syncLegacy()
end

-- Expose timer epochs to BSCHTKA globals so its Falg_UpdateUI keeps working
-- during the LegacyUI transition.  Removed once LegacyUI is retired (4.4).
function Falgravn:syncLegacy()
    if not BSCHTKA then return end
    BSCHTKA.CURRENT_STAGE    = self.CURRENT_STAGE
    BSCHTKA.INSTABILITY_TIME = self.instabilityTimer:getExpiresAt()
    BSCHTKA.BLOODBALL_TIME   = self.bloodBallTimer:getExpiresAt()
    BSCHTKA.OPEN_GATES_TIME  = self.openGatesTimer:getExpiresAt()
    BSCHTKA.TORTURER_TP      = self.torturerTimer:getExpiresAt()
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
-- Phase 4.1: text-only alerts via showAction.  Phase 4.2 adds CombatAlerts.
-- Phase 4.3 adds OSI icon calls where noted.
-- NOT registered while KA Factory uses LegacyUI (Phase 4.4 wires this in).

function Falgravn:onCombatEvent(context, alerts, result, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId)
    -- ── Infuser trash ──────────────────────────────────────────────────
    if abilityId == INFUSER_CASTS and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Infuser!")
        return
    end
    if abilityId == INFUSER_BUFF and result == ACTION_RESULT_EFFECT_GAINED then
        alerts:showAction("Infuser Buff passed!")
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
        elseif result == ACTION_RESULT_EFFECT_FADED and not self.bMove then
            self.bMove = true
        end
        return
    end
    -- Block Cast (same dedup pattern)
    if abilityId == FALGRAVN_M_BLOCK then
        if result == ACTION_RESULT_BEGIN and self.bBlock then
            self.bBlock = false
            alerts:showAction("Block Cast!")
        elseif result == ACTION_RESULT_EFFECT_FADED and not self.bBlock then
            self.bBlock = true
        end
        return
    end
    -- Blood Cleave (no dedup needed — short duration)
    if abilityId == FALGRAVN_M_CLEAVE and result == ACTION_RESULT_BEGIN then
        alerts:showAction("DODGE!")
        return
    end
    -- Blood Fountain
    if abilityId == FALGRAVN_BLOOD_FOUNT and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Block Blood Fountain!")
        return
    end

    -- ── Lightning / connection mechanic ───────────────────────────────
    -- OSI floor icons deferred to Phase 4.3; track bConnect state for now.
    if abilityId == FALGRAVN_LIGHTNING then
        if result == ACTION_RESULT_BEGIN and self.bConnect then
            self.bConnect = false
            -- Phase 4.3: BSCHTKA.EnableAllPosIconConn()
        elseif result == ACTION_RESULT_EFFECT_FADED and not self.bConnect then
            self.bConnect = true
            -- Phase 4.3: BSCHTKA.DisableAllPosIconConn()
        end
        return
    end
    -- Pulse fades → disable connection icons
    if abilityId == FALGRAVN_PULSE and result == ACTION_RESULT_EFFECT_FADED then
        -- Phase 4.3: BSCHTKA.DisableAllPosIconConn()
        alerts:showInfo(2, "")
        alerts:showInfo(3, "")
        alerts:showInfo(4, "")
        return
    end

    -- ── Instability timer reset ────────────────────────────────────────
    if abilityId == FALGRAVN_INSTABILITY and result == ACTION_RESULT_EFFECT_GAINED_DURATION then
        self.instabilityTimer:reset(NEXT_INSTABILITY)
        self:syncLegacy()
        return
    end

    -- ── Stage 2 onset — Unwavering Power fades (Falgravn lands) ───────
    if abilityId == FALGRAVN_UNW_POWER and result == ACTION_RESULT_EFFECT_FADED then
        self.bloodBallTimer:reset(INITIAL_BLOODBALL_DELAY)
        self.instabilityTimer:reset(INSTABILITY_INITIAL_DELAY)
        self:syncLegacy()
        -- Phase 4.3: BSCHTKA.EnableAllPosIconBlood()
        return
    end
    -- Blood Ball effect drives stage 2 and its recurring timer
    if abilityId == FALGRAVN_BLOOTBALL then
        if self.CURRENT_STAGE ~= 2 then
            self.CURRENT_STAGE = 2
            self:syncLegacy()
        end
        if result == ACTION_RESULT_EFFECT_GAINED_DURATION then
            self.bloodBallTimer:reset(30)
            self:syncLegacy()
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.bloodBallTimer:reset(NEXT_BLOODBALL)
            self:syncLegacy()
        end
        return
    end
    -- Secondary stage-2 trigger
    if abilityId == FALGRAVN_START_STAGE2 and result == ACTION_RESULT_BEGIN then
        if self.CURRENT_STAGE ~= 2 then
            self.CURRENT_STAGE = 2
            self:syncLegacy()
        end
        return
    end

    -- ── Stage 3 onset — floor shatters ────────────────────────────────
    if abilityId == FALGRAVN_SHATTER_MID and result == ACTION_RESULT_BEGIN then
        if self.CURRENT_STAGE ~= 3 then
            self.CURRENT_STAGE = 3
            self.openGatesTimer:reset(INITIAL_OPENGATE_TIME)
            self:syncLegacy()
            alerts:showInfo(2, "")
            alerts:showInfo(3, "")
            alerts:showInfo(4, "")
            -- Phase 4.3: BSCHTKA.EnableAllTorturerIcons()
        end
        return
    end
    -- Open the Gates — recurring cast + timer reset
    if abilityId == FALGRAVN_OPEN_DOOR and result == ACTION_RESULT_BEGIN then
        self.openGatesTimer:reset(NEXT_OPENGATE_TIME)
        self.torturerTimer:reset(NEXT_TORTURER_TP)
        self:syncLegacy()
        alerts:showAction("Open the Gates!")
        return
    end
    -- Torturer feeding: start kill countdown (deduped per feed cycle)
    if abilityId == FALGRAVN_TUT_FEED then
        if result == ACTION_RESULT_EFFECT_GAINED then
            if self.bStartTorturerCD then
                self.bStartTorturerCD = false
                alerts:showAction("KILL Torturer!")
            end
            -- Phase 4.3: UpdateTorturerIcon(name, feeding) — needs LibUnitTracker
        elseif result == ACTION_RESULT_EFFECT_FADED then
            self.bStartTorturerCD = true
        end
        return
    end
    -- Prisoner saved — decrement torturer count
    if abilityId == FALGRAVN_SACRIFICE then
        self.torturerCount = self.torturerCount - 1
        -- Phase 4.3: UpdateTorturerIcon(name, saved) — needs LibUnitTracker
        return
    end
    -- Torturer coming down
    if abilityId == FALGRAVN_TORTURER_ESC and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Torturer Comes Down!")
        return
    end
    -- Torturer light attack — only alert non-tanks when they are targeted
    if abilityId == FALGRAVN_TORTURER_LA and result == ACTION_RESULT_BEGIN then
        if IsUnitPlayer(unitTag) and GetSelectedLFGRole() ~= LFG_ROLE_TANK then
            alerts:showAction("DODGE! (Torturer LA)")
        end
        return
    end
end

-- ── Effect change handler ─────────────────────────────────────────────────

function Falgravn:onEffectChanged(context, alerts, changeType, abilityId, unitTag, unitId, unitName)
    -- Prison debuff on a player: kill-countdown alert + OSI icon (Phase 4.3)
    if abilityId == FALGRAVN_PRISON then
        if changeType == EFFECT_RESULT_GAINED then
            alerts:showAction("KILL PRISON!")
            -- Phase 4.3: OSI.SetMechanicIconForUnit(displayName, ICON_PRISON, ...)
        end
        -- Phase 4.3: on FADED → OSI.RemoveMechanicIconForUnit(displayName)
        return
    end

    -- Instability icon on affected players (OSI only — Phase 4.3)
    if abilityId == FALGRAVN_INSTABILITY or abilityId == FALGRAVN_INSTABILITY2 then
        -- Phase 4.3: GAINED → OSI.SetMechanicIconForUnit(displayName, ICON_LBOLT, ...)
        --            FADED  → OSI.RemoveMechanicIconForUnit(displayName)
        return
    end

    -- Prisoner stack tracking — 11 stacks means that torturer's prisoner is lost
    if abilityId == FALGRAVN_PRISONER_F and changeType == EFFECT_RESULT_GAINED then
        local name = zo_strformat("<<1>>", unitName)
        if PRISONERS[name] ~= nil then
            PRISONERS[name] = PRISONERS[name] + 1
            if PRISONERS[name] == 11 then
                self.torturerCount = self.torturerCount - 1
                -- Phase 4.3: UpdateTorturerIcon(name, dead) — needs LibUnitTracker
            end
        end
        return
    end

    -- Execration synergy icon on player (OSI only — Phase 4.3)
    if abilityId == FALGRAVN_BLOPSYNERGIE then
        -- Phase 4.3: GAINED → OSI.SetMechanicIconForUnit(...)
        --            FADED  → OSI.RemoveMechanicIconForUnit(...)
        return
    end
end

return Falgravn
