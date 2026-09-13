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

local Lylanar = {}
Lylanar.__index = Lylanar

Lylanar.key          = "lylanar"
Lylanar.name         = "Lylanar"
Lylanar.nameAliases  = { "Turlassil" }
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
        boss.fireImminent:start(GetUnitDisplayName(unitTag) or unitName)
    end
end

local function handleImminentBlisterFaded(boss, ctx, alerts, abilityId, ...)
    boss.fireImminent:clear()
end

local function handleImminentChillGained(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    local _, isHeal, isTank = GetPlayerRoles()
    if isTank or isHeal then
        boss.iceImminent:start(GetUnitDisplayName(unitTag) or unitName)
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

-- DestructiveEmber: GAINED and UPDATED share the same body
local function handleDestructiveEmberGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        boss.destructiveEmberStacks = stackCount or 1
        boss.destructiveEmberName   = GetUnitDisplayName(unitTag) or unitName
        boss.lastDestructiveEmber   = GetGameTimeMilliseconds() / 1000
    end
end

local function handleDestructiveEmberUpdated(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        boss.destructiveEmberStacks = stackCount or 1
        boss.destructiveEmberName   = GetUnitDisplayName(unitTag) or unitName
        boss.lastDestructiveEmber   = GetGameTimeMilliseconds() / 1000
    end
end

local function handleDestructiveEmberFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.destructiveEmberStacks = 0
        boss.destructiveEmberName   = false
        boss.lastDestructiveEmber   = 0
    end
end

-- PiercingHailstone: same 3-way split
local function handlePiercingHailstoneGained(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        boss.piercingHailstacks = stackCount or 1
        boss.piercingHailName   = GetUnitDisplayName(unitTag) or unitName
        boss.lastPiercingHail   = GetGameTimeMilliseconds() / 1000
    end
end

local function handlePiercingHailstoneUpdated(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
    if AreUnitsEqual("player", unitTag) then
        boss.piercingHailstacks = stackCount or 1
        boss.piercingHailName   = GetUnitDisplayName(unitTag) or unitName
        boss.lastPiercingHail   = GetGameTimeMilliseconds() / 1000
    end
end

local function handlePiercingHailstoneFaded(boss, ctx, alerts, abilityId, unitName, unitTag, ...)
    if AreUnitsEqual("player", unitTag) then
        boss.piercingHailstacks = 0
        boss.piercingHailName   = false
        boss.lastPiercingHail   = 0
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

Lylanar.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = _effectGainedEntry, faded = _effectFadedEntry, updated = _effectUpdatedEntry },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = {} },
}

-- -- Info-line renderers ---------------------------------------------------

local function showFireBubbleLine(self, alerts, now, isHM)
    if self.lastDestructiveEmber > 0 then
        local cd     = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T      = cd - (now - self.lastDestructiveEmber)
        local stks   = self.destructiveEmberStacks
        local name   = self.destructiveEmberName or "?"
        local suffix = stks ~= 1 and Lang.t("dsr_lylanar_ember_suffix_p", stks)
                                   or  Lang.t("dsr_lylanar_ember_suffix",   stks)
        if T > 0 then
            alerts:setRow(1, Fmt.c(Fmt.FIRE, "\xf0\x9f\x94\xa5 " .. name) .. suffix, T)
        else
            alerts:setRow(1,
                Fmt.c(Fmt.FIRE, "\xf0\x9f\x94\xa5 " .. name) .. suffix
                .. " " .. Fmt.c(Fmt.RED, Lang.t("dsr_lylanar_drop")), nil)
        end
    else
        alerts:clearRow(1)
    end
end

local function showIceBubbleLine(self, alerts, now, isHM)
    if self.lastPiercingHail > 0 then
        local cd     = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T      = cd - (now - self.lastPiercingHail)
        local stks   = self.piercingHailstacks
        local name   = self.piercingHailName or "?"
        local suffix = stks ~= 1 and Lang.t("dsr_lylanar_ember_suffix_p", stks)
                                   or  Lang.t("dsr_lylanar_ember_suffix",   stks)
        if T > 0 then
            alerts:setRow(2, Fmt.c(Fmt.FROST, "\xe2\x9d\x84 " .. name) .. suffix, T)
        else
            alerts:setRow(2,
                Fmt.c(Fmt.FROST, "\xe2\x9d\x84 " .. name) .. suffix
                .. " " .. Fmt.c(Fmt.RED, Lang.t("dsr_lylanar_drop")), nil)
        end
    else
        alerts:clearRow(2)
    end
end

local function showFragilityLine(self, alerts)
    local fireT = self.fireFragility:remaining()
    local iceT  = self.iceFragility:remaining()
    if fireT > 0 then
        alerts:setRow(3, Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_fire_fragility")), fireT)
    elseif iceT > 0 then
        alerts:setRow(3, Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_ice_fragility")), iceT)
    else
        alerts:clearRow(3)
    end
end

local function showSpikeLine(self, alerts, now, isHM)
    local fireSpikeT = (self.lastMagmaSpike   > 0) and (SPIKE_DUR - (now - self.lastMagmaSpike))   or -1
    local iceSpikeT  = (self.lastGlacialSpike > 0) and (SPIKE_DUR - (now - self.lastGlacialSpike)) or -1

    if fireSpikeT > 0 then
        alerts:setRow(4, Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_need_fire_dome")), fireSpikeT)
    elseif iceSpikeT > 0 then
        alerts:setRow(4, Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_need_ice_dome")), iceSpikeT)
    elseif isHM and self.lastIncendiaryAxe > 0 then
        local T = WEAPON_CD - (now - self.lastIncendiaryAxe)
        local swordPart = ""
        if self.lastCalamitousSword > 0 then
            swordPart = Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_sword")
                .. Fmt.timer(math.max(0, WEAPON_CD - (now - self.lastCalamitousSword))))
        end
        if T > 0 then
            alerts:setRow(4, Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_axe")) .. swordPart, T)
        else
            alerts:setRow(4,
                Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_axe")) .. " " .. Fmt.c(Fmt.RED, "INC") .. swordPart, nil)
        end
    else
        local fireImminT = self.fireImminent:remaining()
        local iceImminT  = self.iceImminent:remaining()
        if fireImminT > 0 then
            alerts:setRow(4,
                Fmt.c(Fmt.FIRE, Lang.t("dsr_lylanar_imm_blister")
                    .. " (" .. (self.fireImminent:playerName() or "?") .. ")"), fireImminT)
        elseif iceImminT > 0 then
            alerts:setRow(4,
                Fmt.c(Fmt.FROST, Lang.t("dsr_lylanar_imm_chill")
                    .. " (" .. (self.iceImminent:playerName() or "?") .. ")"), iceImminT)
        else
            alerts:clearRow(4)
        end
    end
end

function Lylanar:onWipe(context, alerts)
    self.fireImminent:clear();  self.fireFragility:clear()
    self.iceImminent:clear();   self.iceFragility:clear()
    self.cinderSurgeActive      = false
    self.lastMagmaSpike         = 0;    self.lastIncendiaryAxe    = 0
    self.destructiveEmberStacks = 0;    self.lastDestructiveEmber = 0
    self.destructiveEmberName   = false
    self.firebrandTracker       = {};   self.lastBrandMatchFire   = 0
    self.flameHounds            = 0
    self.numbingShardsActive    = false
    self.lastGlacialSpike       = 0;    self.lastCalamitousSword  = 0
    self.piercingHailstacks     = 0;    self.lastPiercingHail     = 0
    self.piercingHailName       = false
    self.frostbrandTracker      = {};   self.lastBrandMatchIce    = 0
    self.frostHounds            = 0
    self.lastBrandMatch         = 0
    CA.border(false, 0, "yellow")
end

function Lylanar:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = context.isHM
    showFireBubbleLine(self, alerts, now, isHM)
    showIceBubbleLine(self, alerts, now, isHM)
    showFragilityLine(self, alerts)
    showSpikeLine(self, alerts, now, isHM)
end

EventDispatcher.build(Lylanar)

package.loaded["trial.dsr.boss.Lylanar"] = Lylanar
return Lylanar
