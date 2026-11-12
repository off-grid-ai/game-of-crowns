# The realm at map zoom (2026-11-12)

From the mid zoom (camera distance 40) out to the painted overview (past 60) and the minimap, read from the code
and batch 7's d40 frame, against art target `docs/art/target/02-realm.jpg` (lands in bold house colours, glowing
borders in the house's colour, contested land striped, castles under big banners, armies with banners on the
roads). The political map's earlier plan is docs/review/political-map.md; this page is what still doesn't read.

References:
- **CK3's map modes:** one flat colour per realm, thick borders between realms, occupied land striped; names sized
  by the realm's size; at the far zoom, the paper map with its own marks.
- **Total War's campaign map:** each army a standing figure under its faction's banner, its move a line with an
  arrow to where it ends; a siege is a ring of tents and a crossed-swords mark over the town.
- **AoE IV's minimap:** player colours on the land, crossed swords where fighting is, the camera's frame.

## Now vs reference vs fix

| What | Now | Reference | Fix (view, behind `--map=v2`, numbers in `realm/data/map.json`) |
|---|---|---|---|
| Borders at d40-60 | The political map exists (terrain.gd `_set_politics`, look.json `politics`) but is **off** by default; at d40 there's no border and no house colour, so the land doesn't say who holds it. | CK3: borders are the first thing you read. | v2 turns the political map on (its wash and border already wait for map height, so the town view stays clean). |
| Borders on the overview | `realm_map.gd` washes each tile in the nearest **baseline** town's colour at 20%: no lines, and the colours are the chronicle's start, not who holds the land now. | CK3's paper map: flat colour, crisp two-tone border. | v2: the wash from the live owners (the mirror's `owners`), stronger (`overview.wash` 0.42), and a border line on every seam: a dark core with each house's colour on its own side. |
| Town names and sizes | Mid zoom: only seats and towns of size 6+ are named past d40 (map_labels `far` = 26 + size·2.5); every name the same 12 px. Overview: dots 2.4 px, names only past zoom 1.8. | CK3, Total War: names sized by importance, all big places named. | v2: names reach farther and grow with the town's size (`labels.far_base`, `far_per_size`, `font_per_size`); overview marks sized by town size, names of towns of size ≥ `named_size` from the whole-realm zoom, decluttered. |
| Armies | Mid zoom: the 3D companies are specks under a small banner. Overview: a sigil square and a number, for a house's companies grouped. | Total War: a banner figure per army, readable from any zoom. | v2: every host in the field (the mirror's new `armies`: a house's companies within two tiles, out of town) is a standard: pole, flag in the house's colour, its sigil, how many men. The same figure on the mid zoom (map_marks.gd) and the overview. |
| Routes | The royal host's route is a dotted line on the ground, readable only near. | Total War: the march as a line with an arrow. | v2: the crown's hosts on the march draw a dashed gold line on the screen to where they're bound, an arrowhead at the end, on both zooms. |
| War and siege | Overview: a thin red ring round a besieged town. Mid zoom: nothing over the town; war only as the (off) red seam. | Total War's crossed swords over a besieged town; AoE IV's swords on the minimap. | v2: a besieged town carries crossed swords in a pulsing red ring (both zooms); the war seam shows with the political map on. |
| Zoom hand-off at 60 | The painting fades in at its zoom 4 (22 tiles tall) over a 3D view that shows about 12, then eases to 2.6: a jump out, then a slide. The 3D labels vanish at once. | CK3: the map mode crossfades at the same scale. | v2: the painting opens at the scale the camera saw (`overview.match`), then eases out; banners, sieges and routes look the same on both sides, so only the ground changes. |
| Minimap | House colours, seats under sigils, pings, the camera's frame. | AoE IV. | Kept: it already reads (batch 9). |

## Not changed here
- Ships at sea and fleets (no fleet data in the view yet).
- Contested-land stripes by occupation: the political map stripes a house that's slipping; occupation is Freeciv's
  owner flip (the flood), which already shows.
- The bridge's `/lore/map` armies (routes_realm.js): kept; v2 draws the mirror's hosts instead so both zooms agree.

## How it's switched
`--map=v2` (or `realm/data/map.json` `version: "v2"`); `--map=v1` for the before shot. Shots: docs/review/batch10-list.md.
