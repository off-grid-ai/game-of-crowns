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
| Watchman (the square's guard, cast) | 35 | made in the same sitting; not imported yet |
| Remeshes, multi-view images, downloads | 0 | |

Balance 1,165 before, 1,060 after: **105 spent.** Nothing bought, no plan or setting changed. **VENDOR + SEEN**

## The pieces

| Kind | Base (rig, clips) | Tris | Fit scale (x, y, z) | Defects first | Verdict |
|---|---|---|---|---|---|
| hen | Quaternius chicken (poly.pizza, CC0): Root, Legs, Body; Idle, Idle_Peck, Run, Attack, Death | 3,130 | 0.65, 0.67, 0.65 | Scowling cartoon face (reads only close up); comb a cock's, large for a hen; no neck bone, so the peck is the whole body tipping (the base's own clip) | Clears the statue's bar at roof height: full painted colour, clear silhouette. In |
| dog | Quaternius wolf (CC0): its full rig and 12 clips (Idle, Idle_2, Walk, Gallop, Eating, Idle_2_HeadLow…) | 10,421 | 2.48, 2.92, 3.18 | Body proportions stretched a little on the wolf's box (the concept's dog is stockier than the wolf); the coat's long hair is painted, not modelled | Clears the bar; walks, eats, wags on the wolf's clips. In; length 1.1 m nose to tail (was the wolf at 0.85, a grey speck) |

Probe: `tools/animals_check.gd` with `animals.json` `set` (kinds chicken and dog; cow, sheep, pig, goat listed as
next). Before: chicken had no model at all (the square's yards asked for 2-4 hens and none appeared), the dog was
the grey wolf. After: both drawn from the set, PASS.
