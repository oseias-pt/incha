# Incha — Codebase Guide for Claude

## Overview

Incha is an Elder Scrolls Online addon that shows real-time combat alerts during
trial encounters.  It listens to ESO's `EVENT_COMBAT_EVENT` and
`EVENT_EFFECT_CHANGED` streams, filters them to the abilities the active boss
cares about, and emits Combat Alerts (cast bars, dodge/block/debuff
notifications, and action text) through the CombatAlerts external API.

---

## Core Architecture

### Event flow

```
ESO event → EventPipeline → EventDispatcher → boss.events → CA / alerts
```

1. **`core/EventPipeline.lua`** — Registers ESO events through `EVENT_MANAGER`
   with per-ability-id and per-result filters.  Only events whose ability id is
   listed in `boss.events` (or the common module) ever reach Lua.
   `EventPipeline:setActiveBoss(boss)` tears down the previous boss's
   registrations and arms the new ones.

2. **`core/EventDispatcher.lua`** — Receives the filtered events and routes each
   one into the active boss's `events` table.  Three entry points:
   - `onCombatEventFiltered` — ACTION_RESULT_BEGIN and all non-DIED results
   - `onDiedCombatEvent` — ACTION_RESULT_DIED
   - `onEffectChangedFiltered` — EFFECT_RESULT_GAINED / FADED / UPDATED

3. **`boss.events` table** — Every boss declares this at class level:
   ```lua
   Boss.events = {
       beginCast    = { instant={}, started={}, executed={}, interrupted={} },
       effectChanged = { gained={}, faded={}, updated={} },
       combatEvent  = { damage={}, dodged={}, blocked={}, other={} },
   }
   ```
   Each leaf bucket maps `abilityId → entry`.

4. **`core/Trial.lua`** — Wires EventPipeline + EventDispatcher together for one
   trial session.  Created by each trial's `Factory.lua`.

---

## Boss event entry shapes

| `type` field                            | Extra fields                      | Notes                                              |
|-----------------------------------------|-----------------------------------|----------------------------------------------------|
| `AlertTypes.CUSTOM`                     | `fn = namedFunction`              | Named local functions only — **no inline lambdas** |
| `AlertTypes.CAST_BAR`                   | `text`, `dur`, `durMax?`, `color` | —                                                  |
| `AlertTypes.DODGE` / `BLOCK` / `DEBUFF` | `text`, `dur`, `color`            | —                                                  |
| `AlertTypes.INTERRUPT`                  | `text`, `dur`, `color`            | —                                                  |
| `AlertTypes.TIMER_RESET`                | `timer` (string key on boss)      | —                                                  |
| `AlertTypes.IGNORE`                     | —                                 | Silently consume the event                         |

Optional field (all types): `targetOnly = true` — suppress the alert unless the local player is
the target.  Use for single-target abilities (e.g. tank-only melee hits).  Omit for AoE abilities
where everyone must react.

Call `EventDispatcher.build(BossClass)` at the bottom of every boss file.
It validates the `events` table at load time and asserts on structural errors.

---

## Handler signatures

**Combat / beginCast CUSTOM handlers:**
```lua
fn(boss, ctx, alerts, abilityId, sourceUnitName, unitTag, unitId, sourceUnitId, unitName)
```

**EffectChanged CUSTOM handlers:**
```lua
fn(boss, ctx, alerts, abilityId, unitName, unitTag, unitId, stackCount)
```

---

## Trial structure

```
trial/<id>/
  Factory.lua          — creates Trial, registers boss classes
  boss/<Name>.lua      — boss encounter class (extends BossBase)
  *Common.lua          — optional shared add mechanics
```

Each common module exposes:
- `.combatAbilityIds` / `.effectAbilityIds` — sets for EventPipeline registration
- `.handle(alerts, result, abilityId, unitTag, sourceUnitName) → bool`
- `.handleEffect(alerts, changeType, abilityId, unitTag) → bool`  *(optional)*

Common module ability-id sets must be **disjoint** from `boss.events` ability IDs
(verified by `test/checks/filters.lua`).

---

## Tests

Run from the repository root with LuaJIT:

```
luajit test/run_log.lua <encounter.log> [zone_id]
luajit test/checks/filters.lua
luajit test/checks/contracts.lua
luajit test/checks/manifest.lua
luajit test/checks/health_rules.lua
```

`test/run_log.lua` replays a live ESO encounter log through all boss modules and
reports every alert that would have fired.  Use it to validate a migration or
spot dead mechanic coverage.

`test/checks/health_rules.lua` unit-tests `core/HealthRules` in isolation:
priority sort, `_staticText` pre-compilation, boundary inclusivity, `when()`
predicates, `{hp}` substitution, and zero-allocation static-text returns.

---

## Conventions

- **Named local functions only** for event handler values — no inline lambdas
- Factory patterns (`makeXHandler`) must be replaced by individually named
  functions each hardcoding their specific values
- `EventDispatcher.build(BossClass)` at the bottom of every boss file
- `setmetatable(Boss, {__index = BossBase})` for bosses that extend BossBase
- Ability IDs are raw integers declared as `local NAME = <id>` at the top of
  each boss file with a comment naming the mechanic

---

## Boss Detection

### English-only name aliases

`boss.name` and `boss.nameAliases` **must be plain English string literals** —
never `Lang.t(...)` calls.

ESO's combat events (`EVENT_COMBAT_EVENT`, `EVENT_BOSSES_CHANGED`) report unit
names in the client's locale on some events but always in English on others;
`BossRegistry.findByName` is written against English names.  A `Lang.t` call
in an alias would break detection on every non-English client.

```lua
-- CORRECT
BossClass.nameAliases = { "Z'Maja", "Saint Olms the Just" }

-- WRONG — breaks non-English detection
BossClass.nameAliases = { Lang.t("boss_name_zmaja") }
```

`test/checks/contracts.lua` will warn if any alias is not a plain string.

### Detection priority

`BossRegistry` prefers position (`boss.location` AABB) over name when both are
present.  Bosses reachable only by name need a valid English alias; bosses with
an AABB work on all locales without a name entry.  Prefer AABB when in-game
coordinates are available.

---

## Compound Encounters (SubBoss pattern)

Encounters that track multiple independent named units (e.g. OlmsEncounter,
ZmajaEncounter) should use `lib/SubBoss.lua` rather than flat per-sub-boss
field names.

```lua
local SubBoss = require("lib.SubBoss")

Boss.stateSchema = {
    -- one SubBoss per named unit; timers are grouped inside
    siro = function() return SubBoss.new({ jump = Timer.new(23), banner = Timer.new(45) }) end,
    rele = function() return SubBoss.new({ jump = Timer.new(19), bash = Timer.new(20) }) end,
    -- shared top-level fields as usual
    alertList = function() return {} end,
}

-- Access:
--   boss.siro.active           -- boolean
--   boss.siro.jump:remaining() -- timer
--   boss.siro:reset()          -- clears all timers, sets active = false

-- onWipe is simply:
function Boss:onWipe()
    self:cleanupAlertList()
    BossBase.resetSchema(self, Boss)   -- re-creates each SubBoss (clears timers + active)
end
```

See `lib/SubBoss.lua` for the full API.
