# Cavalry: the knight on his barded warhorse

One Meshy model (image-to-3D 7.1, private licence, Mac's account) of the knight riding: docs/art/army/knight_mounted2_side.png,
drawn over the CC0 horse rig's side view. Fitted to that rig (realm/assets/cavalry/horse, license_horse.txt: its skeleton
and five gaits) by realm/tools/beast_rig.py; below the caparison's hem its legs are that rig's own horse legs with their own weights
(realm/tools/rig/mount_legs.py), so they bend at the true knee and hock; baked to vertex animation by realm/tools/vat_bake.py with
realm/tools/rig/cavalry.json. Source files: ~/code/goc-kits/meshy/army/mounted2/.

Rebuilt 2026-11-15 (the fps round) from Meshy's whole `mounted.glb`, welded then decimated to 2,500 triangles (body 2,000, legs 500;
mount_legs.py): the old 8k mesh was torn into 1,747 scraps, so Godot's simplifier stopped at one lighter level (2,627).
Now 2,497 triangles with levels 1,242 and 607. Steps in realm/tools/rig/cavalry.json.
