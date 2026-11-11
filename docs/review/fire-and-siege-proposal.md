# Fire and siege breaches: proposal (Builder 1, 2026-11-11)

Mac: "the magic is in the nitty-gritties." Two items, by proven blocks, judged beside the reference as short clips.
Only the game loop is ours; the look copies Manor Lords and Stronghold (burning), Stronghold and Total War (breaches).

## 1. Fire that reads as fire

**Today:** `scenes.gd _burn` emits soft round dots (towns.gd soft_dot) as flames and smoke; at roof height it's an
orange cloud. No flame shape, no embers, nothing happens to the building.

**Blocks (licences to verify on download; all free):**
| Need | Block | Licence | Fit |
|---|---|---|---|
| Flame and smoke textures | Kenney Particle Pack (flame_01-06, fire_01-02, smoke_01-10, spark_01-07) | CC0 | PNGs; any Godot version |
| Flipbook flames, embers, smoke that drifts | GDQuest's Godot VFX shaders/scenes (their open VFX repo) or a godotshaders.com stylised fire/smoke shader | MIT (GDQuest) / per-shader CC0 or MIT (godotshaders) — **to verify** | GPUParticles3D + a flipbook material; Godot 4 versions exist — **to verify the exact 4.x port** |
| Wind drift | Godot's own particle `gravity` + the realm's wind (weather_fx already has a wind direction) | engine | ours: one read of the wind |
| Scorch on the ground | Godot `Decal` node with a Kenney scorch/smoke texture | engine + CC0 | built in |
| The burnt building | A charred variant per kit house: the same mesh with a dark burnt material + roof removed / beams (Quaternius kit pieces), swapped in after the fire | kit licence (CC0) | through the asset catalogue (one `burnt` variant per component) |

**What it does:** on a sack or razing, each burning house gets a flame sheet up its walls and roof (flipbook
billboards emitted from the house's footprint, not one point), embers, smoke columns that bend with the wind, a
scorch decal; when the fire ends the house stays charred (roof gone, black beams) until the town rebuilds it.
**Owner:** Builder 1 (scenes.gd `_burn`; one `fire.json` for counts, sizes, durations). Burnt variants: Townsfolk
(kit houses, via the asset catalogue).
**Proof:** a 5 s clip of a staged sack (`/test/stage {"sack": city}`) beside a Manor Lords burning-village frame.

## 2. Siege walls that crack and breach

**Today:** a siege is soldiers round a town; walls never change.

**Blocks:**
| Need | Block | Licence | Fit |
|---|---|---|---|
| Wall pieces | Townsfolk's kit castle (Quaternius castle kit) | CC0 | the pieces we already use |
| Pre-fractured chunks | Blender's Cell Fracture add-on (ships with Blender, free), run once per wall piece; export chunks as glTF | tool GPL, output ours | offline, one-time |
| Falling chunks | Godot `RigidBody3D` (Jolt physics, Godot 4.4+, already the default in 4.7) for ~1-2 s, then frozen as rubble | engine | built in |
| Dust | the fire's Kenney smoke particles, grey | CC0 | shared with item 1 |
| Attackers through the gap | the siege's soldiers path through the breach: the town walk map gets the gap as walkable (town_nav rebake for that town) | ours (glue) | existing nav |

**Stages per wall section:** intact → cracked (a crack decal / cracked texture variant) → breached (the fractured
chunks fall, a rubble pile, a walkable gap). The gap stays on the map until the town repairs it (a few seasons).
**One owner of the wall's state:** the bridge (siege.js/campaigns: the siege's real damage per wall section, saved in
the realm state, sent in /world); the view only shows it. No timer in the view.
**Owners:** wall pieces and fractured chunks: Townsfolk (kit castle); wall state on the bridge: Builder 1 (with
Builder 2 if it touches campaigns.js); the view's stages, chunks, dust, and the walk map's gap: Builder 1.
**Proof:** a clip of a staged siege (a test stage hook sets a section's damage) beside a Stronghold breach.

## Order and risk
Fire first (smaller, shared particles); breaches after Townsfolk's kit castle lands. Both behind switches
(`--fire=v2`, `--breach`) until judged; tunables in data; a TUNING line each. Nothing current is removed until the
new one is the default. Downloads go through the asset lane (Mac's yes for each pack).
