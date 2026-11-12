# Quality deep dive: how we get from our frames to the North Star (2026-11-12)

Mac, on goldrock-6 next to `docs/art/target/01-town.jpg`: "quality still is far by much… can you get an agent to
do some deep research to figure out how to get really good quality?"

This builds on `docs/review/look-gap.md` (same day: the v3 grade, the light, the readability scale). That covered
light and colour on Kingsmere's square. This covers the rest: what shipped RTS games do, what Godot 4.7 offers,
how to make the art one style, and the order to do it in.

**Reference board (not in git, fair-use research only): `/tmp/goc-quality-refs/board.jpg`.** The top row is 01-town,
goldrock-6 and centre-feast-wide. Below are 20 stills from 12 shipped games at an RTS camera: Warcraft III Reforged
×4, AoE IV ×3, AoM Retold ×2, AoE II DE, Anno 1800 ×2, Anno 117, Manor Lords, Foundation, Against the Storm ×2,
DINO, Stronghold DE, Northgard. Sources: the Steam store API and Gameswelt's Reforged gallery. All 123 Steam stills
are in `/tmp/goc-quality-refs/dl/`, and the Reforged ones in `/tmp/goc-quality-refs/wc3/`.

Tags: **TESTED** (measured or checked on our files), **VENDOR** (the studio or toolmaker says it), **REVIEW**
(third-party write-up, teardown or forum), **ESTIMATE** (my judgement). Nothing in the game was changed and Godot was
not started.

## Short answer

1. **Colour is not the gap. Content, framing and consistency are.** At town zoom our saturation is already the
   concept's (0.53 vs 0.50) and 1.5x the shipped games' (0.36). Our fine detail is 0.7x the shipped games' at town
   zoom and 0.5x at the wide zooms. 01-town has 2.4x ours. (TESTED)
2. **The concept art is denser than any shipped game.** 01-town's detail number is 0.20. The median of 20 shipped
   stills is 0.12; only AoE II DE and Stronghold reach 0.20, and both have small sprites. The realistic bar is
   "AoE IV / WC3 Reforged at a 45° camera". (TESTED)
3. **Our town camera is lower and closer than every reference.** Town view: pitch 22°, distance 12. The references sit
   at about 40-60° and hold a whole quarter of the town. Ours holds three buildings, a chimney pot and a ghosted house.
   (TESTED for our numbers, ESTIMATE for theirs)
4. **The wide zooms are flat and hazy.** At d16-30 our value spread is 0.63x the shipped games' (luma sd 0.106 vs
   0.168) and the highlights stop at 0.52 against 0.68. That is the tonemapper, the haze and an olive ground, and it
   is mostly settings. (TESTED)
5. **Two art styles sit side by side.** The Quaternius trims are low-contrast flat paint lit by the scene. The Meshy
   pieces carry painted-in light. One repaint of the kit's 8 shared colour sheets re-skins all 176 kit pieces at once.
   (TESTED: the kit's glTFs reference 8 base-colour textures)
6. **What every reference does, and we don't yet:** exaggerate people and props, keep the ground quiet but varied,
   dress every gap, use one palette and one benchmark asset, and paint the light into the albedo. (VENDOR/REVIEW, §2)
7. **Plan:** framing, then wide-zoom light, ground, dressing, one painted kit, scale, ink, Meshy retexture,
   readability, sharpness. Most of the early steps are data. The kit repaint is the one art job. Money: $0, with one
   optional $20 month of Meshy Pro. (§5)

## 1. The gap, measured

Every frame was resized to 960 px wide. Our HUD band and minimap column were cropped out. The shipped stills were
centre-cropped (5-95% across, 12-80% down) to drop their HUDs. Script:
`/tmp/goc-quality-refs/measure.py` (refs: `measure_refs.py`) (PIL + numpy, `arch -arm64 /usr/bin/python3`). Metrics:

- **sat:** mean HSV saturation.
- **sat_hi:** share of pixels with saturation above 0.5.
- **luma sd:** value spread.
- **p5 / p95:** shade and highlight levels.
- **warm / green:** share of saturated pixels by hue.
- **edges:** mean edge-filter response, i.e. fine detail.
- **local:** mean 8×8 luma standard deviation, i.e. local contrast.

Medians per group:

| group | sat | sat_hi | luma | luma sd | p5 | p95 | warm | green | edges | local |
|---|---|---|---|---|---|---|---|---|---|---|
| shipped games (20 stills) | 0.356 | 0.18 | 0.38 | **0.168** | 0.145 | **0.676** | 0.35 | 0.18 | **0.119** | **0.078** |
| Warcraft III Reforged (4) | 0.427 | 0.43 | 0.36 | 0.151 | 0.148 | 0.630 | 0.16 | 0.47 | 0.097 | 0.069 |
| our concepts (01, 03, 04, 06, 08) | 0.502 | 0.52 | 0.42 | 0.196 | 0.127 | 0.733 | 0.62 | 0.09 | 0.121 | 0.084 |
| 01-town alone | 0.509 | 0.54 | 0.43 | 0.207 | 0.130 | 0.785 | 0.66 | 0.09 | **0.203** | **0.134** |
| ours, town zoom (6 frames) | **0.526** | 0.56 | 0.40 | 0.198 | **0.082** | 0.748 | **0.73** | 0.05 | **0.085** | **0.060** |
| ours, wide zoom (d16-30, march) | 0.411 | 0.28 | 0.33 | **0.106** | 0.154 | **0.522** | 0.41 | 0.15 | **0.060** | **0.039** |

Town zoom: goldrock-6, 01-goldrock-fountain, 02-centre-feast-wide, 03-square-street-after, forge, 07-battle-in-play.
Wide zoom: goldrock-16, kingsmere-16, kingsmere-30, 06-painted-march. Per-frame numbers: `/tmp/goc-quality-refs/metrics.txt`
and `refs_metrics.txt`.

What the numbers say:

- **Saturation.** It is already at the concept's level at town zoom. Pushing it further moves us away from every
  shipped game (Settlers 7's "people don't look like people" is the warning, §2). Our colour also piles into one warm
  band: 73% warm against 35% for the shipped games. look-gap.md found the same thing in Lab orange. **Separating the
  hues matters more than adding saturation**: red tile, white plaster, brown timber, grey stone, green garden. (TESTED)
- **Fine detail.** This is the biggest gap. At town zoom we are 0.71x the shipped median (0.085 vs 0.119) and 0.42x
  01-town. At the wide zoom we are 0.50x. A grade does not move this number: look-gap.md's v3 grade left it flat
  (33.0 to 32.7 Laplacian). Only content moves it: dressing, ground variety, painted texture contrast, edges. (TESTED)
- **Wide zoom.** Value spread is 0.63x and the highlights are capped (p95 0.52 vs 0.68). Saturated pixels are 0.28 vs
  0.43 for WC3, and kingsmere-30 is the worst (0.13). The frame reads grey-olive and hazy. Likely causes, untested:
  AgX's highlight desaturation (§3), volumetric haze, and SDFGI bouncing the olive ground into everything. (TESTED for
  the numbers, ESTIMATE for the causes)
- **Town-zoom shade is crushed.** p5 is 0.082 against the shipped 0.145. That matches look-gap.md's L 3 vs 14; the v3
  grade lifts the toe. (TESTED)
- **Green.** The shipped games carry 18% green and WC3 47%. 01-town carries 9%, because it is all roofs and cobbles.
  Our wide frames carry 15%, but olive and dark. WC3's ground is a bright, varied green (board row 2). Ours is one
  flat olive. (TESTED + seen)

What the eye says, on the board:

- **Framing (seen).** Every shipped still looks down at roughly 40-60° (ESTIMATE) and holds 15-60 buildings. Ours
  (pitch 22°, `realm/data/camera.json` town_view) puts a house roof across a third of the frame. The project's own
  rule (memory "oblique camera") is 30-55° looking across the land, so 22° sits below even our own band.
- **Scale (TESTED in look-gap.md, seen here).** People already draw at `people.json readable` 1.5. Buildings still
  disagree with each other: in `settled/forge.png` the kit house is about twice the height of the Meshy forge next to
  it, and the trees stand as tall as two-storey houses. The references keep one storey height and one footprint
  family per building type (Anno, AoE IV, §2).
- **Ground (seen).** Between our houses there is bare grass with scattered tufts. In every reference the ground under
  a town is dirt, paving, yards, gardens, wear and fences: almost no bare default grass inside a settlement.
- **Style (seen).** Goldrock-6 alone has four looks: the Quaternius trim house on the left (flat, low contrast), the
  Meshy gatehouse (painted light, chunky), a grey photoreal chimney pot at the bottom, and a fern from a third kit.

## 2. What makes the references look good at an RTS camera

### Per game (sources in §7)

- **Age of Empires IV (Relic).**
  - "Readability and playability are top on our list in terms of the visual direction." Unit colours were made "more
    differentiated against the environment". Weapons were enlarged "to help the players recognise units much more
    quickly" (VENDOR, Schläppi via Gamepressure).
  - Painterly textures were chosen so the image "cleans itself up" at both 1080p and 4K. Detail was cut on units and
    spent on buildings; the tone is a "coffee-table-book, tourist-town… very colourful" one (VENDOR, MobileSyrup).
  - Units stay over-proportioned on purpose (REVIEW, XboxEra podcast via Steam forum).
  - The ground is splats that blend, plus a few costly decals; decorative foliage is kept apart from blocking trees
    (VENDOR, AoE support docs).
  - One artist set a greybox, model and PBR benchmark that every outsourcer followed (VENDOR, artist portfolio).
- **Warcraft III Reforged (Blizzard, Lemon Sky, BOSi).**
  - "For RTS you want things to be a little bit overbuilt and easier to read from the top down" (VENDOR, Game
    Informer). Proportions were redone several times for the top-down view, with the Grunt as the style reference.
  - Per model: hand-painted diffuse plus normal, ORM (team-colour mask in its alpha) and emissive; one shared
    environment reflection (REVIEW, modder teardown).
  - The same teardown names Reforged's weakness: units lack colour and contrast against an over-saturated terrain.
    Players asked for bigger team-colour areas (REVIEW, Blizzard forums, Hive).
- **Anno 1800 (Ubisoft Mainz).** The only full frame breakdown found (REVIEW, Thomas Poulet):
  - 4x MSAA HDR forward render, quarter-res SSAO, two shadow cameras (a tight near one and a wide far one).
  - Post: bloom, then tonemap, then a colour LUT.
  - Terrain is virtual-textured, about 10 layers blended per tile, decals baked on top, and two 8K whole-map tint and
    "grit" textures.
  - Artists: roofs and large-scale weathering read from above, grout doesn't (VENDOR, Ubisoft News). Machinery goes
    outside so a building's job reads (VENDOR, Anno Union).
  - Dressing rule: "1-2 big showpieces, a few medium sized ornaments, and several versatile small ornaments… to fill
    any gaps" (VENDOR, Anno Union).
- **AoE III DE / AoM Retold (World's Edge).**
  - Units have "slightly exaggerated silhouettes, like tabletop miniatures". Polygons are spent on eaves and round
    barrels. LUTs were added and bloom was cut because it washed out the light areas (VENDOR, ageofempires.com).
  - Reviewers say AoM Retold lost the painterly feel and reads "generic and overblown" (REVIEW, PCGamesN).
- **Foundation (Polymorph).** "Buildings are the main characters", and roofs get the most work because the view is
  from above. Lower tiers are less saturated and more chaotic. One benchmark building was made before production
  (VENDOR, Game Developer).
- **Diplomacy is Not an Option (Door 407).** Textures were muted because bright ones pulled the eye. Units take
  detail from geometry, not texture. Scale is tracked across every object (VENDOR, lead artist via WN Hub).
- **Against the Storm, Northgard, Settlers 7.**
  - Against the Storm cites Blizzard and hand-drawn Disney (VENDOR).
  - Northgard says visibility comes first (VENDOR).
  - Settlers 7's "exaggerated fairy tale" went far enough that reviewers said "the people don't look like people"
    (REVIEW). That is the edge not to cross.
- **Manor Lords.** Megascans at true scale with Lumen off (VENDOR). It is the wrong reference for us, and a known
  "too dark" complaint (REVIEW).
- **The Blizzard painting recipe.**
  - Colour comes from a gradient map, with saturated, coloured AO multiplied in.
  - A top-down light gradient is painted in, and curvature-driven edge highlights go into the albedo.
  - Often there is no normal or roughness map. The light is painted from above, so scene lights must stay gentle
    (REVIEW, 80.lv breakdowns).
  - "Placement of colour masses is more important than details"; team colour goes in solid blocks, not fragments
    (REVIEW, androidarts).

### Ten rules, with the games behind each

1. **Readability over detail. Spend detail on roofs and silhouettes.** AoE IV, Foundation, Anno, DINO.
2. **Exaggerate people, weapons and props against buildings, about 1.5-3x.** AoE IV, WC3, AoE III DE. We are at 1.5;
   weapons and props are not yet enlarged.
3. **The ground is the quiet layer: lower contrast than units and buildings, but varied in hue.** AoE IV, the
   Reforged teardown, AoE III DE.
4. **Team colour in big solid mask blocks, on roofs, banners, shields and shoulders.** WC3, SC2, AoE IV. We do this
   already (`look.json team`).
5. **One palette, one material language, one benchmark asset that everything is matched to.** AoE IV, Foundation,
   WC3's Grunt, DINO. This is our "assortment of kits" problem.
6. **Paint the light into the albedo: top-light gradient, coloured AO, edge highlights. Keep scene light gentle.**
   WC3, AoE IV, the 80.lv Blizzard breakdowns.
7. **The ground in layers: about 10 splat layers, wear decals, and a big low-frequency tint over everything.** Anno,
   AoE IV.
8. **Dress in a hierarchy: 1-2 showpieces, a few mediums, many small gap-fillers, and machinery outside.** Anno, AoE
   IV (scaffolds, rubble).
9. **One warm key, a soft fill or bounce, crisp near shadows, then tonemap, LUT and restrained bloom.** Anno, AoE III
   DE, Tiny Glade.
10. **Status shows in shape, saturation and order: poor is greyer and messier, rich is brighter and ordered.**
    Foundation, Anno tiers.

**No numbers exist publicly.** No studio publishes its texel density or unit-to-building ratio. Industry rules of
thumb: about 128-256 px/m for top-down games and about 512 for third-person (REVIEW, Maxon docs; beyondextent). Our
kit trims are 2048² sheets and the Meshy atlases 2-4K. Texture resolution is not our limit. (TESTED for our sizes)

## 3. Godot 4.7: what to use

We run Godot 4.7.2 (TESTED: `arch -arm64 godot --version`). **Today:**

- AgX tonemap, SDFGI (4 cascades), SSAO, SSIL, glow, adjustment saturation 1.25 and contrast 1.07, a LUT, exponential
  and volumetric fog, 2-split sun shadows at 4096 (`main.gd` 650-710, `look.gd`).
- Play: MetalFX temporal at 0.67 scale (`project.godot`).
- Stills: native resolution, MSAA 4x **plus TAA** (`shot_harness.gd _capture_quality`).
- The "one" look is off by default (`look.json on: false`); v3 is waiting to be filmed.

| Area | What the sources say | For us |
|---|---|---|
| **Tonemap** | AgX "desaturates bright values"; it is the most hue-stable and the slowest tonemapper. Since 4.6, `tonemap_agx_white` (default 16.29) and `tonemap_agx_contrast` (1.25) are settable, and the docs prefer AgX contrast over the adjustment contrast. LUT and adjustments run after the tonemap. (VENDOR, Godot docs, 4.6 release) | Neither AgX knob is set anywhere (TESTED: grep). A lower white (about 4-6) and AgX contrast (about 1.35-1.5), with adjustment contrast back to 1.0, is the cheapest test for the capped highlights at the wide zoom. Render Filmic beside it: `perf_tools.gd` already switches tonemappers. |
| **GI** | SDFGI is the only dynamic open-world GI. Y-scale 50-75% cuts leaks at no cost, half-res GI saves a lot, and it ignores moving objects. The HDDAGI replacement is still an open PR (#119869) and not in 4.7. VoxelGI leaks; LightmapGI is editor-only. Many stylised games use direct light plus AO and no GI. (VENDOR, docs + PR; REVIEW) | Test SDFGI off at the wide zoom, with a tinted sky ambient. Olive ground bounce is a suspect for the grey-olive cast (ESTIMATE). If it stays: Y-scale 50%, half-res, energy about 0.6. |
| **SSAO / SSIL** | SSAO touches ambient only unless `light_affect` is above 0; "be conservative". SSIL complements GI. (VENDOR) | look-gap.md's v3 already tightens these; no new advice. |
| **AA / sharpness** | The docs recommend MSAA for "cartoon or low-reflectivity styles" because it adds no blur, while TAA blurs a little when still and more in motion. SMAA 1x arrived in 4.5. The automatic mip bias adds -0.5 with TAA. Anisotropic filtering matters at oblique views. (VENDOR) | Stills: try MSAA 4x + SMAA with TAA **off** (thin spears, tile edges). Play: MetalFX at 0.67 means about 45% of the pixels are drawn; try 0.85. Set `rendering/textures/default_filters/anisotropic_filtering_level` to 16x. |
| **Grade** | A 3D LUT is imported as Texture3D from a strip (17-65 slices). Grade a neutral strip in any tool (Resolve, Krita, GD Grader) next to a frame. (VENDOR) | Already in place (`realm/tools/fit_look_lut.py`, `assets/grade/v3.png`). Keep it last, after framing and content. |
| **Outlines / ink** | Screen-space depth+normal edge detection is one fullscreen pass at a flat cost. CompositorEffect runs custom compute passes on Forward+. Stencil (4.5+) allows outlines on chosen objects. An inverted hull doubles vertex work and breaks VAT crowds. (VENDOR + ESTIMATE) | A faint, coloured ink on creases and silhouettes is the one post effect that raises the detail number. WC3 has no outlines, but 01-town has bold ones. Keep it subtle and behind a switch. |
| **Painterly post (Kuwahara)** | A port exists. (VENDOR) | Not recommended: it smears units and banners at RTS distance (ESTIMATE). |
| **Foliage / scatter** | ProtonScatter: MIT, about 3k stars, active 2026-09. SimpleGrassTextured: MIT, active 2026-10. Spatial Gardener: MIT, slowing. Terrain3D's own instancer has LODs and shadow impostors. (VENDOR) | Terrain3D's instancer first (already in the stack); ProtonScatter for yards and gardens if hand-placed rules get heavy. |
| **Soft painted shading** | eldskald godot4-cel-shader: MIT, multi-light, rim. Binbun's Ultimate Toon Shader. Flexible Toon's licence is unclear (MIT vs AGPL). (VENDOR) | WC3 is not cel-shaded. At most a soft wrap or two-band ramp on buildings. Low priority after the repaint, which does the same job in the texture. |
| **Showcase proof** | No shipped Godot game with a WC3-Reforged look and a technique write-up was found. GodotCon 2023 "From watercolors to mechs" is the best stylised talk on record. (VENDOR) | We are early adopters. Every step below uses stock Godot features or MIT add-ons. |

## 4. One painted style across all models

**What we hold (TESTED):**

- The Quaternius Medieval Village kit: 176 glTF pieces built from 8 shared trim sheets, 2048². WoodTrim is used by
  136 pieces, Plaster 47, RockTrim 26, Brick 23, RoundTiles 19, UnevenBrick 18; MetalOrnaments 9 (1024²).
- The sheets are already hand-painted in style, but quiet. Plaster is nearly flat beige, and the tiles have no dark
  between-rows. None carries a top-light gradient or edge highlights.
- 13 Meshy buildings (`realm/assets/meshy/`, 2-4K atlases with fragmented UV islands, light painted in) and the
  Meshy cast.

**The options:**

- **Re-texture the kit (recommended).**
  - Repaint the 8 base-colour sheets with the Blizzard recipe: deeper value steps, dark grooves between tiles and
    stones, painted edge highlights on trim, a warm top-light and cool coloured shade, and more distinct hues per
    material (tile red, plaster cream-white, timber brown, stone cool grey).
  - That re-skins all 176 pieces and every house the builder makes.
  - Bake per-vertex AO into the kit meshes at import (Blender's built-in Dirty Vertex Colors, multiplied in the
    shader) so corners and eaves darken the painted way.
  - Tools:
    - Codex image generation on each sheet, with the style prompt and the original sheet as the guide, then a check
      that the tiling and the trim bands still line up.
    - Ucupaint (free, GPL-3, Blender 5.x) or Krita for touch-up.
  - Time: about 1-3 days per sheet by hand, less with Codex. The whole kit in about a week (ESTIMATE). Cost $0.
    Risk: the trim bands must stay pixel-aligned or every piece's UVs break; keep the originals and switch the sheets
    on and off in data.
- **Replace with a generated set.** Meshy hero buildings, all retextured from one style image (§ below), keeping the
  kit for ordinary houses. Good for the 5-10 landmark pieces. A whole town of generated houses loses the kit's
  modular variety and costs a download per model.
- **Buy.** Nothing found matches Reforged.
  - BitGem "Human & Orc RTS Buildings – Hand Painted": $14.99, 22 buildings, last updated 2021. Closest to classic
    WC3 and small.
  - Unity "RTS Mega Pack Fantasy Buildings": $90, mixed cultures.
  - Polyart "Stylized Kingdom": about $300, Unreal-heavy.
  - Unity's and Fab's licences both allow other engines. Buying adds a fourth kit to the mix, so not recommended.
    (VENDOR prices, ESTIMATE fit)

**Meshy specifically (VENDOR, docs.meshy.ai):**

- Retexture takes our own model (GLB/glTF/OBJ/FBX/STL) plus a style image or a text prompt; the image wins if both
  are given.
- `enable_original_uv` keeps our UVs.
- `remove_lighting` (Meshy 6 at 2K/4K only) strips painted light. For the WC3 look, leave painted light on, or set
  it the same way for every piece.
- `art_style` in text-to-3D is now ignored, and there is no seed. One shared style image is the only consistency
  lever.
- Credits: about 10 per retexture (REVIEW, from the pricing page). The real limit is downloads: Starter allows 20 of
  our own a month and 2 are left (meshy-cast.md). A month of Pro is $20 for unlimited downloads. **Paid; flagged.**
- No one has published a whole set unified through retexture. Meshy's own article reports about two-thirds
  alignment. Test 3 pieces before batching. (REVIEW)

**Pipeline, five steps:**

1. **Benchmark.** Pick one finished building as the style anchor: the Meshy forge, the best we hold. Every other
   piece is judged beside it at the town camera.
2. **Repaint the kit's 8 sheets** to match it (above). This is the one art job on the plan.
3. **Retexture the Meshy pieces** from one style image (a crop of 01-town's roofs and walls), original UVs kept.
   Remove the smoke blobs and the "$" sign (meshy-pulls.md).
4. **One scale.** A storey is one height in every source, doors at about 2.2 m. Correct the Meshy and kit scales in
   `meshy.json` and the house builder.
5. **Judge** all of it in the one batched render beside 01-town and the board's AoE IV and WC3 stills.

## 5. The plan, ranked by visual gain at our camera ÷ effort

Effort: S = data or settings, hours; M = a day or two of glue; L = a week, or an art job. Each step gets a switch and a
`docs/TUNING.md` line, and goes into the next batched render, never one of its own.

| # | What | Block / setting | Our files | Expected gain | Effort | Risk | Confidence |
|---|---|---|---|---|---|---|---|
| 1 | **Frame the town like the references.** Town view pitch 22° to about 40°, distance 12 to about 18-20, so it holds the square, about 15 houses, the castle and the fields. Same for the square still. | camera data | `realm/data/camera.json` town_view, town_shot, clarity | High: the board's biggest visible difference. Fewer giant near roofs, more town per frame, and the detail number rises for free. | S | Mac's "low oblique" call; 40° sits inside his 30-55° band | Medium-high |
| 2 | **Open the wide zooms' values.** Film v3 first. Then AgX white about 5 and AgX contrast about 1.4, adjustment contrast 1.0, and haze thinned with distance. Test SDFGI off, or Y-scale 50% and energy 0.6. | Environment (4.6+ AgX knobs), SDFGI | `realm/data/look.json`, `realm/scripts/look.gd`, `main.gd` 650-690 | High at d16-30. Target: luma sd 0.11 to about 0.16, p95 0.52 to about 0.65. | S | Town zoom gets brighter too, so check both | Medium |
| 3 | **Ground with layers.** A large low-frequency hue tint over the grass (WC3's varied green, not one olive). Dirt, paving and wear under and between town buildings. Yards. | Terrain3D texture layers + macro variation; Godot Decal for wear | `realm/data/ground.json`, `realm/scripts/land3d.gd`, `terrain.gd` | High: ground is 40-60% of every wide frame | M | Terrain3D shader edits are already customised (land3d.gd replaces code), so they need care | Medium |
| 4 | **Dress every gap (Anno's 1-2 / few / many).** Fenced yards, gardens, flowerbeds, washing, crates, carts and animals around each house; flower and grass clumps on the verges. Use the 92 unused Quaternius props first. | Terrain3D instancer or ProtonScatter (MIT); our dressing placer | `realm/data/dressing.json`, `dressing.gd`, `roadside.json` | High on the detail number (0.085 toward 0.12) | M | Draw calls (fps bar is 10, so fine); must stay off roads and plots | Medium-high |
| 5 | **One painted kit.** Repaint the 8 Quaternius colour sheets with the WC3 recipe, plus import-baked vertex AO, so 176 pieces match the Meshy pieces. | Codex image gen + Ucupaint/Krita; Blender Dirty Vertex Colors | `realm/assets/village/T_*_BaseColor.png` (new copies + switch), `look.json kit_tints` (retire) | High: removes "assortment of kits" | L (about a week) | Trim alignment; repaint quality varies | Medium |
| 6 | **One scale and footprint family.** Every building to one storey height; trees to about 1.2x a two-storey house at most; Meshy and kit pieces matched. | data | `realm/data/meshy.json`, `towns.json`, house builder tiers, `nature` scales | Medium-high: the forge frame's giant house goes | S-M | Plots and collisions need to follow | Medium |
| 7 | **A faint painted ink.** Screen-space depth+normal edge darkening at about 30-40% in a warm dark, not black, on creases and silhouettes. Stencil outline on selected units only. | CompositorEffect (Forward+), stencil (4.5+) | new `realm/scripts/ink.gd` + `.glsl`, `look.json ink` | Medium-high on detail, the concept's bold outlines | M | Can read cheap; WC3 has none, so keep it subtle and switchable | Medium-low |
| 8 | **Meshy hero retexture** from one style image, original UVs kept: gatehouse, tavern, treasury, market, mill, mine, tower, well. Test 3 first. | Meshy Retexture (credits about 10 each; Pro $20 for a month only if downloads run out) | `realm/assets/meshy/*` | Medium: landmarks match each other and the repainted kit | M | Unproven consistency (about two-thirds), re-rolls | Low-medium |
| 9 | **Readable people and props.** Enlarge weapons, tools and carried goods about 1.3x (AoE IV). Brighter cloth (reds and whites, look-gap.md #7). Bigger team-colour blocks on soldiers. | data | `realm/data/cast.json` dyes, `people.json`, `army.json` look/team | Medium: crowds read as people at d16+ | S | Toy look if pushed past about 1.5x | Medium |
| 10 | **Crisper pixels.** Stills: MSAA 4x + SMAA, TAA off (A/B). Play: MetalFX 0.67 to 0.85, anisotropic 16x, mip bias -0.25. | Viewport / project settings | `realm/scripts/shot_harness.gd`, `realm/project.godot` | Medium in play, small in stills | S | Shimmer without TAA; fps (fine at a bar of 10) | Medium |

Not recommended: Kuwahara or painterly post (smears units), a hard cel shader (WC3 isn't one), more global
saturation (we are already above every shipped game), waiting for HDDAGI (an open PR that needs an engine build),
buying a pack (adds a fourth style).

**Order:** 1 and 2 are settings and should go in the next batched render with v3, since they change every later
judgement. Then 6 and 9 (data). 3 and 4 run in parallel as glue. 5 is the art job and starts now, offline. 7, 8
and 10 come after it.

## 6. What I'm least sure of

- **The cause of the wide-zoom greyness.** AgX highlight roll-off, haze and SDFGI's olive bounce all fit the numbers.
  Only an A/B render separates them.
- **The repaint.** Whether Codex can repaint a trim sheet and keep its bands pixel-aligned is untested. If it can't,
  this is hand work in Ucupaint or Krita and takes longer.
- **The camera numbers for the shipped games** (40-60°) are read off stills, not measured. WC3's default angle is
  folklore I couldn't confirm.
- **The detail metric.** It rewards any high-frequency content, including noise. An ink pass raises it without
  necessarily looking better. Judge by eye beside the board, not by the number alone.
- **Meshy retexture consistency** across a set: no public proof.

## 7. Sources

Games and art direction:
- AoE IV readability (Schläppi): https://www.gamepressure.com/newsroom/age-of-empires-4-takes-flak-for-visuals-devs-respond/z13167
- AoE IV exaggeration: https://www.windowscentral.com/age-empires-4-success-graphics
- AoE IV painterly, detail on buildings: https://mobilesyrup.com/2021/04/10/age-of-empires-iv-relic-developer-interview/
- AoE IV units stay large: https://steamcommunity.com/app/1466860/discussions/0/5047948127395379293/
- AoE IV splats and decals: https://support.ageofempires.com/hc/en-us/articles/4417275201044-Placing-Splats-and-Decals
- AoE IV benchmark artist: https://www.artstation.com/artwork/wJJGOO
- WC3 Reforged (Game Informer): https://www.gameinformer.com/2018/11/02/how-blizzard-has-reforged-warcraft-iii
- WC3 Reforged texture teardown: https://us.forums.blizzard.com/en/warcraft3/t/an-attempt-to-realistically-unsucc-reforged-graphics-actual-content-inside/27002
- WC3 team-colour feedback: https://www.hiveworkshop.com/threads/warcraft-iii-reforged-artistic-textures-ui-feedback.309860/
- BOSi characters: https://www.artstation.com/artwork/ZGJeq0
- Anno 1800 frame analysis: https://blog.thomaspoulet.fr/posts/anno-1800-frame-analysis/
- Anno 1800 texturing: https://news.ubisoft.com/en-us/article/69SwK8nqv5rDUdEzqbNt6h/create-the-unknown-how-anno-1800-put-a-creative-spin-on-the-industrial-revolution
- Anno art devblog: https://www.anno-union.com/devblog-it-begins-with-art/
- Anno tiers: https://www.anno-union.com/en/devblog-residential-tiers/
- Anno dressing rule: https://anno-union.com/tag/anno-1800-en/page/29
- AoE III DE art: https://www.ageofempires.com/news/the-art-of-aoe3de/
- AoM Retold review: https://www.pcgamesn.com/age-of-mythology-retold/review
- Foundation art: https://www.gamedeveloper.com/art/deep-dive-the-art-of-i-foundation-i-
- DINO art: https://wnhub.io/news/art/item-20015
- Against the Storm: https://www.chalgyr.com/2024/04/news-against-the-storm-best-design-award.html
- Settlers 7: https://gamespot.com/articles/the-settlers-7-paths-to-a-kingdom-hands-on-first-look-and-economic-buildup/1100-6249744/
- Manor Lords tech: https://www.gamesradar.com/games/city-builder/manor-lords-dev-says-unreal-engine-5-upgrade-looks-like-a-smoother-overall-experience-so-far-but-here-are-some-new-coats-of-arms-that-medieval-games-for-some-reason-never-add-while-you-wait/
- Stronghold DE: https://www.gamepressure.com/newsroom/stronghold-remaster-devs-show-how-they-overhaul-the-iconic-game/z86110
- Tiny Glade GI: https://x.com/h3r2tic/status/1813197502411092186
- Blizzard-style texturing: https://80.lv/articles/optimization-of-stylized-game-assets
- WoW diorama painting: https://80.lv/articles/002mrs-crafting-a-wow-diorama-textures-painting-lighting
- RTS art rules (androidarts): https://androidarts.com/rts/ta.htm
- SC2 team-colour material: https://mapster.talv.space/star-tools/Tutorial_BasicMaterial.html
- Texel density: https://www.beyondextent.com/deep-dives/deepdive-texeldensity
- Texel density (Maxon): https://help.maxon.net/c4d/en-us/Content/html/Texel_Density.html

Godot:
- Environment and post: https://docs.godotengine.org/en/latest/tutorials/3d/environment_and_post_processing.html
- Environment class (AgX white and contrast, SSAO): https://docs.godotengine.org/en/latest/classes/class_environment.html
- 4.6 release (AgX knobs, glow): https://godotengine.org/releases/4.6/
- 4.5 release (SMAA, stencil): https://godotengine.org/releases/4.5/
- GI overview: https://docs.godotengine.org/en/latest/tutorials/3d/global_illumination/introduction_to_global_illumination.html
- SDFGI: https://docs.godotengine.org/en/4.6/tutorials/3d/global_illumination/using_sdfgi.html
- HDDAGI PR: https://github.com/godotengine/godot/pull/119869
- Anti-aliasing: https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html
- Resolution scaling: https://docs.godotengine.org/en/4.7/tutorials/3d/resolution_scaling.html
- Compositor: https://docs.godotengine.org/en/4.7/tutorials/rendering/compositor.html
- ProtonScatter: https://github.com/HungryProton/scatter
- SimpleGrassTextured: https://github.com/IcterusGames/SimpleGrassTextured
- Spatial Gardener: https://github.com/dreadpon/godot_spatial_gardener
- Terrain3D: https://terrain3d.readthedocs.io/en/1.0/
- Cel shader (eldskald): https://github.com/eldskald/godot4-cel-shader
- Outline post: https://godotshaders.com/shader/post-process-outline-depth-normal/
- Kuwahara: https://godotshaders.com/shader/generalized-kuwahara/
- GD Grader: https://bittwo.itch.io/gd-grader
- GodotCon 2023 stylised talk: https://media.ccc.de/v/godotcon2023-57824-from-watercolors-to-mechs-stylized-rendering-and-asset-pipelines-in-godot
- Stencil article: https://80.lv/articles/mind-bending-power-of-godot-4-5-s-stencil-support

Assets and pipeline:
- Meshy Retexture API: https://docs.meshy.ai/api/retexture.md
- Meshy AI texturing: https://docs.meshy.ai/en/webapp/guides/3d-model/ai-texturing
- Meshy pricing: https://docs.meshy.ai/en/api/pricing
- Meshy plans: https://help.meshy.ai/en/articles/12062933-meshy-pricing-plans-free-pro-studio-enterprise
- Meshy game-assets guide: https://docs.meshy.ai/en/webapp/guides/use-cases/game-assets
- Meshy text-to-3D (art_style ignored): https://docs.meshy.ai/en/api/text-to-3d
- Meshy N1 review: https://gamineai.com/blog/what-meshy-n1-changed-for-stylized-game-textures-2026
- Ucupaint: https://github.com/ucupumar/ucupaint
- Ucupaint 3.0: https://80.lv/articles/free-blender-texture-painting-add-on-ucupaint-3-0-is-now-available
- ArmorPaint 1.0: https://www.cgchannel.com/2026/09/armorpaint-1-0-is-out-after-eight-years-in-early-access/
- Godot batching: https://docs.godotengine.org/en/4.7/tutorials/performance/optimizing_3d_performance.html
- BitGem RTS buildings: https://assetstore.unity.com/packages/3d/environments/fantasy/human-orc-rts-buildings-hand-painted-10839
- RTS Mega Pack: https://assetstore.unity.com/packages/3d/environments/fantasy/rts-mega-pack-fantasy-buildings-206964
- Unity assets in other engines: https://support.unity.com/hc/en-us/articles/34387186019988-Can-I-use-assets-from-the-Asset-Store-with-other-engines
- Fab licences: https://dev.epicgames.com/documentation/en-us/fab/licenses-and-pricing-in-fab

Reference stills: Steam store API (`store.steampowered.com/api/appdetails`), and Gameswelt's Warcraft III gallery
(https://www.gameswelt.de/warcraft-iii/bilder).
