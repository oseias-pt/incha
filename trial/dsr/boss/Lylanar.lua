--- Lylanar (& Turlassil)  -  Dreadsail Reef boss 1

local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local DreadsailCommon = require("trial.dsr.DreadsailCommon")
local DebuffTracker   = require("lib.DebuffTracker")
local Lang            = require("core.Lang")
local Fmt             = require("core.Fmt")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Colors          = require("core.Colors")

-- -- Ability IDs  -  Fire (Lylanar) ------------------------------------------
local CINDER_SURGE         = 166693
local IMMINENT_BLISTER     = 168525
local BLISTERING_FRAGILITY = 166525
local FIREBRAND            = 166472
local BROILING_HEW         = 167273
local TORRID_CLEAVE        = 167298
local SCALDING_SWELL       = 169587
local CHARRED_CONSTRICTION = 167466
local MAGMA_SPIKE          = 168646
local INCENDIARY_AXE       = 168817
local LYLANAR_MULTILOC     = 166909
local DESTRUCTIVE_EMBER    = 166210
local SUMMON_FLAME_HOUND   = 169317

-- -- Ability IDs  -  Ice (Turlassil) -----------------------------------------
local NUMBING_SHARDS       = 166735
local IMMINENT_CHILL       = 168526
local CHILLING_FRAGILITY   = 166529
local FROSTBRAND           = 166482
local STINGING_SHEAR       = 167280
local BRISK_RIP            = 167290
local BITING_BILLOW        = 169594
local FRIGIDARIUM          = 167545
local GLACIAL_SPIKE        = 168632
local CALAMITOUS_SWORD     = 168912
local TURLASSIL_MULTILOC   = 166745
local PIERCING_HAILSTONE   = 166192
local SUMMON_FROST_HOUND   = 169313

-- -- Ability IDs  -  Shared --------------------------------------------------
local HINDERED             = 165972

-- -- Timing constants --------------------------------------------------------
local FRAGILITY_DUR  = 20
local SPIKE_DUR      = 6.5
local WEAPON_CD      = 40
local BRAND_DEDUP    = 1.0
local BUBBLE_CD_NORM = 15
local BUBBLE_CD_HM   = 20

local FALLBACK_HEAVY_DUR = 1500

-- Tracker-row strings built once at load.  The 200 ms display loop reads
-- these (and the per-instance caches below) and never calls Fmt.c / Lang.t.
local _STR_FIRE_FRAGILITY = Fmt.c(Fmt.FIRE,  Lang.t("dsr_lylanar_fire_fragility"))
local _STR_ICE_FRAGILITY  = Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_ice_fragility"))
local _STR_NEED_FIRE_DOME = Fmt.c(Fmt.FIRE,  Lang.t("dsr_lylanar_need_fire_dome"))
local _STR_NEED_ICE_DOME  = Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_need_ice_dome"))
local _STR_AXE            = Fmt.c(Fmt.FIRE,  Lang.t("dsr_lylanar_axe"))
local _STR_AXE_INC        = _STR_AXE .. " " .. Fmt.c(Fmt.RED, Lang.t("common_inc"))
local _STR_DROP           = " " .. Fmt.c(Fmt.RED, Lang.t("dsr_lylanar_drop"))
local _STR_SWORD_PFX      = Lang.t("dsr_lylanar_sword")
local _STR_IMM_BLISTER    = Lang.t("dsr_lylanar_imm_blister")
local _STR_IMM_CHILL      = Lang.t("dsr_lylanar_imm_chill")
local FIRE_EMOJI          = "\xf0\x9f\x94\xa5 "
local ICE_EMOJI           = "\xe2\x9d\x84 "

-- Bubble row text ("🔥 Name  -  N stacks") is rebuilt by the stack handlers,
-- not per tick.  `drop` is the same text with the DROP! tag appended.
local function buildBubbleText(color, emoji, name, stacks)
    local suffix = Lang.t(stacks ~= 1 and "dsr_lylanar_ember_suffix_p" or "dsr_lylanar_ember_suffix", stacks)
    local base   = Fmt.c(color, emoji .. (name or "?")) .. suffix
    return base, base .. _STR_DROP
end

local Lylanar = {}
Lylanar.__index = Lylanar

Lylanar.key          = "lylanar"
Lylanar.name         = "Lylanar"
Lylanar.nameAliases  = { "Turlassil" }
-- Health-pool threshold between NM and HM; re-verify after major patches.
Lylanar.hmHealthThreshold = 100000001

Lylanar.stateSchema = {
    cinderSurgeActive      = false,
    fireImminent           = function() return DebuffTracker.new(10) end,
    fireFragility          = function() return DebuffTracker.new(FRAGILITY_DUR) end,
    lastMagmaSpike         = 0,
    lastIncendiaryAxe      = 0,
    destructiveEmberStacks = 0,
    lastDestructiveEmber   = 0,
    destructiveEmberName   = false,
    _fireBubbleStr         = false,   -- cached row-1 text (see buildBubbleText)
    _fireBubbleDropStr     = false,
    _fireImminentStr       = false,   -- cached "Imminent Blister (name)"
    firebrandTracker       = function() return {} end,
    lastBrandMatchFire     = 0,
    flameHounds            = 0,
    numbingShardsActive    = false,
    iceImminent            = function() return DebuffTracker.new(10) end,
    iceFragility           = function() return DebuffTracker.new(FRAGILITY_DUR) end,
    lastGlacialSpike       = 0,
    lastCalamitousSword    = 0,
    piercingHailstacks     = 0,
    lastPiercingHail       = 0,
    piercingHailName       = false,
    _iceBubbleStr          = false,   -- cached row-2 text (see buildBubbleText)
    _iceBubbleDropStr      = false,
    _iceImminentStr        = false,   -- cached "Imminent Chill (name)"
    _swordSec              = -1,      -- whole second the cached sword strings were built for
    _axeRowStr             = false,   -- "Axe  Sword: Ns" for the current second
    _axeRowIncStr          = false,
    frostbrandTracker      = function() return {} end,
    lastBrandMatchIce      = 0,
    frostHounds            = 0,
    lastBrandMatch         = 0,
}

function Lylanar.new()
    return BossBase.fromSchema(Lylanar)
end

-- -- Brand matching (HM) ---------------------------------------------------
local function matchBrands(self)
    local now = GetGameTimeMilliseconds() / 1000
    if now - self.lastBrandMatch < BRAND_DEDUP then return end
    self.lastBrandMatch = now

    local fire  = self.firebrandTracker
    local frost = self.frostbrandTracker

    if #fire < 2 or #frost < 2 then return end

    local myFire, myFrost = nil, nil
    for i, entry in ipairs(fire) do
        if AreUnitsEqual("player", entry.tag or "") then myFire = i end
    end
    for i, entry in ipairs(frost) do
        if AreUnitsEqual("player", entry.tag or "") then myFrost = i end
    end

    local partner, distance
    if myFire then
        partner  = frost[myFire] and frost[myFire].name or "?"
        distance = (myFire == 1) and "far" or "close"
    elseif myFrost then
        partner  = fire[myFrost] and fire[myFrost].name or "?"
        distance = (myFrost == 1) and "far" or "close"
    else
        return
    end

    CA.alert(nil,
        "STACK ON: " .. partner .. " (" .. distance .. ")",
        0xFF8800D9, SOUNDS.DUEL_START, 6000)
    PlaySound(SOUNDS.DUEL_START)
end

-- -- Handlers: beginCast ----------------------------------------------------

local function handleBroilingHew(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleTorridCleave(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    alerts:showAction(Lang.t("dsr_lylanar_dodge_cleave"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.FIRE)
end

local function handleScaldingSwell(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FIRE, "Fire wave") .. "  -  move!", 0xFF5733D9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 5500)
end

local function handleCharredConstriction(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FIRE, "Fire jump!") .. " (spike  -  block)", 0xFF5733D9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

local function handleMagmaSpike(boss, ctx, alerts, abilityId, ...)
    boss.lastMagmaSpike = GetGameTimeMilliseconds() / 1000
end

local function handleIncendiaryAxe(boss, ctx, alerts, abilityId, ...)
    if ctx.isHM then
        boss.lastIncendiaryAxe = GetGameTimeMilliseconds() / 1000
    end
end

local function handleStingingShear(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    CA.melee(abilityId, sourceUnitName, dur, Colors.FROST)
end

local function handleBriskRip(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    local dur = CastDur.get(abilityId, FALLBACK_HEAVY_DUR)
    alerts:showAction(Lang.t("dsr_lylanar_dodge_cleave"))
    CA.melee(abilityId, sourceUnitName, dur, Colors.FROST)
end

local function handleBitingBillow(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FROST, "Ice wave") .. "  -  move!", 0x99CCffD9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 5500)
end

local function handleFrigidarium(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FROST, "Ice jump!") .. " (spike  -  block)", 0x99CCffD9,
        SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
end

local function handleGlacialSpike(boss, ctx, alerts, abilityId, ...)
    boss.lastGlacialSpike = GetGameTimeMilliseconds() / 1000
end

local function handleCalamitousSword(boss, ctx, alerts, abilityId, ...)
    if ctx.isHM then
        boss.lastCalamitousSword = GetGameTimeMilliseconds() / 1000
    end
end

-- -- Handlers: effectChanged ------------------------------------------------
-- effectChanged sig: (boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)

local function handleCinderSurgeGained(boss, ctx, alerts, abilityId, ...)
    boss.cinderSurgeActive = true
    boss:after(500, function()
        if boss.cinderSurgeActive then
            CA.alert(nil, Fmt.c(Fmt.FIRE, "INTERRUPT!") .. " (Ice Dome)",
                0xFF2020D9, SOUNDS.DUEL_START, 15000)
            PlaySound(SOUNDS.DUEL_START)
        end
    end)
end

local function handleCinderSurgeFaded(boss, ctx, alerts, abilityId, ...)
    boss.cinderSurgeActive = false
end

local function handleNumbingShardsGained(boss, ctx, alerts, abilityId, ...)
    boss.numbingShardsActive = true
    boss:after(500, function()
        if boss.numbingShardsActive then
            CA.alert(nil, Fmt.c(Fmt.FROST, "INTERRUPT!") .. " (Fire Dome)",
                0x2020FFD9, SOUNDS.DUEL_START, 15000)
            PlaySound(SOUNDS.DUEL_START)
        end
    end)
end

local function handleNumbingShardsFaded(boss, ctx, alerts, abilityId, ...)
    boss.numbingShardsActive = false
end

local function handleImminentBlisterGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    local _, isHeal, isTank = GetPlayerRoles()
    if isTank or isHeal then
        local name = GetUnitDisplayName(unitTag) or unitName
        boss.fireImminent:start(name)
        boss._fireImminentStr = Fmt.c(Fmt.FIRE, _STR_IMM_BLISTER .. " (" .. (name or "?") .. ")")
    end
end

local function handleImminentBlisterFaded(boss, ctx, alerts, abilityId, ...)
    boss.fireImminent:clear()
end

local function handleImminentChillGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    local _, isHeal, isTank = GetPlayerRoles()
    if isTank or isHeal then
        local name = GetUnitDisplayName(unitTag) or unitName
        boss.iceImminent:start(name)
        boss._iceImminentStr = Fmt.c(Fmt.FROST, _STR_IMM_CHILL .. " (" .. (name or "?") .. ")")
    end
end

local function handleImminentChillFaded(boss, ctx, alerts, abilityId, ...)
    boss.iceImminent:clear()
end

local function handleBlisteringFragilityGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.fireFragility:start(GetUnitDisplayName(unitTag) or unitName)
    end
end

local function handleBlisteringFragilityFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.fireFragility:clear()
    end
end

local function handleChillingFragilityGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.iceFragility:start(GetUnitDisplayName(unitTag) or unitName)
    end
end

local function handleChillingFragilityFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.iceFragility:clear()
    end
end

-- DestructiveEmber: GAINED and UPDATED share the same body (stack count
-- changed → rebuild the cached row text once, here, not per tick).
local function applyDestructiveEmber(boss, unitName, unitTag, stackCount)
    boss.destructiveEmberStacks = stackCount or 1
    boss.destructiveEmberName   = GetUnitDisplayName(unitTag) or unitName
    boss.lastDestructiveEmber   = GetGameTimeMilliseconds() / 1000
    boss._fireBubbleStr, boss._fireBubbleDropStr =
        buildBubbleText(Fmt.FIRE, FIRE_EMOJI, boss.destructiveEmberName, boss.destructiveEmberStacks)
end

local function handleDestructiveEmberGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        applyDestructiveEmber(boss, unitName, unitTag, stackCount)
    end
end

local function handleDestructiveEmberUpdated(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        applyDestructiveEmber(boss, unitName, unitTag, stackCount)
    end
end

local function handleDestructiveEmberFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.destructiveEmberStacks = 0
        boss.destructiveEmberName   = false
        boss.lastDestructiveEmber   = 0
        boss._fireBubbleStr         = false
        boss._fireBubbleDropStr     = false
    end
end

-- PiercingHailstone: same 3-way split
local function applyPiercingHail(boss, unitName, unitTag, stackCount)
    boss.piercingHailstacks = stackCount or 1
    boss.piercingHailName   = GetUnitDisplayName(unitTag) or unitName
    boss.lastPiercingHail   = GetGameTimeMilliseconds() / 1000
    boss._iceBubbleStr, boss._iceBubbleDropStr =
        buildBubbleText(Fmt.FROST, ICE_EMOJI, boss.piercingHailName, boss.piercingHailstacks)
end

local function handlePiercingHailstoneGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        applyPiercingHail(boss, unitName, unitTag, stackCount)
    end
end

local function handlePiercingHailstoneUpdated(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        applyPiercingHail(boss, unitName, unitTag, stackCount)
    end
end

local function handlePiercingHailstoneFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.piercingHailstacks = 0
        boss.piercingHailName   = false
        boss.lastPiercingHail   = 0
        boss._iceBubbleStr      = false
        boss._iceBubbleDropStr  = false
    end
end

-- Firebrand: GAINED only (already guards in old code)
local function handleFirebrandGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not ctx.isHM then return end
    local entry = { tag = unitTag, name = GetUnitDisplayName(unitTag) or unitName }
    table.insert(boss.firebrandTracker, entry)
    if #boss.firebrandTracker >= 2 and #boss.frostbrandTracker >= 2 then
        matchBrands(boss)
        boss.firebrandTracker  = {}
        boss.frostbrandTracker = {}
    end
end

-- Frostbrand: GAINED only
local function handleFrostbrandGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if not ctx.isHM then return end
    local entry = { tag = unitTag, name = GetUnitDisplayName(unitTag) or unitName }
    table.insert(boss.frostbrandTracker, entry)
    if #boss.firebrandTracker >= 2 and #boss.frostbrandTracker >= 2 then
        matchBrands(boss)
        boss.firebrandTracker  = {}
        boss.frostbrandTracker = {}
    end
end

-- MultiLoc: GAINED only
local function handleLylanarMultilocGained(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FIRE, "Lylanar teleports") .. "  -  reposition!",
        0xFF5733D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 4000)
end

local function handleTurlassilMultilocGained(boss, ctx, alerts, abilityId, ...)
    CA.alert(nil, Fmt.c(Fmt.FROST, "Turlassil teleports") .. "  -  reposition!",
        0x99CCffD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 4000)
end

local function handleSummonFlameHoundGained(boss, ctx, alerts, abilityId, ...)
    boss.flameHounds = boss.flameHounds + 1
end

local function handleSummonFlameHoundFaded(boss, ctx, alerts, abilityId, ...)
    if boss.flameHounds > 0 then boss.flameHounds = boss.flameHounds - 1 end
end

local function handleSummonFrostHoundGained(boss, ctx, alerts, abilityId, ...)
    boss.frostHounds = boss.frostHounds + 1
end

local function handleSummonFrostHoundFaded(boss, ctx, alerts, abilityId, ...)
    if boss.frostHounds > 0 then boss.frostHounds = boss.frostHounds - 1 end
end

-- Hindered (local: GAINED + player → yellow border 12 s)
local function handleHinderedGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        CA.border(true, 12000, "yellow")
    end
end

-- -- Event tables ------------------------------------------------------------

local _beginCastEntry = {}
for k, v in pairs(DreadsailCommon.beginCastEntries) do _beginCastEntry[k] = v end
_beginCastEntry[BROILING_HEW]        = { type = AlertTypes.CUSTOM, fn = handleBroilingHew }
_beginCastEntry[TORRID_CLEAVE]       = { type = AlertTypes.CUSTOM, fn = handleTorridCleave }
_beginCastEntry[SCALDING_SWELL]      = { type = AlertTypes.CUSTOM, fn = handleScaldingSwell }
_beginCastEntry[CHARRED_CONSTRICTION]= { type = AlertTypes.CUSTOM, fn = handleCharredConstriction }
_beginCastEntry[MAGMA_SPIKE]         = { type = AlertTypes.CUSTOM, fn = handleMagmaSpike }
_beginCastEntry[INCENDIARY_AXE]      = { type = AlertTypes.CUSTOM, fn = handleIncendiaryAxe }
_beginCastEntry[STINGING_SHEAR]      = { type = AlertTypes.CUSTOM, fn = handleStingingShear }
_beginCastEntry[BRISK_RIP]           = { type = AlertTypes.CUSTOM, fn = handleBriskRip }
_beginCastEntry[BITING_BILLOW]       = { type = AlertTypes.CUSTOM, fn = handleBitingBillow }
_beginCastEntry[FRIGIDARIUM]         = { type = AlertTypes.CUSTOM, fn = handleFrigidarium }
_beginCastEntry[GLACIAL_SPIKE]       = { type = AlertTypes.CUSTOM, fn = handleGlacialSpike }
_beginCastEntry[CALAMITOUS_SWORD]    = { type = AlertTypes.CUSTOM, fn = handleCalamitousSword }

local _effectGainedEntry = {}
for k, v in pairs(DreadsailCommon.effectChangedEntries.gained) do _effectGainedEntry[k] = v end
_effectGainedEntry[CINDER_SURGE]         = { type = AlertTypes.CUSTOM, fn = handleCinderSurgeGained }
_effectGainedEntry[NUMBING_SHARDS]       = { type = AlertTypes.CUSTOM, fn = handleNumbingShardsGained }
_effectGainedEntry[IMMINENT_BLISTER]     = { type = AlertTypes.CUSTOM, fn = handleImminentBlisterGained }
_effectGainedEntry[IMMINENT_CHILL]       = { type = AlertTypes.CUSTOM, fn = handleImminentChillGained }
_effectGainedEntry[BLISTERING_FRAGILITY] = { type = AlertTypes.CUSTOM, fn = handleBlisteringFragilityGained }
_effectGainedEntry[CHILLING_FRAGILITY]   = { type = AlertTypes.CUSTOM, fn = handleChillingFragilityGained }
_effectGainedEntry[DESTRUCTIVE_EMBER]    = { type = AlertTypes.CUSTOM, fn = handleDestructiveEmberGained }
_effectGainedEntry[PIERCING_HAILSTONE]   = { type = AlertTypes.CUSTOM, fn = handlePiercingHailstoneGained }
_effectGainedEntry[FIREBRAND]            = { type = AlertTypes.CUSTOM, fn = handleFirebrandGained }
_effectGainedEntry[FROSTBRAND]           = { type = AlertTypes.CUSTOM, fn = handleFrostbrandGained }
_effectGainedEntry[LYLANAR_MULTILOC]     = { type = AlertTypes.CUSTOM, fn = handleLylanarMultilocGained }
_effectGainedEntry[TURLASSIL_MULTILOC]   = { type = AlertTypes.CUSTOM, fn = handleTurlassilMultilocGained }
_effectGainedEntry[SUMMON_FLAME_HOUND]   = { type = AlertTypes.CUSTOM, fn = handleSummonFlameHoundGained }
_effectGainedEntry[SUMMON_FROST_HOUND]   = { type = AlertTypes.CUSTOM, fn = handleSummonFrostHoundGained }
_effectGainedEntry[HINDERED]             = { type = AlertTypes.CUSTOM, fn = handleHinderedGained }

local _effectFadedEntry = {}
for k, v in pairs(DreadsailCommon.effectChangedEntries.faded) do _effectFadedEntry[k] = v end
_effectFadedEntry[CINDER_SURGE]         = { type = AlertTypes.CUSTOM, fn = handleCinderSurgeFaded }
_effectFadedEntry[NUMBING_SHARDS]       = { type = AlertTypes.CUSTOM, fn = handleNumbingShardsFaded }
_effectFadedEntry[IMMINENT_BLISTER]     = { type = AlertTypes.CUSTOM, fn = handleImminentBlisterFaded }
_effectFadedEntry[IMMINENT_CHILL]       = { type = AlertTypes.CUSTOM, fn = handleImminentChillFaded }
_effectFadedEntry[BLISTERING_FRAGILITY] = { type = AlertTypes.CUSTOM, fn = handleBlisteringFragilityFaded }
_effectFadedEntry[CHILLING_FRAGILITY]   = { type = AlertTypes.CUSTOM, fn = handleChillingFragilityFaded }
_effectFadedEntry[DESTRUCTIVE_EMBER]    = { type = AlertTypes.CUSTOM, fn = handleDestructiveEmberFaded }
_effectFadedEntry[PIERCING_HAILSTONE]   = { type = AlertTypes.CUSTOM, fn = handlePiercingHailstoneFaded }
_effectFadedEntry[SUMMON_FLAME_HOUND]   = { type = AlertTypes.CUSTOM, fn = handleSummonFlameHoundFaded }
_effectFadedEntry[SUMMON_FROST_HOUND]   = { type = AlertTypes.CUSTOM, fn = handleSummonFrostHoundFaded }

local _effectUpdatedEntry = {
    [DESTRUCTIVE_EMBER]  = { type = AlertTypes.CUSTOM, fn = handleDestructiveEmberUpdated },
    [PIERCING_HAILSTONE] = { type = AlertTypes.CUSTOM, fn = handlePiercingHailstoneUpdated },
}

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

Lylanar.events = {
    beginCast     = { instant = _beginCastInstant, started = _beginCastStarted },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = _effectUpdatedEntry },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

-- -- Info-line renderers ---------------------------------------------------

local function showFireBubbleLine(self, alerts, now, isHM)
    if self.lastDestructiveEmber > 0 and self._fireBubbleStr then
        local cd = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T  = cd - (now - self.lastDestructiveEmber)
        if T > 0 then
            alerts:setRow(1, self._fireBubbleStr, T)
        else
            alerts:setRow(1, self._fireBubbleDropStr, nil)
        end
    else
        alerts:clearRow(1)
    end
end

local function showIceBubbleLine(self, alerts, now, isHM)
    if self.lastPiercingHail > 0 and self._iceBubbleStr then
        local cd = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T  = cd - (now - self.lastPiercingHail)
        if T > 0 then
            alerts:setRow(2, self._iceBubbleStr, T)
        else
            alerts:setRow(2, self._iceBubbleDropStr, nil)
        end
    else
        alerts:clearRow(2)
    end
end

local function showFragilityLine(self, alerts, now)
    local fireT = self.fireFragility:remainingAt(now)
    local iceT  = self.iceFragility:remainingAt(now)
    if fireT > 0 then
        alerts:setRow(3, _STR_FIRE_FRAGILITY, fireT)
    elseif iceT > 0 then
        alerts:setRow(3, _STR_ICE_FRAGILITY, iceT)
    else
        alerts:clearRow(3)
    end
end

-- "Axe  Sword: Ns" changes once per second; rebuild the two row variants
-- only when the displayed sword second changes.
local function axeRowStrings(self, now)
    local sec = 0
    if self.lastCalamitousSword > 0 then
        sec = math.ceil(math.max(0, WEAPON_CD - (now - self.lastCalamitousSword)))
    end
    if sec ~= self._swordSec then
        self._swordSec = sec
        if sec > 0 then
            local swordPart = Fmt.c(Fmt.FROST, _STR_SWORD_PFX .. sec .. "s")
            self._axeRowStr    = _STR_AXE .. swordPart
            self._axeRowIncStr = _STR_AXE_INC .. swordPart
        else
            self._axeRowStr    = _STR_AXE
            self._axeRowIncStr = _STR_AXE_INC
        end
    end
    return self._axeRowStr, self._axeRowIncStr
end

local function showSpikeLine(self, alerts, now, isHM)
    local fireSpikeT = (self.lastMagmaSpike   > 0) and (SPIKE_DUR - (now - self.lastMagmaSpike))   or -1
    local iceSpikeT  = (self.lastGlacialSpike > 0) and (SPIKE_DUR - (now - self.lastGlacialSpike)) or -1

    if fireSpikeT > 0 then
        alerts:setRow(4, _STR_NEED_FIRE_DOME, fireSpikeT)
    elseif iceSpikeT > 0 then
        alerts:setRow(4, _STR_NEED_ICE_DOME, iceSpikeT)
    elseif isHM and self.lastIncendiaryAxe > 0 then
        local T = WEAPON_CD - (now - self.lastIncendiaryAxe)
        local axeStr, axeIncStr = axeRowStrings(self, now)
        if T > 0 then
            alerts:setRow(4, axeStr, T)
        else
            alerts:setRow(4, axeIncStr, nil)
        end
    else
        local fireImminT = self.fireImminent:remainingAt(now)
        local iceImminT  = self.iceImminent:remainingAt(now)
        if fireImminT > 0 and self._fireImminentStr then
            alerts:setRow(4, self._fireImminentStr, fireImminT)
        elseif iceImminT > 0 and self._iceImminentStr then
            alerts:setRow(4, self._iceImminentStr, iceImminT)
        else
            alerts:clearRow(4)
        end
    end
end

function Lylanar:onWipe(context, alerts)
    -- Every per-pull field lives in stateSchema (timers, trackers, caches),
    -- so the schema reset is the whole soft reset.
    BossBase.resetSchema(self, Lylanar)
    CA.border(false, 0, "yellow")
end

function Lylanar:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showFireBubbleLine(self, alerts, now, isHM)
    showIceBubbleLine(self, alerts, now, isHM)
    showFragilityLine(self, alerts, now)
    showSpikeLine(self, alerts, now, isHM)
end

EventDispatcher.build(Lylanar)

package.loaded["trial.dsr.boss.Lylanar"] = Lylanar
return Lylanar
