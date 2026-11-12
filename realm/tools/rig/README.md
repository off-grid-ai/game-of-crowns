# The soldier rig pipeline

An image-made mesh (TRELLIS) becomes a rigged, baked unit for the massed army. No Mixamo login: the skin
weights are copied from a character we already have, with Blender's Data Transfer modifier, and our own
Mixamo clips play on the result. Headless, on the CPU; no Godot.

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --python realm/tools/rig/rig_unit.py -- <unit_x_trellis.glb> realm/assets/armies/<unit> --bake
```

Options: `--kind man|horse` (guessed from the file name), `--yaw <deg>` (a mesh facing the wrong way),
`--arms <deg>|auto` (how far the source's arms are lowered to the mesh's stance), `--tris <n>`.
Numbers live in `rig.json` (docs/TUNING.md); per-mesh overrides go under `units` there.

What it does: weld and decimate to the budget; scale and stand the mesh on the source character; lower
the source's arms to the mesh's stance, copy the weights (nearest face, interpolated), and carry the mesh
back to the skeleton's rest pose by inverting each vertex's skinning; lay our clips on the skeleton, kept
in place; export `<name>.glb` (mesh, skin, clips); paint `mask.png` (the white cloth, bright and unsaturated,
with steel's thin highlights eroded away); with `--bake`, run `tools/vat_bake.py` for `soldier.glb`,
`offsets.exr`, `normals.png`, `tracks.json`. `report.json` holds what each step measured.

Sources: a man copies from `assets/hero/medieval_civilian_3` (Mixamo skeleton; clips from
`assets/anims/mixamo/*.fbx`); a horse from `assets/cavalry/horse` (its own five gaits).

## Proven (2026-11-11, on the stand-in meshes; no soldier mesh had landed)

- `keep_trellis.glb` as a man: 85,690 -> 5,000 triangles, 2,403 vertices all weighted over 38 bones, arms
  auto 45 degrees, 8 clips; exported 1.85 m tall; Walk moves vertices 0.15 m on average, so the skin
  deforms; bake OK: 6,174 vertices x 447 frames, 8 tracks.
- `house_trellis.glb` as a horse: 77,603 -> 4,999 triangles, 64 bones used, 5 gaits; bake OK:
  6,718 vertices x 139 frames.
- Not yet seen: a real soldier (stance match, weapon and shield weights, the cloth mask's thresholds),
  and none of it in the game.

## Known limits

- Gear is rigid: in the lower arm's share of the mesh, whatever stands further from the arm's line than
  flesh does (`rigid.limb`) goes whole to the hand (by the wrist) or the forearm (a strapped shield), a
  joined piece at a time; or a unit names boxes (`units.<name>.rigid`; the man-at-arms needs them). The
  gear is then cut off the body (faces wholly inside it split away, both openings closed), since TRELLIS
  fuses a shield's back into the chest: the bridge follows the body and the gear never stretches. The
  bake's weld only joins twins with the same skin, so the cut survives it.
- Clips: the sword-and-shield and great-sword packs (`SS_*`, `GS_*`) name their bones `mixamorig1:`;
  they are renamed to ours on import (they played frozen before). A unit can bake its own clips
  (`units.<name>.clips`) and say which plays each part (`roles`, for `data/army.json` meshes.<dir>.tracks).
- Ground: the clips come from other characters, so each frame the hips are moved to put the man's lowest
  point (gear left out) on the ground. A sword may still dip into it (the man-at-arms' death).
- The bake laid each clip on its own NLA track with Blender's default hold: the top track (the last clip)
  covered all the others, so every clip but the last baked as one still pose. Fixed in vat_bake.py
  (2026-11-12); bakes made before then (the knight's) need baking again.
- The bake welds the vertices a glTF splits at UV islands (`"weld"` in vat.json; UVs stay on the faces'
  corners): the keep bakes at 2,403 vertices, `offsets.exr` 8.6 MB for 8 clips (22 MB unwelded; the knight
  is 7.4 MB).
- Horse gaits are baked as authored (no in-place pass: its root bone differs from Mixamo's hips).

## The hook into the army (proposed; army.gd is another agent's)

`army.gd` reads one soldier from `ASSET := "res://assets/armies/knight/"`. For units from this
pipeline:

1. Bake each into `realm/assets/armies/<unit>/` (same four files, plus `mask.png` and the TRELLIS texture
   as `albedo.png`).
2. In `realm/data/army.json`, a `units` table: `{"man_at_arms": {"asset": "armies/man_at_arms", "tracks":
   {"idle": "Idle", "walk": "Walk", "run": "Running", "attack": ["Sword_Attack", "SS_Slash_1"], "block":
   "SS_Block_Idle", "hit": "Hit"}, "team": "mask"}}`; the spike picks a unit per regiment.
3. Track names differ from the knight's (`Walking_A`, `1H_Melee_Attack_Chop`): look tracks up by role
   from that table, not by index.
4. House colour: with `"team": "mask"`, `army_vat.gdshader` multiplies the house colour in where
   `mask.png` is white, instead of the palette rectangles (`team.rects`) the KayKit knight uses.
