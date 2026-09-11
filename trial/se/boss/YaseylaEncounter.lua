local AlertTypes      = require("core.AlertTypes")
local EventDispatcher = require("core.EventDispatcher")
local Timer           = require("lib.Timer")
local CA              = require("external-api.CombatAlerts")
local BossBase        = require("lib.BossBase")
local CastDur         = require("lib.CastDur")
local Lang            = require("core.Lang")
local Settings        = require("core.Settings")
local Colors          = require("core.Colors")

-- -- Ability IDs (from SanitysEdgeHelper / SSEA data) ------------------------------
local DEFLECT         = 184823
local SHRAPNEL        = 199131
local FIRE_BOMBS      = 183660
local KNIFE_BLAST_1   = 183803
local KNIFE_BLAST_2   = 183804
local VENGEFUL_STRIKE = 185071
local VANTONS_CLARITY = 184041
local SEETHE          = 162783
local CHAIN_PULL      = 184540
-- Frost Bombs (Tomb mechanic)  -  10 variants
local FROST_BOMB_1    = 185403
local FROST_BOMB_2    = 183783
local FROST_BOMB_3    = 183790
local FROST_BOMB_4    = 192304
local FROST_BOMB_5    = 191049
local FROST_BOMB_6    = 188065
local FROST_BOMB_7    = 199254
local FROST_BOMB_8    = 185406
local FROST_BOMB_9    = 183768
local FROST_BOMB_10   = 185392
local IGNITE          = 188188
-- Wamasu Charges  -  6 variants
local WAMASU_CHARGE_1 = 191133
local WAMASU_CHARGE_2 = 191139
local WAMASU_CHARGE_3 = 191134
local WAMASU_CHARGE_4 = 200544
local WAMASU_CHARGE_5 = 200558
local WAMASU_CHARGE_6 = 200559
-- Wamasu Charged Headbutt  -  3 variants
local HEADBUTT_1      = 184999
local HEADBUTT_2      = 185002
local HEADBUTT_3      = 185000
-- Wamasu Overwhelming Lightning  -  3 variants
local OVW_LIGHTNING_1 = 183598
local OVW_LIGHTNING_2 = 198510
local OVW_LIGHTNING_3 = 183599

-- -- Timer durations (seconds) -----------------------------------------------------
local FIREBOMB_CD         = 23.5
local FIREBOMB_EXEC_CD    = 11
local FIREBOMB_EXEC_THOLD = 26
local CHAIN_CD            = 32
local FROST_CD            = 25

local FALLBACK_DUR = 2000

local YaseylaEncounter = {}
YaseylaEncounter.__index = YaseylaEncounter

YaseylaEncounter.key               = "yaseyla"
YaseylaEncounter.nameAliases       = { "Exarchanic Yaseyla" }
YaseylaEncounter.hmHealthThreshold = 80000000

YaseylaEncounter.stateSchema = {
    firebombTimer = function() return Timer.new(FIREBOMB_CD) end,
    chainTimer    = function() return Timer.new(CHAIN_CD) end,
    frostTimer    = function() return Timer.new(FROST_CD) end,
    executePhase  = false,
    firstFirebomb = true,
    firstFrost    = true,
    shrapnelCount = 0,
    alertList     = function() return {} end,
    m90 = false, m80 = false, m70 = false, m60 = false, m55 = false,
    m50 = false, m35 = false, m30 = false, m25 = false, m20 = false, m10 = false,
}

function YaseylaEncounter.new()
    return BossBase.fromSchema(YaseylaEncounter)
end

function YaseylaEncounter:onLeave(context)
    self:cleanupAlertList()
end

function YaseylaEncounter:onWipe(context, alerts)
    self:cleanupAlertList()
    self.firebombTimer:clear(); self.chainTimer:clear(); self.frostTimer:clear()
    self.executePhase  = false; self.firstFirebomb = true
    self.firstFrost    = true;  self.shrapnelCount = 0
    self.m90 = false; self.m80 = false; self.m70 = false; self.m60 = false
    self.m55 = false; self.m50 = false; self.m35 = false; self.m30 = false
    self.m25 = false; self.m20 = false; self.m10 = false
end

-- -- Handlers: beginCast ------------------------------------------------------------

local function handleFireBombs(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    boss.firstFirebomb = false
    local cd = boss.executePhase and FIREBOMB_EXEC_CD or FIREBOMB_CD
    boss.firebombTimer:reset(cd)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_yaseyla_fire_bombs_tgt", target))
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    local cid = CA.ranged(abilityId, Lang.t("se_yaseyla_fire_bombs_bar"), dur, Colors.FIRE)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleKnifeBlast(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_yaseyla_knife_blast_bar", target), dur, Colors.AMBER)
    alerts:showAction(Lang.t("se_yaseyla_knife_blast", target))
end

local function handleVengefulStrike(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_vengeful_strike"))
    CA.alert(nil, Lang.t("se_yaseyla_vengeful_alert"), 0xFF4400FF, SOUNDS.NONE, 2500)
end

local function handleVantonsClarity(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_portal"))
    CA.alert(nil, Lang.t("se_yaseyla_portal_alert"), 0xAAFFAAFF, SOUNDS.NONE, 4000)
end

local function handleSeethe(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_enrage"))
    CA.alert(nil, Lang.t("se_yaseyla_enrage_alert"), 0xFF0000FF, SOUNDS.NONE, 5000)
end

local function handleChainPull(boss, ctx, alerts, abilityId, ...)
    boss.chainTimer:reset(CHAIN_CD)
    alerts:showAction(Lang.t("se_yaseyla_chains"))
end

local function handleDeflect(boss, ctx, alerts, abilityId, ...)
    boss.shrapnelCount = boss.shrapnelCount + 1
    alerts:showAction(Lang.t("se_yaseyla_shrapnel_you", boss.shrapnelCount))
    CA.alert(nil, Lang.t("se_yaseyla_deflect_alert"), 0xFF0033FF, SOUNDS.NONE, 3000)
end

local function handleShrapnel(boss, ctx, alerts, abilityId, ...)
    alerts:showAction(Lang.t("se_yaseyla_shrapnel"))
    CA.alert(nil, Lang.t("se_yaseyla_shrapnel_alert"), 0xFF0033FF, SOUNDS.NONE, 3000)
end

local function handleWamasuCharge(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    local dur = CastDur.get(abilityId, FALLBACK_DUR)
    CA.ranged(abilityId, Lang.t("se_yaseyla_charge_bar", target), dur, Colors.FIRE)
end

local function handleHeadbutt(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    local target = (unitName and unitName ~= "") and unitName or "?"
    alerts:showAction(Lang.t("se_yaseyla_headbutt", target))
    CA.alert(nil, Lang.t("se_yaseyla_headbutt_alert"), 0xFF6600FF, SOUNDS.NONE, 2500)
end

local function handleOvwLightning(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_yaseyla_overwhelming"))
    CA.alert(nil, Lang.t("se_yaseyla_ovw_lightning"), 0xFFDD44FF, SOUNDS.NONE, 3000)
end

-- -- Handlers: combatEvent.other (EFFECT_GAINED_DURATION) -------------------------

local function handleFrostBomb(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
    boss.firstFrost = false
    boss.frostTimer:reset(FROST_CD)
    if IsUnitPlayer(unitTag) then
        alerts:showAction(Lang.t("se_yaseyla_frost_bomb_you"))
        CA.alert(nil, Lang.t("se_yaseyla_frost_bomb_alert"), 0x99CCFFFF, SOUNDS.NONE, 3000)
    elseif unitName and unitName ~= "" then
        alerts:showAction(Lang.t("se_yaseyla_frost_bomb_tgt", unitName))
    end
end

local function handleIgnite(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, ...)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("se_yaseyla_ignite"))
end

-- -- Event tables ------------------------------------------------------------------

local _beginCastEntry = {
    [FIRE_BOMBS]      = { type = AlertTypes.CUSTOM, fn = handleFireBombs },
    [KNIFE_BLAST_1]   = { type = AlertTypes.CUSTOM, fn = handleKnifeBlast },
    [KNIFE_BLAST_2]   = { type = AlertTypes.CUSTOM, fn = handleKnifeBlast },
    [VENGEFUL_STRIKE] = { type = AlertTypes.CUSTOM, fn = handleVengefulStrike },
    [VANTONS_CLARITY] = { type = AlertTypes.CUSTOM, fn = handleVantonsClarity },
    [SEETHE]          = { type = AlertTypes.CUSTOM, fn = handleSeethe },
    [CHAIN_PULL]      = { type = AlertTypes.CUSTOM, fn = handleChainPull },
    [DEFLECT]         = { type = AlertTypes.CUSTOM, fn = handleDeflect },
    [SHRAPNEL]        = { type = AlertTypes.CUSTOM, fn = handleShrapnel },
    [WAMASU_CHARGE_1] = { type = AlertTypes.CUSTOM, fn = handleWamasuCharge },
    [WAMASU_CHARGE_2] = { type = AlertTypes.CUSTOM, fn = handleWamasuCharge },
    [WAMASU_CHARGE_3] = { type = AlertTypes.CUSTOM, fn = handleWamasuCharge },
    [WAMASU_CHARGE_4] = { type = AlertTypes.CUSTOM, fn = handleWamasuCharge },
    [WAMASU_CHARGE_5] = { type = AlertTypes.CUSTOM, fn = handleWamasuCharge },
    [WAMASU_CHARGE_6] = { type = AlertTypes.CUSTOM, fn = handleWamasuCharge },
    [HEADBUTT_1]      = { type = AlertTypes.CUSTOM, fn = handleHeadbutt },
    [HEADBUTT_2]      = { type = AlertTypes.CUSTOM, fn = handleHeadbutt },
    [HEADBUTT_3]      = { type = AlertTypes.CUSTOM, fn = handleHeadbutt },
    [OVW_LIGHTNING_1] = { type = AlertTypes.CUSTOM, fn = handleOvwLightning },
    [OVW_LIGHTNING_2] = { type = AlertTypes.CUSTOM, fn = handleOvwLightning },
    [OVW_LIGHTNING_3] = { type = AlertTypes.CUSTOM, fn = handleOvwLightning },
}

local _combatOtherEntry = {
    [FROST_BOMB_1]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_2]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_3]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_4]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_5]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_6]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_7]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_8]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_9]  = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [FROST_BOMB_10] = { type = AlertTypes.CUSTOM, fn = handleFrostBomb },
    [IGNITE]        = { type = AlertTypes.CUSTOM, fn = handleIgnite },
}

YaseylaEncounter.events = {
    beginCast     = { instant = _beginCastEntry, started = _beginCastEntry },
    effectChanged = { gained = {}, faded = {}, updated = {} },
    combatEvent   = { damage = {}, dodged = {}, blocked = {}, other = _combatOtherEntry },
}

-- -- Info-line renderers -----------------------------------------------------------

local function showFireBombLine(self, alerts)
    if self.firstFirebomb then
        alerts:setRow(1, Lang.t("se_yaseyla_fire_bombs_first"), nil)
    else
        local r     = self.firebombTimer:remaining()
        local label = self.executePhase
            and Lang.t("se_yaseyla_bombs_exec_name")
            or  Lang.t("se_yaseyla_fire_bombs_name")
        if r > 0 then
            alerts:setRow(1, label, r)
        else
            alerts:setRow(1, label .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

local function showFrostBombLine(self, alerts)
    if self.firstFrost then
        alerts:setRow(3, Lang.t("se_yaseyla_frost_first"), nil)
    else
        local r = self.frostTimer:remaining()
        if r > 0 then
            alerts:setRow(3, Lang.t("se_yaseyla_frost_bomb_label"), r)
        else
            alerts:setRow(3, Lang.t("se_yaseyla_frost_bomb_label") .. " " .. Lang.t("common_ready"), nil)
        end
    end
end

function YaseylaEncounter:onUpdate(context, alerts)
    showFireBombLine(self, alerts)
    local rc = self.chainTimer:remaining()
    if rc > 0 then
        alerts:setRow(2, Lang.t("se_yaseyla_chains_label"), rc)
    else
        alerts:setRow(2, Lang.t("se_yaseyla_chains_label") .. " " .. Lang.t("common_ready"), nil)
    end
    showFrostBombLine(self, alerts)
    alerts:clearRow(4)
    alerts:clearRow(5)
    alerts:clearRow(6)
    alerts:clearRow(7)
end

function YaseylaEncounter:onPowerUpdate(context, healthPercent, alerts)
    if not self.executePhase and healthPercent > 0 and healthPercent < FIREBOMB_EXEC_THOLD then
        self.executePhase = true
        alerts:showAction(Lang.t("se_yaseyla_execute"))
    end

    if not Settings.trial("se").showPercent then return end
    if not self.m90 and healthPercent < 90 then
        self.m90 = true
        alerts:showAction(Lang.t("se_yaseyla_90pct"))
    elseif not self.m80 and healthPercent < 80 then
        self.m80 = true
        alerts:showAction(Lang.t("se_yaseyla_80pct"))
    elseif not self.m70 and healthPercent < 70 then
        self.m70 = true
        alerts:showAction(Lang.t("se_yaseyla_70pct"))
    elseif not self.m60 and healthPercent < 60 then
        self.m60 = true
        alerts:showAction(Lang.t("se_yaseyla_60pct"))
        CA.alert(nil, Lang.t("se_yaseyla_portal_pct_alert", 60), 0xAAFFAAFF, SOUNDS.NONE, 4000)
    elseif not self.m55 and healthPercent < 55 then
        self.m55 = true
        alerts:showAction(Lang.t("se_yaseyla_55pct"))
    elseif not self.m50 and healthPercent < 50 then
        self.m50 = true
        alerts:showAction(Lang.t("se_yaseyla_50pct"))
    elseif not self.m35 and healthPercent < 35 then
        self.m35 = true
        alerts:showAction(Lang.t("se_yaseyla_35pct"))
        CA.alert(nil, Lang.t("se_yaseyla_portal_pct_alert", 35), 0xAAFFAAFF, SOUNDS.NONE, 4000)
    elseif not self.m30 and healthPercent < 30 then
        self.m30 = true
        alerts:showAction(Lang.t("se_yaseyla_30pct"))
    elseif not self.m25 and healthPercent < 25 then
        self.m25 = true
        alerts:showAction(Lang.t("se_yaseyla_25pct"))
    elseif not self.m20 and healthPercent < 20 then
        self.m20 = true
        alerts:showAction(Lang.t("se_yaseyla_20pct"))
    elseif not self.m10 and healthPercent < 10 then
        self.m10 = true
        alerts:showAction(Lang.t("se_yaseyla_10pct"))
    end
end

EventDispatcher.build(YaseylaEncounter)

package.loaded["trial.se.boss.YaseylaEncounter"] = YaseylaEncounter
return YaseylaEncounter
