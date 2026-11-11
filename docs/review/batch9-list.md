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
33. **The crowd's clothes** (batch 8 look2: dark, colourless; 3a593e33): `city Kingsmere 6 -25` and a village at the
    same step. Judge against town-b: warm, varied cloth (madder, woad, weld, cream, russet), about one in six in the
    holder's colour at the crown's seat, fewer in a village; peasants in lighter homespun. Set `cloth.true` false in
    `realm/data/people.json` for the before.
34. **No crowd-check errors** (dca52a35): grep the launch logs for `villagers.gd` script errors: none.

## The UI finesse pass (docs/review/ui-pass.md; --ui=v1 before, --ui=v2 after)

10. **The town at rest, the interface as the player sees it** (`city Kingsmere 10 -3`, `snap ui-town ui`), v1 then v2:
    no camera buttons on the right edge (move the pointer to the bottom-right corner first: `hover 0.97 0.9`), the
    minimap flush to the edge, the date card no wider than about a fifth of the screen.
11. **The chronicle open** (`tap chronicle`, `snap ui-chronicle ui`), v1 then v2: v2 narrow and under half the screen tall.
12. **A town's card not pinned** (the harness's `--town` still, Rosehall), v1 then v2: v2 on the left, narrow, the
    town itself in view.
13. **A toast** (any decree: `town Kingsmere` then a decree button, `snap ui-toast ui` within 2 s), v1 then v2.
Judge each against ui-pass.md's reference column (AoE IV, Anno 1800, CK3).

## The King's decisions in the world (gameplay review #6; switches `--decisions=on`, `--hosts=on`; both off by default until this passes)

Pass each beside North Star 07-unrest and 08-reinforce; a pass turns its switch on by default (`realm/data/decisions.json`
`on`, `realm/data/host_command.json` `on`), a fail takes the promise out of GAME_DESIGN's "within seconds... the result plays
in the world" for that order. Siege camp (`--camp`) and fire (`--fire=v2`) stay with their own items above.
35. **Unrest at a cold house's seat** (`--decisions=on`; `POST /test/stage {"favour": {"<house id>": 20}}` or the house
    coldest in the reign, `city <its seat> 10`): a knot of townsfolk in the square, banners at half-mast; at an ultimatum,
    guards doubled and braziers lit. Judge against 07-unrest.
36. **A feast's lanterns** (`--decisions=on`; a feast decree at a house's seat, `city <seat> 8 -25` within 2 s and at
    +20 s): lanterns round the square and the holder's banners between them, still there a season later.
37. **The levy's table and the royal company at a gate** (`--decisions=on`; a levy at Kingsmere, then
    `city Kingsmere 8`; a garrison stage at a sworn town): recruits in line under the royal standard; the standard and a
    guard at the reinforced town's gate. Judge against 08-reinforce.
38. **Commanding a host** (`--hosts=on`; select the royal standard, march it on a great house's town): the ground ring,
    the glowing banner and the dotted route; a second order the same season says "The King's captains have their orders
    for this season" (the bridge's one order a season); the host reaches the town and lays siege (gameplay review #7).

## The siege as spectacle (#5; 3632faa8, 6d4f395a; `--storm-host=on`, on with `--wall-demo`; siege.json storm_host)

39. **The breach launch again** (`--walls=stone --siege --wall-demo --fire=v2`, the scenario of batch 8's breach):
    before the gap opens, the besiegers' host in line on the camp side (several hundred, their banners up) and fire
    arrows arcing over the wall, a roof or two catching behind it; the engines throwing, stones striking with dust
    (`stone-clip`), the wall cracked, crumbling, open. Then the storm (`storm-clip`, 36 frames): regiments queueing
    into the gap at a run, the front one at blows, the holder's regiments meeting them inside, their banners
    wavering; then `storm-taken`: the holder's regiments running into the town, the besiegers pouring through. No
    camera cut inside any clip (siege_ai no longer moves the camera on a rush). Read the run's fps line: Mac's bar
    is 10 (men 800 + 300 by default; lower `storm_host.men` if it's under).
40. **The field battle in play** (army-ui's field_battle.gd, `--battles=field` on a reign with a fight, Space to
    it): the lines meeting with a visible clash front, banners and standards, a rout that runs.

## Meshy's pieces imported (c26ab7ad)

All seven are through Blender (forge, lumber mill, market, mine, treasury, catapult, guard tower). Run
`realm/tools/meshy_import.sh --godot-import` once before filming shots 19-24 above (only while no other Godot runs).

## The realm's sound v2 (e633dd03; `--sound=v2`, before: without it; record with `--record-audio=<abs path>.wav`)

Every clip in this list can carry its sound: run the launches with `--sound=v2 --record-audio=…` and judge by ear
beside the frames. Reference: Anno 1800's town at street height (close detail, far murmur).

41. **The square, near and far:** `city Kingsmere 4.5 -25`, 10 s, then the same at 14 and 40. Judge: the hubbub
    swells with the crowd and falls away with the zoom; the smith's three blows land on his hammer's strikes; dogs
    bark when they follow someone; nothing repeats the same take back to back.
42. **The yard and the paddock** (`work Kingsmere barn`, `work Kingsmere stables`): cows, sheep and pigs, horses
    snorting, each on its own clock; hens by day.
43. **The mills** (`work Kingsmere mill`): the sails' creak and the wheel's water, by their speed (quiet at night).
44. **A levy marching out** (`{"muster": id}`, `road Kingsmere 5`): the drum at the column's head, the march.
45. **A sack** (fire launch): the roar of a burning house, the crackle as it catches and smoulders.
46. **A siege throw and a battle** (breach launch, `engine`): the engine's creak, the stone's impact; the clash and
    the cheer at the end.
47. **The court:** open, a decree sealed (the bell over the realm), gold spent.
48. **Dawn and night** (`--hour=5.5` and `--hour=23` if the harness has it): the cock at dawn, the owl at night.

## Batch 8b look2's horses, wheat and smoke (80e63489, d2cc3c1d, d1523951)

49. **Horses' coats** (goldrock-stalls, goldrock-fountain: blotched white): the paddock and a cavalry still at
    `--dist=4`. Judge: bay, chestnut, black, grey and dun coats with their own shading, no white patches.
50. **Wheat** (mill-wheat: flat ochre squares): `field summer 0.8` and `field autumn 0.1`, `--dist=4` and 8, a 6 s
    clip. Judge: a field of standing stalks swaying with the wind, gold in autumn, the painted ground barely showing.
51. **Chimney smoke** (goldrock-rings: bright white blobs): `city Kingsmere 14 -22`, a 6 s clip. Judge: thin
    grey-brown threads leaning one way with the wind, not white puffs.
