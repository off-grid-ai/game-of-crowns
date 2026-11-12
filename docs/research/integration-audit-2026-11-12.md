# Integration audit: SSOT, SRP, DRY, SOLID, less hand code — 12 November 2026

Mac: "make sure that everything is properly integrated… SSOT, SRP, DRY, SOLID and OOP"; "make sure that there is less hand code". Read-only audit of HEAD by the supervisor's agent; each finding goes to its file owner (READY.md line 15). Before deleting an old path, the owner checks nothing is lost (goc-cpto: never lose functionality) and keeps the better of the two, not simply the default.

Below are 20 findings, worst first, plus the hand-code section you asked for. I only read HEAD. I edited nothing, ran nothing and committed nothing.

**Line count today:** GDScript in `realm/` without addons: **67,454** (`realm/scripts` alone: 59,781). Bridge JS/MJS: **13,536** (`bridge/*.js` alone: 12,601). Ruleset Lua `script.lua`: 973.

## Ranked findings
Format: finding | evidence | fix at the seam | thread | size

1. **Villagers have two daily-work systems, and the old one is still live code.** | `villagers.gd:1376-1505` `_choose_next` (hand-written role `match` at :1450) and `npc_mind.gd:1597` `villager_activities` (LimboAI). `town_life.gd:60` sets `LIMBO_ALL := true`, so the old path only runs with `--limbo=none`. | Delete `_choose_next` and its role tables. Every call (:597 :643 :676 :743 :1724) becomes "ask the mind". | town life | L
2. **The bridge sends hand-written Lua and goes around the `lua.js` port.** | Gold: `arcs.js:723`, `characters.js:680,1162,1173,1233`, `campaigns.js:152`, `court.js:57`. Transfer: `arcs.js:765`, `characters.js:568`. `create_unit`: `arcs.js:740`, `characters.js:614,1115`, `crown.js:135,174,183`, `garrison.js:25`. Raw `realm_host`/`realm_raid`: `campaigns.js:81`, `director.js:152,181`, `arcs.js:746,754`, `characters.js:598`. | Add `Lua.host`, `Lua.raid`, `Lua.levy` and `Lua.pay(a,b,n)` to `lua.js`. Make a lint rule that bans `edit.` and `realm_` outside `lua.js`. | freeciv | M
3. **The bridge has two meanings of "four seasons a year", and about 10 bare `% 4` checks.** | `characters.js:42` `SEASONS_PER_YEAR` and `treasury.js:47` `YEARLY`. Bare `4`: `season.js:48,55,216`, `treasury.js:108,123,129`, `characters.js:891`, `counsel.js:32`. | Keep one `calendar.js` constant and use `isYearEnd(turn)` everywhere. | freeciv | S
4. **The "crown player" lookup is written about 68 times.** | `houseFor(x).crown` appears 68 times. `director.js:23` already has `crownOf`. Copies in `campaigns.js:87,98,169` and `characters.js:1083,1105,1160`. `houseName` is defined 3 times: `intrigue.js:27`, `reign.js:120`, `situation.js:10`. | Make one world-query module (`crownOf`, `houseName`, `northTowns`) and import it everywhere. | freeciv | S
5. **The North boundary row is set in three places.** | `characters.js:43` `NORTH_Y=30`; `stakes.js:184` and `view.js:121` use a bare `c.y < 30`. | Put the row in data and use one query. | freeciv | S
6. **Soundscape guesses a town's buildings from its size.** | `soundscape.gd:397-399,471`: market at size ≥4, forge ≥3, tavern ≥3, church ≥4. The real plan lives in `towns.gd` and Freeciv. | Read the buildings from the awareness mirror. | town life (or one-store) | S
7. **Town walls have two systems.** | Kit panels or palisade in `towns.gd:1001-1002,1409,2862,2881`. Stone walls in `walls.gd` and `stone_wall.gd`, switched off by default (`walls.json "walls":"off"`). | Pick one owner and delete the other. | fire-siege | M
8. **Old/new switches keep both paths in the build.** | `soundscape.gd:154` with `sound_v2.gd` (v2 off by default). `map_look.gd:15-17` (v1 is the default). `army.gd:395` knight v1/v2. `motion.gd:69` v1 (38 `v2` branches). `court_panel.gd:27` `--court=old`. `town_life.gd:1441` square-agents (data says on). | For each pair: keep the default, delete the other path and its flag. | army layer, town life, one-store | M (each)
9. **`towns.gd` is a god object (3318 lines, 118 funcs).** | It holds: build queue and pacing (:51-240); plot/lane planner (:258-1000); bailey dressing plus a bailey crowd with roles (:388); fields and orchards (:1571, :2913); trades and smithy (`works.gd` already exists) (:1677); walls; banners (:2997-3125); hearth smoke (`hearths.gd` already exists) (:3125). | Split out TownBuilder (queue), TownPlanner (move to `town_plots.gd`), Fields, Banners. The bailey crowd goes to `castle_folk`. | fire-siege | L
10. **`villagers.gd` is a god object (2599 lines).** | It holds: registry (`who_at`, `who_is_home`), conversation (`open_talk`…`give_floor`), stall slots (:1018-1037), field work, places, and the legacy routine. | Split into TalkService, SlotClaims and Registry. | town life | L
11. **`scenes.gd` is a god object (1580 lines).** | It mixes battle, arrows, siege camp, storm and weather, refugees, convoy, feast, handover and captions. | One scene-kind class per row from `scene_kinds.gd`. | town life / fire-siege | L
12. **`army.gd` is a god object (1591 lines).** | It mixes regiment model, formation, march and deploy, banners, LOD meshes, ground clearing and lens. | Split into Formation, Banners and Visual LOD. | army layer | L
13. **`terrain.gd` is a god object (1571 lines).** | It mixes heightmap, rivers and fords, vegetation scatter, politics overlay, roads and A*, and seasons/snow. | Split into Vegetation, PoliticalOverlay and LandPaths. | one-store | M
14. **`server.js` hand-wires about 10 context objects, and they do not match.** | `server.js:442,527,534,600,638,705,749,766,806,943`. `campCtx` captures `world`/`meta` by value, but `sittingCtx` and `seasonCtx` use getters. The value capture can go stale (UNVERIFIED). Diplomacy (`setDiplomacy`/`setDipl` :191-240) also still lives in `server.js`. | Make one `ctx` with getters and move diplomacy to its own `diplomacy.js`. | freeciv | M
15. **`town_life.gd` dispatches 14 `dress_*` methods by string `call`.** | `town_scenes.gd:106` `tl.call("dress_"+dress)`. There are also 7 `match` chains in `town_scenes.gd` (:171 anchors, :266, :480, :512, :582, :987, :1168). | Make each dressing a resource or class registered by row; anchors become a data table. | town life | M
16. **Burnt-house state is keyed by the view's layout.** | `damage.js:5,62-69`: `kindled` stores "the view's home numbers", so the bridge fact depends on how `towns.gd` lays houses. A layout change silently remaps every burnt house (UNVERIFIED in practice). | Key by a stable home id from the town plan. | fire-siege | M
17. **The metres-to-units scale `S := 0.12` is copied in 14 files.** | `towns.gd:8`, `people.gd:6`, `town_life.gd:9`, `works.gd:14`, `walls.gd:17`, `stone_wall.gd:25`, `realistic.gd:6`, `interior.gd:11`, `forest.gd:17`, `countryside.gd:9`, `castle_life.gd:17`, `control.gd:28`, `horse.gd:16`, `terrain.gd:708`. | Make one `Units.M` constant. | one-store | S
18. **There are four copies of the knob loader and three of `_rgb`.** | Knobs: `herald.gd:9-29`, `juice.gd:8-29`, `camera_rig.gd:27-37`, and `fire.gd`/`look.gd` read JSON directly. `data.gd` already does this. `_rgb` copies: `house_tiers.gd:141`, `team_colour.gd:152`, `towns.gd:894`. | Use `Data.num`/`Data.value`, and add `Data.colour`. | one-store | S
19. **Stale `.uid` files.** | `realm/scripts/siege_storm.gd.uid`, `realm/tools/field_battle.gd.uid`, `realm/tools/bridge_probe.gd.uid` (their scripts are gone). | Delete them. | fire-siege / army layer | S
20. **There are 255 numeric `const` tunables in GDScript.** Many are not in data or `docs/TUNING.md`. | `grep '^const [A-Z_]+ := [0-9.]'` | Move gameplay knobs to data rows. | all | M

## Less hand code
Format: hand code | evidence | what replaces it | about how many lines it deletes

- **Legacy villager routine** | `villagers.gd:1376-1505` and the helpers it alone calls | LimboAI trees already in `npc_mind.gd` | about 300
- **Bridge Lua strings** | about 20 sites in finding 2 | `lua.js` builders; `realm_host`, `realm_raid` and a new `realm_levy` in `script.lua` | about 20 lines, plus a smaller attack surface
- **Hand lerp of the siege engine and crew** | `siege_camp.gd:262-280` (no Mover use) | `mover.gd`, or a Path3D/PathFollow3D driven by a Tween | about 25
- **Tween that moves walkers' bodies** | `castle_folk.gd:205-220` `_shuttle` writes `global_position` (no Mover use, against the one-Mover rule) | `mover.gd` routes | about 15
- **Cosine ease** | `cinematics.gd:342` `_ease` | `Tween.TRANS_SINE`/`EASE_IN_OUT`, or a Curve resource | about 3, plus its callers' manual stepping
- **Fire spread clock and queue** | `fire.gd:252-283` `_spread_tick` | A Timer or Tween chain per town (UNVERIFIED that it fits the rebuild case at :255) | about 30
- **Knob loaders** | `herald.gd:6-29`, `juice.gd:6-29`, `camera_rig.gd:27-37` | `data.gd` | about 50
- **Colour helpers** | three `_rgb` copies, plus `heraldry.colour`, `map_look.colour`, `works.colour` | one `Data.colour` | about 15
- **Old/new paths** | finding 8: `sound_v2.gd` 298 lines or the soundscape v1 branch; motion v1 branches; `court_panel` old path; map v1/v2; knight v1 | Keep one of each | several hundred (UNVERIFIED exact)
- **Buildings guessed from size** | `soundscape.gd:397-471` | Freeciv building list via the mirror | about 5, and the rule is no longer duplicated
- **Wall panels or stone walls** | `towns.gd:1378-1440,2881-2912` or `walls.gd` + `stone_wall.gd` (about 1150 lines together) | One wall owner | about 100 to 1000, depending on which survives
- **Stale uids** | 3 files | delete | 3 files

Already engine-backed, no action needed: `terrain.land_path`, `town_plots` and `army_ground` use AStar; `town_nav` uses NavigationServer2D. 20 files use MultiMesh.

`docs/GROUND_TRUTH.md` names the wall wear `/world cities[].damage` as the single owner. Finding 7's kit-panel walls ignore that fact (UNVERIFIED), so finding 7 is also an SSOT issue.
