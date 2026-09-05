local Location = require("core.Location")
local Timer = require("lib.Timer")
local Lang = require("core.Lang")
local Fmt  = require("core.Fmt")

local COL_SKIP = "55aa55"   -- medium green (gryphon skip)
local COL_FAIL = "cc4444"   -- red (gryphon fail HP)

local CA = require("external-api.CombatAlerts")
local BossBase = require("lib.BossBase")
local CastDur = require("lib.CastDur")

-- -- Ability IDs (from BSCHTKA_Yandir.lua) ---------------------------------
local TOTEM_POISON       = 133515  -- combatRoute: ACTION_RESULT_BEGIN -> resets timer + Dodge alert
local TOTEM_POISON_CP    = 133559  -- combatRoute: ACTION_RESULT_EFFECT_GAINED -> delayed 26.8s CA bar
local TOTEM_HARPY_SPWN   = 133510  -- combatRoute: ACTION_RESULT_BEGIN -> resets totem timer
local TOTEM_DRAGON_SPWN  = 133045  -- combatRoute: ACTION_RESULT_BEGIN -> resets totem timer
local TOTEM_GARGYL_SPWN  = 133513  -- combatRoute: ACTION_RESULT_BEGIN -> resets totem timer
local TOTEM_GARGYL       = 133546  -- combatRoute: ACTION_RESULT_BEGIN -> Block alert + caAlertCast
local YANDIR_HEALING     = 133242  -- combatRoute: ACTION_RESULT_BEGIN -> Healing alert
local YANDIR_JUMP        = 132571  -- combatRoute: ACTION_RESULT_BEGIN -> Block alert + caAlertCast
local SEA_ADDER_BILE_SPRAY = 136591  -- combatRoute: ACTION_RESULT_BEGIN -> Dodge alert (player-targeted)

-- -- Spawn/cast durations --------------------------------------------------
local TOTEM_SPAWN_TIME  = 20
local GRYPHON_SPAWN_TIME = 60

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DUR = 5000   -- TOTEM_GARGYL (Gargoyle Totem cast): empirical

local Yandir = {}
Yandir.__index = Yandir
setmetatable(Yandir, {__index = BossBase})   -- inherit cleanupAlertList, default onDied

Yandir.key               = "yandir"
Yandir.hmHealthThreshold = 72769370
Yandir.location          = Location.new(63200, 68900, 24300, 26300, 90500, 99600)

Yandir.stateSchema = {
    totemTimer           = function() return Timer.new(TOTEM_SPAWN_TIME) end,
    gryphonTimer         = function() return Timer.new(GRYPHON_SPAWN_TIME) end,
    bGRYPHON_SKIP        = false,
    -- Seconds remaining on the gryphon timer at the moment the skip was
    -- detected  -  displayed as "(Xs early)" so raiders see the margin.
    bGRYPHON_SKIP_TIME   = 0,
    bGRYPHON_SKIP_FAILHP = 0,
    poisonTotemId        = -1,   -- unitId of the currently targeted poison totem
    BTotemCall           = false,
    -- zo_callLater handle for the 26.8 s delayed second-poison bar.
    -- Stored so it can be cancelled on wipe or zone exit.
    poisonTotemTimer     = false,
    -- [unitId] -> CA cast bar ID; cleared and stopped on leave/death.
    alertList            = function() return {} end,
}

function Yandir.new()
    return BossBase.fromSchema(Yandir)
end

-- -- Lifecycle -------------------------------------------------------------

-- Cancel any pending delayed poison-totem CA bar and stop all alert bars.
-- Called from both onLeave (zone exit) and onWipe so neither path leaks.
local function yandir_cleanup(self)
    self:cleanupAlertList()
    self:cancelAfter(self.poisonTotemTimer)
    self.poisonTotemTimer = false
end

function Yandir:onLeave(context)
    yandir_cleanup(self)
end

-- Soft reset on wipe while still inside the trial zone.  Stops bars and
-- resets all per-pull flags so the next pull starts clean without discarding
-- the boss class's position icons (Yandir has none, but the pattern is here
-- for consistency with Vrol and Falgravn).
function Yandir:onWipe(context, alerts)
    yandir_cleanup(self)
    self.bGRYPHON_SKIP        = false
    self.bGRYPHON_SKIP_TIME   = 0
    self.bGRYPHON_SKIP_FAILHP = 0
    self.poisonTotemId        = -1
    self.BTotemCall           = false
end

-- -- Combat state (fight start / wipe) -------------------------------------
-- Arms both timers when the pull starts.  Timer.new() leaves expiresAt = 0,
-- so isExpired() would return true immediately without this reset.
function Yandir:onCombatState(context, inCombat, alerts)
    if inCombat then
        self.totemTimer:reset()
        self.gryphonTimer:reset()
    end
end

-- 200ms timer display  -  writes to info lines 1-2.
-- No-op when sink has no info handler (e.g. LegacyUI during the KA transition).
function Yandir:onUpdate(context, alerts)
    local t1 = self.totemTimer:remaining()
    alerts:showInfo(1, Lang.t("ka_yandir_totem_label")
        .. (t1 > 0 and ZO_FormatCountdownTimer(t1) or Lang.t("common_ready")))
    local line2
    if self.bGRYPHON_SKIP then
        -- Show how much time was left on the timer when the skip was detected.
        local earlyTag = self.bGRYPHON_SKIP_TIME > 0
            and Lang.t("ka_yandir_gryphon_early", ZO_FormatCountdownTimer(self.bGRYPHON_SKIP_TIME))
            or ""
        line2 = Lang.t("ka_yandir_gryphon_label") .. Fmt.c(COL_SKIP, Lang.t("ka_yandir_gryphon_skip")) .. earlyTag
    elseif self.bGRYPHON_SKIP_FAILHP > 0 then
        line2 = Lang.t("ka_yandir_gryphon_label") .. Fmt.c(COL_FAIL, Lang.t("ka_yandir_gryphon_fail", Fmt.pct(self.bGRYPHON_SKIP_FAILHP)))
    else
        local t2 = self.gryphonTimer:remaining()
        line2 = Lang.t("ka_yandir_gryphon_label")
            .. (t2 > 0 and ZO_FormatCountdownTimer(t2) or Lang.t("common_ready"))
    end
    alerts:showInfo(2, line2)
end

-- -- Routing tables (C3) --------------------------------------------------
-- DIED: delegate alertList cleanup to BossBase, then handle totem-specific state.
function Yandir:onDied(context, alerts,
                        unitTag, sourceUnitTag, sourceUnitId, unitId,
                        sourceUnitName, unitName)
    -- BossBase stops and clears alertList[unitId] and alertList[sourceUnitId].
    BossBase.onDied(self, context, alerts,
        unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
    -- If the player targeted by the poison totem dies, cancel the delayed bar.
    if self.poisonTotemId == unitId or self.poisonTotemId == sourceUnitId then
        self.poisonTotemId = -1
        self.BTotemCall    = false
    end
end

-- Any totem spawn (Harpy/Dragon/Gargoyle spawn IDs) resets the recurring timer.
local function resetTotemTimer(self, context, alerts, result, abilityId, ...)
    if result == ACTION_RESULT_BEGIN then self.totemTimer:reset() end
end

local function handlePoisonTotem(self, context, alerts, abilityId,
                                  unitTag, sourceUnitTag, sourceUnitId, unitId,
                                  sourceUnitName, unitName)
    self.totemTimer:reset()
    alerts:showAction(Lang.t("ka_yandir_dodge_poison"))
    local cid = CA.alertCast(abilityId, sourceUnitName, 4300,
        { -3, 0, false, { 0, 0.8, 0, 0.4 }, { 0, 0.8, 0, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
    self.poisonTotemId = unitId  -- track for delayed second-poison bar
end

local function handlePoisonTotemCp(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    -- Second poison from the same totem ~26.8 s after first cast.
    -- Guard with BTotemCall so only one delayed bar fires per totem spawn.
    if self.BTotemCall then return end
    self.BTotemCall = true
    local capturedSrc = sourceUnitName or ""
    -- Store the handle so yandir_cleanup can cancel it if the zone is exited
    -- or the group wipes before the 26.8 s fires.  Trial:cancelPending is a
    -- second net on both paths.
    self.poisonTotemTimer = self:after(26800, function()
        self.poisonTotemTimer = false
        if self.poisonTotemId ~= -1 and IsUnitInCombat("player") then
            self.BTotemCall = false
            CA.alertCast(TOTEM_POISON_CP, capturedSrc, 4300,
                { -3, 0, false, { 0, 0.8, 0, 0.4 }, { 0, 0.8, 0, 0.8 } })
        end
    end)
end

local function handleGargoyleTotem(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    alerts:showAction(Lang.t("ka_yandir_block_gargoyle"))
    local dur = CastDur.get(TOTEM_GARGYL, FALLBACK_DUR)
    local cid = CA.alertCast(abilityId, "Block!!", dur,
        { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleYandirHealing(self, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ka_yandir_casts_healing"))
    CA.alert(nil, Lang.t("ka_yandir_casts_healing"), 0x991111FF, SOUNDS.NONE, 2000)
end

local function handleYandirJump(self, context, alerts, abilityId,
                                 unitTag, sourceUnitTag, sourceUnitId, unitId,
                                 sourceUnitName, unitName)
    alerts:showAction(Lang.t("ka_yandir_jump_block"))
    local cid = CA.alertCast(abilityId, Lang.t("ka_yandir_jump_block"), 3000,
        { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
end

local function handleSeaAdderSpray(self, context, alerts, abilityId,
                                    unitTag, sourceUnitTag, sourceUnitId, unitId,
                                    sourceUnitName, unitName)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("ka_yandir_dodge_sea_adder"))
    local cid = CA.alertCast(abilityId, sourceUnitName, 1933,
        { -3, 0, false, { 0.7, 0.7, 0.7, 0.4 }, { 0.7, 0.7, 0.7, 0.8 } })
    if cid and unitId then self.alertList[unitId] = cid end
end

Yandir.combatRoutes = {
    [TOTEM_POISON]       = { result = ACTION_RESULT_BEGIN,         fn = handlePoisonTotem },
    [TOTEM_POISON_CP]    = { result = ACTION_RESULT_EFFECT_GAINED, fn = handlePoisonTotemCp },
    [TOTEM_HARPY_SPWN]   = resetTotemTimer,
    [TOTEM_DRAGON_SPWN]  = resetTotemTimer,
    [TOTEM_GARGYL_SPWN]  = resetTotemTimer,
    [TOTEM_GARGYL]       = { result = ACTION_RESULT_BEGIN,         fn = handleGargoyleTotem },
    [YANDIR_HEALING]     = { result = ACTION_RESULT_BEGIN,         fn = handleYandirHealing },
    [YANDIR_JUMP]        = { result = ACTION_RESULT_BEGIN,         fn = handleYandirJump },
    [SEA_ADDER_BILE_SPRAY] = { result = ACTION_RESULT_BEGIN,       fn = handleSeaAdderSpray },
}

function Yandir:onPowerUpdate(context, healthPercent)
    if healthPercent < 60 and not self.gryphonTimer:isExpired() then
        if not self.bGRYPHON_SKIP then
            -- Capture how many seconds remained on the gryphon timer so we
            -- can display "Skip! (Xs early)" in onUpdate.
            self.bGRYPHON_SKIP_TIME = self.gryphonTimer:remaining()
        end
        self.bGRYPHON_SKIP = true
    end

    if healthPercent > 60 and self.gryphonTimer:isExpired() then
        if self.bGRYPHON_SKIP_FAILHP == 0 then
            self.bGRYPHON_SKIP_FAILHP = healthPercent
        end
    end
end

package.loaded["trial.ka.boss.Yandir"] = Yandir
return Yandir
