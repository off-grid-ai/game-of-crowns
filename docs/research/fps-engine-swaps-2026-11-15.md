# FPS: the next hand-written loops to hand to the engine (2026-11-15)

Read-only audit for Mac's ask: "optimise the FPS further. I don't want loss in visual quality... similar to how we
removed hand-written code and used systems". No code changed, nothing run.

**Source of the numbers.** `perf.log`, the section after the last `=== nav7 20:45:17` (battle run, `--perf=smooth`).
Six `jobs (10 s)` windows of 160–221 frames each. "ms/frame" below = the window's ms ÷ its frames, as a range over
the windows. Frames in that run were 42–250 ms (code 19–56 ms, draw 9–48 ms, 0.8–5.5M triangles, 525–1,800 draws).
Estimates are tagged *(est.)*; nothing here is measured after a change.

**Surprise first.** The biggest per-frame costs in the battle are not the ones in the brief. They are in today's new
navigation and ground code: `nav_world` (5–10 ms a frame) and `ground.land` (2.7–7.5 ms a frame). Both use the engine
for the hard part but still run a hand-written loop every frame around it.

## The ranked list (biggest win for least risk first)

### 1. Stop re-baking the navmesh for regiments that move. Let RVO avoidance handle them

- **File, functions:** `realm/scripts/nav_world.gd` `_process`, `_watch`, `_inputs`, `_dispatch`, `_key`
  (`BLOCKING_CLAIMS = ["host", "body", "engine"]`); claims from `army.gd _claim`.
- **Measured:** `nav_world` 5.1–7.8 ms/frame on the main thread (one window 9.6). `watch` is 2.8–5.1, `dispatch` up to
  4.4. On top of that, `nav_world.bake` takes 2.0–14.0 s of worker time every 10 s, so 0.2–1.4 CPU cores are busy
  re-baking all the time.
- **What it does by hand:** every regiment's block is a ground "claim". Each claim is carved into all four land navmeshes
  and re-baked every `nav.claims_settle` (1 s) while the block moves (`moving_on`). `_key()` contains
  `Ground.claims_rev`, and that changes all through a battle, so the watch's sweep never settles. Every frame it
  re-hashes 4 chunks' claims (`claims_in` + `str(hash(...))`) and queues more Recast bakes.
- **Engine feature:** Godot's own rule for dynamic obstacles. Moving things are **avoidance obstacles**, not navmesh
  carves. Re-baking is for static change only. `army_melee.gd _hold_out` already lays every held block as an RVO
  obstacle (`NavigationServer3D.obstacle_create`), so the carve is a second system doing the same job.
  Docs: https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationobstacles.html
- **Change:** take `host` and `body` out of what is baked. Static held ground stays carved: `engine` while parked,
  `camp`. Moving blocks become avoidance obstacles on the maps their movers use (one owner: army_melee's obstacles
  move to the claim itself). Drop `claims_rev` from `_key`.
- **Expected saving:** most of 5–8 ms/frame in battle, and the bake worker load falls to near zero while the armies move
  *(est.)*.
- **Look risk:** none. Nothing drawn changes. Behaviour risk: a route may now pass through another regiment's block and
  rely on avoidance to go round it. Check one battle clip for men walking through a block.
- **Size:** small to medium (about 30 lines, plus moving the obstacle ownership).

### 2. A town that goes off screen keeps its detail. Let frustum culling hide it

- **File, functions:** `realm/scripts/towns.gd` `_on_tier`, `_shell`, `_revive` (driven by `view_tier.gd _watched`).
- **Measured:** `view_tier.changed` 604 ms for 64 changes in 165 frames. That is **9.4 ms per change** (each one a
  hitch) and 2.2–3.7 ms/frame averaged. `resume.towns 232` (the revive) adds 1.0–1.7 ms/frame. `view_tier.watch`
  without changes is only 0.2–0.3 ms/frame, so the watch is cheap and the listener is what costs.
- **What it does by hand:** on `OFF` (just off screen) *or* `FAR`, `_shell` walks every GeometryInstance3D of the town
  with `find_children` and `free()`s the detail. On the way back, `_revive` reads the town back from disk
  (`TownStore`) and re-parents every node. So a sideways pan frees a town and loads it again.
- **Engine feature:** the renderer's frustum culling already draws nothing off screen, for free. Visibility ranges
  (`visibility_range_end`, already set on exactly these nodes, which is how `_detail_only` picks them) already hide them
  at FAR. Docs: https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- **Change:** on `OFF`, only `process_mode = DISABLED` (already there). Shell only at `FAR`. Better still, only after a
  town has been FAR for some seconds, so zooming in and out never pays the free and reload. Keep the shell for
  memory, but only at FAR.
- **Expected saving:** the 9 ms hitches on pans go, plus 2–5 ms/frame in pan-heavy windows *(est.)*.
- **Look risk:** none. The same nodes are hidden by the same engine rules. Memory is higher while towns sit off screen
  but near.
- **Size:** small (a few lines in `_on_tier`).

### 3. Read the land mask once from the heightmap image, not corner by corner each frame

- **File, functions:** `realm/scripts/ground.gd` `_blocks_have`, `_read_block`, `_land_block`; `terrain.gd is_land`,
  `dry_rect`.
- **Measured:** `ground.land` 2.7–7.5 ms/frame, every window, all through the battle.
- **What it does by hand:** the dry/walk mask (0.125-unit cells) is filled lazily, one 2-unit block at a time, on the main
  thread, the first time any `is_clear` touches it. Where `dry_rect` fails (shores, rivers, sea), every corner calls
  `is_land`: a tile lookup, a Terrain3D `get_height` and `in_river`, all in GDScript. A battle that spreads out keeps
  reaching unread blocks.
- **Engine / block:** treat it as baked data, like the towns and navmeshes (`kept.gd`, `tools/bake.gd`: "towns ship
  pre-built"). Build the mask once from the heightmap `Image` plus the river mask and the Lake tiles. Use
  `WorkerThreadPool.add_group_task` over the rows on plain Image copies (not the terrain node, so the "never on a
  worker" rule still holds). Store it as an `Image` (FORMAT_R8) or bytes under `kept/`, and load it in one native read.
  Fords and levelled squares still re-read their area through `_land_changed`, as now.
  Docs: https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html ,
  https://docs.godotengine.org/en/stable/classes/class_image.html
- **Expected saving:** 2.7–7.5 ms/frame, down to about 0 in play *(est.)*.
- **Look risk:** none. The answers are the same, made earlier.
- **Size:** medium (a bake step, a kept file, and a load path that replaces the lazy one; the lazy reader goes).

### 4. Units: let the renderer say what is on screen, and change stances on events

- **File, functions:** `realm/scripts/units.gd _process_timed`.
- **Measured:** `units` 1.25–1.8 ms/frame.
- **What it does by hand:** every frame, for every company figure: a frustum test (`ViewTier.of`), a visibility
  toggle, `Mover.of(n).moving()` and `stance(f)`.
- **Engine feature:** `VisibleOnScreenNotifier3D` (screen_entered / screen_exited from the renderer's own cull) on each
  figure. `villagers` and `castle_life` already use its sibling, `VisibleOnScreenEnabler3D` (`ViewTier.off_when_unseen`).
  Use the notifier here, not the enabler, so a company Freeciv marches keeps moving off screen. The FAR hide becomes one
  check when the lens crosses `FAR_FROM`, not one per figure per frame. The stance is told when the mover stops or the
  wound or dig-in state changes (signals), not polled.
  Docs: https://docs.godotengine.org/en/stable/classes/class_visibleonscreennotifier3d.html
- **Expected saving:** about 1–1.5 ms/frame *(est.)*.
- **Look risk:** none (same rules, driven by events).
- **Size:** medium (one notifier per figure, three signal hooks).

### 5. Map labels: place them again only when the view changes (not an engine swap)

- **File, functions:** `realm/scripts/map_labels.gd _process_timed`, `_rank`, `_think`.
- **Measured:** `map_labels` 1.2–1.9 ms/frame.
- **What it does by hand:** every frame it sorts all towns by `_rank`. `_rank` calls `_mine`, which formats strings, on
  every comparison, so that is O(n log n) string formats. Then for every town it does `unproject_position`,
  `get_combined_minimum_size`, a rect test against the placed rects and `ui.covered()`, even with the camera still.
- **Engine check:** `Label3D` (billboard, `no_depth_test`, `fixed_size`) would place itself natively. Godot has **no
  declutter**, though, and the declutter (seats first, no overlap, the interface kept clear) is the point of this
  layer. Swapping would lose it, so no swap.
  Docs: https://docs.godotengine.org/en/stable/classes/class_label3d.html
- **Change instead:** keep the rank per town (it changes only on sync). Run the placement only when the camera's
  transform, the viewport size, the set of towns or `ui.covered()` changed. Otherwise keep last frame's layout.
- **Expected saving:** 1–1.7 ms/frame whenever the lens is still or easing slowly *(est.)*.
- **Look risk:** none.
- **Size:** small.

### 6. Villagers: drop the hand-written personal-space pass; RVO already does it

- **File, functions:** `realm/scripts/villagers.gd` `_keep_apart` (every frame), `_avoid_others` (4 times a second),
  `_step`.
- **Measured:** `villagers` 0.5–1.4 ms/frame.
- **What it does by hand:** every frame, `get_tree().get_nodes_in_group("people")`, a distance filter, a hand spatial
  hash and sideways nudges. 4 times a second, another walk of the whole group to place a pool of RVO obstacles for
  non-villagers. Its own comment says it covers what avoidance does "a frame late".
- **Engine feature:** NavigationServer3D RVO. Every villager is already an agent. Every mover (cart, horse, fighter) already
  has a `_town_agent` on the same walk map (`mover.gd`). Anyone who isn't an agent yet (scene actors, travellers)
  should become one, with `avoidance_priority` set so walkers yield to those standing, instead of being re-found by a
  group walk.
  Docs: https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_agent_avoidance.html
- **Also flag:** `_step` walks villagers waypoint by waypoint itself, outside `mover.gd`. That goes against CLAUDE.md
  "One way to move". `rules_check.sh` doesn't catch it. Moving villagers onto the Mover is the proper fix and removes
  a second path follower.
- **Expected saving:** 0.5–1 ms/frame *(est.)*.
- **Look risk:** low. Two people stood on one point are parted by `_make_way` today; check a packed square on film.
- **Size:** small for the two passes; large for the move onto the Mover.

### 7. Arrows: fixed-size MultiMesh, one buffer write, or the arc in the shader

- **File, functions:** `realm/scripts/army_field.gd _fly` (also `_keep_up`, `_morale`).
- **Measured:** `army_field` 0.75–0.92 ms/frame (1.35 in the early window).
- **What it does by hand:** every frame it sets `mm.instance_count = shown.size()` (resizing a MultiMesh reallocates
  and clears its buffer), then one `set_instance_transform` per arrow, each a server call.
- **Engine feature:** give the MultiMesh a fixed capacity and use `visible_instance_count`. Write all transforms in one
  `RenderingServer.multimesh_set_buffer`. Or, with no CPU per arrow, put each arrow's start, end, launch time and flight
  time in `INSTANCE_CUSTOM` and compute the arc in the vertex shader from `TIME`, as the VAT soldiers already do for
  their clips. Docs: https://docs.godotengine.org/en/stable/classes/class_multimesh.html ,
  https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
- **Note:** keep our own copy of the data (as `batch.gd` and the VAT fix 0d620de5 do), never read it back.
- **Expected saving:** 0.3–0.6 ms/frame in a volley *(est.)*.
- **Look risk:** none.
- **Size:** small (buffer) or medium (shader arc).

### 8. Turn on occlusion culling for towns and castles

- **File:** `realm/project.godot` (no `rendering/occlusion_culling/use_occlusion_culling`), the town builder
  (`towns.gd`), `castle_builder.gd`.
- **Measured:** draw 9–48 ms, 1,000–1,800 draws, 2–5.5M triangles. At the low oblique camera, houses hide what is behind
  them: people (`towns/Skeleton3D` 0.2M, `scenes/GeneralSkeleton` 0.2M), `CastleLife` props (0.1–0.2M), wells,
  stalls. Godot culls none of it now.
- **Engine feature:** Godot's occlusion culling (Embree raster on the CPU, threaded). Add an `OccluderInstance3D` per town
  with `BoxOccluder3D` / `PolygonOccluder3D`, made from the footprints `ground.gd` already holds, kept inside the walls.
  Optionally add a coarse land occluder for ridges.
  Docs: https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html
- **Limit:** it culls per node. A MultiMesh batch (`bulk.gd` cells, a town's per-model batches) is culled whole, so the
  win is on skinned people and single props.
- **Expected saving:** 10–25% of draws inside towns *(est., not measured; first measure `draw` with it on in one
  run)*.
- **Look risk:** none if the occluders sit inside the walls. A popping risk only if one sticks out, so draw them small.
- **Size:** medium.

### 9. Distant townsfolk as VAT crowds instead of skeletons

- **File, functions:** `realm/scripts/anim_lod.gd _animate`, `_move`; `people.gd`.
- **Measured:** `anim_lod` 0.7–1.2 ms/frame (2.0 early). The skinned draws are `towns/Skeleton3D` and
  `scenes/GeneralSkeleton` at about 0.2M triangles each, plus skinning on the GPU.
- **What it does by hand:** Godot has **no** built-in animation LOD. `ANIMATION_CALLBACK_MODE_PROCESS_MANUAL` plus
  `advance()` with a stride is the documented way, so that part is right; keep it. Two things are redundant. Its own
  frustum test (`ViewTier.of` inside `_every`) repeats what the `VisibleOnScreenEnabler3D` already on each villager knows
  (`can_process()`). And every far body is a full skeleton.
- **Engine / block:** the `godot_vat` add-on (`addons/godot_vat`), already used for every soldier: one MultiMesh draw per
  model, with the clip played in the vertex shader. Past `lod.near` (6 units: a few dozen pixels) a person would become
  a VAT copy and the skeleton would sleep. Docs: https://docs.godotengine.org/en/stable/classes/class_animationmixer.html
  (callback modes); the add-on's README in `realm/addons/godot_vat`.
- **Expected saving:** most of `anim_lod`, plus skinning, for crowds past 6 units *(est. 1–2 ms CPU and some GPU)*.
- **Look risk:** low but real. VAT has no blend between clips, so a far person snaps between clips, and the near/far
  handover must match the pose. That is why it is ninth. Run it through the look audit before turning it on.
- **Size:** large.

### 10. Town building batches split per cell, so mesh LOD and culling work per cell

- **File, functions:** `realm/scripts/towns.gd _flush`, `_hlod`; `batch.gd make`.
- **Measured:** `towns/MultiMeshInstance3D meshy_hs_townhouse_narrow` 0.2–0.6M triangles,
  `meshy_sq_merchant_house` 0.2M, at NEAR.
- **What it does:** one MultiMesh per model per town. Godot's automatic mesh LOD and its frustum and occlusion culling
  judge a MultiMesh by its whole box, so at NEAR every house of that model draws at full detail, even the ones behind
  the lens's shoulder. `realistic.gd` comments already note "a batch's own LOD is judged by the whole town's box".
- **Engine feature:** the same per-cell batching `bulk.gd` uses (`CELL` 32 there; about 8–12 units for a town). Then
  `mesh_lod` (threshold 16 px, already set) and frustum culling pick per cell.
  Docs: https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html
- **Expected saving:** some of the 0.6M at NEAR, for a few more draws *(est.; measure)*.
- **Look risk:** none (Godot's own LOD levels, made by `mesh_lods.gd` under the error cap).
- **Size:** medium.

## Already using the engine well: leave these alone

- **`bulk.gd`**: MultiMesh per mesh per 32-unit cell, with `visibility_range_end` and margins; a kept copy of the
  transforms, never read back. This is how it should be done.
- **Town HLOD** (`towns.gd _hlod`, `detail`; `realistic.gd _low`; `mesh_lods.gd`): Godot visibility ranges with
  self-fade, plus `ImporterMesh.generate_lods` (meshoptimizer) levels under an error cap.
- **Soldiers** (`army.gd`, `addons/godot_vat`): VAT MultiMesh, one draw per regiment, with our own copy of the data (the
  0d620de5 fix).
- **Minds** (LimboAI `BTPlayer`, `update_mode = MANUAL`, `MIND_BUDGET_MS`): 0.06–0.7 ms/frame. A proven block on a
  budget.
- **Crowd avoidance**: NavigationServer3D RVO agents and obstacles in `mover.gd`, `villagers.gd` and `army_melee.gd`.
- **Ground queries** (`ground.gd` on Jolt through PhysicsServer3D): `ground.is_clear` 0.15–1.0 ms/frame for
  3–36k calls. Fine. Only the land mask (item 3) is still hand-read.
- **Nav bakes** on `WorkerThreadPool` and kept to disk (`nav_world.gd`): right, except for what is fed to them (item 1).
- **Off-screen people**: `VisibleOnScreenEnabler3D` (`ViewTier.off_when_unseen`) on villagers and castle folk.
- **`view_tier.of` itself**: about 5,000 queries a frame for 0.2–0.3 ms. Cheap. The cost was its listener (item 2).
- **Sound** (`soundscape.gd`, AudioStreamPlayer3D with attenuation): 0.1–0.2 ms/frame. Nothing to win.
- **`presence.gd`, `weather_fx.gd`, `ui`, `minimap`**: each 0.2 ms/frame or less.
- **Shadows**: `directional_shadow_max_distance` stepped by zoom (`main.gd _update_labels`), small things cast none.
  Already tuned.

## Notes

- **`resume.town_life:134` / `life.dressing`** (1.3–3.0 and about 1.0 ms/frame while a town comes NEAR) are staging work
  on the shared pot (`ViewTier.spend_ok`). It is capped, not wasted. The real fix is the baked-data route from item 3:
  dress each town in `tools/bake.gd` and ship the dressing kept (`Dressing.dress` is seeded and the same every time), so
  NEAR loads it instead of searching for room again. Item 2 also cuts how often a town's life is re-staged.
- **`main`** 0.5–2.2 ms/frame includes `perf._log_perf` and its per-frame probe bookkeeping. Measure it with the probe
  off before acting on it.
- **Order to build:** 1, 2 and 5 are small and touch nothing drawn, so they can go in one batch and one bundled run.
  3 and 4 next. 8 needs one before/after `draw` measure. 9 goes through the look audit.
