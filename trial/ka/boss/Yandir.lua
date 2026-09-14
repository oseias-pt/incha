local Location          = require("core.Location")
local Timer             = require("lib.Timer")
local Lang              = require("core.Lang")
local Fmt               = require("core.Fmt")

local AlertTypes        = require("core.AlertTypes")
local CA                = require("external-api.CombatAlerts")
local BossBase          = require("lib.BossBase")
local CastDur           = require("lib.CastDur")
local Colors            = require("core.Colors")
local EventDispatcher   = require("core.EventDispatcher")

-- -- Ability IDs -------------------------------------------------------------
local TOTEM_POISON          = 133515  -- Chaurus Totem: resets timer + Dodge alert
local TOTEM_POISON_CP       = 133559  -- Chaurus Totem: delayed 26.8s second-poison bar
local TOTEM_HARPY_SPWN      = 133510  -- Harpy Totem spawn: resets totem timer
local TOTEM_DRAGON_SPWN     = 133045  -- Dragon Totem spawn: resets totem timer
local TOTEM_GARGYL_SPWN     = 133513  -- Gargoyle Totem spawn: resets totem timer
local TOTEM_GARGYL          = 133546  -- Gargoyle Totem attack: Block alert
local YANDIR_HEALING        = 133242  -- Heal Pet: Healing alert
local YANDIR_JUMP           = 132571  -- Hailstone Burst: Block alert
local SEA_ADDER_BILE_SPRAY  = 136591  -- Sea Adder Bile Spray: Dodge alert (player-targeted)
local TOXIC_TIDE            = 132511  -- Cleave: 2500ms AoE frontal swing + poison DoT
local BUTCHERS_BLADE        = 135324  -- Uppercut: 1600ms single-target blockable physical
local SUNDERING_STRIKE      = 135369  -- Shatter: 400ms AoE ground slam, post-50%, knockdown

-- -- Spawn/cast durations --------------------------------------------------
local TOTEM_SPAWN_TIME   = 20
local GRYPHON_SPAWN_TIME = 60

-- -- Fallback durations (empirical; replace if GetAbilityCastInfo becomes reliable) -
local FALLBACK_DUR = 5000   -- TOTEM_GARGYL (Gargoyle Totem cast): empirical

local Yandir = {}
Yandir.__index = Yandir
setmetatable(Yandir, {__index = BossBase})   -- inherit cleanupAlertList, default onDied

Yandir.key               = "yandir"
-- Health-pool threshold between NM and HM; re-verify after major patches.
Yandir.hmHealthThreshold = 72769370
Yandir.location          = Location.new(63200, 68900, 24300, 26300, 90500, 99600)

-- -- stateSchema factories --------------------------------------------------
local function newTotemTimer()   return Timer.new(TOTEM_SPAWN_TIME) end
local function newGryphonTimer() return Timer.new(GRYPHON_SPAWN_TIME) end
local function newAlertList()    return {} end

Yandir.stateSchema = {
    totemTimer           = newTotemTimer,
    gryphonTimer         = newGryphonTimer,
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
    alertList            = newAlertList,
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

-- 200ms timer display  -  writes to tracker rows 1-2.
function Yandir:onUpdate(context, alerts)
    local t1 = self.totemTimer:remaining()
    if t1 > 0 then
        alerts:setRow(1, Lang.t("ka_yandir_totem_label"), t1)
    else
        alerts:setRow(1, Lang.t("ka_yandir_totem_label") .. " " .. Lang.t("common_ready"), nil)
    end

    if self.bGRYPHON_SKIP then
        -- Static: show how much time was left when the skip fired.
        local earlyTag = self.bGRYPHON_SKIP_TIME > 0
            and Lang.t("ka_yandir_gryphon_early", ZO_FormatCountdownTimer(self.bGRYPHON_SKIP_TIME))
            or ""
        alerts:setRow(2, Lang.t("ka_yandir_gryphon_label") .. " " .. Fmt.c(Fmt.LEAF, Lang.t("ka_yandir_gryphon_skip")) .. earlyTag, nil)
    elseif self.bGRYPHON_SKIP_FAILHP > 0 then
        alerts:setRow(2, Lang.t("ka_yandir_gryphon_label") .. " " .. Fmt.c(Fmt.CRIMSON, Lang.t("ka_yandir_gryphon_fail") .. Fmt.pct(self.bGRYPHON_SKIP_FAILHP)), nil)
    else
        local t2 = self.gryphonTimer:remaining()
        if t2 > 0 then
            alerts:setRow(2, Lang.t("ka_yandir_gryphon_label"), t2)
        else
            alerts:setRow(2, Lang.t("ka_yandir_gryphon_label") .. " " .. Lang.t("common_ready"), nil)
        end
    end
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

-- -- Handlers ---------------------------------------------------------------

local function handlePoisonTotem(boss, context, alerts, abilityId, sourceUnitName,
                                  unitTag, unitId, sourceUnitId, unitName)
    boss.totemTimer:reset()
    alerts:showAction(Lang.t("ka_yandir_dodge_poison"))
    local cid = CA.ranged(abilityId, sourceUnitName, 4300, Colors.POISON)
    if cid and unitId then boss.alertList[unitId] = cid end
    boss.poisonTotemId = unitId  -- track for delayed second-poison bar
end

-- Fires ~26.8 s after the Chaurus Totem's first cast to show the second
-- poison bar.  Captured in a named local so the readability of the parent
-- handler is not harmed by an inline closure.
local function onDelayedPoisonFired(boss, capturedSrc)
    boss.poisonTotemTimer = false
    if boss.poisonTotemId ~= -1 and IsUnitInCombat("player") then
        boss.BTotemCall = false
        CA.ranged(TOTEM_POISON_CP, capturedSrc, 4300, Colors.POISON)
    end
end

local function handlePoisonTotemCp(boss, context, alerts, abilityId, sourceUnitName, ...)
    -- Second poison from the same totem ~26.8 s after first cast.
    -- Guard with BTotemCall so only one delayed bar fires per totem spawn.
    if boss.BTotemCall then return end
    boss.BTotemCall = true
    local capturedSrc = sourceUnitName or ""
    -- Store the handle so yandir_cleanup can cancel it if the zone is exited
    -- or the group wipes before the 26.8 s fires.  Trial:cancelPending is a
    -- second net on both paths.
    boss.poisonTotemTimer = boss:after(26800, function()
        onDelayedPoisonFired(boss, capturedSrc)
    end)
end

local function handleGargoyleTotem(boss, context, alerts, abilityId, sourceUnitName,
                                    unitTag, unitId, sourceUnitId, unitName)
    alerts:showAction(Lang.t("ka_yandir_block_gargoyle"))
    local dur = CastDur.get(TOTEM_GARGYL, FALLBACK_DUR)
    local cid = CA.ranged(abilityId, "Block!!", dur, Colors.SILVER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleYandirHealing(boss, context, alerts, abilityId, ...)
    alerts:showAction(Lang.t("ka_yandir_casts_healing"))
    CA.alert(nil, Lang.t("ka_yandir_casts_healing"), 0x991111FF, SOUNDS.NONE, 2000)
end

local function handleYandirJump(boss, context, alerts, abilityId, sourceUnitName,
                                 unitTag, unitId, sourceUnitId, unitName)
    alerts:showAction(Lang.t("ka_yandir_jump_block"))
    local cid = CA.ranged(abilityId, Lang.t("ka_yandir_jump_block"), 3000, Colors.SILVER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleSeaAdderSpray(boss, context, alerts, abilityId, sourceUnitName,
                                    unitTag, unitId, sourceUnitId, unitName)
    if not IsUnitPlayer(unitTag) then return end
    alerts:showAction(Lang.t("ka_yandir_dodge_sea_adder"))
    local cid = CA.ranged(abilityId, sourceUnitName, 1933, Colors.SILVER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleToxicTide(boss, context, alerts, abilityId, sourceUnitName,
                                unitTag, unitId, sourceUnitId, unitName)
    alerts:showAction(Lang.t("ka_yandir_block_cleave"))
    local cid = CA.ranged(abilityId, Lang.t("ka_yandir_block_cleave"), 2500, Colors.SILVER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleButchersBlade(boss, context, alerts, abilityId, sourceUnitName,
                                    unitTag, unitId, sourceUnitId, unitName)
    alerts:showAction(Lang.t("ka_yandir_block_uppercut"))
    local cid = CA.ranged(abilityId, Lang.t("ka_yandir_block_uppercut"), 1600, Colors.SILVER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleSunderingStrike(boss, context, alerts, abilityId, sourceUnitName,
                                      unitTag, unitId, sourceUnitId, unitName)
    alerts:showAction(Lang.t("ka_yandir_block_shatter"))
    local cid = CA.ranged(abilityId, Lang.t("ka_yandir_block_shatter"), 1600, Colors.SILVER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

-- -- Events table -----------------------------------------------------------
-- All entries live in both instant and started beginCast buckets: cast time
-- is sourced from GetAbilityCastInfo at runtime; covering both ensures the
-- alert fires regardless of when the T event arrives.
-- TOTEM_POISON_CP fires via effectChanged.gained (EFFECT_RESULT_GAINED).

local _beginCastEntry = {
    [TOTEM_POISON]         = { type = AlertTypes.CUSTOM,      fn = handlePoisonTotem                          },
    [TOTEM_HARPY_SPWN]     = { type = AlertTypes.TIMER_RESET,                         timer = "totemTimer"    },
    [TOTEM_DRAGON_SPWN]    = { type = AlertTypes.TIMER_RESET,                         timer = "totemTimer"    },
    [TOTEM_GARGYL_SPWN]    = { type = AlertTypes.TIMER_RESET,                         timer = "totemTimer"    },
    [TOTEM_GARGYL]         = { type = AlertTypes.CUSTOM,      fn = handleGargoyleTotem                        },
    [YANDIR_HEALING]       = { type = AlertTypes.CUSTOM,      fn = handleYandirHealing                        },
    [YANDIR_JUMP]          = { type = AlertTypes.CUSTOM,      fn = handleYandirJump                           },
    [SEA_ADDER_BILE_SPRAY] = { type = AlertTypes.CUSTOM,      fn = handleSeaAdderSpray                        },
    [TOXIC_TIDE]           = { type = AlertTypes.CUSTOM,      fn = handleToxicTide                            },
    [BUTCHERS_BLADE]       = { type = AlertTypes.CUSTOM,      fn = handleButchersBlade, targetOnly = true     },
    [SUNDERING_STRIKE]     = { type = AlertTypes.CUSTOM,      fn = handleSunderingStrike                      },
}

-- Split into two independent copies so EventDispatcher.build() validates each
-- bucket separately and future per-bucket entries can't cross-contaminate.
local _beginCastInstant = {}
local _beginCastStarted = {}
for k, v in pairs(_beginCastEntry) do _beginCastInstant[k] = v; _beginCastStarted[k] = v end

Yandir.events = {
    beginCast = {
        instant = _beginCastInstant,
        started = _beginCastStarted,
    },
    effectChanged = {
        gained = {
            [TOTEM_POISON_CP] = { type = AlertTypes.CUSTOM, fn = handlePoisonTotemCp },
        },
    },
}

EventDispatcher.build(Yandir)

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
