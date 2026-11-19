# The realm outside towns: built once, saved, loaded

Mac, 2026-11-19: play only loads the realm; "it should just be additive".

1. **Block:** Godot's own. Each layer of what stands still on the land is cut into 32-unit chunks of the map, each a
   `PackedScene` of `batch.gd` batches (their copies' places in the file, the MultiMesh packed empty, the mesh named by
   key and supplied by the owner in play so the season's tint reaches it). `realm/scripts/realm_chunks.gd`.
2. **Made once:** `tools/bake.gd` builds each land (`terrain.gd _plant`: `vegetation.make`, `forest.make`) and keeps
   its chunks under `res://baked/realm/`, then writes what the starting realm's towns and roads felled into them
   (`terrain.keep_chunks`): that is the baseline every game loads. A land never baked is made once and kept in
   `user://kept/realm/`.
3. **Play loads:** chunks stream in by the lens's distance: `ResourceLoader.load_threaded_request`, a `WorkerThreadPool`
   task instantiates off the tree, fills each batch's MultiMesh from one buffer, settles it on the graded ground and
   replays the edits; it joins the tree on `ViewTier.spend_ok`. Far tree cards: every chunk, always. Near trees and
   cover: within reach.
4. **Additive:** a live change (a wood felled for a town, a lane cut, a fire) is an edit: applied to the chunk in the
   tree, kept for any chunk read later, and the chunk saved again into the player's copy (read before the game's), so
   the next start loads the land as it was left. Nothing is laid out again.

Layers now: `woods` (full and middle trees), `woods_far` (cards; its index keeps every tree's place for sight lines and
trunks), `wild` (grass, flowers, bushes, rocks).
