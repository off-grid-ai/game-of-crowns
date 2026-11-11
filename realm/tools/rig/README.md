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

- A weapon or shield in the mesh takes the nearest limb's weights, so it bends with the arm. If that
  reads badly: split the weapon off before the copy and weight it whole to the hand bone.
- The bake has about 6k vertices (the knight has fewer) because TRELLIS's UV islands split vertices:
  `offsets.exr` is 22 MB for 8 clips against the knight's 7.4 MB. Fewer clips, a lower `tris`, or a
  re-unwrap bring it down.
- Horse gaits are baked as authored (no in-place pass: its root bone differs from Mixamo's hips).

## The hook into the army (proposed; army_spike.gd is another agent's)

`army_spike.gd` reads one soldier from `ASSET := "res://assets/armies/knight/"`. For units from this
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
