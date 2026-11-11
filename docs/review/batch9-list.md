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
