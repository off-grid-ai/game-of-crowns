# The look standard: what every visible asset must meet

Mac, 2026-11-12: "we need to adhere to some standards, and then create the right components, or use the right
components". Why: [docs/research/look-audit-2026-11-12.md](../research/look-audit-2026-11-12.md): ten sources reach the
screen; the Kingsmere square is the one part made the proper way, and the one part that matches the target. This page
writes the square's route down so every asset takes it. The bar: [target/](target/) (look) and the casebook (play).

Status: draft for Mac's approval. Numbers marked *(est.)* are read off the target frames and get measured once.

## 1. Art bible

- **Style:** [target/style-prompt.txt](target/style-prompt.txt) for scenes; the asset prompt in
  [square/style.txt](square/style.txt), word for word, for every concept. Warcraft III Reforged polish: chunky readable
  shapes, slightly exaggerated proportions, hand-painted textures with visible strokes, rich warm saturated colour.
- **Style image (retexture):** one image every asset is retextured from, so community pieces and new pieces share one
  hand. Proposed: the square set's own sheet ([square/sheet.jpg](square/sheet.jpg)), our one proven family. Mac picks.
- **Palette:**
  - House colour (the holder's): roof tiles, awnings, banners, tabards, shields, cart cloths, saddle cloths.
  - Natural materials stay natural: warm grey stone, dark oak timber, cream plaster, golden thatch, earth brown.
  - People wear house colour and white/cream, so a crowd reads against grey stone. No brown companies.
- **Light:** painted albedo may carry soft ambient occlusion in creases; never a cast shadow, a sun direction or a
  highlight. The game's one light and grade do the rest (`realm/scripts/look.gd`).

## 2. Metrics (world scale)

One game unit = 8.33 m (`world_units.gd` M = 0.12). Every asset is made and imported at these sizes.

| Thing | Size | Rule |
|---|---|---|
| Adult man | 1.8 m, drawn x1.1 (`people.json` readable) | Head level with a door's top, as in 01-town |
| Woman / child | 0.93 / 0.62 of a man | `people.json` build |
| Door | 2.0 m | Kit and Meshy doors alike |
| Storey | 3.0 m | Cottage 6.5 m, townhouse 9 m, merchant 12 m to the ridge |
| Horse | 1.6 m at the withers; rider's head about 2.6 m | One horse body for road, field and cavalry |
| Cobble stone | 0.25-0.3 m across *(est.: a sixth of a man in 01-town)* | Today about 1 m on screen: fails |
| Tree, grown | 8-14 m (`assets.json` tree_range): one to one and a half houses | In clumps of 3-7, not rings or rows |
| Regiment banner | pole about 2.5 men tall; cloth about 1 man wide *(est., 03-army)* | Today half a unit's height: fails |
| Market stall | 3.6 m | `meshy.json` |

## 3. Texel density

Measured as albedo pixels per metre of the asset's height on its main surface.

| Class | Minimum | Today's worst |
|---|---|---|
| People, soldiers, horses, beasts | 400 px/m | Kenney/KayKit 1024 on chibi bodies (style fails anyway) |
| Buildings, castle, walls | 200 px/m | Kenney turrets 512 |
| Props | 256 px/m | Kenney town kit 512 colormap |
| Ground | 200 px/m at true scale, sharp at the town camera | Watercolour pack (soft at any density) |

## 4. Proportions

- Adults: head about 1/5.5-1/6 of height (the Meshy cast). Children about 1/4.
- **Fails:** chibi (head bigger than 1/3.5: KayKit Adventurers), realistic (head under 1/7: Mixamo, Fuse).
- Weapons and tools read at the town view: up to 1.3x true size (`people.json` held).
- Beasts: stocky, painted coats, the cast's finish (`meshy/beasts`).

## 5. Rigs and motion

- People and soldiers: the Mixamo skeleton (`meshy_api.py` rig, `skeleton_template: mixamo`); armies VAT-baked
  (`army_vat.gdshader`).
- Four-legged beasts and horses: the Quaternius animal rigs (`tools/beast_rig.py`). One horse rig for every horse.
- Every move goes through the Mover (CLAUDE.md, one way to move).

## 6. The route (the square's, for everything)

1. **Target crop:** cut the piece from the matching target image (`docs/art/<set>/ref/<name>_ref.jpg`).
2. **Concept:** `codex exec -i ref/<name>_ref.jpg -- "<square/style.txt> The asset: <line>"`, one 3/4 view on flat
   grey; for characters, front plus a views sheet.
3. **Model:** Meshy image-to-3D, latest (7.1), multi-image, 2K texture, Private licence (`realm/tools/meshy_api.py`).
   Meshy 7 texture generation stops 2026-12-31: move to the latest texture model before then.
4. **Retexture** from the one style image (Meshy retexture, `image_style_url`, keep UVs).
5. **Rig** (people and beasts) per section 5.
6. **Import** with `realm/tools/meshy_import.py`: height from section 2, triangle budget from section 7, +Z forward,
   pivot at the feet, house-colour mask.
7. **Judge** (section 8). Only then is it wired in, and the piece it replaces is deleted in the same change.

A pack piece (Quaternius, Kenney, KayKit, Sketchfab, Poly Haven, Mixamo) stays only if it passes steps 4, 6 and 8.

## 7. Acceptance checklist (every asset)

- [ ] Made by the route in section 6, from a target crop.
- [ ] Size per section 2; texel density per section 3; proportions per section 4.
- [ ] Triangles: building 20-30k, stall 15k, prop 2-12k, soldier 5-6k (VAT), beast 6-8k, horse 10k or less.
- [ ] One material; house-colour faces masked (`mask.png`); no light baked beyond soft AO.
- [ ] Pivot at the feet, front facing +Z.
- [ ] Licence and source recorded beside it (`import.json`, `SOURCE.md`).
- [ ] Listed in the one asset manifest by role (section 9); no script names its file.
- [ ] Judged per section 8.

## 8. The gate (no visual change is done until this passes)

1. **Lineup:** the asset at true scale beside the standard figures (a man, a door, a horse, a cottage) in one render.
2. **Frame beside target:** the change rendered at the matching target's framing, side by side with the target image,
   defects listed first. Attach the side-by-side to the commit or report.
3. **Numbers** (`realm/tools/look_gap.py`, HUD masked) within the target's band: saturation mean 0.45-0.55,
   sharpness at least 50, red+orange share at least 0.5 in town and army frames.

A headless probe proves it works. Only the side-by-side proves it looks right. One owner holds the frame for each
target image.

## 9. One asset manifest (the look's store)

- One file lists every visible asset by role ("knight", "oak", "cart", "ground.grass"): its file, size, source and
  status (passed or off). `realm/data/assets.json` and `meshy.json` merge into it.
- Scripts ask for a role, never a path. A rules check (like `realm/tools/rules_check.sh` for the Mover) fails any
  `res://assets/` path written outside the manifest; its known-breach list only shrinks.
- No run-time corrections of an input (tints over a texture, leaf swaps, body narrowing, size fudges): fix the asset
  and re-import it. House colour and season are the only run-time colour changes.

## 10. Components (use, don't build)

| Job | Block | Status |
|---|---|---|
| Assets | Meshy via the route above; Codex for concepts and ground textures | In use |
| Land | Terrain3D (MIT) | In use; ground texture to replace |
| Land use, clumps, hedges, orchards | ProtonScatter or Spatial Gardener (MIT) | To survey for Godot 4.7 |
| Crowds and armies | godot_vat (VAT) | In use |
| Light and grade | Sky3D, AgX, LUT, SDFGI, SSAO | In use; passes in the square |

## 11. Replace list, worst first, and the Meshy budget

Balance 2026-11-12: **565 credits** (`meshy_api.py balance`), no monthly allowance. About 35 a model, 10 a retexture,
5 a rig.

| # | Set | Off today | Est. credits |
|---|---|---|---|
| 1 | Army: knight, cavalry rider, horse, 3 engines; retexture the 3 Meshy soldiers | KayKit chibi, blendswap horse, Kenney engines | ~250 |
| 2 | Castle and walls: keep, wall stretch, round and corner towers | MegaKit + Kenney turrets | ~140 |
| 3 | Nature: 4 broadleaf, 3 pine, 2 bush, 2 grass clumps, flower bed; ground texture (Codex) | Quaternius trees and tufts, watercolour ground | ~420 |
| 4 | Props: cart, wagon, barrel, crate, fence, haystack, woodpile, sacks, bench, table | Sketchfab, Poly Haven, Quaternius, Kenney | ~350 |
| 5 | Kit houses retextured | Quaternius MegaKit | ~100 |
| | **Total** | | **~1,260** |

565 covers sets 1 and 2 with retries. Sets 3-5 need more credits: Mac's call. Test-rig one horse on Tripo first
(its quadruped rig) before spending on horses.
