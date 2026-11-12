# Ground truth: who owns where a body may stand (12 November 2026)

Three facts players notice, each owned once. Guards: `realm/tools/ground_truth_probe.gd` and
`bridge/tools/damage_probe.mjs` (run both on every change to these files).

| Fact | Owner | Block | Replaced (deleted) |
|---|---|---|---|
| What stands in a town's way | What is set down, read off its geometry: `realm/scripts/nav_ground.gd` | Godot's NavigationServer2D bake (`town_nav.gd`) from those outlines | Per-file footprint rectangles: town_life's Life lists, the feast's, dressing's crates (b24bc2a1; f7ca6b46 for the walk maps) |
| Where rivers run, and where they are crossed | The drawn courses, `realm/assets/maps/rivers.json` (`bridge/tools/azgaar_rivers.py`) | Freeciv river extras from those courses (`azgaar_world.py --rivers`); Freeciv's Move_Bonus effect for wading; roads' fords in the road graph | Freeciv's own discharge cut over Azgaar cells; rivers speeding hosts (a3b7cf8b) |
| Which houses stand burnt | The bridge's damage fact, `bridge/damage.js` (`meta.damage[city]`: burnt share and kindled homes) | Freeciv/bridge save; the view's awareness mirror | fire.gd's session-only lists of arrow-lit and sack-lit houses (79aafe9f) |

- **Walk.** `terrain.walkable(x, z)` (dry land, or a ford where a road crosses a river) is the one answer for water.
  Town walk maps (`town_nav._water`) and fight grounds (`army_ground.gd`) shut every cell it refuses.
- **Planner's record.** `towns.gd` still keeps a `footprints` list: its plot record for laying lanes and plots and the
  camera's roof heights. It is not read for walking or standing; nothing else may write one (the probe checks).
- **Open.** A ford has no look yet (no bridge model in our kits). Overland paths with no road between two places
  (`terrain.land_path`, Freeciv-tile A*) still cross a river anywhere. A new realm is needed for the new river tiles.
