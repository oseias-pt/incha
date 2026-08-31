# Feedback — Trial-Mechanics Review (Incha)

> Addressed to the main developer (Oseias). Compiled from a full line-by-line
> audit of the cloned repo. Every item below was double-checked against source.
> Delivery target: this file is carried on the branch opened as a PR to
> `oseias-pt/incha:master`, since issues/discussions are disabled on the fork.

Overall: clean, well-architected addon. The `require()` shim, `pcall`
crash-isolation, `stateSchema`/`fromSchema` per-instance state, and the shared
`CombatHandler` routing tables are all solid. The items below are triaged by
severity. Nothing is urgent; a couple are real, the rest are tracked or cosmetic.

---

## 🔴 P1 — Real bugs worth fixing

### 1. `ui/Panel.lua` — `hideAction()` leaves the action-text cache stale
- **Where:** `ui/Panel.lua:203-207` (`hideAction`), contrast with `panel_clear()` `:58-59` and the `action()` cache guard `:193`.
- **What:** `hideAction()` calls `ctrl.action:SetText("")` but never resets
  `ctrl.actionText`. The `action()` handler skips `SetText` when the incoming
  string equals the cached `ctrl.actionText`. So an identical recurring callout
  is silently suppressed until a *different* string appears.
- **Impact:** Reachable on `hideActionWhenNoRule` bosses (e.g. **Falgravn**,
  `trial/ka/boss/Falgravn.lua:242` sets `hideActionWhenNoRule = true`). If boss
  health leaves a threshold band and re-enters it (healing/adds oscillation),
  the `%` callout is dropped — a real missing combat alert on the hot path.
- **Fix:** add `ctrl.actionText = ""` inside `hideAction()` (mirror `panel_clear`).

### 2. `test/run_log.lua` — replay loop never drives the 200 ms lifecycle callbacks
- **Where:** `test/run_log.lua` — only `onCombatEvent` (`:296`) and
  `onEffectChanged` (`:322`) are `pcall`'d; `pipeline:enable()` is `:207`.
- **What:** `Trial:onPowerUpdate`, `boss:onUpdate`, and
  `onCombatState`/`onWipe` never run during replay.
- **Impact:** exit 0 gives false confidence. Any broken HP-milestone /
  execute-phase logic, all info-line display rendering, and wipe/timer-reset
  logic pass silently even if broken.
- **Fix:** after each event (or on a ticker) call `trial:onUpdate()`,
  `trial:onPowerUpdate(pct, max)`, and drive `onCombatState` across an inCombat
  transition.

### 3. `test/harness/eso_api.lua` — `GetPlayerRoles` is not stubbed
- **Where:** called in `trial/rg/boss/Bahsei.lua:157,184`,
  `trial/rg/RockgroveCommon.lua:70`, `trial/oc/OseinCageCommon.lua:118`,
  `trial/lc/LCCommon.lua:58`, `trial/dsr/boss/Lylanar.lua:322,335`. Not defined
  in `test/harness/eso_api.lua` (grep → 0).
- **What:** On real logs `GetPlayerRoles` exists; in the harness it is nil, so
  any OC/LC/rg replay with a player-role read throws → the `pcall` at
  `run_log.lua:322` fails → `stats.errors++` → false `exit 1`.
- **Fix:** add a stub, e.g. `local GetPlayerRoles = function() return false,false,true end`.

---

## 🟡 P2 — Real, lower impact

- **`ui/Preview.lua:25-31`** — `instAnimTick()` allocates a fresh
  `string.format` result **and** a fresh color table every 50 ms, violating the
  file's own "no per-tick allocations anywhere" rule. Precompute the frame
  texture strings and hoist the color table to a module-local reuse.
- **`test/run_log.lua:271`** — the `UNIT_REMOVED` clear branch is dead for
  `as/cr/se/lc/oc` because their `TRIAL_CONFIG.hints = {}` makes
  `getByKey("")` return nil. No crash (next `UNIT_ADDED` re-injects), but
  "removed" telemetry never fires. Resolve the removed boss via `findByName` too.

---

## 🟢 Already tracked / cosmetic — no action needed

- **`lib/MapUtils.lua`** group-nearby thresholds (Yolna 2.8 / Lokke 4.5 /
  Nahvii 7.0): geometry is correct; the *threshold scale* needs in-game
  recalibration after the `GetUnitWorldPosition` rewrite. Already tracked in
  **ROADMAP.md #786 / GitHub #29-31**.
- **`Location` bounds + HM health thresholds** for RG/DSR bosses: intentional
  placeholders (name-based detection fallback). Documented in ROADMAP Phase 6.
- **Unused ability-id constants in DSR** — confirmed **decl-only dead code**:
  `Taleria` (`NEMATOCYST_P/_AOE`, `SWELTERING_P/_AOE`, `SUFFOCATING_P/_AOE`),
  `Lylanar` (`PRE_FIREBRAND`, `PRE_FROSTBRAND`), `ReefGuardian` (`ACID_POOL`).
  Real portal tracking uses `VENOM_EVOKER_P` / `SEA_BOILER_P` / `TIDAL_MAGE_P`.
  Safe to delete whenever.

---

## Suggested order
1. P1 #1 (`hideAction` cache reset) — one line, zero risk.
2. P1 #3 (`GetPlayerRoles` stub) — one-line harness stub, removes false `exit 1`.
3. P1 #2 (drive lifecycle callbacks) — higher value, better as a follow-up to the replay loop.
