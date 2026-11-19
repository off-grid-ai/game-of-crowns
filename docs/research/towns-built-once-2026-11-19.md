# Towns built once, then only loaded and edited (Mac, 2026-11-19)

Mac: "once a scene is created, you should be able to use that as the baseline the next time"; "it should just be additive".

- **One file a town** (town_store.gd): a PackedScene keyed by the town alone (Freeciv id + the map's land; in play also the chronicle's reign id). Its facts (size, buildings, holder) are not in the key, so a town that grows keeps its file.
- **Read order**: the player's own copy in this reign, else the game's baked baseline (tools/bake.gd: the starting realm), else laid out once and kept. Loading stays threaded (load_threaded_request, made a node on a worker).
- **A change is an edit** (towns.gd `_edit`): what the kept layout lacks (new houses, a new building's trade, the edge round them) is laid off-tree and added; a change of hands, seat or bannerman swaps banners (`_reown`, `_family_arms`). A smaller town keeps its houses; a new rank or seat keeps the square and castle it was founded with. The edited town's edition goes up and it is written over the player's file (packed on the main thread because it is in the tree; written by ResourceSaver on a worker, kept.gd).
- **Gone**: the facts-hash key, the index of kept ages, `nearest` (grow forward from an older age), and the full rebuild + `_merge` for a change that wasn't growth.
- **Bake**: the ages and chronicle passes of tools/bake.gd no longer feed anything for towns (no nearest-age lookup); a bake keeps the starting realm's towns as the baseline and never edits over them.
