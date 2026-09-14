--- ReefGuardian  -  Dreadsail Reef boss 2

local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local DreadsailCommon = require("trial.dsr.DreadsailCommon")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local Colors          = require("core.Colors")

-- -- Ability IDs -----------------------------------------------------------
local BUILDING_STATIC_1    = 163575
local BUILDING_STATIC_2    = 169688
local VOLATILE_RESIDUE_1   = 174835
local VOLATILE_RESIDUE_2   = 174932
local SHELTERED            = 163571
local HEARTBURN            = 163692
local HEARTBURN_EFFECT     = 166036
local ACID_REFLUX          = 163702
local CRAB_MONSTROUS_CLAW  = 166582
local CRAB_SWIPE           = 166584
local CRAB_HEAVY_3         = 166585
local CRUSH                = 166019
local CLAW_ATTACK          = 166020
local CRACKDOWN            = 166586
local KING_ORGNUM_FIRE_DBF = 175832
local ACIDIC_VULN          = 174659
local REPLICATION          = 163701

-- -- Timing constants --------------------------------------------------------
local PORTAL_WIPE_TIME = 60
local ACID_INTERVAL    = 1750
local ACID_COUNT       = 5
local SHELTERED_WINDOW = 3

local ACT_ACID     = { 8000, "MOVE OUT!", 0.3, 0.9, 0.1, 0.9, nil }
local FALLBACK_DUR = 1500

-- Tracker-row strings built once at load; the 200 ms loop reads these and
-- the per-instance stack caches below, and never calls Fmt.c / Lang.t.
local _STR_ELEC_CLEANSED   = Fmt.c(Fmt.GOLD,   Lang.t("dsr_reef_elec_cleansed"))
local _STR_POISON_CLEANSED = Fmt.c(Fmt.POISON, Lang.t("dsr_reef_poison_cleansed"))
local _STR_ACIDIC_VULN     = Fmt.c(Fmt.ORANGE, Lang.t("dsr_reef_acidic_vuln"))
local _STR_WARN            = " " .. Fmt.c(Fmt.RED, "!")
local _STR_ELEC_PFX        = Lang.t("dsr_reef_elec_label")
local _STR_POISON_PFX      = Lang.t("dsr_reef_poison_label")

-- "Reef N" labels, gold and red variants, filled lazily per reef index
-- (bounded by the number of portals opened in one pull).
local _REEF_LABEL_GOLD, _REEF_LABEL_RED = {}, {}
local function reefLabel(idx, urgent)
    local cache = urgent and _REEF_LABEL_RED or _REEF_LABEL_GOLD
    local s = cache[idx]
    if not s then
        s = Fmt.c(urgent and Fmt.RED or Fmt.GOLD, Lang.t("dsr_reef_reef_timer", idx))
        cache[idx] = s
    end
    return s
end

-- "⚡ N stacks !" row text, rebuilt by the stack handlers rather than per tick.
local function stackText(prefix, stacks)
    local s = prefix .. Lang.t(stacks ~= 1 and "dsr_reef_stack_p" or "dsr_reef_stack", stacks)
    return (stacks >= 7) and (s .. _STR_WARN) or s
end

local ReefGuardian = {}
ReefGuardian.__index = ReefGuardian

ReefGuardian.key               = "reef_guardian"
ReefGuardian.name              = "Reef Guardian"
-- Health-pool threshold between NM and HM; re-verify after major patches.
ReefGuardian.hmHealthThreshold = 100000001

ReefGuardian.stateSchema = {
    buildingStaticStacks   = 0,
    buildingStaticEndTime  = 0,
    _elecStr               = false,   -- cached row-1 stack text (see stackText)
    volatileResidueStacks  = 0,
    volatileResidueEndTime = 0,
    _poisonStr             = false,   -- cached row-2 stack text
    playerSheltered        = false,
    lastShelteredTime      = 0,
    reefPortals   = function() return {} end,
    reefNum       = 0,
    acidicVulnLast  = 0,
    acidRefluxBarId = false,
}

function ReefGuardian.new()
    return BossBase.fromSchema(ReefGuardian)
end

function ReefGuardian:onLeave(context)
    CA.castAlertsStop(self.acidRefluxBarId)
    self.acidRefluxBarId = false
end

-- -- Handlers: beginCast -------------------------------------------------------

local function handleHeavy(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleHeartburn(boss, ctx, alerts, abilityId, ...)
    boss.reefNum = boss.reefNum + 1
    local idx = boss.reefNum
    boss.reefPortals[idx] = { openTime = GetGameTimeMilliseconds() / 1000,
                               wipeActive = false }
    CA.alert(nil, "Reef " .. idx .. ": OPEN  -  60 s!",
        0xFFD700D9, SOUNDS.DUEL_START, 5000)
    PlaySound(SOUNDS.DUEL_START)
end

local function handleAcidReflux(boss, ctx, alerts, abilityId, ...)
    CA.castAlertsStop(boss.acidRefluxBarId)
    boss.acidRefluxBarId = CA.bar(
        abilityId, "Acid Reflux", 10000, 10000, Colors.POISON, 0.5, ACT_ACID)
    for i = 1, ACID_COUNT do
        boss:after(i * ACID_INTERVAL, function()
            CA.alert(nil,
                "Acid pool " .. i .. "/" .. ACID_COUNT .. "  -  MOVE!",
                0x44DD22D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 1500)
        end)
    end
end

local function handleReplication(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, "Replication!", 0xFF8800D9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 3000)
end

-- -- Handlers: effectChanged --------------------------------------------------
-- effectChanged sig: (boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)

-- Building Static: GAINED and UPDATED share body; FADED clears.  The row
-- text is rebuilt here, on the (rare) stack change, not on every tick.
local function applyBuildingStatic(boss, stackCount)
    boss.buildingStaticStacks  = stackCount or 1
    boss.buildingStaticEndTime = GetGameTimeMilliseconds() / 1000 + 10
    boss._elecStr              = stackText(_STR_ELEC_PFX, boss.buildingStaticStacks)
end

local function handleBuildingStaticGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then applyBuildingStatic(boss, stackCount) end
end

local function handleBuildingStaticUpdated(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then applyBuildingStatic(boss, stackCount) end
end

local function handleBuildingStaticFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.buildingStaticStacks  = 0
        boss.buildingStaticEndTime = 0
        boss._elecStr              = false
    end
end

-- Volatile Residue: same pattern
local function applyVolatileResidue(boss, stackCount)
    boss.volatileResidueStacks  = stackCount or 1
    boss.volatileResidueEndTime = GetGameTimeMilliseconds() / 1000 + 10
    boss._poisonStr             = stackText(_STR_POISON_PFX, boss.volatileResidueStacks)
end

local function handleVolatileResidueGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then applyVolatileResidue(boss, stackCount) end
end

local function handleVolatileResidueUpdated(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then applyVolatileResidue(boss, stackCount) end
end

local function handleVolatileResidueFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.volatileResidueStacks  = 0
        boss.volatileResidueEndTime = 0
        boss._poisonStr             = false
    end
end

local function handleShelteredGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not AreUnitsEqual("player", unitTag) then return end
    boss.playerSheltered       = true
    boss.lastShelteredTime     = GetGameTimeMilliseconds() / 1000
    boss.buildingStaticStacks  = 0
    boss.volatileResidueStacks = 0
    boss._elecStr              = false
    boss._poisonStr            = false
end

local function handleShelteredFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.playerSheltered = false
    end
end

-- HeartburnEffect: GAINED only (was { changeType = EFFECT_RESULT_GAINED } in old code)
local function handleHeartburnEffect(boss, ctx, alerts, abilityId, ...)
    local now = GetGameTimeMilliseconds() / 1000
    for i = boss.reefNum, 1, -1 do
        local reef = boss.reefPortals[i]
        if reef and not reef.wipeActive and (now - reef.openTime) < 5 then
            reef.wipeActive = true
            reef.wipeStart  = now
            break
        end
    end
end

local function handleKingOrgnumFireDbfGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        CA.alert(nil, Fmt.c("FF5500", "King Orgnum fire  -  MOVE!"),
            0xFF5500D9, SOUNDS.DUEL_START, 5000)
    end
end

local function handleAcidicVulnGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.acidicVulnLast = GetGameTimeMilliseconds() / 1000
    end
end

local function handleAcidicVulnFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.acidicVulnLast = 0
    end
end

-- -- Event tables ------------------------------------------------------------

local _beginCastEntry = {}
for k, v in pairs(DreadsailCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[HEARTBURN]           = { type = AlertTypes.CUSTOM, fn = handleHeartburn }
_beginCastEntry[ACID_REFLUX]         = { type = AlertTypes.CUSTOM, fn = handleAcidReflux }
_beginCastEntry[REPLICATION]         = { type = AlertTypes.CUSTOM, fn = handleReplication }
_beginCastEntry[CRAB_MONSTROUS_CLAW] = { type = AlertTypes.CUSTOM, fn = handleHeavy }
_beginCastEntry[CRAB_SWIPE]          = { type = AlertTypes.CUSTOM, fn = handleHeavy }
_beginCastEntry[CRAB_HEAVY_3]        = { type = AlertTypes.CUSTOM, fn = handleHeavy }
_beginCastEntry[CRUSH]               = { type = AlertTypes.CUSTOM, fn = handleHeavy }
_beginCastEntry[CLAW_ATTACK]         = { type = AlertTypes.CUSTOM, fn = handleHeavy }
_beginCastEntry[CRACKDOWN]           = { type = AlertTypes.CUSTOM, fn = handleHeavy }

local _effectGainedEntry = {}
for k, v in pairs(DreadsailCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
_effectGainedEntry[BUILDING_STATIC_1]    = { type = AlertTypes.CUSTOM, fn = handleBuildingStaticGained }
_effectGainedEntry[BUILDING_STATIC_2]    = { type = AlertTypes.CUSTOM, fn = handleBuildingStaticGained }
_effectGainedEntry[VOLATILE_RESIDUE_1]   = { type = AlertTypes.CUSTOM, fn = handleVolatileResidueGained }
_effectGainedEntry[VOLATILE_RESIDUE_2]   = { type = AlertTypes.CUSTOM, fn = handleVolatileResidueGained }
_effectGainedEntry[SHELTERED]            = { type = AlertTypes.CUSTOM, fn = handleShelteredGained }
_effectGainedEntry[HEARTBURN_EFFECT]     = { type = AlertTypes.CUSTOM, fn = handleHeartburnEffect }
_effectGainedEntry[KING_ORGNUM_FIRE_DBF] = { type = AlertTypes.CUSTOM, fn = handleKingOrgnumFireDbfGained }
_effectGainedEntry[ACIDIC_VULN]          = { type = AlertTypes.CUSTOM, fn = handleAcidicVulnGained }

local _effectFadedEntry = {}
for k, v in pairs(DreadsailCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end
_effectFadedEntry[BUILDING_STATIC_1]  = { type = AlertTypes.CUSTOM, fn = handleBuildingStaticFaded }
_effectFadedEntry[BUILDING_STATIC_2]  = { type = AlertTypes.CUSTOM, fn = handleBuildingStaticFaded }
_effectFadedEntry[VOLATILE_RESIDUE_1] = { type = AlertTypes.CUSTOM, fn = handleVolatileResidueFaded }
_effectFadedEntry[VOLATILE_RESIDUE_2] = { type = AlertTypes.CUSTOM, fn = handleVolatileResidueFaded }
_effectFadedEntry[SHELTERED]          = { type = AlertTypes.CUSTOM, fn = handleShelteredFaded }
_effectFadedEntry[ACIDIC_VULN]        = { type = AlertTypes.CUSTOM, fn = handleAcidicVulnFaded }

local _effectUpdatedEntry = {
    [BUILDING_STATIC_1]  = { type = AlertTypes.CUSTOM, fn = handleBuildingStaticUpdated },
    [BUILDING_STATIC_2]  = { type = AlertTypes.CUSTOM, fn = handleBuildingStaticUpdated },
    [VOLATILE_RESIDUE_1] = { type = AlertTypes.CUSTOM, fn = handleVolatileResidueUpdated },
    [VOLATILE_RESIDUE_2] = { type = AlertTypes.CUSTOM, fn = handleVolatileResidueUpdated },
}

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

ReefGuardian.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = _effectUpdatedEntry },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

-- -- Info-line renderers ---------------------------------------------------

local function showLightningStacksLine(self, alerts, now)
    if self.buildingStaticStacks > 0 and self._elecStr then
        if self.playerSheltered
           or (now - self.lastShelteredTime < SHELTERED_WINDOW) then
            alerts:setRow(1, _STR_ELEC_CLEANSED, nil)
        else
            alerts:setRow(1, self._elecStr, nil)
        end
    else
        alerts:clearRow(1)
    end
end

local function showPoisonStacksLine(self, alerts, now)
    if self.volatileResidueStacks > 0 and self._poisonStr then
        if self.playerSheltered
           or (now - self.lastShelteredTime < SHELTERED_WINDOW) then
            alerts:setRow(2, _STR_POISON_CLEANSED, nil)
        else
            alerts:setRow(2, self._poisonStr, nil)
        end
    else
        alerts:clearRow(2)
    end
end

local function showReefWipeLines(self, alerts, now)
    -- At most two wipe timers are displayed; pick them without allocating a
    -- scratch table on every tick.
    local idx1, t1, idx2, t2 = nil, nil, nil, nil
    for i = 1, self.reefNum do
        local reef = self.reefPortals[i]
        if reef and reef.wipeActive then
            local remaining = PORTAL_WIPE_TIME - (now - reef.wipeStart)
            if remaining > 0 then
                if not idx1 then
                    idx1, t1 = i, remaining
                elseif not idx2 then
                    idx2, t2 = i, remaining
                    break
                end
            else
                reef.wipeActive = false
            end
        end
    end

    if idx1 then
        alerts:setRow(3, reefLabel(idx1, t1 <= 15), t1)
    else
        alerts:clearRow(3)
    end

    if idx2 then
        alerts:setRow(4, reefLabel(idx2, t2 <= 15), t2)
    elseif self.acidicVulnLast > 0 then
        local T = 5 - (now - self.acidicVulnLast)
        if T > 0 then
            alerts:setRow(4, _STR_ACIDIC_VULN, T)
        else
            self.acidicVulnLast = 0
            alerts:clearRow(4)
        end
    else
        alerts:clearRow(4)
    end
end

function ReefGuardian:onWipe(context, alerts)
    CA.castAlertsStop(self.acidRefluxBarId)  -- stop bar before schema reset overwrites the id
    BossBase.resetSchema(self, ReefGuardian)
end

function ReefGuardian:onUpdate(context, alerts)
    local now = GetGameTimeMilliseconds() / 1000
    showLightningStacksLine(self, alerts, now)
    showPoisonStacksLine(self, alerts, now)
    showReefWipeLines(self, alerts, now)
end

EventDispatcher.build(ReefGuardian)

package.loaded["trial.dsr.boss.ReefGuardian"] = ReefGuardian
return ReefGuardian
