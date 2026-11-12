# Batch 9 review: judged launch by launch against the art targets

Running from f363cef1. Frames are in `/tmp/goc-batch9`, contact sheets in `/tmp/goc-batch9/review/sheets/`, and the best
frames in `/tmp/goc-batch9/review/best/`. Mac's bar: a shot passes only if it would clear its concept in
`docs/art/target` at 100%. This file grows as each launch finishes; the top 15 comes at the end.

## ladder (11 frames, 0 script errors)

**Camera check: no regression.** Every distance lands where asked: Kingsmere 6, 10, 16, 30, 50, 14 and 40;
Goldrock 6, 10, 16 and 30. There are no duplicate frames, and every shot settles in 0.7-2.9 s. Kingsmere sits at
34-39 degrees down; Goldrock, with its tilt, at 17-24 degrees, where the sky and horizon show.

| Shot | Verdict | Defects |
|---|---|---|
| goldrock-6 | FAIL (best town frame to date) | Close to 01-town: the new gatehouse with house banners carrying arms, a busy colourful square, a lit house, and the sea beyond. Defects: a big shiny grey chimney pot fills the bottom middle (an untextured metallic look). Chimney smoke drifts across the left house's face. The rider's horse is still patchy. Rain streaks are drawn as long white lines. |
| goldrock-10 / -16 | FAIL | Dense, readable roofs and towers, with the horizon. A roof cuts the lower left at 10. The square is small at 16. |
| goldrock-30 | FAIL | The whole town on its island reads. A pale square halo shows in the sky (a fog volume's edge?). |
| kingsmere-6 / -10 | FAIL | Square, crowd and stalls are clear. No sky at 35-37 degrees. **A blown-out white glare on a thatch roof** (the wet-roof glint far too hot). Long rain streaks. A dark red roof cuts the lower left at 6. |
| kingsmere-16 | FAIL | **Glowing white blobs on the ground** in the lower left: wet-ground or puddle highlights blowing out. The castle walls read. |
| kingsmere-30 / -50 / -40-low | FAIL | The whole town, walls and roads read as a strategic view. The road border is a loud salmon-red line. Smudgy at 50. |
| kingsmere-14-low | FAIL | A good oblique with the horizon, walls and square. Bright white glare spots on far roofs, and the far mountains are glossy. |

**ladder defects:** (1) wet glare: white blown-out highlights on roofs and the ground in rain (weather_fx.gd wetness,
weather.json; look.gd glow). (2) The foreground chimney pot and roof edges at d6 (camera_rig.gd lower-third clear,
46aefe45: still catches the nearest chimney). (3) Rain drawn as long white streaks. (4) A loud red territory line on the roads at d30-50.

## settled (26 frames, 0 script errors; the forge at 4.5, settled in 0.6 s at 30 degrees)

| Shot | Verdict | Defects |
|---|---|---|
| forge / forge-ui | FAIL | The settled framing works: no camera drift. The new forge with its house-colour shield, the fire inside, two smiths, a busy lane and a barn read clearly. Winter now puts **snow on the roofs** (a gain). Defects: the snow on the trees is **flat white cross-quads** sticking out of the crowns (cards, not snow). Summer grass tufts and red flowers poke up through the snow everywhere. A red blob floats in mid-air left of the forge. The inn's name label ("...en Wheel") is cut by a roof. A grey see-through rectangle sits on the snow behind the fence (a water or decal plane). The left house's snowy roof is blown-out flat white. forge-ui is the same frame as forge: no interface difference shows. |
| forge-clip | FAIL | The camera is steady (difference 0.45 throughout), and frames are now about 0.6 s of wall time apart. The two smiths stand by the door, away from the anvil: one bends, the other shifts. No hammering is seen at the anvil. The fire flickers. |

**settled defects:** (1) tree snow drawn as white cross-quad cards (forest.gd winter snow on foliage, or the snow
material). (2) Summer grass and flowers through the snow (grass.gd or countryside props aren't seasoned). (3) The
smiths don't work at the anvil (works.gd smith anchor positions, works.json). (4) Floating red blob (a seed, an ember
sprite or a flower prop). (5) The name label is cut by roofs (towns.gd site labels).

## army-line-d12 (a still; ARMY 6000 men, 41 regiments at rest, 3 fps)

| Shot | Verdict | Defects |
|---|---|---|
| army-line-d12 | FAIL (closest to 03-army yet) | **The army shows** (batch 7 caught the main menu): 41 dense rectangular regiments under red arrow banners and a great royal standard, with the town and castle behind. This is real density. Defects: regiments stand **through a house, trees and hedged fields** (no clearance from what stands on the ground). Only two looks (grey and dark), every man the same silhouette: no knights, archers, spears or siege, as in 03-army. House colour only on the flags, not on the men. Green hedges and summer trees in a snowfield. 3 fps. |

**army defects:** (1) regiments placed over buildings, trees and fields (army_spike.gd placement; scenes.gd clearing).
(2) No unit variety or house colours on the men (army.json units and colours). (3) Seasonless hedges and trees (forest.gd,
countryside hedges).

## clarity-old / clarity-new (3 + 3 frames, 0 errors; side by side: `review/sheets/clarity-old-new.jpg`)

| Pair | Verdict | Notes |
|---|---|---|
| kingsmere | FAIL (new better, not clean) | Old: a blurred, orange, ghosted thatch house in the middle. New: crisp true colours, the square with its column and crowd at the centre, the horizon. But **a ghosted, dithered house front still fills the right quarter** of the new frame: the clarity fade still lets a near building ghost at the frame edge. |
| goldrock | FAIL (new clearly better) | Old: ghosted houses in the foreground, near blur, the gate half hidden. New: the gate, banners, square and rider are clear. A shiny chimney pot and drifting smoke still fill the bottom middle (the same as ladder goldrock-6). |
| forge | FAIL (new better) | Old: a ghosted roof at the bottom, orange cast. New: clean and true. The forge reads, but a big thatch house in the left foreground takes about a third of the frame, and the inn's label ("...n Wheel") sits over the roofs. |

**Clarity verdict:** keep it on. It removes the near blur and the orange cast and most ghosting. Left: near buildings at the
frame edge still ghost (camera_rig.gd sight check / clarity.fade), and foreground roofs and chimney pots still crowd
the lower third at d4.5-6.
