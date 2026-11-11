# Free RTS kits against the North Star (2026-11-12)

Question (Mac): Quaternius and the other free kits on his two lists. Do any of them get closer to the painted
Warcraft III look in `docs/art/target` than what we have, for units, buildings, castle, props or terrain?
Direction is settled: stylised Warcraft III (A), not realistic Manor Lords.

Contact sheet (preview images beside our man-at-arms concept, 01-town and 03-army):
`/tmp/goc-models/quaternius_sheet.jpg` (same file: `/tmp/goc-models/free_rts_kits_sheet.jpg`).

Tags: **VENDOR** (the maker's page says it), **TESTED** (we checked files on disk), **ESTIMATE** (my judgement
from preview images).

## Short answer

- **No free kit reaches the painted look of 01-town or 03-army.** Every one is a solid-colour or
  gradient-atlas low-poly kit. Next to the concepts they look like toys: flat colour, no painted wear, no
  gold trim, no cloth folds (ESTIMATE, sheet rows 2-4).
- **Quaternius' new MegaKits are the exception, and we already use their free tiers.** Village, Fantasy Props
  and Stylized Nature are textured and lit like a Ghibli/Fortnite scene, much nearer the target than the old
  flat packs. Their paid tiers add the missing pieces (Village 300+ pieces, the plate-armour knight outfit).
- **Units: keep the plan in soldier-source.md (Tripo from our concepts).** The one free kit worth adding is
  **KayKit Character Animations** (CC0, about 150 clips): our army knight is already KayKit Adventurers 1.0, and
  its bones are the same Rig_Medium names, so the clips should drop in (still to test).
- **Terrain: we already run Terrain3D** (`realm/scripts/land3d.gd`), so there's nothing to upgrade there.
  w3terrain needs Warcraft III's own game files, so it's out (no ripped Blizzard data).
- **Downloads: none made.** Nothing free beat what we hold, so there was nothing to download. The KayKit
  animations are free but behind itch's $0 checkout, which wouldn't run from a script ("invalid key"), so Mac
  or a browser session clicks it (14 MB).

## What we already have on disk (TESTED)

| Folder | Pack (Quaternius, CC0 unless noted) | Tier | Used |
|---|---|---|---|
| `realm/assets/village/` (198 files) | Medieval Village MegaKit | Standard (free, 170 pieces, VENDOR) | 25 pieces in `house_builder.gd` |
| `realm/assets/props/` | Fantasy Props MegaKit | Standard (free part of 200+) | a few (sword, shield, banners, washing) |
| `realm/assets/nature/` | Stylized Nature MegaKit | Standard | trees, orchards, grass, rocks |
| `realm/assets/people/` | Universal Base Characters + Modular Outfits Fantasy (Peasant, Ranger only) | Standard | townsfolk |
| `realm/assets/anims/` | Universal Animation Library 1 (Godot glTF) | Standard | townsfolk clips |
| `realm/assets/q/` (59 glb) | Ultimate Fantasy RTS (castles "Wonder_*", houses "Houses_FirstAge/SecondAge", walls, towers, temple, market, windmills), Medieval Village Pack (House_1-4, Inn, Stable, Blacksmith, Bell_Tower), Ultimate Animated Animals (deer, wolf, horse), Farm Animals (cow, pig, sheep), Ultimate Animated Characters / RPG (king, farmer), Animated Men/Woman, dragons, giant | free | wolf as the town dog; the rest banned by `docs/review/asset-audit.md` (toy look) |
| `realm/assets/armies/knight/` | **KayKit** Adventurers 1.0 Knight (CC0), 76 clips, Rig_Medium bone names | free | army knight (VAT bake) |
| `realm/assets/castle/` | Kenney Castle Kit (CC0) | free | siege engines, gate, flags |

So Mac's "high interest" pack, **Ultimate Fantasy RTS, is mostly on disk already** (about 25 of its 128
models in `q/`, 1-15k tris each). It is the same flat-shaded look the asset audit rejected.

## Quaternius (quaternius.com, all CC0)

Two generations. The **old packs** (2019-2022) are flat-colour, untextured or atlas, chunky low poly. The
**MegaKits** (2024-2025) are textured, with trim sheets, wear, normals and a free Standard tier plus paid
Pro/Source tiers.

| Pack | Link | What's in it (VENDOR) | Rig / anim | Look (ESTIMATE) | Have | Fits North Star? |
|---|---|---|---|---|---|---|
| Medieval Village MegaKit | [page](https://quaternius.com/packs/medievalvillagemegakit.html) | 300+ modular pieces (free tier 170); Pro $9.99, Source $14.99 with Godot 4.3 project and wear-colour shaders | - | Textured timber, plaster, tile, moss: **the nearest to 01-town of anything free** | free tier | **Yes, keep.** Pro is the cheapest upgrade in this whole survey (more roofs and balconies); Mac's "nothing paid" rule holds, so it's only an option |
| Fantasy Props MegaKit | [page](https://quaternius.com/packs/fantasypropsmegakit.html) | 200+ props (weapons, tools, food, stalls, chests, furniture); Pro adds collisions and worn variants | - | Textured, warm, painterly | free tier | **Yes, props.** 92 of ours are still unused (asset audit) |
| Stylized Nature MegaKit | [page](https://quaternius.com/packs/stylizednaturemegakit.html) | 110+ (40 trees, 35 plants, 27 rocks) | - | Ghibli-style painted foliage | yes | **Yes, nature** |
| Universal Base Characters | [page](https://quaternius.com/packs/universalbasecharacters.html) | 6 bodies, humanoid rig | rigged | Clean stylised | yes | Base bodies only |
| Modular Character Outfits Fantasy | [page](https://quaternius.com/packs/modularcharacteroutfitsfantasy.html) | 12 outfits from 62 parts; free tier = Peasant and Ranger only | rigged | Mid-fidelity textured; the plate knight is in the paid tiers | free tier | Plate knight would make a soldier base, but it's paid |
| Universal Animation Library 1 / 2 | [UAL1](https://quaternius.com/packs/universalanimationlibrary.html), [UAL2](https://quaternius.com/packs/universalanimationlibrary2.html) | 120+ / 130+ clips; UAL2 free tier 42 clips (sword attacks, shield idles, melee) | humanoid | - | UAL1 | UAL2 free tier: worth a look for soldier melee clips |
| Ultimate Fantasy RTS | [page](https://quaternius.com/packs/ultimatefantasyrts.html) (Google Drive, no sign-in) | 128 buildings in ages and upgrade levels (FirstAge/SecondAge, Level1-3), walls, wonders, docks, farms | - | **Flat toy**: solid colours, no texture, 1-15k tris | ~25 in `q/` | **No.** The upgrade-stage idea is good; the art isn't. Next to 01-town it reads as a board game |
| Medieval Village Pack | [page](https://quaternius.com/packs/medievalvillage.html) | 44 | - | Flat | some in `q/` | No |
| Modular Medieval Building / Ultimate Buildings / Farm Buildings | [1](https://quaternius.com/packs/modularmedievalbuildings.html), [2](https://quaternius.com/packs/ultimatetexturedbuildings.html), [3](https://quaternius.com/packs/farmbuildings.html) | 30 / 76 / 13 | - | Flat or simple textures | no | No |
| Ultimate Modular Ruins | [page](https://quaternius.com/packs/ultimatemodularruins.html) | 90 | - | Flat | no | No (we have Sketchfab ruins) |
| Animated Knight | [page](https://quaternius.com/packs/knightcharacter.html) | 10 (knight plus weapons on the hand bone) | rigged, animated | Chibi, flat grey | no | **No.** Far below the man-at-arms concept |
| RPG Characters / Ultimate Animated Characters / Modular Men & Women | [RPG](https://quaternius.com/packs/rpgcharacters.html), [UAC](https://quaternius.com/packs/ultimatedanimatedcharacter.html) | 6 / 52 / 11+10 | rigged, animated | Flat chibi | king, farmer | No |
| Modular Weapons | [page](https://quaternius.com/packs/medievalweapons.html) | 24 | - | Flat | no | Silhouette stand-ins only |
| Ultimate Animated Animals | [page](https://quaternius.com/packs/ultimateanimatedanimals.html) | 12 (deer, stag, horse, wolf, fox, bull, donkey, alpaca, husky...) | rigged, 8-26 clips each | Faceted but readable at roof height | deer, wolf, horse | **Yes, animals at RTS distance** (the dog already uses the wolf). Retint is easy |
| Farm Animals | [page](https://quaternius.com/packs/farmanimal.html) | 7 (horse, cow, pig, sheep, llama, pug...) | rigged, 2-6 clips | Same | cow, pig, sheep | **Yes, livestock** (our only livestock) |
| Ultimate Crops | [page](https://quaternius.com/packs/ultimatecrops.html) | 102 | - | Flat | no | Maybe for far fields; we have crops |
| Ultimate Nature / Ultimate Stylized Nature | [1](https://quaternius.com/packs/ultimatenature.html), [2](https://quaternius.com/packs/ultimatestylizednature.html) | 150 / 63 | - | Older look; the MegaKit supersedes them | trees in `q/` | No, the MegaKit is better |

**The earlier worry, judged on the previews:** it's fair for the old packs and the characters. Flat colour,
chibi bodies and no material breakup sit badly beside our painted concepts. It isn't fair for the
MegaKits: they're textured and would pass in 01-town if the roof tiles took house colour. Where Quaternius
works for us: **textured kit buildings (MegaKit), props, nature, animals at RTS distance, and base bodies
plus animation libraries.** Where it doesn't: soldiers, the castle, and any flat pack as finished art.

## Kenney (kenney.nl, CC0)

| Pack | Link | Contents (VENDOR) | Fit (ESTIMATE) |
|---|---|---|---|
| Medieval RTS | [page](https://kenney.nl/assets/medieval-rts) | 120 files, **2D** tiles and sprites | No, it's 2D |
| Castle Kit | [page](https://kenney.nl/assets/castle-kit) | 75 3D pieces (walls, towers, siege engines) | We have it (`castle/`). Flat pastel toy. Siege engines OK as stand-ins; castle no |
| Fantasy Town Kit | [page](https://kenney.nl/assets/fantasy-town-kit) | 160 3D pieces | Flat toy; no |
| Retro Medieval Kit | [OpenGameArt](https://opengameart.org/content/retro-medieval-kit) (kenney.nl page now 404) | 100 models, low-res retro textures | Deliberately PS1-style; no |

## KayKit (Kay Lousberg, itch.io, CC0)

| Pack | Link | Contents (VENDOR) | Fit (ESTIMATE) |
|---|---|---|---|
| Medieval Hexagon | [itch](https://kaylousberg.itch.io/kaykit-medieval-hexagon) | Free: 200+ hex tiles, buildings, props; **every building in 4 team colours** (blue, red, green, yellow). Extra $9.99: 150+ incl. units, horses, ships | The team-colour approach matches our North Star, but the look is a glossy board game, and it's built on hex tiles. **No for the realm, yes as a reference** for how a kit carries team colour (roofs and trims only) |
| Character Pack Adventurers | [itch](https://kaylousberg.itch.io/kaykit-adventurers) | Free: 5 characters (Knight, Barbarian, Rogue, Mage, Ranger), weapons on hand slots; Extra $7.95 adds 3 | **Our army knight already is this Knight** (`~/Downloads/Aldmere/armies/kaykit-adventurers/`, v1.0). Chibi proportions: fine in a dense block at RTS distance, far from the man-at-arms concept up close |
| Character Animations | [itch](https://kaylousberg.itch.io/kaykit-character-animations) | Free: 150+ humanoid clips (v1.1, Dec 2025) on Rig_Medium (100+) and Rig_Large; melee 1H/2H, block, dual-wield, ranged/bow, death, hit, emotes, tool work | **The best free pick in this survey.** Our knight's 41 bones are `root, hips, spine, chest, upperarm.l…handslot.r…` (TESTED), which are the Rig_Medium names, so the clips should bind straight onto the knight and through our VAT bake. That gives more march, attack and block variety (repetition is a bug). It also suits the man-at-arms if it's rigged to Rig_Medium. To test: bind 3 clips, bake, look |

## Other packs on Mac's list

| Pack | Link | Contents / licence (VENDOR) | Fit (ESTIMATE) |
|---|---|---|---|
| emace-art Free Fantasy Medieval Houses and Props | [itch](https://emaceart.itch.io/free-fantasy-medieval-houses-and-props-pack), [Godot store](https://store.godotengine.org/asset/emace-art/free-fantasy-medieval-houses-and-props-pack/) | 165+ assets, 3 LODs each, Godot 4 project, glTF; own licence: free incl. commercial, no resale (page also tags CC0) | Low-poly flat-textured landscape; reads like a survival game. Ready-made LODs are its plus. **No for the look** |
| Avramania Free Low-Poly Medieval Collection | [itch](https://avramania.itch.io/free-collection) | 203 models CC0 (nature 41, village 31, **castle & siege 14**, interiors 25, props 20, weapons 19, food 22, ruins 17, farm 14); glb, one 256 px palette, 1 m scale; pay what you want | Clean flat-shaded; same tier as Kenney. **No** as finished art; the siege engines are fine as stand-ins |
| Sketchfab "Low-Poly Medieval Buildings (RTS Style)" | not found under that title (Sketchfab API search, downloadable) | nearest: [cleorenshaw Stylised Medieval Buildings](https://sketchfab.com/3d-models/0437f6522192424292866976c24a27f7) series, CC-BY, 0.5-2k faces | Flat; no |
| Sketchfab "Low Poly Knights - Animated & Rigged" | not found under that title | nearest: [Knight Low Poly (dartuchiwa)](https://sketchfab.com/3d-models/c789ae2785584256873929f3fd2621a2), CC-BY, 2.3k faces, 10 clips | Chibi, flat; no |
| Sketchfab Stylized Modular Medieval Building Pack | [model](https://sketchfab.com/3d-models/be9fc8ce7b7143939e10324544c2e687) | JosephMontalvo, **CC-BY** (credit), 23k faces | Textured timber and plaster, decent; about level with our Village MegaKit, so it adds nothing |
| OpenGameArt WC3-ish collection | [collection](https://opengameart.org/content/wc3-ish-mod) | Mixed CC0 / CC-BY 3.0 / 4.0; the page itself warns most 3D needs hand-painted textures to get the style | Props and chests only; no units or buildings that reach the target |
| "Free Medieval Environment Props" (70 PBR) | not found under that title | nearest: [Chuck_CG Medieval-Fantasy Props](https://www.blendernation.com/2024/10/23/free-download-medieval-fantasy-props/) (50 PBR props, free) | PBR realistic. It's the wrong direction now that A is settled |
| dimonp/w3terrain-godot-extension | [GitHub](https://github.com/dimonp/w3terrain-godot-extension) | GDExtension that renders WC3 `.w3e` maps; Godot 4.7+, MIT, 5 stars, 52 commits, no releases | **No.** It needs textures and cliffs extracted from Warcraft III's MPQ archives (ripped Blizzard data), and it's early-stage. The idea worth keeping is WC3's cliff-tile terrain, which Terrain3D can approximate with painted cliff textures |

## Terrain: Terrain3D

`realm/scripts/land3d.gd` already builds the land with Terrain3D (TokisanGames, MIT; `realm/addons/terrain_3d`):
height-blended textures, detiling, clipmap rings, mud stamping for lanes. **It's already the upgrade.** The gap
to the target is the painting, not the engine: hand-painted ground textures (we have `ground/painted/`) and
WC3-style cliff faces.

## Verdict per category

| Category | Better than what we have? | Pick |
|---|---|---|
| Units | No free kit. KayKit Knight (ours) stays the stand-in | Tripo from our concepts (soldier-source.md); **add KayKit Character Animations** for clip variety |
| Buildings | No. Quaternius Village MegaKit (ours) is the best free one | Keep MegaKit; house colour on roofs and trims via the mask shader; MegaKit Pro if Mac ever allows paid |
| Castle | No. Every free castle (Quaternius RTS, Kenney, Avramania, KayKit) is a toy | Keep our own castle builder plus concepts; Codex/Tripo for hero pieces |
| Siege | No. Kenney, Avramania and KayKit siege are stand-ins only | Same as castle |
| Props | Quaternius Fantasy Props (ours) is the best free one; 92 unused | Use more of what we own |
| Animals | Quaternius animals (ours) are fine at RTS distance | Keep; KayKit Hexagon Extra horses are paid |
| Nature | Quaternius Stylized Nature (ours) | Keep |
| Terrain | Terrain3D (ours) | Keep; paint cliffs and ground |

No ripped Blizzard models or data anywhere in this list.
