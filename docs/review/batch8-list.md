# Batch 8: shots to film (the army's finish, field battles)

The next film batch, for whoever runs it (batch7.sh's way: one Godot at a time on a private bridge, every still and
clip together). Each line says what the shot must prove. Add to this list; don't film from it piecemeal.

## The soldiers' painted finish (598a1e45; switch `--army-look=painted`, numbers in `realm/data/army.json` look)

At the camera's closest stop (roof height, about `--dist=3`), low and oblique, `--army-spike=1200 --army-shape=line --army-select=0`:

1. **Before / after, the same frame:** once with `--army-look=kit`, once with `--army-look=painted`. Judge: steel
   reads as steel from the shadow side (no flat grey), the cloth has a darker hem and collar, the feet are grounded,
   the regiment isn't clones.
2. **One close crop per house colour:** set `colours` to `houses` in `data/army.json` (or one run per house) and crop
   one regiment of each: the arms on shield (a roundel, the soldier's left) and chest are crisp, not blurred or
   stretched; the house colour sits in big clean blocks.
3. **A march:** `--army-shape=march`, `--dist=6`, a 4 s clip: per-man variation holds as they move; no swimming paint.
4. **A melee:** `--army-battle=1200 --dist=4`, snapped about 20 s after "BATTLE begins", plus a 4 s clip: steel and
   cloth read in motion; the arms on shields turned toward and away from the light.

Knight now; repeat 1 and 2 on `armies/man_at_arms` and `armies/knight_v2` once their bakes land (same layout:
the boxes in `meshes.<dir>.emblem` and bands in `meshes.<dir>.trim` may need re-measuring with
`realm/tools/emblem_probe.gd`).

## Field battles (5891d912, 5a47b648; the bridge half follows)

5. **The massed battle**, `--army-battle=3000 --dist=10`, a play file: lines formed (~70 s), volleys (+8 s), fronts meet
   (+12 s), the flank (+12 s), waver and rout (+10 s), the field held (+10 s). Judge: two lines facing, arrows arcing,
   the fronts fighting along their length (not a blob), horse on the flank, beaten banners wavering and men running,
   the fallen left behind. Grep `^BATTLE` from the log.
6. **Close at blows**, `--dist=4`, about +20 s after "BATTLE begins", and a 3-6 s clip: cuts, reels, shield blocks.
7. **A battle in play**, `--battles=field` on a reign with a fight in it: framed with Space from the news chip (the
   battle never moves the camera). Judge: the two houses' colours and arms, sized from the men who fought, the
   beaten breaking.

## Clarity: the player sees clearly what he looks at (7ccb0b73, 41fabfad, 065c9c39; Mac: "I can barely see anything")

The same play file twice, once with `--clarity=old` (before) and once without (after; clarity is on by default),
each shot the same frame. Reference: Age of Empires IV and Anno 1800 town cameras, art target 01-town.

8. **The breach frame again** (batch 7's breach launch: `breach 4 -25`, `snap breach-cracked`, and the 30-frame
   breach clip): before, a near house ghosted (dithered away) and smeared across half the screen; after, the lens
   tipped up over the roofs, the near houses solid and sharp. Judge: nothing in the foreground is see-through or
   blurred; the view stays oblique (not top-down).
9. **Any town at roof height** (`--city=Kingsmere --dist=6`, and Rosehall at 6): the colours: roofs and walls in
   their own colours, not washed orange; the far land faintly hazed and softly blurred only past the town.
10. **Every autoplay framing step at its lowest tilt** (`look`, `castle <seat> 4 -22`, `breach 3 -25`, `site inn 0 6`,
    `work Kingsmere forge 4.5`): the lens never inside or behind a building.
11. **Film shots without panels**: the breach launch's snaps: no Rosehall card, no chronicle drawer over the fight
    (the harness opens the besieged town's card to frame a siege; snaps now put it away). One `snap name ui`
    shot keeps the interface, to check that path.
12. **The yard washing**, close by a cottage (`--city=Rosehall --dist=6`, near the edge houses): linen, faded blue,
    madder and wool cloth on the lines, with their weave; no flat salmon slabs. Before: batch 7's breach-clip-08.

## The army's frame rate, measured clean (Mac's bar: 10 fps)

Batch 7's army launch logged fps=3 at 6,000 men (41 regiments, ~3,400 draws, 142M prims), but read whole the log
says the capture was the cost, not the army: 25 readings of 2-4 fps all fell while the harness saved 2400x1380
frames and checks.gd ran its people checks (225 CHECK lines), and the 6 readings after it, the same 6,000 men on
screen at d12, ran 23-36 fps. The men add one pass of geometry: 6,000 x 5,296 triangles = 32M, the log's 110M -> 142M
step (knight and knight_v2 are the same mesh). The other 110M is the realm itself at film quality. The d50 launch
logged no ARMY line at all (it never reached the army). So, before any change to the army's drawing:

13. **Army, no capture:** `--army-spike=6000 --army-shape=line --dist=12`, then `--dist=50`, each with `wait 20`
    before its first snap and `GOC_PERF_PROBE=1`; take fps from the ARMY lines of the uncaptured stretch only, and
    the probe's per-system split (army spike, units, villagers, towns...). Then once with `--knight=v2` and
    `--army-look=painted`, the same. Judge: fps >= 10 with every man drawn; which system owns the process time.
14. **A battle, no capture:** `--army-battle=3000 --dist=10`, `wait 90`, then read the BATTLE fps lines while the fronts
    fight.
