# Kyne's Aegis — Alert Catalogue

> **Purpose:** Independent validation reference. A tester can follow this document to confirm every alert fires correctly without reading source code. Each entry lists the trigger condition, ability ID, expected display, duration, colour, and sound.

**Bosses (in encounter order):**
1. [Yandir the Butcher](#1-yandir-the-butcher)
2. [Vrol Ka'lar](#2-vrol-kalar)
3. [Falgravn](#3-falgravn)

---

## Common conventions

| Term | Meaning |
|------|---------|
| **action** | One-line text in the action panel (bottom of Incha UI) |
| **cast bar** | `CA.bar()` — scrolling cast-bar alert with ability icon |
| **ranged bar** | `CA.ranged()` — incoming ranged-attack warning bar |
| **flash alert** | `CA.alert()` — full-screen flash message |
| **OSI icon** | Above-head mechanic icon (OdySupportIcons) |
| **floor icon** | World-space position icon (PositionIcons) |
| **tracker row** | Persistent countdown row in the tracker panel |
| ⚠️ HM only | Fires only in Veteran Hard Mode |
| ⚠️ player only | Fires only when the local player is the event target |

Colour codes reference: `FLYZONE` = green, `MAGENTA` = magenta/pink, `BLUE` = blue, `POISON` = toxic green, `SILVER` = silver/white, `VOID` = dark purple, `PINK` = pink, `ICE` = light blue, `YELLOW` = yellow, `AMBER` = amber, `GREEN` = green, `RED` = red, `CRIMSON` = deep red, `PURPLE` = purple.

---

## 1. Yandir the Butcher

**Detection:** AABB `x 63200–68900 · y 24300–26300 · z 90500–99600`  
**HM threshold:** 72,769,370 HP ⚠️ unverified — see issue [#165]

### 1.1 Tracker rows

| Row | Label | Countdown | Reset trigger |
|-----|-------|-----------|---------------|
| 1 | `Totem` | 20 s → `Totem Ready` | Any totem spawn (ability 133510, 133045, 133513, or 133515) |
| 2 | `Gryphon` | 60 s → `Gryphon Ready` | Combat start only |

**Row 2 special states:**
- Below 60% HP before timer expires → `Gryphon Skip! (Xs early)` (static, green)
- Timer expires while boss still above 60% → `Gryphon Fail @ X%` (static, red)

### 1.2 Combat alerts

#### Poison Totem — 133515 `TOTEM_POISON`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Dodge! (Poison Totem)` |
| Alert type | Ranged bar |
| Duration | 4300 ms |
| Colour | POISON |
| Sound | (none) |
| Also resets | Totem timer |

#### Poison Totem (second poison) — 133559 `TOTEM_POISON_CP`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_EFFECT_GAINED` |
| Delay | 26,800 ms after effect gained (one bar per totem spawn) |
| Alert type | Ranged bar |
| Duration | 4300 ms |
| Colour | POISON |
| Sound | (none) |
| Note | Cancelled on wipe/zone exit; fires only if totem still alive and player in combat |

#### Gargoyle Totem cast — 133546 `TOTEM_GARGYL`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Block! (Gargoyle Totem)` |
| Alert type | Ranged bar (label `Block!!`) |
| Duration | ~5000 ms (fallback; replace when `GetAbilityCastInfo` returns stable value) |
| Colour | SILVER |
| Sound | (none) |

#### Yandir Healing — 133242 `YANDIR_HEALING`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Casts Healing!` |
| Alert type | Flash alert |
| Duration | 2000 ms |
| Colour | Red `0x991111FF` |
| Sound | (none) |

#### Yandir Jump — 132571 `YANDIR_JUMP`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `(Jump) Block!!` |
| Alert type | Ranged bar (label `(Jump) Block!!`) |
| Duration | 3000 ms |
| Colour | SILVER |
| Sound | (none) |

#### Sea Adder Bile Spray — 136591 `SEA_ADDER_BILE_SPRAY` ⚠️ player only
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN`, only if event target is local player |
| Action text | `Dodge! (Sea Adder)` |
| Alert type | Ranged bar |
| Duration | 1933 ms |
| Colour | SILVER |
| Sound | (none) |

### 1.3 Wipe / leave cleanup

| Item | Action |
|------|--------|
| All `alertList` cast bars | Stopped via `cleanupAlertList()` |
| Delayed second-poison bar timer | Cancelled |
| `bGRYPHON_SKIP`, `bGRYPHON_SKIP_TIME`, `bGRYPHON_SKIP_FAILHP` | Reset to defaults |
| `poisonTotemId` | Reset to `-1` |
| `BTotemCall` | Reset to `false` |
| Tracker rows | Cleared (timers expired state resets on next combat start) |

---

## 2. Vrol Ka'lar

**Detection:** AABB `x 110200–118500 · y 24500–29000 · z 65000–78800`  
**HM threshold:** 72,769,370 HP ⚠️ unverified — see issue [#165]

### 2.1 Tracker rows

| Row | Label | Countdown | Notes |
|-----|-------|-----------|-------|
| 1 | `Next Fog` / `Fog Clears` | 30 s between fogs / fog active duration | While fog is active label becomes `Fog Clears`; turns pink when ≤ 5 s remain |
| 2 | `Conduit` | 40 s | Resets on Harpoon cast |
| 3 | `Portal` | 15 s (first pull), 45 s (recurring) | Hidden once boss drops below 50% HP |

**Fog extension:** every 3 `VROL_FOG_INCREASE` (133756) pulses extend the active fog by 9 s (no direct player alert, only tracker row update).

### 2.2 Combat alerts

#### Portal cast — 133994 `VROL_PORTAL_CAST`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `KILL Conjurer!` |
| Alert type | Ranged bar (icon ability 134016) |
| Duration | 3000 ms |
| Colour | VOID |
| Sound | (none) |
| Also resets | Portal timer (45 s) |

#### Fog cast — 133808 `VROL_FOG_CAST`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Dodge/Move! (Fog)` |
| Alert type | Ranged bar |
| Duration | 1000 ms |
| Colour | BLUE |
| Sound | (none) |
| Side effects | Starts fog display (30 s duration on tracker row 1); resets fog timer |

#### Harpoon — 133913 `VROL_HARPOON`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Kill Harpoon! (~16 s)` |
| Alert type | Cast bar (label `Harpoon!`) |
| Duration | 16,000 ms |
| Colour | FLYZONE |
| Sound | (none) |
| Also resets | Conduit timer (40 s) |

#### Apothecary interrupt — 140255 `VROL_APOTHECARY`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Interrupt Apothecary!` |
| Alert type | Flash alert |
| Duration | 2000 ms |
| Colour | Blue `0x0099FFFF` |
| Sound | `CHAMPION_POINTS_COMMITTED` |

### 2.3 Effect alerts

#### Portal kill-time debuff — 134016 `VROL_PORTAL_KTIME` ⚠️ player only
| Event | Action |
|-------|--------|
| `EFFECT_RESULT_GAINED` | Action `KILL Conjurer! (20 s)` + cast bar (20,000 ms, FLYZONE) |
| `EFFECT_RESULT_FADED` — Conjurer killed in time | Action `Portal OK!` + flash alert (green `0x119911FF`, `DUEL_WON`, 2000 ms) |
| `EFFECT_RESULT_FADED` — time expired | Action `Portal Failed!` + flash alert (red `0x991111FF`, `DUEL_FORFEIT`, 2000 ms) |

Only fires for the **local player's** portal debuff (`GetLocalPlayerGroupUnitTag()`).

### 2.4 Floor position icons (optional setting)

| Icon | Coordinates | Texture | Visible |
|------|-------------|---------|---------|
| Portal spawn point | `(114624, 25764, 71349)` | `/esoui/art/icons/malatar_agonizingbolts.dds` | Always (from `onEnter`) |

Requires `Settings.trial("ka").portalIconVrol = true`. Created once on zone entry; survives wipes (intentional — icon marks a fixed location).

### 2.5 Wipe / leave cleanup

| Item | Action |
|------|--------|
| All `alertList` cast bars | Stopped via `cleanupAlertList()` |
| Portal kill-time bar (`portalKillBarId`) | Stopped |
| `bPORTAL_END` | Reset to `false` |
| `fogEndTime`, `fogHitCount`, `portalKillExpires` | Reset to 0 |
| Portal floor icon | **Leave only** — discarded on zone exit; survives wipes |

---

## 3. Falgravn

**Detection:** AABB `x 73700–84500 · y 6000–22500 · z 50200–61900`  
**HM threshold:** 248,386,060 HP  
⚠️ **Floor icon coordinate space unverified** — node tables (CONN_NODES, BLOOD_NODES, TORTURER_NODES) appear to use a different origin than the arena AABB. Run `/incha debug` in-arena and compare the printed `falgravn coords` line before trusting floor marker positions. See issue [#165].

### 3.1 Stages

| Stage | Entry condition | Active tracker rows |
|-------|----------------|---------------------|
| **Stage 1** | Combat start | Row 1: Instability |
| **Stage 2** | Falgravn lands — `FALGRAVN_UNW_POWER` (139378) fades | Row 1: Instability · Row 2: Blood Ball |
| **Stage 3** | Floor shatters — `FALGRAVN_SHATTER_MID` (136727) begins | Row 1: Open Gates · Row 2: Torturer TP |

### 3.2 Tracker rows

#### Stage 1 & 2 — Row 1: Instability
| State | Display |
|-------|---------|
| Timer running | `Instability  12` (countdown in seconds) |
| Timer expired | `Instability UP` |
| Reset event | `FALGRAVN_INSTABILITY` effect gained-duration; initial 10 s, then 22 s |

#### Stage 2 — Row 2: Blood Ball
| State | Display |
|-------|---------|
| Timer running | `Blood Ball  34` |
| Timer expired | `Blood Ball Soon` |
| On Blood Ball active (GAINED_DURATION) | Timer resets to 30 s |
| On Blood Ball faded | Timer resets to 45 s |
| Initial delay | 20 s after `FALGRAVN_UNW_POWER` fades (Falgravn lands) |

#### Stage 3 — Row 1: Open Gates
| State | Display |
|-------|---------|
| Timer running | `Open Gates  28` |
| Timer expired | `Open Gates Soon` |
| Reset event | Each `FALGRAVN_OPEN_DOOR` cast; initial 40 s, then 45 s |

#### Stage 3 — Row 2: Torturer TP
| State | Display |
|-------|---------|
| Timer running | `Torturer TP  12` |
| Timer expired | Row cleared |
| Reset event | Each `FALGRAVN_OPEN_DOOR` cast (resets to 25 s) |

### 3.3 Health rules (shown when `showPercent` setting enabled)

| HP range | Display |
|----------|---------|
| 90–93% | `Connect Soon! (90% / {hp}%)` |
| 80–83% | `Connect Soon! (80% / {hp}%)` |
| 70–73% | `Dont Ult (Floor Shatter)! (70% / {hp}%)` |
| 35–38% | `Dont Ult! (35% / {hp}%)` — Stage 1/2 only |

### 3.4 Combat alerts

#### Infuser trash interrupt — 137289 `INFUSER_CASTS`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Interrupt Infuser!` |
| Alert type | Ranged bar |
| Duration | 1000 ms |
| Colour | BLUE |
| Sound | (none) |

#### Infuser buff passed — 139961 `INFUSER_BUFF`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_EFFECT_GAINED` |
| Action text | `Infuser Buff passed!` |
| Alert type | Flash alert |
| Duration | 3000 ms |
| Colour | Orange `0xFF8800FF` |
| Sound | `DUEL_START` |

#### HM confirmation — 137215 `FALGRAVN_HM` ⚠️ HM only
| Event | Action |
|-------|--------|
| `EFFECT_RESULT_GAINED` | Panel header → `{boss name} [HM: ON]` |
| `EFFECT_RESULT_FADED` | Panel header → `{boss name}` (reverts after 2 s delay if no longer in combat) |

#### Njordal: Ground Move AoE — 136965 `FALGRAVN_M_MOVE`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` (deduplicated — one alert per move cycle) |
| Action text | `Move!` |
| Alert type | Cast bar |
| Duration | 12,000 ms |
| Colour | FLYZONE |
| Early-warn | 12,000 ms (immediately on begin) |
| Sound | (none) |
| Dedup reset | `EFFECT_RESULT_FADED` on same ability |

#### Njordal: Block Charge (Bloody Frenzy) — 136953 `FALGRAVN_M_BLOCK` / 137499 `FALGRAVN_M_BLOCK_HEAVY`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` on 136953 (deduped); cast bar uses icon 137499 (`Bloody Frenzy`) |
| Action text | `Block Cast!` |
| Alert type | Cast bar |
| Duration | 6500 ms |
| Colour | FLYZONE |
| Sound | (none) |
| Dedup reset | `EFFECT_RESULT_FADED` on same ability |

#### Njordal: Blood Cleave — 136976 `FALGRAVN_M_CLEAVE`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `DODGE!` |
| Alert type | Cast bar |
| Duration | ~2000 ms (fallback; `CastDur.get` used) |
| Colour | MAGENTA |
| Early-warn | 700 ms before end: text `DODGE!`, sound `CHAMPION_POINTS_COMMITTED` |

#### Blood Fountain — 140294 `FALGRAVN_BLOOD_FOUNT`
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Block Blood Fountain!` |
| Alert type | Ranged bar |
| Duration | 3033 ms |
| Colour | MAGENTA |
| Sound | (none) |

#### Open the Gates — 136693 `FALGRAVN_OPEN_DOOR` (Stage 3)
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Open the Gates!` |
| Alert type | Flash alert |
| Duration | 2000 ms |
| Colour | Red `0x991111FF` |
| Sound | `CHAMPION_POINTS_COMMITTED` |
| Delayed alert | 25,000 ms later → ranged bar (7500 ms, BLUE) — heavy-attack warning for tanks |
| Also resets | Open Gates timer (45 s), Torturer TP timer (25 s) |

#### Kill Torturer (feed start) — 137314 `FALGRAVN_TUT_FEED` (Stage 3)
| Field | Value |
|-------|-------|
| Trigger | `EFFECT_RESULT_GAINED` (deduped — one bar per feed cycle) |
| Action text | `KILL Torturer!` |
| Alert type | Cast bar |
| Duration | 10,000 ms |
| Colour | FLYZONE |
| Sound | (none) |
| Side effect | Active torturer's floor icon turns yellow |
| Dedup reset | `EFFECT_RESULT_FADED` on same ability |

#### Torturer teleports down — 139633 `FALGRAVN_TORTURER_ESC` (Stage 3)
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN` |
| Action text | `Torturer Comes Down!` |
| Alert type | Flash alert |
| Duration | 3000 ms |
| Colour | Orange `0xFF8800FF` |
| Sound | `CHAMPION_POINTS_COMMITTED` |

#### Torturer light attack — 136958 `FALGRAVN_TORTURER_LA` ⚠️ player only, non-tank
| Field | Value |
|-------|-------|
| Trigger | `ACTION_RESULT_BEGIN`, only if target is local player **and** local player is not Tank role |
| Action text | `DODGE! (Torturer LA)` |
| Alert type | Flash alert (label `Torturer LA's`, body `DODGE!`) |
| Duration | 1000 ms |
| Colour | Red `0xFF0000FF` |
| Sound | `DUEL_START` |

### 3.5 Effect alerts

#### Prison debuff — 132473 `FALGRAVN_PRISON`
| Event | Action |
|-------|--------|
| `EFFECT_RESULT_GAINED` | Action `KILL PRISON!` + cast bar (8000 ms, FLYZONE, keyed per player — multiple simultaneous prisons supported) + OSI prison icon (PURPLE) above player's head |
| `EFFECT_RESULT_FADED` | Stop that player's cast bar; remove OSI icon |

#### Instability — 140944 `FALGRAVN_INSTABILITY` / 140941 `FALGRAVN_INSTABILITY2` ⚠️ player only
| Event | Action |
|-------|--------|
| `EFFECT_RESULT_GAINED` | Start 40-frame animated OSI icon above player (50 ms/frame, 2 s loop, FLYZONE colour) |
| `EFFECT_RESULT_FADED` | Stop animation; remove OSI icon |

> Note: `FALGRAVN_INSTABILITY` (140944) also routes through `combatRoutes` on `EFFECT_GAINED_DURATION` to reset the tracker countdown — that path does not trigger the OSI icon (effect route handles icons; combat route handles timer).

#### Prisoner feed stacks — 137315 `FALGRAVN_PRISONER_F`
| Condition | Action |
|-----------|--------|
| Any stack gained | Increment internal stack counter for that prisoner |
| Stack count reaches **9** | Action + flash alert: `KILL Torturer! ({name} fed 9× — dying!)` (red `0xFF2200FF`, `DUEL_START`, 4000 ms) |
| Stack count reaches **11** | Prisoner dead — decrement torturer count; torturer floor icon turns RED |

> The 9-stack threshold is provisional. See TODO in source (`#126`).

#### Execration synergy — 129936 `FALGRAVN_BLOPSYNERGIE` ⚠️ player only
| Event | Action |
|-------|--------|
| `EFFECT_RESULT_GAINED` | OSI synergy icon (CRIMSON) above player's head |
| `EFFECT_RESULT_FADED` | Remove OSI icon |

### 3.6 Floor position icons (optional setting `posIconsFalgravn`)

All icons are created 3.1 s after zone entry and hidden by default; they are shown/hidden dynamically during the fight.

#### Connection nodes (Lightning mechanic — 90% / 80%)
- **Count:** 20 nodes across 4 lines (LN, LS, RN, RS — left-north, left-south, right-north, right-south)
- **Per-line nodes:** 5, numbered wall=1 → boss=5
- **Texture:** Numbered red squares (`squaretwo_red_one.dds` … `squaretwo_red_five.dds`)
- **Colour:** PINK
- **Shown:** On `FALGRAVN_LIGHTNING` (133428) `ACTION_RESULT_BEGIN`
- **Hidden:** On `FALGRAVN_PULSE` (134854) `EFFECT_RESULT_FADED`
- **⚠️ UNVERIFIED coordinates** — see note at top of section

#### Blood-ball nodes (Stage 2)
- **Count:** 4 nodes at lower floor level
- **Texture:** Numbered orange squares (`squaretwo_orange_one.dds` … `squaretwo_orange_four.dds`)
- **Colour:** AMBER
- **Shown:** On `FALGRAVN_BLOOTBALL` (136548) `EFFECT_GAINED_DURATION`
- **Hidden:** On Stage 3 start (`FALGRAVN_SHATTER_MID`)
- **⚠️ UNVERIFIED coordinates**

#### Torturer nodes (Stage 2 + 3)
- **Count:** 8 (one per torturer: Brekalda, Thjorlak, Aevar, Triveta, Skormgondar, Irthrig, Ama, Sislea)
- **Colour states:**

| State | Texture | Colour |
|-------|---------|--------|
| Idle | `square_blue.dds` | ICE |
| Feeding (active) | `square_yellow.dds` | YELLOW |
| Prisoner saved | `square_green.dds` | GREEN |
| Prisoner dead (11 stacks) | `square_red.dds` | RED |

- **Shown:** On Stage 2 start (Falgravn lands or Blood Ball GAINED_DURATION)
- **Hidden on wipe:** icons hidden but handles kept; reset to blue state
- **Discarded:** Zone exit only

### 3.7 Wipe / leave cleanup

| Item | Wipe | Leave |
|------|------|-------|
| `alertList` cast bars | Stopped | Stopped |
| Per-player prison bars (`prisonBars`) | Stopped; table cleared | Stopped; table cleared |
| Delayed Open Gates heavy-attack timer | Cancelled | — |
| OSI prison icons | Removed | Removed |
| OSI instability animated icons | Animation stopped; icons removed | Animation stopped; icons removed |
| OSI synergy icons | Removed | Removed |
| Connection-node floor icons | Hidden (handles kept) | Discarded |
| Blood-node floor icons | Hidden (handles kept) | Discarded |
| Torturer floor icons | Hidden, reset to blue (handles kept) | Discarded |
| Stage | Reset to 1 | — |
| `bMove`, `bBlock`, `bConnect` dedup flags | Reset to `true` | — |
| `bStartTorturerCD` | Reset to `true` | — |
| `torturerCount` | Reset to 8 | — |
| `PRISONERS` stack counters | All reset to 0 | — |

---

## 4. Known issues / unverified data

| # | Item | Status |
|---|------|--------|
| [#165] | Falgravn arena AABB coordinates | In-game measurement needed |
| [#165] | Falgravn floor icon coordinate space | Suspected mismatch — `/incha debug` required |
| [#165] | Yandir + Vrol AABB coordinates | In-game measurement needed |
| [#165] | Yandir + Vrol HM thresholds | In-game measurement needed |
| [#165] | Falgravn HM threshold (248,386,060) | Needs vet HM confirmation |
| #126 | Prisoner feed-stack warning threshold (9 vs 10) | Evaluate in-game |

---

*Sources: [`trial/ka/boss/Yandir.lua`](../../trial/ka/boss/Yandir.lua) · [`trial/ka/boss/Vrol.lua`](../../trial/ka/boss/Vrol.lua) · [`trial/ka/boss/Falgravn.lua`](../../trial/ka/boss/Falgravn.lua)*
