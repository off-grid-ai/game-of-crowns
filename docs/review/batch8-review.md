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
