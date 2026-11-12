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
   left across it; the gatehouse sits on the curtains' line. Add `--castle-life=on`, a 6 s clip at 0.2 s on
   `castle Kingsmere 5 -5 gate` (5d455446): three folk, a guard first, walk in from the road through the
   passage into the bailey and out again, on the ground outside and the passage floor, never through a wall.
3. **The market cart, no '$'** (`--dressing=on`): `city Kingsmere 4.5 -25`, find the cart by the square. Judge:
   the hanging sign reads as a plain board (a faint bag at most), no dollar sign from any side.
4. **The tavern at 30,000 triangles** (`work * inn 4.5 -25`, then `4.5 -12`): its roofs whole (no rag edges, no
   holes), no grey smoke blob over the chimney (the game's own smoke rises there), the sign and barrels read. It is every
   town's tavern under `--landmarks=meshy` (the tavern's catalogue is swapped whole): check a second seat too,
   `work Goldrock inn 4.5 -25`.

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

## The whole Meshy cast (3790e402, 405a7085, 73c7369e; `--cast=meshy`, before: `--cast=kit`)

Before filming: one `arch -arm64 godot --headless --path realm --import` while no other Godot runs (the cast's 13
new bodies retarget at import), then `-s res://tools/feet_check.gd -- --cast=meshy` and `-s res://tools/mind_probe.gd`.
Each shot twice, kit then cast, the same frame, at roof height or above.

11. **Kingsmere's square** (`city Kingsmere 6 -25`): men and women of several looks (ranger, both farmers,
    townswoman, merchant, stallholder), never twins side by side, in the town's dyes on their own colour garment;
    the crier at the heart; the noble lady among the gentry. Judge: one painted look across the crowd, nobody
    standing out (the lady is the one to watch).
12. **Children at play** (the square's chase, `city Kingsmere 5 -25`, a 4 s clip at 0.2): the boy and the girl
    running, child-sized (about 0.7 of a grown body), never a grown body.
13. **Old folk** (`city Kingsmere 6 -25` by day, a lane of houses): the old man and old woman at doors and on
    benches; feet on the bench in Sitting_Idle (feet_check).
14. **The forge at work** (`work Kingsmere forge 4.5 -25`, then a 24-frame clip at 0.2, with `--landmarks=meshy`
    and with kit): the blacksmith at the anvil on its stump, the second at the bellows by the hearth door pumping
    (Pushing); sparks on the frame the hammer meets the iron, the ring with them (`--sound=v2`). Not at the door.
15. **The mill and the friar** (`work Kingsmere windmill 4.5 -25`, a funeral or `city Kingsmere 6` near the sept):
    the miller at the door, the friar walking.
16. **What's drawn where** (batch 9's forge frame, `work Kingsmere forge 4.5 -25` in winter): `pick 0.373 0.522`
    (the red blob in mid-air), `pick 0.75 0.88` (the grey see-through rectangle), `pick 0.17 0.19` (the inn's
    name under a roof). play.log names each, its mesh, colour and height over the ground: the fixes follow.

## The siege's engines at the wall (e97e07e9; North Star 04-siege; `--walls=stone --castles=kit --siege --wall-demo --camp=on`)

Against batch 9's breach launch frames (`/tmp/goc-batch9`), the same steps. Oblique, roof height or above.

1. **A stone's flight:** `engine 0 3.5 -5`, wait 14, an 8 s clip at 0.2 s. Judge: a thin dust trail follows
   each stone on its arc from the cup to the wall; where it lands on open ground a burst of earth about 2.5
   times the old puff; on the wall, the wall's own dust and falling stones.
2. **The ram at the wall:** `camp 9 -20`, wait 35, a snap, then a 6 s clip at 0.2 s. Judge: the ram has left
   its place in the band, pushed by its two men (Pushing, behind it), and stands at the wall's face, drawn back
   and driven in about every 1.8 s, a burst of dust at each blow and a stone loosed when the wall's wear has
   doomed one. Nothing sunk into the wall or floating off the ground.
3. **The tower against the wall:** the same frame, or `camp 9 -20` turned to the tower's side. Judge: the
   siege tower rolled up to stand against the wall, its men cheering at it.

## The host in the field (018db615, 70552f7f; batch 9 army-line-d12 defects)

Before filming: the cavalry and the Meshy bodies live outside git (realm/assets/armies/cavalry etc., imported on
this Mac). Read the log's `ARMY` lines: `triangles by level`, `muster: n moved`, and the 2 s perf line (fps,
process ms, draws, prims).

11. **The same frame as batch 9** (`--dist=12 --wait=90 --army-spike=6000 --army-shape=line`), then again with
    `--units=kit --army-look=kit --army-lod=off` (the before). Judge: no regiment through a house, orchard,
    haystack or hedged field (the log says how many moved); five looks (guard spearmen, men-at-arms, rangers with
    bows behind, knights, a horse wing on each flank); the crown's red on the men's cloth, not only the flags.
    Perf: the ARMY line's fps and prims against batch 9's 3 fps / 143,492k prims.
12. **Cavalry up close** (`--army-spike=1500 --army-shape=auto --dist=6`): a 4 s clip at 0.2 s as the column
    marches in. Judge: riders sit their horses at every gait (no rider sliding off the back, no legs through the
    flank), the horses' legs move with their walk, no stretching between horse and rider.
13. **At the far zoom** (`--army-spike=6000 --army-shape=line --dist=30`): the lighter levels in. Judge: no
    popping or melting silhouettes as the camera moves (a 3 s clip at 0.2 s while zooming from 20 to 30).
