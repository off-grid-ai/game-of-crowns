# The Meshy cast: how a character comes in, and the first two judged (2026-11-12)

Mac: "replace all of the people on the ground, farmers, townspeople etc., with Meshy characters… just make a really
good experience." The concepts are being made in `docs/art/cast/` and turned into rigged GLBs in
`~/code/goc-kits/meshy/cast/<name>/`, with the Meshy agent's verdicts in `docs/research/meshy-cast.md`. This page
covers the integration: the path is built and tried on the two characters we already have.

## The path

1. **Import, on the CPU:** `Blender -b --python realm/tools/cast_import.py -- <glb> cast_<name> [12000] [cream | hue:lo,hi]`.
   It writes `realm/assets/people/mixamo/cast_<name>/` the way `people.gd` reads a Mixamo body:
   - Mixamo bones renamed (`mixamorig:X` to `mixamorig_X`, the names in `retarget/mixamo_map.tres`).
   - Its own clips dropped: our people play the shared library.
   - Textures capped at 1024 px, the mesh decimated past the budget.
   - A cloth mask: cream cloth like the army's, or a coloured cloth by its hue.
2. **Godot import:** the `.gltf.import` retargets at `PATH:Armature/Skeleton3D` through `mixamo_map.tres`, as every
   Mixamo body does. This needs one headless `arch -arm64 godot --headless --path realm --import`, run only while no
   other Godot runs. **Not run yet:** the one Godot was busy all this round.
3. **List it:** add the member to `realm/data/cast.json` with its sex, the roles it plays and its mask path.
4. **Switch:** `--cast=meshy` (or `on` in cast.json) means a role the cast covers is played by the cast alone, always
   by a body. `--cast=kit` gives the old bodies and outfits, for the before shot. Children, elders and roles the cast
   doesn't cover yet keep the outfits.
5. **Colour:** a cast member's masked cloth takes the town's dyes (people.json cloth, by rank) or the house's colour
   (soldiers), multiplied through the material's detail layer. Skin, leather and steel keep their paint.
6. **Feet:** `realm/tools/feet_check.gd` measures the cast in every clip once it's imported (People.all_bodies). It
   is run with `--cast=meshy`.

## The proof without the GPU

For each character, `/tmp/goc-models/cast_strips.py` plays all 24 of the clips our people use most, 6 frames each,
on the CPU. Each bone is turned from the clip rig's rest as the clip turns it, applied to the cast rig's own rest,
with the hips' travel scaled to the cast's hip height. That is what Godot's import retarget does. Copying the bones'
local turns straight across, as a first try did, left the arms stuck out and the body lifted.

The sheets are `/tmp/goc-models/town_guard_clips.jpg` and `/tmp/goc-models/young_ranger_clips.jpg`. The turntable
beside our townsfolk is in `/tmp/goc-models/meshy_tt/`.

## Verdicts

**Town guard** (rfiser46, CC0; about 10.6k triangles; crimson skirt mask, 8% of the texture): **pass**, as the town
guard (role soldier: gates, walls, the watch, patrols).
- Beside our townsfolk he sits in our look: painted leather, cloth and steel, at the Mixamo bodies' detail.
- Clean in Idle, Walk, Running, Carrying, PickUp_Table, Hammer_Swing, Digging, Pick_Fruit, Planting, Watering,
  Kneeling, Talking, Cheering, Sword_Idle, Praying, Fixing_Kneeling, Pushing, Dance, Yelling, Axe_Down, Milking
  and Drinking.
- Watch:
  - **Sitting_Drinking:** the body leaves the frame after the first frame in the proxy, because the clip has big
    hip travel. It's unproven until Godot imports him. Keep him off the benches until then (soldiers sit only at
    the inn in war).
  - **Waving:** weak (the hand barely raised).
  - **Kneels:** they float a few centimetres in the proxy. People.gd's per-body foot planting corrects that in game
    (feet_check will say).
  - **Look:** the right pauldron is oversized (it's his armour's design).

**Young ranger** (rfiser46, CC0; about 10.7k triangles; green cloak mask, 8.5%): **pass**, as a townsman and
peasant (green hood, leather jerkin).
- He reads very clearly from roof height.
- The same clips are clean, with the same watch items: Sitting_Drinking, Waving, and the kneels' float in the proxy.

**Farmer (m)** (ours, Meshy 7.1 from `docs/art/cast/farmer_m_front.png`; 8.4k triangles; green jerkin mask, hue
0.15-0.33, 9.6%): **pass**, as a peasant (fields, flocks: the farmer, fieldhand, gleaner and shepherd), beside the
ranger. Strips: `/tmp/goc-models/farmer_m_clips_a.jpg` and `_b.jpg` (21 clips; Walking isn't in our library under
that name).
- The straw hat stays on the head through every bend (PickUp_Table, Digging, Planting, Milking, Praying).
- Clean in Idle, Running, Carrying, PickUp_Table, Hammer_Swing, Digging, Pick_Fruit, Planting, Watering, Kneeling,
  Talking, Cheering, Praying, Pushing, Dance, Yelling, Axe_Down, Milking and Drinking.
- Watch: the same as the first two. Sitting_Drinking leaves the frame in the proxy, Waving is weak, and the kneels
  float a little. A wide straw brim may clip a low doorway or a neighbour in a tight crowd.
- Imported (`cast_import.py`, `realm/assets/people/mixamo/cast_farmer_m/`). Its Godot import and
  `feet_check -- --cast=meshy` wait for the next bundled Godot pass.

Neither of the first two is rejected. Neither has a female body, a child or an elder: those wait for the 14 concepts in `docs/art/cast/`.

## Roles to fill as the cast lands (for the Meshy agent)

| Role | people.gd station | Where they work (villagers.gd and works.gd) |
|---|---|---|
| farmer, fieldhand, gleaner, shepherd | peasant | fields (field_work.gd), flocks |
| smith, apprentice | townsfolk | the forge |
| stallholder, buyer, porter | townsfolk | the market |
| crier, gossip | townsfolk | the square |
| priest, monk | clergy | the sept, a funeral |
| guard, levy man | soldier | gates, walls, the muster |
| woman (several looks) | peasant, townsfolk | everywhere |
| child (two looks) | (outfits today) | the square's games |
| noble, lady | noble | the keep, the court |
