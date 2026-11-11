# Batch 9: shots to film (batch7-review #1, #3, #7, #10, #15)

One Godot at a time on a private bridge, every still and clip together. Each line says what it must prove. Read
play.log's "settled in … distance … deg down" line after every framing step: it is the ladder's proof.

## The distance ladder (#7)

The camera's floor is 6 (camera.json `floor`; Mac: no close-up realism), so d4 and d6 are one frame by design:
the log now says "under the camera's floor". Batch 7's d14 and d40 went wrong for two other reasons: tilts of -22 and
-20 made the lens skim the land at 10-16 degrees (a far, low view reads as "close"), and Goldrock's d4 framed
Rosehall because a court sitting took the camera (fixed, e87d2394).

1. **Kingsmere ladder at the rig's own pitch:** `city Kingsmere 6`, `city Kingsmere 10`, `city Kingsmere 16`,
   `city Kingsmere 30`, `city Kingsmere 50` (no tilt), a snap after each. Judge: each step visibly further and
   higher; play.log distances 6, 10, 16, 30, 50, pitch rising with distance (about 30 up to 40 degrees down).
2. **The same with the old low tilts** (`city Kingsmere 14 -22`, `city Kingsmere 40 -20`): for the record of why
   batch 7 read backwards; with clarity on, the lens now tips up where roofs block it (the log's pitch says by how much).
3. **Goldrock 6, 10, 16, 30** at default tilt, with a court sitting due: the frame stays on Goldrock (the court
   waits at its place; Space would take you there).

## Settled frames, true clip gaps (#10, #15)

4. **forge and forge-clip** (`work Kingsmere forge 4.5 -25`, then snap and a 24-frame clip at 0.2): the first frame
   already settled (no orbit in frames 1-13); clip frames 0.2 s of game time apart (check a walker's stride between
   frames, or play.log's timestamps).
5. **breach clips** (`breach 4 -25`, 30 frames at 0.2): no cut inside a clip.
6. **army-line-d12** (`--army-spike=6000 --army-shape=line --dist=12 --wait=90`): the army, not the main menu
   (log: "SHOT waiting for the realm" if the title was up).
7. **The breach launch's log**: no `field_work.gd:86` errors (92185fe7). (fire.gd:170's 178 errors are fire's own.)

## Panels and the court (#1, #3)

8. **Film shots without panels**: every breach/siege snap free of the town card, the court card and the chronicle
   (41fabfad), and no court sitting moving the camera mid-film (e87d2394). One `snap name ui` keeps them, to check.
9. **Clarity before/after** (#1): batch 8's shots 8-12 (`--clarity=old` for the before).

## A sack burns where it's seen (#2; 8441a7e8, fire-siege session)

10. **The fire launch again** (`--fire=v2`): `city <sacked town> 6 -25`, stage `{"sack": id}`, then snaps at +6 s,
    +20 s, +45 s and +90 s, and a 30-frame clip from +8 s. Judge: three houses torched at once, spaced apart, in the
    middle of the frame (the burn picks the houses nearest the camera's look point); the fire then goes house to
    house, downwind, one every 3-12 s; smoke columns leaning one way; roofs falling in with a burst of sparks; the
    charred shells left. The run log has no `fire.gd` errors (the spread follows the town when towns.gd rebuilds it).
11. **storm-fire in the breach launch**: after the gap is taken, the town alight in frame (same proof as 10).

## Glow orbs and blob pads (#13; 35ed77ce, ba9f8f56, ae508125, fec1c0e6)

12. **The forge's anvil** (`work Kingsmere forge 4.5 -25`): no glowing ball at the smith's feet; sparks a short burst
    off the anvil each stroke; the forge mouth warm, not blown out.
13. **The bailey's campfire and drill** (`castle Kingsmere 4 -22` or `city Kingsmere 40` as batch 7 framed it): no
    orb beside the fire; the drill's soldiers stand on grass, not brown square pads (`--wear=on`: only walked paths wear).
14. **The feast's bonfire** (stage a feast): flames, not a bright blob.

## The ground and the season (#14; 9d930ee0, 2ff5521d, b863c5ec, abcf6035, feb8da39)

15. **Winter held** (`--season` not given, a winter reign; the fire launch's fire-before): the season the film starts
    in stays for the whole run (no flip to spring mid-shot); the snow has drifts and the ground's texture faintly
    through it, shading on slopes, not a flat white sheet.
16. **The far mountains** (`city Kingsmere 30`): matte rock, no white specular blobs.
17. **Field hedges** (`city Goldrock 16 -20`, `field summer 0.3`): green hedgerows with a few small flowers, no red rings.
18. **A town's watermill** (`work <town> mill`): a watermill stands only on water; a dry town has none.

## Meshy's pieces in place (3064606c, 748f3189; switch `--landmarks=meshy`, data `realm/data/meshy.json`)

Before filming: `realm/tools/meshy_import.sh --godot-import` once (Blender re-imports every piece that has landed,
then one headless Godot import so the game can load them; only while no other Godot runs), and
`realm/tools/meshy_import.sh --r2` to copy the binaries to R2. Each shot twice: `--landmarks=kit` (before) and
`--landmarks=meshy` (after), the same frame. A piece not imported yet shows the kit's building in both.

19. **The forge** (landed: 4,862 tris, 8.5 x 8.6 x 7.5 m): `work Kingsmere forge 4.5 -25`, then `4.5 -12`. Judge: it
    stands on the ground facing the street (else `yaw` in meshy.json), its size beside the townsfolk and houses, the
    hand-painted look beside the kit's, its roof or banner in the holder's colour (6% of its faces; `mask` if the
    wrong parts take it), the smith at the anvil where its anvil stands (the work spots are the kit forge's).
20. **The lumber mill** (in the watermill's place): `work Goldrock mill 5 -25`; the wheel in the stream.
21. **The treasury** (in the guild hall's place): `city Kingsmere 6 -25` and close.
22. **The catapult in the siege** (`--walls=stone --siege --wall-demo`): `engine 1 2.5 -18`, a 6 s clip: the crew round
    it, its stone leaving from its top (no arm of its own to swing: say if that reads wrong).
23. **The guard tower in the siege band** (the parked siege tower's place): `camp 9 -20`.
24. **The whole town**, `city Kingsmere 14`, kit then meshy: does the painted set sit with the kit's houses?

## Batch 7's fixes from the village and mood builder (1ee02a1e, 946b702a, d03deec4, b7d36cae)

Each against its batch 7 frame (`/tmp/goc-batch7`), the same step.

25. **Stables and paddock** (batch 7 stables-clip: horses frozen in all 24 frames), `work Kingsmere stables 4.5 -25`,
    then the same at `--dist=14`: a 24-frame clip at 0.2 s. Judge: horses stroll and drop their heads to graze, near
    and far (anim_lod now moves horses to 40 units and beasts to 22, not 18).
26. **The forge** (batch 7 forge-clip: one arm barely moving): `work Kingsmere forge 4.5 -25`, a 6 s clip: two at the
    anvil, smith and striker.
27. **A levy marching out** (batch 7 levy-clip: a milling knot): `POST /test/stage {"muster": <Kingsmere id>}`, then
    `city Kingsmere 6 -25` and `road Kingsmere 5`, a 20 s clip on each. Judge: 24 in four rows before the sergeant,
    then files of six marching out along the main road one behind the other, kin waving by the well.
28. **War** (`{"city": id, "mood": "war"}`): 16 in four rows in the square, half the stalls unmanned, barricade and
    standards at the way in.
29. **Hunger** (`{"city": id, "mood": "hunger"}`): the dole table at the market with ten in line, beggars at the
    church step, half the chimneys cold, two thirds of the stalls shut.
30. **The road** (batch 7 carts-clip: no one in 28 frames): `road Kingsmere 5`, a 28-frame clip. Judge: at least two
    parties or carts in shot.
31. **The inn** (batch 7 inn: no horses, no tables): `work Kingsmere inn 4.5 -25`. Judge: two horses at the rail, a
    long table in the yard with drinkers on its benches by day.
32. **The windmill and the watermill** (batch 7 mill: flat salmon sails cutting the next roof; hunger-town: a salmon
    wheel): `work Kingsmere mill 5 -25`, a 6 s clip. Judge: canvas sails and a timber wheel with grain to them, and
    the sails turning clear of every roof.

## The fountain (batch 8 review look2; d8f73471, this commit's fountain stone)

25. **Goldrock's fountain and Kingsmere's statue close** (`city Goldrock 3 -25`, `city Kingsmere 3 -25`): the basin in
    the village kit's grey uneven stone, dark still water that catches the sky; no stall canopy over the basin, no
    one standing in the water (dogs, children, the levy's kin all start outside its rim).
