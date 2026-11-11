# Meshy pulls: what we downloaded and generated (2026-11-12)

Follow-up to [meshy-library.md](meshy-library.md) and [soldier-source.md](soldier-source.md). Done in Mac's Chrome
session on meshy.ai. Files live outside git in `~/code/goc-kits/meshy/<name>/` (each with a `SOURCE.md`: post URL,
licence, date). Turntables (Blender 5.2, Cycles on CPU, 1024 px; front, 3/4, side, back, top-3/4) and one contact
sheet per model are in `/tmp/goc-models/meshy/<name>/`. Godot not used (GPU busy filming). The two rigged community units render small in frame (their bounds include the skeleton); look at them zoomed.

Tags: **SEEN** (I looked at it at 100% in our turntable), **VENDOR** (Meshy's page says it).

## Account and cost

- Plan when I started: **Free**, 850 credits (100 monthly + 750 permanent). Free can't download community models
  (the Download button hits a "Subscribe to download" wall). Mac then bought **Starter**: balance 1,115 after the
  plan change (+250), renews 2026-12-12. **VENDOR**
- Starter limits: **15 community downloads a month** (all 15 used today, the button now shows the PRO badge again)
  and **20 downloads of our own models a month** (3 used). 5 concurrent tasks; Private licence on generations;
  A-pose and Multi-view unlocked. **VENDOR + SEEN**
- What things cost (seen in the app's usage history):
  - Community download: no credits, counts against the 15.
  - Image-to-3D, Smart Topology (Meshy T2.5, poly target): 5 model + 10 texture = **15 credits**.
  - Image-to-3D, High Detail (Meshy 7.1, Ultra 2K) with Multi-view: **35 credits**. Meshy drew the left, back and
    right views from our front image for free.
  - Remesh (fixed 10K triangles) and Humanoid auto-rig: **0 credits**.
- **Credits used today: 65** (try 1 15 on Free, try 2 15, try 3 35). Rewards added 130 (daily login 30, two
  onboarding rewards of 50). **Balance now 1,165.**

## Community downloads (15 of 15, all CC0 per Meshy ToS section 3.3)

Verdicts list defects first. "Ready" means usable as-is at RTS camera height after the house-colour mask, not
"clears the concept at 100%".

| Folder | Post | Tris | Sheet | Defects at 100% | Verdict |
|---|---|---|---|---|---|
| forge | [Village Blacksmith Forge](https://www.meshy.ai/posts/village-blacksmith-forge-01a126fa-4513-7714-a689-18aa09baefa1) | 4,862 | forge/forge_sheet.jpg | Back and side walls are plain, repeated stone (front-only detail); roof slates slightly soft at the back | Ready. Best of the set |
| lumber_mill | [Lumber Mill with Water Wheel](https://www.meshy.ai/posts/lumber-mill-with-water-wheel-01a126fb-23b7-731a-b37e-d0d8213307f1) | 4,880 | lumber_mill/lumber_mill_sheet.jpg | Back wall planks warped and uneven at the eaves; saw blade small | Ready from front and 3/4; back needs a look at our camera |
| marketplace | [Stylized Marketplace](https://www.meshy.ai/posts/stylized-fantasy-marketplace-hand-painted-rts-building-01a125c5-8ece-7089-a248-88c5fa86af2f) | 2,816 | marketplace/marketplace_sheet.jpg | Back roof tiles crumpled at the ridge; gable infill smeared beige on one side; coin sign is a generic gold disc | Ready from the front half; back roof is a visible defect |
| mine | [Mine Entrance with Ore Cart](https://www.meshy.ai/posts/mine-entrance-with-ore-cart-01a126fc-cd82-778c-84fe-77ace7fb1218) | 4,787 | mine/mine_sheet.jpg | Back is one blank stepped rock slab; a dark gap at a base corner from above | Ready if placed against a hill / back to the camera never shown |
| treasury | [Royal Treasury Bank](https://www.meshy.ai/posts/royal-treasury-bank-01a126fd-fe2f-733c-9ca6-7af574cfc3ee) | 9,682 | treasury/treasury_sheet.jpg | **"$" dollar sign** on both gables (anachronistic); a black plank-like sliver across the vault door; thin black shard on the ground | Not ready: repaint the emblem, cut the sliver |
| tavern | [Tavern](https://www.meshy.ai/posts/tavern-01a125da-3717-762a-8787-48ea7ccd5fed) | 1,283,956 | tavern/tavern_sheet.jpg | Raw 1.28M tris, needs decimation to 5-10k; chimney smoke is solid grey blobs (cut them, use our particles); back wall plain | Best-looking building pulled. Ready after decimate and smoke cut |
| house | [Half-Timbered Village House](https://www.meshy.ai/posts/half-timbered-village-house-01a12700-5f89-71b8-bf2a-6aeccca80613) | 1,945,880 | house/house_sheet.jpg | Raw 1.95M tris; has a beer-mug sign (reads as a second inn); solid grey smoke blobs; from above the roof planes overlap messily | Ready after decimate, smoke cut and sign removed; strong half-timber look at roof height |
| market_stalls | [Medieval Market Stalls](https://www.meshy.ai/posts/medieval-market-stalls-01a126fe-e4a9-7553-a625-3d1c5cc62122) | 1,916,416 | market_stalls/market_stalls_sheet.jpg | Raw 1.92M tris; small half-timber shed welded to the stalls (one piece, can't place stalls alone); coin sign generic | Ready after decimate; awnings take house colour |
| town_guard | [Town Guard Soldier](https://www.meshy.ai/posts/town-guard-soldier-01a12703-0f12-731a-9cb7-d89a2a86fa99) | 10,602 | town_guard/town_guard_sheet.jpg | Rigged (Mixamo skeleton) with all its clips in one GLB. 2x our unit budget; face realistic-ish next to our painted concepts | Usable as a town guard / NPC, not as an army unit |
| young_ranger | [Young Ranger](https://www.meshy.ai/posts/young-ranger-01a12706-eb7a-7600-85cd-e8e27b9402c6) | 10,674 | young_ranger/young_ranger_sheet.jpg | Rigged (Mixamo), Walking clip only ("All Added" refused: over 20 actions). No bow | Usable as a villager / archer body |
| catapult | [Crownguard Catapult](https://www.meshy.ai/posts/019aee50-a1af-74c5-839d-3374f85ec6da) | 1,394 | catapult/catapult_sheet.jpg | Arm and cup are one piece with the frame (no separate throwing arm to animate); stone is a loose separate lump | Ready as a static engine; arm needs splitting to animate |
| guard_tower | [Crownguard Guard Tower](https://www.meshy.ai/posts/019b02b0-e012-7bc2-a2ec-8df3eb96cff0) | 1,996 | guard_tower/guard_tower_sheet.jpg | Roof shingles melted/smeared on one side; small cracks in base stone | Ready at RTS height; roof is the house-colour candidate |
| gatehouse | [Gatehouse (lumbynathan1992)](https://www.meshy.ai/posts/0199686f-024c-762e-99d4-5a7204df02c1) | 9,959 | gatehouse/gatehouse_sheet.jpg | Same door on both faces; gate is closed solid geometry (no opening to walk through); crenels soft | Ready as a wall-gate piece. Fills the gatehouse gap |
| well | [Stone Well Circular (GobWiz)](https://www.meshy.ai/posts/019eac04-fa1b-7614-812a-55e047bd37ea) | 22,798 | well/well_sheet.jpg | Shingles are many loose overlapping cards (most of the 22.8k tris); top of roof a flat smeared disc | Ready after a decimate to about 5k |
| market_cart | [Medieval Market Cart - Low Poly](https://www.meshy.ai/posts/medieval-market-cart-low-poly-01a19192-819b-750c-a08e-62312892d03c) | 5,633 | market_cart/market_cart_sheet.jpg | Money-bag sign with "$" (repaint); sword banner on the side reads as a guild crest | Ready after repainting the sign; blue/cream stripes take house colour |

Picked over the rest of the creator set (orc brute, orc warrior, skeleton, wizard tower, alchemist, golden paladin,
butcher, weapons): orcs, undead and magic aren't our realm, the paladin reads as Alliance, and the four weapon props
are cheap to generate ourselves out of the 20 own-model downloads. Gap search: I looked at about 400 community
posts tagged gatehouse, wall, well, dock, banner, trebuchet, ballista, siege, bridge, barracks, stable, church,
windmill, cart; only the gatehouse, well and cart were in our painted style and low-poly. Docks, banners and
trebuchets in this style don't exist there (ballistas and siege rigs are realistic, 100-420k tris).

## The man-at-arms (generated, Private licence)

Input: `~/code/goc-kits/meshy/man_at_arms/input/front_body.png`, the body cropped from the concept (sword and
lion shield left out, they become hand-bone props). No side/back sheet existed at `bakeoff/tripo/man_at_arms/`.

| Try | Settings | Tris | File | Sheet |
|---|---|---|---|---|
| 1 | Free tier, Smart Topology T2.5, 8k target, Meshy N1 texture, no pose, CC BY 4.0 | ~8k | not downloaded (CC BY) | - |
| 2 | Starter, Smart Topology T2.5, 8k target, Meshy 7 texture 2K, **A-pose**, Private; then Meshy auto-rig | 8,422 | try2_apose_meshy7.glb, try2_rigged_mixamo.glb | man_at_arms_try2/man_at_arms_try2_sheet.jpg |
| 3 | High Detail Meshy 7.1 Ultra 2K, **Multi-view** (Meshy drew left/back/right), Meshy 7 texture 2K, A-pose, Private; Remesh 10K | 10,339 | try3_multiview_remesh10k.glb | man_at_arms_try3/man_at_arms_try3_sheet.jpg |

**Try 2, defects first (SEEN):**
1. **No cape.** The concept's blue cape is gone; the back repeats the front's lion tabard instead.
2. Back plate and back of the helmet a shade darker grey than the front (still steel, not brown: rule 5 passes, just).
3. Lion emblem softer and blobbier than the concept's.
4. UVs are an automatic atlas of hundreds of small islands (`man_at_arms_try2/uv_over_albedo.png`): fine for the
   hue mask, useless for hand-painting.
5. One fused mesh (body only by design; weapons will be separate props).
Passes: no seam specks or holes seen in any view, gold trim crisp against steel, steel lit from every side, belt and
buckle clean, face reads under the visor, 8.4k tris, clean A-pose that auto-rigged without fixes.

**Try 3, defects first (SEEN):**
1. **Cape has dark baked-shadow blotches** on its sides (rule 3 fails).
2. **Face almost lost** behind a deeper visor; only a cheek shows (rule 7 weak). Helmet slightly asymmetric.
3. Same fragmented auto-UVs; 10.3k tris after remesh (on budget).
Passes: the cape is there and hangs right from the back, steel lit from all sides, trim crisp, no holes seen.

**Verdict: neither clears the concept at 100%.** Try 2 is the cleaner body and already rigged; it misses the cape.
Try 3 has the cape but brings smears and hides the face. Three tries used (the cap), 65 credits. Next step if Mac
wants it: re-texture try 3's mesh with Meshy 7 using the front image only (texture stage is 10 credits), or take
try 2 and add the cape as a separate cloth piece.

## Next

- Re-render the three towns pieces in the batched Godot render (house-colour mask on roofs and awnings) beside
  01-town; that is the real judge at roof height.
- Decimate tavern, house, stalls and well in Blender to 5-10k before import.
- Repaint the "$" on the treasury and the cart.
