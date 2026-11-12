# Meshy townsfolk cast: 14 people for Aldmere's streets (2026-11-12)

Mac: "replace all of the people on the ground… with Meshy characters… just make a really good experience."
Concepts by the Codex CLI in [docs/art/cast/](../art/cast/) (`<name>_front.png`, `<name>_views.png`, `sheet.jpg`,
style in `STYLE.md`). Models made in Mac's Meshy account (Starter plan) through the website. Files live outside
git in `~/code/goc-kits/meshy/cast/<name>/` (GLB + `SOURCE.md` + `input/`). Turntables (Blender 5.2, Cycles on CPU,
1024 px; front, 3/4, side, back, top-3/4) in `/tmp/goc-models/meshy/cast/<name>/<name>_sheet.jpg`.

**Cast sheet (all 14 plus the man-at-arms): `/tmp/goc-models/meshy/cast/cast_sheet.jpg`.**

Tags: **SEEN** (looked at in our turntable), **VENDOR** (Meshy's page says it).

## Pipeline (same for every character)

1. Inputs: the front concept as Main view; the views sheet split in half, the side profile into **Left** and the back
   into **Back** (Right left empty).
2. Image-to-3D: High Detail, Meshy 7.1, Ultra 2K, Multi-view on, Meshy 7 texture at 2K, **A-pose**, Image
   Enhancement on, Licence **Private**. 35 credits (25 model + 10 texture). Output about 0.8-1.6 million triangles.
3. Remesh: Fixed, custom **8,000 triangles**, triangle topology, 0 credits. Results 8,015-8,329 tris.
4. Rig: Meshy auto-rig (Humanoid, Mixamo skeleton), 0 credits. **Only the first one worked** (farmer_m). From the
   second character on, Meshy's rig Generate button carries a PRO badge with "Subscribe and Unlock unlimited
   generation": Starter allows only a couple of auto-rigs (we used two: man-at-arms try 2 and farmer_m). I did not
   upgrade. **13 characters are downloaded unrigged** (`<name>_8k.glb`); farmer_m is `farmer_m_rigged.glb`
   (Mixamo skeleton, Meshy's default clips in the file).
5. One generation per character, no retries: none failed outright.

## Spend

- Credits: 14 × 35 = **490** (1,185 before the cast, 695 after; daily login added 30). **VENDOR + SEEN**
- Own-model downloads: **14** (farmer_m rigged + 13 unrigged). With the four man-at-arms files that is 18 of
  Starter's 20 this month; **2 left**. No character is left undownloaded.
- Nothing bought, nothing upgraded.

## Defects, per character (SEEN at 100% in the turntables)

Common to all:
- **All are about 1.9 m tall**, children included (Meshy normalises height). The boy and girl must be scaled to
  about 0.65-0.7 on import; the old woman a little down. farmer_m is 1.7 m (rig step set 1.7).
- **Not rigged** except farmer_m (see step 4). They're in a clean A-pose, so Mixamo's auto-rigger or Meshy on a
  higher plan will take them as they are.
- Each GLB carries one 2K base colour, metallic-roughness and normal map on one material; UVs are Meshy's automatic
  atlas (many small islands): fine for a hue-based house-colour mask, not for hand painting.
- The rigged file holds a stray 80-face "Icosphere" object (about 2 m across) next to the body; delete on import.

| Character | Meshy name | Tris | Defects first | Verdict |
|---|---|---|---|---|
| farmer_m | Harvest Guardian | 8,280 | Hat brim slightly thick from above; otherwise clean | Good; rigged |
| farmer_f | Rosie the Village Baker | 8,239 | Headscarf hangs as a flat sheet over the back of the head; hitched skirt folds dark | Good |
| blacksmith | The Ironhide Blacksmith | 8,268 | One dark baked-shadow patch on the apron's side | Good; best of the cast |
| miller | Flour-Dusted Baker | 8,293 | Flour dust reads as blotchy white smears on the apron and arms (in the concept, but heavy) | Good |
| stallholder | The Cheerful Wanderer | 8,299 | None seen | Good |
| townswoman | The Woolen Vineyard Maiden | 8,299 | **Dark blotches on the dress** on the side and back (baked shadow patches, rule 3) | Usable at roof height; fix texture later |
| merchant | Lord Evergreen | 8,282 | Dark blotches on the robe's sides | Usable; gold trim and fur crisp |
| old_man | Kindly Sage | 8,256 | None seen; patches and frayed hem are in the concept | Good |
| old_woman | Grandmother Willow | 8,329 | Dark blotch on the dress side | Good |
| boy | Sunny Patchcloak | 8,327 | A blue smear on one boot toe (from the capelet colour); same height as adults | Good after scaling |
| girl | Poppy | 8,258 | Same height as adults | Good after scaling |
| priest | The Gentle Friar | 8,254 | None seen | Good |
| noble_lady | Sapphire Duchess | 8,015 | More realistic, slimmer proportions than the rest of the cast (small head, long body) | Usable; slightly off-style |
| town_crier | Jolly Red Wanderer | 8,255 | Hood sits to one side of the head and bunches at the back | Good |

Faces read clearly at 100% on every character (e.g. blacksmith crop `/tmp/goc-models/meshy/cast/crop_check.png`,
right); the dark cloth blotches (same file, left: townswoman's dress side) are the one recurring texture defect.

## Against the man-at-arms

Side by side on the cast sheet the townsfolk and the man-at-arms (try 3 re-textured) read as one game: the same
chunky painted look, big hands, warm materials. The cast is cleaner than any man-at-arms try (multi-view input
did what it promised: backs are designed, not guessed).

## What's left for Mac

- Rigging: 13 characters need a skeleton. Options: Meshy on a higher plan (its rig is free per use but capped on
  Starter), or Mixamo (free with an Adobe login only Mac can give), or a Blender auto-rig. I stopped here.
- Two own-model downloads remain this month.
