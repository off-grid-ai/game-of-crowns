# Knight v2: clips and the roles they can play (2026-11-12)

**What:** the army's knight baked again with 27 clips instead of 8, so marching and fighting stop repeating.
New unit folder `realm/assets/armies/knight_v2` (VAT: `soldier.glb`, `offsets.exr`, `normals.png`,
`tracks.json`). The old `realm/assets/armies/knight` is untouched. army-ui wires the roles in `army.json`.

**Sources (both CC0, Kay Lousberg):**
- The knight itself and its own 76 clips: KayKit Adventurers 1.0 (`Knight.glb`). The old bake used 8 of
  them; this one uses 22.
- 5 more clips from KayKit Character Animations 1.1, Rig_Medium (Idle_A, Idle_B,
  Melee_1H_Attack_Jump_Chop, Waving, Skeletons_Taunt; 133 humanoid clips in the pack; itch.io
  kaylousberg/kaykit-character-animations, downloaded to `~/code/goc-kits/kaykit-anims`). Licence:
  `knight_v2/license_animations.txt`.

**Skeleton match: yes.** Rig_Medium's 23 bones are all in the knight, with the same names and rest
positions (largest difference 0.0). The knight has 18 more bones: the IK and roll controls (`kneeIK`, `IK-foot`,
`control-heel-roll`...). They don't deform anything, and the packs don't key them. No retargeting was needed.

**Bake:** `Blender -b --python realm/tools/vat_bake.py -- Knight.glb <out> knight_v2.json` on the CPU.
vat_bake.py now takes `actions_from` (the pack's glbs) as a config key. A pack clip whose name the knight
already has is kept as `<name>_pack`, and the knight's own version is the one baked. The bake has 4957
vertices and 878 frames at 24 fps, with `offsets.exr` at about 35 MB (the old knight had 185 frames). The
config is in the table below; the run used `/tmp/goc-models/knight_v2.json`.

## Roles

Frames are `startFrame-endFrame` in `knight_v2/tracks.json`. "Loop" means the clip loops. Pick at random
among a role's clips, and never the same one twice running (the variety-and-reaction rule).

| Role | Clips (frames) | Loop | Notes |
|---|---|---|---|
| idle | Idle (0-25), Idle_A (26-51), Idle_B (52-103) | yes | Idle_B is a long breathing shift, so it reads at rest. |
| ready / guard | Blocking (104-129) | yes | Shield up, standing in the line before contact. |
| walk | Walking_A (130-155), Walking_B (156-181), Walking_C (182-220) | yes | Three paces of march; vary them across a regiment. |
| run | Running_A (221-240), Running_B (241-266) | yes | The charge. |
| attack | 1H_Melee_Attack_Chop (267-292), 1H_Melee_Attack_Slice_Diagonal (293-317), 1H_Melee_Attack_Slice_Horizontal (318-343), 1H_Melee_Attack_Stab (344-382), Melee_1H_Attack_Jump_Chop (383-415), Block_Attack (416-441) | no | Six cuts. Jump_Chop is the big one, rare (about 1 in 8). Block_Attack strikes from behind the shield. |
| block | Block (442-467), Block_Hit (468-493) | Block yes, Block_Hit no | Block_Hit is a blow taken on the shield. |
| hit | Hit_A (494-510), Hit_B (511-531) | no | |
| death | Death_A (532-551), Death_B (552-615), Lie_Down (616-688) | no | Hold the last frame. Death_A falls back, Death_B pitches forward, Lie_Down sinks to the knees and lies on its side (a slow death). |
| cheer | Cheer (689-729) | no | Victory, or the King passing (one clip: the pack's Cheering is the same move). |
| at ease | Waving (730-781), Interact (782-813), Use_Item (814-852), Skeletons_Taunt (853-877) | no | Fidgets between idles. Taunt is a sword brandish at the enemy line. |

Roles for `army.json` meshes.knight_v2.tracks, as `rig.json` units write them:

```json
{ "idle": ["Idle", "Idle_A", "Idle_B"], "ready": "Blocking", "walk": ["Walking_A", "Walking_B", "Walking_C"],
  "run": ["Running_A", "Running_B"],
  "attack": ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Stab", "Melee_1H_Attack_Jump_Chop", "Block_Attack"],
  "block": ["Block", "Block_Hit"], "hit": ["Hit_A", "Hit_B"], "death": ["Death_A", "Death_B", "Lie_Down"],
  "cheer": ["Cheer"], "ease": ["Waving", "Interact", "Use_Item", "Skeletons_Taunt"] }
```

## Proof

The contact sheet `/tmp/goc-models/knight_v2_clips.jpg` has one strip per clip, 8 frames each, posed on the
skinned knight (the VAT's source) over a checker ground and rendered with Cycles on the CPU. Defects found
on it are listed in the report and in the section below.

## Defects (from the contact sheet, every strip read at full size)

Dropped after the first sheet:
- **Skeletons_Death**: the body comes apart. Hands and feet fly off the limbs; it's the skeleton enemy's
  collapse into bones. Replaced by Lie_Down.
- **Cheering**: the same move as the knight's own Cheer, frame for frame.

Kept, with what to watch:
- **Walks and runs play in place** (no root motion; the pipeline wants this). Whether feet slide depends on
  the army moving a man at each clip's own stride. Walking_B and Walking_C take short chibi steps. Match their
  pace in army.json, or they skate.
- **Hit_A** hardly moves. At army height it may not read; Hit_B is the clear one, so weight it higher.
- **Block_Hit** looks almost like Block: the recoil is small.
- **Block_Attack** is a short jab from behind the shield, and reads weakly as an attack. Weight it low.
- **1H_Melee_Attack_Slice_Diagonal**: on the backswing (frames 2-3 of 8) the blade passes through the
  shield and the chest. It's brief, but seen up close.
- **Melee_1H_Attack_Jump_Chop and Skeletons_Taunt** leave the ground (a hop). That's right for them, but don't
  play them in a tight rank.
- **The sword is held out to the side, level, in Idle, Walking_B and Walking_C**, as in the old bake (the
  pack's rest arm). It isn't new.
- **The sheet shows the knight untextured** (grey and orange), because the sheet's render didn't load the
  pack's external texture. The baked VAT is unaffected; it carries positions only, and Godot paints it
  with knight_texture.png.
