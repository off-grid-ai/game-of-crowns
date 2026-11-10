# State architecture audit

Read-only audit, 10 Nov 2026. Repo state: main at 39eb9d8 plus uncommitted work (awareness.gd is new and not yet wired).

The target: Freeciv owns the simulation. The bridge owns one realm state. The view keeps one mirror (awareness.gd, filled only from /world). Every agent decision runs on LimboAI.

Where we are today: Freeciv's facts reach the bridge by two routes that disagree for up to a turn. The bridge keeps its realm in about 15 files plus about 20 in-memory variables, and some of those are lost on a restart. The view has no mirror yet. Six or more scripts each read /world for themselves. Only battles and sieges run on LimboAI. Townsfolk use LimboAI only for films (`--limbo=`).

---

## The 5 worst duplications (ranked by what the player would see)

### 1. A truce lives in three places, and Freeciv often never hears of it
- **Court, per lord:** `court.truces["c1:c7"]`, saved in court.json (characters.js:98, 168). It is set by a court ruling (characters.js:1046, 8 turns), a story effect (characters.js:928, 8×n turns) and an arc beat (arcs.js:756, 4×n turns).
- **Court, per house:** `court.truces["h:2:5"]`, 16 turns (server.js:2040, 2043). Only `keepTruce` sets this (the peace decree and the council's peace).
- **Freeciv's diplstate:** set by `ceasefire()`, which saves, edits and reloads (server.js:168-200). When no court is sitting it waits in `meta.pendingCease` (server.js:2037-2038) and runs at the next sitting (server.js:1132).
- **How they disagree:**
  - A truce from a court ruling or a story never reaches Freeciv. Freeciv's AI keeps fighting.
  - /world hides that war as a "truce" (server.js:2298, 2312). The houses panel shows peace while battle scenes play between those two houses.
  - `goalNow()` counts raw Freeciv wars and ignores truces (server.js:1611). The top bar says "2 are at war with each other" while the houses panel shows none. The win can't be reached, and the player can't see why.
  - The two timers differ: a court truce lasts 8 turns, Freeciv's ceasefire 16 (characters.js:1046 vs server.js:168).
  - A story's war deletes the lord truce but not the house truce (characters.js:951, arcs.js:753).
- **Fix:** keep one truce record, in the bridge. Every path that makes a truce goes through `keepTruce` and Freeciv. /world and `goalNow` read the same `stilled()`.

### 2. The town's mood is decided in five places
- town_life.gd:52-83 reads `famine`, `disorder` and `celebrating` itself. It lights the bonfire and revels when `celebrating` is true even if the town is starving (line 81).
- villagers.gd:564-572 `_town_mood()` puts disorder first, then famine, then feast.
- villagers.gd:719-721: the bridge's plan for each villager wins over the mood. But the bridge's `rulePlan` knows only plague and fear (minds.js:530-540). It doesn't know riot or feast. In a town in disorder, town_life shows smoke and an angry crowd while every villager with a plan walks to the fields.
- npc_mind.gd:600-605 `MoodIs` reads the blackboard if awareness has set one up. Otherwise it falls back to villagers.gd.
- awareness.gd:90 writes its own mood. It isn't instantiated anywhere yet, so the fallback always runs.
- villagers.gd:1361 `_witness` reads the same three flags a sixth time to tell the bridge what people saw.
- The bridge's own minds take famine and plague from the save (server.js:151-154).
- **Fix:** the bridge sends one `mood` per city in /world, and awareness.gd is the only reader in the view. The bridge's plans take that mood into account.

### 3. Scenes and favour effects live only in bridge memory, and leak between realms
- `scenes` (server.js:82, 112-115) keeps 120 entries and /world serves those under 90 s old (server.js:2342). `effects` (server.js:77, 1597) keeps 20, with `effectSeq` (server.js:78).
- `load()` (server.js:117-160) resets neither. Open another chronicle and the old realm's sacks, riders and favour toasts are served for up to 90 s, at the old map's coordinates.
- After a bridge restart `effectSeq` starts again at 0. The view's `_effect_seq` stays high (ui.gd:1173-1183). The next favour changes are dropped without a toast, which breaks "every change is seen".
- Scenes are lost on a restart, so a sack 30 s before it never plays. The scar in marks.json survives, so the ground burns with no story behind it.
- Five view readers each dedupe scenes with their own key, and there is no scene id:
  - scenes.gd:49 and awareness.gd:105 key on kind:x:y:turn:city.
  - director.gd:108 and minimap.gd:166 key on kind:x:y:turn.
  - main.gd:1497-1498 ranks news with its own lists.
  - Two scenes that differ only by city play twice but ping once.
- **Fix:** scenes and effects get a `seq` and are saved (like chronicle.jsonl). `load()` clears them. /world sends `scenes_since`. The view keeps one seen-set, in awareness.gd.

### 4. Two readings of Freeciv, up to a turn apart
- **The snapshot:** world.json from snapshot.lua (snapshot.lua:58-64), read 500 ms after the request (server.js:437-447). It gives towns, owners, size, buildings, units and gold.
- **The save:** `detail()` re-parses the newest autosave (server.js:228-239, savefile.js:82-112). It gives wars, allies, food, famine, disorder, building progress, unit hp and the territory `owners`.
- **How they disagree:**
  - After a conquest the town flies its new banner (snapshot), but the minimap and ground wash keep the old owner's colour (`owners` from the save) until the next autosave (minimap.gd:108, terrain.set_realm at main.gd:1166).
  - `detail()` reads only `auto` saves (server.js:230). The ceasefire save `realm-…-ceasefire-…` is skipped, so wars stay shown until Freeciv's next autosave.
  - `d.players[p.id]` assumes the save's player slot is the player id (server.js:2259, savefile.js:86).
- **The turn-start race:** on `turn`, timers fire at 1.5 s (snapshot), about 2.0 s (`stakes.tick`), 2.5 s (season), 3 s (minds) and 4 s (arcs) (server.js:603-610). `stakes.tick` can run on last turn's `world`.
- **Fix:** one Lua dump with everything the bridge uses (wars, food, disorder, owners). Run it on the turn event and chain the turn's work on its promise, not on timers.

### 5. Three loops decide whether a house rises against the King
- `meta.turning` gives a house an ultimatum before it may rise (server.js:1162-1205, `mayRise`). characters.js:469 respects it.
- The stakes.js usurper goes from none to rumour to march based only on favour under 25 (stakes.js:88-110). It never asks `mayRise`, so a pretender can march with no ultimatum ever sent.
- characters.js:469-582 adds a third loop: per-lord utility scores plus an LLM "rebel or endure" call.
- **Player sees:** the promised warning card can be skipped. A march comes with only a chronicle whisper.
- **Fix:** one rebellion state machine per house: calm, turning, ultimatum, rising, march. stakes and court both read it.

---

## 1. Every source of truth

### Freeciv (the simulation)
| State | Where | Who writes | How the bridge sees it |
|---|---|---|---|
| Turn, year, players, gold, government, cities (size, owner, capital, buildings), units (type, tile), roads | live server | Freeciv; the bridge via `lua cmd edit.*` (decrees, works, sieges, god.js) | snapshot.lua → state/world.json (snapshot.lua:22-64) |
| Terrain | live | world_setup*.lua; god.js scars (god.js:22) | snapshot.lua → map.json, written once (snapshot.lua:66-82) |
| Diplomacy, food, famine, disorder, celebrating, production, unit hp/orders, tile owners | save file | Freeciv autosave every turn (realm.serv:30-31); `ceasefire()` edits the save text (server.js:168-200) | `detail()` parses the save (server.js:228) |
| Events (city built, transferred, destroyed, size, unit lost, tech, civil war, turn) | stdout `EVENT {…}` | events.lua:11-46 | `onEvent` (server.js:594) |
| Turn timer | `set timeout` | the bridge's `timeoutNow()` (server.js:1052) | — |

### Bridge files (chronicles/<id>/)
| File | Holds | Writer |
|---|---|---|
| meta.json | about 40 keys (below) | `chron.saveMeta`, about 50 call sites in server.js |
| state/world.json | the Freeciv snapshot | snapshot.lua (the bridge only reads it) |
| state/map.json | terrain | snapshot.lua |
| state/chronicle.jsonl | the narrative log, seq'd | `writeRecord` (server.js:271-284) |
| state/history.jsonl | per-turn measures (peace, pop, food, treasury) | server.js:1793 |
| state/favour.json, favour-why.json, deeds.json, favour-past.json | house favour toward the crown, its reasons, per-house deeds, two-year trend | `saveFavour` (server.js:780-785) |
| state/scars.json | god-scarred tiles and their heal turn | server.js:599, 1730 |
| state/marks.json | battle, sack and razed marks | server.js:628, 2598 |
| state/stakes.json | usurper stage, the North, seat, wards | stakes.js:33 |
| state/minds.json | every mind (`folk:city:i` and named `cN`): mood, memories, bonds, beliefs, plan | minds.js:143-147, every 30 s |
| state/chatter.json | rumours, trails, travellers, `heard` | chatter.js:227-232 (debounced) |
| state/talks.json, folk-tales.json | conversation logs | server.js:478, 2929, 2974 |
| court.json | petitions, claims, truces, debts | characters.js:167-169 |
| mood.json | the King's standing orders ("decrees" in Court) | characters.js:145, 151 |
| characters/cN.json | each lord: traits, goals, loyalty, opinions, memories, spouse, alive | characters.js:109 |
| arcs.json | story clock, active and done arcs | arcs.js:186-188 |
| saves/*.sav.zst | Freeciv saves, including ceasefire edits | Freeciv; server.js:179 |
| ../records.json, names.json, stories/ | cross-reign records, renames, own stories | chronicles.js:66, names.js:42, server.js:3048 |

**meta.json keys** (server.js unless noted):
- **The reign:** id, name, title, scenario, seed, status, minutes, elapsedMs (saved every 30 s, server.js:2202), pace, options, optionsApplied, openingMood, openingMoodApplied, stage (test films), score, verdict, why, outcome, endedAt, epilogue, fate.
- **Court and Hand:** court {sitting, hand, heard, lastCall, push, sitOnReturn} (1054), counselNow {kinds, since} (986; not the in-memory `counselNow`), counselTold, mattersRest, answeredAt, decreeAt, relieved, interlude, interludes, councils, councilWar, choices, kindness.
- **Politics:** turning (ultimatums), alliances (sworn houses), campaigns (royal sieges), taken, pendingCease, united, works.
- **Aims:** ladder, ambitions, ambitionsFrom, lastAct.
- **The King's name:** ledger {sum, acts, favour, deeds, name} (ledger.js:23-25).
- **Money:** tithe.

### Bridge memory (server.js), lost on a restart unless noted
| Variable | Line | Lost on restart? | Also held in |
|---|---|---|---|
| `meta`, `world`, `chronicle`, `history`, `scars` | 55-61 | reloaded | files |
| `favour`, `favourWhy`, `deeds`, `favourPast`, `lastSeason` | 66-70, 1621-1623 | reloaded | favour files; `meta.ledger.favour` is a separate tally |
| `scenes` | 82 | **yes**; not reset on realm switch | — |
| `effects`, `effectSeq` | 77-78 | **yes**; not reset on realm switch | ui.gd `_effect_seq` |
| `decreesIssued` | 79, 2458 | yes. It is **dead**: only stakes.js's unused `epithet()` takes it (stakes.js:183-205) | meta.ledger.acts |
| `paused` | 64, 2403 | **yes**: a paused realm resumes after a restart (129) | meta.status |
| `sitting` (the realm is held) | 1050 | rebuilt from meta.court.sitting | meta.court.sitting (whether the court is open) |
| `away` | 1051 | yes | — |
| `counselNow` (the Hand's list) | 1049 | **yes**. It is computed as a side effect of GET /world (2342), so the court's docket depends on the view polling | — |
| `held` (grouped chronicle lines) | 250 | **yes**: lines waiting to be grouped are lost | — |
| `arrivals`, `savesSeen`, `detailCache`, `marks` cache, `tally` | 84, 163, 62, 661, 1621 | caches | — |
| `turnSeconds` | 63 | constant 40 | — |
| Court (characters.js), Arcs, Stakes, Minds, Chatter | 71-76 | loaded from files | minds.json is up to 30 s behind |

### View state (realm/scripts)
| Script | Holds | Fed by |
|---|---|---|
| bridge.gd:16 `world` | the last /world | /world every second |
| main.gd:26 `_houses`; `_seen`, `_news`, `_framed_*`, `_court_turn`, `_look_season` (46-57, 1517) | house map, news pick, held season | main reads /world and fans it out (main.gd:1148-1215) |
| towns.gd:11 `towns[id].data` | **a second copy of each city**. Refreshed only while the town's signature is unchanged (towns.gd:63); a queued rebuild keeps old data | world.cities |
| town_life.gd (in towns) | the "Life" node's signature (sig) per town | towns[id].data |
| villagers.gd:16, 42 `hour`, `_plans`, `_crowds`, `_was`, `_talks` | the day clock, the bridge's plans, per-person loop state | /minds/town every 4 s, towns.data |
| scenes.gd:19-21 `_seen`, `_sieges`, `_fighting` | played scenes, siege camps | world.scenes |
| director.gd `world`, `_last_key` | the current shot | main sets `director.world` |
| minimap.gd:13-16, 72-77 `_ids`, `_seats`, `_seen_ms`, `_pings` | territory, pings | world.owners, scenes, cities |
| terrain.gd, ruins.gd | owner tint, marks burn, ruins, season | main.gd:1166-1172 |
| units.gd:9, 71 `_figures`, `_heading` | a figure per unit | world.units |
| ui.gd `_purse`, `_effect_seq`, `_was_united`, `_last_act_told` | top bar, toasts | world |
| awareness.gd:20-22 `realm`, `_towns`, `_seen` | the intended mirror | **not instantiated yet** (only npc_mind.gd:292 looks for it) |

---

## 2. Every state machine and decision loop

| Loop | Where | Decides | Engine |
|---|---|---|---|
| Battle soldiers and knights | battle_ai.gd:79-90 | each man's state | **LimboAI HSM** |
| Siege assault parties | siege_ai.gd:65 | each man's state | **LimboAI HSM** |
| Townsfolk activities | npc_mind.gd:24-290, 595 | activity, steps, reactions | **LimboAI BT**, only in `LIMBO_TOWNS` (empty, town_life.gd:36) or `--limbo=` |
| Villager day | villagers.gd:719-800 | where to walk and what to do: the bridge plan first, else block × mood × role | hand-rolled |
| Town life | town_life.gd:50-90 | builders, drill, crowds, bonfire, unrest from city flags | hand-rolled (signature rebuild, not an HSM) |
| Scene staging | scenes.gd:39-99, `_victor` 102 | what plays, **and who won a battle (guessed in the view)** | hand-rolled |
| Director | director.gd:95-121 | which scene to watch next | hand-rolled scorer |
| News offer | main.gd:1497-1530 | which news Space jumps to | a second hand-rolled scorer |
| Person motion | motion.gd | clip transitions | Godot AnimationTree state machine |
| Player melee | combat.gd | ready, strike, block, stagger, dead | hand-rolled |
| Units glide | units.gd | figure movement | hand-rolled |
| Reign clock and hold | server.js:1052-1066, 2177-2204 | Freeciv timeout, elapsed time, the 5 s jobs (ladder, ambitions, council, interlude, lastAct) | hand-rolled |
| Court sitting and the Hand | server.js:1092-1228 (`courtSeason`, `callMatter`, `closeIfDone`) | when the court sits, what is called | hand-rolled |
| Counsel | server.js:796 `counsel()`, run inside GET /world | the King's matters | hand-rolled |
| Favour drift and tithe | server.js:1656-1716 | favour moves each season | hand-rolled |
| Ultimatums | server.js:1162-1205 | a house turns and sends an ultimatum | hand-rolled |
| Usurper and the North | stakes.js:84-130 | rumour, march, waves of the dead | hand-rolled |
| Lords' season | characters.js:369-600 | defect, serve, petition, rebel: utility scores + LLM `ask` | hand-rolled + LLM |
| Story arcs | arcs.js:166-360 | storylets, beats, effects | hand-rolled + LLM |
| Minds | minds.js:288 `tick`, 499 `plans`, 451/487 `thinkPlan` | mood drift, each commoner's hour plan | rules + LLM |
| Chatter | chatter.js:223 (60 s), 431 | rumours, travellers | hand-rolled + LLM |
| Royal siege | server.js:1494-1560 | **the bridge rolls the outcome** (`Math.random() < odds`, 1554) and transfers the city by Lua | hand-rolled; Freeciv doesn't simulate it |
| Decrees | crown.js | a decree's effects and cost | one-shot |
| God commands | god.js | Lua terrain and building edits | one-shot |

So: 3 of about 25 loops are on LimboAI, and one of those 3 is off by default.

---

## 3. Other duplication and drift

6. **A lord's memories live in two stores.** characters/cN.json `memories` (characters.js:109, `court.remember`) and minds.json named mind `memories` (minds.js:212-224). Arcs and chatter write to the mind (arcs.js:326, 802; chatter.js:61-64). Talking to a lord reads only the court record (server.js:451-468). A lord never mentions gossip he heard or a story beat he lived. The named mind also copies name, town, age and wants once (minds.js:217-221) and never refreshes them.
7. **The land's season vs the calendar.** main.gd:61-69 holds the ground's season for at least 120 s while a turn is 40 s. The top bar and awareness use `world.date.season` (ui.gd:2732, awareness.gd:69). The ground can show summer for 3 turns of "Winter of 302 AC".
8. **"At war" has three readings.**
   - Raw `atWarWith` (server.js:2259, 1611, 896, 2002).
   - `p.wars`, which hides truces and wars with loyal houses (server.js:2302).
   - `history.peace`, which hides calm pairs (server.js:1781-1789).
   - awareness.gd:91 reads `p.wars`.
9. **Allies twice.** `meta.alliances` (sworn to the crown, server.js:2293, 2500) and Freeciv's Alliance (`detail().allies`, server.js:2736). These are different meanings under one word.
10. **Pause.** `/pause` sets only the in-memory `paused` (server.js:2403). After a restart `paused = meta.status !== "running"` (129), so the realm runs again.
11. **Two things named counselNow.** In memory it is the Hand's list (1049). In meta it is the lesser matters told (986). The in-memory one is filled only by GET /world (2342). After a restart, `courtSeason` sees an empty docket until the view polls.
12. **Writes that lag.** minds.json waits up to 30 s (minds.js:138-147) and elapsedMs up to 30 s (2202). talks.json and chronicle.jsonl are written at once. A crash keeps the talk but loses the mind's memory of it.
13. **Two day clocks.** The bridge extrapolates a 240 s wall-clock day (minds.js:118, 490-494). The view loops dawn to dusk over 16 h (main.gd:1022-1026). This is safe only because villagers.gd:1292 sends `hour` on every ask.
14. **Favour defaults and thresholds.** The bridge treats a missing favour as 60 (server.js:787); awareness uses 100 (awareness.gd:89). Thresholds are scattered: 20, 25, 35, 50 and 60 in the bridge; 35 in npc_mind.gd:387 and 60 in awareness.gd:102.
15. **Who won a battle is decided in the view** (scenes.gd:102-115, from nearby units). The bridge knows the loser (server.js:617) but not the victor.
16. **Raw parsers outside the future mirror.** Each of these reads /world itself:
    - main.gd: about 25 loops over cities and players (1157-1834)
    - towns.gd:58, 1110
    - scenes.gd:42-105
    - director.gd:101, 222-249
    - minimap.gd:108-185
    - units.gd:19-81
    - roads.gd:21-66
    - ui.gd:2678-2773
    - terrain.set_realm and set_marks, ruins.show_marks (main.gd:1166-1168)
    - autoplay.gd and cinematics.gd (test-only)
17. **Dead code.** `decreesIssued` (server.js:79, 2458) is counted before validation and never read. stakes.js `epithet`/`epithetNear` (189-205) are no longer called: the name now comes from ledger.js.
18. **Realm switch in the view.** bridge.gd:355-363 clears `world`, but scenes.gd `_seen`, minimap `_seen_ms` and ui `_effect_seq` are kept. Together with #3, a switched realm can replay or suppress news.

---

## 4. Who owns what

```
                ┌──────────────────────────── FREECIV (simulation) ───────────────────────────┐
                │ live: cities, units, gold, roads ─ snapshot.lua ─► state/world.json          │
                │ save: wars, food, disorder, owners ─ autosave ─► saves/*.sav.zst             │
                │ signals ─ events.lua ─► stdout EVENT lines                                   │
                └──────▲──────────────────────────────▲──────────────────────────▲─────────────┘
          lua cmd edit.* (decrees, works,      ceasefire(): stop, edit save,     set timeout
          sieges, god, hosts)                  reload (server.js:168)            (hold/pause)
                       │                              │                          │
┌──────────────────────┴──────────── BRIDGE (server.js + modules) ───────────────┴─────────────┐
│ world (snapshot) + detail() (save)  ◄── two readings of Freeciv                               │
│ files: meta.json(~40 keys) favour* deeds marks scars history chronicle stakes court.json      │
│        characters/* minds.json chatter.json arcs.json talks.json mood.json                    │
│ memory only: scenes, effects, counselNow, held, paused, away, decreesIssued(dead)             │
│ loops: court/Hand · ultimatums · stakes usurper · lords' season · arcs · minds · chatter ·    │
│        favour drift · royal siege roll · 5 s reign jobs                                       │
└───────────────────────────────┬──────────────────────────────────────┬────────────────────────┘
                     GET /world (1 s)                      GET /minds/town (4 s), /chronicle, /court
                                │                                      │
┌───────────────────────────────▼──────────── VIEW (Godot) ────────────▼────────────────────────┐
│ bridge.gd.world ─► main._on_world fans out to:                                                │
│   towns(data copy)→town_life   scenes   units   roads   terrain/ruins   minimap   ui   director│
│   main (news ranker)           awareness.gd (built, NOT wired)                                │
│ villagers.gd: _plans (bridge) + _town_mood (towns.data) ─► hand-rolled day loop               │
│ npc_mind.gd (LimboAI BT, film towns only) ─ MoodIs → blackboard or villagers fallback         │
│ battle_ai / siege_ai (LimboAI HSM) ← scenes.gd stages them, guesses the victor                │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

```mermaid
flowchart LR
  FC[Freeciv live] -->|snapshot.lua| WJ[world.json]
  FCS[Freeciv autosave] -->|detail()| BR
  FC -->|events.lua EVENT| BR[Bridge server.js]
  WJ --> BR
  BR -->|lua cmd / ceasefire reload / timeout| FC
  BR <--> F[(meta, favour, court, characters, minds, chatter, arcs, stakes, marks, scars, chronicle, history)]
  BR -. memory only .- M[(scenes, effects, counselNow, held, paused)]
  BR -->|/world| V[bridge.gd world]
  BR -->|/minds/town| VL[villagers.gd]
  V --> MAIN[main.gd] --> TW[towns + town_life]
  MAIN --> SC[scenes.gd] --> BAI[battle_ai / siege_ai LimboAI]
  MAIN --> DIR[director] & MM[minimap] & UI[ui] & TR[terrain/ruins] & UN[units]
  TW --> VL --> NM[npc_mind LimboAI: film towns only]
  AW[awareness.gd: planned single mirror, not wired] -.-> NM
```

## To reach the target, in order
1. Give the bridge one Freeciv reading: one Lua dump per turn with wars, food, disorder and owners. Retire `detail()` for live facts.
2. Make one truce path through Freeciv (#1) and one rebellion state machine (#5).
3. Give scenes and effects a seq, save them, and clear them on load (#3).
4. Have the bridge send `mood` per city. Wire awareness.gd into main.gd `_on_world` and make it the only parser. town_life, villagers, minimap, director and scenes then read awareness.
5. Turn on LimboAI for every town (`LIMBO_TOWNS`). The villagers.gd day loop becomes the walking layer only. The bridge plan becomes a blackboard input, not an override.
6. Merge a lord's memories into one store, minds.json, with the court as the source of who he is (#6).
