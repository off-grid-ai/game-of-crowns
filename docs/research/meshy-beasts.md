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
| Cow, sheep, pig, goat, through the API | 4 x 35 = 140 | realm/tools/meshy_api.py model: latest (7.1), 2k geometry, Meshy 7 2k PBR texture, remeshed in the task (cow 8k, the rest 6k), single image |
| Remeshes, multi-view images, downloads | 0 | |

Balance 1,165 before; **285 spent here** (35 wasted on the browser watchman). The key's balance read 740 after the farm four: the other 140 in that window were fire-siege's farm set (a883bdce). Nothing bought, no plan or setting changed. **VENDOR + SEEN**

## The pieces

| Kind | Base (rig, clips) | Tris | Fit scale (x, y, z) | Defects first | Verdict |
|---|---|---|---|---|---|
| hen | Quaternius chicken (poly.pizza, CC0): Root, Legs, Body; Idle, Idle_Peck, Run, Attack, Death | 3,130 | 0.65, 0.67, 0.65 | Scowling cartoon face (reads only close up); comb a cock's, large for a hen; no neck bone, so the peck is the whole body tipping (the base's own clip) | Clears the statue's bar at roof height: full painted colour, clear silhouette. In |
| cow | Quaternius cow: Idle, Walk, WalkSlow, Run, Jump, Death | ~8k | 3.95, 4.82, 4.78 | A touch long in the barrel against the concept | Clears the bar: red-brown painted coat, horns, walks on its own clips. In |
| sheep | the Quaternius cow's skeleton and clips (the sheep's own rig took the cow's walk with a hind leg flung out: its rest pose differs) | ~10k | 2.83, 4.83, 3.62 | Long and low on the cow's frame; fleece reads well | In; walks for the first time (the kit sheep had only Idle and Jump, so a driven flock glided) |
| pig | Quaternius pig, the cow's Walk, WalkSlow, Run added (the same rest pose) | ~13k | 4.59, 5.16, 4.71 | None at roof height | Clears the bar: bristly rust-and-black coat. In; walks for the first time |
| goat | the cow's skeleton and clips, as the sheep | ~11k | 3.00, 4.83, 3.61 | Long and low on the cow's frame | In; the realm's first goat (the kind had no model) |
| dog | Quaternius wolf (CC0): its full rig and 12 clips (Idle, Idle_2, Walk, Gallop, Eating, Idle_2_HeadLow…) | 10,421 | 2.48, 2.92, 3.18 | Body proportions stretched a little on the wolf's box (the concept's dog is stockier than the wolf); the coat's long hair is painted, not modelled | Clears the bar; walks, eats, wags on the wolf's clips. In; length 1.1 m nose to tail (was the wolf at 0.85, a grey speck) |

Probe: `tools/animals_check.gd` with `animals.json` `set` (all six kinds from the painted set; cow, sheep, pig, goat
and dog must have a walk). Farm four: before 6 problems (four kit models, sheep and pig without a walk, no goat), after PASS. Before: chicken had no model at all (the square's yards asked for 2-4 hens and none appeared), the dog was
the grey wolf. After: both drawn from the set, PASS.

## The watchman (the square's guard, cast)

Concept `docs/art/cast/watchman_front.png`, drawn from 01-town's guard (`docs/art/cast/ref/watchman_ref.png`): silver
plate and helm, red plume, crimson tunic with a cream panel down the chest and gold trim, brown boots. Made and rigged
through the Meshy API (key from the keychain at run time). 10,408 tris, Mixamo skeleton, imported by
`realm/tools/cast_import.py` as `cast_watchman` with the crimson cloth and plume masked for the house colour (share
0.31). Replaces the community "Town Guard Soldier" outright (blue armour, red boots: read as a superhero against
01-town's). cast.json `panel`: his chest panel is painted on, so people.gd puts only the house arms on it. Back seen in
Blender: clean and consistent with the front. Defects: bare oversized hands (no gauntlets), no finger bones.
