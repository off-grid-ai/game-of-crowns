# Batch 10 shot list

## Meshy's building fixes (0203c0cb, 9bf47954, bb763233, e8108c8c, 115a0e83, 744010da; `--landmarks=meshy`)

Before filming: `realm/tools/meshy_import.sh --godot-import` once (Blender re-imports every piece with its fixes,
then one headless Godot import; only while no other Godot runs). Each shot twice: `--landmarks=kit` (before) and
`--landmarks=meshy` (after), the same frame. Camera at roof height or above (dist ≥ 3.5), oblique.

1. **The catapult's arm swings** (`--walls=stone --castles=kit --siege --wall-demo`): `engine 0 3.5 -5`, wait 14,
   a 6 s clip at 0.2 s. Judge: the arm (its own part now, cup and rope with it) winds back, whips over and the
   stone leaves from the cup at the top of the swing; no arm left behind on the frame, nothing floating.
2. **The gatehouse stands open** (`--castles=kit --walls=stone`): `castle Kingsmere 4 -5 gate`, then
   `castle Kingsmere 8 -5`. Judge: a clear arch you can see through, a shadowed stone passage, no slab or leaf
   left across it; the gatehouse sits on the curtains' line. (Men don't walk through it yet: the castle has no
   walking map.)
3. **The market cart, no '$'** (`--dressing=on`): `city Kingsmere 4.5 -25`, find the cart by the square. Judge:
   the hanging sign reads as a plain board (a faint bag at most), no dollar sign from any side.
4. **The tavern at 30,000 triangles** (`work * inn 4.5 -25`, then `4.5 -12`): its roofs whole (no rag edges, no
   holes), no grey smoke blob over the chimney (the game's own smoke rises there), the sign and barrels read.

Not placed, so not filmed: the market stalls (passed in the turntable, but they're one 7.8 x 6.7 m market block
that needs its place in the square first), the treasury and house (still rejected), the well (cards for shingles).

## The realm at map zoom (9147f986; docs/review/realm-map.md; `--map=v2`)

Each shot twice, `--map=v1` (before) and `--map=v2` (after), the same frame, `--hosts=on` so the crown has hosts
to order. Oblique, the rig's own pitch.

5. **Mid zoom over Kingsmere:** `city Kingsmere 40`, then `city Kingsmere 55`, a snap after each. Judge: house
   colours and two-tone borders read on the land (none at roof height: `city Kingsmere 10` stays clean); every
   town of size 5+ named, bigger towns in bigger type; each host out of town under a standard in its house's
   colour with its sigil and men; nothing over the interface.
6. **A march on the map:** `host 0`, `order march <a town two houses away>`, then `city Kingsmere 50`. Judge: a
   dashed gold line with an arrowhead from the host's standard to the town; it shortens as the host walks.
7. **A siege on the map** (`--siege`, or wait for one): `city <the besieged town> 45`. Judge: crossed swords in
   a pulsing red ring over the town (a 3 s clip at 0.2 s shows the pulse); the red war seam on the border.
8. **The hand-off:** `city Kingsmere 58`, then `wheel 0.5 0.5 3` (out past 60), a 2 s clip at 0.1 s. Judge: the
   painting comes in at about the scale the land showed (v1 jumps out to ~22 tiles tall first), then eases
   out; standards, marches and sieges look the same on both sides; only the ground changes.
9. **The whole realm** (the overview as the game opens, or `wheel 0.5 0.5 6` from 8): Judge against
   02-realm.jpg: each house's land in its colour as held now, a crisp border on every seam, the coast with no
   border, seats under their sigils, big towns named without overlaps, hosts as standards.
10. **No red road at the wide town shots** (look.json politics line 30-38, was 9-22; `--politics=on`):
    `city Kingsmere 30`, `city Kingsmere 50`, `city Kingsmere 60`. Judge against batch 9's kingsmere-30/50: no
    salmon line round Kingsmere at 30, at most a faint one at 50, the border whole (and in the crown's own red,
    not salmon) only at 60.
