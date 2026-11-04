# Building blocks: what exists, what we stitch, what we write

Surveyed 2026-11-03. Licences were checked against the repos and pages. (?) marks anything still to confirm.

## Bottom line
About 70% of the game exists as reusable open pieces: engine, terrain, sky, vegetation, crowds, pathfinding, all the art except the dragon, world generation, names, heraldry, text generation, and well-known formulas for plague, famine and unrest.
The remaining 30% is ours to write, and it's the soul of the game:
1. the **simulation brain** (how kingdoms live and react)
2. **narrative control** (how you steer the story)
3. the **continuous zoom** from the realm down to a building interior.

There is **no open-source WorldBox** to fork.

## Proposed stack

| Layer | Pick | Licence | Notes |
|---|---|---|---|
| Engine | **Godot 4** (GDScript) | MIT | Native Mac app that can run persistently. Most game plugins of any option. GDScript avoids installing .NET |
| Starting point | godot-open-rts (lampe-games) | MIT | Working 3D RTS: camera, selection, building placement, navmesh. Check whether to fork it or borrow parts |
| Terrain | Terrain3D (TokisanGames) | MIT | LOD terrain, texture painting, foliage instancing |
| Sky, day/night | Sky3D (TokisanGames) | MIT | Sun, moon, clouds, fog |
| Vegetation, props scattering | ProtonScatter | MIT | |
| Weather | TCA_Weather_System | MIT | Young project; evaluate before relying on it |
| Crowds of villagers | Godot Vertex Animation Textures plugin (antzGames) | MIT | Thousands of animated people, rendered cheaply |
| Pathfinding | Godot NavigationServer3D (built in) | MIT | Add flow fields for big crowds |
| Fire, smoke | GPUParticles3D (built in) | MIT | |
| **World seed** | **Azgaar Fantasy Map Generator** JSON export | MIT | States, cultures, religions, towns, provinces, routes, markers, diplomacy |
| Names, heraldry | Azgaar name-bases and emblem generator | MIT | |
| Buildings | **Quaternius Medieval Village MegaKit** | CC0 | Walls have inside faces, so the cut-away interior view works. Free tier; Pro is $9.99 |
| Interiors, props | Quaternius Fantasy Props MegaKit | CC0 | Free tier; Pro is about $9.99 |
| Nature | Quaternius Stylized Nature MegaKit | CC0 | Free |
| People | Quaternius Universal Base Characters + Fantasy Outfits | CC0 | One shared rig for all characters |
| Animations | Quaternius Universal Animation Library 1+2, KayKit Character Animations, Mixamo for gaps | CC0 / Mixamo terms | Farming, hammering, digging, combat, death covered; praying and chopping come from Mixamo |
| Animals, monsters | Quaternius Animated Animals, Ultimate Monsters; KayKit Skeletons | CC0 | |
| Skies, textures | Poly Haven, ambientCG | CC0 | |
| Chronicle text | Tracery (or a GDScript port) | Apache-2.0 | "In the winter of year 12, Lord X ..." |
| Authored scenes | ink (inkgd for GDScript (?)) | MIT | Optional |
| Kingdom personalities | Unciv `Personalities.json` *pattern* | MPL-2.0 | Re-encode the weights in our own format; don't copy the file |
| Formulas | SIR plague, Malthusian harvest/storage, Turchin structural-demographic unrest, Sugarscape migration | Public science | Freeciv illness and Widelands production chains as reference numbers only (GPL) |
| Placeholder art | Kenney Castle + Fantasy Town kits | CC0 | Already downloaded to `assets/kenney`. Too toy-like for the final look |

Art budget: **about $25**, or about $45 with the Quaternius Source tiers (shaders and Godot projects).

## Gaps (nothing good exists)
- **Hero dragon** (rigged, with a flying animation): buy or commission. The free ones are low-poly or have unclear licences.
- Direwolf (scale up the wolf), giant, kraken: make do with existing models or buy.
- **Zoom from the whole realm down into a building interior:** no library does this on any platform. Our own LOD and streaming code.
- **Simulation brain:** our own code, built from the formulas and patterns above.
- **Narrative arcs** (you set an intent and the world bends toward it): our own design. Storylet pattern (preconditions, salience, effects), plus "story sifting" (Felt/Winnow, read for ideas only) to pick what's chronicle-worthy.

## Avoid
- GPL/AGPL code inside the game (Widelands, Freeciv, 0 A.D. engine, Veloren, citybound): read these for ideas only.
- 0 A.D. art: its share-alike licence would spread to our game's art.
- Synty: $350, a restrictive EULA, and the flat low-poly look isn't any better than Quaternius.
- Paradox event content, and GoT data from An API of Ice and Fire (the data belongs to GRRM).
