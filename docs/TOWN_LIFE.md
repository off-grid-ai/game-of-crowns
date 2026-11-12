# Town life: one store, one direction (Mac, 2026-11-12)

Mac's call: no more hand-written scene functions; centralised state; data flows one way, like a Redux store.
Research: docs/research/what-were-getting-wrong-2026-11-12.md. No engine ships town life (Unreal ships only the
plumbing: Smart Objects, Mass Signals); the design copies Unreal's smart objects and slots, GTA and Red Dead's
scenario points, The Sims' advertisements and RimWorld's moods. No fallbacks: what this replaces is deleted.

```
Freeciv -> bridge -> /world ─┐
events (fire, levy, ruling) ─┴─> STORE (awareness.gd: realm + town blackboards)
                                   │
                                   ▼
                       DIRECTOR (town_scenes.gd)  the reducer: state + hour + events -> plan
                                   │  writes only: town.scenes (running), town.claims (slots taken)
                                   ▼
                       PEOPLE (one LimboAI tree each) read their assignment, act,
                       and dispatch "done" / "left" back; they never write shared state.
```

## The store
- Realm scope and one scope per town, filled only by `awareness.sync(/world)` and `awareness.emit(event)`.
- Town facts (from the bridge): mood, at_war, grief, prosperity, granary_low, levy, burnt, ruling, besieged.
- Derived town mood tags (one function, `mood_tags`): war, levy, hunger, grief, riches, feast, unrest, fire.
- The director's slice: `scenes` (each running scene: id, kind, slot, roles, cast, ends_at) and `claims`.

## Actions
- `sync`: a new /world (the season turned, a ruling, a levy).
- `stimulus`: an event with a place and a reach (fire, battle, herald, riot, the King passing).
- `done(person, scene)` and `left(person)`: from a person's tree.
Nothing else changes the store.

## The director (reducer)
Every tick, per town near the camera: from the town's state, the hour and the events since the last tick, it
starts and ends scenes (weights from data, caps by town size), casts roles, claims slots and writes the plan. A
stimulus within reach interrupts lower-priority scenes for its reaction scene.

## Data (realm/data/town_scenes.json): rows, not code
- `objects`: smart objects, the places a scene can happen and their slots (well, stall, gate, tavern, forge,
  granary, square, a building site), each slot a spot, a facing and the roles it takes.
- `scenes`: id, object, roles (who, how many, clips), hours, how long, base weight, mood weights, cap.
- `reactions`: per stimulus kind: reach, priority, who reacts and the reaction scene (flee, gather, help, cheer,
  kneel), how long.
- `director`: tick, most scenes at once by town size, how near the camera.

A new scene, mood or reaction is a row. A new kind of behaviour is a new LimboAI task, not a new branch.

## Replaced (2026-11-12)
town_life.gd's scene functions are gone: _crowd, _revels, _trade's people, _market_day's people, _unrest, _crier,
_moods with its _muster, _feast, _justice, _grant, _dole, _mourning and _leaving (the Leaving class), _square_life,
_square_more, _beat, _crowd_count and SquareLife, and the people _dress posted (the war's watch, the well's mourners,
the lute, the tax table's queue). Each is a `standing` row in realm/data/town_scenes.json, staged by the director
(town_scenes.gd `stage`) when town_life.gd dresses the town; town_life keeps only the props (`dress_<name>`, each
returning where the scene's people go) and the working buildings' own people. Posted people get their npc_mind.gd
post; walkers (the watch's beat, carriers, the cart, dogs, children chasing, the funeral, the levy marching out) get
LimboAI tasks in town_scenes.gd and walk only by the Mover. crowd.json and moods.json keep what isn't a scene's cast
(the villagers' square agents, the market's switch, how the town looks). The passing scenes that duplicated a
standing one (muster, mourners, feast dance, angry crowd, beggars, granary queue, crier) went from `scenes`.
Guard: realm/tools/director_probe.gd.
