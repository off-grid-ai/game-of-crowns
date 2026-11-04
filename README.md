# Game of Crowns

A living medieval world that runs on its own, set in the fictional realm of **Aldmere**. You are its King. Great houses rule their lands, grow their towns, marry, scheme and go to war whether you watch or not; you keep the peace while the realm prospers, with grain, gold, decrees, judgement at court and, when you must, the royal host. Zoom from the whole continent down into a town square, see the people at work and at prayer, step into a lord and walk their streets.

Personal project, macOS on Apple Silicon. Decisions live in [VISION.md](VISION.md) and [DESIGN.md](DESIGN.md).

---

## How it fits together

```
 Freeciv server ──► bridge (Node) ──► realm (Godot 4.7)
  the simulation     turns, story,      what you see:
  (rules, AI,        characters,        land, towns, people,
   economy, war)     the court, LLM     battles, the HUD
```

- **Freeciv 3.2** runs the world: a custom medieval ruleset (`bridge/data/realmrules`), seven AI great houses plus the Crown, a hand-shaped continent. One turn is one season.
- **The bridge** (`bridge/server.js`, port 8787) starts Freeciv, reads every save and turn, and adds what Freeciv doesn't have: named characters with traits, goals and memories (`characters.js`), the court and its petitions, the stakes of the reign (usurpers, the dead beyond the wall: `stakes.js`), the King's decrees (`crown.js`, `god.js`), chronicles you can start, switch and end (`chronicles.js`), and the narrator. It serves the realm as JSON to the view.
- **The realm** (`realm/`, Godot 4.7, Forward+) draws it: Terrain3D land and Sky3D light, towns laid out from realistic Sketchfab kits, townsfolk living a daily routine, armies on the roads, battles, sieges, feasts and handovers as scenes, and the interface.
- **Words** (a lord's pivotal choice in their own voice, a townsperson's story, turning "make the North restless" into numbers) come from a local language model through the [Off Grid AI](https://github.com/off-grid-ai) desktop gateway. If it isn't running, everything falls back to rules.

## Setup

1. Tools (Homebrew):
   ```bash
   brew install freeciv node
   brew install --cask godot
   ```
   Godot **4.7**, Freeciv **3.2**, Node **22+**.
2. Art. Our own art (heraldry, logo, icons, sky, fonts) is in the repo. Third-party art is not, by licence and by size (~2 GB); only its import settings are tracked. Put it back in these folders before opening the game:

   | Folder in `realm/assets/` | What | Source |
   | --- | --- | --- |
   | `realistic/` | buildings, trees, props | Sketchfab (CC BY, credits in each folder's `license.txt`), Poly Haven (CC0) |
   | `people/` | townsfolk bodies, outfits, hair | Quaternius *Universal Base Characters* + *Fantasy Outfits* (CC0) |
   | `anims/mixamo/` | every townsperson's move | Mixamo (Adobe account); list in [MIXAMO_DOWNLOADS.md](MIXAMO_DOWNLOADS.md) |
   | `hero/` | close-up characters and their moves | Sketchfab Mixamo-rigged characters + Mixamo |
   | `village/`, `props/`, `nature/`, `q/` | stylised kit pieces still in use | Quaternius MegaKits (CC0) |
   | `ground/` | ground and road textures | Poly Haven / ambientCG (CC0) |

   The file names each folder expects are the ones in its `.import` files. Asset hunting is briefed in `ASSET_SHORTLIST.md` and the `CODEX_*` briefs.
3. Open the project once so Godot imports everything (Apple Silicon: always native):
   ```bash
   arch -arm64 godot --headless --path realm --import
   ```
4. Optional: keep the realm alive whenever you're logged in.
   ```bash
   bridge/tools/install-launchagent.sh
   ```
5. Optional: the Off Grid AI desktop app, for characters' own words.

## Running

```bash
./realm.sh
```

Wakes the bridge (which starts Freeciv) and opens the view. `./realm.sh status` prints the turn and towns, `./realm.sh stop` saves and stops, `./realm.sh start` wakes it without the window. The world keeps running after you close the window, and catches up when you return.

A new realm starts from the title screen: **Begin a New Chronicle** lets you choose the world (Aldmere nine years in, Aldmere from year one, or a random realm), the season length, the reign's length, the great houses' temper, wealth and faith in the crown, how cruel fate is, when the dead stir, the royal host and treasury, and the opening mood in your own words. Choices can be saved as scenarios.

## Playing

- **Camera:** drag to pan, wheel to zoom, the pad bottom-right to turn and tilt, **Z** back to Kingsmere, **M** hides the minimap.
- **Panels:** **K** the court (petitions to answer), **H** the great houses and your word, **C** the chronicle, **L** the ledger.
- **A town:** click it for its people, stores and buildings, and the royal decrees (send grain, gift crowns, a feast, a levy, grant the castle, fund a building).
- **A person:** "See" on a house or a petition opens them up close: nature, goals, memories, moves. **Change who they are** rewrites their traits, aim and loyalty. **Take control** puts you in their boots in their own town: WASD walk, Shift run, right-drag turn, wheel closer, **E** talk to someone or step through a door (great hall, tavern, chapel, cottage), **Esc** back to the realm.

## Repository

```
bridge/             the simulation bridge (Node, no dependencies)
  server.js         HTTP API, Freeciv process, turns, scenes
  characters.js     the court: people, goals, memories, petitions
  stakes.js         usurpers, the dead, the end of a reign
  chronicles.js     start / switch / end realms; new-realm options
  data/realmrules   the medieval Freeciv ruleset
  data/nation       the great houses' nations and AI temperaments
  lua/              Freeciv-side scripts (world setup, events, snapshots)
  baseline/aldmere  a realm a few years in, where new Aldmere chronicles begin
  tools/            map generation (Azgaar), baseline capture, launch agent
realm/              the Godot project
  scripts/          everything you see (main.gd is the entry point)
  assets/retarget/  bone maps: Quaternius and Mixamo rigs -> Godot's humanoid
  tools/            preview and asset helper scripts
  addons/           Terrain3D, Sky3D
realm.sh            open / start / stop / status
*.md                vision, design, world bible, UI, asset briefs
```

## Licence

Our code, docs and own art are [MIT](LICENSE). Freeciv is GPL 2.0 and runs as its own program. Third-party art keeps its own licence: each folder's `license.txt`, [audio credits](realm/assets/audio/CREDITS.md), the fonts' OFL files in `realm/assets/fonts/`, and the in-game Credits page, which lists everyone.

## Development notes

- **Run Godot natively.** A shell under Rosetta starts the universal Godot binary as Intel, several times slower. Use `arch -arm64 godot …` (`realm.sh` does).
- **Screenshots without playing:** `arch -arm64 godot --path realm -- --shot=out.png --wait=60` plus a scene: `--city=Stonefell --dist=5`, `--new` (new chronicle screen), `--hero=<house id>` (a lord up close), `--move=<move>`, `--control=<house id>` (take control), `--interior=<great_hall|tavern|chapel|cottage>`, `--feast`, `--handover`, `--battle`, `--siege`. `--wait` must outlast the world's first build.
- **New Mixamo moves:** drop the FBX (Without Skin, 30 fps, In Place) into `realm/assets/anims/mixamo/` named for the move, import, and set its import to retarget with `res://assets/retarget/mixamo_map.tres` (copy the `_subresources` block from any neighbour's `.import`). It then plays on every townsperson.
- **Bone maps** are generated by `realm/tools/make_bone_maps.gd`.
- **The bridge** reloads on `launchctl kickstart -k gui/$(id -u)/com.realm.bridge` when installed as a launch agent.
