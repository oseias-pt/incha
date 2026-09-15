# Kyne's Aegis — Alert Catalogue

Independent validation reference. Each row lists the trigger, expected output, and observable behaviour so a tester can confirm correctness without reading source code.

**Legend:** `action` = action-panel text · `bar` = cast bar · `ranged` = ranged-attack bar · `flash` = full-screen flash · `osi` = above-head icon · `floor` = world-space marker  
⚠️ **HM** = hard mode only · ⚠️ **local** = fires only for the local player

---

## Yandir the Butcher

AABB `x 63200–68900 · y 24300–26300 · z 90500–99600` · HM threshold 72,769,370 HP ⚠️ unverified

### Tracker rows

| Row | Label     | Countdown              | Resets on                                                                                                   |
|-----|-----------|------------------------|-------------------------------------------------------------------------------------------------------------|
| 1   | `Totem`   | 20 s → `Totem Ready`   | Any totem spawn (133510, 133045, 133513, 133515)                                                            |
| 2   | `Gryphon` | 60 s → `Gryphon Ready` | Combat start only; below 60% HP → `Gryphon Skip! (Xs early)`; timer expires above 60% → `Gryphon Fail @ X%` |

### Alerts

| Ability ID | Name                   | Trigger                                          | Type            | Output                                        | Duration  | Colour | Sound |
|------------|------------------------|--------------------------------------------------|-----------------|-----------------------------------------------|-----------|--------|-------|
| 133510     | Harpy Totem spawn      | `ACTION_RESULT_BEGIN`                            | action          | `Kill! (Harpy Totem)` + resets Totem timer    | —         | —      | —     |
| 133045     | Dragon Totem spawn     | `ACTION_RESULT_BEGIN`                            | action          | `Kill! (Dragon Totem)` + resets Totem timer   | —         | —      | —     |
| 133513     | Gargoyle Totem spawn   | `ACTION_RESULT_BEGIN`                            | action          | `Kill! (Gargoyle Totem)` + resets Totem timer | —         | —      | —     |
| 133515     | Poison Totem           | `ACTION_RESULT_BEGIN`                            | action + ranged | `Dodge! (Poison Totem)`                       | 4300 ms   | POISON | —     |
| 133559     | Poison Totem (2nd hit) | `ACTION_RESULT_EFFECT_GAINED` → +26,800 ms delay | ranged          | *(same bar, second cast)*                     | 4300 ms   | POISON | —     |
| 133546     | Gargoyle Totem cast    | `ACTION_RESULT_BEGIN`                            | action + ranged | `Block! (Gargoyle Totem)`                     | ~5000 ms* | SILVER | —     |
| 133242     | Yandir Healing         | `ACTION_RESULT_BEGIN`                            | action + flash  | `Yandir Healing`                              | 2000 ms   | red    | —     |
| 132571     | Yandir Jump            | `ACTION_RESULT_BEGIN`                            | action + ranged | `Block! (Yandir Jump)`                        | 3000 ms   | SILVER | —     |
| 132511     | Toxic Tide             | `ACTION_RESULT_BEGIN`                            | action + ranged | `Block! (Toxic Tide)`                         | 2500 ms   | SILVER | —     |
| 135369     | Sundering Strike       | `ACTION_RESULT_BEGIN`                            | action + ranged | `Block! (Sundering Strike)`                   | 1600 ms   | SILVER | —     |
| 136591     | Sea Adder Bile Spray   | `ACTION_RESULT_BEGIN` ⚠️ local                   | action + ranged | `Dodge! (Sea Adder)`                          | 1933 ms   | SILVER | —     |

\* fallback duration — replace when `GetAbilityCastInfo` returns stable value.

**Wipe/leave:** stops all alert bars; cancels delayed second-poison timer; resets gryphon-skip flags.

### Debug panel

**Start Fight** injects a fresh boss instance and calls `onCombatState(inCombat=true)`, which arms both the Totem (20 s) and Gryphon (60 s) timers — tracker panel shows both rows counting down.  
**Wipe** stops bars and resets gryphon-skip flags; timers keep running (they only reset on the next Start Fight).

All entries are in both `instant` and `started` buckets; the panel deduplicates them into a single `(instant)` button per ability.

| Button (panel label)                              | Expected output                                                 | Notes                                                                     |
|---------------------------------------------------|-----------------------------------------------------------------|---------------------------------------------------------------------------|
| `[132511] … (instant)` Toxic Tide                 | action `Block! (Toxic Tide)` + 2500 ms SILVER ranged bar        | ✓                                                                        |
| `[132571] … (instant)` Yandir Jump                | action `Block! (Yandir Jump)` + 3000 ms SILVER ranged bar       | ✓                                                                        |
| `[133045] … (instant)` Dragon Totem spawn         | action `Kill! (Dragon Totem)` + resets Totem tracker row        | ✓                                                                        |
| `[133242] … (instant)` Yandir Healing             | action `Yandir Healing` + 2000 ms red flash                     | ✓                                                                        |
| `[133510] … (instant)` Harpy Totem spawn          | action `Kill! (Harpy Totem)` + resets Totem tracker row         | ✓                                                                        |
| `[133513] … (instant)` Gargoyle Totem spawn       | action `Kill! (Gargoyle Totem)` + resets Totem tracker row      | ✓                                                                        |
| `[133515] … (instant)` Poison Totem               | action `Dodge! (Poison Totem)` + 4300 ms POISON ranged bar      | ✓                                                                        |
| `[133546] … (instant)` Gargoyle Totem cast        | action `Block! (Gargoyle Totem)` + ~5000 ms SILVER ranged bar   | ✓                                                                        |
| `[135324] … (instant)` Butcher's Blade            | **nothing visible**                                             | `targetOnly` — skipped when injected unit is not the local player         |
| `[135369] … (instant)` Sundering Strike           | action `Block! (Sundering Strike)` + 1600 ms SILVER ranged bar  | ✓                                                                        |
| `[136591] … (instant)` Sea Adder Bile Spray       | **nothing visible**                                             | handler guards `IsUnitPlayer(unitTag)` — fake event has no player unitTag |
| `[133559] … (effect GAINED)` Poison Totem 2nd hit | **nothing immediately**; ranged POISON bar appears after 26.8 s | delayed — only if `BTotemCall` is false (first inject after Start Fight)  |

---

## Vrol Ka'lar

AABB `x 110200–118500 · y 24500–29000 · z 65000–78800` · HM threshold 72,769,370 HP ⚠️ unverified  
Floor icon: portal spawn at `(114624, 25764, 71349)` — requires `portalIconVrol` setting; survives wipes.

### Tracker rows

| Row | Label                     | Countdown                                        | Notes                                                                                       |
|-----|---------------------------|--------------------------------------------------|---------------------------------------------------------------------------------------------|
| 1   | `Next Fog` / `Fog Clears` | 30 s between / active duration                   | While fog active label switches; turns pink ≤ 5 s. Every 3 pulses of 133756 extend fog +9 s |
| 2   | `Conduit`                 | 40 s → `Conduit Ready`                           | Resets on Harpoon cast                                                                      |
| 3   | `Portal`                  | 15 s first pull, 45 s recurring → `Portal Ready` | Hidden once boss < 50% HP                                                                   |

### Alerts

| Ability ID | Name                                 | Trigger                                       | Type            | Output                                   | Duration  | Colour  | Sound                     |
|------------|--------------------------------------|-----------------------------------------------|-----------------|------------------------------------------|-----------|---------|---------------------------|
| 133994     | Portal cast                          | `ACTION_RESULT_BEGIN`                         | action + ranged | `Kill! (Conjurer)`                       | 3000 ms   | VOID    | —                         |
| 133808     | Fog cast                             | `ACTION_RESULT_BEGIN`                         | action + ranged | `Dodge! (Fog)`                           | 1000 ms   | BLUE    | —                         |
| 133913     | Harpoon                              | `ACTION_RESULT_BEGIN`                         | action + bar    | `Kill! (Harpoon)` / bar label `Harpoon!` | 16,000 ms | FLYZONE | —                         |
| 140255     | Apothecary                           | `ACTION_RESULT_BEGIN`                         | action + flash  | `Interrupt! (Apothecary)`                | 2000 ms   | blue    | CHAMPION_POINTS_COMMITTED |
| 134016     | Portal kill debuff (gained)          | `EFFECT_RESULT_GAINED` ⚠️ local               | action + bar    | `Kill! (Conjurer)`                       | 20,000 ms | FLYZONE | —                         |
| 134016     | Portal kill debuff (faded — success) | `EFFECT_RESULT_FADED` ⚠️ local, conjurer dead | action + flash  | `Portal OK!`                             | 2000 ms   | green   | DUEL_WON                  |
| 134016     | Portal kill debuff (faded — fail)    | `EFFECT_RESULT_FADED` ⚠️ local, time expired  | action + flash  | `Portal Failed!`                         | 2000 ms   | red     | DUEL_FORFEIT              |

**Wipe/leave:** stops all bars including portal kill bar; resets fog state; portal floor icon discarded on leave only.

### Debug panel

**Start Fight** injects a fresh boss instance and calls `onCombatState(inCombat=true)`, which arms Portal (15 s first interval), Conduit (40 s), and Fog (30 s) timers — all three tracker rows appear counting down.  
**Wipe** stops portal-kill bar, clears fog state and `bPORTAL_END` flag; timers reset on the next Start Fight.

All entries are in both `instant` and `started` buckets; the panel deduplicates them into a single `(instant)` button per ability. The two `effectChanged` entries for `134016` (portal kill debuff gained/faded) have **no button** — they are not in any `beginCast` bucket.

| Button (panel label)                | Expected output                                                           | Notes                                                                                                                                |
|-------------------------------------|---------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------|
| `[133808] … (instant)` Fog cast     | action `Dodge! (Fog)` + 1000 ms BLUE ranged bar; fog timer resets to 30 s | ✓                                                                                                                                   |
| `[133756] … (instant)` Fog Increase | **nothing visible**                                                       | only increments internal `fogHitCount` and extends `fogEndTime` if fog is active; if no fog is active the state update has no effect |
| `[133913] … (instant)` Harpoon      | action `Kill! (Harpoon)` + 16 s FLYZONE cast bar; conduit timer resets    | ✓                                                                                                                                   |
| `[133994] … (instant)` Portal cast  | action `Kill! (Conjurer)` + 3000 ms VOID ranged bar; portal timer resets  | ✓                                                                                                                                   |
| `[140255] … (instant)` Apothecary   | action `Interrupt! (Apothecary)` + orange flash 2000 ms                   | ✓                                                                                                                                   |

---

## Falgravn

AABB `x 73700–84500 · y 6000–22500 · z 50200–61900` · HM threshold 248,386,060 HP  
⚠️ **Floor icon coordinate space unverified** — run `/incha debug` in-arena to confirm; see [#165].

Three stages: **S1** combat start → **S2** Falgravn lands (139378 fades) → **S3** floor shatters (136727 begins).

### Tracker rows

| Stage | Row | Label         | Countdown                                                                         | Resets on                                       |
|-------|-----|---------------|-----------------------------------------------------------------------------------|-------------------------------------------------|
| S1    | 1   | `Instability` | 10 s initial, 22 s recurring → `Instability UP`                                   | `EFFECT_GAINED_DURATION` on 140944              |
| S2    | 1   | `Instability` | (same as S1)                                                                      | (same)                                          |
| S2    | 2   | `Blood Ball`  | 20 s initial (after landing), then 30 s active / 45 s between → `Blood Ball Soon` | Blood Ball gained-duration → 30 s; faded → 45 s |
| S3    | 1   | `Open Gates`  | 40 s initial, 45 s recurring → `Open Gates Soon`                                  | Each Open Gates cast                            |
| S3    | 2   | `Torturer TP` | 25 s → row cleared on expiry                                                      | Each Open Gates cast                            |

Health rules (requires `showPercent` setting): `Connect Soon!` at 90–93% and 80–83%; `Dont Ult (Floor Shatter)!` at 70–73%; `Dont Ult!` at 35–38% (S1/S2 only).

### Alerts

| Ability ID      | Name                                          | Trigger                                      | Type                            | Output                                                                 | Duration                    | Colour     | Sound                     |
|-----------------|-----------------------------------------------|----------------------------------------------|---------------------------------|------------------------------------------------------------------------|-----------------------------|------------|---------------------------|
| 137289          | Infuser cast                                  | `ACTION_RESULT_BEGIN`                        | action + ranged                 | `Interrupt! (Infuser)`                                                 | 1000 ms                     | BLUE       | —                         |
| 139961          | Infuser buff passed                           | `ACTION_RESULT_EFFECT_GAINED`                | action + flash                  | `Infuser Buff passed!`                                                 | 3000 ms                     | orange     | DUEL_START                |
| 137215          | HM confirm (gained) ⚠️ HM                     | `EFFECT_GAINED`                              | header                          | `{boss} [HM: ON]`                                                      | —                           | —          | —                         |
| 136965          | Njordal Move AoE                              | `ACTION_RESULT_BEGIN` (deduped)              | action + bar                    | `Move!`                                                                | 12,000 ms                   | FLYZONE    | —                         |
| 136953          | Njordal Block Charge                          | `ACTION_RESULT_BEGIN` (deduped; icon 137499) | action + bar                    | `Block! (Bloody Frenzy)`                                               | 6500 ms                     | FLYZONE    | —                         |
| 136976          | Blood Cleave                                  | `ACTION_RESULT_BEGIN`                        | action + bar                    | `Dodge! (Blood Cleave)` · early-warn 700 ms                            | ~2000 ms*                   | MAGENTA    | CHAMPION_POINTS_COMMITTED |
| 140294          | Blood Fountain                                | `ACTION_RESULT_BEGIN`                        | action + ranged                 | `Block! (Blood Fountain)`                                              | 3033 ms                     | MAGENTA    | —                         |
| 133428          | Lightning / Connect                           | `ACTION_RESULT_BEGIN` (deduped)              | floor                           | Shows 20 connection-node floor icons                                   | —                           | PINK       | —                         |
| 136693          | Open the Gates (S3)                           | `ACTION_RESULT_BEGIN`                        | action + flash + delayed ranged | `Open the Gates!`; after 25 s: heavy-attack bar                        | 2000 ms flash · 7500 ms bar | red / BLUE | CHAMPION_POINTS_COMMITTED |
| 137314          | Torturer feed start (S3)                      | `EFFECT_RESULT_GAINED` (deduped)             | action + bar + floor            | `Kill! (Torturer)`; torturer icon → yellow                             | 10,000 ms                   | FLYZONE    | —                         |
| 139633          | Torturer teleports down (S3)                  | `ACTION_RESULT_BEGIN`                        | action + flash                  | `Torturer Comes Down!`                                                 | 3000 ms                     | orange     | CHAMPION_POINTS_COMMITTED |
| 136958          | Torturer light attack (S3) ⚠️ local, non-tank | `ACTION_RESULT_BEGIN`                        | action + flash                  | `Dodge! (Torturer LA)`                                                 | 1000 ms                     | red        | DUEL_START                |
| 132473          | Prison debuff (gained)                        | `EFFECT_RESULT_GAINED` (per player)          | action + bar + osi              | `Kill! (Prison)`; prison icon (PURPLE) above head                      | 8000 ms                     | FLYZONE    | —                         |
| 132473          | Prison debuff (faded)                         | `EFFECT_RESULT_FADED`                        | —                               | Stops bar; removes OSI icon                                            | —                           | —          | —                         |
| 140944 / 140941 | Instability (gained) ⚠️ local                 | `EFFECT_RESULT_GAINED`                       | osi                             | Animated 40-frame icon above head (50 ms/frame)                        | until faded                 | FLYZONE    | —                         |
| 137315          | Prisoner feed stack                           | `EFFECT_RESULT_GAINED`                       | action + flash at stack 9       | `KILL Torturer! ({name} fed 9× — dying!)` · at 11: torturer icon → red | 4000 ms                     | red        | DUEL_START                |
| 129936          | Execration synergy (gained) ⚠️ local          | `EFFECT_RESULT_GAINED`                       | osi                             | Synergy icon (CRIMSON) above head                                      | until faded                 | CRIMSON    | —                         |

\* fallback — `CastDur.get` used; replace when reliable.

**Torturer floor icons** (requires `posIconsFalgravn` setting, ⚠️ coords unverified):  
8 anchors (Brekalda, Thjorlak, Aevar, Triveta, Skormgondar, Irthrig, Ama, Sislea) — blue idle · yellow feeding · green saved · red prisoner dead.  
4 blood-ball nodes (orange) shown on Blood Ball active; 20 connection nodes (red numbered) shown on Lightning, hidden on Pulse fade.

**Wipe:** stops all bars + prison bars; cancels delayed Open Gates timer; removes all OSI icons; hides (not discards) floor icons; resets torturer icons to blue; resets stage to S1 and all dedup flags.  
**Leave:** same as wipe, plus discards all floor icon handles.

### Debug panel

**Start Fight** calls `onCombatState(inCombat=true)`, which arms only the Instability timer (10 s). Tracker shows row 1 `Instability` counting down. Blood Ball and Open Gates rows are Stage 2/3 only — they appear after clicking the stage-transition buttons below.  
**Wipe** resets stage to S1, all dedup flags (`bMove`, `bBlock`, `bConnect`, `bStartTorturerCD`), and stops all bars — click each dedup button again after Wipe to re-test it.

`instant` and `started` tables are independent but identical; the panel deduplicates to a single `(instant)` button per ability. All `effectChanged` entries (Infuser Buff 139961, HM 137215, Blood Ball 136548, Torturer Feed 137314, Instability/Prison/Synergy effects) have **no button**.

| Button (panel label)                         | Expected output                                                                                              | Notes                                                                         |
|----------------------------------------------|--------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| `[129936] … (instant)` Execration synergy    | **nothing visible**                                                                                          | handler guards `IsUnitPlayer(unitTag)` — fake events have no player unitTag   |
| `[132473] … (instant)` Prison debuff         | **nothing visible**                                                                                          | `effectChanged` only (no `beginCast` entry) — button should not appear        |
| `[133428] … (instant)` Lightning / Connect   | floor icons shown (20 connection nodes) if `posIconsFalgravn` setting enabled                                | fires once only (`bConnect` dedup); click Wipe to reset                       |
| `[135271] … (instant)` Start Stage 2         | **no CA bar or action text**; sets `CURRENT_STAGE = 2`, shows torturer floor icons                           | tracker switches to S2 layout (row 2 shows Blood Ball)                        |
| `[136548] … (instant)` Blood Ball            | **nothing visible**                                                                                          | effectChanged only (no beginCast entry) — button should not appear            |
| `[136693] … (instant)` Open the Gates        | action `Open the Gates!` + red flash 2000 ms; after 25 s: 7500 ms BLUE ranged bar                            | S3 only in live play; the 25 s delayed bar fires regardless of stage in panel |
| `[136727] … (instant)` Floor Shatter (S3)    | **no CA bar or action text**; sets `CURRENT_STAGE = 3`, arms Open Gates (40 s) + Torturer TP (25 s) timers   | tracker switches to S3 layout                                                 |
| `[136958] … (instant)` Torturer light attack | **nothing visible**                                                                                          | handler guards `IsUnitPlayer(unitTag)` — fake events have no player unitTag   |
| `[136965] … (instant)` Njordal Move AoE      | action `Move!` + 12 s FLYZONE cast bar                                                                       | fires once only (`bMove` dedup); click Wipe to reset                          |
| `[136953] … (instant)` Njordal Block Charge  | action `Block! (Bloody Frenzy)` + 6.5 s FLYZONE cast bar                                                     | fires once only (`bBlock` dedup); click Wipe to reset                         |
| `[136976] … (instant)` Blood Cleave          | action `Dodge! (Blood Cleave)` + ~2 s MAGENTA bar with 700 ms early-warn sound                               | ✓                                                                            |
| `[137289] … (instant)` Infuser cast          | action `Interrupt! (Infuser)` + 1000 ms BLUE ranged bar                                                      | ✓                                                                            |
| `[139620] … (instant)` Prisoner saved        | **no CA bar or action text**; decrements `torturerCount`, marks torturer icon green if `posIconsFalgravn` on | ✓ for icon; no visible alert                                                 |
| `[139633] … (instant)` Torturer Comes Down   | action `Torturer Comes Down!` + orange flash 3000 ms                                                         | ✓                                                                            |
| `[140294] … (instant)` Blood Fountain        | action `Block! (Blood Fountain)` + 3033 ms MAGENTA ranged bar                                                | ✓                                                                            |

---

*Sources: [`trial/ka/boss/Yandir.lua`](../../trial/ka/boss/Yandir.lua) · [`trial/ka/boss/Vrol.lua`](../../trial/ka/boss/Vrol.lua) · [`trial/ka/boss/Falgravn.lua`](../../trial/ka/boss/Falgravn.lua)*
