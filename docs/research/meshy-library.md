# Meshy's community library: what's usable for Game of Crowns (2026-11-12)

Question (Mac): Meshy's community medieval library ([tag: medieval](https://www.meshy.ai/tags/medieval),
[medieval & viking](https://www.meshy.ai/subcategory/medieval-viking), e.g.
[Middle Ages Tower](https://www.meshy.ai/posts/middle-ages-tower-019fe4d3-e3e3-7fd0-82ea-a0ba0451a86e)). Can we use
it, what fits the North Star (Warcraft III Reforged look, house colours), and where do we generate our own instead?

How I looked: read only, not signed in, nothing downloaded. Meshy's public read API (the one its own pages call:
`/meshyd-api/web/public/community/posts?tags=…` and `/v2/tasks/<id>`) gives each post's licence, face count,
generator and rig state; I turned the best ones in the page's 3D viewer (front, side, back) and zoomed.
Roughly 300 posts checked across knight, soldier, archer, cavalry, horse, catapult, trebuchet, siege, castle, house,
windmill, cart, barrel, sheep, cow, lowpoly, stylized, handpainted, rts and warcraft, plus three creators' full lists.

Tags: **VENDOR** (Meshy says it), **SEEN** (I looked at it in the viewer), **ESTIMATE** (my judgement).

## 1. Licence and terms

- **Every community model is CC0.** Terms of Service §3.3 "Community License" (last updated 2026-09-19): "Customer
  Output, including 3D models, is licensed under the Creative Commons Zero (CC0) 1.0" …
  ([meshy.ai/terms-of-use](https://www.meshy.ai/terms-of-use)). The API's `license` field said `cc0` on every
  post I pulled, and each viewer shows a CC0 badge. **VENDOR + SEEN**
- **CC0 means commercial use, no attribution, edits allowed.** Images posted to the community (not models) are
  CC BY-NC 4.0; we don't need those.
- **Downloading needs a paid plan.** Pricing page: Free has no community downloads; Starter 15 downloads a month;
  Pro and above unlimited ([meshy.ai/pricing](https://www.meshy.ai/pricing)). **VENDOR**
- **What we make ourselves** is ours on a paid plan (private, customer-owned); on Free it's CC BY 4.0 with credit to
  Meshy (§3.2). **VENDOR**
- **The catch: CC0 only covers the uploader's rights.** If a model copies someone else's design, CC0 doesn't clean
  it. Some of the most WC3-looking pieces are near-copies of Blizzard units (see Crownguard below). Our style prompt
  already says "no real franchise", so those are out. **ESTIMATE**

## 2. What's there

**The big picture.** About 95% of the medieval library is raw, unremeshed output: 0.2-3 million triangles,
"realistic" texture mode, not rigged, every creator in a different style (statues, chibi, photoreal, steampunk).
None of the popular knights, horses or siege engines is usable as is. **SEEN** (knight tag: 24 of 24 between 87k and
3.1M faces, none rigged.)

What does fit comes from a handful of creators working in a game style. Three of them matter:

### A. Creator `s17912285991ac39`: a hand-painted RTS town set (best find)
22 posts, all one look: Warcraft III Reforged / WoW hand-painted, chunky, on small cobbled bases. Made with
Meshy's own "Smart Topology + Meshy T2.5 + Meshy 7 (Texture)" pipeline. **SEEN**

| Model | Link | Tris | Rig | Fit |
|---|---|---|---|---|
| Lumber Mill with Water Wheel | [post](https://www.meshy.ai/posts/lumber-mill-with-water-wheel-01a126fb-23b7-731a-b37e-d0d8213307f1) | 4,880 | – | Strong: clean planks, crisp edges all round |
| Village Blacksmith Forge | [post](https://www.meshy.ai/posts/village-blacksmith-forge-01a126fa-4513-7714-a689-18aa09baefa1) | 4,862 | – | Strong: slate roof, anvil, barrel |
| Stylized Marketplace (RTS building) | [post](https://www.meshy.ai/posts/stylized-fantasy-marketplace-hand-painted-rts-building-01a125c5-8ece-7089-a248-88c5fa86af2f) | 2,816 | – | Strong: striped awnings, crates; red roof (house-colour candidate) |
| Mine Entrance with Ore Cart | [post](https://www.meshy.ai/posts/mine-entrance-with-ore-cart-01a126fc-cd82-778c-84fe-77ace7fb1218) | 4,787 | – | Good |
| Royal Treasury Bank | [post](https://www.meshy.ai/posts/royal-treasury-bank-01a126fd-fe2f-733c-9ca6-7af574cfc3ee) | 9,682 | – | Good (a guildhall / counting house) |
| Tavern | [post](https://www.meshy.ai/posts/tavern-01a125da-3717-762a-8787-48ea7ccd5fed) | 1,283,956 | – | Look is right (our inn); mesh needs a remesh to ~5k |
| Half-Timbered Village House | [post](https://www.meshy.ai/posts/half-timbered-village-house-01a12700-5f89-71b8-bf2a-6aeccca80613) | 1,945,880 | – | Same: remesh first |
| Medieval Market Stalls | [post](https://www.meshy.ai/posts/medieval-market-stalls-01a126fe-e4a9-7553-a625-3d1c5cc62122) | 1,916,416 | – | Same: remesh first |
| Arcane Crystal Wizard Tower | [post](https://www.meshy.ai/posts/arcane-crystal-wizard-tower-01a126f8-6dc7-7119-9c01-d41c0518be60) | 4,828 | – | No: magic, not our realm |
| Town Guard Soldier | [post](https://www.meshy.ai/posts/town-guard-soldier-01a12703-0f12-731a-9cb7-d89a2a86fa99) | 10,522 | Rigged + clips | Good look (helm, mail, red skirt); 2x our budget |
| Golden Paladin Knight | [post](https://www.meshy.ai/posts/golden-paladin-knight-01a12709-96ef-70f2-9f6d-d7cf07853514) | 10,055 | Rigged + clips | Too fantasy (gold and blue, gryphon pauldron); reads Alliance |
| Young Ranger | [post](https://www.meshy.ai/posts/young-ranger-01a12706-eb7a-7600-85cd-e8e27b9402c6) | ~10k | Rigged + clips | Possible archer |
| Longsword, Recurve Bow, Spear, Battle Axe | [sword](https://www.meshy.ai/posts/knight-s-longsword-01a12708-b853-762d-adee-ee73636ef882), [bow](https://www.meshy.ai/posts/recurve-bow-01a12707-cdf4-75c6-82b2-cbcbd9cf7bc1), [spear](https://www.meshy.ai/posts/wooden-spear-01a12701-692e-77d2-be96-b48ac3d9cef0), [axe](https://www.meshy.ai/posts/double-bladed-battle-axe-01a12705-1a8c-743d-810b-94d395f9a5b5) | ~3k each | – | Separate weapon props (our hand-bone plan) |

Each building sits on its own cobbled square; we'd cut that base off or keep it as the plot's yard.

### B. Creator `ProteinPenguin`: "Crownguard (Medieval Humans)", a WC3-style faction
13 posts, 1,000-2,500 tris each (WC3's own counts), remeshed in Meshy, CC0. **SEEN**

| Model | Link | Tris | Note |
|---|---|---|---|
| Footman | [post](https://www.meshy.ai/posts/019b0269-5e23-7542-bfa6-cfdbe3bf0420) | 1,000 | Sword and lion shield are separate pieces. Blue tabard, gold trim. A near-copy of WC3's Alliance Footman |
| Knight (+ horse) | [post](https://www.meshy.ai/posts/019b0257-7787-7933-aca3-bdf437e80ded) | 1,493 | Same Alliance look |
| Catapult | [post](https://www.meshy.ai/posts/019aee50-a1af-74c5-839d-3374f85ec6da) | 1,394 | Generic wooden catapult with iron-banded wheels. The one clean siege engine I found |
| Guard Tower | [post](https://www.meshy.ai/posts/019b02b0-e012-7bc2-a2ec-8df3eb96cff0) | 1,996 | Stone base, timber top, blue shingle roof (house-colour candidate) |
| Royal Academy (barracks) | [post](https://www.meshy.ai/posts/019b02b4-410c-79c5-8294-6dfdc6c61218) | 2,480 | – |
| Robin Hood, King/Sir Gallahad, Griffin, Sky Pirate, Battlemage | via [profile](https://www.meshy.ai/@ProteinPenguin) | 1-2k | Heroes and fantasy; out |

The footman and knight are too close to Blizzard's to ship (lion shield, Alliance blue and gold). The catapult and
guard tower are generic enough to use. **ESTIMATE**

### C. Creator `s1783932131a3ee1`: white-tabard infantry (closest to our soldier plan)
| Model | Link | Tris | Note |
|---|---|---|---|
| Light infantry | [post](https://www.meshy.ai/posts/019f8eca-2a64-72d8-b27c-7191160eafec) | 2,869 | Kettle helm, **white tabard** (ready for the house-colour mask), no weapons, T-pose. Not rigged |
| Heavy infantry | [post](https://www.meshy.ai/posts/019f8ecb-0d06-7ee1-b29c-7abb0f3a283b) | 3,495 | Black plate over a white tabard; same set |
| Armoured horse | [post](https://www.meshy.ai/posts/019f612a-5e22-77bb-8a58-e141082424db) | 11,048 | Bard and saddle; darker, more realistic than A or B |

### Other single finds (each in its own style)
| What | Link | Tris | Rig | Style vs ours |
|---|---|---|---|---|
| Market Stall / Market Stall Round / Goods Kart (`s1791459643eba3a`) | [stall](https://www.meshy.ai/posts/market-stall-01a1bc8c-dd88-7003-915d-5a42b4b39d89), [round](https://www.meshy.ai/posts/01a1b695-d204-7679-b2b2-b257d405eab0), [kart](https://www.meshy.ai/posts/goods-kart-01a1bc8c-856a-7468-be7f-fde9e11ed88c) | 5-6k | – | Painted, a bit muted; close to set A |
| Medieval Market Cart, low poly | [post](https://www.meshy.ai/posts/medieval-market-cart-low-poly-01a19192-819b-750c-a08e-62312892d03c) | 5,633 | – | Close to set A |
| Windmill | [post](https://www.meshy.ai/posts/windmill-01a1306d-eefe-7408-a84d-ba2c88ec731d) | 3,680 | – | Flat cartoon, white and red; weaker than set A |
| Castle | [post](https://www.meshy.ai/posts/castle-01a1c6b7-8a71-70d8-be70-89f5e06f9977) | 14,840 | – | Toy-like cartoon keep; one piece, not kit parts |
| Pack mule | [post](https://www.meshy.ai/posts/pack-mule-01a12ccc-e503-700b-abcf-5719d781034b) | 20,376 | – | Realistic; doesn't match |
| Cow (rigged) | [post](https://www.meshy.ai/posts/cow-rigged-01a16c43-e687-75f5-bee9-ab5be8498b90) | – | Rigged | Realistic Holstein; doesn't match |
| Low Poly Cute Sheep | [post](https://www.meshy.ai/posts/low-poly-cute-sheep-01a1c213-bd51-7774-82b3-29c835838885) | – | Rigged | Chibi faceted; doesn't match |
| Middle Ages Tower (Mac's link) | [post](https://www.meshy.ai/posts/middle-ages-tower-019fe4d3-e3e3-7fd0-82ea-a0ba0451a86e) | 1,077,292 | – | Photoreal ruin with ivy; out |
| Trebuchets | e.g. [1](https://www.meshy.ai/posts/019565d4-15d6-7285-af99-a10b24476332), [2](https://www.meshy.ai/posts/0195f68e-12b8-7ada-a7ed-76dfbc81f863) | ~100k | – | Realistic, smeared; none usable |

Missing entirely in a matching style: castle kit parts (wall runs, gatehouse, corner towers), a stylised trebuchet,
cannon, war elephant, crossbowman, spearman blocks, and farm animals.

## 3. Quality against Mac's unit bar (seen in the viewer, not in our engine)

| Rule | Set A buildings (forge, mill, market) | Crownguard (footman, catapult, tower) | Infantry C | Typical popular post |
|---|---|---|---|---|
| 1 No seam specks or holes | ✓ none seen | ✓ none seen | ~ dark red blotches on the upper back | ✗ often |
| 2 Clean cloth edges | ✓ awnings clean | ✓ cape hem clean | ✓ tabard hem clean | ~ |
| 3 No smears on flat areas | ✓ | ✓ shield face crisp | ~ back of tabard blotched | ✗ |
| 4 Crisp material edges | ✓ wood/stone/slate crisp | ✓ gold trim crisp | ✓ | ~ |
| 5 Metal light from every side | n/a (anvil fine) | ✓ steel light from the back | ✓ helm light from behind | ✗ backs go dark |
| 6 Weapon and shield separate | n/a | ✓ separate pieces | ✓ no weapons (props go on the hand bone) | ✗ fused |
| 7 Face reads | n/a | ✓ at unit scale | ✓ bearded face reads | – |

So the Smart-Topology / Meshy 7 output (set A) and the remeshed low-poly sets clear the bar on what the viewer
shows. The raw high-poly majority doesn't. Not checked yet: UV layout, texture size and normals after import into
Godot. That needs one download.

## 4. Recommendation

1. **Buildings: use set A for the landmark buildings.** Forge, lumber mill (sawmill), market, mine, treasury
   (guildhall), plus the tavern and house once remeshed. It's the one consistent, licensed (CC0), on-target set, and
   it matches our style prompt ("Warcraft III Reforged, hand-painted, chunky"). House colour: roofs and awnings get the
   mask by hue (red tile, slate, stripes); stone and wood stay. Risk: it's more colourful and fantasy than our Kenney
   and Quaternius town houses, so the whole town has to move to it or it'll look patched. Fill ordinary plots by
   generating more houses in the same pipeline (below), not by mixing kits. **ESTIMATE**
2. **Siege and towers: take the Crownguard catapult and guard tower.** Generic designs, WC3 triangle counts.
   Generate the trebuchet, cannon and wall/gate kit ourselves.
3. **Soldiers: generate our own; don't take community units.** The best WC3-like ones copy Blizzard; the
   white-tabard infantry (C) proves the look we want is reachable in Meshy at ~3k triangles, but there are only two of
   them and they have back smears. Our 12 units need one consistent set.
4. **Animals and small props:** market stalls, carts and the goods kart from the matching creators are fine. Animals
   on Meshy are realistic or chibi, so generate horse, ox, sheep and pig in our style (or keep what we have).
5. **Where to generate (Mac already has a Meshy account):** image-to-3D from our concept turnarounds (Codex front,
   side and back, as in [soldier-source.md](soldier-source.md)), with Smart Topology / remesh to 2-5k triangles,
   hand-painted texture, then Meshy's auto-rig for bodies and horses. That's the exact pipeline that produced set A and
   the infantry above, so we stay in one look. It's a real alternative to the Tripo plan: same gate (man-at-arms
   first, must pass all seven rules on our turntable). Prompting tip from set C: "game-ready stylised medieval … unit,
   white tabard, no weapon, T-pose".
6. **Plan:** downloading community models needs Starter (15 a month) or Pro (unlimited). Set A plus the catapult and
   tower is ~12 files, so one month of Starter covers it; generating our own wants Pro credits.

Next step if Mac agrees: one download of the forge and the catapult. Import into Godot, apply the house-colour mask
to the roof, and render them beside 01-town at roof height in the next batched render.
