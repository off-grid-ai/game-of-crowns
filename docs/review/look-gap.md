# The look gap: our town frames against 01-town, measured

Mac on batch 9's best town frame (goldrock-6): "this still seems poor quality". Target: `docs/art/target/01-town.jpg`.
Scope since the supervisor's 2026-11-12 redirect: **Kingsmere's square at the default town view**, and only my layer:
light, colour, atmosphere, the grade, and the readability-scale numbers. Composition is the camera agent's, the
buildings fire-siege's, ground and props army-ui's, people works-life's.

How measured: `realm/tools/look_gap.py` (every frame at 960 wide, our HUD masked out). Lab L is 0-100.
Picture: `docs/review/screens/look-gap/target-before-after.jpg` (target | batch 9 | v3 grade offline).

## The numbers

| metric | 01-town | Kingsmere (clarity-new) | kingsmere-6 | goldrock-6 |
|---|---|---|---|---|
| brightness, L mean | 47.1 | 40.8 | 31.3 | 44.3 |
| contrast, L std | 20.6 | 20.8 | 16.7 | 18.0 |
| darkest tenth, L | **14.1** | **3.4** | **3.2** | 16.5 |
| brightest, L p95 | 80.8 | 68.3 | 57.0 | 80.7 |
| chroma mean (Lab) | 29.9 | 26.7 | 24.6 | 24.4 |
| chroma p90 | 59.2 | ~45 | 44.4 | 41.8 |
| haze (dark channel mean) | **0.088** | 0.151 | 0.100 | **0.207** |
| fine detail (Laplacian std) | **63.1** | 33.0 | 26.3 | **25.8** |
| chroma in Lab red (30-45 deg) | 0.23 | | 0.27 | 0.13 |
| chroma in Lab orange (60-75 deg) | 0.17 | | 0.24 | 0.36 |
| chroma in green (110-140 deg) | 0.10 | | 0.04 | 0.02 |

What they say:

1. **Brightness and contrast are not the gap.** Goldrock-6's range (L p5-p95 62.9) is the target's (65.6), its contrast
   0.87 of it. A full lightness histogram match was tried first and only blew out the bright frames.
2. **Kingsmere's shade is crushed.** Its darkest tenth sits at L 3; the target's at 14. The target has deep but
   readable shade; ours goes black under eaves and in the lee of the near houses. Kingsmere also sits about 6 L
   darker overall.
3. **The colour piles up in orange.** Our chroma sits in Lab orange (goldrock-6: 0.36 against 0.17); the target's sits
   in red (0.23) and green (0.10). The plaster, timber, stone and tiles all lean one orange; 01-town separates red
   tiles, white plaster, brown timber, grey stone and green gardens.
4. **Haze.** Goldrock-6 carries more than twice the target's haze (dark channel 0.207 vs 0.088): the rain, the
   volumetric haze and smoke near the lens.
5. **Detail density is the biggest number: half the target's fine detail** (Laplacian 26-33 vs 63). That is content:
   outlines, tile edges, fences, flowers, people, goods. No grade fixes it.
6. **Readability scale (measured on kingsmere-new, native pixels).** A townsperson stands about the height of a
   house door and about 0.5 of a storey (48 px against a ~100 px storey); 0.13 of a three-storey house to the
   ridge. In 01-town a person is about 0.8 of a cottage's wall height and 0.33 of the cottage to the ridge. **The
   target draws people about 1.5-1.7x larger against buildings than we do** [estimate, from 6 hand-measured
   figures]. The supervisor's 1.35 is the conservative end; the statue is short by more (target: about 3.5 people
   tall on a stepped plinth; ours about 2).
7. People read dark: our townsfolk wear blue-grey and brown; the target's red and white clothes are what make them
   pop off the cobbles (for works-life).

## What the v3 look changes (`--look=v3`; `--look=one` keeps batch 9's)

All in `realm/data/look.json` `v3`, laid key by key over the one look by `look.gd`; **off by default until filmed**
(`v3.on`). TUNING.md has the line.

- **The grade**, fitted offline (`realm/tools/fit_look_lut.py` -> `realm/assets/grade/v3.png`, composed after
  bold.png): chroma x1.15 (fitted to the target's mean), Lab orange turned 9 deg toward red, olive grass 12 deg
  toward green, a gentle S of slope 1.1 round L 46, and the crushed shade's toe lifted 8 L. look.gd builds the 3D
  texture from the PNG if Godot hasn't imported it yet.
- **Light:** exposure 1.16 -> 1.22 (Kingsmere 6 L dark), sun 38 -> 44 deg and 1.3 -> 1.4, shadow opacity
  0.72 -> 0.78 (crisper, not darker: the shade is already crushed), the camera-shoulder fill 0.35 -> 0.45.
- **Contact shadows:** SSAO radius 1.2 -> 0.9 (tight, under eaves and at feet), intensity 1.8 -> 2.0, and they
  now show in sunlit areas a little (light_affect 0.15 -> 0.22).
- **Clear air:** volumetric haze 0.003 -> 0.0015, depth fog 0.0008 -> 0.0003, the haze's share at the closest
  zoom 0.2 -> 0.08.
- **The pale square over the sea** (goldrock-30, batch 9 review), a fix, on by default (`look.json sea.floor`):
  the water is see-through and reads what lies under it; past the realm's land Terrain3D has no floor, so the sky
  showed through as a pale panel with a straight edge. A dark floor plane now lies just under the deep sea floor
  (-3.3) out to 4000 units (`terrain.gd _build_sea_floor`).

### Offline previews (the grade only, on batch 9's frames)

`/tmp/goc-look/*-before-after.jpg` (left batch 9, right graded): kingsmere-new, kingsmere-old, kingsmere-6, -10, -16,
goldrock-6, forge-new.

| | target | Kingsmere before | Kingsmere after (grade) |
|---|---|---|---|
| darkest tenth, L | 14.1 | 3.4 | 8.5 |
| chroma mean | 29.9 | 26.7 | 30.5 |
| colourfulness | 28.5 | 25.1 | 29.1 |
| green share (HSV) | 0.090 | 0.074 | 0.101 |
| haze | 0.088 | 0.151 | 0.137 |
| fine detail | 63.1 | 33.0 | 32.7 |

Judged at 100% beside 01-town: **better, not close.** Reds read as red rather than orange, the grass greens, the
shade under eaves opens up. It does not make the frame look like the target: the target's richness is its detail,
its density and its large, brightly dressed people, and those barely move with a grade. The haze, light and
exposure changes can only be judged on film.

## What a grade and light can't fix (needs other layers or new art)

- **Detail density (half the target's):** fences, flowerbeds, fruit trees, washing lines, goods, animals in yards;
  the bare cobbles and grass patches between houses (army-ui: ground and props).
- **People 1.5-1.7x too small against buildings, and dressed dark** (works-life; the scale numbers are above). The
  statue needs a bigger plinth and a bigger King.
- **The framing:** 01-town is a high oblique holding a whole quarter; the default Kingsmere view holds three
  buildings, a chimney and a ghosted house (camera agent).
- **Two styles side by side:** Quaternius kit houses beside Meshy's hand-painted pieces (the gatehouse at Goldrock
  most of all). Handed to fire-siege with the buildings.
- **Fine detail in the art itself:** the target's bold dark outlines and painted edge highlights. A Godot 4 outline
  or edge-detect pass would raise the detail number; that's a building block to survey (none chosen).

## The painted line and edge light (v3)

The target's bold painted edges and part of the fine-detail gap. Survey (2026-11-12):

| block | licence | how | fit |
|---|---|---|---|
| **High Quality Post Process Outline** (EMBYR, godotshaders.com) | MIT | full-screen quad: 3x3 depth and normal edges, width and strength easing with distance, grazing-angle guard | the most used Godot 4 outline; works on 4.3+ reverse-Z; Forward+ normal buffer. **Picked** |
| 3D Pixel art outline & highlight (Leo Peltola; perspective by Riley Evans) | MIT | full-screen quad: depth outline plus a light on convex normal edges | the edge-light idea taken from it; its depth thresholds are absolute and pixel-art tuned |
| Sobel outline (LoudFlameLava) | MIT | Sobel on depth and normals | noted unreliable far away |
| Inverted hull (per-mesh second pass) | n/a | a grown, front-culled copy of every mesh | doubles triangles (143M a frame at 6,000 men already); can't reach baked or VAT meshes; no crease lines |
| CompositorEffect compute outlines (forum playgrounds, itch) | mixed | compute pass on the buffers | no mature, licensed, maintained block; more glue for the same result |

Why EMBYR's: proven, MIT, one material on one quad (nothing touches the buildings, people or army meshes), and
its distance easing suits a camera that runs from 6 to 60 units. Fitted: the depth test is relative to the
distance (one absolute threshold can't serve 6 and 60 units off), the normals are decoded, the grazing guard is a
plain multiplier on edge-on surfaces, and Peltola's edge light falls only on outward folds of one surface.
Concave folds (a wall meeting the ground, an eave over a wall) get the line; convex ones (ridges, beam corners,
trims) the warm light. Compiled on Metal Forward+ (Godot 4.7.2, a 6-frame headless-free compile test, no
picture taken). Every number in `look.json v3.outline`. Known risks to watch on film: lines in foliage (noisy
normals) and on grass cards, shimmer under MetalFX temporal upscaling at the play resolution (films draw at full
size), outlines drawn through smoke (smoke isn't in the depth buffer).

## To film (supervisor's batch)

Kingsmere's square at the default town view, three shots at the same frame: `--look=one` (before), `--look=v3`, and
the target beside them; and goldrock-30 to check the sea panel. Re-measure with
`arch -arm64 /usr/bin/python3 realm/tools/look_gap.py docs/art/target/01-town.jpg <frames>`. If the godot import
hasn't run, v3.png still loads (built from the PNG); the gate's import gives it a .import.
