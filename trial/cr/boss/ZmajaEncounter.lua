local Location = require("core.Location")
local Timer    = require("lib.Timer")

-- ── CombatAlerts helpers ──────────────────────────────────────────────────
local function caAlertCast(...) if CombatAlerts then return CombatAlerts.AlertCast(...) end end
local function caAlert(...)     if CombatAlerts then return CombatAlerts.Alert(...)     end end
local function caCastAlertsStop(id)
    if CombatAlerts and id then CombatAlerts.CastAlertsStop(id) end
end

-- ── Ability ID sets for mini-boss detection ───────────────────────────────
-- Any of these firing marks that mini as active (detects +1/+2/+3 variant).
local SIRO_IDS = {
    [104755]=true, -- HA
    [106601]=true, -- Jump
    [104902]=true, -- Banner
    [103531]=true, -- Flare
    [110431]=true, -- Flare (execute)
    [105765]=true, -- Dark Talons
}
local RELE_IDS = {
    [105780]=true, -- HA
    [105796]=true, -- Flux Burst jump
    [105380]=true, -- Direct Current (interrupt)
    [106614]=true, -- Jolt
    [103555]=true, -- Overload incoming
    [87346] =true, -- Overload active
}
local GALE_IDS = {
    [106375]=true, -- HA
    [106682]=true, -- Teleport jump
    [106405]=true, -- Glacial Spikes (interrupt)
    [106378]=true, -- Donut
    [105151]=true, -- Hoarfrost cast
    [110466]=true, -- Hoarfrost cast (execute)
    [103695]=true, -- Hoarfrost debuff
    [110516]=true, -- Hoarfrost debuff (execute)
    [106374]=true, -- Chilling Comet
    [106367]=true, -- Chilling Comet variant
}

-- ── Ability IDs (from HowToCloudrest / CrutchAlerts) ─────────────────────

-- ── Siroria ───────────────────────────────────────────────────────────────
local SIRO_HA          = 104755  -- Heavy Attack → block/dodge
local SIRO_JUMP        = 106601  -- Jump — 23 s CD
local SIRO_BANNER      = 104902  -- Banner skill — 45 s CD
local SIRO_DARK_TALONS = 105765  -- Root on player
local SIRO_FLARE       = 103531  -- Roaring Flare → target name, 6.6 s window
local SIRO_FLARE_EXEC  = 110431  -- Roaring Flare execute variant

-- ── Relequen ──────────────────────────────────────────────────────────────
local RELE_HA          = 105780  -- Heavy Attack
local RELE_JUMP        = 105796  -- Flux Burst jump — 19 s CD
local RELE_DIRECT_CURR = 105380  -- Direct Current channel → INTERRUPT! 20 s CD
local RELE_JOLT        = 106614  -- Jolt cone — 15 s CD
local RELE_OVERLOAD_1  = 103555  -- Voltaic Overload incoming (bar-swap warning)
local RELE_OVERLOAD_2  = 87346   -- Voltaic Overload active on player

-- ── Galenwe ───────────────────────────────────────────────────────────────
local GALE_HA          = 106375  -- Heavy Attack
local GALE_JUMP        = 106682  -- Teleport jump — 19 s CD
local GALE_GLACIAL     = 106405  -- Glacial Spikes channel → INTERRUPT! 22 s CD
local GALE_DONUT       = 106378  -- Donut AoE — 22 s CD
local GALE_HOARFROST_C = 105151  -- Hoarfrost cast (ground AoE incoming)
local GALE_HOARFROST_C2= 110466  -- Hoarfrost cast execute variant
local GALE_HOARFROST   = 103695  -- Hoarfrost debuff on player — 6 s drop window
local GALE_HOARFROST_2 = 110516  -- Hoarfrost debuff execute variant
local GALE_HOARFROST_SY= 103697  -- Hoarfrost synergy used (drop frost now!)
local GALE_HOARFROST_S2= 110525  -- Hoarfrost synergy execute variant
local GALE_HOARFROST_AO= 103765  -- Hoarfrost AoE on ground
local GALE_COMET       = 106374  -- Chilling Comet on player — 4 s window
local GALE_COMET_2     = 106367  -- Chilling Comet variant

-- ── Environment / mini shared ─────────────────────────────────────────────
local RAZOR_THORNS     = 106656  -- Creeper root on player

-- ── Portal mechanics ──────────────────────────────────────────────────────
local PORTAL_OPEN      = 103946  -- Portal spawns / opens (75 s window)
local PORTAL_CLOSE_1   = 104057  -- Remove Shadow Realm (normal close)
local PORTAL_CLOSE_2   = 104792  -- Portal close (PC win)
local PORTAL_RESET     = 105890  -- Z'Maja re-engage — reset portal group to 1
local PLAYER_EXIT      = 105218  -- Player exits shadow realm (side-boss variant)

-- ── Z'Maja abilities ──────────────────────────────────────────────────────
local ZMAJA_JUMP       = 104564  -- BEGIN → "Z'Maja jumping!"
local ZMAJA_HIDE_JUMP  = 104452  -- BEGIN → Z'Maja retreats to shadow
local CRUSHING_DARK_1  = 105152  -- BEGIN → Kite! Crushing Darkness
local CRUSHING_DARK_2  = 105172
local CRUSHING_DARK_3  = 105239
local SHADOW_SPLASH    = 105123  -- BEGIN → Shadow Splash! Interrupt!
local BANEFUL_MARK     = 107196  -- BEGIN (execute) → Baneful Mark!
local ZMAJA_SHACKLE    = 107490  -- EFFECT_GAINED → mini shackled / dies

-- ── Malevolent Cores / misc ───────────────────────────────────────────────
local CORE_EXPOSED     = 103980
local CORE_PICKED_UP   = 103989
local CORE_MISSED      = 110202
local BEAD_TICK        = 105339
local BEAD_SPAWN       = 105363
local BEAD_CHARGE      = 105373
local OLORIME_SPEAR    = 104018
local BREAK_AMULET     = 106023
local MALICIOUS_SPHERE = 105291

-- ── Timer durations (seconds) ─────────────────────────────────────────────
local SIRO_JUMP_CD     = 23
local SIRO_BANNER_CD   = 45
local RELE_JUMP_CD     = 19
local RELE_BASH_CD     = 20
local RELE_JOLT_CD     = 15
local GALE_JUMP_CD     = 19
local GALE_BASH_CD     = 22
local GALE_DONUT_CD    = 22
local HOARFROST_DROP   = 6     -- seconds until Hoarfrost is droppable
local FLARE_WINDOW     = 7     -- Roaring Flare alert window (seconds)
local COMET_WINDOW     = 4     -- Chilling Comet window (seconds)
local PORTAL_OPEN_DUR  = 75    -- portal stays open ~75 s
local PORTAL_NEXT_CD   = 46    -- seconds until next portal after close

-- ── CA colour palettes ────────────────────────────────────────────────────
local COL_SIRO  = { -3, 0, false, { 1, 0.27, 0, 0.4 },    { 1, 0.27, 0, 0.8 } }    -- orange (fire)
local COL_RELE  = { -3, 0, false, { 0.2, 0.6, 1, 0.4 },   { 0.2, 0.6, 1, 0.8 } }  -- blue (lightning)
local COL_GALE  = { -3, 0, false, { 0, 0.87, 0.87, 0.4 }, { 0, 0.87, 0.87, 0.8 } } -- cyan (frost)
local COL_ZMAJA = { -3, 0, false, { 0.6, 0, 0.8, 0.4 },   { 0.6, 0, 0.8, 0.8 } }   -- purple (shadow)

local ZmajaEncounter = {
    id           = 1,
    key          = "zmaja",
    nameAliases  = { "Z'Maja" },
    -- hmHealthThreshold: TBD — verify in-game on vet HM
    hmHealthThreshold = 0,
    -- Location: entire arena — name-based detection is used instead.
    location = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Timers ────────────────────────────────────────────────────────────────
-- Siroria
ZmajaEncounter.siroJumpTimer   = Timer.new(SIRO_JUMP_CD)
ZmajaEncounter.siroBannerTimer = Timer.new(SIRO_BANNER_CD)
-- Relequen
ZmajaEncounter.releJumpTimer   = Timer.new(RELE_JUMP_CD)
ZmajaEncounter.releBashTimer   = Timer.new(RELE_BASH_CD)
ZmajaEncounter.releJoltTimer   = Timer.new(RELE_JOLT_CD)
-- Galenwe
ZmajaEncounter.galeJumpTimer   = Timer.new(GALE_JUMP_CD)
ZmajaEncounter.galeBashTimer   = Timer.new(GALE_BASH_CD)
ZmajaEncounter.galeDonutTimer  = Timer.new(GALE_DONUT_CD)
-- Portal
ZmajaEncounter.portalTimer     = Timer.new(PORTAL_OPEN_DUR)  -- open → close countdown
ZmajaEncounter.portalNextTimer = Timer.new(PORTAL_NEXT_CD)   -- close → next open countdown

-- ── Mini-boss presence ────────────────────────────────────────────────────
ZmajaEncounter.siroActive = false
ZmajaEncounter.releActive = false
ZmajaEncounter.galeActive = false

-- ── Portal / Z'Maja state ─────────────────────────────────────────────────
ZmajaEncounter.portalGroup   = 0      -- increments on each PORTAL_OPEN (1, 2, 3…)
ZmajaEncounter.portalActive  = false
ZmajaEncounter.executePhase  = false
ZmajaEncounter.spearCount    = 0
ZmajaEncounter.coreAlert     = nil    -- "Core out!" / "Core MISSED!" / nil

-- ── CA cast-bar tracking ──────────────────────────────────────────────────
ZmajaEncounter.alertList = {}

function ZmajaEncounter:reset()
    self.siroJumpTimer:clear()
    self.siroBannerTimer:clear()
    self.releJumpTimer:clear()
    self.releBashTimer:clear()
    self.releJoltTimer:clear()
    self.galeJumpTimer:clear()
    self.galeBashTimer:clear()
    self.galeDonutTimer:clear()
    self.portalTimer:clear()
    self.portalNextTimer:clear()
    self.siroActive    = false
    self.releActive    = false
    self.galeActive    = false
    self.portalGroup   = 0
    self.portalActive  = false
    self.executePhase  = false
    self.spearCount    = 0
    self.coreAlert     = nil
    for _, cid in pairs(self.alertList) do caCastAlertsStop(cid) end
    self.alertList = {}
end

-- ── Combat events ─────────────────────────────────────────────────────────
function ZmajaEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)

    -- ── Mini activation: first ability from a mini marks it as live ───────
    if not self.siroActive and SIRO_IDS[abilityId] then
        self.siroActive = true
    elseif not self.releActive and RELE_IDS[abilityId] then
        self.releActive = true
    elseif not self.galeActive and GALE_IDS[abilityId] then
        self.galeActive = true
    end

    -- ── Mini death: Z'Maja shackles the mini out of the fight ────────────
    if abilityId == ZMAJA_SHACKLE and result == ACTION_RESULT_EFFECT_GAINED then
        if unitName and unitName:find("Siroria") then
            self.siroActive = false
            self.siroJumpTimer:clear()
            self.siroBannerTimer:clear()
        elseif unitName and unitName:find("Relequen") then
            self.releActive = false
            self.releJumpTimer:clear()
            self.releBashTimer:clear()
            self.releJoltTimer:clear()
        elseif unitName and unitName:find("Galenwe") then
            self.galeActive = false
            self.galeJumpTimer:clear()
            self.galeBashTimer:clear()
            self.galeDonutTimer:clear()
        end
        return
    end

    -- ── SIRORIA ───────────────────────────────────────────────────────────
    if abilityId == SIRO_HA and result == ACTION_RESULT_BEGIN then
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Siroria HA! (" .. target .. ")")
        local dur = select(1, GetAbilityCastInfo(SIRO_HA)) or 0
        if dur <= 0 then dur = 1500 end
        local cid = caAlertCast(abilityId, "Siro HA!", dur, COL_SIRO)
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == SIRO_JUMP and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Siroria jumping!")
        self.siroJumpTimer:reset()

    elseif abilityId == SIRO_BANNER and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Siroria Banner!")
        self.siroBannerTimer:reset()

    elseif (abilityId == SIRO_FLARE or abilityId == SIRO_FLARE_EXEC)
           and result == ACTION_RESULT_BEGIN then
        -- Roaring Flare: Siroria targets a player; show who needs to move
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Flare → " .. target)
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = math.floor(FLARE_WINDOW * 1000) end
        local cid = caAlertCast(abilityId, "Flare → " .. target, dur, COL_SIRO)
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == SIRO_DARK_TALONS and result == ACTION_RESULT_EFFECT_GAINED
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Rooted! (Siroria)")

    -- ── RELEQUEN ──────────────────────────────────────────────────────────
    elseif abilityId == RELE_HA and result == ACTION_RESULT_BEGIN then
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Relequen HA! (" .. target .. ")")
        local dur = select(1, GetAbilityCastInfo(RELE_HA)) or 0
        if dur <= 0 then dur = 1500 end
        local cid = caAlertCast(abilityId, "Rele HA!", dur, COL_RELE)
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == RELE_JUMP and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Relequen jumping!")
        self.releJumpTimer:reset()

    elseif abilityId == RELE_DIRECT_CURR and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Relequen!")
        caAlert(nil, "INTERRUPT!", 0xFF0000FF, SOUNDS.NONE, 2500)
        self.releBashTimer:reset()

    elseif abilityId == RELE_JOLT and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Relequen Jolt! Move!")
        self.releJoltTimer:reset()

    elseif (abilityId == RELE_OVERLOAD_1 or abilityId == RELE_OVERLOAD_2)
           and result == ACTION_RESULT_EFFECT_GAINED_DURATION
           and IsUnitPlayer(unitTag) then
        if abilityId == RELE_OVERLOAD_1 then
            alerts:showAction("Overload incoming — bar swap!")
        else
            alerts:showAction("Overload on you — swap now!")
            caAlert(nil, "BAR SWAP", 0x3399FFFF, SOUNDS.NONE, 3000)
        end

    -- ── GALENWE ───────────────────────────────────────────────────────────
    elseif abilityId == GALE_HA and result == ACTION_RESULT_BEGIN then
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Galenwe HA! (" .. target .. ")")
        local dur = select(1, GetAbilityCastInfo(GALE_HA)) or 0
        if dur <= 0 then dur = 1500 end
        local cid = caAlertCast(abilityId, "Gale HA!", dur, COL_GALE)
        if cid and unitId then self.alertList[unitId] = cid end

    elseif abilityId == GALE_JUMP and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Galenwe jumping!")
        self.galeJumpTimer:reset()

    elseif abilityId == GALE_GLACIAL and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Interrupt Galenwe!")
        caAlert(nil, "INTERRUPT!", 0xFF0000FF, SOUNDS.NONE, 2500)
        self.galeBashTimer:reset()

    elseif abilityId == GALE_DONUT and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Galenwe Donut! Out!")
        self.galeDonutTimer:reset()

    elseif (abilityId == GALE_HOARFROST or abilityId == GALE_HOARFROST_2)
           and result == ACTION_RESULT_EFFECT_GAINED
           and IsUnitPlayer(unitTag) then
        -- Player picked up hoarfrost — show name and 6 s drop countdown
        local carrier = GetUnitDisplayName("player") or "you"
        alerts:showAction("Frost! Drop in 6s (" .. carrier .. ")")
        caAlert(nil, "FROST — drop in 6s", 0x00EEEEff, SOUNDS.NONE, 4000)

    elseif (abilityId == GALE_HOARFROST or abilityId == GALE_HOARFROST_2)
           and result == ACTION_RESULT_EFFECT_GAINED
           and not IsUnitPlayer(unitTag)
           and unitName and unitName ~= "" then
        -- Another player got hoarfrost — announce their name
        alerts:showAction("Frost → " .. unitName)

    elseif (abilityId == GALE_HOARFROST_SY or abilityId == GALE_HOARFROST_S2)
           and result == ACTION_RESULT_EFFECT_GAINED_DURATION
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Drop frost now!")
        caAlert(nil, "DROP FROST!", 0x00EEEEff, SOUNDS.NONE, 2000)

    elseif (abilityId == GALE_COMET or abilityId == GALE_COMET_2)
           and result == ACTION_RESULT_EFFECT_GAINED
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Chilling Comet! Move!")
        caAlert(nil, "COMET — move!", 0x00AAFFFF, SOUNDS.NONE, 2500)

    -- ── ENVIRONMENT ───────────────────────────────────────────────────────
    elseif abilityId == RAZOR_THORNS and result == ACTION_RESULT_EFFECT_GAINED
           and IsUnitPlayer(unitTag) then
        alerts:showAction("Rooted! (Creeper)")

    -- ── PORTAL ────────────────────────────────────────────────────────────
    elseif abilityId == PORTAL_OPEN and result == ACTION_RESULT_BEGIN then
        self.portalGroup  = self.portalGroup + 1
        self.portalActive = true
        self.portalTimer:reset(PORTAL_OPEN_DUR)
        self.portalNextTimer:clear()
        alerts:showHeader("Shadow Realm — Group " .. self.portalGroup)

    elseif (abilityId == PORTAL_CLOSE_1 or abilityId == PORTAL_CLOSE_2)
           and result == ACTION_RESULT_BEGIN then
        self.portalActive = false
        self.portalTimer:clear()
        self.portalNextTimer:reset(PORTAL_NEXT_CD)
        self.coreAlert = nil

    -- ── Z'MAJA ────────────────────────────────────────────────────────────
    elseif abilityId == ZMAJA_JUMP and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Z'Maja jumping!")

    elseif abilityId == ZMAJA_HIDE_JUMP and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Z'Maja retreating to shadow!")

    elseif (abilityId == CRUSHING_DARK_1 or abilityId == CRUSHING_DARK_2
            or abilityId == CRUSHING_DARK_3) and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Kite! Crushing Darkness")
        local dur = select(1, GetAbilityCastInfo(abilityId)) or 0
        if dur <= 0 then dur = 6000 end
        caAlertCast(abilityId, "KITE!", dur, COL_ZMAJA)

    elseif abilityId == SHADOW_SPLASH and result == ACTION_RESULT_BEGIN then
        alerts:showAction("Shadow Splash! Interrupt!")
        caAlert(nil, "INTERRUPT!", 0xFF0000FF, SOUNDS.NONE, 2500)

    elseif abilityId == BANEFUL_MARK and result == ACTION_RESULT_BEGIN then
        self.executePhase = true
        alerts:showAction("Baneful Mark! (execute)")
        caAlert(nil, "BANEFUL MARK", 0xFF4444FF, SOUNDS.NONE, 4000)

    elseif abilityId == OLORIME_SPEAR
           and (result == ACTION_RESULT_EFFECT_GAINED or result == ACTION_RESULT_BEGIN) then
        self.spearCount = self.spearCount + 1
        local target = (unitName and unitName ~= "") and unitName or "?"
        alerts:showAction("Spear → " .. target .. " (" .. self.spearCount .. ")")

    -- ── MALEVOLENT CORES ──────────────────────────────────────────────────
    elseif abilityId == CORE_EXPOSED and result == ACTION_RESULT_BEGIN then
        self.coreAlert = "Core out! Pick it up!"
        alerts:showAction("Core exposed!")
        caAlert(nil, "CORE OUT!", 0xFFDD00FF, SOUNDS.NONE, 4000)

    elseif abilityId == CORE_MISSED and result == ACTION_RESULT_BEGIN then
        self.coreAlert = "Core MISSED!"
        alerts:showAction("Core missed!")
        caAlert(nil, "CORE MISSED!", 0xFF4444FF, SOUNDS.NONE, 5000)

    elseif abilityId == CORE_PICKED_UP and result == ACTION_RESULT_BEGIN then
        self.coreAlert = nil
        alerts:showAction("Core picked up.")
    end
end

-- ── Effect changed ────────────────────────────────────────────────────────
function ZmajaEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- CR-3: portal world-state, mini shackle via effect path, execute phase
end

-- ── 200 ms display update ─────────────────────────────────────────────────
function ZmajaEncounter:onUpdate(context, alerts)
    -- Line 1: Portal status — open countdown or next-portal countdown
    if self.portalActive then
        local r = self.portalTimer:remaining()
        local t = r > 0 and ZO_FormatCountdownTimer(r) or "closing"
        alerts:showInfo(1, "Portal open: " .. t)
    elseif not self.portalNextTimer:isExpired() then
        local r = self.portalNextTimer:remaining()
        alerts:showInfo(1, "Next portal: " .. ZO_FormatCountdownTimer(r))
    else
        alerts:showInfo(1, "")
    end

    -- Line 2: Portal group label / execute phase
    if self.executePhase then
        alerts:showInfo(2, "!!! EXECUTE PHASE !!!")
    elseif self.portalGroup > 0 then
        alerts:showInfo(2, "Shadow Group " .. self.portalGroup)
    else
        alerts:showInfo(2, "")
    end

    -- Line 3: Core alert (persistent until resolved)
    alerts:showInfo(3, self.coreAlert or "")

    -- Line 4: Olorime Spear count
    if self.spearCount > 0 then
        alerts:showInfo(4, "Spears: " .. self.spearCount)
    else
        alerts:showInfo(4, "")
    end

    -- Line 5: Siroria timers
    if self.siroActive then
        local j = self.siroJumpTimer:remaining()
        local b = self.siroBannerTimer:remaining()
        local jt = j > 0 and ZO_FormatCountdownTimer(j) or "ready"
        local bt = b > 0 and ZO_FormatCountdownTimer(b) or "ready"
        alerts:showInfo(5, "Siro: Jump " .. jt .. "  Bnr " .. bt)
    else
        alerts:showInfo(5, "")
    end

    -- Line 6: Relequen timers
    if self.releActive then
        local j = self.releJumpTimer:remaining()
        local b = self.releBashTimer:remaining()
        local jt = j > 0 and ZO_FormatCountdownTimer(j) or "ready"
        local bt = b > 0 and ZO_FormatCountdownTimer(b) or "INTERRUPT"
        alerts:showInfo(6, "Rele: Jump " .. jt .. "  Bash " .. bt)
    else
        alerts:showInfo(6, "")
    end

    -- Line 7: Galenwe timers
    if self.galeActive then
        local j = self.galeJumpTimer:remaining()
        local b = self.galeBashTimer:remaining()
        local jt = j > 0 and ZO_FormatCountdownTimer(j) or "ready"
        local bt = b > 0 and ZO_FormatCountdownTimer(b) or "INTERRUPT"
        alerts:showInfo(7, "Gale: Jump " .. jt .. "  Bash " .. bt)
    else
        alerts:showInfo(7, "")
    end
end

function ZmajaEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- CR-3: execute threshold pre-warning (if applicable)
end

return ZmajaEncounter
