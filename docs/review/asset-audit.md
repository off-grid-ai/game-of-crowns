# Asset audit: what we downloaded vs what the player sees

Snapshot: 10 Nov 2026, read-only. Method: every model, clip, sound and image was matched by name against `realm/scripts/*.gd`, `realm/tools/*.gd` and `realm/main.tscn`. Paths that the code builds at runtime (kit names, clip names, `%s` paths) were checked by hand. Loose Mixamo files were matched to the game's copies by file hash. Nothing was rendered or unzipped. `npc_mind.gd` was being edited during the audit, so clip counts can move by a few.

"Live" means a player can see or hear it today. "Waiting" means the code names it, but that code is switched off or never called. "Unused" means nothing names it.

## Summary

**Counted:** about 1,080 asset units in `realm/assets` (258 clips, 95 sounds, 517 models, about 207 images). On top of that sit roughly 140 packs or folders of source downloads across `downloads/`, `~/Downloads` and `~/Downloads/Aldmere`. Those hold about 900 extra Mixamo files, about 650 sound files, 70+ characters, about 60 Sketchfab and Poly Haven models, and about 60 texture sets.

**In `realm/assets`:**

| | Units | Live | Waiting | Unused | Of the unused: never use |
|---|---:|---:|---:|---:|---:|
| Animation clips | 258 | 165 | 22 | 48 | 23 (UAL guns, spells and swimming, plus 7 copies already covered by Mixamo) |
| Sounds | 95 | 70 | 0 | 25 | 0 |
| Models | 517 | 122 | 5 | 390 | 98 (Kenney and Quaternius toy-style kits, 5 duplicate hero bodies) |
| Images | ~207 | ~171 | 0 | ~36 | 10 (old ground maps) |
| **Total** | **~1,077** | **~528 (49%)** | **27** | **~499** | **~131** |

**Outside the game:** most of `downloads/` and `~/Downloads` is the source for files already copied into `realm/assets`. The parts that never reached the game are listed per location below.

**"admir":** no file or folder in `~/Downloads` has "admir" in its name, at any depth, and no game-asset zip lists such a file. It almost certainly means **`~/Downloads/Aldmere/`** (8.6 GB, 3,956 files), the asset staging folder. It is audited below.

### Top 10 unused assets by what the player would notice

| # | What | Where it lives | Where it should go | Builder |
|---|---|---|---|---|
| 1 | **25 sounds already in the game that never play**: footsteps on grass, wood and snow (15), hammer, chop, door open and close, draw blade, coins, gallop, march, charge, dead voices | `realm/assets/audio/sfx/` | `soundscape.footstep()` exists but nothing calls it. Hammer at the forge, chop by woodcutters, coins on a market sale, doors on entering a room, draw blade before a duel, gallop with cavalry, march with columns, charge at the charge, dead voices when the Dead come. | Builder 2 |
| 2 | **More sounds from Aldmere**: Kenney RPG and impact packs (about 300 one-shots: cloth, book pages, metal pots, creaks, punches, mining, wood, 5 surfaces of footsteps), 4 blacksmith hammer takes, rain and thunder loop, death bell, crowd cheering, autumn wind | `~/Downloads/Aldmere/audio/kenney/`, `audio/oga/` | Punches for tavern fist fights, mining for quarries, thunder for storms, page turns in the chronicle, cloth rustle for crowds. All CC0 or CC-BY. | Builder 2 |
| 3 | **Realistic trees we never planted**: beech, 5 birches, Norway spruce, Scots pine set; plus the unused variants inside packs we do use (10 oaks incl. saplings, 6 small or sapling pines, 9 bushes) | `downloads/realistic/{beech_tree,birch_trees_pack,norway_spruce,scots_pine_trees}`; `realm/assets/realistic/{oak_trees_pack,pines,bush_models_pack}` | Mixed woods instead of 7 oak and 8 pine shapes; birch on lowlands, spruce in the north, saplings at wood edges. Same author (LOLIPOP) as the trees in use, so the look matches. | Builder 2 |
| 4 | **Ruins of razed towns**: abbey ruins, abbey wall ruins, rubble pile, two tree stumps | `realm/assets/realistic/{abbey_ruins,abbey_wall_ruins,rubble_pile,ph/tree_stump_0*}` | Loaded only by `ruins.gd`, which nothing calls (`grep ruins` finds no caller). Call it where a town is razed or stormed. | Builder 2 |
| 5 | **Crowd bodies**: hooded peasant (hood, mantle, boots), poor woman in a headscarf, Eve, fuse warrior, and Mixamo's medieval-ready Maria and Kachujin | `~/Downloads/Aldmere/characters/civilians/{peasant_man_hooded,peasant_woman_poor_woman}` (preview: `front.png`, `CIVILIANS_CONTACT_SHEET.png`); `realm/assets/people/mixamo/eve` | More faces in every square. Eve is already imported, so she only needs a line in `people.gd` BODIES. The hooded man needs a Mixamo auto-rig. The woman's clothes need skinning. | Builder 2 |
| 6 | **The Dead's own moves**: Zombie Idle, Walk, Run, Attack, Scream, Stand Up, Death | `~/Downloads/Aldmere/mixamo/Zombie Moves/`, also loose in `downloads/realistic/` | The Dead army has a banner, music and a horde sound but moves like living men. Use these for its soldiers. | NPC builder |
| 7 | **Village-life clips nobody asks for**: Fishing Cast and Fishing Idle, the UAL Torch Idle, Formal Walk, Sitting Idle and Sitting Talking loops, Ride Relaxed, Injured Hurting, Box Walk | `realm/assets/anims/mixamo/`, `realm/assets/anims/AnimationLibrary_Godot_Standard.gltf` | Fishers on riverbanks, a night watchman with a torch, a court procession, elders talking on a bench, a calm rider on the road, the wounded after a battle. Another 22 clips (Hammer_Swing, Lute_Playing, Sleeping_Idle, Sitting_*) are already written into `npc_mind.gd`, but no town has it switched on (`LIMBO_TOWNS` is empty). | NPC builder |
| 8 | **Battle moves**: draw and sheath sword (3 takes), draw greatsword (2), equip and disarm axe and bow, taunt battlecry and chest thump, Axe_Combo_1 and 2, GS_Slash_2 and 4, Getting_Up_2, strafes and turns with a weapon raised | `~/Downloads/Aldmere/mixamo/{Lite Sword and Shield Pack,Sword And Shield Pack,Great Sword Pack,Pro Melee Axe Pack,Pro Longbow Pack}`; ~/Downloads `Standing Taunt *.fbx`; `realm/assets/anims/mixamo/` | Men draw steel before the clash, sheathe it after, taunt across the line. More different blows per fight. | NPC builder |
| 9 | **Arms variety**: kite shield, arming sword, 9 more bows plus crossbows, an arrow model, a longbow target | `~/Downloads/Aldmere/cavalry/kite_shield_iedalton`; `downloads/realistic/weapons/sword/arming_sword`; `realm/assets/props/weapons/bows` (only `Object_41` is shown); `realm/assets/props/weapons/arrow`; `downloads/realistic/weapons/longbow/plain_longbow_quiver_set` (preview: `weapons/longbow/review/*.png`) | Kite shields on knights, crossbowmen in garrisons, arrows in flight, archery butts in town squares. | Builder 2 |
| 10 | **The King's own body**: Armored King (crown, armour, cape) | `~/Downloads/Aldmere/characters/medieval_ready/armored_king/` | The player's king in the hall and the close-up. Its cape folds badly in a walk (NOBILITY_STATUS.md), so it needs skin-weight repair first. | Builder 2 |

Close runners-up: market-stall goods split out as carry items (sacks, melons, apples, handcart in `medieval_market_asset_pack`), Poly Haven castle door, iron gate and wildflowers (`~/Downloads/Aldmere/polyhaven/models`), a draft horse for carts, and roof and plaster texture sets for house variety.

**Never use:** the Kenney castle and town kits and the Quaternius `q/` kit (toy low-poly look), `modular_castle_wall_kit` (CC-BY-NC), Mixamo's modern characters and Egunoff's modern "LOD" people, the ActionVFX blood pack (licence not cleared), the Meshy AI legionnaire (Roman, licence unknown), the 15 `.crdownload` partial files.

---

## 1. `realm/assets/` (in the game folder)

### Animation clips

| Asset | What | Used where | Where it should go / never |
|---|---|---|---|
| `anims/mixamo/*.fbx` (172) | Mixamo moves, one clip per file, loaded into one library by `people.gd:92` | 140 named in code (e.g. `villagers.gd`, `combat.gd`, `scenes.gd`, `motion.gd:30`) | 20 more are named only in `npc_mind.gd`, which is off: Arm_Stretching, Clapping, Dig_And_Plant, Digging, Drunk_Idle, Hammer_Swing, Lute_Playing, Pointing_Arm_Bent, Pointing_Forward, Push_Heavy, Pushing, SS_Slash_2, Shove_Reaction, Sitting_Cross_Legged, Sitting_Drinking, Sitting_Ground, Sitting_Idle, Sleeping_Idle, Throw_Object, Wiping_Sweat. **12 unused:** Axe_Combo_1, Axe_Combo_2, GS_Slash_2, GS_Slash_4, Getting_Up_2, Groin_1, Side_Light (more variety in fights); Fishing_Cast, Fishing_Idle (riverbank); Ride_Relaxed (a rider at a walk); Injured_Hurting (after battle); Box_Walk (carrying a crate) |
| `hero/anims/*.fbx` (40) | Mixamo gestures for the close-up (the Gestures pack and others) | `hero_view.gd:370` fidgets, `people.gd:131` also loads them for crowds; 25 named | 2 named only in `npc_mind.gd` (Doubtful, Pleased). **13 unused:** Angry, Annoyed, Cocky, Crouch And Point, Disappointed, Dismiss, Firm Nod, Great Sword Idle, Kneeling Idle, Sarcastic Nod, Slow Nod, Telling A Secret, Victory Idle. They fit court reactions: a lord's mood toward the King (`ui.gd:2631` already computes Angry and Cold) and petition rulings. |
| `anims/AnimationLibrary_Godot_Standard.gltf` | Quaternius Universal Animation Library, 46 clips, CC0 (preview: `downloads/anims/Preview.png`) | Loaded at `people.gd:113`; **no clip is ever played by name** | Use: Idle_Torch_Loop (night watch), Walk_Formal_Loop (procession), Sitting_Idle_Loop and Sitting_Talking_Loop with Sitting_Enter and Sitting_Exit (benches, tavern), Crouch_Idle_Loop (scouts), Push_Loop (carts), Dance_Loop, Jog_Fwd_Loop. Never: the 16 Pistol, Spell, Swim, Roll and T-pose clips (code already skips them). 7 are hidden by Mixamo files of the same name. |
| `anims/UAL1_Standard.fbx` | FBX copy of the same library | Nowhere | Never: duplicate of the glTF. |

### Sounds

| Asset | What | Used where | Where it should go / never |
|---|---|---|---|
| `audio/music/` (19) | Kevin MacLeod, RandomMind and others, CC-BY or CC0 | All in `soundscape.gd:66` | — |
| `audio/ambience/` (19) | Freesound and OGA beds | All in `soundscape.gd:40` | — |
| `audio/ui/` (8) | Kenney UI clicks | All in `soundscape.gd:101` | — |
| `audio/sfx/` used (24) | Horns, clashes, hits, bells, drums, cheers | `soundscape.gd:59-98` | — |
| `audio/sfx/step_{grass,wood,snow}_0-4.wav` (15) | Kenney footsteps | `soundscape.gd:199` builds the names, but **nothing calls `footstep()`** | The lord you control, on the right surface, near the camera |
| `audio/sfx/{hammer,chop,coins,door_open,door_close,draw_blade}.wav` | Kenney RPG audio, CC0 | Nowhere | Smithy, woodcutter, market sale, entering a room (`interior.gd`), a duel starting |
| `audio/sfx/{gallop,march,charge,dead_voices}.ogg` | Freesound, CC0 | Nowhere (the names appear only in comments) | Cavalry moving, a column on the road, the charge in `scenes.gd`, the Dead arriving |

Note: `audio/CREDITS.md` opens with "Personal, non-commercial use", but every file it lists is CC0, CC-BY or CC-BY-SA. That header looks wrong; worth a look before release. `rain_roof.ogg` is CC-BY-SA.

### Models

| Asset | What | Used where | Where it should go / never |
|---|---|---|---|
| `realistic/` 21 Sketchfab kits (CC-BY 4.0) | Houses, castle, church, mill, barn, longhall, tavern, carts, hay, fence, woodpile, market, trees, bushes | Through `realistic.gd:9` KIT: `towns.gd:211-556`, `countryside.gd:208-254`, `town_life.gd:308-371`, `roads.gd:158`, `forest.gd:8-10`, `interior.gd:34` | `medieval_tools_set` is **unused** (tongs, hammers, chisels, keys): lay it on smithy benches, or hand a hammer to the smith. Inside packs we use: oaks use 7 of 17 variants (Big_oak_004, Large_oak_001-003, Small_oak_001-003 and Sapling_oak_001-003 are unused); pines use 8 of 15 (Pine_medium_3, Pine_small_1-3, Pine_sapling_1-3 unused); bushes use 6 of 15 (Bush_big_004/005, Bush_medium_002/004, Bush_small_001-005 unused). The market pack is placed whole; its Handcart, Sacks, Melons, Apples, Carrots, Pottery and Bottles could become carry items. |
| `realistic/ph/` 11 Poly Haven props (CC0) | Barrels, crates, bucket, basket, ladder, lantern, fire pit, stumps | Clutter at `towns.gd:521`, fire pit as the well at `towns.gd:515` and `town_life.gd:559`, lantern `towns.gd:542`, ladder `town_life.gd:371` | `tree_stump_01/02` are waiting: only `ruins.gd` names them. |
| `realistic/{abbey_ruins,abbey_wall_ruins,rubble_pile}` | Sketchfab ruins, CC-BY | Waiting: only `ruins.gd:10`, which nothing calls | Razed towns (see Top 10 #4) |
| `interiors/{chapel,cottage,great_hall,tavern}` | Sketchfab rooms, CC-BY | `interior.gd:220` | — |
| `crops/{wheat,hay,cabbage}` | Sketchfab crops, CC-BY | `countryside.gd:360` | — |
| `cavalry/horse/horse.glb` | Rigged horse with 5 gaits (CC0 and CC-BY) | `horse.gd:18` | — |
| `weapons/lance` | Tournament lance (Sketchfab Standard) | `horse.gd:20` | — |
| `props/weapons/` 9 | Sword, greatsword, axe, spear, dagger, bows, shield, quiver, arrow | `weapons.gd:20` KINDS | `arrow` is **unused**: arrows in quivers and in flight. `bows` shows 1 of 10 bows; the rest include crossbows. |
| `people/` outfits, base bodies, hair | Quaternius outfits (Peasant, Ranger), base bodies, 6 hairstyles, CC0 | `people.gd:22-25`, `people.gd:221` | `hair/Eyebrows_Female`, `Eyebrows_Regular` unused (the base mesh carries its own brows). Never needed. |
| `people/mixamo/` 17 bodies | Mixamo and Sketchfab characters | 16 in `people.gd:38-63` BODIES | `eve` is imported but **not in BODIES**: add her as townsfolk or noble. |
| `hero/{knight,fuse_civilian_1,fuse_civilian_2,fuse_woman_1,medieval_civilian_3}` | Raw Sketchfab copies | Nowhere (`hero_view.gd` builds people through `people.gd`) | Never: the fuse bodies are duplicates of `people/mixamo/fuse_*`. `knight` is a statue model (could stand in a castle yard). `medieval_civilian_3` never passed Mixamo rigging. |
| `village/` 176 | Quaternius Medieval Village MegaKit, CC0 (preview: `downloads/megakit-village/Preview.jpg`) | 25 pieces in `house_builder.gd:80-116` (walls, doors, windows, 5 roof sizes, chimney) and `Prop_Wagon` at `scenes.gd:28` | 151 unused: balconies, overhangs, stairs, dormers, wooden roofs, vines, fences, metal fences, doorframes, other door and window styles. Stylised look. Use only for the builder-made townhouses, and only if those are still seen next to the realistic kit. Otherwise leave them. |
| `nature/` 68 | Quaternius Stylized Nature MegaKit, CC0 (preview: `downloads/nature/Preview_1-4.jpg`) | 24 in `terrain.gd:583-588`, `countryside.gd:57-59,360,594`, `roads.gd:230` | 44 unused: TwistedTree_1-5, DeadTree_4-5, Bush_Common, Bush_Common_Flowers, Flower_3_Single, Flower_4_*, Mushrooms, Pebbles (11), RockPath (10), Petals (5), Plant_*_Big, Clover_2, Grass_Common_Tall. Small ground cover (mushrooms, flowers, pebbles) can pass at the oblique distance; the stylised trees clash with the realistic forest. |
| `props/` 94 | Quaternius Fantasy Props MegaKit, CC0 (preview: `downloads/props/Preview_1-3.jpg`) | 2: `Sword_Bronze`, `Shield_Wooden` at `scenes.gd:262` | 92 unused: anvil, workbench, cauldron, barrels, crates, farm crates of apples and carrots, stalls, beds, tables, chairs, books, candles, chandelier, torches, coins, pouch, scrolls, weapon stand, pickaxe, axe. Stylised trim-sheet look. Fine as small props and carry items seen from the oblique camera (pickaxe, axe, pouch, farm crates, scroll); check them next to Poly Haven before using big ones. |
| `castle/` 19 | Kenney Castle Kit, CC0 | 2: `siege-catapult`, `siege-trebuchet` at `scenes.gd:23` | Never for the other 17: toy low-poly look. |
| `town/` 17 | Kenney Fantasy Town Kit, CC0 | Nowhere | Never: toy look. |
| `q/` 59 | Quaternius low-poly town, people, animals and dragons, listed in `q/manifest.json` | Nowhere | Never: low-poly look. Note: the only livestock (sheep, cow, pig) and wildlife (deer, wolf) models we have are here. Realistic animals are a real gap. |

### Images

| Asset | What | Used where | Where it should go / never |
|---|---|---|---|
| `heraldry/` 72 banners and sigils | Generated house arms | `heraldry.gd:21,55`, `lore.gd:610` (by house name) | — |
| `intro/` 28 | Paintings, stills, splash, seal | `intro.gd:13`, `lore.gd:340`, `hero_view.gd:209`, `splash.gd:15`, `seal.gd:8` | — |
| `icons/` 28 svg | Phosphor icons | `ui.gd:267` | `fast-forward`, `hourglass-medium`, `play-pause` unused (time controls). |
| `ui/` 20 | Kenney RPG UI panels and buttons, gauntlet cursor, 7 logo options | `title-background.png`, `offgrid-mark.png` | Panels, buttons and cursor unused; UI.md's look doesn't call for them. The 7 logo drafts are unused alternatives. Never needed in play. |
| `ground/` 18 jpg and `ground/packed/` 16 png | Poly Haven ground sets | `terrain.gd:449`, `land3d.gd:36`, `towns.gd`, `countryside.gd` | `packed/mud-*` unused (mud loads the sand maps on purpose, `land3d.gd:35`). `packed/old/` 10 files: never, superseded. |
| `props/blood/` 5 | Blood decals (CC0, Quixel) | `blood.gd:8-13` | — |
| `emblem.png`, `sky/sky.hdr` | Emblem; HDR sky | emblem nowhere; sky only in `tools/house_preview.gd` | Not needed in play. |

---

## 2. `downloads/` (repo source folder)

Most folders here are the sources of what `realm/assets` holds. Only what never reached the game is described.

| Pack | What | Used where | Where it should go / never |
|---|---|---|---|
| `anims/`, `characters/`, `megakit-village/`, `nature/`, `outfits/`, `props/` | Quaternius sources (all CC0) | Copied 1:1 into `realm/assets` | `outfits/.../Modular Parts/` (20 parts: Ranger hoods, pauldrons, boots) are not in the game. Mixing a Ranger hood onto peasants gives cheap variety. |
| `ual-fbx/UAL1_Standard.fbx` | UAL as FBX | Duplicate | Never. |
| `rpg-ui/` + `rpg-ui.zip` | Kenney UI pack (preview: `rpg-ui/preview.png`) | Partly copied to `realm/assets/ui`, unused | Never needed. |
| `sky3d/`, `terrain3d/` + zips | Godot add-ons | In `realm/addons` | — |
| `azgaar/` | Fantasy Map Generator source code | A tool for the bridge (`bridge/tools/azgaar_rivers.py`), not a game asset | — |
| `realistic/` 21 kit folders, `sketchfab/`, `interiors/`, `weapons/`, `characters/fuse_*` | Sources of `realm/assets/realistic`, `interiors`, `props/weapons`, `people/mixamo` | Copied | — |
| `realistic/{beech_tree,birch_trees_pack,norway_spruce,scots_pine_trees}` | Realistic trees, CC-BY (LOLIPOP, evolveduk, Georgeous, Batyrev) | Not in game | Forest variety (Top 10 #3). |
| `realistic/pine_trees_pack` | Same as `realm/assets/realistic/pines` | Copied | — |
| `realistic/polyhaven/` 19 not copied | boulder_01, rock_07, rock_moss_set_01/02, dead_tree_trunk, fern_02, shrub_01-03, grass_medium_01/02, fir_tree_01, fir_sapling, pine_tree_01, pine_sapling_medium, tree_small_02, spinning_wheel_01, wooden_stool_01 (CC0) | Not in game | Rocks, mossy boulders, ferns and shrubs for roadsides and woods; spinning wheel and stool in cottage yards and the market. Never as is: fir_tree_01 (478 MB of mesh), pine_tree_01 (949 MB), pine_sapling_medium (264 MB) are far too heavy. |
| `realistic/polyhaven/textures/` 7 sets | leafy_grass, brown_mud_02, farm_soil, gravelly_sand, mossy_rock, forest_leaves_02, muddy_tracks | Became `realm/assets/ground` | muddy_tracks was tried and dropped (`land3d.gd:33`). |
| `realistic/modular_castle_wall_kit` | Castle wall kit | Not in game | **Never: CC-BY-NC.** |
| `realistic/{vikingmedieval_game_character,characters/vikingmedieval_game_character}` | Viking warrior, CC-BY, not rigged | Not in game | Raider or northern soldier after a Mixamo auto-rig. |
| `realistic/medieval_knight__sculpture__game_ready` | Knight statue, CC-BY | Copied to `hero/knight`, unused | A statue in a castle yard or a hall. |
| `realistic/medieval_civilian_3`, `characters/medieval_civilian_3` | Civilian, Sketchfab Standard | Copied, unused (Mixamo rejected the rig) | Crowd body if the rig is fixed. |
| `realistic/weapons/sword/arming_sword` | Second sword, CC-BY (preview: `source_preview.png`) | Not in game | Variety in soldiers' hands. |
| `realistic/weapons/longbow/plain_longbow_quiver_set` | Longbow, quiver and **target**, CC-BY (preview: `weapons/longbow/review/plain_longbow_quiver_preview.png`) | The quiver is used | Archery target for a town's practice butts. |
| `realistic/weapons/_review/axe_taylor_over_budget` | Second axe, CC-BY | Rejected for size | Never unless decimated. |
| `realistic/interiors/_review/*` | Older cottage and tavern copies | Duplicates | Never. |
| `realistic/Gestures Pack Basic/`, `Lite Sword and Shield Pack/` | Mixamo packs | 14 of 15 gestures in `hero/anims`; 6 of 17 sword and shield clips copied | Unused: draw sword 1, sheath sword 1, run (2), strafe and strafe (2), turn and turn (2), block, block (2), attack (3), attack (4). |
| `realistic/*.fbx` loose (287) | Mixamo clips and characters | 111 are byte-identical to game files | Unused groups: **Hit reactions and deaths** (about 95: Head Hit 1-8, Hit Reaction 1-8, Standing React Large and Small from each side, Dying 1-10, Standing Death Left, Right and Backward, Walking To Dying, Fall Flat, Fall Over, Shoved Reaction With Spin, Livershot Knockdown, Turn To Knocked Unconscious, Swing Into Wall); **Zombie** (10); **Sitting** (Sitting, Sitting Idle, Sitting Talking, Sitting Clap, Cheering While Sitting, Stand To Sit, Sit To Stand, Male Sitting Pose); **Evasion** (Walking Backwards, Running Backward, Stumble Backwards, Stand To Roll); others (Climbing, Jumping Down, Slipping, Left Turn, Right Turn, Taunt). Never: Rifle Death, Rifle Hit To Back, Rifle Kneel Hit To Back, Rifle Prone Hit Reaction, Bayonet Stab, Standing Aim Idle 01 (guns). |
| `realistic/Ch01..Ch49_nonPBR.fbx` (31), `Remy`, `Lola`, `Medea`, `Whiteclown`, `passive_marker_man`, `Swat` | Mixamo stock characters | Not in game | Never: Aldmere's own review filed them under "other" as modern dress, clowns, mocap suits or sci-fi. Ch24 and Ch40 were judged medieval-ready (see section 3). |
| `realistic/{Kachujin,Maria J J Ong,Maria WProp}.fbx` | Mixamo fighters, medieval-ready | Not in game | Maria (sword and shield woman) as a shieldmaiden or noble guard. Kachujin is samurai-styled: never. |
| `realistic/*.zip` (71) | Mostly archives of folders above | Sources | Unique and unused: **Mixamo packs** (Farming, Great Sword, Male Injured, Pro Longbow, Pro Melee Axe, Sword and Shield; see section 3 for unused clips); `medieval_kite_shield.zip`; `medieval_lance.zip`; `knight_riding_a_horse.zip`; 5 horse zips (`horse`, `the_horse`, `horse_riggedgame_ready`, `animated_rigged_horse_with_saddle`, `draft_horse_walk`); `realistic_wheat.zip`, `yard_wheat_clump.zip`; `fuse_warrior.zip`, `free_game_character_-_ancient.zip`; 4 blood zips; 14 Egunoff "LOD man/lady" characters and `fuse-black-girl`, `fuse-call-girl` (modern dress: never). `getoffgridai.co-Performance...zip` is not a game asset (skipped). |
| `realistic/*.crdownload` (15) | Partial downloads | — | Never: broken. |
| `realistic/Horse Rigged All Gaits.blend` | Source of the game horse | Used via `cavalry/horse` | — |

---

## 3. `~/Downloads` and `~/Downloads/Aldmere`

### Loose files in `~/Downloads`

| Asset | What | Used where | Where it should go / never |
|---|---|---|---|
| 23 Mixamo `.fbx` (Hammer_Swing, Lute_Playing, Sitting_*, Sleeping_Idle, Fishing_*, Drunk_Idle, Throw_Object, Wiping_Sweat, ...) | Sources | Byte-identical to `realm/assets/anims/mixamo` | Duplicates. |
| `Cross Punch`, `Jab Cross`, `Right Hook`, `Punch Combo` | Mixamo boxing | Not in game | Tavern brawls (`town_life.gd:465` already stages fist fights with two clips). |
| `Standing Taunt Battlecry`, `Standing Taunt Chest Thump` | Mixamo taunts | Not in game | The battle line before the clash (Top 10 #8). |
| `Mma Kick`, `Punching Bag`, `Unarmed Walk Forward`, `Walking`, `Walking (1)`, `Boxing` (another take) | Mixamo | Not in game | Never: modern sport moves, or duplicates. |
| `armored_king_apose_upload.fbx`, `armored_king.zip`, `armored-king.zip` | Armored King, CC-BY | Not in game | Top 10 #10. |
| `noble_lady_upload.fbx`, `princess_nun_royal_queen.zip` | Source of `noble_lady` | Used (`people.gd:63`) | — |
| `*_4k.blend.zip` Poly Haven (22) | Blender 4K versions of Poly Haven props | 11 duplicate game props at higher resolution | New items, CC0: `wooden_axe`, `wooden_axe_02`, `wooden_axe_03` (woodcutters' carry tool), `wooden_broom` (sweeping chores), `wooden_bowl_01` (feasts, market), `folding_wooden_stool`, `wooden_stool_01/02`, `wooden_bucket_02`, `wicker_basket_02`, `wooden_ladder_02`. They need export from `.blend` to glTF at 1K. |
| Sketchfab zips (~20: barn, mill, castle, tavern, viking house, market, wagon, cart, ruins, fence, woodpile, tools set, ...) | Sources | Copied into `realm/assets/realistic` | Duplicates. `modular_castle_wall_kit_-_free_game_asset.zip`: never (NC). |
| `vikingmedieval_game_character.zip`, `medieval_civilian_3.zip`, `medieval_knight__sculpture__game_ready.zip` | Sources | See section 2 | — |
| Quaternius zips (Universal Base Characters, Stylized Nature, Fantasy Props, Modular Outfits) | Sources | Copied | Duplicates. |
| `Pro Sword and Shield Pack.zip` | Mixamo pack (+ X Bot) | Partly copied as `SS_*` | Adds `draw sword 2` and `sheath sword 2` over the Aldmere copy. |
| `Meshy_AI_Crimson_Legionnaire_biped.zip` + folder | AI-made Roman legionnaire, walk and run | Not in game | Never: Roman, AI mesh, licence unknown. |
| `ares-299k-body-rigged.glb`, `Ares/ares.png` | 299k-triangle rigged figure | Not in game | Never: 10x the crowd budget, wrong look. |

### `~/Downloads/Aldmere/` (the "admir" folder)

| Folder | What | Used where | Where it should go / never |
|---|---|---|---|
| `audio/src/` (64) | Original downloads of the game's music and ambience | Trimmed copies are in `realm/assets/audio` | Duplicates. |
| `audio/kenney/` (351; rpg-audio, impact-sounds, interface-sounds, ui-audio; CC0) | One-shots | `chop`, `coins`, `door*`, `draw_blade`, `hammer`, footsteps and UI clicks were copied (most of those copies are unused in `realm`) | Top 10 #2: `impactPunch_*` for fist fights, `impactMining_*` for quarries, `impactWood_*` for chopping, `bookFlip*` and `bookOpen` for the chronicle, `cloth*` for crowds, `metalPot*` for cooking, `creak*` for doors and carts, 5 footstep surfaces. |
| `audio/oga/` (16 packs) | Rain loop, rain and thunder loop, birds, river and waterfall (7z), blacksmith (4 takes), blacksmith hammer, breeze, church bell, crickets, dark ambiences (zip), death bell, crowd cheering, autumn wind, battle SFX (zip), 30 CC0 loops (zip) | Some fed `realm/assets/audio` (river, rain roof) | Thunder for storms, blacksmith takes for the forge (varied, not one loop), death bell for a lord's death, dark ambiences for the Dead's lands. Each folder holds web-page junk (`.css`, `.js`): ignore those. |
| `characters/medieval_ready/` (22) | Medieval-ready bodies (preview: `characters/identity_review/CHARACTER_IDENTITY_CONTACT_SHEET.png`, `characters/sketchfab_review/*.png`) | 13 are in `people/mixamo` (akai, Arissa, Brute, Dreyar, Erika x2, Eve, Ganfaul, Heraklios, Knight, Paladin x2, Uriel, noble_lady) | Unused: `armored_king` (Top 10 #10), `Ch24_nonPBR`, `Ch40_nonPBR` (Mixamo medieval-ready, look unverified), `Maria J J Ong` and `Maria WProp` (shieldmaiden), `sketchfab_fuse_warrior` (soldier), `sketchfab_ancient` (ancient warrior; check the look). Never: `Kachujin` (samurai). |
| `characters/civilians/` (6) | Peasant bodies (preview: `CIVILIANS_CONTACT_SHEET.png`, each `front.png`) | `medieval_man`, `monk`, `svend` are in the game | Unused: `peasant_man_hooded` (best new look; needs merge, rescale and auto-rig), `peasant_woman_poor_woman` (clothes need skinning). Never: `peasant_man_keash` (rigid segments, low quality). |
| `characters/other/` (51) | Modern-dress spare bodies | Not in game | Never for the look: modern clothes. |
| `characters-unverified/` | Unchecked bodies | Not in game | Never until checked. |
| `mixamo/` (380 fbx in 12 packs) | All combat and village packs | 149 are byte-identical to game files | Unused by pack: **Zombie Moves 7/7** (Attack, Stand Up, Walk, Death, Idle, Run, Scream). **Great Sword 35/51**: draw a great sword 1-2, idles 2-5, walk (2), run, run (2), strafes 1-4, turns, 180 turns, jumps, crouching 1-6, slash (5), kick (2), blocking (3), impact 4-5, slide attack, jump attack; never: casting, power up, spell cast. **Sword and Shield 31/49**: sheath sword 1-2, idle 1-4, walk (2), run 1-2, strafes 1-4, turns, 180 turns, crouch set, attack 1-2; never: casting 1-2, power up. **Lite Sword and Shield 11/17** (as in section 2). **Pro Melee Axe 32/47**: equip and disarm (underarm, over shoulder), taunt chest thump, combo attack 3, 360 low, run jump attack, kick 2, walks and runs in each direction, turns, idle looking 1-2, crouch idle. **Pro Longbow 8/16**: equip bow, disarm bow, idle 02 looking, idle 03 examine, block, death forward 01, death backward 01, unarmed idle. **Farming 6/15**: pick fruit (2), pick fruit (3), pull plant (2), holding idle, wheelbarrow dump, kneeling idle. **Male Injured 8/10**: injured walk turns, walk backwards, backwards turns, stumble idle, wave idle. **Evasion 4/7**: Stand To Roll, Walking Backwards, Running Backward, Stumble Backwards. **Unarmed 3/15**: Getting Up (2), Getting Up (3), Taunt. **Hit Reactions 109/131** (see section 2's loose list). **Root 18/57**: Sitting Idle, Sitting Talking, Sitting Clap, Cheering While Sitting, Stand To Sit, Sit To Stand, Standing Arguing 1-2, Idle (1), Standing Idle (2), Left Turn, Right Turn, Walking (1), Standing Melee Attack Downward, Sword And Shield Slash. Never: Bayonet Stab, Standing Aim Idle 01. |
| `mixamo-retries/` | One retried clip | Duplicate | — |
| `cavalry/gaits/`, `cavalry/horse_game/` | Source of the game horse | Used | — |
| `cavalry/{horse_abhayexe,aaadragon_the_horse,horse_saddle_ayan,bazsi_draft_horse_walk}` | Alternative horses, CC-BY (preview in `CAVALRY_STATUS.md`) | Not in game | `bazsi_draft_horse_walk`: a heavy draft horse pulling carts and ploughs (walk only). The others: never, because the game horse is better (no separate gaits). |
| `cavalry/rider/` | Knight on a horse, `Horse knight.fbx` (preview: `knight_riding_preview.jpeg`) | Not in game | Never as is: the rider and horse are one mesh; our cavalry already mounts riders. |
| `cavalry/rider_moves/` | Sitting, Male Sitting Pose, Climbing, Jumping Down | Not in game | Mounting and dismounting stand-ins; sitting on carts. |
| `cavalry/kite_shield_iedalton/` | Kite shield, CC-BY | Not in game | Knights' and riders' shields (Top 10 #9). |
| `cavalry/lance/` | Lances incl. the game's tournament lance | Game lance used | Others: duplicates. |
| `crops/` (5) | Wheat x3, haystack, cabbage (preview: each `SOURCE_PREVIEW.png`, `graphetta_preview.png`, `yard_wheat_preview.png`) | `ljungman_wheat`, `ljungman_haystack`, `meerschaum_cabbage` are in the game | `graphetta_realistic_wheat`: a second ripe wheat for field variety. `ebmclachlan_yard_wheat`: green, unripe wheat for spring fields. |
| `polyhaven/models/` (25, CC0) | Castle door, large iron gate, modular fort, barrel_03, wildflowers (celandine, dandelion, nettle, periwinkle), moss, roots (4), dry branches, dead trunk 02, rocks (rock_09, stone_01, two rock faces, mountainside), shrub_04, saplings, cannon_01 | Only `tree_stump_02` is in the game (as a waiting ruin stump) | Gate and door on castle and town gates; modular fort for town walls; wildflowers, roots, moss and branches as forest-floor and roadside cover; rock faces on cliffs. Never: `cannon_01` (gunpowder). |
| `polyhaven/textures/` (~55 sets, CC0) | Thatch and reed roofs, roof slates and planks, plasters, castle brick, medieval walls and blocks, cobblestones, gravel road, grass paths, farm furrows, forest grounds, weathered planks | A handful became `realm/assets/ground` | `farm_furrows` for ploughed fields, `gravel_road` and `grass_path_*` for road variety, `cobblestone_floor_*` for seat towns' squares, thatch and plaster sets to re-dress house variants. |
| `vfx/blood/` (7 packs) | Quixel stains and spatter, OGA splatter, Sova 2D splashes, ActionVFX pools and prints | 5 images in `realm/assets/props/blood` | `quixel_hand_smear` unused (walls after a sack). Sova splash sprite frames: hit spurts in battle. **ActionVFX: never** until the licence is cleared (`ACTIONVFX_LICENCE_REVIEW.md` says not usable). |
| `ui/title-background-alt.png` | Alternative title art | Not in game | Spare. |
| `intro/`, `heraldry-source/` | Full-size sources of game paintings and arms (previews: `INTRO_CONTACT_SHEET.png`, `HERALDRY_CONTACT_SHEET.png`) | Copied | Sources. |
| `launch/` | Marketing paintings | Not game assets | Out of scope. |
| `tools/` | Download and audit scripts | — | Out of scope. |

## Licence flags

- **Never ship:** `modular_castle_wall_kit` (CC-BY-NC); ActionVFX blood (licence not cleared); Meshy legionnaire (licence unknown).
- **Fine with credit:** all Sketchfab CC-BY 4.0 kits, characters, trees, weapons; Kevin MacLeod music (CC-BY); `rain_roof.ogg` (CC-BY-SA: the edited file stays CC-BY-SA).
- **Sketchfab Standard** (fine inside a game, no raw redistribution): the lance in use, `medieval_civilian_3`.
- **CC0:** Quaternius, Kenney, Poly Haven, most Freesound and OGA sounds.
- Mixamo clips and characters are free for games under Adobe's terms but can't be redistributed as raw files.
