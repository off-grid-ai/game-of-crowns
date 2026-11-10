# Principles audit: SSOT, SRP, DRY, SOLID

Read-only audit of `realm/scripts/*.gd` and `bridge/*.js`, 2026-11-10. Line numbers are from that
snapshot; two builders were editing at the time (main.gd moved ~10 lines during the audit), so search
by the quoted name if a line has shifted. Where state lives and the state machines are covered in
`state-architecture.md` (not yet written when this was done); this file is about code structure.

Owners: **NPC** = NPC builder (motion, people, npc_mind, town_life, villagers, scenes).
**B2** = Builder 2 (terrain, land, audio, UI). **Bridge** = shared.

## The 10 worst, ranked by (drift risk) x (how often the code changes)

| # | Principle | Where | Problem | Fix | Size | Owner |
|---|---|---|---|---|---|---|
| 1 | OCP, DRY | Decrees: `crown.js:7,82-329`, `server.js:543,924,1390-1430`, `ui.gd:2929,2945-3000` | One decree is defined in 8 places: cost (`DECREES`), price share (`SHARE`), once-a-year rules (`YEARLY`, `FAVOUR`, `yearlyKey`), kindness wear (`KIND`), effect text (`DOES`), the scene it plays (`decreeScenes`), the UI label with hard-coded effects ("+15", "every house +5", "600 men") and fallback prices, and `BUILT_AS` copied from `BUILDABLE`. A new decree touches 3 files and 8 tables | One `bridge/data/decrees.json` (cost, share, yearly, kind, effect words, scene) plus a handler map `{action: fn}` in crown.js; `/world.crown.decrees` carries label, effect line and wait; ui.gd just renders | M | Bridge, then B2 |
| 2 | SSOT, DRY | Favour bands: `ui.gd:2660,2874,2883`, `towns.gd:1093`, `awareness.gd:102`, `npc_mind.gd:392`, `server.js:803,819,875,901,959,1167,1285,2302,2732`, `stakes.js:90,121`, `characters.js:467,469,720`, `crown.js:130` | 25 / 35 / 60 hard-coded in 20+ places across both layers, plus one-offs (40, 45, 50, 70, 75). Change "loyal" from 35 and half the game still uses 35 | `bridge/favour.js` with `BANDS` and `band(f)`; `/world` sends `p.band`; the view never compares favour numbers | S | Bridge, then B2/NPC |
| 3 | SSOT, SRP | Two villager brains: `villagers.gd:706-833` `_choose_next` vs `npc_mind.gd:380-420,490-535` | Mood, block and role logic exist twice. And `npc_mind` reads the town's mood from two sources: `MoodIs` (`npc_mind.gd:458-466`) calls `villagers._town_mood` (towns.gd cache of the last sync), `weight()` reads the awareness blackboard `&"mood"`. They can disagree for a frame or a sync | `MoodIs` reads `bb.get_var(&"mood")`; then, behind `LIMBO_TOWNS`, retire `_choose_next`'s mood and role branches | L | NPC |
| 4 | DRY, SSOT | Town mood: `awareness.gd:90`, `villagers.gd:564`, `villagers.gd:1361` (`_witness`), `town_life.gd:54-102`, `main.gd:815` | Each script turns Freeciv's `disorder/famine/celebrating` flags into a mood with its own precedence and its own cache | Bridge sends `city.mood` (one precedence); awareness is the only reader; others read the town scope | S | Bridge, NPC |
| 5 | SRP | `bridge/server.js` (3185 lines) | Freeciv process, saves, reign switching, favour, counsel, court, campaigns, tithe, ladder, epilogue, ledger, and a 930-line HTTP handler (`server.js:2249-3180`, ~90 routes). `GET /world` also recomputes counsel and writes `counselNow` (`server.js:2342`) every poll | Split by responsibility (see SRP section); routes into a table; `/world` becomes a pure projection | L | Bridge |
| 6 | DRY, OCP | Scene kinds: `main.gd:1486-1487,1541-1553`, `director.gd:12-28`, `minimap.gd:81-84,163`, `awareness.gd:27-37`, `soundscape.gd:61-104`, `cinematics.gd:58-241`, `scenes.gd:55-98` | Seven tables of the same kinds, drifting: hostile is `sack/razed/battle/siege` in main, `sack/razed/battle/raid/struck` in awareness, and minimap marks every handover as war while main only a lord's. `KINGS_OWN` == `director.ROYAL` copied. The scene key is `kind:x:y:turn:city` in scenes/awareness but `kind:x:y:turn` in minimap | Bridge gives each scene an `id`, `tone` (loss/crown/plain) and `royal`; one `scene_kinds.gd` table (reach, sound, ping colour, caption, weight) read by all | M | Bridge, NPC, B2 |
| 7 | SRP, DIP | `realm/scripts/ui.gd` (3611 lines) | Top bar, house ladder, chronicle and ticker, town card and decree buttons, camera pad, minimap host, court and audience, ledger charts, digest, guide, epilogue and reign end, sigils. Parses bridge English back into data: `_FAVOUR_RE` (`ui.gd:2295,3331`) pulls "House X +15" out of hint text; `touches_crown` (`ui.gd:3081`) greps text for "Kingsmere" to colour a line red | Split into panels (see SRP); bridge sends structured `favour` and `crown: true` on entries | L | B2 |
| 8 | SRP | `realm/scripts/main.gd` (1981 lines) | Boot wiring (`_ready`, 380 lines), the test-shot harness (`_shot` used 170 times, `_frame_for_shot` 200 lines, `_parse_args` 106), news and Watch offers (`_on_staged`, `_offer`), sound view, day clock, overview | `shot_harness.gd`, `news.gd` (merge into director.gd), `boot.gd` wiring; main keeps the scene tree | L | B2 (scenes hookups with NPC) |
| 9 | DIP | 61 calls into another script's `_private` members | `control.gd` -> `villagers._people` x16; `battle_ai.gd` -> `scenes._stand` x10, `_ground`, `_die`, `_arrows`; `cinematics.gd` -> `main._shot` x9, `main._houses` x8; `director.gd`/`main.gd` -> `rig._goal_*` x20; `npc_mind.gd` -> `villagers._town_mood/_at/_near/_route_to/_field_work`; `main.gd` -> `ui._*_panel/_btn` | Public methods or signals per node; `rig.goal()`; a `CrowdApi` on villagers for minds | M | NPC, B2 |
| 10 | DRY | Bridge lookups: great houses, crown, seat | "Great houses" filtered inline 27 times with 4 definitions (`!wild && !crown`; plus `cities > 0`; plus `cities?.length !== 0`; ui.gd:1041 adds `units > 0`); `greatHouses()` exists (`server.js:1746`) but is used 7 times. Seat lookup written 18 ways, some fall back to any town, two to the title "Kingsmere" (`stakes.js:73`, `server.js:571`). `crownOf` means a player in `crown.js:33` and in `server.js:1846` | `bridge/realm.js`: `greatHouses(world, {fielded})`, `crownOf`, `seatOf(pid)`; `/world` sends `crownId` and `seatId` | S | Bridge |

## 1. SRP: god files and god functions

### File sizes (lines)
Over ~800: `ui.gd` 3611, `server.js` 3185, `main.gd` 1981, `scenes.gd` 1860, `title.gd` 1534,
`villagers.gd` 1521, `towns.gd` 1257, `terrain.gd` 1225, `characters.js` 1176, `arcs.js` 906,
`control.gd` 846, `battle_ai.gd` 843. Close: `countryside.gd` 770, `hero_view.gd` 757, `lore.gd` 730,
`town_life.gd` 678, `minds.js` 637, `people.gd` 622, `npc_mind.gd` 565, `claude.js` 562.
Totals: 59 .gd files, 37,444 lines with the 21 bridge files (8,884 of them bridge).

### Files over 800 lines, and their split

**ui.gd (3611).** Mixes: widgets (`_btn`, `_pill`, `_gauge` 232-413), top bar (`_build_top_bar` 500-690),
house ladder (`_rank_houses` 1039-1151, `show_house` 1330), town card and decrees (`show_town` 3015,
`_name_decrees` 2945, `_price`, `_forecast`), court (`set_court` 3161, `_show_audience` 3196-3400,
`_realm_matter`, `ruled_in_words`), ledger charts (`show_ledger` 1649, `_chart`, `_spark`), digest, guide
(`_guide_*` 2035-2099), reign end (`_epilogue` 2373, `_reign_end` 2487), folk and character form
(1429-1630), the world sync (`set_world` 2676-2920) and input. Split:
`ui/top_bar.gd`, `ui/houses_panel.gd`, `ui/town_card.gd` (decree buttons), `ui/court_panel.gd`,
`ui/ledger_panel.gd`, `ui/reign_end.gd`, `ui/guide.gd`, `ui/folk_panel.gd`; widgets go to `theme.gd`
(it already has `label/datum/title`). `ui.gd` stays as the CanvasLayer that owns them and routes signals.

**server.js (3185).** Mixes: Freeciv process and Lua channel (`startFreeciv` 292, `send` 288, `switchTo` 363),
records and saves (`record`, `writeRecord`, `newestSave`), favour and deeds (`shiftFavour` 1584,
`noteFavour`, `recordDeed`, `temper`), counsel (`counsel` 794-1030), court sittings and docket
(1049-1340), campaigns and sieges (`startCampaign` 1455 to `resolveCampaigns` 1537), tithe and works
(1628-1738), ledger and score (1761-1845), ambitions ladder (1867-1991), council and interlude
(1992-2101), epilogue and reign end (2102-2217), HTTP routing (2249-3180). Split:
`freeciv.js` (process, `send`, ceasefire reload), `favour.js` (bands, shift, temper, causes),
`counsel.js`, `court-sitting.js`, `campaigns.js`, `treasury.js` (tithe, works, prices), `ambitions.js`,
`reign.js` (goal, epilogue, end, score), `view.js` (the `/world` projection), `routes/*.js` (one file per
area: world, court, decree, lore, stories, test). One `realm` object holds the 28 module `let`s
(`server.js:55-82`, 350, 763, 1049-1051) and is passed in, so modules stop closing over globals.

**main.gd (1981).** Boot and wiring (`_ready` 74-453), graphics and UI scale (454-560), the shot harness
(`_parse_args` 560, `_ride_frames`, `_take_shot`, `_frame_for_shot` 1272-1471, `_stage_test_battle`,
`_profile_once`, `_cycle_step`, `_tour`), environment and sky (695-797), sound view (797-830), world sync
(`_on_world` 1141-1229), chronicle and seen-marks, news and offers (`_on_staged` 1522, `_offer`,
`_to_news`, `_edge_tick`), walking and control (1766-1817). Split: `shot_harness.gd` (everything reading
`_shot`), `news.gd` merged into `director.gd` (KINGS_OWN/WAR already mirror `director.ROYAL`),
`sky_clock.gd` (sky, night fill, `villagers.hour`), `boot.gd` (node creation and signal wiring).

**scenes.gd (1860).** Scene dispatch (`sync` 40-101), crowd helpers (`_stand`, `_route`, `_ground`), the
battle timeline (`_battle` 394-571 and helpers to 925), the siege (`_siege` 950-1072 and 1073-1422),
refugees, muster, rider, convoy, feast, handover (1423-1808), captions (1809-1860). Split:
`scenes/battle.gd` (with battle_ai), `scenes/siege.gd` (with siege_ai), `scenes/road.gd` (rider, convoy,
muster, ward), `scenes/town_events.gd` (feast, burn, refugees, handover), `scene_captions.gd`, and a
shared `scene_stage.gd` for `_stand/_ground/_die/_arrows` (the members battle_ai and siege_ai reach into).

**title.gd (1534).** Main menu, new-chronicle form (`show_new` 276-644, 369 lines), story beats
(`_fill_beats` 661-810), settings (963-1167), chronicle list, records, credits. Split:
`title/new_reign.gd`, `title/settings.gd`, `title/records.gd`; title.gd keeps the menu.

**villagers.gd (1521).** Spawning and LOD (51-172), movement and avoidance (`_step` 373-512), place
claiming (`_at`, `_claim` 589-700), the daily brain (`_choose_next` 706-833), gatherings and talk
(859-1060, 1411-1520), bridge plans over HTTP (`_ask_plans` 1280, own `BRIDGE` const at 41), witnesses
(1357). The target says movement only. Split: brain to `npc_mind.gd` (already there for LimboAI towns),
gatherings to `gatherings.gd`, bridge plans to `bridge.gd` (`minds_plans(town, cb)`), witnesses to
awareness. villagers.gd keeps spawn, `_step`, `_claim`, nav.

**towns.gd (1257).** Lot layout (`_real_lots` 263-367, `_street_fronts`, `_plots`), the town build
(`_build_town` 759-959, 201 lines), walls, fields, banners, hearth smoke, the life refresh. Split:
`town_layout.gd` (lots, plots, streets: pure functions), `town_dress.gd` (banners, smoke, hearths);
`_build_town` becomes layout -> place -> dress.

**terrain.gd (1225).** Heights and rivers (258-353), land and sea meshes (412-559), vegetation scatter
(560-808), realm colours and marks (809-997), paths and roads (1115-1225), seasons (123-194). Split:
`terrain_veg.gd`, `terrain_roads.gd` (`land_path`, `road_bow`, `smooth_road`, `along`).

**characters.js (1176).** Name deck, people and families, opinions, the season's AI (`bestMove`, `act`),
petitions (`petition` 641-822, 182 lines), dilemma deck play, the answer resolver (`answer` 1007-1148, a
37-branch `option ===` chain), truces, persistence. Split: `petitions.js` (make and answer, per-kind
handlers), `lords-ai.js` (bestMove, act), `characters.js` keeps the cast.

**arcs.js (906), control.gd (846), battle_ai.gd (843).** arcs.js mixes template loading/checking with
the runner; move `check`, `refsIn`, `readTemplates` to `arc-templates.js`. control.gd reaches into
villagers 18 times (see DIP); it is behind `Features.WALKING = false`, so leave it until v2.
battle_ai.gd is one concern; fine.

### Functions over ~120 lines
`server.js:2249` HTTP handler (~930) · `main.gd:74 _ready` (380) · `title.gd:276 show_new` (369) · `crown.js:82 decree` (~245, a
16-case switch) · `ui.gd:2676 set_world` (245) · `server.js:794 counsel` (237) · `ui.gd:3196
_show_audience` (205) · `towns.gd:759 _build_town` (201) · `main.gd:1272 _frame_for_shot` (200) ·
`ui.gd:500 _build_top_bar` (191) · `characters.js:641 petition` (182) · `scenes.gd:394 _battle` (178) ·
`hero_view.gd:438 _fill_panel` (160) · `autoplay.gd:69 _play` (157) · `title.gd:661 _fill_beats` (150) ·
`characters.js:1007 answer` (142) · `villagers.gd:373 _step` (140) · `ui.gd:2487 _reign_end` (132) ·
`ui.gd:1493 show_character_form` (132) · `villagers.gd:706 _choose_next` (127) · `scenes.gd:950 _siege`
(123) · `ui.gd:1199 _process` (120) · `hero_view.gd:598 _editor` (120) · `stakes.js:65 tick` (118) ·
`arcs.js:709 act` (115).
The worst for change risk: `counsel`, `decree`, `answer`, `set_world`, `_choose_next`. Each is a list of
independent cases in one body; each case should be its own function in a table (see OCP).

## 2. DRY: the same rule in more than one place

| Rule | Where | Drift today | Lives in |
|---|---|---|---|
| Favour bands | see top-10 #2 | `ui.gd:2660` names 60/35/25 Loyal/Content/Cold/Angry; `towns.gd:1093` banner height uses the same cuts; `npc_mind.gd:392` "sour" < 35; `characters.js:720` suspects < 45; `server.js:901` cold < 40 | `bridge/favour.js`, sent as `band` |
| Town mood | see top-10 #4 | `town_life.gd:93-102` lets disorder and famine both show; awareness gives riot priority; `villagers._witness` tracks all three as independent flags | bridge `city.mood` |
| Decree rules | see top-10 #1 | ui.gd says a feast is "+15"; `crown.js:213` gives 15 but `server.js:1433 temper` cuts it to 7 or 3 on a repeat; ui's levy/banners wait rule (`ui.gd:2989`) copies `server.js:1404` | `data/decrees.json` |
| Buildable names | `ui.gd:2929 BUILT_AS` = `crown.js:31 BUILDABLE` | identical now | crown.js, sent in `/world.crown` |
| "Temple" means a church | `main.gd:814` (`contains("Temple")`), `towns.gd:910`, `town_life.gd:325`, `soundscape.gd:349` (falls back to `size >= 4`) | sound's fallback disagrees with main's | a `features` set per city from the bridge |
| Tavern exists | `main.gd:815` `size >= 3`, `soundscape.gd:280` same fallback | same today | as above |
| Calendar | `ui.gd:3602 _season_of` re-implements `stakes.js:12-17 calendar` | same today; ui capitalises its own | bridge sends `when` text on entries |
| The north | `main.gd:815` `y < 25.0`; `server.js:2335`, `stakes.js:156` `y < 30`; `stakes.js:163` `y < 22` | three cuts for one region | `stakes.js` const, sent as `city.north` |
| Seasons per year | `characters.js:36`, `crown.js:29` (`>= 4`), `server.js:1090 HAND_YEAR`, `server.js:1401 YEARLY`, `server.js:2330` (`- 4`) | same today | `stakes.js` export |
| Scene key and kinds | see top-10 #6 | minimap key drops `city` | bridge `scene.id` |
| House colour | 33 `Color.from_string(house.color, ...)` sites in 17 files (`ui.gd:1056,1711,2666,2816`, `scenes.gd:399,400,978,979,1705,1754`, `lore.gd:164,400,697`, `towns.gd:770`, `town_life.gd:82` ...) | fallbacks `#888`, `#888888`, `#777`, `#ddd`, `#8a6d3b`, `#b08a4a`, `#7a2222`; lightening 0.2, 0.25, 0.3, 0.35, 0.4, 0.45 | `heraldry.gd`: `colour(house, tone)` with named tones (cloth, sigil, label) |
| Great houses, crown, seat | see top-10 #10 | four definitions of "great" | `bridge/realm.js` |
| Lua snippets | `edit.change_gold` inline 20 times (`crown.js` 5, `server.js` 6, `characters.js` 4, `arcs.js` 2, `god.js` 2); `transfer_city` 6 times | quoting and `-${n}` signs written by hand each time | `bridge/lua.js`: `gold(pid, n)`, `transfer(city, to)` (god.js already has `healLua`) |
| Time of day | `villagers.gd:321 _block` (night < 5.5 or >= 21.5); `npc_mind.gd:490 DAY` copies `villagers.gd:726`; `main.gd:1011` sets `villagers.night` from `sky3d.is_night()` and soundscape uses the sky | two definitions of night; `villagers.night` is set but never read in villagers.gd | `sky_clock.gd` owns hour and block; awareness carries `&"block"` |
| Animation LOD | `anim_lod.gd:11-12` NEAR 6, STRIDE 3; `villagers.gd:8-9` STEP_NEAR 10, STRIDE 4; `villagers.gd:92 _pause_unseen` toggles `anim.active` with the same SEEN_TO and `in_view` test anim_lod already runs | two cullers on one AnimationMixer | anim_lod.gd for animation; villagers only strides its own `_step` and should read anim_lod's constants |
| Clip lists | `villagers.gd:34 SOCIAL`, `:36 LISTEN`, `_choose_next` inline lists; `npc_mind.gd` post activities; `town_life.gd:190 DRILL_SWORD/BOW` vs `npc_mind.gd` "drill"/"bows"; `motion.gd:29 ONCE` | drill uses `SS_Slash_1/4, Spear_Thrust, SS_Attack_3` in town_life, 8 cuts in npc_mind | npc_mind post activities, as data (`data/activities.json` later) |
| LimboAI town switch | `villagers.gd:230` and `town_life.gd:51` each test `LIMBO_TOWNS or _limbo_args()` | same today | `features.gd`: `limbo_town(id)` |
| HTTP to the bridge | `bridge.gd` plus its own `HTTPRequest`s in `villagers.gd` (3) and `chatter.gd:100` | villagers' `_asking` de-dupe and error handling differ from bridge.gd | bridge.gd only |
| Crown currency | `ui.gd:1622 CROWNS := 100`; `server.js:1754 crowns()` | same today | bridge sends crowns, view never multiplies |

## 3. SSOT in code (not state placement)

- **Banners cooldown twice.** `crown.js:27 let bannersCalled` (module memory, lost on restart, never reset by
  `switchTo`) gates `bannersReady`; `server.js:1419 seasonsLeft("banners")` gates it again from
  `meta.decreeAt`. After a restart or a reign switch they disagree. Keep `meta.decreeAt` only.
- **Town mood from two snapshots.** `villagers._town_mood` reads `towns.towns[id].data` (towns.gd's copy
  from its last `sync`); awareness reads the live `/world`. `npc_mind` uses both (top-10 #3).
- **Who the crown is, found per script.** Bridge: `houseFor(p).crown` scans everywhere. View:
  `awareness.gd:79-83` loops players; `main.gd:1278`, `cinematics.gd:178` test `_houses[...].crown`;
  `main.gd:1278,1392,1845` and `roads.gd:79` find the capital by the title "Kingsmere". Bridge should send
  `crownId` and `seatId`; nobody matches a town by name.
- **Effects told twice.** The UI states a decree's effect from its own constants (`ui.gd:2971-2975`),
  not from what `crown.js` will do, and ignores `temper`. The counsel card has a third copy (`server.js:924 DOES`).
- **Loss and crown tone from text.** `ui.gd:3081` decides a chronicle line touches the crown by searching
  for "The Crown", "Kingsmere", "the King's"; `ui.gd:2295` recovers favour changes from hint text. The
  bridge has both facts as data when it writes the line.
- **Counsel recomputed on every poll.** `/world` calls `counsel()` and stores `counselNow` as a side effect
  (`server.js:2342`); `/court` and the docket read `counselNow`, so what the court sees depends on when the
  window last polled. Compute counsel once per turn in the season tick.
- **Scene "seen" sets.** `scenes.gd._seen`, `awareness.gd._seen`, `minimap.gd._seen_ms`, `main._news` each
  decide "is this scene new" with their own key. One `scene.id` from the bridge plus one seen-set in
  awareness, emitting a `scene_started(s)` signal the others subscribe to.

## 4. SOLID

### Open/closed: kind switches that grow with every feature
| Switch | Size | Make it |
|---|---|---|
| `crown.js:82-329` decree `switch (cmd.action)` | 16 cases | handler map + `data/decrees.json` (ledger.json is the house precedent: `ledger.js:12`) |
| `characters.js:1007-1148 answer` | 37 `option ===` branches over ~20 petition kinds | `PETITIONS[kind] = {make, answer: {option: fn}}`; the dilemma deck (`play`) is already data, move the rest to it |
| `server.js:2249-3180` routes | ~90 `if (url.pathname === ...)` | route table `{"GET /world": fn}` split per file |
| `server.js:543 decreeScenes`, `:566 rulingScene` | 7 cases | the `scene` field of each decree in data |
| `scenes.gd:55-98 sync` | 12 kinds | `const PLAY := {"sack": _on_sack, ...}` or one script per kind registered by name |
| `main.gd:771` (`_try_look`, 18 cases), `autoplay.gd:76` (19), `cinematics.gd:146,217` | film/test clips | data table of shots (they are test aids; low priority) |
| `npc_mind.gd:167 post_activities` (11 posts), `:387 weight` (if-chain on act names) | grows with every activity | `data/activities.json`: post -> sequences, weights by state |
| `villagers.gd:706-833 _choose_next` (match block, match role) | 5 blocks x 8 roles | delete once npc_mind runs every town |
| `main.gd:820 _sound_events KINDS`, `soundscape.gd:61-104` | per event | one `scene_kinds.gd`/event table shared with director and minimap |

### Dependency inversion
- **View reads raw Freeciv shapes.** `disorder`, `famine`, `celebrating`, `buildingKind`, `buildings`
  strings, `capital`, `owner` are read in ui, main, towns, town_life, villagers, awareness, minimap,
  scenes. The target says awareness is the only `/world` reader; today 11 scripts parse `world.cities`
  (`autoplay, awareness, cinematics, director, main, roads, minimap, scenes, towns, units, ui`), 4 parse
  `players`, 5 parse `scenes`, 10 read `crown`. Each `sync(world)` should read from awareness scopes or
  from typed fields the bridge already computed (mood, band, crownId, seatId, scene.id, tone).
- **Private reach-ins:** top-10 #9. Worst for drift: `npc_mind` -> `villagers._town_mood/_at/_near/_route_to`
  (the new brain bound to the old one's internals), `battle_ai`/`siege_ai` -> `scenes._stand/_ground/_die/_arrows/_people`
  (24 calls), `director`/`main`/`cinematics` -> `rig._goal_target/_goal_yaw/_goal_tilt/_goal_distance` (25 calls).
- **Service locator.** `Engine.set_meta("awareness", self)` (`awareness.gd:41`) is how minds find it;
  `Engine.set_meta("stage", ...)` is used as a profiler label. Acceptable as one autoload; make awareness an
  autoload and say so, rather than a meta key.
- **Bridge modules close over server.js globals** via `ctx` callbacks (`courtCtx`, `heardCtx`, `arcCtx`,
  `server.js:739,1055-1056`) built ad hoc per call. A single `realm` interface (favourOf, shiftFavour,
  send, world, turn) passed to Court, Arcs, Stakes, Chatter would replace five shapes of ctx.

### Interface segregation
- `villagers.gd` exposes `_crowds`, `_people`, `_nav`, `_talks` and they are used from `control.gd` (18),
  `main.gd`, `npc_mind.gd`. Give it a small surface: `who_at`, `who_on_screen`, `hold`, `struck`,
  `gatherings` (already public) plus `crowd(town)` for minds.
- `towns.towns` (the raw dict of town nodes and data) is read in 12 scripts (`villagers` 21, `control` 13,
  `main` 11, `map_labels` 5 ...). Expose `towns.node(id)`, `towns.data(id)`, `towns.near(p)`.
- `bridge.gd` is a 40-method facade every caller gets in full. Fine for now; split into `court_api`,
  `lore_api`, `people_api` only when it is touched.
- `main.gd` is the de facto global: cinematics reads `main._shot` and `main._houses`. `_houses` (house id
  -> house) belongs in awareness's realm scope.

## 5. Dead, switched-off and duplicate code

- **Battle and siege timelines behind `ClassDB.class_exists("LimboHSM")`** (`scenes.gd:478-571`,
  `1047-1050`). LimboAI is a hard dependency (npc_mind, awareness, battle_ai need it), so the tween
  fallback never runs: `_battle` 481-571, `_duel_step` 614, `_wait_step` 637, `_brace` 672, `_fall` 682,
  `_charge_flank` 831 and the `not minds` path in `_assault`, roughly 300 lines. Delete after a battle and
  a siege render confirm battle_ai and siege_ai cover them.
- **Stopgaps from 61f7f7d.** `town_life.gd:190-227 _drill_routine` is a timer-driven mini-brain that
  duplicates the npc_mind "drill"/"bows" posts; it runs whenever the town is off the switch (all towns:
  `LIMBO_TOWNS` is empty, `town_life.gd:35`). The siege's dead sweep (`scenes.gd:961-976`) polls metas
  on a 10 s Timer; it belongs in siege_ai's `dead` state (battle_ai already has `_lie_clear`). The riot
  spacing tweak lives in `_crowd`; `_mind_pair` (`town_life.gd:257`) is the replacement. Remove each when
  its town flips to LimboAI.
- **The old villager brain.** `villagers._choose_next` (706-833) plus `_mood_idle`, `_grieving`, the mood
  branches, stays live for every town while `LIMBO_TOWNS` is empty. It is the duplicate, not npc_mind.
- **Battle and siege HSMs** (`battle_ai.gd:79-160`, `siege_ai.gd:65`) are LimboHSMs, not BTs. They are
  current, not dead; npc_mind's trees cover townsfolk only. Note for the "every agent on LimboAI trees"
  target: these are LimboAI but HSM, and fine to keep.
- **`villagers.night`** (`villagers.gd:15`) is written by main.gd:1011 and never read.
- **`Features.WALKING = false`** gates `control.gd` (846), `combat.gd` (342), `interior.gd` (415),
  `horse.gd` (381), and branches in ui, title, intro, hero_view, main. Kept on purpose for v2; do not
  refactor it, but do not count it when sizing the live game.
- **`motion.gd`** (AnimationTree state machine) is current and is the only animation path. Not dead.
- **`bridge/records-tests-archived.json`, `bridge/tools/__pycache__/*.pyc`** are staged in git; the pyc
  should not be tracked.

## Consolidation order (never break a working feature)

Each step is one module, behind a switch or additive first, proven by the goc-tests way (bridge calls,
compile check, render) before the old path is removed.

1. **Bridge helpers, additive (S, Bridge).** `bridge/realm.js` (`greatHouses`, `crownOf`, `seatOf`),
   `bridge/favour.js` (`BANDS`, `band`), `bridge/lua.js` (`gold`, `transfer`). Replace call sites file by
   file; behaviour must not change, except where drift was a bug (decide each with Mac: "great" with or
   without towns).
2. **Richer `/world`, additive (S, Bridge).** Add `crownId`, `seatId`, `p.band`, `city.mood`,
   `city.north`, `scene.id`, `scene.tone`, `scene.royal`. Old fields stay. Move `counsel()` out of the
   GET into the season tick.
3. **Awareness reads the new fields (S, NPC).** Then `MoodIs` reads `&"mood"` from the blackboard. One
   test town on `--limbo=` to prove it.
4. **One scene table in the view (M, NPC + B2).** `scene_kinds.gd`; scenes, director, minimap, main
   news, soundscape read it; one seen-set keyed by `scene.id`. Swap one reader per commit.
5. **Decrees as data (M, Bridge then B2).** `data/decrees.json` + handler map in crown.js with the old
   switch kept as the fallback until every action has a handler; then `/world.crown.decrees` carries
   label, effect and wait; ui.gd stops hard-coding them. Drop `crown.js bannersCalled`.
6. **Petition answers as handlers (M, Bridge).** One kind per commit out of `characters.answer`.
7. **LimboAI for every town (L, NPC).** Flip `LIMBO_TOWNS` to all towns behind a `features.gd` switch;
   watch clips (3-6 s) of feast, riot, hunger, drill, market. Then delete `_choose_next`'s brain,
   `_drill_routine`, the siege sweep, and the scenes.gd tween fallback, one per commit.
8. **Public surfaces (M, NPC + B2).** `rig.goal()`, `scene_stage.gd`, villagers' crowd API, towns
   accessors; replace the 61 private reach-ins.
9. **Split server.js (L, Bridge).** Routes table first (pure move), then `freeciv.js`, `favour.js`,
   `counsel.js`, `campaigns.js`, `treasury.js`, `reign.js`, `view.js`. One module per commit, a bridge
   smoke (`/world`, `/court`, `/decree`) after each.
10. **Split ui.gd and main.gd (L, B2).** Panels out of ui.gd one at a time (court first: it changes
    most); `shot_harness.gd` and `news.gd` out of main.gd. Screenshots before and after each.
11. **House colour and LOD constants (S, B2 + NPC).** `heraldry.colour()`; villagers reads anim_lod's
    constants and stops toggling `anim.active`.
