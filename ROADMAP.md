# Incha — Roadmap

Working plan last updated 2026-08-23. Phases are ordered by dependency.
Checked items are **shipped** (committed). Unchecked items are pending.

---

## Architecture phases

### Phase 0 — Memory foundation
- [ ] Make `modulesToUnload` exhaustive per trial, or auto-derive it (walk what
      `Factory` actually `require`s). Today only the Factory itself is unloaded
      for `ka` — boss modules leak for the whole session.
- [ ] Verify the `require` shim frees GC roots: `collectgarbage("count")`
      before/after entering and leaving a trial zone; confirm it returns to baseline.
- [ ] `core/Throttle.lua` — bucket `Trial:onPowerUpdate` so full rule evaluation
      only fires when `healthPercent` crosses a rounded boundary.
- [ ] Reduce hot-path allocation in `HealthRules.evaluate` / `AlertSink:emit`
      (reuse scratch table; skip `gsub`/`format` when bucketed value hasn't changed).

### Phase 1 — `lib/` primitives
- [x] `lib/Timer.lua` — `Timer.new(duration)`, `:remaining()`, `:isExpired()`, `:reset()`.
      Used by all KA bosses.
- [x] `lib/Log.lua` — debug output gated behind a settings flag.
- [ ] Formalize `lib/Throttle.lua` from Phase 0 so `rg`/`dsr` and new trials get it for free.

### Phase 2 — Settings foundation
- [x] `core/Settings.lua` — `ZO_SavedVars:NewAccountWide`-backed namespace (`Incha_SV`),
      defaults-merging, per-trial enable flags.

### Phase 3A — Config UI (LAM settings panel)
- [x] `ui/Menu.lua` — LibAddonMenu-2.0 panel wired via `## OptionalDependsOn`.
      `/incha` slash-command fallback always present.
      Settings panel has General, Overlay, KA, RG, DSR sections.
      **Add new trial sections as each trial reaches Phase X.2+.**

### Phase 3B — Overlay UI (in-play HUD)
- [x] `ui/Panel.lua` — `WINDOW_MANAGER` overlay implementing AlertSink vocabulary
      (`header`, `info1–3`, `action`, `clear`, `hideAction`).
      Drag-to-move + lock; position/scale persisted in `core/Settings.lua`.
      Used by `ka`, `rg`, `dsr` as default bridge.

### Phase 4 — Retire BSCHTKA dependency for `ka`
- [x] Deleted `trial/ka/bridge/LegacyUI.lua` (dead 119-line bridge).
- [x] KA Factory now uses `Panel` directly; `ka` no longer depends on BSCHTKA at runtime.

### Phase 5 — Markers/icons helper (OSI)
- [x] `OSI.SetMechanicIconForUnit` wired for KA/Falgravn: Prison, Instability,
      Blood Synergy icons using `GetAbilityIcon` textures.
- [ ] `OSI.CreatePositionIcon` for floor/world markers — requires in-game coordinate
      measurement for each boss room (see In-game verification section).

### Phase 6 — Flesh out `rg` / `dsr`
- [x] Infrastructure: `Trial.create`, `Factory`, `BossRegistry`, stub modules.
- [x] `rg`: Bahsei (enrage + ManifoldDebuff OSI), Oaxiltso (stub), Xalvakka (ManifoldDebuff OSI).
      Location bounds TBD (currently `Location.new(0,0,0,0,0,0)` — zone detection always false).
- [x] `dsr`: Lylanar (stub), ReefGuardian (stub), Taleria (stub).
      Location bounds TBD.
- [ ] Real `Location` bounds for both trials — verify unit zone coordinates in-game.
- [ ] Real HM health thresholds for RG (Bahsei, Oaxiltso, Xalvakka) and DSR (all bosses).

---

## Trial roadmap

### KA — Kyne's Aegis (zoneId = 1196) ✅ Complete (feature-complete)
- [x] Infrastructure: Factory, CombatHandler, BossRegistry, Location
- [x] Yandir (boss 1): totem timer, portal alert, connection node tracking
- [x] Vrol (boss 2): portal kill-timer, fog duration countdown + extension tracking,
      Harpoon conduit timer, Apothecary interrupt
- [x] Falgravn (boss 3): Prison/Instability/Blood Synergy OSI icons, BlockCast fix,
      Torturer 25 s pre-alert via `zo_callLater` + combat guard
- [ ] KA OSI floor icons (deferred — requires in-game coordinate measurement):
      connection nodes (×8), blood fountain spawns, torturer walk positions

---

### RG — Rockgrove (zoneId = 1263) 🔄 In progress
- [x] Infrastructure: Factory, CombatHandler, BossRegistry stubs
- [x] Bahsei (boss 1): enrage at 50%/25% HP rules; ManifoldDebuff OSI mechanic icon
- [x] Oaxiltso (boss 2): stub
- [x] Xalvakka (boss 3): ManifoldDebuff OSI mechanic icon
- [ ] Real Location bounds (zone coordinates needed in-game)
- [ ] HM thresholds for all three bosses (verify in-game)
- [ ] Oaxiltso real mechanics (reference: external guides — no reference addon available)
- [ ] Xalvakka: shield event parameters, first-jump timing (verify in-game)

---

### DSR — Dreadsail Reef (zoneId = 1344) 🔄 In progress
- [x] Infrastructure: Factory, CombatHandler, BossRegistry stubs
- [x] Lylanar (boss 1): stub
- [x] ReefGuardian (boss 2): stub
- [x] Taleria (boss 3): stub
- [ ] Real Location bounds (zone coordinates needed in-game)
- [ ] All boss mechanics — no reference addon for this trial yet

---

### AS — Asylum Sanctorium (zoneId = 1000) 📋 Planned

**Architecture note:** AS is a *concurrent* multi-boss fight — Olms is always present; Llothis and
Felms spawn and go dormant on timers. This doesn't fit the single-active-boss pattern.
Model it as a **single compound boss module** (`OlmsEncounter`) that tracks all three entities
internally, rather than wiring three separate boss modules through `BossRegistry`.

**Reference addons:** `AsylumPriorityTarget` (priority targeting UI), `AsylumTracker` (comprehensive
timer tracker). Key ability IDs extracted from both.

#### AS-1 — Infrastructure
- [ ] `trial/as/Factory.lua` — zone detection (zoneId=1000), create trial, wire `OlmsEncounter`
- [ ] `trial/as/CombatHandler.lua` — delegates combat/effect events to `OlmsEncounter`
- [ ] Register `as` in `incha.lua`; add `## Description` update for AS

#### AS-2 — OlmsEncounter (single compound module)
Boss name: `"Saint Olms the Just"` (from `GetUnitName("boss1")`)

**Ability IDs (from AsylumTracker/AsylumPriorityTarget):**
```
OLMS_STORM_THE_HEAVENS  = 98535   -- Kite! 41 s repeat
OLMS_TRIAL_BY_FIRE      = 98582   -- Below 25% HP
OLMS_SCALDING_ROAR      = 98683   -- Steam breath, 28 s repeat
OLMS_GUSTS_OF_STEAM     = 98868   -- Jumps at 90/75/50/25%
OLMS_EXHAUSTIVE_CHARGES = 95482   -- 12 s repeat
STATIC_SHIELD           = 96010   -- Protector shield on Olms
LLOTHIS_DEFILING_BLAST  = 95545   -- Cone — alert with target name
LLOTHIS_OPPRESSIVE_BOLTS = 95585  -- Interrupt!
FELMS_TELEPORT_STRIKE   = 99138   -- Jump — alert with target name
DORMANT                 = 99990   -- EFFECT_RESULT_GAINED = mini sleeps;
                                  --   FADED = mini wakes
BOSS_EVENT              = 10298   -- ACTION_RESULT_EFFECT_GAINED hitValue=1
                                  --   records exact mini-boss spawn timestamp
```
- [ ] Track Llothis active/dormant state via `DORMANT` effect on unitName search "Llothis"
- [ ] Track Felms active/dormant state via `DORMANT` effect on unitName search "Felms"
- [ ] Alert `showAction("INTERRUPT Llothis!")` on `OPPRESSIVE_BOLTS BEGIN`
- [ ] Alert `showAction("Cone → <name>")` on `DEFILING_BLAST BEGIN` (hitValue=2000 filter)
- [ ] Alert `showAction("Felms jump → <name>")` on `TELEPORT_STRIKE BEGIN`
- [ ] Alert `showAction("Kite!")` on `STORM_THE_HEAVENS BEGIN`; 6 s pre-warning from timer
- [ ] Alert `showInfo` for Static Shield (protector up/down)
- [ ] `onUpdate`: display countdown timers for next Defiling Blast (~21 s), Oppressive Bolts (~12 s),
      Storm the Heavens (~41 s), Teleport Strike (~21 s)
- [ ] HP milestone alerts at 90/75/50/25% (Olms jump pre-warning)
- [ ] `reset()` on combat exit (wipe guard via `zo_callLater` + `IsUnitInCombat`)
- [ ] OSI icons: Oppressive Bolts targets (if applicable — verify if player-targeted)

#### AS-3 — In-game verification
- [ ] Confirm exact boss name string returned by `GetUnitName("boss1")` in EN/other locales
- [ ] Confirm `hitValue` filter needed on Defiling Blast (ref uses `hitValue == 2000`)
- [ ] Verify mini-boss spawn timing (~12 s from `BOSS_EVENT`) for pre-warning accuracy

---

### CR — Cloudrest (zoneId = TBD) 📋 Planned

**Architecture note:** CR supports +0/+1/+2/+3 variants. The mini-bosses (Siroria, Relequen, Galenwe)
can be active simultaneously with Z'Maja. Use a single encounter module similar to AS,
or separate mini-boss sub-modules keyed by unit name. Recommend: single `ZmajaEncounter` that
registers handlers for all entities, gated by which variant is active.

**Reference addon:** `HowToCloudrest` (comprehensive tracker).

**Zone ID:** Verify in-game — likely ~800–1000 range (Summerset, 2018). Use `GetUnitZoneByIndex`
or search for constant in ESO data files.

#### CR-1 — Infrastructure
- [ ] Determine zone ID (in-game verification)
- [ ] `trial/cr/Factory.lua`, `trial/cr/CombatHandler.lua`
- [ ] Register `cr` in `incha.lua`

#### CR-2 — Mini-boss mechanics (Siroria, Relequen, Galenwe)
These appear in the pre-Z'Maja phase (portal realm) and optionally alongside Z'Maja.

**Key ability IDs:**
```
-- Heavy Attacks (HA warning)
SIRORIA_HA    = 104755
RELEQUEN_HA   = 105780
GALENWE_HA    = 106375

-- Mini jumps (each mini teleports/jumps — dodge area)
SIRORIA_JUMP  = 106601
RELEQUEN_FLUX = 105796
GALENWE_TELE  = 106682

-- Interrupt channels
RELEQUEN_DIRECT_CURRENT  = 105380  -- Bash!
GALENWE_GLACIAL_SPIKES   = 106405  -- Bash!

-- Mini skills
SIRORIA_BANNER = 104902
RELEQUEN_JOLT  = 106614
GALENWE_DONUT  = 106378

-- Creeper root
RAZOR_THORNS   = 106656

-- Siroria
SIRORIA_DARK_TALONS   = 105765
SIRORIA_ROARING_FLARE = 103531  -- 110431 for execute phase

-- Relequen
RELEQUEN_OVERLOAD     = 87346   -- 103555 for debuff on player

-- Galenwe
GALENWE_HOARFROST_CAST  = 105151  -- 110466 execute
GALENWE_HOARFROST       = 103695  -- 110516 execute
GALENWE_HOARFROST_SYN   = 103697  -- 110525 execute
GALENWE_HOARFROST_AOE   = 103765
GALENWE_CHILLING_COMET  = 106374  -- 106367
```
- [ ] HA warnings for active mini-bosses
- [ ] Jump alerts with mini-boss name
- [ ] Interrupt alerts (`DIRECT_CURRENT`, `GLACIAL_SPIKES`)
- [ ] Overload target name alert (Relequen)
- [ ] Hoarfrost player icon via OSI (Galenwe)

#### CR-3 — Z'Maja encounter
```
-- Portal phases
ZMAJA_RESET        = 107478  -- Reset portals
PORTAL_OPEN        = 103946
PORTAL_CLOSED_1    = 104057
PORTAL_CLOSED_2    = 104792
PORTAL_CLOSED_3    = 105890
PORTAL_CLOSED_4    = 105218  -- player exits shadow realm

-- Malevolent Cores (balls)
CORE_EXPOSED       = 103980
CORE_PICKED_UP     = 103989  -- hitValue: ball picked up
CORE_MISSED        = 110202  -- ball hits player (not picked up)

-- Z'Maja mechanics
ZMAJA_JUMP         = 104564
ZMAJA_HIDE_JUMP    = 104452
CRUSHING_DARK_1    = 105152
CRUSHING_DARK_2    = 105172
CRUSHING_DARK_3    = 105239
SHADOW_SPLASH      = 105123  -- Drop from ceiling
BANEFUL_MARK       = 107196  -- Execute mechanic
SHADOW_BEAD_TICK   = 105339
SHADOW_BEAD_SPAWN  = 105363
SHADOW_BEAD_CHARGE = 105373
CREEPER_SPAWN      = 105016
OLORIME_SPEAR      = 104018  -- Spear grant
ZMAJA_SHACKLE_MINI = 107490  -- Mini dies → Z'Maja phase
```
- [ ] Portal open/close alerts
- [ ] Z'Maja jump alert + position tracking
- [ ] Crushing Darkness alert (kite)
- [ ] Shadow Splash cast bar
- [ ] Baneful Mark (execute) alert
- [ ] Malevolent Core: balls not picked up alert
- [ ] Olorime Spear: flash alert on spear grant

#### CR-4 — In-game verification
- [ ] Zone ID constant
- [ ] Confirm portal assignments fire correctly with all group configurations
- [ ] Verify Shadow Bead spawn/charge events for ground-icon eligibility

---

### LC — Lucent Citadel (zoneId = TBD) 📋 Planned

**Architecture note:** Sequential bosses, fits single-active-boss model.
5–6 encounters: Baron, Cavot, Orphic, Xoryn, Zilyesset (with Count Ryelaz).
ArcaneKnot may be a sub-phase or trash encounter — verify in-game.

**Reference addons:** `LucentCitadelHelper` (LCH), `LucentCitadel` (LC).

**Zone ID:** Verify in-game (Gold Road chapter, 2024 — likely ~1490–1520 range).

#### LC-1 — Infrastructure
- [ ] Determine zone ID
- [ ] `trial/lc/Factory.lua`, `trial/lc/CombatHandler.lua`
- [ ] Register `lc` in `incha.lua`; stub bosses: Baron, Cavot, Orphic, Xoryn, Zilyesset

#### LC-2 — Common / trash mechanics
These apply throughout all encounters:
```
HINDERED          = 165972  -- Tank swap debuff → OSI icon for tanks
RADIANCE_DEBUFF   = 214675  -- Screen border alert (CombatAlerts.AlertBorder)
SOLAR_FLARE       = 222475  -- Dremora Spellcaster cast bar alert
```
- [ ] `trial/lc/LCCommon.lua`: Hindered OSI icon (tank-only), Radiance border, Solar Flare cast bar

#### LC-3 — Orphic
From LCH: color-change mechanic, clock mechanic (cardinal/non-cardinal).
- [ ] Verify Orphic ability IDs from LCH.Orphic module (not yet read — verify separately)
- [ ] Color-change alert (was `orphicIsCastingColorChange` tracked in LC status)
- [ ] Clock phase alert

#### LC-4 — Xoryn
```
SPLINTERED_BURST     = 219799  -- Crystal Atronach AOE on tank
GLASS_STOMP          = 219797  -- Splintered Shards cast
ARCANE_CONVEYANCE    = 223024  -- Tether cast
ARCANE_CONVEYANCE_DB = 223060  -- Tether debuff
LUSTROUS_JAVELIN     = 223546  -- Mantikora Javelin
NECROTIC_BARRAGE     = 223198
ACCELERATING_CHARGE  = 214542  -- Channel before chain lightning (interrupt!)
FLUCTUATING_CURRENT  = 214597  -- Debuff: holding for up to 15 s → death
OVERLOADED_CURRENT   = 214745  -- Debuff from dropping fluctuating current
TEMPEST              = 215107  -- Group-wide line mechanic from mirrors
KNOT_CARRY           = 213477  -- Player picks up knot → alert with name
```
- [ ] Accelerating Charge interrupt alert
- [ ] Fluctuating Current player icon (timer OSI + alert if >12 s held)
- [ ] Knot Carry: who holds it → `showInfo`
- [ ] Tether debuff player icons
- [ ] Tempest line mechanic alert

#### LC-5 — Zilyesset (with Count Ryelaz)
```
BRILLIANT_ANNIHILATION = 214187  -- Room wipe → cast bar
BLEAK_ANNIHILATION     = 214203  -- Room wipe → cast bar
PORCINLIGHT            = 219329  -- Player is on dark side (with Count Ryelaz)
PORCINDARK             = 219330  -- Player is on light side (with Zilyesset)
SUMMON_LIGHTWEAVER     = 218113  -- Big add (light side)
SUMMON_BLACKGUARD      = 218109  -- Big add (dark side)
```
OSI pad icons (world coordinates from LCH.Zilyesset — 6 numbered pads):
```
Count Ryelaz side:  [127371,33533,132051] [125015,33533,133229] [122751,33533,131966]
Zilyesset side:     [127396,33541,128074] [124978,33541,126882] [122814,33541,127806]
```
- [ ] Annihilation cast bar alert (both Brilliant and Bleak, deduplicate with `annihilationOngoing` flag)
- [ ] Player side detection (`showInfo` which boss room they're in)
- [ ] Big add alert when on matching side
- [ ] OSI pad number icons (1/2/3 on each side) — requires OSI

#### LC-6 — Baron and Cavot
These modules exist in LC main but LCH doesn't cover them → mechanics unknown without reading LC boss files.
- [ ] Read `LucentCitadel/boss/Baron.lua` and `Cavot.lua` to extract ability IDs
- [ ] Implement once abilities are known

#### LC-7 — In-game verification
- [ ] Zone ID, boss name strings, HM thresholds
- [ ] Pad icon coordinate accuracy (LCH coords pre-measured but verify they match)

---

### OC — Ossein Cage (zoneId = TBD) 📋 Planned

**Architecture note:** 3 sequential bosses, fits single-active-boss model.
Boss 1: Jynorah (with Skorkhif mini). Boss 2: Kazpian. Boss 3: Shaper of Flesh.

**Reference addons:** `OsseinCageHelper` (OCH), `AsquartOsseinCageHelper` (Asquart).

**Zone ID:** Verify in-game (Fallen Banners DLC, 2025 — likely ~1600+ range).

#### OC-1 — Infrastructure
- [ ] Determine zone ID
- [ ] `trial/oc/Factory.lua`, `trial/oc/CombatHandler.lua`
- [ ] Register `oc` in `incha.lua`; stub bosses: Jynorah, Kazpian, ShaperOfFlesh

#### OC-2 — Common / trash mechanics
```
HINDERED             = 165972   -- Tank swap debuff → OSI icon (tank-only)
MURDEROUS_TRAUMA     = 245785   -- Tormented Carrion Reaper heavy → heal absorption
SECOND_BOSS_TRAUMA   = 245919   -- Boss 2 heavy trauma
SPECTRAL_REVENGE     = 236569   -- Spectral Revenant
SKULLSTORM           = 236631   -- Skullmancer → cast bar alert
ASPECT_OF_TERROR     = 245318
TOXIC_IRE            = 160007   -- Spectral Revenant → "Toxic Ire (you)" alert
CORVID_SWARM         = 236947   -- Murder Corvid → screen border debuff
CURSED_TERRAIN       = 236571   -- Tormented Deadraiser → screen border debuff
DETONATE_SOUL_DB     = 236778   -- Soul Devourer → cast bar alert on player
LIFE_DRAIN           = 236751   -- Soul Devourer → alert on player
THISA_BLOOD_DIVE     = 238847   -- Blood Drinker → alert
CAUSTIC_CARRION_1    = 240708   -- Trash/Boss1/3 portals debuff → show stack count
CAUSTIC_CARRION_2    = 241089   -- Boss2 portals debuff
```
- [ ] Hindered OSI icon (tank-only)
- [ ] Skullstorm cast bar
- [ ] Toxic Ire alert (only once per 10 s to avoid spam)
- [ ] Screen borders for Corvid Swarm, Cursed Terrain
- [ ] Detonate Soul cast bar + alert
- [ ] Life Drain alert
- [ ] Caustic Carrion stack display (`showInfo`) with color gradient (6/8/10 max by boss)

#### OC-3 — Jynorah (boss 1)
Two dragons: **Myrinax** (sparking/blue) and **Valneer** (blazing/red), plus main bosses Jynorah and Skorkhif.

```
-- Curses
SPARKING_CURSE_CAST  = 234000   -- From Jynorah
BLAZING_CURSE_CAST   = 234276   -- From Skorkhif
SPARKING_CURSE_DB    = 234008   -- Debuff on player
BLAZING_CURSE_DB     = 234280   -- Debuff on player

-- Stomps (dodge area)
COLDFLAME_STOMP      = 234521   -- Jynorah
BRIMSTONE_STOMP      = 234524   -- Skorkhif

-- Fire walls
COLDFLAME_SURGE      = 234321   -- Jynorah → "Surge (you)" if player hit
BRIMSTONE_SURGE      = 234330   -- Skorkhif → "Surge (you)" if player hit

-- Titanic Clash (phase where dragons fight each other)
TITANIC_CLASH        = 232375   -- Phase start → ~37.5 s duration countdown
TITANIC_CLASH_HIT_V  = 232460   -- Hits Valneer
TITANIC_CLASH_HIT_M  = 232465   -- Hits Myrinax

-- Titanic Leaps (dragons leap in room)
MYRINAX_LEAP_UPPER   = 233477
MYRINAX_LEAP_EXIT    = 234704
MYRINAX_LEAP_MID     = 233452
VALNEER_LEAP_UPPER   = 233489
VALNEER_LEAP_EXIT    = 234722
VALNEER_LEAP_MID     = 233466
-- Cooldowns: first=5s, recurring=48s, execute=48s (adjust by leaps since Clash)

-- Heat Rays (from dragon summons)
JYN_HEAT_RAY         = 234141   -- Jynorah's dragon summon
SKOR_HEAT_RAY        = 234161   -- Skorkhif's dragon summon

-- Reflective Scales (tank mechanic — don't hit during this)
MYRINAX_REFL_SCALES  = 233321
VALNEER_REFL_SCALES  = 233330

-- Tail Slams
MYRINAX_TAIL_SLAM    = 235800
VALNEER_TAIL_SLAM    = 235803

-- Incinerating Smash
INCINERATING_SMASH   = 233594
SWIFT_DETONATION     = 234437

-- Dragon breath (ground icon on target)
MYRINAX_GOADED_BREATH = 234548
VALNEER_GOADED_BREATH = 234558

-- Portal phase
-- (ability IDs TBD — verify in-game)
```
- [ ] Curse debuff alert with color (blue=sparking, red=blazing)
- [ ] Stomp alert (dodge!)
- [ ] Surge alert when player is targeted
- [ ] Titanic Clash phase: countdown timer in `showInfo`
- [ ] Titanic Leap countdown between leaps
- [ ] Heat Ray alert (show only if relevant curse active — match Jyn vs Skor)
- [ ] Reflective Scales: screen border or cast bar when on tank
- [ ] Dragon breath: OSI ground icon on targeted player
- [ ] Portal phase alert + boss-side assignment hint

#### OC-4 — Kazpian (boss 2)
```
-- Molag Kena mechanics
HEAVY_SHOCK          = 235206   -- Interrupt!
STORM_SLAM           = 235201
STORM_SURGE          = 235205

-- Chains
DOMINATORS_CHAINS_1  = 232773   -- Chain cast
DOMINATORS_CHAINS_2  = 232775
CHAINS_ACTIVE_1      = 232779   -- Chain debuff active
CHAINS_ACTIVE_2      = 232780
TORTUROUS_CHAINS     = 236338   -- Debuff: players too close

-- Giant Sword
SWORD_KB_PULSE_1     = 235495
SWORD_KB_PULSE_2     = 244937
SWORD_CONES          = 232574
SWORD_SHOCK_SPEAR    = 235514

-- Kazpian own
KAZPIAN_TRAUMA       = 245165   -- Frenzy trauma
AGONIZER_BOMBS       = 237149
BITING_BLAZE_1       = 235354   -- Cast
BITING_BLAZE_2       = 246009
VILE_LEAP            = 235557
SEETHING_VILE_LEAP   = 245208
VILE_TELEPORT        = 232969   -- Teleport to start portal phase

-- Trash helpers
STRICKEN             = 235594   -- Tank swap debuff
RITUAL_BUFF          = 234349   -- Pain Channeler portal active
FIREBOMB_DB          = 245264
TREMOR_SHARDS        = 245255   -- King Khrogo
IMMOLATING_SPHERE    = 237011   -- Incinerator
```
- [ ] Heavy Shock interrupt alert
- [ ] Chains alert with targets (who is chained)
- [ ] Torturous Chains: alert if player has both chain debuffs nearby (too close)
- [ ] Giant Sword: alert on cones/knockback pulse
- [ ] Agonizer Bombs alert
- [ ] Biting Blaze: cast bar alert
- [ ] Vile Leap / Seething Vile Leap alert
- [ ] Portal phase: detect via `VILE_TELEPORT` or `RITUAL_BUFF`

#### OC-5 — Shaper of Flesh (boss 3)
- [ ] Read `OsseinCageHelper/modules/ShaperOfFlesh.lua` to extract ability IDs
- [ ] Implement once abilities are known

#### OC-6 — In-game verification
- [ ] Zone ID, boss name strings, HM thresholds (dragon_max_hp=242176464 on vet HM)
- [ ] Portal color assignment logic (Jynorah) — verify curse tracking accuracy
- [ ] Caustic Carrion max danger stacks per boss (6/8/10 per OCH)

---

### SE — Sanity's Edge (zoneId = 1427) 📋 Planned

**Architecture note:** 3 sequential bosses, fits single-active-boss model.
Boss 1: Exarchanic Yaseyla. Boss 2: Chimera. Boss 3: Ansuul the Tormentor.

**Reference addons:** `SanitysEdgeHelper` (SEH), `SlipsSanitysEdgeAssist` (SSEA).

#### SE-1 — Infrastructure
- [ ] `trial/se/Factory.lua`, `trial/se/CombatHandler.lua`
- [ ] Register `se` in `incha.lua`; stub bosses: Yaseyla, Chimera, Ansuul

#### SE-2 — Yaseyla (boss 1)
```
-- Primary abilities
FIREBOMB_TOSS        = 183660
SHRAPNEL             = 199131
KNIFE_BLAST          = 183803   -- 183804
VENGEFUL_STRIKE      = 185071
VANTONS_CLARITY      = 184041   -- Portal synergy
SEETHE               = 162783   -- Enrage

-- Wamasu charges (Contramagis Wamasu)
WAMASU_CHARGE_1      = 191133
WAMASU_CHARGE_2      = 191139
WAMASU_CHARGE_3      = 191134
WAMASU_CHARGE_4      = 200544
WAMASU_CHARGE_5      = 200558
WAMASU_CHARGE_6      = 200559

-- Wamasu Charged Headbutt
HEADBUTT_1           = 184999
HEADBUTT_2           = 185002
HEADBUTT_3           = 185000

-- Wamasu Overwhelming Lightning
OVW_LIGHTNING_1      = 183598
OVW_LIGHTNING_2      = 198510
OVW_LIGHTNING_3      = 183599

-- Frost Bombs (Tomb mechanic)
TOMB_FROSTBOMB_1..9  = 183790,183783,192304,191049,188065,199254,185406,183768,185392

-- Hindered
HINDERED             = 165972   -- Tank swap debuff → OSI icon (tank-only)

-- Trueshot
TRUESHOT             = 184802
```
HP milestone alerts (from SSEA defaults): 90%, 70%, 50%, 30%, 20%, 10% — Wamasu + Archers warning;
60%, 35% — portal phase; 80%, 55%, 25%, 20%, 10% — Shrapnel warning.

- [ ] Hindered OSI icon (tank-only)
- [ ] Wamasu charge cast bar + ground icon on targeted player
- [ ] Fire Bomb Toss alert
- [ ] Shrapnel alert
- [ ] Knife Blast cast bar
- [ ] Vengeful Strike alert
- [ ] Frost Bomb OSI target icon (who has it)
- [ ] Portal alert on Vanton's Clarity
- [ ] HP milestone pre-warnings (Wamasu/portal/Shrapnel phases)
- [ ] Enrage (Seethe) alert

#### SE-3 — Chimera (boss 2)
Chimera alternates between active (stone-form off) and petrified phases. Key timers:
- Despawn timer (active → petrify countdown)
- Chain Lightning repeat timer

```
-- Chain Lightning (many variants)
CHAIN_LIGHTNING      = {183858,183898,183911,183913,184033,184028,184036,
                        184032,184029,184030,183915,183917,183885}

-- Chain Circuit debuffs on players
CHAIN_CIRCUIT_DB     = {184063,184068,184066,184067}

-- Arctic Shred (~5.5 s cooldown)
ARCTIC_SHRED         = 184275

-- Lifecycle
VIVIFY               = 186000   -- Comes out of stone
PETRIFY              = 185038   -- Goes back into stone

-- Sub-boss abilities
LION_DOUBLE_STRIKE   = 186969   -- Ascendant Lion
GRYPHON_PECK         = 187002   -- Ascendant Gryphon
```
OSI position icons (portal locations — hard-coded world coordinates):
```
WAMASU_PORTAL:  [182466, 40391, 222635]
LION_PORTAL:    [187456, 40387, 222644]
GRYPHON_PORTAL: [185015, 40390, 228119]
```
Crystal number icons (used during active phase for positioning):
- Normal mode: 4 sets of 3 positions each
- HM: 5 sets of 3 positions each
- Coordinates in SEH.data (need to read `SanitysEdgeHelper` main data file)

- [ ] Vivify/Petrify: track active/petrified state
- [ ] Despawn timer countdown in `showInfo` when Chimera is active
- [ ] Chain Lightning timer countdown
- [ ] Chain Circuit debuff OSI player icon
- [ ] Arctic Shred alert
- [ ] Lion Double Strike + Gryphon Peck cast bar alerts
- [ ] OSI portal icons (Wamasu/Lion/Gryphon positions)
- [ ] Crystal number icons (need coordinates from SEH data file)

#### SE-4 — Ansuul the Tormentor (boss 3)
The most complex SE boss. Has a maze phase (The Ritual) and a split-clone phase (Breakdown).

```
-- Primary mechanics
POISONED_MIND        = {184707,184709,199644,184711}  -- Poison debuff → green border
MANIC_PHOBIA         = {185117,185123,185171,185251}  -- Player icon (fear marker)
WRACK                = 184621   -- Kite lightning
CALAMITY             = 186728   -- Heavy cone → timer countdown
SUNBURST             = 199344   -- Fire explosion circle
WRATHSTORM           = 189163
EXECUTE              = 198482
CORRUPT              = 187091

-- Enraged Atronachs
ENRAGED_INFERNO      = 183778   -- Interrupt!
ENRAGED_FLARE        = 183784

-- Phase transitions
THE_RITUAL           = (TBD)    -- Maze starts (EFFECT_GAINED) / ends (EFFECT_FADED)
BREAKDOWN_RED        = (TBD)    -- Split red clone
BREAKDOWN_GREEN      = (TBD)    -- Split green clone
BREAKDOWN_BLUE       = (TBD)    -- Split blue clone
```
OSI corner icons (world coordinates from SEH):
```
GREEN corner: [196570, 30199, 38049]
RED corner:   [200014, 30199, 44150]
BLUE corner:  [203417, 30199, 38080]
```
Calamity timers (from SEH data): first Calamity CD and recurring Calamity CD (check SEH data file).
Split HP tracking: all three clones named "Ansuul the Tormentor" — differentiate by buff
(`ansuul_red_split_breakdown`, `ansuul_green_split_breakdown`, `ansuul_blue_split_breakdown`).

- [ ] Poisoned Mind: CombatAlerts green border on player
- [ ] Manic Phobia: OSI player icon
- [ ] Wrack: cast bar / kite alert
- [ ] Calamity: countdown timer + alert when imminent
- [ ] Sunburst: alert
- [ ] Enraged Inferno: interrupt alert
- [ ] The Ritual (maze): phase entry/exit alert + timer
- [ ] Breakdown: show colored clone HP (via combat event damage accumulation + reticle-over check)
- [ ] OSI corner icons (green/red/blue positions)
- [ ] Enraged Fragment: target marker on `"Enraged Fragment"` units

#### SE-5 — In-game verification
- [ ] Confirm zone ID = 1427 matches the correct zone (verify with `GetUnitZoneByIndex`)
- [ ] Breakdown ability IDs (`ansuul_red/green/blue_split_breakdown`) — read SEH main data file
- [ ] Chimera crystal number icon coordinates — read SEH data file
- [ ] Calamity cooldown values — read SEH data file
- [ ] Chimera despawn CD and Chain Lightning CD — read SEH data file

---

## In-game verification backlog
(Items requiring a live ESO session)

### All new trials
- [ ] Zone IDs for CR, LC, OC (AS=1000 confirmed, SE=1427 confirmed)
- [ ] Boss name strings for `BossRegistry.nameAliases` in each trial's Factory

### KA
- [ ] OSI floor icon world coordinates: connection nodes (×8), blood fountains, torturer walk spots

### RG
- [ ] Real Location bounds for zone detection
- [ ] HM thresholds: Bahsei, Oaxiltso, Xalvakka
- [ ] Xalvakka shield event params + first-jump timing

### DSR
- [ ] Real Location bounds
- [ ] All boss mechanics (no reference addon found)

### OC
- [ ] dragon_max_hp on non-HM vet (242,176,464 confirmed for HM from OCH)
- [ ] Portal-phase ability IDs for Jynorah

### SE
- [ ] Breakdown split-clone ability IDs
- [ ] Chimera crystal icon coordinates (normal + HM)
- [ ] Calamity first/recurring cooldown values

---

## Open architecture questions

1. **`core/` must not depend on `ui/`** — currently `core/Trial.lua` does
   `require("ui.Bridge")`, which inverts the dependency layer.  `Bridge` is a
   pure interface (no WINDOW_MANAGER calls, no UI state) and belongs in core.
   Fix: move `ui/Bridge.lua` → `core/Bridge.lua`; update the two callers:
   `core/Trial.lua` and `ui/Panel.lua` both `require("core.Bridge")`.
   Update `incha.txt` accordingly (remove `ui/Bridge.lua`, add `core/Bridge.lua`
   in the core block before `core/Trial.lua`).

2. **AS/CR concurrent-boss model**: both trials have multiple simultaneous boss entities.
   We need either (a) a compound module that handles all entities internally, or
   (b) a small extension to `Trial` that supports multiple "active" bosses.
   Option (a) is lower risk and doesn't change the existing API.

2. **`modulesToUnload` drift**: each new trial added without updating this list extends
   the session-lifetime leak. Consider auto-deriving from Factory `require` calls (Phase 0).

3. **Zone ID discovery**: for trials without a known ID, use:
   ```lua
   d(GetUnitZoneByIndex(GetZoneId()))
   ```
   inside the trial zone. Zone IDs are decimal integers.

4. **OSI dependency**: SE and LC use OSI extensively. Ensure `## OptionalDependsOn: OdySupportIcons`
   remains in `incha.txt` (already present) and all OSI calls are nil-guarded.
