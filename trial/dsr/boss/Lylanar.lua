--- Lylanar (& Turlassil) — Dreadsail Reef boss 1
---
--- Fire (Lylanar) and ice (Turlassil) boss pair fight simultaneously.
--- Both bosses' ability IDs are handled in this single module.
--- nameAliases = {"Turlassil"} ensures detection regardless of which unit
--- is reported as boss1 on any given pull.
---
--- Phase DSR-3: full mechanics
---   Fire side (Lylanar):
---     CinderSurge (166693): GAINED → 500 ms delay → "INTERRUPT! (Ice Dome)"
---     ImminentBlister (168525): GAINED_DURATION + tank/heal → info countdown
---     BlisteringFragility (166525): GAINED_DURATION → fragility timer
---     Firebrand (166472): GAINED_DURATION → brand tracker; HM: MatchBrands
---     BroilingHew (167273): BEGIN + player → AlertCast (heavy)
---     TorridCleave (167298): BEGIN + player → AlertCast (cleave)
---     ScaldingSwell (169587): BEGIN → Alert "Fire wave" 5.5 s
---     CharredConstriction (167466): BEGIN → Alert "Fire jump (spike!)" 2.5 s
---     MagmaSpike (168646): BEGIN → info countdown "Need Fire Dome"
---     IncendiaryAxe (168817): BEGIN → HM weapon cooldown tracker
---     MultiLoc (166909): EFFECT_GAINED → Alert "Lylanar teleports"
---     DestructiveEmber (166210): GAINED/UPDATED/FADED → fire bubble stacks
---     SummonFlameHound (169317): GAINED_DURATION → flameHounds++
---   Ice side (Turlassil):
---     NumbingShards (166735): GAINED → 500 ms delay → "INTERRUPT! (Fire Dome)"
---     ImminentChill (168526): GAINED_DURATION + tank/heal → info countdown
---     ChillingFragility (166529): GAINED_DURATION → fragility timer
---     Frostbrand (166482): GAINED_DURATION → brand tracker; HM: MatchBrands
---     StingingShear (167280): BEGIN + player → AlertCast (heavy)
---     BriskRip (167290): BEGIN + player → AlertCast (cleave)
---     BitingBillow (169594): BEGIN → Alert "Ice wave" 5.5 s
---     Frigidarium (167545): BEGIN → Alert "Ice jump (spike!)" 2.5 s
---     GlacialSpike (168632): BEGIN → info countdown "Need Ice Dome"
---     CalamitousSword (168912): BEGIN → HM weapon cooldown tracker
---     MultiLoc (166745): EFFECT_GAINED → Alert "Turlassil teleports"
---     PiercingHailstone (166192): GAINED/UPDATED/FADED → ice bubble stacks
---     SummonFrostHound (169313): GAINED_DURATION → frostHounds++
---   Shared:
---     Hindered (165972): GAINED_DURATION + player → AlertBorder 12 s
---     Brand matching (HM): 2 fire + 2 ice brands → "STACK ON: partner (far/close)"
---
--- HM detection: context.difficulty == Difficulty.HARDMODE
---   TODO: verify exact HM health pool in-game.

local Difficulty       = require("core.Difficulty")
local DreadsailCommon  = require("trial.dsr.DreadsailCommon")

-- ── Ability IDs — Fire (Lylanar) ───────────────────────────────────────────
local CINDER_SURGE         = 166693   -- channel → interrupt for ice dome
local IMMINENT_BLISTER     = 168525   -- 10 s tank/heal warning
local BLISTERING_FRAGILITY = 166525   -- 20 s fragility debuff
local FIREBRAND            = 166472   -- HM brand
local BROILING_HEW         = 167273   -- heavy melee
local TORRID_CLEAVE        = 167298   -- frontal cleave
local SCALDING_SWELL       = 169587   -- fire wave (5.5 s)
local CHARRED_CONSTRICTION = 167466   -- fire jump cage
local MAGMA_SPIKE          = 168646   -- fire spike cage
local INCENDIARY_AXE       = 168817   -- HM weapon cast (40 s cd)
local LYLANAR_MULTILOC     = 166909   -- teleport
local DESTRUCTIVE_EMBER    = 166210   -- fire bubble stacks
local SUMMON_FLAME_HOUND   = 169317
local PRE_FIREBRAND        = 166355   -- cast before brand placement

-- ── Ability IDs — Ice (Turlassil) ─────────────────────────────────────────
local NUMBING_SHARDS       = 166735   -- channel → interrupt for fire dome
local IMMINENT_CHILL       = 168526   -- 10 s tank/heal warning
local CHILLING_FRAGILITY   = 166529   -- 20 s fragility debuff
local FROSTBRAND           = 166482   -- HM brand
local STINGING_SHEAR       = 167280   -- heavy melee
local BRISK_RIP            = 167290   -- frontal cleave
local BITING_BILLOW        = 169594   -- ice wave (5.5 s)
local FRIGIDARIUM          = 167545   -- ice jump cage
local GLACIAL_SPIKE        = 168632   -- ice spike cage
local CALAMITOUS_SWORD     = 168912   -- HM weapon cast (40 s cd)
local TURLASSIL_MULTILOC   = 166745   -- teleport
local PIERCING_HAILSTONE   = 166192   -- ice bubble stacks
local SUMMON_FROST_HOUND   = 169313
local PRE_FROSTBRAND       = 166364   -- cast before brand placement

-- ── Ability IDs — Shared ──────────────────────────────────────────────────
local HINDERED             = 165972   -- slow on player (12 s)

-- ── Timing constants ─────────────────────────────────────────────────────
local FRAGILITY_DUR  = 20    -- s: fragility debuff visible window
local SPIKE_DUR      = 6.5   -- s: spike cage must be solved
local WEAPON_CD      = 40    -- s: HM weapon cooldown
local BRAND_DEDUP    = 1.0   -- s: MatchBrands dedup gate
local BUBBLE_CD_NORM = 15    -- s: bubble drop cooldown (normal)
local BUBBLE_CD_HM   = 20    -- s: bubble drop cooldown (HM)

local CA = require("lib.CA")

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_FIRE_HEAVY = { -2, 0, false, { 1.0, 0.35, 0.1, 0.4 }, { 1.0, 0.35, 0.1, 0.8 } }
local COL_ICE_HEAVY  = { -2, 0, false, { 0.3, 0.75, 1.0, 0.4 }, { 0.3, 0.75, 1.0, 0.8 } }

-- ── Boss definition ───────────────────────────────────────────────────────
local Lylanar = {}
Lylanar.__index = Lylanar

Lylanar.key          = "lylanar"
Lylanar.name         = "Lylanar"        -- TODO: verify via GetUnitName("boss1") in-game
Lylanar.nameAliases  = { "Turlassil" }  -- both bosses active simultaneously
Lylanar.hmHealthThreshold = 100000001   -- TODO: verify exact HM health pool

function Lylanar.new()
    return setmetatable({
        -- State — Fire
        cinderSurgeActive      = false,
        lastFireImminentTime   = 0,
        lastFireImminentPlayer = nil,
        lastFireFragilityTime  = 0,
        lastFireFragilityPlyr  = nil,
        lastMagmaSpike         = 0,
        lastIncendiaryAxe      = 0,
        destructiveEmberStacks = 0,
        destructiveEmberName   = nil,
        lastDestructiveEmber   = 0,      -- last GAINED/UPDATED time
        firebrandTracker       = {},     -- {unitId, name} pairs collected this cast
        lastBrandMatchFire     = 0,      -- dedup gate
        flameHounds            = 0,

        -- State — Ice
        numbingShardsActive    = false,
        lastIceImminentTime    = 0,
        lastIceImminentPlayer  = nil,
        lastIceFragilityTime   = 0,
        lastIceFragilityPlyr   = nil,
        lastGlacialSpike       = 0,
        lastCalamitousSword    = 0,
        piercingHailstacks     = 0,
        piercingHailName       = nil,
        lastPiercingHail       = 0,
        frostbrandTracker      = {},
        lastBrandMatchIce      = 0,
        frostHounds            = 0,

        -- State — Shared
        lastBrandMatch = 0,  -- dedup for the combined MatchBrands alert
    }, Lylanar)
end

-- ── Brand matching (HM) ───────────────────────────────────────────────────
-- Called after both firebrand and frostbrand trackers each hold 2 entries.
-- Finds the local player in either list and names their required partner.
local function matchBrands(self)
    local now = GetGameTimeMilliseconds() / 1000
    if now - self.lastBrandMatch < BRAND_DEDUP then return end
    self.lastBrandMatch = now

    local fire  = self.firebrandTracker   -- [{unitId, name}, ...]
    local frost = self.frostbrandTracker

    if #fire < 2 or #frost < 2 then return end

    -- Find local player's slot index in fire or frost list.
    local myFire, myFrost = nil, nil
    for i, entry in ipairs(fire) do
        if AreUnitsEqual("player", entry.tag or "") then myFire = i end
    end
    for i, entry in ipairs(frost) do
        if AreUnitsEqual("player", entry.tag or "") then myFrost = i end
    end

    -- Player must be in exactly one list; their partner is the matching index
    -- in the other list (index 1 → index 1, index 2 → index 2).
    local partner, distance
    if myFire then
        partner  = frost[myFire] and frost[myFire].name or "?"
        distance = (myFire == 1) and "far" or "close"
    elseif myFrost then
        partner  = fire[myFrost] and fire[myFrost].name or "?"
        distance = (myFrost == 1) and "far" or "close"
    else
        return  -- player not branded this round
    end

    CA.alert(nil,
        "STACK ON: " .. partner .. " (" .. distance .. ")",
        0xFF8800D9, SOUNDS.DUEL_START, 6000)
    PlaySound(SOUNDS.DUEL_START)
end

-- ── Routing tables (C3) ──────────────────────────────────────────────────
-- Shared trash mechanic handler.
Lylanar.common = DreadsailCommon

Lylanar.combatRoutes = {
    -- ── Fire ───────────────────────────────────────────────────────────────
    [BROILING_HEW] = function(self, context, alerts, result, abilityId,
                               unitTag, sourceUnitTag, sourceUnitId, unitId,
                               sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 1500 end
        CA.alertCast(abilityId, sourceUnitName, dur, COL_FIRE_HEAVY)
    end,
    [TORRID_CLEAVE] = function(self, context, alerts, result, abilityId,
                                unitTag, sourceUnitTag, sourceUnitId, unitId,
                                sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 1500 end
        alerts:showAction("Dodge! (Cleave)")
        CA.alertCast(abilityId, sourceUnitName, dur, COL_FIRE_HEAVY)
    end,
    [SCALDING_SWELL] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        CA.alert(nil, "|cFF5733Fire wave|r — move!", 0xFF5733D9,
            SOUNDS.CHAMPION_POINTS_COMMITTED, 5500)
    end,
    [CHARRED_CONSTRICTION] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        CA.alert(nil, "|cFF5733Fire jump!|r (spike — block)", 0xFF5733D9,
            SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
    end,
    [MAGMA_SPIKE] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.lastMagmaSpike = GetGameTimeMilliseconds() / 1000
    end,
    [INCENDIARY_AXE] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        if context.difficulty == Difficulty.HARDMODE then
            self.lastIncendiaryAxe = GetGameTimeMilliseconds() / 1000
        end
    end,
    -- ── Ice ────────────────────────────────────────────────────────────────
    [STINGING_SHEAR] = function(self, context, alerts, result, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 1500 end
        CA.alertCast(abilityId, sourceUnitName, dur, COL_ICE_HEAVY)
    end,
    [BRISK_RIP] = function(self, context, alerts, result, abilityId,
                            unitTag, sourceUnitTag, sourceUnitId, unitId,
                            sourceUnitName, unitName)
        if result ~= ACTION_RESULT_BEGIN then return end
        if not IsUnitPlayer(unitTag) then return end
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 1500 end
        alerts:showAction("Dodge! (Cleave)")
        CA.alertCast(abilityId, sourceUnitName, dur, COL_ICE_HEAVY)
    end,
    [BITING_BILLOW] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        CA.alert(nil, "|c99CCffIce wave|r — move!", 0x99CCffD9,
            SOUNDS.CHAMPION_POINTS_COMMITTED, 5500)
    end,
    [FRIGIDARIUM] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        CA.alert(nil, "|c99CCffIce jump!|r (spike — block)", 0x99CCffD9,
            SOUNDS.CHAMPION_POINTS_COMMITTED, 2500)
    end,
    [GLACIAL_SPIKE] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        self.lastGlacialSpike = GetGameTimeMilliseconds() / 1000
    end,
    [CALAMITOUS_SWORD] = function(self, context, alerts, result, abilityId, ...)
        if result ~= ACTION_RESULT_BEGIN then return end
        if context.difficulty == Difficulty.HARDMODE then
            self.lastCalamitousSword = GetGameTimeMilliseconds() / 1000
        end
    end,
}

Lylanar.effectRoutes = {
    -- ── Fire: CinderSurge → interrupt ice dome ─────────────────────────────
    [CINDER_SURGE] = function(self, context, alerts, changeType, abilityId,
                               unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED then
            self.cinderSurgeActive = true
            zo_callLater(function()
                if self.cinderSurgeActive then
                    CA.alert(nil, "|cFF5733INTERRUPT!|r (Ice Dome)",
                        0xFF2020D9, SOUNDS.DUEL_START, 15000)
                    PlaySound(SOUNDS.DUEL_START)
                end
            end, 500)
        elseif changeType == EFFECT_RESULT_FADED then
            self.cinderSurgeActive = false
        end
    end,
    -- ── Ice: NumbingShards → interrupt fire dome ───────────────────────────
    [NUMBING_SHARDS] = function(self, context, alerts, changeType, abilityId,
                                 unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED then
            self.numbingShardsActive = true
            zo_callLater(function()
                if self.numbingShardsActive then
                    CA.alert(nil, "|c99CCffINTERRUPT!|r (Fire Dome)",
                        0x2020FFD9, SOUNDS.DUEL_START, 15000)
                    PlaySound(SOUNDS.DUEL_START)
                end
            end, 500)
        elseif changeType == EFFECT_RESULT_FADED then
            self.numbingShardsActive = false
        end
    end,
    -- ── Fire: ImminentBlister (tank/heal warning, 10 s) ────────────────────
    [IMMINENT_BLISTER] = function(self, context, alerts, changeType, abilityId,
                                   unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED then
            local _, isHeal, isTank = GetPlayerRoles()
            if isTank or isHeal then
                self.lastFireImminentTime   = GetGameTimeMilliseconds() / 1000
                self.lastFireImminentPlayer = GetUnitDisplayName(unitTag) or unitName
            end
        elseif changeType == EFFECT_RESULT_FADED then
            self.lastFireImminentTime = 0
        end
    end,
    -- ── Ice: ImminentChill (tank/heal warning, 10 s) ───────────────────────
    [IMMINENT_CHILL] = function(self, context, alerts, changeType, abilityId,
                                 unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED then
            local _, isHeal, isTank = GetPlayerRoles()
            if isTank or isHeal then
                self.lastIceImminentTime   = GetGameTimeMilliseconds() / 1000
                self.lastIceImminentPlayer = GetUnitDisplayName(unitTag) or unitName
            end
        elseif changeType == EFFECT_RESULT_FADED then
            self.lastIceImminentTime = 0
        end
    end,
    -- ── Fire: BlisteringFragility (20 s debuff on local player) ───────────
    [BLISTERING_FRAGILITY] = function(self, context, alerts, changeType, abilityId,
                                       unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED then
            if AreUnitsEqual("player", unitTag) then
                self.lastFireFragilityTime = GetGameTimeMilliseconds() / 1000
                self.lastFireFragilityPlyr = GetUnitDisplayName(unitTag) or unitName
            end
        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.lastFireFragilityTime = 0
            end
        end
    end,
    -- ── Ice: ChillingFragility (20 s debuff on local player) ──────────────
    [CHILLING_FRAGILITY] = function(self, context, alerts, changeType, abilityId,
                                     unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED then
            if AreUnitsEqual("player", unitTag) then
                self.lastIceFragilityTime = GetGameTimeMilliseconds() / 1000
                self.lastIceFragilityPlyr = GetUnitDisplayName(unitTag) or unitName
            end
        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.lastIceFragilityTime = 0
            end
        end
    end,
    -- ── Fire: DestructiveEmber (fire bubble stacks, stackCount used!) ───────
    [DESTRUCTIVE_EMBER] = function(self, context, alerts, changeType, abilityId,
                                    unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
            if AreUnitsEqual("player", unitTag) then
                self.destructiveEmberStacks = stackCount or 1
                self.destructiveEmberName   = GetUnitDisplayName(unitTag) or unitName
                self.lastDestructiveEmber   = GetGameTimeMilliseconds() / 1000
            end
        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.destructiveEmberStacks = 0
                self.destructiveEmberName   = nil
                self.lastDestructiveEmber   = 0
            end
        end
    end,
    -- ── Ice: PiercingHailstone (ice bubble stacks, stackCount used!) ────────
    [PIERCING_HAILSTONE] = function(self, context, alerts, changeType, abilityId,
                                     unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED or changeType == EFFECT_RESULT_UPDATED then
            if AreUnitsEqual("player", unitTag) then
                self.piercingHailstacks = stackCount or 1
                self.piercingHailName   = GetUnitDisplayName(unitTag) or unitName
                self.lastPiercingHail   = GetGameTimeMilliseconds() / 1000
            end
        elseif changeType == EFFECT_RESULT_FADED then
            if AreUnitsEqual("player", unitTag) then
                self.piercingHailstacks = 0
                self.piercingHailName   = nil
                self.lastPiercingHail   = 0
            end
        end
    end,
    -- ── Fire: Firebrand (HM brand tracking) ──────────────────────────────
    [FIREBRAND] = function(self, context, alerts, changeType, abilityId,
                            unitTag, unitId, unitName, stackCount)
        if context.difficulty ~= Difficulty.HARDMODE then return end
        if changeType ~= EFFECT_RESULT_GAINED then return end
        local entry = { tag = unitTag, name = GetUnitDisplayName(unitTag) or unitName }
        table.insert(self.firebrandTracker, entry)
        if #self.firebrandTracker >= 2 and #self.frostbrandTracker >= 2 then
            matchBrands(self)
            self.firebrandTracker  = {}
            self.frostbrandTracker = {}
        end
    end,
    -- ── Ice: Frostbrand (HM brand tracking) ──────────────────────────────
    [FROSTBRAND] = function(self, context, alerts, changeType, abilityId,
                             unitTag, unitId, unitName, stackCount)
        if context.difficulty ~= Difficulty.HARDMODE then return end
        if changeType ~= EFFECT_RESULT_GAINED then return end
        local entry = { tag = unitTag, name = GetUnitDisplayName(unitTag) or unitName }
        table.insert(self.frostbrandTracker, entry)
        if #self.firebrandTracker >= 2 and #self.frostbrandTracker >= 2 then
            matchBrands(self)
            self.firebrandTracker  = {}
            self.frostbrandTracker = {}
        end
    end,
    [LYLANAR_MULTILOC] = function(self, context, alerts, changeType, abilityId, ...)
        if changeType == EFFECT_RESULT_GAINED then
            CA.alert(nil, "|cFF5733Lylanar teleports|r — reposition!",
                0xFF5733D9, SOUNDS.CHAMPION_POINTS_COMMITTED, 4000)
        end
    end,
    [TURLASSIL_MULTILOC] = function(self, context, alerts, changeType, abilityId, ...)
        if changeType == EFFECT_RESULT_GAINED then
            CA.alert(nil, "|c99CCffTurlassil teleports|r — reposition!",
                0x99CCffD9, SOUNDS.CHAMPION_POINTS_COMMITTED, 4000)
        end
    end,
    [SUMMON_FLAME_HOUND] = function(self, context, alerts, changeType, abilityId, ...)
        if changeType == EFFECT_RESULT_GAINED then
            self.flameHounds = self.flameHounds + 1
        elseif changeType == EFFECT_RESULT_FADED then
            if self.flameHounds > 0 then self.flameHounds = self.flameHounds - 1 end
        end
    end,
    [SUMMON_FROST_HOUND] = function(self, context, alerts, changeType, abilityId, ...)
        if changeType == EFFECT_RESULT_GAINED then
            self.frostHounds = self.frostHounds + 1
        elseif changeType == EFFECT_RESULT_FADED then
            if self.frostHounds > 0 then self.frostHounds = self.frostHounds - 1 end
        end
    end,
    -- ── Shared: Hindered (slow on player → yellow border 12 s) ──────────
    [HINDERED] = function(self, context, alerts, changeType, abilityId,
                           unitTag, unitId, unitName, stackCount)
        if changeType == EFFECT_RESULT_GAINED and AreUnitsEqual("player", unitTag) then
            CA.border(true, 12000, "yellow")
        end
    end,
}

-- ── 200 ms display loop ───────────────────────────────────────────────────
function Lylanar:onUpdate(context, alerts)
    local now  = GetGameTimeMilliseconds() / 1000
    local isHM = (context.difficulty == Difficulty.HARDMODE)

    -- ── Info 1: Fire bubble (Destructive Ember) ───────────────────────────
    if self.lastDestructiveEmber > 0 then
        local cd   = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T    = cd - (now - self.lastDestructiveEmber)
        local stks = self.destructiveEmberStacks
        if T > 0 then
            alerts:showInfo(1,
                "|cFF5733🔥 " .. (self.destructiveEmberName or "?") .. "|r"
                .. " — " .. stks .. " stack" .. (stks ~= 1 and "s" or "")
                .. " (" .. string.format("%.0f", T) .. "s)")
        else
            -- Bubble should have been dropped; dim display
            alerts:showInfo(1,
                "|cFF5733🔥 " .. (self.destructiveEmberName or "?") .. "|r"
                .. " — " .. stks .. " stack" .. (stks ~= 1 and "s" or "")
                .. " |cff0000DROP!|r")
        end
    else
        alerts:showInfo(1, "")
    end

    -- ── Info 2: Ice bubble (Piercing Hailstone) ───────────────────────────
    if self.lastPiercingHail > 0 then
        local cd   = isHM and BUBBLE_CD_HM or BUBBLE_CD_NORM
        local T    = cd - (now - self.lastPiercingHail)
        local stks = self.piercingHailstacks
        if T > 0 then
            alerts:showInfo(2,
                "|c99CCff❄ " .. (self.piercingHailName or "?") .. "|r"
                .. " — " .. stks .. " stack" .. (stks ~= 1 and "s" or "")
                .. " (" .. string.format("%.0f", T) .. "s)")
        else
            alerts:showInfo(2,
                "|c99CCff❄ " .. (self.piercingHailName or "?") .. "|r"
                .. " — " .. stks .. " stack" .. (stks ~= 1 and "s" or "")
                .. " |cff0000DROP!|r")
        end
    else
        alerts:showInfo(2, "")
    end

    -- ── Info 3: Fragility countdowns ──────────────────────────────────────
    -- Show whichever fragility is active on the local player (fire takes priority).
    if self.lastFireFragilityTime > 0 then
        local T = FRAGILITY_DUR - (now - self.lastFireFragilityTime)
        if T > 0 then
            alerts:showInfo(3,
                "|cFF5733Fire Fragility|r: " .. string.format("%.0f", T) .. "s")
        else
            self.lastFireFragilityTime = 0
            alerts:showInfo(3, "")
        end
    elseif self.lastIceFragilityTime > 0 then
        local T = FRAGILITY_DUR - (now - self.lastIceFragilityTime)
        if T > 0 then
            alerts:showInfo(3,
                "|c99CCffIce Fragility|r: " .. string.format("%.0f", T) .. "s")
        else
            self.lastIceFragilityTime = 0
            alerts:showInfo(3, "")
        end
    else
        alerts:showInfo(3, "")
    end

    -- ── Info 4: Spike cage / weapon (HM) / imminent ───────────────────────
    -- Priority: spike cage > HM weapon > imminent warning
    local fireSpikeT = (self.lastMagmaSpike  > 0) and (SPIKE_DUR - (now - self.lastMagmaSpike))  or -1
    local iceSpikeT  = (self.lastGlacialSpike > 0) and (SPIKE_DUR - (now - self.lastGlacialSpike)) or -1

    if fireSpikeT > 0 then
        alerts:showInfo(4,
            "|cFF5733Need Fire Dome|r: " .. string.format("%.1f", fireSpikeT) .. "s")
    elseif iceSpikeT > 0 then
        alerts:showInfo(4,
            "|c99CCffNeed Ice Dome|r: " .. string.format("%.1f", iceSpikeT) .. "s")
    elseif isHM and self.lastIncendiaryAxe > 0 then
        local T = WEAPON_CD - (now - self.lastIncendiaryAxe)
        if T > 0 then
            alerts:showInfo(4,
                "|cFF5733Axe|r: " .. string.format("%.0f", T) .. "s"
                .. (self.lastCalamitousSword > 0 and
                    ("  |c99CCffSword|r: " .. string.format("%.0f",
                        math.max(0, WEAPON_CD - (now - self.lastCalamitousSword))) .. "s") or ""))
        else
            alerts:showInfo(4, "|cFF5733Axe|r: |cff0000INC|r")
        end
    elseif self.lastFireImminentTime > 0 then
        local T = 10 - (now - self.lastFireImminentTime)
        if T > 0 then
            alerts:showInfo(4,
                "|cFF5733Imminent Blister|r (" ..
                (self.lastFireImminentPlayer or "?") .. "): " ..
                string.format("%.0f", T) .. "s")
        else
            self.lastFireImminentTime = 0
            alerts:showInfo(4, "")
        end
    elseif self.lastIceImminentTime > 0 then
        local T = 10 - (now - self.lastIceImminentTime)
        if T > 0 then
            alerts:showInfo(4,
                "|c99CCffImminent Chill|r (" ..
                (self.lastIceImminentPlayer or "?") .. "): " ..
                string.format("%.0f", T) .. "s")
        else
            self.lastIceImminentTime = 0
            alerts:showInfo(4, "")
        end
    else
        alerts:showInfo(4, "")
    end
end

return Lylanar
