# The starting realm: one snapshot, every game loads it

Mac, 2026-11-19: simulate the start once and save the whole realm; every new game and Continue start from it.

**Three starts (title.gd):** "Aldmere, nine years in" (scenario `aldmere`, the bridge's BASELINE) and "Aldmere, year
one" (`aldmere_fresh`) are fixed: each is snapshotted whole, logic and view. Year one gets a bridge baseline of its own,
captured as tools/make-baseline.sh captures nine years in, so a year-one game copies it instead of founding live; the
bake then snapshots each start's view under its own name (`<scenario>`). "A random realm" can't be pre-made: it is built
once when the reign is created and saved there and then as that reign's own snapshot (the player's copy); Continue loads it.

1. **What:** each fixed start's bridge baseline (bridge/chronicles.js BASELINE, nine years in; year one's own) loaded by `tools/bake.gd` headless,
   let settle (towns stood, roads painted, farms laid, people at their posts), then saved as Godot PackedScenes by layer:
   the land (realm chunks, done: docs/REALM_CHUNKS.md), towns (town_store.gd, by id), roads (by road key), farms (by
   patch, done), and the people (one scene a town: bodies, posts, activity, blackboard).
2. **Load:** play reads each layer with `ResourceLoader.load_threaded_request`, instantiates on a WorkerThreadPool task
   and joins the tree on `ViewTier.spend_ok`, under the loading card. Only what differs from the baseline is applied
   after (the reign's own dice: names, a town grown or razed, a road changed), as edits on the loaded scene, then saved
   to the player's copy (additive: the next start loads it as left).
3. **Can't be packed, restored on load:** LimboAI's running tree (BTPlayer's task states): the tree is made again from
   its .tres with the saved blackboard, so a mind resumes its activity, not its tick. AnimationTree playback: the saved
   activity's clip at a random phase. A Mover's route in flight and worker tasks: asked again (nav_world.gd). RIDs
   (Jolt bodies, navigation regions, MultiMesh data): rebuilt by their nodes on entering the tree (batches refill from
   their own lists). Runtime signal links and bulk.gd handles: re-made by their owners' `_ready`.
4. **Owners:** land, farms, roads, bake: this thread. Towns: the towns thread (town_store.gd). People and minds
   (villagers.gd, town_life.gd, npc_mind.gd, people.gd): their owners add a `snapshot()` / `restore()` pair each;
   tools/bake.gd calls them and keeps the result, as it keeps the land.

## The people (Mac 2026-11-19: "people, state, thought process, everything")

**What casting cost (perf.log, the heaviest first minute of a play):** a town's Life is cast whenever it comes NEAR
(towns.gd _life_near): town_life.gd lays its works (the forge's smiths, the mill, the inn, crews, beasts), then
town_scenes.gd casts every standing row (keepers, the watch's beat, carriers, the cart, dogs, children, knots).
town_scenes body 1.46 s (222 bodies), mind 1.47 s, cast 0.90 s, anchor.stops 0.74 s, done 0.70 s, town_life pacing
0.41 s, place/spots/open 0.19 s: ~6 s of main-thread work a start. villagers/anim_lod/minds lines are their per-frame
ticks, not casting; villagers.gd and castle_life.gd stream bodies by tier and are not in this snapshot yet.

1. **Saved (people_store.gd, tools/bake.gd, each start that has a bridge baseline):** every town's Life as staged for its
   facts, one PackedScene a town keyed by those facts (its sig, size, holder's colour, rank, town file and edition), so
   both starts' Lives sit side by side and a town loads whichever matches what it is now. Props, sites, stalls, metas
   (node links as paths) and the town root's staging metas (keepers, horses, piles, stock, square census) are packed.
2. **A body is packed as itself minus its insides:** its skeleton, meshes and clips come from third-party files (an
   imported mesh can't be referenced from another file, only copied: ~0.5 MB a body), so each body keeps the record it
   was made by (`made`: the maker, its arguments, the dice's seed and state, the town's dress) and is remade from it on
   load, the same look; what was added after (a bier on a shoulder, a torch) is packed on it.
3. **A mind is saved as data:** a LimboAI tree (its tasks are inner classes, it holds callables) can't be packed, so each
   installer (npc_mind give, town_scenes walker, a drill, a beast's idle life, the works' tick) leaves a `_redo` record
   (its owner, function, plain arguments, node links as paths) and the bake adds the blackboard's thought (last
   activity, clip, breaker, its place in the round: `weigh_phase` + `picks`), so the mind resumes the activity it was
   in, at its place in its round, not its tick. GPU particles are packed as their CPU twins and turned back.
4. **On load (town_life.gd):** read on Godot's loader threads, made a node on a worker, then off the tree each body
   remade, links turned back and each `_redo` run on the frame's pot (ViewTier.spend_ok), then swapped in whole. A Life
   with anything the bake can't save (an inner-class node with no redo, a Timer or particle nobody records) is not kept:
   the bake names it (`BAKE lives: ... not kept: <why>`), and that town is cast as before until its owner records it.
5. **After the start:** a town whose facts change (a riot, a season) is staged for its new facts as it always was; that
   restage is the town changing, not the start. Births, deaths and new workers are added on the loaded Life.
