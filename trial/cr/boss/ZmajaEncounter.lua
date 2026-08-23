local Location = require("core.Location")

-- ── Ability IDs (from HowToCloudrest / CrutchAlerts) ─────────────────────

-- ── Siroria ───────────────────────────────────────────────────────────────
local SIRO_HA          = 104755  -- Heavy Attack → block/dodge
local SIRO_JUMP        = 106601  -- Jump — 23 s CD after landing
local SIRO_BANNER      = 104902  -- Banner skill — 45 s CD
local SIRO_DARK_TALONS = 105765  -- Dark Talons root on player
local SIRO_FLARE       = 103531  -- Roaring Flare → target name alert, 6.6 s window
local SIRO_FLARE_EXEC  = 110431  -- Roaring Flare execute-phase variant

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
local GALE_HOARFROST_C = 105151  -- Hoarfrost cast (AoE ground debuff incoming)
local GALE_HOARFROST_C2= 110466  -- Hoarfrost cast execute variant
local GALE_HOARFROST   = 103695  -- Hoarfrost debuff on player — 6 s drop window
local GALE_HOARFROST_2 = 110516  -- Hoarfrost execute variant
local GALE_HOARFROST_SY= 103697  -- Hoarfrost synergy used
local GALE_HOARFROST_S2= 110525  -- Hoarfrost synergy execute variant
local GALE_HOARFROST_AO= 103765  -- Hoarfrost AoE on ground
local GALE_COMET       = 106374  -- Chilling Comet on player — 4 s window
local GALE_COMET_2     = 106367  -- Chilling Comet variant

-- ── Environment / mini shared ─────────────────────────────────────────────
local RAZOR_THORNS     = 106656  -- Creeper root on player

-- ── Portal mechanics ──────────────────────────────────────────────────────
local PORTAL_OPEN      = 103946  -- Portal spawns / opens (75 s window)
local PORTAL_CLOSE_1   = 104057  -- Remove Shadow Realm (portal done, normal)
local PORTAL_CLOSE_2   = 104792  -- Portal close (PC win)
local PORTAL_RESET     = 105890  -- Z'Maja re-engage — resets portal group to 1
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

-- ── Malevolent Cores (balls in portal) ───────────────────────────────────
local CORE_EXPOSED     = 103980  -- ball appears in portal
local CORE_PICKED_UP   = 103989  -- ball picked up by player
local CORE_MISSED      = 110202  -- ball not caught — hits player

-- ── Shadow Beads ──────────────────────────────────────────────────────────
local BEAD_TICK        = 105339
local BEAD_SPAWN       = 105363
local BEAD_CHARGE      = 105373

-- ── Miscellaneous ─────────────────────────────────────────────────────────
local OLORIME_SPEAR    = 104018  -- Olorime spear granted
local BREAK_AMULET     = 106023  -- Execute phase begins
local MALICIOUS_SPHERE = 105291  -- Sphere spawn

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
local FLARE_WINDOW     = 7     -- Roaring Flare alert window
local COMET_WINDOW     = 4     -- Chilling Comet alert window
local PORTAL_OPEN_DUR  = 75    -- portal stays open ~75 s
local PORTAL_NEXT_CD   = 46    -- seconds until next portal after close

local ZmajaEncounter = {
    id           = 1,
    key          = "zmaja",
    nameAliases  = { "Z'Maja" },
    -- hmHealthThreshold: TBD — verify in-game on vet HM
    hmHealthThreshold = 0,
    -- Location: entire arena — name-based detection is used instead.
    location = Location.new(0, 0, 0, 0, 0, 0),
}

-- ── Mini-boss presence ────────────────────────────────────────────────────
ZmajaEncounter.siroActive = false   -- Siroria alive this run
ZmajaEncounter.releActive = false   -- Relequen alive this run
ZmajaEncounter.galeActive = false   -- Galenwe alive this run

-- ── Portal state ──────────────────────────────────────────────────────────
ZmajaEncounter.portalGroup  = 1     -- current portal group (1 or 2)
ZmajaEncounter.portalActive = false -- true while players are inside portal
ZmajaEncounter.executePhase = false -- true after break amulet

-- ── Spear counter (resets each portal) ───────────────────────────────────
ZmajaEncounter.spearCount = 0

function ZmajaEncounter:reset()
    self.siroActive    = false
    self.releActive    = false
    self.galeActive    = false
    self.portalGroup   = 1
    self.portalActive  = false
    self.executePhase  = false
    self.spearCount    = 0
end

function ZmajaEncounter:onCombatEvent(context, alerts,
        result, abilityId, unitTag, sourceUnitTag, sourceUnitId, unitId,
        sourceUnitName, unitName)
    -- CR-2: Siroria mechanics
    -- CR-2: Relequen mechanics
    -- CR-2: Galenwe / Hoarfrost mechanics
    -- CR-3: Portal open/close
    -- CR-3: Z'Maja abilities (Crushing Darkness, Shadow Splash, Jump, etc.)
    -- CR-3: Malevolent Cores / Olorime Spears
end

function ZmajaEncounter:onEffectChanged(context, alerts,
        changeType, abilityId, unitTag, unitId, unitName)
    -- CR-2: Hoarfrost/Comet debuff alerts, root alerts
    -- CR-3: Portal world-state (EFFECT_GAINED on PORTAL_OPEN, etc.)
    -- CR-3: Mini shackled (ZMAJA_SHACKLE)
    -- CR-3: Break amulet (execute phase entry)
end

function ZmajaEncounter:onUpdate(context, alerts)
    -- CR-2: mini-boss timers (lines 5-7)
    -- CR-3: portal countdown (line 1)
end

function ZmajaEncounter:onPowerUpdate(context, healthPercent, alerts)
    -- CR-3: execute threshold pre-warning (if applicable)
end

return ZmajaEncounter
