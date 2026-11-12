# Farm set: armoury, barn, granary, pen made in Meshy to 01-town's finish (2026-11-12)

The town's working buildings after the square set ([meshy-square-set.md](meshy-square-set.md)), the same look and
pipeline, now through the Meshy API (no browser). Concepts in [docs/art/farm/](../art/farm/). Files outside git in
`~/code/goc-kits/meshy/farm/<name>/` (GLB, `SOURCE.md` with the task id, Meshy's four view thumbnails). Imported
(Blender, `realm/tools/meshy_import.py`) as `realm/data/meshy.json` pieces `fs_<name>`, each replacing its kit
component outright.

**Contact sheet: [docs/art/farm/sheet.jpg](../art/farm/sheet.jpg)** (per row: 01-town crop, concept, our model front
3/4, back 3/4; Blender Cycles on the CPU, `realm/tools/meshy_turntable.py`, a 1.7 m figure for scale).

Tags: **SEEN** (looked at in our turntable), **VENDOR** (Meshy's API says it).

## Pipeline

1. Concept: `codex exec -i ref/<name>_ref.jpg -- "<style.txt> The asset: <line>"`. All four first try.
2. Image-to-3D through the API (`POST /openapi/v1/image-to-3d`, the concept as a data URI): `ai_model` meshy-7.1,
   `geometry_resolution` 2k, `texture_model` meshy-7 at 2k with PBR, `image_enhancement`, remeshed in the task
   (`should_remesh`, triangles, `target_polycount` 30,000 armoury and barn, 20,000 granary, 12,000 pen),
   `multi_view_thumbnails`. One task each, no retries. **VENDOR**
3. Import: no house-colour mask on any piece (the square's lesson: a face-by-face mask out of Meshy's baked atlas
   read as smears on the roofs). Sizes set by `height_m` so each stands about the size of the kit piece it replaces.

## Spend

- **140 credits: 4 x 35** (each task's `consumed_credits`). Balance 1,025 before, 880 after (`GET /openapi/v1/balance`).
  Downloads free. Nothing bought, no plan or setting changed. **VENDOR**

## Pieces

Size is width x depth x height in metres as imported; the kit's is its footprint (`farm_set_probe.gd` prints both).

| Piece | meshy.json | Replaces | Size (m) | Kit's (m) | Tris | Defects seen, first | Verdict |
|---|---|---|---|---|---|---|---|
| Armoury | fs_armoury | armoury | 6.9 x 8.9 x 8.0 | 6.8 x 8.0 | 30,000 | Back is plain stone and plaster with the chimney (clean, as drawn); the spear racks are thin at roof height | Good: shields with the eagle, banner, armour stand and arched door read at a glance |
| Barn | fs_barn | barn | 11.8 x 8.0 x 7.2 | 11.8 x 8.8 | 30,000 | One door leaf hangs a little skew (as drawn); the pitchfork from the concept is lost | Good: open doors with hay inside, hoist beam, bales |
| Granary | fs_granary | granary | 5.5 x 8.0 x 7.0 | 6.8 x 7.9 | 20,000 | Depth includes the steps and sacks; the thatch's back is a touch flatter than its front | Good: staddle stones, steps and sacks |
| Pen | fs_pen | yard_pen | 2.4 x 2.8 x 1.3 | 2.0 x 2.0 | 11,568 | The concept's log trough came out missing (bucket and lean-to are there). First imported at 1.8 m tall (3.3 x 3.9 m), too deep for a crown yard: now 1.3 m, and a yard's thing only stands where it fits (f0ed7cc8, yard_fit_probe.gd) | Good |

**SEEN** for every defect. Turntable light is flat studio light; the real judge is the batched Godot render.
