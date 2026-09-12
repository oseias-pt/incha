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

| `type` field        | Extra fields              | Notes |
|---------------------|---------------------------|-------|
| `AlertTypes.CUSTOM` | `fn = namedFunction`      | Named local functions only — **no inline lambdas** |
| `AlertTypes.CAST_BAR` | `text`, `dur`, `durMax?`, `color` | — |
| `AlertTypes.DODGE` / `BLOCK` / `DEBUFF` | `text`, `dur`, `color` | — |
| `AlertTypes.INTERRUPT` | `text`, `dur`, `color` | — |
| `AlertTypes.TIMER_RESET` | `timer` (string key on boss) | — |
| `AlertTypes.IGNORE` | — | Silently consume the event |

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
```

`test/run_log.lua` replays a live ESO encounter log through all boss modules and
reports every alert that would have fired.  Use it to validate a migration or
spot dead mechanic coverage.

---

## Conventions

- **Named local functions only** for event handler values — no inline lambdas
- Factory patterns (`makeXHandler`) must be replaced by individually named
  functions each hardcoding their specific values
- `EventDispatcher.build(BossClass)` at the bottom of every boss file
- `setmetatable(Boss, {__index = BossBase})` for bosses that extend BossBase
- Ability IDs are raw integers declared as `local NAME = <id>` at the top of
  each boss file with a comment naming the mechanic
