# Batch 9: shots to film (the dressed town, the square's crowd, the countryside, the knight's new clips)

The next film batch, for whoever runs it (batch7.sh's way: one Godot at a time on a private bridge, every still
and clip together). Each line says what the shot must prove. Add to this list; don't film from it piecemeal.
Every before/after is the same frame twice: the same play file, once with the switch off and once with it on.

## The town dressed in what we own (428968da; `--dressing=on`, numbers in `realm/data/dressing.json`)

References: art targets `docs/art/target/01-town` and `town-composition/town-b` beside each shot.

1. **Kingsmere's square and main street, before/after:** without and with `--dressing=on`, `city Kingsmere 6 -25`.
   Judge: the trodden ground between the houses holds bushes, flowers, ferns, rocks and the odd crate, so no bare plane
   shows between buildings. Nothing sits in a street, a back lane, a doorway or the well's ring.
2. **The forge's door, before/after,** `work Kingsmere forge 4.5 -25`. Judge: an anvil log, a quench barrel and
   bucket, a coal crate, a chain, a whetstone and a workbench, all beside the smith's spot and not on it. The smith,
   the apprentice and the sparks are still there.
3. **The granary or mill, and the tannery** (`work Kingsmere granary`, `work Kingsmere mill`,
   `work <town> tannery`): sacks heaped, crates, drying racks and vats. Each trade reads as its trade at roof height.
4. **A row of house fronts,** `--dist=4`: planters and flower boxes against the walls either side of a door, and
   no door blocked.
5. **A village at mid zoom, before/after** (`city <a size-3 town> 8 -30`): lighter dressing (a third of the crown's),
   so it doesn't read as cluttered.
6. **Nothing floats or sinks:** one low crop (`--dist=3`, tilt -15) along a street edge. Judge: pots, barrels and
   rocks stand on the ground, on a slope too.

## The square's own life (08de3013, a09db4fb, 5c3d1e70; `--crowd=off` for before)

7. **Kingsmere's square, before/after,** `city Kingsmere 6 -25`, wait 10 s, then a 24-frame clip at 0.2 s. Judge
   against town-b: a crier at the well, two beggars at the church step, a pair of guards walking the square's ring
   and stopping to look about, three hounds trotting after people, two pairs of children chasing (the caught one
   turns chaser), knots of gossips. The square is fuller (buyers 2-4 a stall, 5 porters, 2 carts).
8. **The count:** run `realm/tools/motion_probe.sh` twice (before: `GAME_EXTRA="--crowd=off"`) and copy the two
   `MOTION in frame:` lines (people on screen on average and at most) into the review.

## The countryside's year (4144e005, 1327dd42, 65b89302; `--fieldwork=off` for before)

9. **Ploughing:** `field spring 0.15` then a 4 s clip: two oxen and a ploughman walking the furrow, turning at the
   headland.
10. **Sowing and weeding:** `field spring 0.5`, `field summer 0.3`: sowers casting seed, weeders stooping and hoeing.
11. **Harvest:** `field autumn 0.15`, a 6 s clip: reapers stooping with sickles or swinging, binders, the stooks
    rising in rows. Then `field autumn 0.6`: gleaners among the stooks.
12. **A flock:** `flock 0`, a 6 s clip (wait for the move every 25-50 s): the shepherd leading his sheep to the next
    fallow field, the sheep grazing between moves.
13. **The roads:** `road Kingsmere 8`, a 6 s clip: a pedlar with his pack, pilgrims, a spear patrol on the crown's
    road, a messenger at the gallop. A night shot of the same road: only a torchlit patrol or a rider.

## The knight's new clips (c651da09; `realm/assets/armies/knight_v2`, once army-ui wires `army.json`)

14. **Marching and fighting don't repeat:** `--army-shape=march` and `--army-battle=1200 --dist=4`, a 6 s clip each.
    Judge: three walks across a regiment, six cuts, three deaths, no lockstep. Watch for the defects on the CPU
    sheet (`docs/research/knight-clips.md`): feet sliding in Walking_B and Walking_C if their pace isn't matched,
    the diagonal slice passing through the shield.

## Town moods and rulings still unfilmed (c49ee2c6, 7d97840d, 355e710a, 955f4bb9, 8bcd3c42)

15. If batch 8 didn't take them: war, famine, feast and the levy marching out (`POST /test/stage {city, mood}`,
    `{muster: id}`), and each court ruling's answer in its town (`{city, ruling: relief|justice|grant|build}`).
