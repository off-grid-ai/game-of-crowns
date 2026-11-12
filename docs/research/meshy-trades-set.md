# Trades set: alehouse, stables, windmill, tannery, dyer made in Meshy to 01-town's finish (2026-11-12)

The last kit trades in Kingsmere replaced the farm set's way ([meshy-farm-set.md](meshy-farm-set.md)): same look,
same pipeline, through the Meshy API. Casebook: "Goods have to walk" and "Each house is a family" (a workplace you
read at a glance). Concepts in [docs/art/trades/](../art/trades/). Files outside git in
`~/code/goc-kits/meshy/trades/<name>/`. Imported (Blender, `realm/tools/meshy_import.py`) as `realm/data/meshy.json`
pieces `ts_<name>`, each replacing its kit component outright: the kit variants are gone from `assets.json`, and so
are the kit tiers only they used (alehouse, tannery, dyer; `stables` stays, the castle bailey builds it).

**Contact sheet: [docs/art/trades/sheet.jpg](../art/trades/sheet.jpg)** (Blender Cycles on the CPU,
`realm/tools/meshy_turntable.py`).

Tags: **SEEN** (looked at in our turntable or measure grid), **VENDOR** (Meshy's API says it).

## Pipeline

1. Concept: `codex exec -i ref/<name>_ref.jpg -- "<style.txt> The asset: <line>" < /dev/null`.
2. Image-to-3D through the API: meshy-7.1, 2k geometry, meshy-7 texture 2K with PBR, remeshed in the task
   (30,000 tris alehouse and stables, 25,000 tannery and dyer, 20,000 windmill). One task each. **VENDOR**
3. Import: no house-colour mask (the square's lesson). Sizes by `height_m`, each about the kit piece it replaces.
4. Work spots: each piece's `work_front` read off `realm/tools/meshy_measure.py` at its final height (metres;
   `across` along the model's +X, as the square smithy's trough shows; `out` from the front, negative inside).
   `own_props` on the stables, tannery and dyer: their trough, hay, racks and vats are modelled, so the trade's
   life lays no kit props over them. The alehouse keeps the kit's benches (people sit on them).

## Spend

- **175 credits: 5 x 35.** Balance about 740 before, about 565 after. Nothing bought. **VENDOR**

## Pieces

Width x depth x height in metres as imported.

| Piece | meshy.json | Replaces | Size (m) | Defects seen | Verdict |
|---|---|---|---|---|---|
| Alehouse | ts_alehouse | alehouse | 7.1 x 7.35 x 8.0 | Thatch a more orange straw than 01-town's paler thatch | Good: tankard sign on its bracket, flower boxes, barrels, glowing door |
| Stables | ts_stables | town_stables | 11.6 x 11.0 x 4.8 | First imported at 6 m tall (14.5 x 13.7 m), far bigger than the kit's 11.6 x 10: now 4.8 m. The paddock fills the front half, so the footprint blocks walkers there too (they stop at its edge for the door and hay) | Good: four open stalls, hayloft door, fenced paddock with trough and hay |
| Windmill | ts_windmill | windmill | 6.8 x 7.8 x 11.0 | Drawn without sails as asked; the kit sails sit on its hub (assets.json windmill.rotor: out -1.7, up 8.1, size 9) | Good: tapering stone tower, thatched cap, stair and sacks |
| Tannery | ts_tannery | tannery | 8.7 x 8.1 x 5.0 | The hide racks are loose parts standing out front (they read, but they sit apart from the house) | Good: lean-to with vats, hides on frames, leather rack |
| Dyer | ts_dyer | dyer | 7.8 x 5.3 x 5.5 | None beyond flat studio light | Good: red, blue and yellow vats, cloth drying on lines, wool basket; the red tile roof matches 01-town best |

**SEEN** for every defect. The real judge is the batched Godot render: `work Kingsmere windmill 4 -15` (the sails
must clear the tower), `work Kingsmere stables 4 -15`, `work Kingsmere alehouse 4 -15`.
