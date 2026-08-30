# Incha — Development Roadmap

This file tracks deferred work that requires in-game measurement, broader design
decisions, or hasn't been scheduled yet.  Items are grouped by theme.

---

## HM Health Thresholds  (in-game measurement required)

Several bosses carry `hmHealthThreshold = math.huge` (or a placeholder `100000001`)
because their Hard Mode health pools haven't been measured yet.  Until the correct
value is supplied, `detectDifficulty()` will always return `NORMAL` for those bosses,
meaning HM-specific alerts are silently skipped.

**How to measure:**
1. Pull the boss on Veteran Hard Mode.
2. At any point during combat run:
   `/script d(GetUnitPower("boss1", POWERTYPE_HEALTH))`
3. Record the returned value and update `hmHealthThreshold` in the boss file.

| Boss file | Current value | Notes |
|---|---|---|
| `trial/cr/boss/ZmajaEncounter.lua` | `math.huge` | Cloudrest — Z'Maja |
| `trial/as/boss/OlmsEncounter.lua` | `math.huge` | Asylum Sanctorium — Saint Olms |
| `trial/dsr/boss/Lylanar.lua` | `100000001` (placeholder) | Dreadsail Reef boss 1 |
| `trial/dsr/boss/Taleria.lua` | `100000001` (placeholder) | Dreadsail Reef boss 3 |
| `trial/dsr/boss/ReefGuardian.lua` | `100000001` (placeholder) | Dreadsail Reef boss 2 |
| `trial/lc/boss/DarielEncounter.lua` | `math.huge` | Lucent Citadel — Dariel |
| `trial/lc/boss/XynizataEncounter.lua` | `math.huge` | Lucent Citadel — Xynizata |
| `trial/oc/boss/JynorahEncounter.lua` | `math.huge` | Oathsworn Pit — Jynorah |
| `trial/oc/boss/KazpianEncounter.lua` | `math.huge` | Oathsworn Pit — Kazpian |
| `trial/oc/boss/ShaperEncounter.lua` | `math.huge` | Oathsworn Pit — Shaper of Flesh |

> The Rockgrove trio (Bahsei, Oaxiltso, Xalvakka) each use `100000001` — treat these
> as placeholders; confirm with a live HM pull.

---

## AABB Bounding Boxes  (in-game measurement required)

Boss detection currently falls back to name matching (`nameAliases`).  This works on
EN clients but may fail on localised clients where boss names differ.  Adding an
axis-aligned bounding box (AABB) derived from `GetUnitWorldPosition` makes detection
locale-independent.

**How to measure:**
1. Stand at each corner of the boss arena with the boss alive.
2. Run `/script d(GetUnitWorldPosition("player"))` at each corner.
3. Record the min/max X and Z values, then populate the `location` field.

Bosses that still show a "placeholder" comment in `location`:

- All Cloudrest bosses (Z'Maja / mini-boss arena)
- All Dreadsail Reef bosses
- All Asylum Sanctorium bosses
- All Sunken Elder bosses
- All Lucent Citadel bosses
- All Oathsworn Pit bosses

Sunspire (KA) bosses already have `location` populated.

---

## Proximity Threshold Recalibration  (in-game measurement required)

`lib/MapUtils.lua` was refactored in `fix/maputils-world-position` to use
`GetUnitWorldPosition` instead of the normalised-map-coordinate API.  The threshold
values in the three callers below were written for the old `normalised-map × 1000`
scale and **must be recalibrated** in world units before the new implementation is
considered stable.  See ROADMAP.md and the comment added in each caller.

| Caller | Old threshold | Status |
|---|---|---|
| `trial/ss/boss/Yolna.lua` | 2.8 | needs recalibration |
| `trial/ss/boss/Lokke.lua` | 4.5 | needs recalibration |
| `trial/ss/boss/Nahvii.lua` | 7.0 | needs recalibration |

---

## Settings Granularity  (design + implementation)

The current settings panel exposes a single global on/off toggle.  Finer control
would let players enable only the trials or bosses they need:

- Per-trial toggles (e.g. disable all CR alerts while progging elsewhere)
- Per-boss toggles within a trial
- Per-mechanic category toggles (e.g. disable HM-only alerts in normal mode)

---

## Panel Flexible Line Count  (UI)

The info panel renders a fixed number of lines regardless of content.  A
variable-height panel that shows only populated lines would reduce clutter for bosses
with few active timers.

---

## i18n / Localisation Layer  (architecture)

All user-visible strings are currently hard-coded in English.  Adding a thin
localisation layer would allow the community to contribute translations:

- Extract all alert labels and action strings into a `lang/en.lua` table
- Load the appropriate language at startup based on `GetCVar("Language.2")`
- Fall back to `en` for any missing key
