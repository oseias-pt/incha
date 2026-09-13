# ESO Combat Log — Event Reference

> Based on live log analysis. Events appear in `timestamp,EVENT_TYPE,...` format.
> Timestamps are in milliseconds from the start of the log session.

---

## Event Categories

| Category            | Events                        |
|---------------------|-------------------------------|
| Static declarations | `ABILITY_INFO`, `EFFECT_INFO` |
| Cast lifecycle      | `BEGIN_CAST`                  |
| Effect lifecycle    | `EFFECT_CHANGED`              |
| Combat outcomes     | `COMBAT_EVENT`                |

---

## Static Declarations

These are **not timed events** — they carry no unit state and describe no action.
They appear **inline** in the log the first time an ability/effect is encountered.

### `ABILITY_INFO`

```
timestamp,ABILITY_INFO,abilityId,"Name","iconPath",isToggle,isPassive
```

| Field     | Example          | Notes                                  |
|-----------|------------------|----------------------------------------|
| abilityId | `133559`         | Numeric ID, consistent across sessions |
| Name      | `"Chaurus Bile"` | Display name                           |
| iconPath  | `"...dds"`       | UI icon path                           |
| isToggle  | `F/T`            | Whether it's a toggled ability         |
| isPassive | `F/T`            | Whether it's a passive                 |

**When it appears:** Once per ability ID per log segment, at the timestamp when that ability is first used.

---

### `EFFECT_INFO`

```
timestamp,EFFECT_INFO,abilityId,effectType,stackType,visibility
```

| Field      | Values                       | Notes                                                |
|------------|------------------------------|------------------------------------------------------|
| effectType | `BUFF`, `DEBUFF`             | Whether it helps or harms the target                 |
| stackType  | `NONE`, `STACK`              | Whether the effect stacks                            |
| visibility | `DEFAULT`, `NEVER`, `ALWAYS` | `NEVER` = hidden from UI; `DEFAULT` = shown normally |

**When it appears:** At the same timestamp as the first `EFFECT_CHANGED,GAINED` for that effect.

---

## Cast Lifecycle — `BEGIN_CAST`

```
timestamp,BEGIN_CAST,castTime,didFire,sourceUnitId,abilityId,targetUnitId,
    sourceHp/sourceMaxHp,...,sourceX,sourceY,sourceZ,
    targetUnitId,targetHp/targetMaxHp,...,targetX,targetY,targetZ
```

The `didFire` boolean is the key field:

| didFire | Meaning                                         |
|---------|-------------------------------------------------|
| `F`     | Cast **started** — the button was pressed       |
| `T`     | Cast **completed** — the ability actually fired |

### Sequence: Instant cast (castTime = 0)

Only one `BEGIN_CAST` event since start and fire are simultaneous.

```
timestamp,BEGIN_CAST,0,F,...   ← fires immediately
timestamp,EFFECT_INFO,...      ← (if first time seen)
timestamp,EFFECT_CHANGED,GAINED,...
```

### Sequence: Cast with cast time

```
timestamp_1,BEGIN_CAST,1500,F,...   ← player presses button
timestamp_2,BEGIN_CAST,1500,T,...   ← ability fires ~1500ms later
timestamp_2,EFFECT_INFO,...         ← (if first time seen)
timestamp_2,EFFECT_CHANGED,GAINED,...
```

`timestamp_2 - timestamp_1 ≈ castTime`

### Sequence: Cast interrupted

No `T` event arrives within the castTime window.

```
timestamp_1,BEGIN_CAST,1500,F,...   ← cast started
                                    ← no T — interrupted or cancelled
timestamp_2,BEGIN_CAST,1500,F,...   ← new cast attempt begins
```

> **How to detect:** `BEGIN_CAST,F` at time X with castTime N,
> and no `BEGIN_CAST,T` for the same `abilityId + sourceUnitId` before X+N.
> ESO does **not** emit an explicit interrupt event.

---

## Effect Lifecycle — `EFFECT_CHANGED`

```
timestamp,EFFECT_CHANGED,changeType,stackCount,sourceUnitId,abilityId,targetUnitId,
    sourceHp/sourceMaxHp,...,sourceX,sourceY,sourceZ,
    targetUnitId,targetHp/targetMaxHp,...,targetX,targetY,targetZ
```

| changeType | Meaning                                                    |
|------------|------------------------------------------------------------|
| `GAINED`   | Effect was applied to the target                           |
| `FADED`    | Effect was removed from the target                         |
| `UPDATED`  | Effect was refreshed (duration reset, stack count changed) |

Always come in pairs per application: every `GAINED` eventually has a matching `FADED`.

The **third numeric field** after `GAINED`/`FADED` is the target's **local unit ID** — used to track per-target effect instances in AoE abilities.

### Sequence: Normal effect expiry

```
timestamp_1,EFFECT_CHANGED,GAINED,1,sourceId,abilityId,targetId,...
timestamp_2,EFFECT_CHANGED,FADED,1,sourceId,abilityId,targetId,...   ← natural expiry
```

### Sequence: AoE hitting multiple targets

Multiple `GAINED` at the same timestamp, one per target unit ID.

```
timestamp,EFFECT_CHANGED,GAINED,1,...,targetId_1,...
timestamp,EFFECT_CHANGED,GAINED,1,...,targetId_56,...
timestamp,EFFECT_CHANGED,GAINED,1,...,targetId_314,...
```

---

## Combat Outcomes — `COMBAT_EVENT`

```
timestamp,COMBAT_EVENT,actionResult,damageType,value,overflow,unk,
    sourceUnitId,abilityId,targetUnitId,
    sourceHp/sourceMaxHp,...,sourceX,sourceY,sourceZ,
    targetUnitId,targetHp/targetMaxHp,...,targetX,targetY,targetZ
```

### Action Results

| actionResult          | Meaning                                           |
|-----------------------|---------------------------------------------------|
| `DAMAGE`              | Damage was dealt to the target                    |
| `CRITICAL_DAMAGE`     | Critical hit damage dealt                         |
| `HEAL`                | Healing applied to a unit                         |
| `CRITICAL_HEAL`       | Critical heal applied                             |
| `DAMAGE_SHIELDED`     | Damage was absorbed by a damage shield            |
| `KILLING_BLOW`        | Target was killed                                 |
| `DODGED`              | A damage tick was dodged — no damage applied      |
| `BLOCKED_DAMAGE`      | A damage tick was blocked — reduced/negated       |
| `IMMUNE`              | Target is immune to this effect                   |
| `ABILITY_ON_COOLDOWN` | Unit tried to cast but the ability is on cooldown |

### Damage Types

| damageType | Notes                              |
|------------|------------------------------------|
| `GENERIC`  | Untyped / fallback                 |
| `PHYSICAL` | Physical / bleed                   |
| `FIRE`     | Flame damage                       |
| `SHOCK`    | Lightning damage                   |
| `COLD`     | Frost damage                       |
| `MAGIC`    | Magic / oblivion variants          |
| `POISON`   | Poison damage                      |
| `DISEASE`  | Disease damage                     |
| `OBLIVION` | Oblivion damage (bypasses shields) |

---

## `COMBAT_EVENT` Sequences

### Sequence: Direct damage hit

```
timestamp,BEGIN_CAST,0,F,...                         ← instant ability
timestamp,COMBAT_EVENT,DAMAGE,POISON,1240,0,0,...    ← damage dealt
```

### Sequence: Critical hit

```
timestamp,COMBAT_EVENT,CRITICAL_DAMAGE,FIRE,3820,0,0,...
```

### Sequence: Damage absorbed by shield

```
timestamp,COMBAT_EVENT,DAMAGE_SHIELDED,MAGIC,900,0,0,...
```

### Sequence: Target dodged

The effect **still applies** (`GAINED`), then the damage tick is dodged and the effect is immediately stripped (`FADED`).

```
timestamp_1,EFFECT_CHANGED,GAINED,1,...,targetId,...    ← debuff lands
timestamp_2,COMBAT_EVENT,DODGED,POISON,0,0,0,...        ← tick dodged
timestamp_2,EFFECT_CHANGED,FADED,1,...,targetId,...     ← effect stripped
```

> **Important:** `GAINED` fires before `DODGED`. The effect *did* land — the dodge
> resolved a damage tick, which then removed the effect. The target was never "safe"
> from the initial application.

### Sequence: Target blocked damage

Same pattern as dodge — effect lands first, block resolves a tick, effect is stripped.

```
timestamp_1,EFFECT_CHANGED,GAINED,1,...,targetId,...
timestamp_2,COMBAT_EVENT,BLOCKED_DAMAGE,POISON,0,0,0,...
timestamp_2,EFFECT_CHANGED,FADED,1,...,targetId,...
```

### Sequence: Target immune

```
timestamp,COMBAT_EVENT,IMMUNE,POISON,0,0,0,...    ← no GAINED, no FADED
```

### Sequence: Ability on cooldown (failed cast attempt)

Not part of a cast — a completely separate event.
The ability was not used; nothing happened.

```
timestamp,COMBAT_EVENT,ABILITY_ON_COOLDOWN,GENERIC,0,0,0,unitId,abilityId,...
```

### Sequence: Killing blow

```
timestamp,COMBAT_EVENT,DAMAGE,PHYSICAL,450,0,0,...    ← damage
timestamp,COMBAT_EVENT,KILLING_BLOW,PHYSICAL,0,0,0,... ← target dies
timestamp,UNIT_REMOVED,...                              ← unit leaves tracking
```

---

## Combining All: Full Ability Lifecycle Examples

### Example A — Instant AoE poison (Chaurus Bile)

```
t,ABILITY_INFO,133559,"Chaurus Bile",...              ← declared once
t,BEGIN_CAST,0,F,...                                  ← instant: only F
t,EFFECT_INFO,133559,DEBUFF,NONE,DEFAULT              ← declared once
t,EFFECT_CHANGED,GAINED,1,...,target_1,...            ← 3 targets hit
t,EFFECT_CHANGED,GAINED,1,...,target_56,...
t,EFFECT_CHANGED,GAINED,1,...,target_314,...
t+67,COMBAT_EVENT,DODGED,POISON,0,0,0,...,target_56  ← target 56 dodges
t+67,EFFECT_CHANGED,FADED,1,...,target_56,...         ← stripped
t+116,COMBAT_EVENT,DODGED,POISON,0,0,0,...,target_1  ← target 1 dodges
t+116,EFFECT_CHANGED,FADED,1,...,target_1,...
t+917,COMBAT_EVENT,BLOCKED_DAMAGE,POISON,...,target_314 ← target 314 blocks
t+917,EFFECT_CHANGED,FADED,1,...,target_314,...
```

### Example B — Cast-time buff (Abyssal Healing)

```
t,ABILITY_INFO,133242,"Abyssal Healing",...
t,BEGIN_CAST,300,F,...          ← cast starts (300ms cast time)
t+383,BEGIN_CAST,2000,T,...     ← cast fires
t+383,EFFECT_INFO,133242,BUFF,NONE,DEFAULT
t+383,EFFECT_CHANGED,GAINED,1,...
t+2383,EFFECT_CHANGED,FADED,1,...   ← buff expires naturally (~2s duration)
```

### Example C — Cast interrupted

```
t,BEGIN_CAST,5000,F,...         ← cast starts (5s cast time)
                                ← interrupted — no T within 5000ms
t+500,BEGIN_CAST,5000,F,...     ← boss tries again
t+5500,BEGIN_CAST,5000,T,...    ← this one completes
```

### Example D — Failed attempt (ability on cooldown)

```
t,BEGIN_CAST,2000,F,...         ← original successful cast
t+383,BEGIN_CAST,2000,T,...     ← fired
...
t+41307,COMBAT_EVENT,ABILITY_ON_COOLDOWN,GENERIC,...  ← another unit tried, cooldown not ready
```

---

## Quick Reference: F vs T vs ABILITY_ON_COOLDOWN

| Situation                             | Events                                    |
|---------------------------------------|-------------------------------------------|
| Cast started                          | `BEGIN_CAST,F`                            |
| Cast completed and fired              | `BEGIN_CAST,T`                            |
| Cast interrupted / cancelled          | `BEGIN_CAST,F` → *(no T within castTime)* |
| Tried to cast but already on cooldown | `COMBAT_EVENT,ABILITY_ON_COOLDOWN`        |

---

## Quick Reference: Effect Resolution

| What happened                            | Events                                |
|------------------------------------------|---------------------------------------|
| Effect applied, runs full duration       | `GAINED` → `FADED`                    |
| Effect applied, target dodges a tick     | `GAINED` → `DODGED` → `FADED`         |
| Effect applied, target blocks a tick     | `GAINED` → `BLOCKED_DAMAGE` → `FADED` |
| Target immune, effect never applied      | `IMMUNE` *(no GAINED/FADED)*          |
| Effect applied to multiple targets (AoE) | multiple `GAINED` at same timestamp   |

---

## Event → Reaction Rules (Parser / Addon Logic)

Rules for what a parser or addon should do when it receives each event.

### Static declarations → populate lookup tables, no UI action

```
ABILITY_INFO  → store { abilityId → name, icon, isToggle, isPassive }
EFFECT_INFO   → store { abilityId → effectType (BUFF/DEBUFF), stackType, visibility }
```

No alert. No cast bar update. These are data, not events.

---

### Cast lifecycle → depends on castTime

```
BEGIN_CAST, castTime=0, F
    → alert immediately
      (instant cast: start and fire are the same moment)

BEGIN_CAST, castTime=N, F
    → update cast bar / incoming cast table
    → start countdown timer for N ms
    → if ability is interruptible (see caveat below):
          alert now — this is the window to interrupt
    → if not interruptible:
          schedule alert for when timer expires (cast fires)

BEGIN_CAST, castTime=N, T
    → cast fired — effect is now happening
    → if you alerted on F: confirm / escalate alert
    → if you did not alert on F: alert now
    → clear cast bar and cancel timer

BEGIN_CAST, F  (no T within castTime window)
    → cast was interrupted or cancelled
    → clear cast bar, cancel timer, cancel any pending alert
```

> **Caveat — interruptibility is not in the log.**
> `ABILITY_INFO` does not carry an interruptible flag.
> You must maintain a separate lookup table keyed by `abilityId`
> populated from community data or manual testing.
> Until that data exists for an ability, treat it as non-interruptible
> to avoid false alerts.

---

### Effect lifecycle → per-target tracking

```
EFFECT_CHANGED, GAINED
    → mark targetUnitId as affected by abilityId
    → start duration timer for that target
    → if effectType = DEBUFF and visibility ≠ NEVER:
          alert (dangerous debuff landed on a player)

EFFECT_CHANGED, FADED
    → clear targetUnitId's mark for abilityId
    → cancel duration timer
    → check cause:
          if preceded by DODGED/BLOCKED at same timestamp → target evaded, note in stats
          otherwise → natural expiry or cleanse

EFFECT_CHANGED, UPDATED
    → refresh duration timer for targetUnitId
    → update stack count if stackType = STACK
```

---

### Combat outcomes → mostly stat tracking, some conditional alerts

```
COMBAT_EVENT, DAMAGE             → stat tracking (DPS meter)
COMBAT_EVENT, CRITICAL_DAMAGE    → stat tracking
COMBAT_EVENT, HEAL               → stat tracking (HPS meter)
COMBAT_EVENT, CRITICAL_HEAL      → stat tracking
COMBAT_EVENT, DAMAGE_SHIELDED    → stat tracking (shield absorption)

COMBAT_EVENT, KILLING_BLOW       → unit died
                                    remove unitId from all active effect tracking

COMBAT_EVENT, DODGED             → stat tracking (who dodged)
                                    paired FADED handles the effect side

COMBAT_EVENT, BLOCKED_DAMAGE     → stat tracking (who blocked)
                                    paired FADED handles the effect side

COMBAT_EVENT, IMMUNE             → target immune, no GAINED is coming
                                    no effect tracking needed

COMBAT_EVENT, ABILITY_ON_COOLDOWN → ignore
                                     failed attempt, nothing happened
```

---

## Decision Tree Summary

```
Receive event
│
├── ABILITY_INFO / EFFECT_INFO
│       └── update lookup table, stop
│
├── BEGIN_CAST
│   ├── castTime = 0, F  →  alert immediately
│   ├── castTime = N, F  →  cast bar + timer
│   │                        └── interruptible? alert now : alert at T
│   ├── castTime = N, T  →  cast fired → alert / escalate, clear cast bar
│   └── F with no T      →  interrupted → clear cast bar, cancel alert
│
├── EFFECT_CHANGED
│   ├── GAINED   →  mark target, start timer, alert if dangerous DEBUFF
│   ├── FADED    →  clear target mark, check if caused by DODGED/BLOCKED
│   └── UPDATED  →  refresh timer / stack count
│
└── COMBAT_EVENT
    ├── DAMAGE / CRITICAL_DAMAGE / HEAL / CRITICAL_HEAL / DAMAGE_SHIELDED
    │       └── stat tracking only
    ├── KILLING_BLOW    →  remove unit from effect tracking
    ├── DODGED          →  stat tracking (FADED will follow)
    ├── BLOCKED_DAMAGE  →  stat tracking (FADED will follow)
    ├── IMMUNE          →  no effect tracking needed
    └── ABILITY_ON_COOLDOWN  →  ignore
```
