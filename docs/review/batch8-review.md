# Batch 8 review: judged launch by launch against the art targets

Running from e5227195, with the clarity fixes. Frames are in `/tmp/goc-batch8`, contact sheets in
`/tmp/goc-batch8/review/sheets/`, and the best frames in `/tmp/goc-batch8/review/best/`. Mac's bar: a shot passes
only if it would clear its concept in `docs/art/target` at 100%. This file grows as each launch finishes.

## Against batch 7 (what clarity bought)

- **Fixed in frame:** no ghosted near houses, no near blur, and no card or chronicle over the shots in look2.
  The colours are much truer (tiles, stone, green grass, house banners in yellow and red). The square, its stalls,
  the crowd and the castle gate can be seen at last.
- **New and serious:** the camera now looks nearly straight down (about 55-65 degrees) in every town shot, and no
  sky or horizon shows. The rig's sight check (camera_rig.gd `_tipped`, camera.json `clarity.liftStep`/`liftTries`)
  keeps lifting the pitch until the roofs clear. That breaks the low oblique view the project requires (01-town is
  about 30-35 degrees). The steps that ask for -12 (street height) come out top-down too.

## look2 (13 frames, 9 script errors: villagers.gd:1106 `_who`)

| Shot | Verdict | Defects |
|---|---|---|
| goldrock-rings | FAIL (best of batch 8 so far) | Gate, curtain wall, square and stalls all read, with no ghosting. But it is near top-down with no sky. It asked for d14 and got about d6 (log cam_dist 6), so the ring streets aren't shown. The castle banners are plain yellow cloth with no arms. A roof cuts the lower edge. |
| goldrock-plots | FAIL | Nearly the same frame as goldrock-stalls (difference 6.5/255). No plots in frame, only the square. |
| goldrock-stalls | FAIL | Stalls in rows (good). The fountain basin is flat, untextured lavender plastic. A stall canopy stands over the fountain's water. A pinto horse has over-bright white blotches. |
| goldrock-fountain | FAIL | Crisp, with real life: arms banners, riders, a cat, a running man. Asked for d2 at -18 and got the same top-down d6 frame. Same basin and canopy defects. The crowd wears dark, colourless clothes. |
| goldrock-lanes | FAIL | A blurred thatch roof crosses the lower left corner. Otherwise the same square again. |
| goldrock-street-height | FAIL | Asked for street height (-12); got top-down. The same frame as the others. |
| kingsmere-stalls / -yards / -statue / street-height | FAIL | Four near-identical frames (difference 2-11). The square's stalls form a ring (good), and the crowd is dense but dark-clad. The King on his column reads as a small figure on a stack of crates. A figure stands inside the basin's water. No washing yards in frame. Street height comes out top-down. |
| kingsmere-lanes | FAIL | Clear and lively: a crowd at the stalls, sacks, a cart, a horse. Top-down. The earth lanes read. A tree crown blurs the lower right. |
| kingsmere-orchards | FAIL | Wider (d18 honoured more), the castle and square visible. No orchards in frame. Mostly roofs. |
| mill-wheat | FAIL | A tree crown at the lens fills the middle third with black-shaded leaves. The windmill's sails are still flat, untextured salmon. No wheat field in frame. |

### Top defects so far (ranked)

1. **The camera lifts to near top-down** in every town shot, with no sky. Owner: camera_rig.gd `apply`/`_tipped`, camera.json clarity (liftStep 2.5 x liftTries 14 allows +35 degrees). Cap the lift near the oblique band, and come in short of the building first.
2. **The distance and tilt steps are ignored**: cam_dist stays 6 for d2, d2.5 and d3.5 asks, and 8 near-duplicate frames come out. Owners: autoplay.gd `_frame_city` (line 494), the camera_rig.gd distance floor 6.
3. **Flat untextured surfaces**: windmill sails (assets.json rotor `town/windmill.glb` sail) and the fountain basin (assets.json square_statue / Kenney basin material).
4. **Tree crowns at the lens** (mill-wheat, lanes): trees don't dissolve or move the camera. Owners: forest.gd and realistic.gd (tree fade), camera_rig.gd sight check (trees not counted).
5. **The crowd is dark and colourless**, with no house colours (01-town has red and cream clothes). Owners: people.gd and villagers.gd cloth; data/people.json.
6. **Pinto horse blotches**: horse.gd COATS multiplies the bay texture past 1.0.
7. **Square dressing collides**: a canopy over the fountain, and a man in the water. Owners: towns.json market and centre placement, town_life.gd paths.
8. **villagers.gd:1106 `_who`** script errors (9).

## Status

The supervisor stopped batch 8 after look2 (00:49) because of the top-down camera. army-ui is fixing the sight check. The rerun goes to `/tmp/goc-batch8b` and will be judged here.

## 8b (rerun with camera fix 7be7e133, tilts for 30-35 degrees; `/tmp/goc-batch8b`)

Sheets: `/tmp/goc-batch8b/review/sheets/`. Best frames: `/tmp/goc-batch8b/review/best/`.

### look2 (13 frames, 0 script errors)

**Camera check: fixed.** play.log's settled pitches are 13-37 degrees down, so nothing is top-down. Every distance
lands where asked: d14, 6, 3.5, 2, 8, 18, 4.5 and 2.5. No two of the 13 frames are duplicates (every pair differs
by more than 12/255). Sky and walls show at the low tilts, and the crowd now wears coloured clothes (red, green,
blue, ochre). This is the first batch whose town frames read against 01-town.

| Shot | Verdict | Defects |
|---|---|---|
| goldrock-fountain | FAIL (best town frame yet) | Gate, curtain wall, banners, stalls, a busy crowd and riders, at a true oblique. Two bare poles (a mast and a spear-like shaft) stand in the middle foreground. The fountain's centrepiece is a stack of grey blocks, not a statue. The wall banners carry no arms. The horse coat is still blotched. |
| goldrock-stalls | FAIL | A good square. A big thatch roof fills the left third. A pinto rider stands in the foreground. |
| goldrock-street-height | FAIL | It reads well. The same pinto rider is at the bottom, and a roof edge cuts the left. |
| goldrock-plots | FAIL | A roof fills the lower 40%. No plots are framed. |
| goldrock-lanes | FAIL | Foreground roofs fill the lower half. The lanes are only seen between them. |
| goldrock-rings | FAIL | The d14 overview reads: walls, the square, roofs. It's dense but the rings aren't clear, chimney smoke puffs are bright white blobs, and there's no horizon. |
| kingsmere-stalls | FAIL | Lively and colourful. A black-shaded tree crown fills the lower left quarter. |
| kingsmere-statue | FAIL | **Ghost:** a see-through, dithered red stall and its people sit in the middle of frame. The King on his column reads as one more standing man, hidden behind the stalls. A guard is cut by the lower right edge. |
| kingsmere-yards | FAIL | Readable square and crowd. A red roof slab cuts the lower left. No washing yards in frame. |
| kingsmere-lanes | FAIL | Good earth lanes, crowd and tower. A blurred roof crosses the lower edge. |
| kingsmere-orchards | FAIL | The d18 whole-town view works: castle, square, the house ring. No orchards in frame, and it's very busy with roofs. |
| mill-wheat | FAIL | The mill and the wheat plots are in frame at last. The wheat is flat ochre squares with no stalks. The windmill's sails can't be seen behind the trees. |
| street-height | FAIL | A ghosted house runs down the left edge. The square and crowd are fine. |

**Top look2 defects (8b):** (1) foreground roofs and tree crowns take a third to a half of 6 of 13 frames: the
camera still looks over the nearest roofs, not past them (camera_rig.gd sight check: count trees, prefer yaw).
(2) The ghost remains at short distances (kingsmere-statue, street-height): the clarity fade (camera.json
clarity.fade, team_colour.gdshader). (3) The squares' centrepieces don't read: a stack of blocks at Goldrock, and the
King sized as a man (assets.json square_statue). (4) Stray poles in the Goldrock square. (5) Horse coat blotches
(horse.gd COATS). (6) Flat wheat squares (field crops). (7) Bright white smoke blobs (hearths.gd, chimney smoke).

### centre (3 frames, 0 script errors; pitches 15, 22 and 26 degrees, distances 2, 3 and 5 as asked)

| Shot | Verdict | Defects |
|---|---|---|
| centre-grief | FAIL | **No grief reads.** The same busy market as a calm day: open stalls, a colourful crowd and no candles at the rim that you could see. The see-through, dithered red stall sits in the middle again, just as in look2's kingsmere-statue. The King on his column reads as a standing man. Winter: the ground is flat, untextured white snow, yet every roof is bare. |
| centre-feast | FAIL | The feast reads: bunting, long tables and a crowd round the column. A huge near roof fills the lower-left quarter, and a black-shaded tree crown sits beside it. The centrepiece is a man on a stack of blocks. |
| centre-feast-wide | FAIL (best frame of 8b so far) | Bunting, tables, dancers, the bonfire ring and the stalls together at 26 degrees. The bonfire ring is unlit: no flames at a feast. Roofs fill the bottom and left edges. Snow lies flat white on the ground with none on the roofs. A news toast sits in the lower left. |

**Centre defects:** (1) a grief mood that looks like any market day: town_life.gd `_moods`, data/moods.json grief
(shut the stalls, thin and darken the crowd, light the candles). (2) The near-camera stall dither persists at d2-d3
in the square: the clarity fade or the stall material (team_colour.gdshader fade_gone/solid). (3) An unlit bonfire at
the feast: towns.json centre bonfire, fire.gd hearth. (4) Winter has no snow on the roofs and flat white ground:
terrain.gd and ground.json snow, team_colour or roof snow. (5) Foreground roofs at the short distances: the camera_rig.gd
sight check.

### square-before / square-after (26 frames each, 0 errors; 32 degrees at d6 and d4.5)

| Shot | Verdict | Defects |
|---|---|---|
| square-before / square-street-before | FAIL | A lively, readable square with a colourful crowd, stalls in a ring and the King's banner on its pole. A dark red roof slab fills the lower-left quarter. The column's centrepiece is a stack of grey blocks with a man on top. The inn's front glows blown-out white-hot. Even with `--crowd=off` the square is full. |
| square-after / square-street-after | FAIL | The difference is hard to see. More strollers, and three boxy black-and-white cows walk through the middle of the market, which breaks the square. There's no crier, beggars or dogs you could pick out. Same roof slab and blown-out inn. Clips: the camera holds steady and people move. Frames are still about 1 s apart (fixed after 8b in bbb6aa3b). |

### castle (34 frames, 0 errors)

| Shot | Verdict | Defects |
|---|---|---|
| castle, castle-walls, castle-gate, castle-breached | FAIL | The camera sits in the bailey against a tower: one flat stone wall fills the right half, and no castle silhouette, walls walk or gate front ever shows. The bailey is flat white snow. Nobody is on the walls. castle-breached is the same frame as castle: the staged wear doesn't show. guards-clip: the same tower and five figures at a fire. |

### fields (107 frames, 0 errors)

| Shot | Verdict | Defects |
|---|---|---|
| field-plough, -sow, -weed, -reap, -glean, plough-clip, reap-clip | FAIL | **All the same frame**: the step picks "field 0 of 778" at (105.5, 188.8), a plot inside Kingsmere, so the lens sits in a ghosted house. No field work is seen. |
| fields-wide | FAIL | Roofs of Kingsmere. No fields. |
| flock / flock-clip | FAIL | Sheep in a fold beside a wheat patch and a hut: the only countryside frame. A roof cuts the lower right, a white-flowered hedge ring looks pasted on, and the shepherd can't be seen. |

### breach (156 frames, **3306 script errors**: 3238 x siege_ai.gd:612 `_go`, a freed body assigned to a typed variable; 65 x scenes.gd:1142)

| Shot | Verdict | Defects |
|---|---|---|
| siege-camp | FAIL | The wall and the camp are in frame at last (camera fixed). Salmon untextured palisade stakes and pink tent slabs run across the middle. The engine can't be seen behind a house. |
| breach-cracked, breach, storm-taken, storm-fire | FAIL vs 04-siege | The storm host stands in dense blocks under crown banners, close to 03-army's density (progress). But the blocks never move in any frame. The wall shows one small stepped notch, not a breach. No one storms through and the town never burns. The salmon palisade and the pink tents fill the lower third. |
| engine, stone, breach, storm clips | FAIL | Nothing moves across 151 frames apart from one stone in flight: the storm AI is dead (siege_ai.gd errors). |

### painted-march / painted-melee (21 frames each, 0 errors; note: no `--army-colours` switch, so per-house crops weren't filmed)

| Shot | Verdict | Defects |
|---|---|---|
| painted-march | FAIL vs 03-army | A long double column under red standards beside a farm. The soldiers are chibi men with round grey helmets and glowing orange shield bosses (the boss is emissive, which reads as a lamp). All one kind. Not 03-army's mixed, dense blocks. It does march (clip). |
| painted-melee | FAIL | Two thin lines far off across a snowfield. No contact, no melee in any frame. Two-thirds of the frame is empty snow and sea. |

### battle (6 stills) / battle-close (31) / battle-play (1), 0 errors

| Shot | Verdict | Defects |
|---|---|---|
| battle-1 ... battle-6 | FAIL | The lines read as grey strings at the frame's edges, with a lake filling the middle. Volleys, the fronts meeting, the flank, the rout and the held field are all unreadable at this framing: the six frames look nearly alike. |
| battle-close / battle-clip | FAIL | Asked d4; the armies are far off at the top right. A frozen lake and snow fill 80% of the frame. Nobody is at blows. |
| battle-in-play | FAIL (but real fire) | Space jumped to the latest news, a burning town, not a battle. **Fire now reads**: tall shaped flames, charred roofs, smoke. Against 04-siege, though, the nearest fire is a huge blotchy orange mass at the lens, and the smoke is white cotton balls. |

### hosts (3 frames, 0 errors)

| Shot | Verdict | Defects |
|---|---|---|
| host-selected, host-route, host-march-click | FAIL | All three frames are identical. The order failed (`no way over land to Eaglehaven`). There's no gold ring, lit banner, command card or route line, just one standard and a figure in an empty field, with a black-shaded tree crown at the lens in the lower right. |

### rain (27 frames) / snow (2 frames), 0 errors

| Shot | Verdict | Defects |
|---|---|---|
| rain-close / rain-clip | FAIL | No rain to be seen, no wet roofs, no puddles, people out as usual. A white light smear lies across the lower right. |
| rain-square | FAIL | Good square life with house banners, but no weather. Grey-blue bowls scattered on the cobbles. |
| rain-town | FAIL | A one-line rumour ("They say thin soup and thinner bread...") runs across the whole screen under the town's name. No rain. |
| snow-close | FAIL | Snow on the ground only: every roof is bare. A big roof fills the lower left. |
| snow-town | FAIL | A good whole-town oblique with walls, towers and the square. The same bare roofs, flat white ground and rumour line across the middle. |

### night (4 frames, 0 errors)

| Shot | Verdict | Defects |
|---|---|---|
| night-inn | FAIL | Kingsmere has no inn ("none (the town has: armoury, stables, ...)"), so the step fell back to a 124-unit map view with territory tints. |
| night-road-inn | FAIL | Broad daylight: night isn't applied here. The Last Lantern stands small among the pines. |
| night-castle-gate | FAIL | It reads as night (fire glow, silhouettes), but the ground is a flat blue sheet, the gate is dark, and the figures are black shapes. |
| night-road | FAIL | A sunset sky over dark houses. It reads as dusk, not night. No lit windows to be seen. |

## 8b top 15, ranked by how much they hurt what the player sees

(Fixed since 8b started = a commit after 66f64448, so these still need proving on film.)

1. **The siege storm never happens**: 3238 errors at siege_ai.gd:612 (`_go` assigns a freed body), and the host blocks stand frozen. siege_ai.gd, scenes.gd (storm mass, 3632faa8).
2. **The fields launch films the inside of a house**: the `field` step frames "field 0", a plot inside Kingsmere. autoplay.gd field step, field_work.gd field order (choose fields outside the town).
3. **The battles don't read**: grey strings at the frame's edges round a lake, d4 shows the armies far off, and no clash or rout is seen. army_spike.gd and battle_ai.gd battle framing (`--dist` not honoured).
4. **Commanding a host shows nothing**: the order failed (no land route to the war town), no ring, card or route, identical frames. host_command.gd, the bridge host order, batch8.sh target choice.
5. **Untextured salmon and pink pieces persist**: the siege palisade and camp tents, and the windmill sails. scenes.gd and siege.json camp, assets.json rotor.
6. **Foreground roofs and tree crowns fill a third to half of town frames**. camera_rig.gd sight check; **fixed after 8b: 46aefe45** (lower third kept clear).
7. **The castle shots are a tower wall**: no silhouette, no guards on the walk, no visible breach. The autoplay.gd castle step framing; castle_builder.gd and castle_life.gd; the staged wear doesn't show.
8. **Ghost dither at short range** (centre-grief, kingsmere-statue, street-height). **Fixed after 8b: 46aefe45.**
9. **Weather doesn't read**: no rain, wet roofs or puddles; snow on the ground but never on the roofs; flat white ground. weather_fx.gd, weather.json, terrain.gd and ground.json snow.
10. **Night is inconsistent**: daylight at the road inn, a fallback map view at night-inn (Kingsmere has no inn), a flat blue ground. look.gd hour, autoplay.gd work fallback, batch shot list.
11. **Moods**: grief looks like a market day and the feast bonfire is unlit. **Fixed after 8b: e4f6ad59.**
12. **The painted soldiers are far from 03-army**: one chibi kind, glowing orange shield bosses, a thin column; the melee shot has no contact. army.json painted look, army_spike.gd framing; no `--army-colours` switch yet.
13. **A rumour line spans the screen under the town's name** at town distance (rain-town, snow-town). The town label's whisper line (towns.gd label; text from chatter.gd or the bridge): cap its width or hide it beyond roof height.
14. **The square centrepiece doesn't read** (a stack of grey blocks; the King sized as a man). assets.json square_statue; **monument pieces staged after 8b: 93b0461c, not imported yet.** Also the blown-out inn front, a hot interior light (works.gd / towns.gd inn light).
15. **The square's life is muddled**: crowd-on and crowd-off barely differ, boxy cows walk through the market, and clip frames were 1 s apart (**fixed after 8b: bbb6aa3b**). town_life.gd crowd roles, animals.gd herd paths.

**Fixed after 8b, still to film:** 46aefe45 (lower third clear, ghosts), e4f6ad59 (grief, bonfire), a928582a (notices hidden in film snaps),
aea5d79e (no bare pole, feast bunting), 80e63489 (horse coats), d2cc3c1d (swaying wheat), d1523951 (chimney smoke),
3a593e33 (crowd colours; 8b's crowd is already colourful), 857abcb4 (house arms on the castle banners), 6d135651 (square rim
dressing), bbb6aa3b (true 0.2 s clip frames).

**Best frames (8b):** `/tmp/goc-batch8b/review/best/`: 01-goldrock-fountain, 02-centre-feast-wide, 03-square-street-after,
04-rain-square, 05-snow-town, 06-painted-march, 07-battle-in-play, 08-breach. None clears its target. These are the honest
gains: true oblique town views with colourful crowds, a burning town with real flames, and the storm host at the wall in
dense blocks.
