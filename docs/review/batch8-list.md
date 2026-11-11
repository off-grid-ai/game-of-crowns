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
