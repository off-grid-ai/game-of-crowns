# Batch 9: shots to film

The next film batch, for whoever runs it (batch8.sh's way: one Godot at a time on a private bridge, every still and
clip together). Each line says what the shot must prove. Add to this list; don't film from it piecemeal.

## Meshy's pieces in place (3064606c; switch `--landmarks=meshy`, data `realm/data/meshy.json`)

Before filming: `realm/tools/meshy_import.sh --godot-import` once (Blender re-imports every piece that has landed,
then one headless Godot import pass so the game can load them; only while no other Godot runs), and
`realm/tools/meshy_import.sh --r2` to copy the binaries to R2. Each shot runs twice, `--landmarks=kit` (before) and
`--landmarks=meshy` (after), the same frame. A piece not imported yet shows the kit's building in both: the log line
`MESHY no file …` says which.

1. **The forge** (landed: 4,862 tris, 8.5 x 8.6 x 7.5 m): `work Kingsmere forge 4.5 -25`, then `4.5 -12`. Judge:
   it stands on the ground facing the street (else turn `yaw` in meshy.json), its size beside the townsfolk and the
   houses, the hand-painted look beside the kit's houses, its roof or banner in the holder's colour (6% of its
   faces take it; `mask` in meshy.json if the wrong parts do), the smith at the anvil and the sparks where its
   anvil stands (the work spots are the kit forge's: they may need moving).
2. **The lumber mill** (in place of the watermill): `work Goldrock mill 5 -25`. Judge as 1, and that the water
   wheel stands in the stream.
3. **The treasury** (in place of the guild hall): `city Kingsmere 6 -25` and close. Judge as 1.
4. **The catapult in the siege** (`--walls=stone --siege --wall-demo`): `engine 1 2.5 -18` (the catapult; the
   trebuchet keeps the kit's swinging arm), a 6 s clip. Judge: the crew round it, its stone leaving from its top
   and striking the wall (a Meshy catapult has no arm of its own to swing: say if that reads as wrong).
5. **The guard tower in the siege band** (in place of the parked siege tower): `camp 9 -20`. Judge: it stands on the
   ground at the camp's flank, its blue shingle roof in the besieger's colour.
6. **The whole town**, `city Kingsmere 14 -22`, kit then meshy: does the painted set sit with the kit's houses or
   stand apart? (Mac's call on mixing.)

Not in place anywhere yet: the market (a whole RTS building, not a stall) and the mine (no trade for it); they're
imported for a later place.

## The town dressed in what we own (428968da; `--dressing=on`, numbers in `realm/data/dressing.json`)

References: art targets `docs/art/target/01-town` and `town-composition/town-b` beside each shot.

7. **Kingsmere's square and main street, before/after:** without and with `--dressing=on`, `city Kingsmere 6 -25`.
   Judge: the trodden ground between the houses holds bushes, flowers, ferns, rocks and the odd crate, so no bare plane
   shows between buildings. Nothing sits in a street, a back lane, a doorway or the well's ring.
8. **The forge's door, before/after,** `work Kingsmere forge 4.5 -25`. Judge: an anvil log, a quench barrel and
   bucket, a coal crate, a chain, a whetstone and a workbench, all beside the smith's spot and not on it. The smith,
   the apprentice and the sparks are still there.
9. **The granary or mill, and the tannery** (`work Kingsmere granary`, `work Kingsmere mill`,
   `work <town> tannery`): sacks heaped, crates, drying racks and vats. Each trade reads as its trade at roof height.
10. **A row of house fronts,** `--dist=4`: planters and flower boxes against the walls either side of a door, and
   no door blocked.
11. **A village at mid zoom, before/after** (`city <a size-3 town> 8 -30`): lighter dressing (a third of the crown's),
   so it doesn't read as cluttered.
12. **Nothing floats or sinks:** one low crop (`--dist=3`, tilt -15) along a street edge. Judge: pots, barrels and
   rocks stand on the ground, on a slope too.

## The square's own life (08de3013, a09db4fb, 5c3d1e70; `--crowd=off` for before)

13. **Kingsmere's square, before/after,** `city Kingsmere 6 -25`, wait 10 s, then a 24-frame clip at 0.2 s. Judge
   against town-b: a crier at the well, two beggars at the church step, a pair of guards walking the square's ring
   and stopping to look about, three hounds trotting after people, two pairs of children chasing (the caught one
   turns chaser), knots of gossips. The square is fuller (buyers 2-4 a stall, 5 porters, 2 carts).
14. **The count:** run `realm/tools/motion_probe.sh` twice (before: `GAME_EXTRA="--crowd=off"`) and copy the two
   `MOTION in frame:` lines (people on screen on average and at most) into the review.

## The countryside's year (4144e005, 1327dd42, 65b89302; `--fieldwork=off` for before)

15. **Ploughing:** `field spring 0.15` then a 4 s clip: two oxen and a ploughman walking the furrow, turning at the
   headland.
16. **Sowing and weeding:** `field spring 0.5`, `field summer 0.3`: sowers casting seed, weeders stooping and hoeing.
17. **Harvest:** `field autumn 0.15`, a 6 s clip: reapers stooping with sickles or swinging, binders, the stooks
    rising in rows. Then `field autumn 0.6`: gleaners among the stooks.
18. **A flock:** `flock 0`, a 6 s clip (wait for the move every 25-50 s): the shepherd leading his sheep to the next
    fallow field, the sheep grazing between moves.
19. **The roads:** `road Kingsmere 8`, a 6 s clip: a pedlar with his pack, pilgrims, a spear patrol on the crown's
    road, a messenger at the gallop. A night shot of the same road: only a torchlit patrol or a rider.

## The knight's new clips (c651da09; `realm/assets/armies/knight_v2`, once army-ui wires `army.json`)

20. **Marching and fighting don't repeat:** `--army-shape=march` and `--army-battle=1200 --dist=4`, a 6 s clip each.
    Judge: three walks across a regiment, six cuts, three deaths, no lockstep. Watch for the defects on the CPU
    sheet (`docs/research/knight-clips.md`): feet sliding in Walking_B and Walking_C if their pace isn't matched,
    the diagonal slice passing through the shield.

## Town moods and rulings still unfilmed (c49ee2c6, 7d97840d, 355e710a, 955f4bb9, 8bcd3c42)

15. If batch 8 didn't take them: war, famine, feast and the levy marching out (`POST /test/stage {city, mood}`,
    `{muster: id}`), and each court ruling's answer in its town (`{city, ruling: relief|justice|grant|build}`).
