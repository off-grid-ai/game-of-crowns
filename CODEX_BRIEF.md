# Brief for Codex: assets for Aldmere

You are fetching free assets for Aldmere, a Godot 4 medieval kingdom game in `/Users/user/wednesday/civilization`. Claude Code wires them into the game. Your job is only to download, unpack and list them. **Do not edit anything under `realm/`, `bridge/` or any `.md` file except your own report.**

## Where things go
- Put everything under **`/Users/user/wednesday/civilization/downloads/realistic/`**, one folder per asset, unzipped.
  - Poly Haven: `downloads/realistic/polyhaven/<asset_id>/`
  - Characters: `downloads/realistic/characters/<name>/`
- When done, write `downloads/realistic/CODEX_REPORT.md`: one line per asset with its folder, format and anything odd (missing textures, wrong format).

## 1. Poly Haven (no login, CC0)
Format **glTF at 1k** only. Not `.blend`, not 4k: the game can't use `.blend` files, and 4k is far too heavy. The API gives direct file URLs: `https://api.polyhaven.com/files/<id>` → `["gltf"]["1k"]["gltf"]` (the `.gltf` plus its `include` textures). Send a User-Agent header or you'll get 403.

IDs:
- Props: `wooden_barrels_01 wine_barrel_01 wooden_crate_01 wooden_crate_02 wooden_bucket_01 wicker_basket_01 wooden_ladder spinning_wheel_01 wooden_stool_01 stone_fire_pit wooden_lantern_01`
- Trees: `fir_tree_01 pine_tree_01 fir_sapling pine_sapling_medium tree_small_02 dead_tree_trunk tree_stump_01`
- Undergrowth: `shrub_01 shrub_02 shrub_03 fern_02 grass_medium_01 grass_medium_02`
- Rocks: `boulder_01 rock_07 rock_moss_set_01 rock_moss_set_02`

If you already downloaded these as 4k `.blend` into `~/Downloads/Aldmere/polyhaven`, re-fetch them as 1k glTF instead; those can be deleted.

## 2. Characters (people)
- The Fuse characters already downloaded (`fuse_woman_1.zip`, `fuse_civilian_1.zip`, `fuse_civilian_2.zip`, `medieval_civilian_3.zip`, `vikingmedieval_game_character.zip`): unzip each into `downloads/realistic/characters/<name>/`. Note in the report whether each is **rigged** (has a skeleton) and its format (glTF/FBX).
- If more are needed: medieval-looking, rigged, realistic (not stylised or low-poly) peasants, soldiers and nobles, ideally Mixamo-compatible. List any candidates in the report with links; don't buy anything.

## 3. Animations for those characters (needs the user's Adobe login)
From Mixamo, for **one** of the rigged characters, download as FBX "With Skin" once, then each of these **"Without Skin"**, 30 fps: Walking, Running, Idle, Sword And Shield Idle, Sword And Shield Slash, Sword And Shield Block, Death, Talking, Praying, Digging, Hammering. Put them in `downloads/realistic/animations/`.

## Done looks like
Every asset unzipped in its own folder under `downloads/realistic/`, all glTF or FBX, nothing over 1k textures from Poly Haven, and `CODEX_REPORT.md` listing it all.
