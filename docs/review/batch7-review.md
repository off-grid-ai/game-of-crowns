# Batch 7 review: every finished launch, judged against the art targets

Judged 2026-11-12 from `/tmp/goc-batch7` (run at 5ffa97a9). Launches judged: towns, moods, fire, breach, and the
one army still that finished (army-line-d12). The supervisor stopped the batch at the army launch (00:43); square,
castle, rulings and fields were not in this run, and battle, hosts, weather and night never ran. Batch 8 refilms
with the fixes listed under "Already fixed".

The bar: a shot passes only if it would clear its concept in `docs/art/target` at 100%. **No shot passes.** The
nearest are feast-town and the settled forge clip frames (14-24).

Contact sheets (one per launch): `/tmp/goc-batch7/review/sheets/{towns,moods,fire,breach}.jpg`.
Best frames that show real progress: `/tmp/goc-batch7/review/best/` (6 jpgs).

Harness note for every clip: the snaps landed about 1.05 s apart, not 0.2 s (a snap costs about 0.8 s at 4-10 fps),
so the 5 fps mp4s play about 5x fast. Clip strips were read as about 1 s steps.

## Already fixed after this batch (in batch 8, not yet filmed)

- Ghosted near houses, near blur and the orange wash: clarity, 7ccb0b73 (camera_rig.gd, look.gd, realistic.gd,
  team_colour.gdshader; camera.json and look.json `clarity`).
- Town card, decree card and chronicle over film shots: 41fabfad (autoplay.gd snap puts the panels away).
- Pink and cream slabs at the breach: the yard washing, 065c9c39 (assets.json yard_washing, realistic.gd dyed).
- Breach camera among the houses, no wall in frame: 4ea627d2 (scenes.gd), 72cbe0d1 (autoplay.gd breach/camp/engine).

These still count below, because this batch is what the frames show. Batch 8 has to prove each fix.

## Per shot

### towns (164 frames, 0 script errors)

| Shot | Verdict | Defects |
|---|---|---|
| kingsmere-d4 | FAIL | Camera among the roofs. A ghosted house fills the lower right third and is smeared by the near blur. The square and its people sit in a slot between two roofs. Orange wash on every wall. Dead grass bailey on the left. |
| kingsmere-d6 | FAIL | The same frame as d4 (mean pixel difference 0.6/255): the rig's floor of 6 swallows the step. Same defects. |
| kingsmere-d14 | FAIL | Not d14: a map-height view of the whole coast. Kingsmere is cut off at the right edge behind the minimap. Flat grey-blue haze, mud-brown fields, and a red hedge band reads as a border line. |
| kingsmere-d40 | FAIL | The best Kingsmere frame, but it is the closest of the four, so the distance ladder runs backwards. Bailey figures are dark and stand on rectangular brown blob pads. A campfire has a glowing orb floating below it. The square is hidden behind the roofs. A house banner is visible (good). Foreground roofs are blurred. |
| goldrock-d4 | FAIL | Frames Rosehall, not Goldrock. The court card covers the right half. The red-flowered hedge square floats on bare ground. |
| goldrock-d6 | FAIL | The court card sits in the middle of the frame. A tower is ghosted on the left. |
| goldrock-d14 | FAIL | A ghosted house fills the left 40%. The paddock horses are tiny. Not a d14 framing. |
| goldrock-d40 | FAIL | Close, not d40. Blurred tree crowns fill the lower left. A loud red hedge ring round a field. A lone siege tower stands in a field. |
| forge | FAIL | Snapped before the camera settled: a ghosted house fills the right third. Clip frames 14-24 settle into a good frame. A glowing orb floats at the smith's anvil, outside the forge. The forge mouth is blown out to white. Green leaf flecks hang in the air like confetti. |
| forge-clip | FAIL | The camera orbits during frames 4-13 (difference 18-24), then settles. The smith barely moves: one arm, no hammer rhythm visible at this size. |
| stables | FAIL | A ghosted tower fills the left 40%. The horses are small and far off, behind a house. |
| stables-clip | FAIL | The horses stand frozen in all 24 frames. One townsman runs past (good stride). |
| mill | FAIL | The windmill's sails are flat, untextured salmon. They turn through the neighbouring house's roof (clipping). Pine crowns in the foreground take the lower half. |
| mill-clip | FAIL | The sails turn but sweep through the next house in every frame. |
| barnyard | FAIL | No animals in frame. The yard is empty grass behind a ghosted house. |
| barnyard-clip | FAIL | The minimap covers the only moving figure (the yardhand). No cows, sheep or pigs seen in 24 frames. |
| inn | FAIL vs 06-inn | The inn is clear and lit by the sun: real progress. Against the target it has no horses at a rail, no soldiers at tables, no merchant, shrine or milestone. The sign is a blank white cloth. The lamp post is plain white and untextured. The forest round it is a uniform wall. |
| inn-clip | FAIL | The folk at the door stand nearly still (difference 0.3). |
| hamlet | FAIL | Readable: farmstead, a pig, a sheep, one hand. Sparse and empty. Half the frame is bare grass. Town labels show through the trees as ghost text. |
| bridge | FAIL | No bridge stands (log: "0 of that kind stand"). An empty wide shot. |
| carts / carts-clip | FAIL | No cart, rider or walker in all 28 frames: only the water moves. A giant pine is out of scale with the houses. Flat salmon windmill sails stand on the shore. |

### moods (83 frames, 0 script errors)

| Shot | Verdict | Defects |
|---|---|---|
| war-town / war-clip | FAIL | Ghosted houses cover about 60% of the frame. No war cue visible at all (no levy rows, no shut stalls, no smiths). |
| war-inn | FAIL | Ghosted roof and wall fill the frame. The inn can't be seen. |
| feast-town | FAIL (closest to 01-town) | The best frame of the batch: a deep street to a lit square, dancers with arms up, stalls with awnings. Defects: a tree in the middle blocks the square. The crowd is dark silhouettes in no house colour. The inn's front is blown out by a hot light. The bunting barely reads. The far mountains have glossy white specular blobs (plastic). There's no castle presence as in 01-town. |
| feast-clip | FAIL | The crowd dances (good motion), but the centre tree hides about a third of it. |
| feast-tables | FAIL | The same frame as feast-town (difference 0.7): the 3.5 step didn't move the camera. No long tables seen. |
| hunger-town | FAIL | No hunger cue reads (no granary queue, no cold chimneys you could tell apart). The watermill's wheel is flat, untextured salmon and stands on dry grass, with no water near it. |
| levy-town / levy-clip | FAIL | A clear, sunny street (progress). The levy is a milling knot in the square, not two rows marching out. The mounted man is frozen in every frame. His horse coat is blotched with over-bright white patches. A house banner hangs from a tree (good). |
| war-feast-wide | FAIL | Kingsmere's walls read as flat slabs. Neither war nor feast is visible at this distance. Blurred tree crowns fill the lower right. The middle of the frame is empty grass. |

### fire (32 frames, 0 script errors)

| Shot | Verdict | Defects |
|---|---|---|
| fire-before | FAIL | The snow ground is flat, shadeless white with no texture. The town is a small island ringed by fences, with no wall. |
| fire-06s / fire-20s / fire-ruin / fire-clip | FAIL vs 04-siege | **No fire.** The sack staged fine (`{"ok":true,"sack":237}`), but fire.log shows 1 lit fire at most, and it's off frame (a glow at the right edge of fire-20s). Nothing spreads in 76 s, and the ruin frame shows the same intact town. The season flips mid-shot (Winter, then Spring, then Summer): the snow vanishes at once. A toast and three log lines cover the lower left. |

### breach (156 frames, **484 script errors**)

| Shot | Verdict | Defects |
|---|---|---|
| siege-camp | FAIL vs 04-siege | The Rosehall town card covers the left 35%. The camp is pink and cream untextured slabs (the washing, fixed in 065c9c39). A ghosted house fills the right 40%. The wall is a flat slab with a dark seam for a crack. There are only a handful of soldiers. |
| engine-clip | FAIL | No engine throw is seen: the card covers it, and the camera cuts twice mid-clip (frames 18 and 41). |
| breach-cracked / breach | FAIL | Ghosted house in the middle, chronicle panel on the right. The only wall in frame stands whole. |
| stone-clip / breach-clip | FAIL | Camera cuts mid-clip (frames 1 and 25; 13). No stones hitting, no opening. |
| storm-clip | FAIL | No storm through a gap: about 6 figures, and the camera reframes at frame 22. |
| storm-taken / storm-fire | FAIL | No fire: fire.gd's spread loop errors 178 times. A red near-plane mesh smears across the bottom. Chronicle panel, ghosted roof. A stone hangs in the sky (in flight; fine). |

Script errors: 306 x `field_work.gd:86` (`_stop` given a freed crop) and 178 x `fire.gd:170` (`_spread_tick` assigns a
freed root to a typed variable before its `is_instance_valid` check).

### army (stopped)

| Shot | Verdict | Defects |
|---|---|---|
| army-line-d12 | FAIL | The still is the **main menu**, not the army. The log ran at 3 fps, 142 M prims, 41 regiments at rest; the snap fired before the view left the title screen. |

## Top 15 defects, ranked by how much they hurt what the player sees

1. **The subject is hidden behind ghosted near houses** in about half the frames (towns d4, d6, d14, forge, stables, barnyard, war, war-inn, every breach shot). Owner: camera_rig.gd (sight check), realistic.gd fade_near, team_colour.gdshader; camera.json near_fade. Fix landed: 7ccb0b73. Prove in batch 8.
2. **A sack lights no fire**: fire and storm-fire show intact towns. Owners: fire.gd (`_spread_tick` line 170: a freed root assigned to a typed variable; the sack lights only 1 house, off frame), scenes.gd (sack staging); data/fire.json spread.
3. **Panels cover the action**: court card (goldrock d4, d6), town card (siege-camp, engine), chronicle (breach, storm), toasts and log lines (fire). Owners: autoplay.gd snap (fix 41fabfad); court_panel.gd opens mid-film and appears to move the camera to Rosehall (camera never steals).
4. **Near blur and the orange wash** smear the foreground and every wall. Owners: look.gd (dof_blur_near, lut bold.png, saturation 1.3), data/look.json. Fix: 7ccb0b73.
5. **The breach never reads**: no wall opening, no storm, a handful of men, and the camera cuts mid-clip in every breach clip. Owners: scenes.gd (siege placement, fix 4ea627d2), autoplay.gd breach/camp/engine (fix 72cbe0d1), walls.json and siege.json (wall-demo timing), wall model (flat slab, a seam for a crack).
6. **Flat untextured salmon blocks**: windmill sails, the watermill wheel, the yard washing. Owners: data/assets.json rotor (town/windmill.glb `sail`, town/watermill.glb `wheel`) with realistic.gd's kit tints; washing fixed in 065c9c39.
7. **The distance ladder is broken**: d4 = d6, d14 is a map view, d40 is roof height; feast-tables = feast-town. Owners: autoplay.gd `_frame_city` (line 494), camera_rig.gd distance floor 6 and the clamps.
8. **Empty subjects**: no carts or travellers on the road, no bridge, no barnyard animals, no inn horses or tables. Owners: traffic.gd and roadside.gd (data/roadside.json mix, sites), animals.gd (barn yard), works.gd and works.json (inn dressing).
9. **Mood scenes don't read**: no levy rows marching, no hunger queue or cold chimneys, no war cues. Owners: town_life.gd `_moods`, data/moods.json (levy.muster men 8, rows 2: far too few to see).
10. **The camera moves during clips and snaps fire before it settles** (forge 4-13; breach clips). Owners: autoplay.gd (wait after framing), camera_rig.gd easing; the sight-check lift in 7ccb0b73 adds easing, so check it settles before the snap.
11. **Frozen and stiff people**: stable horses, the mounted levy man, idle inn folk; the smith barely works. Owners: horse.gd, town_life.gd, works.gd (smith clip), anim_lod.gd (clips cut at range).
12. **Mills clip through houses**: the windmill sails sweep the neighbour's roof. Owners: house_tiers.gd and town_trades.gd (mill placement), assets.json rotor `size`/`out`.
13. **Floating glow orbs** at the forge anvil and under the bailey campfire, and blob pads under the bailey figures. Owners: works.gd (forge light), castle_life.gd or town_life.gd (fire and shadow decal).
14. **The ground and the season look wrong**: flat white snow plane, an instant season flip mid-shot, a watermill on dry grass, glossy specular mountains, loud red hedge rings. Owners: terrain.gd and ground.json (snow, mountain roughness), countryside.gd (season hold during a film), towns.json trades (mill by water), countryside hedges.
15. **Harness**: army-line-d12 captured the main menu; clip frames land 1 s apart, not 0.2 s; 306 field_work.gd:86 errors. Owners: tools/render.sh and army_spike.gd (wait for the realm), autoplay.gd burst timing, field_work.gd `_look` (check validity before `_stop`).

## Best frames (real progress, honestly)

`/tmp/goc-batch7/review/best/`: 01-feast-town, 02-forge-clip-20, 03-levy-town, 04-inn, 05-fire-20s (Highfell's square,
before the missing fire), 06-hamlet. None clears its target; these show the dense timber town, square life, the
inn on the road and the countryside reading clearly when the camera isn't among the roofs.
