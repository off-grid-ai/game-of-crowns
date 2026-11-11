# Where the soldiers come from: one source for the 12 army units (2026-11-12)

Question: who already makes Warcraft III / AoM Retold grade soldier models, so we stop hand-fixing TRELLIS v1?
Twelve units from the concepts (man-at-arms, knight, spearman, archer, crossbowman, axeman, warhammer, light and
heavy cavalry, war elephant, cannon, general): clean painted look, clear silhouettes, ≤5k tris, rigged, a white
cloth region we tint in house colour, a shield face or chest for the emblem.

Tags: **VENDOR** (the maker says it), **REVIEW** (third-party test or write-up), **TESTED** (we ran it),
**ESTIMATE** (my judgement).

## Mac's bar (2026-11-12), judged on a four-view turntable

1. No black specks or holes along texture seams.
2. No torn or ragged cloth edges (tabard hem).
3. No smeared or blotched flat areas (shield face).
4. Clean edges between materials (gold trim against steel).
5. Steel stays light from every side (not dark brown at the back or sides).
6. Sword and shield are separate, solid pieces.
7. The face reads.

Our TRELLIS v1 man-at-arms (`/tmp/goc-models/man_at_arms_fixed_sheet.jpg`) fails 1, 2, 3, 4, 5 and 6. Its
shape is right; the texture and the fused shield are what break it.

## The pick: Tripo (Pro plan, $20 for one month), body and props generated apart

**Why.** It is the only option that covers every item in one product: a newer image-to-3D model than ours with
multi-view input (front, side and back images, which is what fixes rule 5), a low-poly mode with a face target
(≤5k), a part split that separates weapon from hand (rule 6), auto-rig for bipeds and four-legged animals (horse,
elephant), and commercial rights on paid plans. In the one public blind test (run by Meshy's own staff, so if
anything biased against it) Tripo won geometry in every pairing and led textured output with multi-view input.
REVIEW: [HackerNoon stress test, Meshy 6 vs Tripo v3.1 vs Rodin Gen-2.5](https://hackernoon.com/lang/ja/how-i-stress-tested-3-ai-3d-generators-on-the-same-inputs-what-the-numbers-actually-show).

**How we use it (the part that answers the bar).**
- **Feed it turnarounds, not one picture.** Codex makes front, side and back views of each unit in the same
  style prompt (Mac OK'd Codex image gen). Back-side darkness (rule 5) and the smeared hem (rule 2) come from the
  model guessing the unseen sides; three views remove the guess.
- **Bodies without weapons, weapons as props.** Generate each soldier empty-handed in a relaxed A-pose, and the
  sword, shield, spear, bow, crossbow, axe and hammer as separate small models attached to the hand bone. That is
  how Warcraft III and every RTS kit does it (Quaternius' knight notes the same: weapons on the hand bone), it
  makes rule 6 true by construction, lets one body carry several weapons, and gives a flat shield face for the
  emblem (rule 3). Tripo's part split is the fallback when a pose fuses.
- **House colour mask by script.** The concepts' cloth is white; a mask is every low-saturation, high-value texel
  in the albedo (the WC3 approach, already our shader's plan). One small Blender script per model: decimate
  check, weld, mask, export glTF.
- **Rig.** Tripo's auto-rig for the bodies, horse and elephant (25 credits each, VENDOR); bodies can go through
  Mixamo instead if its skeleton fits our clips better.

**Cost.** Tripo Pro: $20/month, 3,000 credits, commercial use (REVIEW:
[Costbench, verified Nov 2026](https://www.costbench.com/software/ai-3d-generation/tripo-ai/); the official page
blocks scripted reads). Per unit ≈ 30 (multi-view model) + 30 (texture) + 25 (rig) + 10-40 (retopology) ≈ 100-130
credits (VENDOR: [Tripo developer page](https://developers.tripo3d.ai/)). 12 bodies + 8 props with three retries
each fits in 3,000. One month is enough: **$20 total, ≤$90 worst case** (Max plan if we burn through it).

**Not yet proven on our concepts.** Hands-on tests were blocked today: the HF ZeroGPU quota on this Mac's login
is spent (TRELLIS.2 and Hunyuan3D 2.1 Spaces both refused; resets in ~17 h), and Tripo needs an account Mac
creates. So the pick is gated: **the man-at-arms goes first and must pass all seven rules on a turntable before
we make the other eleven.** If it fails, the fallback is Meshy (row 2), same pipeline.

## Ranked table

Bar grades are expected results from published tests and samples, not our own runs (none was possible today).
✓ likely passes, ~ partly, ✗ likely fails.

| # | Option | Bar 1-7 (expected) | WC3/AoM fit | Cost for 12 | Licence | Rig / team colour | Time to 12 | Main risk |
|---|---|---|---|---|---|---|---|---|
| 1 | **Tripo** (Pro), multi-view + low-poly + auto-rig, props apart | 1 ✓ 2 ~ 3 ✓ 4 ~ 5 ✓ 6 ✓ 7 ~ | Good: matches our concepts' painted look; low-poly mode at a face target | $20 (≤$90) | Paid plans commercial; free plan non-commercial | Auto-rig biped + quadruped; mask by script | 2-3 days (ESTIMATE) | Texture still AI-baked: gold trim edges may blur (rule 4); face small and soft (rule 7) |
| 2 | Meshy 6 (Pro), same pipeline | 1 ✓ 2 ~ 3 ✓ 4 ~ 5 ~ 6 ~ 7 ~ | Good; Meshy led textured single-view in its own test | ~$20 (1,000 credits; 20 + 10 per model, rig and remesh free) | Paid: private, commercial ([Meshy docs](https://docs.meshy.ai/pricing)) | Auto-rig humanoid only (no elephant rig) | 2-3 days | Geometry ranked last in the same test; "adjacent parts merging" on complex inputs |
| 3 | Hunyuan3D 3.1 (Tencent global site) | 1 ✓ 2 ~ 3 ✓ 4 ~ 5 ✓ 6 ✗ 7 ~ | Good textures (paint model) | Free (20/day) | Unclear for 3.x; the 2.1 licence excludes EU, UK, South Korea ([licence](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/blob/main/LICENSE)) | No rig, no part split | 3-4 days | Licence; no low-poly target; Mac signs up |
| 4 | TRELLIS.2 / Hunyuan3D 2.1 via HF Spaces (HF PRO $9 for 40 min/day) | 1 ~ 2 ~ 3 ~ 4 ~ 5 ~ 6 ✗ 7 ~ | Unknown on our style | $9 | TRELLIS.2 MIT, but its background remover RMBG-2.0 is CC BY-NC; Hunyuan region-limited | None; 300k-tri output to decimate | 4-5 days | Same class of artefacts as v1, only sharper; we'd still hand-fix |
| 5 | TRELLIS.2 / Hunyuan 2.1 locally on this Mac | ✗ textures | - | Free | as above | none | - | Mac ports bake textures in 66-224 min and testers call them unusable ([lilting.ch M1 Max test](https://lilting.ch/en/articles/trellis2-m1-max-hands-on)); Hunyuan disables texture on macOS ([PR](https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1/pull/105)) |
| 6 | Rodin Gen-2.5 (Creator $30) | 1 ✓ 2 ~ 3 ✓ 4 ✓ 5 ~ 6 ✗ 7 ✓ | Fine detail, weaker overall structure | $30-60 | Check terms | No auto-rig | 3-4 days | Pays per download; structure errors (REVIEW, same test) |
| 7 | Kit: Toon RTS Units (Polygon Blacksmith, Unity) | all ✓ (hand-made) | Low: flat toy look, not our painted concepts | $25 | Unity EULA (fine in Godot, single entity) | Humanoid rig except cavalry; 9 colour skins, no mask | 1 day | No elephant, no cannon; looks like a mobile game ([store](https://assetstore.unity.com/packages/3d/characters/toon-rts-units-67948)) |
| 8 | Kit: Synty POLYGON Knights / Fantasy Kingdom | all ✓ | Low: flat-shaded palette; cavalry only in the $199.99 Sidekick pack | $15-30 (+$200) | Synty EULA, 5 seats | Humanoid rig; palette swap gives team colour | 1-2 days | Look miles from the concepts; no elephant or cannon crew ([store](https://syntystore.com/products/polygon-knights-pack)) |
| 9 | Kit: Quaternius / KayKit / Kenney (CC0) | all ✓ | Very low: toy look; our asset audit already bans Quaternius' kit look | Free | CC0 | Rigged, simple | 1 day | Rejected look (docs/review/asset-audit.md) |
| 10 | Hybrid: kit body + concept-painted texture | ~ | Medium | Kit + days of painting | Mixed | Kit rig | 1-2 weeks | Hand-built texture work; not "who already built this" |

Why no kit wins: the hand-made kits pass the bar's cleanliness rules by construction, but none matches the
concepts' gold-trimmed painted plate, and none has a war elephant or a crewed cannon. They are the floor if
every AI route fails, not the pick.

## Sample links

- Tripo: [segmentation splits weapon from hand](https://www.tripo3d.ai/blog/split-3d-model-into-parts),
  [Smart Mesh low-poly](https://www.barchart.com/story/news/936837/tripo-ai-introduces-smart-mesh-p1-0-defining-a-new-phase-for-ai-3d-production),
  [80.lv on Tripo's topology](https://80.lv/articles/how-tripo-is-tackling-clean-topology-for-its-3d-asset-pipeline),
  [low-poly for games](https://www.tripo3d.ai/game-development/accelerate-low-poly-modeling-game-development-tripo).
- Independent caution on Tripo low-poly: [Neural4D review of Tripo 3.1](https://newsletter.neural4d.com/p/tripo-3-1-model-review)
  ("does not fully replace manual cleanup for hero assets"); our units are not hero assets at RTS zoom.
- TRELLIS.2: [project page](https://microsoft.github.io/TRELLIS.2), [Space](https://huggingface.co/spaces/microsoft/TRELLIS.2).
- Hunyuan3D 2.1: [Space](https://huggingface.co/spaces/tencent/Hunyuan3D-2.1), [paper](https://arxiv.org/html/2506.15442v1).
- Kits: [Toon RTS Units](https://assetstore.unity.com/packages/3d/characters/toon-rts-units-67948),
  [Synty Knights](https://syntystore.com/products/polygon-knights-pack),
  [Quaternius knight (CC0)](https://quaternius.itch.io/lowpoly-animated-knight).

## First step

1. **Mac:** sign up at tripo3d.ai and take the Pro plan ($20, one month). Either make the man-at-arms in Tripo
   Studio yourself from the three views below, or create an API key and save it to a file only you type
   (e.g. `~/.config/goc/tripo.key`); the script reads it, nobody pastes it.
2. **Us (no GPU needed):** Codex makes the man-at-arms front, side and back views, empty-handed, A-pose, plus the
   sword and the shield alone. Tripo makes body (multi-view, low-poly ~4k), sword and shield; auto-rig the body.
3. **Gate:** Blender four-view turntable of the result, graded on rules 1-7 beside the TRELLIS sheet, sent to
   Mac in the next batched render. Pass → the other eleven the same way. Fail → same run on Meshy before anything
   else.
