# The army spike: one page (Builder 1, 2026-11-11)

Target: docs/art/target/03-army.jpg (Warcraft III massed footmen, each house in its colours). Research:
armies-research.md (notes). Go/no-go before any game code changes. Renders go through the supervisor's batch.

## What the spike answers
Can the M5 draw 1,500 / 6,000 / 15,000 stylised soldiers in regiments, animated, each regiment in its
house's colour, at Kingsmere's camera heights (roof, mid, map) at 3024x1964, at 30 fps or better, and does it
look like target 03?

**Bar (Mac, 2026-11-11):** "anything above 10 fps is fine." Go at **≥10 fps at mid zoom with 6,000 men**; then push
the count (15,000, 30,000) and report the largest army that holds 10 fps. Density and the look beside 03 matter
more than frame rate.

## Blocks (all free; downloaded under Mac's standing MIT/CC0 rule)
| Need | Block | Licence |
|---|---|---|
| Animated crowds as one draw per regiment | antzGames Godot VAT plugin (v0.1.6, Godot 4.5+, benchmarked on 4.7.1) + its Blender baker | MIT |
| One soldier, chunky Warcraft-like | KayKit Adventurers (Knight) + KayKit Character Animations, or Quaternius Knight (matches the town's Quaternius pick) | CC0 |
| Team colour | an `instance uniform team_color` in the VAT shader, sharing Builder 2's team_colour mask rule | engine |
| Baking | Blender (installed: /Applications/Blender.app), run headless | free |

## Steps
1. **Fetch** the antz plugin into `realm/addons/` (a git tag, MIT licence kept) and one CC0 soldier pack into
   `~/Downloads/Aldmere/armies/`; say name, source, size.
2. **Bake** one soldier (sword + shield merged) with 8 clips (idle, walk, run, attack x2, block, hit, die) in
   the antz Blender tool, headless; output: a mesh + VAT texture + clip table in `realm/assets/armies/`.
3. **Spike scene** `realm/tools/army_spike.tscn` + `army_spike.gd` (a test aid, not the game): N regiments of
   150 men, each one MultiMeshInstance3D (fixed slot grid, ranks and files), two LODs by distance, team colour per
   regiment (6 houses' colours), regiments marching and wheeling on a loop; the camera at roof, mid and map
   heights over the Kingsmere terrain; prints fps, CPU and GPU ms, draw calls every 2 s. Flags: `--regiments=10|40|100`.
4. **Batch takes** (supervisor's render): counts 1,500 / 6,000 / 15,000 / 30,000 x 3 heights, stills + one 5 s marching clip, beside target 03.
5. **Go/no-go:** go if 6,000 men hold 10 fps at mid height and the still reads as 03; then a one-page plan for the
   game (regiment per Freeciv unit, the skinned duel layer kept up close, Warcraft III command for the royal host).

## Risks
No blending between VAT clips (fine for mass; the skinned layer stays near the camera); the plugin is one
author's (MIT, forkable); Metal numbers unmeasured; KayKit vs Quaternius family must match the town's art pick.
