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

-- Tracker-row strings built once at load so the 200 ms onUpdate never
-- concatenates or calls Lang.t / Fmt.c (see Falgravn.lua for the pattern).
local _STR_TOTEM         = Lang.t("ka_yandir_totem_label")
local _STR_TOTEM_READY   = Lang.t("ka_yandir_totem_label") .. " " .. Lang.t("common_ready")
local _STR_GRYPHON       = Lang.t("ka_yandir_gryphon_label")
local _STR_GRYPHON_READY = Lang.t("ka_yandir_gryphon_label") .. " " .. Lang.t("common_ready")
local _STR_GRYPHON_SKIP  = Lang.t("ka_yandir_gryphon_label") .. " " .. Fmt.c(Fmt.LEAF, Lang.t("ka_yandir_gryphon_skip"))
local _STR_GRYPHON_FAIL  = Lang.t("ka_yandir_gryphon_label") .. " "
local _STR_BLOCK_GARGOYLE     = Lang.t("ka_yandir_block_gargoyle")
local _STR_KILL_HARPY_TOTEM   = Lang.t("ka_yandir_kill_harpy_totem")
local _STR_KILL_DRAGON_TOTEM  = Lang.t("ka_yandir_kill_dragon_totem")
local _STR_KILL_GARGYL_SPWN   = Lang.t("ka_yandir_kill_gargoyle_spwn")

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
    -- Row-2 text for the skip / fail states.  Built once by onPowerUpdate
    -- when the state is entered; onUpdate only reads it.
    gryphonRowText       = false,
    poisonTotemId        = -1,   -- unitId of the currently targeted poison totem
    BTotemCall           = false,
    bPlayerPoisoned      = false, -- true while the local player carries the TOTEM_POISON_CP effect
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
    self.gryphonRowText       = false
    self.poisonTotemId        = -1
    self.BTotemCall           = false
    self.bPlayerPoisoned      = false
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
    local now = GetGameTimeMilliseconds() / 1000
    local t1 = self.totemTimer:remainingAt(now)
    if t1 > 0 then
        alerts:setRow(1, _STR_TOTEM, t1)
    else
        alerts:setRow(1, _STR_TOTEM_READY, nil)
    end

    if self.gryphonRowText then
        -- Skip / fail state: static text built once in onPowerUpdate.
        alerts:setRow(2, self.gryphonRowText, nil)
    else
        local t2 = self.gryphonTimer:remainingAt(now)
        if t2 > 0 then
            alerts:setRow(2, _STR_GRYPHON, t2)
        else
            alerts:setRow(2, _STR_GRYPHON_READY, nil)
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
    boss.poisonTotemId = unitId  -- track for delayed second-poison bar
    if boss.bPlayerPoisoned then
        alerts:showAction(Lang.t("ka_yandir_stand_still_poison"))
    else
        alerts:showAction(Lang.t("ka_yandir_kill_poison_totem"))
        local cid = CA.ranged(abilityId, sourceUnitName, 4300, Colors.POISON)
        if cid and unitId then boss.alertList[unitId] = cid end
    end
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

local function handlePoisonTotemCp(boss, context, alerts, abilityId, unitName,
                                    unitTag, unitId, stackCount)
    -- Track whether the local player currently carries the poison effect.
    if unitTag and IsUnitPlayer(unitTag) then
        boss.bPlayerPoisoned = true
    end
    -- Second poison from the same totem ~26.8 s after first cast.
    -- Guard with BTotemCall so only one delayed bar fires per totem spawn.
    if boss.BTotemCall then return end
    boss.BTotemCall = true
    local capturedSrc = unitName or ""
    -- Store the handle so yandir_cleanup can cancel it if the zone is exited
    -- or the group wipes before the 26.8 s fires.  Trial:cancelPending is a
    -- second net on both paths.
    boss.poisonTotemTimer = boss:after(26800, function()
        onDelayedPoisonFired(boss, capturedSrc)
    end)
end

local function handlePoisonTotemCpFaded(boss, context, alerts, abilityId, unitName,
                                         unitTag, unitId, stackCount)
    if unitTag and IsUnitPlayer(unitTag) then
        boss.bPlayerPoisoned = false
    end
end

local function handleGargoyleTotem(boss, context, alerts, abilityId, sourceUnitName,
                                    unitTag, unitId, sourceUnitId, unitName)
    alerts:showAction(Lang.t("ka_yandir_block_gargoyle"))
    local dur = CastDur.get(TOTEM_GARGYL, FALLBACK_DUR)
    local cid = CA.ranged(abilityId, _STR_BLOCK_GARGOYLE, dur, Colors.SILVER)
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

local function handleHarpyTotemSpawn(boss, context, alerts, abilityId, sourceUnitName,
                                      unitTag, unitId, sourceUnitId, unitName)
    boss.totemTimer:reset()
    local cid = CA.ranged(abilityId, _STR_KILL_HARPY_TOTEM, 120000, Colors.DANGER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleDragonTotemSpawn(boss, context, alerts, abilityId, sourceUnitName,
                                       unitTag, unitId, sourceUnitId, unitName)
    boss.totemTimer:reset()
    local cid = CA.ranged(abilityId, _STR_KILL_DRAGON_TOTEM, 120000, Colors.DANGER)
    if cid and unitId then boss.alertList[unitId] = cid end
end

local function handleGargoyleTotemSpawn(boss, context, alerts, abilityId, sourceUnitName,
                                         unitTag, unitId, sourceUnitId, unitName)
    boss.totemTimer:reset()
    local cid = CA.ranged(abilityId, _STR_KILL_GARGYL_SPWN, 120000, Colors.DANGER)
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
    [TOTEM_HARPY_SPWN]     = { type = AlertTypes.CUSTOM, fn = handleHarpyTotemSpawn   },
    [TOTEM_DRAGON_SPWN]    = { type = AlertTypes.CUSTOM, fn = handleDragonTotemSpawn  },
    [TOTEM_GARGYL_SPWN]    = { type = AlertTypes.CUSTOM, fn = handleGargoyleTotemSpawn},
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
        faded = {
            [TOTEM_POISON_CP] = { type = AlertTypes.CUSTOM, fn = handlePoisonTotemCpFaded },
        },
    },
}

EventDispatcher.build(Yandir)

function Yandir:onPowerUpdate(context, healthPercent)
    -- Both branches are one-shot: they fire once per pull and bake the row-2
    -- text at that moment, so the 200 ms display loop never formats.
    if self.bGRYPHON_SKIP or self.bGRYPHON_SKIP_FAILHP > 0 then return end

    local gryphonLeft = self.gryphonTimer:remaining()
    if healthPercent < 60 and gryphonLeft > 0 then
        -- Capture how many seconds remained on the gryphon timer so the row
        -- can show "Skip! (Xs early)".
        self.bGRYPHON_SKIP      = true
        self.bGRYPHON_SKIP_TIME = gryphonLeft
        self.gryphonRowText     = _STR_GRYPHON_SKIP
            .. Lang.t("ka_yandir_gryphon_early", ZO_FormatCountdownTimer(gryphonLeft))
    elseif healthPercent > 60 and gryphonLeft <= 0 then
        self.bGRYPHON_SKIP_FAILHP = healthPercent
        self.gryphonRowText       = _STR_GRYPHON_FAIL
            .. Fmt.c(Fmt.CRIMSON, Lang.t("ka_yandir_gryphon_fail") .. Fmt.pct(healthPercent))
    end
end

package.loaded["trial.ka.boss.Yandir"] = Yandir
return Yandir
