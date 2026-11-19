# The starting realm: one snapshot, every game loads it

Mac, 2026-11-19: simulate the start once and save the whole realm; every new game and Continue start from it.

1. **What:** the bridge's baseline (bridge/chronicles.js BASELINE, nine years in) loaded by `tools/bake.gd` headless,
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
