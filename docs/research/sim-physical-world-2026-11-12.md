# The physical world: what to build on (12 November 2026)

Scope: terrain, rivers, navigation, crowds, wall breaches, fire, weather and seasons, armies of 600-6,000,
and keeping all of it true to the strategy sim through save and load. Research only; no code changed, no
Godot run. Companion to [independent-foundation-audit-2026-11-12.md](independent-foundation-audit-2026-11-12.md)
(engine and city-kit ranking); this file does not repeat it.

Tags: **[fact]** has a link or a file:line. **[judgement]** is my reading. **[estimate]** is a guess at effort.

## 1. The answer

1. The engine isn't the main mistake. No engine ships "a wall that cracks, then breaches, and armies path through
   the gap" or "a river nobody can wade". Total War, AoE IV and Manor Lords all built that layer themselves. [judgement]
2. The mistake is the missing layer under the pictures. Nobody owns "where can a man stand, and how does he get
   there". So each scene hand-rolls its own movement: six army systems, three river truths, one navmesh only in towns.
3. The 6,000-at-3-fps number isn't a clean measurement. The repo's own logs say 12-13 fps (batch 2) and 23-36 fps
   once frame capture was excluded (commit 9069e5f7). 6,000 x 5,296 triangles is the real cost. Impostors fix that on any engine.
4. Build on: Freeciv (or the sim that replaces it) as the only owner of walls, rivers, fire and season. Under it,
   one **world-grid layer**: a cost grid with flow fields for armies and a tiled navmesh for townsfolk. Every scene reads it.
5. If you switch engines for this layer, Unreal 5 gives the most free pieces (Mass, dynamic navmesh, Chaos caches,
   Niagara). It costs a C++ workflow and Mac caveats. Unity DOTS plus paid kits is second. Godot gives the least,
   but the gap is about 3-5 weeks of glue, not a rewrite. [judgement, estimate]
6. Fastest proof either way: the wall-breach and river-crossing test in section 4, run in Godot first, then in UE5 if it fails.

## 2. Need, best existing block, what stays ours

| Need | Best existing block (on today's Godot) | Same need on UE5 / Unity | What stays custom |
|---|---|---|---|
| Rules: wall wear, breach, burnt houses, season, weather, river crossings | **Freeciv** ruleset + bridge (already: bridge/damage.js, season.js, weather.js) | Same (the sim is engine-free) | River as a real barrier: today rivers *speed* units (`[road_river] move_cost = 2`, bridge/data/realmrules/terrain.ruleset:2340). A ford/bridge rule is ours. |
| Terrain + height | Terrain3D (in addons/) | UE Landscape + PCG; Unity Terrain / MicroSplat | Azgaar import (done) |
| Rivers drawn | Waterways (in addons/) | UE Water plugin; Unity: R.A.M. (paid) | Mapping one river source to tiles, nav and water |
| Walkable ground for people | NavigationServer (Recast bake, RVO avoidance) | UE dynamic navmesh with tile rebuild; Unity NavMesh + NavMeshObstacle carve | One realm-wide tiled navmesh, not one per town |
| Army movement, 600-6,000 | **Flow field on a cost grid**: gdmapf or Tilemap Flowfields (immature), or ~600 lines of our own over Godot's grid | UE Mass + MassNavigation; Unity Agents Navigation (ProjectDawn, paid) or Photon Quantum flow fields | Formation slots, regiment cohesion, gap queuing |
| Crowd avoidance | Godot RVO (in use, villagers.gd:349) | Mass avoidance; Agents Navigation | Tuning |
| Army rendering | godot_vat (in use) + **impostors at range** (needs a block or ~1 week) | UE: Mass + ISM + Nanite (Mac caveats); Unity: GPU Instancer / Rukhanka (paid) | House colour, banners (done) |
| Wall breach visuals | Jolt rubble (in use, stone_wall.gd) | UE Chaos Geometry Collection + Cache Manager (pre-baked) | Mapping wear 0..1 to cached damage states |
| Wall breach on the map | Navmesh obstacle off, rebake one tile | UE dynamic navmesh tile regen | The trigger (fact changes, rebake) |
| Fire spread | None found in Godot | UE: Niagara + community fire-spread kits; Unity: paid fire kits | Spread rule in the sim (cells, fuel, wind), so it saves |
| Fire/smoke look | GPUParticles3D + GDQuest fire shader (in use) | Niagara (Niagara Fluids partly unsupported on Mac) | Nothing |
| Weather, sky | Sky3D (in use) | UE Sky Atmosphere + Volumetric Clouds; Unity HDRP/Enviro (paid) | Nothing |
| Seasons look | Terrain3D snow blend (land3d.gd:216) | Material parameter collections | Nothing |
| Save/load | Freeciv savegame + bridge meta | Same | No view-only state that the player can see |

## 3. What each option gives pre-built

### Options

| Option | Supplies for the physical world | Last release | Licence / cost | Apple Silicon | Headless, agent-scriptable | Effort to reach our physical scope |
|---|---|---|---|---|---|---|
| **Godot 4.7** (today) | Recast navmesh bake, RVO agents and obstacles, Jolt (default since 4.6), GPU particles. No flow fields, no destruction, no crowd LOD, no fire spread. | 4.6 Jan 2026 [fact: [4.6 notes](https://godotengine.org/releases/4.6/)]; 4.7 docs live [fact: [4.7 NavigationServer](https://docs.godotengine.org/en/4.7/tutorials/navigation/navigation_using_navigationservers.html)] | MIT, free | Native | Yes, fully (`--headless`, `--check-only`) | 3-5 weeks of glue [estimate] |
| **Unreal 5.x** (5.8 seen in forum posts) | Mass entities + MassCrowd (crowd LOD, avoidance; City Sample), dynamic navmesh, Chaos Geometry Collections + cache replay, Niagara, PCG, Landscape, Water. | Active | Free; 5% over US$1M gross | Native since 5.2 [fact: [Epic](https://www.unrealengine.com/en-US/tech-blog/unreal-engine-5-2-brings-native-support-for-apple-silicon-and-other-developments-for-macos)]; "work in progress", TSR limits; some Niagara Fluids unsupported on Mac [fact: [forum](https://forums.unrealengine.com/t/what-is-up-with-niagara-fluids-not-working-on-a-mac/884774)] | Yes (commandlets, Python), but C++ builds are slow and heavy for agents | 2-4 months to port + 2-3 weeks for this layer [estimate] |
| **Unity 6** + DOTS | Entities 1.4 (exp) [fact: [docs](https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/whats-new.html)], NavMesh + carving obstacles. Crowds via **Agents Navigation** (ProjectDawn, paid; DOTS; avoidance) [fact: [docs](https://lukaschod.github.io/agents-navigation-docs/manual/index.html)]. No first-party DOTS navigation found. | Active | Personal free under thresholds; kits US$30-100 each | Native editor | Batch mode, C# scripts; package installs need automation | 2-4 months to port + 2 weeks for this layer [estimate] |
| **0 A.D. / Pyrogenesis** | Complete RTS: tile pathfinder + short-range unit pathfinder, formations, walls with gates and segments, terrain, water. No fire spread, no seasons. | R28 "Boiorix", 18 Feb 2026, first non-alpha [fact: [play0ad](https://play0ad.com/?p=5185)] | GPL-2 code, CC BY-SA art | Native M1 build (prior audit) | Yes (JS sim, autostart flags) | Most physical pieces free; medieval look and our sim are the work. 1-3 months to a slice [estimate] |
| **Recoil** (Beyond All Reason) | Proven 1,000s of units, flow-ish pathing, terrain deform, Lua gadgets, headless. | 2026-07-04, adds ARM64 [fact: [BAR](https://www.beyondallreason.info/microblogs/195), [GamingOnLinux](https://gamingonlinux.com/2026/07/impressive-grand-scale-rts-game-beyond-all-reason-gets-a-major-engine-upgrade-with-arm64-support)] | GPL | ARM64 new; macOS unconfirmed | Yes | Sci-fi bias; medieval town life is all ours. Reserve. |
| **Moddable shipped games** (Total War, Mount & Blade II, AoE II DE) | Everything physical, finished. | — | EULA: mods only, no standalone game | Mostly Windows | Poor | Only as references, not a foundation |

### How much of our physical-world work would have come free [judgement]

| Piece | Godot | UE5 | Unity DOTS + kits | 0 A.D. |
|---|---|---|---|---|
| Terrain, rivers drawn | ~80% (addons) | ~90% | ~70% (paid) | ~80% |
| Paths for townsfolk | ~70% | ~85% | ~80% | ~70% |
| Army movement 600-6,000 | ~20% | ~60% (Mass; flat-ground caveats per prior audit) | ~60% (paid) | ~80% |
| Wall breach (look + map) | ~40% | ~70% | ~40% | ~60% (segments exist; no visual crumble) |
| Fire spread | ~30% (look only) | ~50% | ~40% | ~10% |
| Weather + seasons | ~70% | ~75% | ~60% (paid) | ~20% |
| Sim consistency, save/load | 0% everywhere: it's the sim's job | 0% | 0% | ~70% (its sim owns everything) |

## 4. How shipped games do it at an RTS camera

| Game | Simulated | Faked | Source |
|---|---|---|---|
| Total War (Warhammer II) | Every projectile, line of sight, battle logic on its own threads, a frame or more ahead of the drawing | Units by LOD; hand-made street links and blocked ground; set animations on walls | [Game Developer, 2018](https://gamedeveloper.com/design/designing-i-total-war-warhammer-ii-i-to-handle-tons-of-units-and-massive-battles) [fact] |
| Total War sieges | Wall **segments** with their own hit points; damage carries from campaign (Three Kingdoms) | The crumble is a canned state per segment [judgement; no CA tech post found] | [Gamepressure guide](https://www.gamepressure.com/total-war-warhammer-2/siege/zca33e), [PC Gamer](https://www.pcgamer.com/total-war-warhammers-unloved-sieges-are-being-reworked-in-the-third-game) |
| Age of Empires IV | Flow fields + steering for groups | — | GDC 2022 "Pathing in Age of Empires" [fact: [GDC Vault](https://www.gdcvault.com/play/1027659/Pathing-in-Age-of-Empires)] |
| Supreme Commander 2 / Planetary Annihilation | Flow-field tiles for crowds | — | Emerson, "Crowd pathfinding and steering using flow field tiles", Game AI Pro [fact: [O'Reilly](https://www.oreilly.com/library/view/game-ai-pro/9781482254792/K23980_C017.xhtml)] |
| Manor Lords (UE4, solo dev) | Seasons, economy | **Pre-calculated** destruction, not live | [Epic interview](https://www.unrealengine.com/developer-interviews/solo-dev-makes-sophisticated-sim-manor-lords-using-unreal-engine) (403 to fetch; summary via search) |
| Far Cry 2 | Fire as a spreading front over grass and wood, driven by wind | Flame look is particles; a year of one programmer's time | [Game Developer interview](https://gamedeveloper.com/game-platforms/interview-how-i-far-cry-2-i-s-fire-fuels-spreads) [fact] |
| Banished | Seasons drive fields (dormant in winter), firewood, cold deaths | The land look is a tint and snow | [Shining Rock dev blog](https://shiningrocksoftware.com/2013-05-07-game-design-flux-or-how-i-learned-virtual-crop-rotation-isnt-fun/), [guide](https://gamepressure.com/banished/winter/z960a2) |
| Stronghold | Wall hit points per piece; breach opens a path | Rubble is a sprite/mesh swap | [judgement; no dev source found] |

The pattern [judgement]: the **rule** lives in a grid (hit points per wall segment, fuel per cell, season per turn).
The **look** is a canned or cached state picked from that rule. Live physics only for the near camera, and
it never decides anything. Our stone_wall.gd already follows this. The armies and rivers don't.

## 5. Our likely mistakes (from the repo)

1. **Six army systems, no shared movement layer.** units.gd (map figures lerp straight between tiles, units.gd:235),
   tools/army_spike.gd (VAT regiments), battle_ai.gd (LimboAI men), siege_ai.gd, siege_storm.gd (regiments walk
   straight to a goal, siege_storm.gd:151), combat.gd. Each moves men its own way. [fact] Total War and AoE put one
   pathing layer under all of them. [judgement]
2. **Battles have avoidance but no map.** battle_ai.gd:761-776 makes an RVO map with no navmesh. Men steer straight
   (battle_ai.gd:697-728) and avoid only each other. They don't see water, walls or houses. [fact]
3. **"Nobody stands on water" is a snap, not a rule.** town_nav.gd:372 pushes a man to dry ground after he steps there.
   He doesn't path round the river; he jumps the bank. [fact]
4. **Three river truths.** Azgaar's lines (rivers.gd:1-7, drawn by Waterways); Freeciv river tiles only for discharge
   ≥ 900 (bridge/tools/azgaar_world.py:16); and town navmeshes that cut out water. In Freeciv a river speeds
   movement (terrain.ruleset:2340) rather than blocking it. So "can't walk on a river" exists nowhere in the rules. [fact]
5. **Navmesh only per town.** town_nav.gd bakes one map per town and rebakes the whole town on a breach
   (town_nav.gd:38, 107). Outside towns there is no walkable map. The fix is a tiled realm navmesh, one tile rebuilt.
   Recast's TileCache was built for exactly this. [fact: [recast-navigation-js](https://www.npmjs.com/package/recast-navigation),
   [Mononen](https://digestingduck.blogspot.com/2010/08/handling-temporary-obstacles.html)]
6. **Perf diagnosed by eye, not by profile.** The 3 fps came from a capture (commit 9069e5f7). Clean runs read 12-13 fps
   (40f0cd9c) and 23-36 fps. The army is 32M of 142M triangles (9069e5f7); LOD was added later (018db615). No impostor
   stage, no shared crowd LOD. [fact] The fix is impostors past ~d20, not an engine swap. [judgement]
7. **A fire fact the save can't see.** fire.gd:30 keeps arrow-lit houses "for the session" only. Reload, and they stand
   whole. Spread order is also chosen in the view (fire.gd:214). Rule: the sim owns every fact a player can notice. [fact]
8. **Hand-built where a block fits.** stone_wall.gd (992 lines) rolls its own stacked-stone fracture on Jolt. It works
   and follows the right rule/look split. But it's one wall type. UE's Chaos caches or a Blender Cell Fracture bake
   played as a canned state would cover every building. [judgement]
9. **What's right and should stay:** bridge owns damage, weather and season (damage.js header; weather_fx.gd:1-5);
   villagers use Godot's RVO properly (villagers.gd:349-361); the view "decides nothing". Keep that rule. [fact]

## 6. A wall breach, end to end (recommended blocks)

1. **Sim.** A siege battle hits section 3 of Kingsmere's wall. bridge/damage.js raises its wear 0.62 → 0.91. At ≥ 0.9 the
   section is **breached**. Freeciv/bridge save it in meta.damage. (exists)
2. **Map rule.** The bridge publishes `cities[].damage.sections[3] = breached`. The world-grid layer marks those wall cells
   passable (cost 1 instead of blocked). (new, ~2 days [estimate])
3. **Navmesh.** The wall section's NavigationObstacle3D (`affect_navigation_mesh`) is switched off. Only the realm tile under
   it rebakes (async). Godot's obstacle only acts at bake time, so a tiled bake is the cheap path.
   [fact: [Godot obstacle docs](https://docs.godotengine.org/en/4.3/classes/class_navigationobstacle3d.html)]
4. **Flow field.** The besiegers' target field is recomputed for the tiles touched. Regiments now flow to the gap and
   queue in it. (new, flow-field block or ~600 lines [estimate])
5. **Look, near camera.** stone_wall.gd's Jolt fall plays (exists). **Far or after a load:** jump to the same rubble state
   (exists). Rubble is visual only; the grid rule decides passability.
6. **Save/load.** Reload. Wear 0.91 comes back from meta.damage. The grid marks the cells, the navmesh tile bakes open, the
   wall draws rubble. No view state needed.

## 7. A river crossing, end to end

1. **One river source.** Azgaar's river lines become the single truth. Freeciv gets them as tiles (all of them, or every
   river the view draws). Same list feeds Waterways and the grid. (fix the 900 cut; ~1 day [estimate])
2. **Rule.** Ruleset: river tiles cost a lot to cross and slow the army (or are non-native for land units) except at a
   **ford** or **bridge** extra. Freeciv supports extras and native rules; exact syntax to test. [judgement]
3. **Map move.** A host ordered across: Freeciv paths to the ford. units.gd follows Freeciv's tile path instead of lerping
   straight (units.gd:235). (~1 day [estimate])
4. **Close up.** The cost grid marks water blocked and fords/bridges open. Flow field sends men to the ford, in column.
   Townsfolk use the realm navmesh with water cut out (Recast, as town_nav already does).
5. **Season.** Winter: the bridge may mark a river frozen (crossable) for the season. The grid reads the flag; land3d shows ice.
6. **Save/load.** All of it is Freeciv tiles + bridge flags. Nothing to restore in the view.

## 8. Next steps, ranked

| # | Step | Effort [estimate] | Confidence it pays |
|---|---|---|---|
| 1 | Clean army profile in Godot: 600 / 2,000 / 6,000 at d12 and d40, no capture, CPU vs GPU split (perf probe exists) | 0.5 day | High: settles whether engine matters for armies |
| 2 | Wall-breach + river test (sections 6-7) in Godot on one stretch of Kingsmere | 3-5 days | High: proves the missing layer |
| 3 | Try gdmapf and Tilemap Flowfields on macOS arm64; if neither builds, write our own grid flow field | 1-2 days | Medium: both look immature (Linux-only listing for one) [fact: [listing](https://rustrepo.com/repo/plugin-to-generate-flowfields-from-tilemaps-in-the-godot-engine)] |
| 4 | Impostor/billboard stage for regiments past ~d20 (look for a Godot octahedral-impostor addon first) | 2-5 days | High: triangles are the measured cost |
| 5 | Same breach + river test in UE5 with Mass + City Sample crowd + dynamic navmesh, on this Mac | 1-2 weeks | Medium: Mac caveats, C++ build time for agents |
| 6 | Read 0 A.D.'s pathfinder and wall code (source/simulation2/components/CCmpPathfinder*, walls templates) as the reference design | 1 day | Medium |
| 7 | Move fire spread order and arrow-lit houses into the bridge (fire.gd:30, 214) | 1-2 days | High (save/load truth) |
| 8 | Watch GDC 2022 "Pathing in Age of Empires" and read Emerson's flow-field chapter before step 3 | 0.5 day | High |

## Unverified

- Unreal Mass on Mac at 6,000 units; Chaos on Mac; current Mass plugin status (one bug report says a Mass plugin is
  deprecated in 5.5) [fact: [UE-268724](https://issues.unrealengine.com/issue/UE-268724)].
- Agents Navigation price and its flow-field add-on's official listing.
- Recoil on macOS.
- Total War's and Stronghold's wall internals (no developer source found).
- Freeciv ruleset syntax for a river barrier with fords.
