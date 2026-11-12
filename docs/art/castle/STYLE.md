# The royal castle and walls: concept art for Meshy image-to-3D

STANDARDS.md replace list #2: Kingsmere's keep, curtain wall and towers in 01-town's painted stone, replacing the
MegaKit-wall keep and Kenney hexagon turrets built in code (`castle_builder.gd`). They must match the Meshy
gatehouse already in the walls (`realm/assets/meshy/gatehouse`). Crops from [01-town](../target/01-town.jpg) in `ref/`.

Route: as the square set ([square/STYLE.md](../square/STYLE.md)): `codex exec --skip-git-repo-check -i
ref/<name>_ref.jpg -- "<square/style.txt>\n\n<line from pieces.tsv>"`, then Meshy image-to-3D as a shape preview
(`meshy_api.py model … '{"should_texture": false}'`), judged in a turntable, then painted from the concept
(`meshy_api.py retexture`). Roof tiles stay red clay (house colour by roof mask, as meshy.json does); banners are drawn
plain cream off-white for the house colour. The style prompt is `../square/style.txt`, word for word.
