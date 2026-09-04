--- lang/en.lua  -  English string table.
---
--- Keys are lowercase snake_case.  Color codes (|cRRGGBB...|r) are kept
--- inside the values so translators only change the text, not the markup.
--- Format specifiers (%.0f, %s, %d, etc.) must be preserved in the same
--- order as the call site passes arguments.
---
--- To add a new locale, copy this file to lang/<code>.lua, translate every
--- value, and add the new file to incha.txt BEFORE core/Lang.lua.

local M = {}

-- ── Boss unit names ──────────────────────────────────────────────────────────
-- Matched against GetUnitName() results; must match the game client's locale.

M.boss_lokkestiiz           = "Lokkestiiz"
M.boss_yolnahkriin          = "Yolnahkriin"
M.boss_nahviintaas          = "Nahviintaas"
M.boss_bahsei               = "Bahsei"
M.boss_oaxiltso             = "Oaxiltso"
M.boss_xalvakka             = "Xalvakka"
M.boss_lylanar              = "Lylanar"
M.boss_turlassil            = "Turlassil"
M.boss_reef_guardian        = "Reef Guardian"
M.boss_tideborn_taleria     = "Tideborn Taleria"
M.boss_saint_olms           = "Saint Olms the Just"
M.boss_zmaja                = "Z'Maja"
M.boss_siroria              = "Siroria"
M.boss_relequen             = "Relequen"
M.boss_galenwe              = "Galenwe"
M.boss_yaseyla              = "Exarchanic Yaseyla"
M.boss_chimera              = "Chimera"
M.boss_ansuul               = "Ansuul the Tormentor"
M.boss_jynorah              = "Jynorah"
M.boss_skorkhif             = "Skorkhif"
M.boss_kazpian              = "Overfiend Kazpian"
M.boss_shaper               = "Shaper of Flesh"
M.boss_xynizata             = "Xynizata"
M.boss_xoryn                = "Xoryn"
M.boss_count_ryelaz         = "Count Ryelaz"
M.boss_zilyesset            = "Zilyesset"
M.boss_orphic               = "Orphic Shattered Shard"
M.boss_dariel               = "Dariel"

-- ── Common fallback labels ───────────────────────────────────────────────────

M.common_ready              = "ready"
M.common_soon               = "soon!"
M.common_now                = "NOW"
M.common_up                 = "up!"
M.common_imminent           = "imminent"
M.common_interrupt          = "INTERRUPT!"
M.common_you                = "YOU"

-- ── Sunspire (SS) ── SunspireCommon.lua ─────────────────────────────────────

M.ss_block_heavy_attack     = "Block! (Heavy Attack)"
M.ss_block_jump             = "Block! (Jump)"
M.ss_dodge_leap             = "Dodge! (Leap)"
M.ss_block_shield_charge    = "Block! (Shield Charge)"
M.ss_dodge_breath           = "Dodge! (Breath)"
M.ss_atro_incoming          = "Atro incoming! (Spit)"

-- SS shared (Lokke / Yolna / Nahvii share these info-line format strings)
M.ss_landing                = "|c5cd65cLanding|r: %.0fs"
M.ss_can_fly_in             = "|cffa500Can Fly In|r: %.1f%%"

-- ── Sunspire ── Lokke ────────────────────────────────────────────────────────

M.ss_lokke_block_glacial    = "Block! (Glacial Fist)"
M.ss_lokke_laser            = "|c7fffd4Laser|r: %.0fs"
M.ss_lokke_tomb_header_inc  = "|c00ffffIce Tomb|r |cff0000%s|r |cff0000INC|r"
M.ss_lokke_tomb_header_cd   = "|c00ffffIce Tomb|r |cff0000%s|r |c00ffffin|r: %.0fs"
M.ss_lokke_tomb_active      = "|c00ffffIce Tomb|r |cff0000%d|r"
M.ss_lokke_tomb_slot_a      = "[|c00ff00A|r]: "
M.ss_lokke_tomb_slot_b      = "[|c00ff00B|r]: "
M.ss_lokke_tomb_take        = "|cd92626Take|r "
M.ss_lokke_tomb_heal        = "|c00ffffHeal|r "
M.ss_lokke_tomb_done        = "|c00FF00Done|r"
M.ss_lokke_tomb_inc         = "|c00ffffinc|r"
M.ss_lokke_tomb_double      = "|c00ff00Double|r"

-- ── Sunspire ── Yolna ────────────────────────────────────────────────────────

M.ss_yolna_kill_atro        = "Kill Atro!"
M.ss_yolna_dodge_geyser     = "Dodge! (Geyser)"
M.ss_yolna_next_flare       = "|ce51919Next Flare|r: %.0fs"
M.ss_yolna_next_flare_inc   = "|ce51919Next Flare|r: |cff0000INC|r"
M.ss_yolna_cataclysm_ends   = "|ce51919Cataclysm Ends|r: %.1fs"

-- ── Sunspire ── Nahvii ───────────────────────────────────────────────────────

M.ss_nahvii_you_meteor      = "YOU -> Meteor!"
M.ss_nahvii_block_slam      = "Block! (Slam)"
M.ss_nahvii_block_stonefist = "Block! (Stonefist)"
M.ss_nahvii_sweep_right     = "> Sweep Breath >>>"
M.ss_nahvii_sweep_left      = "<<< Sweep Breath <"
M.ss_nahvii_soul_tear       = "SOUL TEAR!"
M.ss_nahvii_dodge_negate    = "Dodge! (Negate)"
M.ss_nahvii_next_meteor     = "|cf51414Next Meteor|r: %.0fs"
M.ss_nahvii_next_meteor_inc = "|cf51414Next Meteor|r: |cff0000INC|r"
M.ss_nahvii_interrupt_in    = "|c7fffd4Interrupt in|r: |cff0000%.1fs|r"
M.ss_nahvii_next_pins       = "|c7fffd4Next Pins|r: |cffcc00%.0fs|r"
M.ss_nahvii_portal_urgent   = "|c7fffd4Portal|r: |cff0000%.0fs|r"
M.ss_nahvii_portal          = "|c7fffd4Portal|r: %.0fs"
M.ss_nahvii_fire_storm_begin = "|ce51919Fire Storm Begin|r: %.1fs"
M.ss_nahvii_fire_storm_end  = "|ce51919Fire Storm End|r: %.1fs"
M.ss_nahvii_portal_wipe     = "|c8a2be2Portal Wipe|r: %.0fs"

-- ── Rockgrove (RG) ── RockgroveCommon.lua ───────────────────────────────────

M.rg_block_sundering        = "Block! (Sundering)"
M.rg_dodge_scalding         = "Dodge! (Scalding)"

-- ── Rockgrove ── Oaxiltso ────────────────────────────────────────────────────

M.rg_oaxiltso_dodge_cone    = "Dodge! (Cone)"
M.rg_oaxiltso_add_spawning  = "ADD SPAWNING!"
M.rg_oaxiltso_next_blitz    = "|cff6030Next Blitz|r: %.0fs"
M.rg_oaxiltso_next_blitz_inc = "|cff6030Next Blitz|r: |cff0000INC|r"
M.rg_oaxiltso_next_sludge   = "|c50c050Next Sludge|r: %.0fs"
M.rg_oaxiltso_next_sludge_inc = "|c50c050Next Sludge|r: |cff0000INC|r"
M.rg_oaxiltso_boss_add_enrage = "|cff2020BOSS + ADD ENRAGED|r"
M.rg_oaxiltso_boss_enraged  = "|cff2020BOSS ENRAGED|r"
M.rg_oaxiltso_add_enraged   = "|cff6020ADD ENRAGED|r"

-- ── Rockgrove ── Bahsei ──────────────────────────────────────────────────────

M.rg_bahsei_next_curse      = "|caa50ffNext Curse|r: %.0fs"
M.rg_bahsei_next_curse_inc  = "|caa50ffNext Curse|r: |cff0000INC|r"
-- Portal: countdown uses two args (%d = portal number, %.0f = seconds remaining)
M.rg_bahsei_portal_cd       = "|c38bdf8Portal|r |c7b82a0(%d)|r: %.0fs"
M.rg_bahsei_portal_cw       = "|c00cc00CW|r"
M.rg_bahsei_portal_ccw      = "|cff8040CCW|r"
M.rg_bahsei_portal_progress = "|c7b82a0in progress|r"
M.rg_bahsei_tank_exploding  = "|cff2020TANK EXPLODING|r: %.0fs!"
M.rg_bahsei_death_touch     = "|c6699ffDeath Touch|r: %.1fs"
M.rg_bahsei_no_portal       = "|cff6030No Portal|r: %.0fs"
M.rg_bahsei_next_sickle     = "|ccc80ffNext Sickle|r: %.0fs"
M.rg_bahsei_next_sickle_inc = "|ccc80ffNext Sickle|r: |cff0000INC|r"

-- ── Rockgrove ── Xalvakka ────────────────────────────────────────────────────

M.rg_xalvakka_next_jump     = "|cffaa40Next Jump|r: %.0fs"
M.rg_xalvakka_next_jump_inc = "|cffaa40Next Jump|r: |cff0000INC|r"
M.rg_xalvakka_soul_res      = "|cff6600Soul Resonance|r: %.1fs"
M.rg_xalvakka_manifold      = "Manifold: %s"
M.rg_xalvakka_shield        = "|c75E6DAShield|r: %s"
M.rg_xalvakka_run_in        = "|cffdd00RUN IN|r: %.1f%%"
M.rg_xalvakka_on_blob       = "|c66ff66ON BLOB|r  -  stand still!"

-- ── Dreadsail Reef (DSR) ── Lylanar ─────────────────────────────────────────

M.dsr_lylanar_dodge_cleave  = "Dodge! (Cleave)"
-- Ember/bubble suffix: pick singular vs plural in Lua based on stack count
M.dsr_lylanar_ember_suffix  = "  -  %d stack"
M.dsr_lylanar_ember_suffix_p = "  -  %d stacks"
M.dsr_lylanar_drop          = "|cff0000DROP!|r"
M.dsr_lylanar_fire_fragility = "|cFF5733Fire Fragility|r: %.0fs"
M.dsr_lylanar_ice_fragility = "|c99CCffIce Fragility|r: %.0fs"
M.dsr_lylanar_need_fire_dome = "|cFF5733Need Fire Dome|r: %.1fs"
M.dsr_lylanar_need_ice_dome = "|c99CCffNeed Ice Dome|r: %.1fs"
M.dsr_lylanar_axe           = "|cFF5733Axe|r: %.0fs"
M.dsr_lylanar_axe_inc       = "|cFF5733Axe|r: |cff0000INC|r"
M.dsr_lylanar_sword         = "  |c99CCffSword|r: %.0fs"
M.dsr_lylanar_imm_blister   = "|cFF5733Imminent Blister|r (%s): %.0fs"
M.dsr_lylanar_imm_chill     = "|c99CCffImminent Chill|r (%s): %.0fs"

-- ── Dreadsail Reef ── ReefGuardian ──────────────────────────────────────────

M.dsr_reef_elec_cleansed    = "|cFFD666\xe2\x9a\xa1 CLEANSED|r"   -- ⚡ CLEANSED
M.dsr_reef_poison_cleansed  = "|c66CC66\xe2\x98\xa3 CLEANSED|r"   -- ☣ CLEANSED
-- Stack labels: color prefix and "|r" suffix are built in Lua (urgency-dependent)
M.dsr_reef_elec_label       = "\xe2\x9a\xa1 "                       -- "⚡ "
M.dsr_reef_poison_label     = "\xe2\x98\xa3 "                       -- "☣ "
M.dsr_reef_stack            = "%d stack"                             -- singular
M.dsr_reef_stack_p          = "%d stacks"                           -- plural
M.dsr_reef_warn             = " |cff0000!|r"
M.dsr_reef_reef_timer       = "Reef %d: %.0fs"                     -- col wrapped in Lua
M.dsr_reef_acidic_vuln      = "|cff8800Acidic Vuln|r: %.1fs"

-- ── Dreadsail Reef ── Taleria ────────────────────────────────────────────────

M.dsr_taleria_dodge_maelstrom = "|cff0000DODGE!|r (Maelstrom ends)"
M.dsr_taleria_heal          = "|c66CC66HEAL!|r (%.0fs)"
M.dsr_taleria_maelstrom     = "|c66CC66Maelstrom|r: %.0fs"
M.dsr_taleria_maelstrom_inc = "|c66CC66Maelstrom|r: |cff0000INC|r"
M.dsr_taleria_behemoth_slam = "|cFF8800Behemoth SLAM|r: %.0fs!"
M.dsr_taleria_behemoth      = "|cFF8800Behemoth|r: %.0fs"
M.dsr_taleria_behemoth_inc  = "|cFF8800Behemoth|r: |cff0000INC|r"
M.dsr_taleria_storm_cw      = "|cD672F7Storm CW ->|r  -  %.0fs"
M.dsr_taleria_storm_ccw     = "|cD672F7Storm CCW <-|r  -  %.0fs"
-- Bridge: label abbreviations + next threshold (%% → single % via string.format)
M.dsr_taleria_bridge_label_1 = "|c22CC22G|r"
M.dsr_taleria_bridge_label_2 = "|cDDCC00Y|r"
M.dsr_taleria_bridge_label_3 = "|c8822DDPu|r"
M.dsr_taleria_next_bridge   = "Next bridge: |cffdd00%.1f%%|r"
-- Alerts
M.dsr_taleria_maelstrom_alert = "|c66CC66Maelstrom  -  HEAL!|r (6 s)"
M.dsr_taleria_portal_green  = "|c22CC22Green portal open|r  -  60 s!"
M.dsr_taleria_portal_yellow = "|cDDCC00Yellow portal open|r  -  60 s!"
M.dsr_taleria_portal_purple = "|c8822DDPurple portal open|r  -  60 s!"

-- ── Kyne's Aegis (KA) ── Yandir ─────────────────────────────────────────────
-- KA uses location-based detection; no boss name keys needed.

M.ka_yandir_dodge_poison    = "Dodge! (Poison Totem)"
M.ka_yandir_block_gargoyle  = "Block! (Gargoyle Totem)"
M.ka_yandir_casts_healing   = "Casts Healing!"
M.ka_yandir_jump_block      = "(Jump) Block!!"
M.ka_yandir_dodge_sea_adder = "Dodge! (Sea Adder)"
-- Info-line labels (intentional trailing spaces for column alignment)
M.ka_yandir_totem_label     = "Totem:   "
M.ka_yandir_gryphon_label   = "Gryphon: "
M.ka_yandir_gryphon_skip    = "|c55aa55Skip!|r"
M.ka_yandir_gryphon_early   = " (%s early)"
M.ka_yandir_gryphon_fail    = "|ccc4444Fail @ %.0f%%|r"

-- ── Kyne's Aegis ── Vrol ─────────────────────────────────────────────────────

M.ka_vrol_kill_conjurer     = "KILL Conjurer!"
M.ka_vrol_kill_conjurer_20s = "KILL Conjurer! (20 s)"
M.ka_vrol_dodge_fog         = "Dodge/Move! (Fog)"
M.ka_vrol_kill_harpoon      = "Kill Harpoon! (~16 s)"
M.ka_vrol_harpoon_action    = "Harpoon!"
M.ka_vrol_interrupt_apoth   = "Interrupt Apothecary!"
M.ka_vrol_portal_ok         = "Portal OK!"
M.ka_vrol_portal_failed     = "Portal Failed!"
-- Info labels (intentional trailing spaces for alignment)
M.ka_vrol_fog_clears        = "Fog clears:"   -- col prefix and |r suffix added in Lua
M.ka_vrol_next_fog          = "Next fog: "
M.ka_vrol_conduit           = "Conduit: "
M.ka_vrol_portal_label      = "Portal:  "

-- ── Kyne's Aegis ── Falgravn ─────────────────────────────────────────────────

-- Info labels with %s for the timer-or-fallback string
M.ka_falgravn_instability   = "Instability: %s"
M.ka_falgravn_blood_ball    = "Blood Ball: %s"
M.ka_falgravn_open_gates    = "Open Gates: %s"
M.ka_falgravn_torturer_tp   = "Torturer TP: %s"
M.ka_falgravn_hm_suffix     = " [HM: ON]"
-- Action strings
M.ka_falgravn_interrupt_inf = "Interrupt Infuser!"
M.ka_falgravn_inf_buff      = "Infuser Buff passed!"
M.ka_falgravn_move          = "Move!"
M.ka_falgravn_block_cast    = "Block Cast!"
M.ka_falgravn_dodge         = "DODGE!"
M.ka_falgravn_block_fountain = "Block Blood Fountain!"
M.ka_falgravn_open_gates_action = "Open the Gates!"
M.ka_falgravn_kill_torturer = "KILL Torturer!"
M.ka_falgravn_torturer_down = "Torturer Comes Down!"
M.ka_falgravn_dodge_torturer = "DODGE! (Torturer LA)"
M.ka_falgravn_torturer_la_label = "Torturer LA's"
M.ka_falgravn_kill_prison   = "KILL PRISON!"

-- ── Asylum Sanctorium (AS) ── OlmsEncounter ─────────────────────────────────

M.as_olms_kite_storm        = "Kite! (Storm the Heavens)"
M.as_olms_steam_breath      = "Steam Breath! Move!"
M.as_olms_charges           = "Charges!"
M.as_olms_trial_by_fire     = "Trial by Fire!"
M.as_olms_jump_dodge        = "Jump! Dodge!"
M.as_olms_blast_target      = "Blast! \xe2\x86\x92 %s"      -- "Blast! → %s"
M.as_olms_blast_bar         = "Blast \xe2\x86\x92 %s"       -- CA bar label (no !)
M.as_olms_interrupt_llothis = "Interrupt Llothis!"
M.as_olms_strike_target     = "Strike! \xe2\x86\x92 %s"     -- "Strike! → %s"
M.as_olms_strike_bar        = "Strike \xe2\x86\x92 %s"      -- CA bar label (no !)
M.as_olms_kill_protector    = "Kill the Protector!"
M.as_olms_shield_down       = "Shield down!"
M.as_olms_protector_active  = "|cffcc00[!] PROTECTOR ACTIVE|r"
-- Info labels (intentional trailing spaces for alignment)
M.as_olms_storm_label       = "Storm:   "
M.as_olms_steam_label       = "Steam:   "
M.as_olms_charges_label     = "Charges: "
M.as_olms_fire_label        = "Fire:    "
M.as_olms_llothis_dormant   = "Llothis: DORMANT"
M.as_olms_blast_label       = "Blast:   "
M.as_olms_bolts_label       = "Bolts:   "
M.as_olms_felms_dormant     = "Felms:   DORMANT"
M.as_olms_strike_label      = "Strike:  "
M.as_olms_jump_at           = "Jump at %.0f%%!"

-- ── Cloudrest (CR) ── ZmajaEncounter ────────────────────────────────────────

M.cr_zmaja_flare_target     = "Flare \xe2\x86\x92 %s"       -- "Flare → %s"
M.cr_zmaja_frost_drop_6s    = "Frost! Drop in 6s"
M.cr_zmaja_frost_target     = "Frost -> %s"
M.cr_zmaja_drop_frost       = "Drop frost now!"
M.cr_zmaja_chilling_comet   = "Chilling Comet! Move!"
M.cr_zmaja_re_engaged       = "Z'Maja re-engaged -- portal counter reset"
M.cr_zmaja_kite_darkness    = "Kite! Crushing Darkness"
M.cr_zmaja_siroria_ha       = "Siroria HA! (%s)"
M.cr_zmaja_siroria_jump     = "Siroria jumping!"
M.cr_zmaja_siroria_banner   = "Siroria Banner!"
M.cr_zmaja_siroria_rooted   = "Rooted! (Siroria)"
M.cr_zmaja_relequen_ha      = "Relequen HA! (%s)"
M.cr_zmaja_relequen_jump    = "Relequen jumping!"
M.cr_zmaja_interrupt_rele   = "Interrupt Relequen!"
M.cr_zmaja_relequen_jolt    = "Relequen Jolt! Move!"
M.cr_zmaja_overload_inc     = "Overload incoming - bar swap!"
M.cr_zmaja_overload_you     = "Overload on you - swap now!"
M.cr_zmaja_galenwe_ha       = "Galenwe HA! (%s)"
M.cr_zmaja_galenwe_jump     = "Galenwe jumping!"
M.cr_zmaja_interrupt_gale   = "Interrupt Galenwe!"
M.cr_zmaja_galenwe_donut    = "Galenwe Donut! Out!"
M.cr_zmaja_spear_target     = "Spear \xe2\x86\x92 %s (%d)"  -- "Spear → %s (count)"
M.cr_zmaja_creeper_rooted   = "Rooted! (Creeper)"
M.cr_zmaja_shadow_realm     = "Shadow Realm - Group %d"
M.cr_zmaja_jumping          = "Z'Maja jumping!"
M.cr_zmaja_retreating       = "Z'Maja retreating to shadow!"
M.cr_zmaja_shadow_splash    = "Shadow Splash! Interrupt!"
M.cr_zmaja_baneful_mark     = "Baneful Mark! (execute)"
M.cr_zmaja_core_exposed     = "Core exposed!"
M.cr_zmaja_core_missed      = "Core missed!"
M.cr_zmaja_core_picked      = "Core picked up."
-- Info labels
M.cr_zmaja_portal_open      = "Portal open: %s"
M.cr_zmaja_next_portal      = "Next portal: "
M.cr_zmaja_execute_phase    = "!!! EXECUTE PHASE !!!"
M.cr_zmaja_shadow_group     = "Shadow Group %d"
M.cr_zmaja_spears           = "Spears: %d"
M.cr_zmaja_siro_timers      = "Siro: Jump %s  Bnr %s"
M.cr_zmaja_rele_timers      = "Rele: Jump %s  Bash %s"
M.cr_zmaja_gale_timers      = "Gale: Jump %s  Bash %s"

-- ── Sanity's Edge (SE) ── YaseylaEncounter ───────────────────────────────────

M.se_yaseyla_frost_bomb_you = "Frost Bomb on you! Drop it!"
M.se_yaseyla_frost_bomb_tgt = "Frost Bomb -> %s"
M.se_yaseyla_fire_bombs_tgt = "Fire Bombs -> %s"
M.se_yaseyla_chains         = "Chains!"
M.se_yaseyla_ignite         = "Ignite on you! Move!"
M.se_yaseyla_shrapnel_you   = "SHRAPNEL! Stack! (%d)"
M.se_yaseyla_shrapnel       = "Shrapnel! Stack!"
M.se_yaseyla_knife_blast    = "Knife Blast -> %s"
M.se_yaseyla_vengeful_strike = "Vengeful Strike! Dodge!"
M.se_yaseyla_portal         = "Portal! Vanton's Clarity"
M.se_yaseyla_enrage         = "ENRAGE! Seethe!"
M.se_yaseyla_headbutt       = "Headbutt -> %s! DODGE!"
M.se_yaseyla_overwhelming   = "Overwhelming Lightning on you!"
M.se_yaseyla_execute        = "Execute! (<26%%) Fire Bombs accelerate"
-- CA bar labels
M.se_yaseyla_fire_bombs_bar    = "Fire Bombs!"
M.se_yaseyla_knife_blast_bar   = "Knife Blast \xe2\x86\x92 %s"
M.se_yaseyla_charge_bar        = "Charge \xe2\x86\x92 %s"
-- CA alert popups
M.se_yaseyla_frost_bomb_alert  = "FROST BOMB - drop!"
M.se_yaseyla_deflect_alert     = "STACK!"
M.se_yaseyla_shrapnel_alert    = "SHRAPNEL - STACK!"
M.se_yaseyla_vengeful_alert    = "VENGEFUL STRIKE"
M.se_yaseyla_portal_alert      = "PORTAL - synergy!"
M.se_yaseyla_enrage_alert      = "ENRAGE!"
M.se_yaseyla_headbutt_alert    = "HEADBUTT - DODGE!"
M.se_yaseyla_ovw_lightning     = "OVW LIGHTNING"
M.se_yaseyla_portal_pct_alert  = "PORTAL PHASE ~%d%%"
-- HP milestone action strings
M.se_yaseyla_90pct          = "90%% - Wamasu + Archers incoming!"
M.se_yaseyla_80pct          = "80%% - Shrapnel incoming!"
M.se_yaseyla_70pct          = "70%% - Wamasu + Archers incoming!"
M.se_yaseyla_60pct          = "60%% - Portal phase!"
M.se_yaseyla_55pct          = "55%% - Shrapnel incoming!"
M.se_yaseyla_50pct          = "50%% - Wamasu + Archers incoming!"
M.se_yaseyla_35pct          = "35%% - Portal phase!"
M.se_yaseyla_30pct          = "30%% - Wamasu + Archers incoming!"
M.se_yaseyla_25pct          = "25%% - Shrapnel incoming!"
M.se_yaseyla_20pct          = "20%% - Wamasu + Archers + Shrapnel!"
M.se_yaseyla_10pct          = "10%% - Wamasu + Archers + Shrapnel!"
-- Info labels
M.se_yaseyla_fire_bombs_first  = "Fire Bombs: first ~7s"
M.se_yaseyla_fire_bombs_name   = "Fire Bombs"
M.se_yaseyla_bombs_exec_name   = "Bombs (exec)"
M.se_yaseyla_fire_bombs_label  = "%s: "    -- label with colon and space (%s = ability name)
M.se_yaseyla_frost_first       = "Frost: first ~17s"
M.se_yaseyla_frost_bomb_label  = "Frost Bomb: "
M.se_yaseyla_chains_label      = "Chains: "

-- ── Sanity's Edge ── AnsuulEncounter ─────────────────────────────────────────

M.se_ansuul_triplet_header  = "TRIPLET PHASE!"
M.se_ansuul_triplet_ended   = "Triplet ended!"
M.se_ansuul_calamity_stack  = "Calamity! Stack!"
M.se_ansuul_kite_wrack      = "Kite! Wrack incoming!"
M.se_ansuul_interrupt_exec  = "INTERRUPT! Execute!"
M.se_ansuul_sunburst        = "Sunburst on you! Dodge!"
M.se_ansuul_poisoned_mind   = "Poisoned Mind on you!"
M.se_ansuul_manic_phobia    = "Manic Phobia -> %s"
M.se_ansuul_interrupt_inf   = "INTERRUPT! Enraged Inferno!"
M.se_ansuul_enraged_flare   = "Enraged Flare -> %s"
M.se_ansuul_maze_header     = "Maze phase!"
M.se_ansuul_maze_cleared    = "Maze cleared! Calamity in ~9s"
-- CA bar labels
M.se_ansuul_sunburst_bar    = "SUNBURST"
M.se_ansuul_wrathstorm_bar  = "Wrathstorm!"
-- CA alert popups
M.se_ansuul_kite_alert      = "KITE!"
M.se_ansuul_manic_alert     = "MANIC PHOBIA - fear!"
M.se_ansuul_inferno_alert   = "INTERRUPT - Inferno!"
M.se_ansuul_flare_alert     = "ENRAGED FLARE"
-- Info strings
M.se_ansuul_maze_no_cal     = "Maze phase (no Calamity)"
M.se_ansuul_triplet_cal     = "TRIPLET - Calamity: %s"
M.se_ansuul_calamity_first  = "Calamity: first ~9s"
M.se_ansuul_calamity_label  = "Calamity: "
M.se_ansuul_split_phase     = "Split phase - equalize HP!"
M.se_ansuul_navigate_maze   = "Navigate the maze"
M.se_ansuul_now             = "now!"

-- ── Sanity's Edge ── ChimeraEncounter ────────────────────────────────────────

M.se_chimera_header         = "Chimera spawned!"
M.se_chimera_despawning     = "Chimera despawning..."
M.se_chimera_chain_lightning = "Chain Lightning!"
M.se_chimera_chain_circuit  = "Chain Circuit on you!"
M.se_chimera_arctic_shred   = "Arctic Shred -> %s"
M.se_chimera_lion_double    = "Lion Double Strike!"
M.se_chimera_gryphon_peck   = "Gryphon Peck!"
M.se_chimera_lightning_bolt = "Lightning Bolt -> %s"
M.se_chimera_wind_lance     = "Wind Lance! Move!"
-- CA alert popups
M.se_chimera_chain_lightning_alert = "CHAIN LIGHTNING"
M.se_chimera_chain_circuit_alert   = "CHAIN CIRCUIT"
M.se_chimera_wind_lance_alert      = "WIND LANCE"
-- CA bar labels
M.se_chimera_arctic_shred_bar = "Arctic Shred!"
M.se_chimera_lion_double_bar  = "Lion Double Strike!"
M.se_chimera_gryphon_peck_bar = "Gryphon Peck!"
M.se_chimera_bolt_bar         = "Bolt!"
-- Portal mantle labels
M.se_chimera_portal_wamasu  = "Wamasu Portal (Green)"
M.se_chimera_portal_lion    = "Lion Portal (Red)"
M.se_chimera_portal_gryphon = "Gryphon Portal (Blue)"
-- Info labels
M.se_chimera_despawn_label  = "Despawn: "
M.se_chimera_chain_label    = "Chain Ltng: "

-- ── Lucent Citadel (LC) ── LCCommon.lua ──────────────────────────────────────

M.lc_swap_hindered          = "SWAP! (Hindered)"
M.lc_hindered_alert         = "Tank swap \xe2\x80\x94 Hindered!"   -- "Tank swap — Hindered!"

-- ── Lucent Citadel ── RyelazEncounter ────────────────────────────────────────

M.lc_ryelaz_brilliant       = "Brilliant Annihilation!"
M.lc_ryelaz_bleak           = "Bleak Annihilation!"
M.lc_ryelaz_annihil_action  = "STACK \xe2\x80\x94 Annihilation!"  -- "STACK — Annihilation!"
M.lc_ryelaz_side_dark       = "|cFFAA44Ryelaz side (dark)|r"
M.lc_ryelaz_side_light      = "|c8888FFZilyesset side (light)|r"

-- ── Lucent Citadel ── DarielEncounter ────────────────────────────────────────

M.lc_dariel_throw_you       = "Powerful Throw on YOU!"
M.lc_dariel_throw_target    = "Powerful Throw \xe2\x86\x92 %s"  -- "→ %s"

-- ── Lucent Citadel ── OrphicEncounter ────────────────────────────────────────

M.lc_orphic_thunder_thrall       = "Thunder Thrall (Xoryn jump)"
M.lc_orphic_lightning_flood      = "Lightning Flood \xe2\x86\x92 %s"
M.lc_orphic_break_crystal        = "Break out of the crystal!"
M.lc_orphic_break_out_bar        = "BREAK OUT!"
M.lc_orphic_shield_throw         = "Shield Throw \xe2\x86\x92 %s"
M.lc_orphic_color_change         = "Color change! Switch mirror!"
M.lc_orphic_color_change_alert   = "Color Change!"
-- Info labels
M.lc_orphic_thrall_first    = "Thrall: first ~8s"
M.lc_orphic_thrall_label    = "Thrall: "
M.lc_orphic_flood_first     = "Flood:  first ~3s"
M.lc_orphic_flood_label     = "Flood:  "

-- ── Lucent Citadel ── XynizataEncounter ──────────────────────────────────────

M.lc_xynizata_interrupt_beam = "INTERRUPT \xe2\x80\x94 Piercing Beam!"
M.lc_xynizata_beam_bar       = "INTERRUPT \xe2\x80\x94 Beam!"
M.lc_xynizata_interrupt_vitr = "INTERRUPT \xe2\x80\x94 Vitrify!"
-- Info labels
M.lc_xynizata_beam_first    = "Beam: first ~14s"
M.lc_xynizata_beam_label    = "Beam: "
M.lc_xynizata_vitr_first    = "Vitrify: first ~9s"
M.lc_xynizata_vitr_label    = "Vitrify: "

-- ── Lucent Citadel ── XorynEncounter ─────────────────────────────────────────

M.lc_xoryn_accel_charge     = "Accelerating Charge \xe2\x86\x92 Chain Lightning!"
M.lc_xoryn_tempest          = "Tempest! MOVE from mirror line!"
M.lc_xoryn_atronach_aoe     = "Atronach AOE on YOU!"
M.lc_xoryn_lustrous_javelin = "Lustrous Javelin on you!"
M.lc_xoryn_arcane_knot      = "Arcane Knot \xe2\x80\x94 carry and pass!"
M.lc_xoryn_tether           = "Tether on you! Separate from partner!"
M.lc_xoryn_fluctuating      = "Fluctuating Current \xe2\x80\x94 hold, then drop!"
M.lc_xoryn_overloaded       = "Overloaded \xe2\x80\x94 DROP the current!"
-- CA bar labels
M.lc_xoryn_barrage_bar      = "Necrotic Barrage!"
M.lc_xoryn_tempest_bar      = "MOVE from line!"
M.lc_xoryn_atronach_bar     = "Atronach AOE \xe2\x86\x92 %s"
-- CA alert popups
M.lc_xoryn_chain_lightning  = "Chain Lightning incoming!"
M.lc_xoryn_javelin_alert    = "Javelin on YOU!"
M.lc_xoryn_knot_alert       = "Carry knot! Pass it!"
M.lc_xoryn_tether_alert     = "TETHER! Move away!"
M.lc_xoryn_current_alert    = "Hold current! Drop at edge!"
M.lc_xoryn_drop_alert       = "DROP current!"
-- Info
M.lc_xoryn_current          = "|c44CCFFCurrent: %.0fs|r"
M.lc_xoryn_drop_now         = "|cFF0000DROP NOW!|r"
M.lc_xoryn_carrying_knot    = "|cFFAA44Carrying Arcane Knot|r"

-- ── Ossein Cage (OC) ── OsseinCageCommon.lua ─────────────────────────────────

M.oc_carrion_label          = "Carrion: %d"        -- col prefix and |r suffix added in Lua
M.oc_carrion_alert          = "Carrion: %d stacks!"
M.oc_move_life_drain        = "Move! (Life Drain)"
M.oc_life_drain_alert       = "Life Drain"
M.oc_swap_hindered          = "SWAP! (Hindered)"
M.oc_hindered_swap_alert    = "Hindered  -  SWAP!"
M.oc_toxic_ire              = "Toxic Ire (you!)"
M.oc_toxic_ire_alert        = "Toxic Ire"
M.oc_detonate_soul          = "Detonate Soul (you!)"
M.oc_detonate_soul_bar      = "Detonate Soul"

-- ── Ossein Cage ── JynorahEncounter ──────────────────────────────────────────

M.oc_jynorah_titanic_leap   = "Titanic Leap!"
M.oc_jynorah_reflective     = "Reflective Scales  -  stop DPS!"
M.oc_jynorah_titanic_clash  = "Titanic Clash (~37.5s)"
M.oc_jynorah_clash_bar      = "TITANIC CLASH! DODGE!"
M.oc_jynorah_valneer_hit    = "Valneer hit!"
M.oc_jynorah_myrinax_hit    = "Myrinax hit!"
M.oc_jynorah_sparking_you   = "Sparking Curse  -  on YOU!"
M.oc_jynorah_sparking_tgt   = "Sparking Curse -> %s"
M.oc_jynorah_blazing_you    = "Blazing Curse  -  on YOU!"
M.oc_jynorah_blazing_tgt    = "Blazing Curse -> %s"
M.oc_jynorah_sparking_valneer = "Sparking Curse  -  swap to Valneer side!"
M.oc_jynorah_blazing_myrinax = "Blazing Curse  -  swap to Myrinax side!"
M.oc_jynorah_sparking_blue  = "Sparking Curse  -  BLUE!"
M.oc_jynorah_blazing_red    = "Blazing Curse  -  RED!"
M.oc_jynorah_curse_alert    = "Curse incoming!"
M.oc_jynorah_coldflame      = "Coldflame Surge on you! MOVE!"
M.oc_jynorah_brimstone      = "Brimstone Surge on you! MOVE!"
M.oc_jynorah_surge_alert    = "Surge on YOU!"
M.oc_jynorah_stomp_bar      = "DODGE  -  stomp!"
M.oc_jynorah_heat_ray       = "Heat Ray on you  -  move!"
M.oc_jynorah_heat_ray_alert = "Heat Ray on YOU!"
M.oc_jynorah_myrinax_breath = "Myrinax Breath on you! MOVE!"
M.oc_jynorah_valneer_breath = "Valneer Breath on you! MOVE!"
M.oc_jynorah_breath_alert   = "BREATH  -  MOVE!"
M.oc_jynorah_tail_slam_bar  = "Tail Slam \xe2\x86\x92 %s"
-- Info
M.oc_jynorah_clash_timer    = "|cFF4444CLASH: %s|r"
M.oc_jynorah_leap_first     = "Leap: first ~5s"
M.oc_jynorah_leap_label     = "Leap: "

-- ── Ossein Cage ── KazpianEncounter ──────────────────────────────────────────

M.oc_kazpian_chains         = "Chains: %s \xe2\x86\x92 %s"   -- "Chains: A → B"
M.oc_kazpian_chained_alert  = "CHAINED \xe2\x80\x94 pull apart!"
M.oc_kazpian_biting_blaze   = "Biting Blaze \xe2\x86\x92 %s"
M.oc_kazpian_vile_leap      = "Vile Leap!"
M.oc_kazpian_seething_leap  = "Seething Vile Leap!"
M.oc_kazpian_seething_bar   = "VILE LEAP (enrage)!"
M.oc_kazpian_agonizer       = "Agonizer Bombs!"
M.oc_kazpian_giant_sword_bar = "Giant Sword!"
M.oc_kazpian_dodge_cones    = "Dodge cones!"
M.oc_kazpian_dodge_spear    = "Dodge spear!"
M.oc_kazpian_storm_slam     = "Molag Kena Storm Slam \xe2\x80\x94 DODGE!"
M.oc_kazpian_storm_slam_bar = "DODGE \xe2\x80\x94 Storm Slam!"
M.oc_kazpian_storm_surge_bar = "Storm Surge!"
M.oc_kazpian_heavy_shock    = "Molag Kena Heavy Shock on you!"
M.oc_kazpian_heavy_shock_alert = "Heavy Shock on YOU!"
M.oc_kazpian_immolating     = "Immolating Sphere on you!"
M.oc_kazpian_immolating_alert = "Immolating Sphere!"
M.oc_kazpian_portal_phase   = "Portal phase %d!"
M.oc_kazpian_stricken       = "Stricken \xe2\x80\x94 tank mechanic!"
M.oc_kazpian_stricken_alert = "Stricken on YOU!"
M.oc_kazpian_firebomb       = "Firebomb \xe2\x80\x94 spread!"
M.oc_kazpian_firebomb_alert = "Firebomb on YOU!"
M.oc_kazpian_tort_chains    = "Tortuous Chains \xe2\x80\x94 run from Kazpian!"
M.oc_kazpian_channeler_down = "Channeler down! (%d dead)"
-- Info
M.oc_kazpian_portal_label   = "Portal: phase %d"
M.oc_kazpian_channelers     = "Channelers dead: %d"

-- ── Ossein Cage ── ShaperEncounter ───────────────────────────────────────────

M.oc_shaper_ogrim_you        = "Ogrim Charge on YOU! Move!"
M.oc_shaper_ogrim_tgt        = "Ogrim Charge \xe2\x86\x92 %s"
M.oc_shaper_ogrim_bar        = "MOVE \xe2\x80\x94 Ogrim Charge!"
M.oc_shaper_shielded_kill    = "Shaper of Flesh shielded \xe2\x80\x94 kill channelers!"
M.oc_shaper_shielded_alert   = "Shaper shielded \xe2\x80\x94 kill channelers!"
M.oc_shaper_vulnerable       = "Shaper vulnerable \xe2\x80\x94 BURN!"
M.oc_shaper_vulnerable_alert = "Shaper vulnerable!"
M.oc_shaper_channelers_shld  = "Channelers shielding Shaper \xe2\x80\x94 eliminate them!"
M.oc_shaper_shielded_info    = "|cAA44FFShaper: SHIELDED|r"

-- ── Cloudrest (CR) ── ZmajaEncounter ─────────────────────────────────────────

-- Z'Maja abilities
M.cr_zmaja_jump              = "Z'Maja jumping!"
M.cr_zmaja_hide_jump         = "Z'Maja retreating to shadow!"
M.cr_zmaja_crushing_dark     = "Kite! Crushing Darkness"
M.cr_zmaja_crushing_kite     = "KITE!"
M.cr_zmaja_shadow_splash     = "Shadow Splash! Interrupt!"
M.cr_zmaja_shadow_splash_bar = "INTERRUPT! Shadow Splash"
M.cr_zmaja_baneful_mark      = "Baneful Mark! (execute)"
M.cr_zmaja_baneful_alert     = "BANEFUL MARK"
M.cr_zmaja_portal_reset      = "Z'Maja re-engaged \xe2\x80\x94 portal counter reset"
-- Malevolent Cores
M.cr_zmaja_core_exposed      = "Core exposed!"
M.cr_zmaja_core_out_alert    = "Core out! Pick it up!"
M.cr_zmaja_core_out_ca       = "CORE OUT!"
M.cr_zmaja_core_missed       = "Core missed!"
M.cr_zmaja_core_missed_alert = "Core MISSED!"
M.cr_zmaja_core_missed_ca    = "CORE MISSED!"
M.cr_zmaja_core_picked       = "Core picked up."
-- Portal
M.cr_zmaja_shadow_realm      = "Shadow Realm \xe2\x80\x94 Group %d"
-- Siroria
M.cr_zmaja_siro_flare        = "Flare \xe2\x86\x92 %s"
M.cr_zmaja_siro_ha           = "Siroria HA! (%s)"
M.cr_zmaja_siro_ha_bar       = "Siro HA!"
M.cr_zmaja_siro_jump         = "Siroria jumping!"
M.cr_zmaja_siro_banner       = "Siroria Banner!"
M.cr_zmaja_siro_root         = "Rooted! (Siroria)"
-- Relequen
M.cr_zmaja_rele_ha           = "Relequen HA! (%s)"
M.cr_zmaja_rele_ha_bar       = "Rele HA!"
M.cr_zmaja_rele_jump         = "Relequen jumping!"
M.cr_zmaja_rele_interrupt    = "Interrupt Relequen!"
M.cr_zmaja_rele_jolt         = "Relequen Jolt! Move!"
M.cr_zmaja_rele_overload_in  = "Overload incoming \xe2\x80\x94 bar swap!"
M.cr_zmaja_rele_overload_you = "Overload on you \xe2\x80\x94 swap now!"
M.cr_zmaja_rele_bar_swap     = "BAR SWAP"
-- Galenwe
M.cr_zmaja_gale_ha           = "Galenwe HA! (%s)"
M.cr_zmaja_gale_ha_bar       = "Gale HA!"
M.cr_zmaja_gale_jump         = "Galenwe jumping!"
M.cr_zmaja_gale_interrupt    = "Interrupt Galenwe!"
M.cr_zmaja_gale_donut        = "Galenwe Donut! Out!"
M.cr_zmaja_gale_frost_you    = "Frost! Drop in 6s"
M.cr_zmaja_gale_frost_alert  = "FROST \xe2\x80\x94 drop in 6s"
M.cr_zmaja_gale_frost_tgt    = "Frost \xe2\x86\x92 %s"
M.cr_zmaja_gale_drop_frost   = "Drop frost now!"
M.cr_zmaja_gale_drop_alert   = "DROP FROST!"
M.cr_zmaja_gale_comet        = "Chilling Comet! Move!"
M.cr_zmaja_gale_comet_alert  = "COMET \xe2\x80\x94 move!"
-- Environment
M.cr_zmaja_creeper_root      = "Rooted! (Creeper)"
M.cr_zmaja_olorime_spear     = "Spear \xe2\x86\x92 %s (%d)"
-- Info labels
M.cr_zmaja_portal_open_label = "Portal open: "
M.cr_zmaja_portal_closing    = "closing"
M.cr_zmaja_portal_next_label = "Next portal: "
M.cr_zmaja_execute_phase     = "!!! EXECUTE PHASE !!!"
M.cr_zmaja_shadow_group      = "Shadow Group %d"
M.cr_zmaja_spears_label      = "Spears: %d"
M.cr_zmaja_siro_label        = "Siro: Jump %s  Bnr %s"
M.cr_zmaja_rele_label        = "Rele: Jump %s  Bash %s"
M.cr_zmaja_gale_label        = "Gale: Jump %s  Bash %s"
M.cr_zmaja_bash_due          = "INTERRUPT"

package.loaded["lang.en"] = M
return M
