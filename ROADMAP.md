# Incha — Architecture Roadmap

Working plan from the architecture review (2026-08-22). Phases are ordered by
dependency — later phases assume earlier ones landed. Each phase should be a
small, independently shippable/testable change.

## Phase 0 — Memory foundation (do first, blocks nothing, unblocks trust in everything else)
- [ ] Make `modulesToUnload` exhaustive per trial, or better: auto-derive it
      (walk what `Factory` actually `require`s) so it can't drift as bosses
      are added. Today only the Factory itself is unloaded for `ka` — the
      boss modules and `LegacyUI` bridge leak for the whole session.
- [ ] Verify the `require` shim really frees modules: sample
      `collectgarbage("count")` before entering a trial zone, after leaving
      it, and after a manual `collectgarbage("collect")`. Confirm the number
      returns to baseline. If it doesn't, everything downstream that assumes
      "leaving a trial frees its memory" needs rethinking first.
- [ ] Reduce hot-path allocation in `HealthRules.evaluate` / `AlertSink:emit`
      (reuse a scratch table; skip re-`gsub`/`format` when the bucketed
      value hasn't changed since last tick).
- [ ] Add `core/Throttle.lua` and bucket `Trial:onPowerUpdate` (e.g. only
      re-evaluate rules when healthPercent crosses a rounded boundary)
      instead of re-running full evaluation on every raw `EVENT_POWER_UPDATE`.

**Why first:** this is pure risk-reduction on the existing design — no new
surface area, and it's the thing everything else (UI, lib) will be judged
against ("did adding this feature reintroduce leaks/stutter?").

## Phase 1 — `lib/` primitives (low risk, unlocks Phase 2+)
- [ ] `lib/Timer.lua` — `Timer.new(duration)`, `:remaining()`, `:isExpired()`,
      `:reset()`. Replace the hand-rolled `os.time() + N` arithmetic in
      Yandir/Vrol/Falgravn (`TOTEM_TIME`, `PORTAL_TIME`, `CONDUIT_TIME`,
      `FOG_TIME`, `INSTABILITY_TIME`) one boss at a time — behavior should be
      1:1, so this is a safe refactor to validate the abstraction.
- [ ] `lib/Log.lua` — debug output gated behind a flag (off by default),
      so future debugging doesn't turn into stray `d()`/`print()` calls.
- [ ] Formalize `lib/Throttle.lua` from the Phase 0 fix so `rg`/`dsr` get the
      same protection for free once they get real boss logic.

## Phase 2 — Settings foundation (needed before either UI track, and before dropping BSCHTKA)
- [ ] `core/Settings.lua` — own SavedVariables namespace (`Incha_SV` or
      similar) with defaults-merging (`ZO_SavedVars:NewAccountWide` /
      per-character as appropriate).
- [ ] Define the schema up front: per-trial alert on/off, overlay
      position/scale/lock, hardmode-detection overrides, debug flag. This is
      the contract both UI tracks below will read/write.
- [ ] One-time import from `BSCHTKA.SV_ACC.*` where a value exists, so
      existing users don't lose their current config when this lands.

**Why before UI:** both the config menu and the overlay need somewhere
durable to read/write. Building either UI against ad hoc globals first would
mean rewriting it here anyway.

## Phase 3A — Config UI (menus/windows)
- [ ] Adopt **LibAddonMenu-2.0 (LAM)** as a dependency for the settings
      panel rather than hand-building checkboxes/sliders. It's the ESO
      ecosystem standard, and — relevant to your memory goal — it's a
      *shared* library: if the user has any other LAM-based addon installed,
      it's already resident, so adding it doesn't add new baseline memory
      the way a bespoke settings window would.
- [ ] Build the panel entirely off the `core/Settings.lua` schema from
      Phase 2 — no boss/trial-specific logic in the menu itself.
- [ ] Only reach for a fully custom window if something genuinely doesn't
      fit LAM's model (e.g. visually repositioning the overlay by dragging
      it — that's really an overlay concern, see Phase 3B's "edit mode").

## Phase 3B — Overlay UI (in-play alerts/HUD)
This is the real `AlertSink` default implementation — right now `rg`/`dsr`
get silent no-ops because nothing implements the interface except the `ka`
legacy bridge.
- [ ] `ui/Panel.lua` — plain `WINDOW_MANAGER`-created controls implementing
      the existing handler vocabulary (`header/progress/action/clear/hideAction`).
      **Build the controls once, at panel creation** — never create/destroy
      controls per event; steady-state updates should only ever call
      `:SetText`/`:SetHidden` on already-existing controls. This is the UI
      analogue of the Phase 0 allocation fix — don't reintroduce per-tick
      garbage at this layer.
- [ ] Simple drag-to-move + lock, position/scale persisted via
      `core/Settings.lua` (no need for a movable-frame library for something
      this small — a plain `OnMoveStop` handler is enough).
- [ ] Wire as the **default** `alerts`/`bridge` in `Trial.create` when a
      trial passes none — `rg`/`dsr` get a working overlay immediately, with
      zero per-trial code.
- [ ] Leave `ka` on `LegacyUI` for now — don't touch working code until
      Phase 4 explicitly migrates it.

## Phase 4 — Retire the BSCHTKA dependency for `ka`
- [ ] Once Settings (Phase 2), Overlay (Phase 3B), and — if needed —
      Markers (below) cover what `LegacyUI`/`BSCHTKA` currently provide,
      switch `ka`'s bridge over and drop `BSCHTKA` as a runtime dependency.
- [ ] This is the actual payoff of the "aggregate addons to save memory"
      goal — `ka` stops requiring another addon's tables to stay loaded.

## Phase 5 — Markers/icons helper (only if `rg`/`dsr` need them)
- [ ] `core/Markers.lua` wrapping floor/world markers, replacing direct
      calls like `BSCHTKA.AddPortalIcon()`. Only build this once a boss
      actually needs it — don't build ahead of demand.

## Phase 6 — Flesh out `rg`/`dsr`
- [ ] Real `Location` bounds (currently `Location.new(0,0,0,0,0,0)` —
      always-false, dead code) and real boss modules, now built on top of
      `lib/Timer`, `lib/Throttle`, `core/Settings`, and the default
      `ui/Panel` overlay — so the new trials never repeat the patterns
      Phase 0–3 exist to fix.

---
**Status:** planning stage, nothing implemented yet. Update checkboxes as
phases land.
