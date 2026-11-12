# The square's beasts made in Meshy: the hen and the dog (2026-11-12)

Goal: Kingsmere's square's animals in the painted look of the Meshy cast and square set (Mac: "one Meshy look across
people, animals and props"), replacing the kit beasts outright. Concepts: [docs/art/animals/](../art/animals/)
(the cast's style prompt, each drawn over a render of its rigged CC0 Quaternius base). Rig and moves:
`realm/tools/beast_rig.py` (the base's skeleton, hand-painted weights and clips moved onto the Meshy body).

Tags: **SEEN** (looked at in Meshy's viewer and our Blender pose renders), **VENDOR** (Meshy's page says it).

## How they were made

- Mac's Meshy account (Pro), on meshy.ai in his Chrome (the API key came later; every piece from now goes through
  the Meshy API, no browser). Image-to-3D: High Detail, Meshy 7.1, Ultra 2K, Multi-view (Meshy's own left, back and
  right drawn from the concept; the dog's right view came out facing the same way as its left and was dropped),
  Texture Meshy 7 at 2K, Pose off, Image Enhancement on, Licence **Private**. **SEEN**
- Remesh: Fixed, triangle topology; the hen 3K (several to a yard), the dog 10K. 0 credits. **VENDOR + SEEN**
- Files outside git: `~/code/goc-kits/meshy/beasts/<kind>/` (`<kind>_<n>k.glb` as downloaded, `<kind>_rigged.glb`,
  `input/`). In the game: `realm/assets/meshy/beasts/<kind>/<kind>.glb` (ignored; its `.import` files tracked).

## Spend

| Piece | Credits | Notes |
|---|---|---|
| Hen | 35 | 25 model + 10 texture |
| Dog | 35 | |
| Watchman, browser copy | 35 | made in the same sitting; the API can't see web-made tasks, so it was never downloaded |
| Watchman, through the API | 35 | image-to-3D: latest (7.1), geometry 2k, Meshy 7 texture 2k with PBR, image enhancement, A-pose, remesh 10k triangle; single image (the API's multi-view needs our own views) |
| Watchman rig, through the API | 5 | rigging, skeleton_template mixamo, 1.75 m; no finger bones |
| Remeshes, multi-view images, downloads | 0 | |

Balance 1,165 before, 1,020 after: **145 spent** (35 wasted on the browser watchman). Nothing bought, no plan or setting changed. **VENDOR + SEEN**

## The pieces

| Kind | Base (rig, clips) | Tris | Fit scale (x, y, z) | Defects first | Verdict |
|---|---|---|---|---|---|
| hen | Quaternius chicken (poly.pizza, CC0): Root, Legs, Body; Idle, Idle_Peck, Run, Attack, Death | 3,130 | 0.65, 0.67, 0.65 | Scowling cartoon face (reads only close up); comb a cock's, large for a hen; no neck bone, so the peck is the whole body tipping (the base's own clip) | Clears the statue's bar at roof height: full painted colour, clear silhouette. In |
| dog | Quaternius wolf (CC0): its full rig and 12 clips (Idle, Idle_2, Walk, Gallop, Eating, Idle_2_HeadLow…) | 10,421 | 2.48, 2.92, 3.18 | Body proportions stretched a little on the wolf's box (the concept's dog is stockier than the wolf); the coat's long hair is painted, not modelled | Clears the bar; walks, eats, wags on the wolf's clips. In; length 1.1 m nose to tail (was the wolf at 0.85, a grey speck) |

Probe: `tools/animals_check.gd` with `animals.json` `set` (kinds chicken and dog; cow, sheep, pig, goat listed as
next). Before: chicken had no model at all (the square's yards asked for 2-4 hens and none appeared), the dog was
the grey wolf. After: both drawn from the set, PASS.

## The watchman (the square's guard, cast)

Concept `docs/art/cast/watchman_front.png`, drawn from 01-town's guard (`docs/art/cast/ref/watchman_ref.png`): silver
plate and helm, red plume, crimson tunic with a cream panel down the chest and gold trim, brown boots. Made and rigged
through the Meshy API (key from the keychain at run time). 10,408 tris, Mixamo skeleton, imported by
`realm/tools/cast_import.py` as `cast_watchman` with the crimson cloth and plume masked for the house colour (share
0.31). Replaces the community "Town Guard Soldier" outright (blue armour, red boots: read as a superhero against
01-town's). cast.json `panel`: his chest panel is painted on, so people.gd puts only the house arms on it. Back seen in
Blender: clean and consistent with the front. Defects: bare oversized hands (no gauntlets), no finger bones.
