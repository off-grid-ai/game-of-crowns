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
