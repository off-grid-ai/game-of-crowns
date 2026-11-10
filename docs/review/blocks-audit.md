# Blocks audit: what's hand-built, and the proven block that should own it

2026-11-10. Read-only audit (a separate thread), after Mac: "overall finesse is really poor because there is a lot of hand building, rather than using proven components and systems."

Star counts marked ~ are from memory. Godot 4.7 support is confirmed only where stated.

**Already on proven blocks:**
- LimboAI 1.8.1: battle_ai.gd, siege_ai.gd
- Terrain3D 1.1.0: land3d.gd, forest.gd
- Sky3D 2.1
- Waterways 0.3 and Boujie Water 1.0.0
- AnimationTree: motion.gd

| System | Built today | Proven block for the job | Rough edges traced to our code | Swap cost / risk |
|---|---|---|---|---|
| Villager behaviour and movement | Hand: villagers.gd 1501, town_life.gd 607, on NavigationServer2D | LimboAI behaviour trees (installed, MIT). Beehave 2.9.3 (MIT, 4.7 confirmed) | Fallback to three idles (villagers.gd:419). Hand stuck-timers (449-470). Drills, crowds and builders loop (town_life) | Medium; touches working town life |
| Crowds and travellers | Hand: scenes.gd 1846 | NavigationAgent3D path following and avoidance | Cart parts by magic numbers (scenes.gd:190-209) | Small to medium |
| Animation | Proven: AnimationTree (motion.gd 254) | (none needed) | Moves picked by name | (none) |
| Camera | Hand: camera_rig.gd 404, director.gd 254, cinematics.gd 343, plus `.current` hand-offs in control, interior, hero_view, cinematics | Phantom Camera (MIT, ~2.5k★, 0.11.x for 4.4+) | Five cameras hard-cut. director writes the rig's private `_goal_*` fields | Medium; touches working panning |
| Scenes and map battles | Hand: scenes.gd, fixed-second timelines | LimboAI (already runs battle_ai) | Two battle systems; map battles ignore the ground and the foe | Large |
| Melee | Hand: combat.gd 342, string state machine | LimboHSM (installed) | States can drift from animations | Small to medium |
| Captions and alerts | Hand: ui.gd | No mature block; give it a real queue | Captions dropped while a result is up; only one toast waits | Small |
| UI panels and cards | Hand: ui.gd 3556, theme.gd 179, all in code | Godot Theme .tres, Containers, .tscn scenes | Spacing and sizes hand-tuned per card | Large; touches the approved UI |
| Court and dialogue | Hand in ui.gd | Dialogue Manager or Dialogic 2; poor fit, since lines are generated live | (none) | Not worth it |
| Minimap | Hand: minimap.gd 305 | None mature | (none) | Keep |
| Audio | Hand: soundscape.gd 507 | AudioStreamInteractive (music on the beat), AudioStreamRandomizer (no repeats), .tres bus layout | Music cuts across bars; the same take can repeat | Small |
| Day, season, weather | Proven: Sky3D plus LUT grade | (none needed) | Fine | (none) |
| Terrain paint | Proven: Terrain3D | (none needed) | Fine | (none) |
| Roads | Hand: roads.gd 425, box MultiMesh | Terrain3D control-map painting, or decals | Seams; floats on slopes | Small to medium |
| Rivers | Proven: Waterways | (none needed) | Fine | (none) |
| Forest | Proven: Terrain3D instancer | (none needed) | Fine | (none) |
| Countryside | Hand: countryside.gd 770 | Terrain3D instancer; ProtonScatter (MIT, 4.7 untested) | A second scatter system that fades differently | Medium |
| Towns and houses | Mixed: MegaKit assets, hand layout (towns.gd 1257) | No mature generator | (none) | Keep |
| Portraits | SubViewport bake (Godot's own pattern) | (none needed) | Fine | Keep |
| Save and load | Freeciv saves plus chronicles.js | (none needed) | Fine | Keep |
| Horse gaits | Hand: horse.gd 381 | AnimationTree BlendSpace1D | Gaits switch instead of blending | Small |

## The judge's order (2026-11-10)
1. Villagers on LimboAI: one town, switch off means no change, before/after clips. Goes first.
2. AudioStreamRandomizer for alert and ambient takes, alongside. AudioStreamInteractive waits until 1 lands.
3. Phantom Camera: on hold. The camera works, and it never steals.
4. Caption queue when needed: small, under about 60 lines.
5. The rest are parked until 1-3 are done and proven.
