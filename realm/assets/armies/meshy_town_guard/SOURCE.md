# meshy_town_guard: the pikemen

Two-handed pikemen (Mac, 2026-11-12), the spearmen's folder: a Meshy body with empty hands (docs/art/army/pikeman_body_front.png) and a separate Meshy pike (pike_front.png, 4.5 m, gripped a third up) carried by the right hand as a prop, rigged by realm/tools/rig/rig_unit.py (rig.json units.pikeman_body), VAT-baked. Sources: ~/code/goc-kits/meshy/army/pikeman_body/, ~/code/goc-kits/meshy/army/pike/pike_prop.glb.

The forward jab at the attack (Pike_Jab_1, Pike_Jab_2): Meshy text-to-motion (realm/tools/meshy_api.py motion, prime,
2.5 s) laid on the Mixamo-skeleton rig task 01a1d057-2d2e-7741-9280-ba4165be0b08, two prompts for a level two-handed
thrust from the right hip at waist height (no lift, no swing); FBX in ~/code/goc-kits/meshy/anims/ and
realm/assets/anims/mixamo/ (ignored). Baked with the body's other clips (rig.json units.pikeman_body).
