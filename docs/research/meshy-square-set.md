# Kingsmere square set: 8 pieces made in Meshy to 01-town's finish (2026-11-12)

Goal: the square's buildings and props at the finish of [docs/art/target/01-town.jpg](../art/target/01-town.jpg)
(hand-painted storybook RTS). Concepts by the Codex CLI in [docs/art/square/](../art/square/) (fixed style prompt
in `STYLE.md`, each piece drawn with its 01-town crop attached). Models made in Mac's Meshy account (Pro) on
meshy.ai. Files outside git in `~/code/goc-kits/meshy/square/<name>/` (GLB, `SOURCE.md`, `input/`). Imported (Blender,
`realm/tools/meshy_import.py`) as `realm/data/meshy.json` pieces `sq_<name>` into `realm/assets/meshy/sq_<name>/`.
Not placed in towns: `replaces` is empty; the buildings thread wires them.

**Contact sheet: `/tmp/goc-models/meshy/square/sheet.jpg`** (per row: 01-town crop, concept, our model front 3/4,
our model back 3/4; Blender Cycles on the CPU). Turntables and measure grids per piece in
`/tmp/goc-models/meshy/square/<name>/`.

Tags: **SEEN** (looked at in our turntable), **VENDOR** (Meshy's page says it).

## Pipeline (same for every piece)

1. Concept: `codex exec -i ref/<name>_ref.jpg -- "<style.txt> The asset: <line>"`, one 3/4 view on flat grey.
   All eight first try.
2. Image-to-3D: High Detail, Meshy 7.1, Ultra 2K, Multi-view on (Meshy's own free view generator drew left, back,
   right from the concept; checked before generating), Texture Meshy 7 at 2K, Pose off, Image Enhancement on,
   Licence **Private**. 35 credits each (25 model + 10 texture). Raw 0.9-2.2 million triangles. **VENDOR + SEEN**
3. Remesh: Fixed, triangle topology; 30K for the four buildings, custom 15,000 for the stall, 12,000 for well,
   statue and cart. 0 credits.
4. Download GLB (texture GLB of the remeshed model: one baked material, 2K base colour, metal-rough, normal).
5. One generation per piece; none was broken, so no retries.

## Spend

- Credits: **1,445 before, 1,165 after: 280 spent** (8 x 35). Remeshes, multi-view images and downloads free.
  Nothing bought, no plan or setting changed. **VENDOR + SEEN**

## Pieces

Size is width x depth x height in metres as imported (height set in meshy.json; front faces +Z, the street side).
House colour: roof pieces mask only upward red faces (tiles) into `MI_RoundTiles_house`; stall and statue mask any
red (awning stripes; cloak and banner); cottage and cart mask nothing.

| Piece | meshy.json | Meshy name | Size (m) | Tris | House share | Defects seen in the turntable, first | Verdict |
|---|---|---|---|---|---|---|---|
| Townhouse | sq_townhouse | Hearthglen Cottage | 5.8 x 4.9 x 9.0 | 29,356 | 20% | **Back wall weak**: the rear timber frame is broken scribbles on blank plaster, no windows, and the back roof edge is ragged at the gable. Front is clean: jetty, shutters, window boxes, dormer, chimney | Good from the front and sides; place its back to a neighbour or retexture (10 credits) |
| Thatched cottage | sq_cottage | Golden Thatch Cottage | 5.5 x 5.3 x 6.5 | 29,999 | 0% | A red-purple smear on the thatch under the dormer at the back; dormer glass dark. Thatch reads as straw, ridge poles crisp | Good; closest to 01-town's thatch |
| Merchant house | sq_merchant_house | The Golden Key Inn | 8.1 x 7.3 x 12.0 | 30,000 | 21% | None seen; back gable and windows designed. Sign is a plain golden key | Good; best of the houses |
| Smithy | sq_smithy | Emberstone Forge | 6.4 x 6.6 x 7.5 | 30,000 | 17% | Shallow: the open front is under a deep roof, so at 35 degrees the hearth and tool rack hide; back is a plain stone wall with the chimney (as drawn) | Good; turn it open-side to the square |
| Market stall | sq_market_stall | Harvest Market Stall | 4.5 x 2.5 x 3.6 | 14,837 | 22% | Back of the awning's stripes soft and smudged; back is a closed plank wall (as drawn). Goods (cheese, apples, cabbages, baskets) crisp | Good; back to a wall or another stall |
| Well | sq_well | Village Well | 2.6 x 2.2 x 3.6 | 12,000 | 10% | None seen; shingles are solid (unlike the rejected community well), rope, crank and bucket all there | Good; ready |
| Statue | sq_statue | Regal Sentinel Statue | 2.4 x 2.4 x 7.0 | 11,958 | 18% | Plinth a cooler grey than the concept's warm stone; plinth back is plain; the king's face is small at 7 m | Good; the 01-town monument |
| Cart | sq_cart | Merchant's Haul | 2.8 x 1.7 x 1.8 | 12,000 | 0% | None seen; wheels, rims, barrels and sacks crisp; shafts rest on the ground | Good; ready |

Against 01-town (sheet): the eight read as one set and as the painting's own buildings, the same warm red tiles,
golden thatch, cream plaster and dark oak. Turntable light is flat studio light; the real judge is the batched
Godot render at roof height with the house-colour mask on.

## Godot import

A Godot already running (the supervisor's batched focus render) ran its `--import` and picked these files up, so
their `.import` files exist. I ran no Godot.

## What's left

- Wiring into towns (buildings thread): `replaces` in meshy.json, or towns.json placement.
- Optional, 10 credits each: retexture the townhouse's back (and the cottage's smear) with Meshy Retexture from
  the concept.
