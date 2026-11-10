# Consolidation plan: SSOT, SRP, DRY, SOLID

Supervisor's ruling, 2026-11-10. Built from `state-architecture.md` (where state lives) and
`principles-audit.md` (code structure). The rules are in goc-engineering's "Architecture" section.

**The target:**
- Freeciv owns the simulation, and the bridge reads it one way.
- The bridge owns the realm state, one definition per fact, and `/world` is a pure projection of it.
- The view keeps one mirror (`awareness.gd`). Every view script reads it.
- Every agent decision runs on LimboAI.
- Kinds (decrees, scenes, petitions) are data rows plus handlers, not growing `match` blocks.

**How we get there:**
- One module per commit, behind a switch or additive first.
- Nothing is lost.
- Each step is proven: private bridge, check-only, and the behaviour probe for NPCs.
- Films go to the batch.

**Owners:** **N** = NPC builder. **B2** = Builder 2.
- Shared files (`server.js`, `main.gd`) are staged by hunk.
- While `server.js` is being split (C3), only its splitter edits it.

**Parallel helpers** (Mac approved): a builder may give the steps marked ⧉ to code-writing helpers on
files that don't overlap. The builder reviews every diff, runs check-only, and commits it itself.

## Phase A: duplications a player can see (now)

| # | What | Fix | Owner |
|---|---|---|---|
| A1 | Truces live in three places. A truce from a court ruling or a story never reaches Freeciv, and the goal line still counts the war | Every truce, from a decree, a ruling or a story, goes through the one ceasefire writer (9dcc7bc's save edit). The goal line, the houses panel and the terrain read the same truce list | N |
| A2 | Hunger, at war, besieged, feasting and town mood are each defined 2–5 times. minds.js plans ignore riots and feasts | One bridge function owns them (already in progress). `/world` sends `city.mood`, `city.hunger`, `city.besieged`, `p.band`. minds.js plans read `city.mood`. Every other copy is deleted | N |
| A3 | Scenes and favour messages live only in bridge memory, and leak across chronicles | Opening another chronicle clears them. Favour changes are kept per chronicle, so the message survives a restart | B2 |
| A4 | Freeciv is read two ways (live and autosave), up to a turn apart | One read path: live for cities, owners and wars; the save only for what live can't give (the diplomatic table), applied at once after a reload | N |
| A5 | Three loops decide rebellion. The usurper path skips the ultimatum gate | One rebellion decider in stakes.js, and every path passes the ultimatum gate (a pretender always sends a warning card first) | B2 |

**Ruling on "great house"** (the audit asked for one): great means not wild, not the crown, and holds
at least one town. A `{includeFallen}` option exists only for lore and the chronicle.

## Phase B: foundations (additive)

| # | What | Owner |
|---|---|---|
| B1 | **The mirror, for real.** `awareness.gd` is built but not created or wired in HEAD. Put it in the tree, filled from `world_updated`. Then move every reader over, one per commit: scenes, director and minimap (N); terrain, ruins, the heading and ui (B2). `MoodIs` reads the blackboard | N, then B2 |
| B2 | ⧉ `bridge/realm.js` (`greatHouses`, `crownOf`, `seatOf`), `bridge/favour.js` (`BANDS`, `band`), `bridge/lua.js`. Replace the call sites file by file. The view never compares raw favour numbers again | B2 (helpers per file) |
| B3 | Richer `/world`: `crownId`, `seatId`, `p.band`, `scene.id`, `scene.tone`, `scene.royal`. `counsel()` moves out of `GET /world` into the season tick | N |
| B4 | One scene table: `scene_kinds.gd` (reach, sound, ping colour, caption, weight, hostile). Scenes, director, minimap, news, soundscape and awareness read it, and the seen-set is keyed by `scene.id` | N owns the file; ⧉ B2 swaps its readers |
| B5 | Decrees as data: `bridge/data/decrees.json` plus a handler map in crown.js, with the old switch as a fallback until every action has a handler. `/world.crown.decrees` carries label, effect and wait. ui.gd stops hard-coding "+15" | B2 |
| B6 | ⧉ Petition answers as handlers: one kind per commit, out of `characters.answer` | N (helpers per kind) |

## Phase C: retire and split

| # | What | Owner |
|---|---|---|
| C1 | LimboAI for every town: flip `LIMBO_TOWNS` to all towns, once the behaviour probe passes on all towns and the frame cost is measured. Then delete `_choose_next`'s brain, `_drill_routine`, the siege sweep, the scenes.gd tween fallback and town_life's old HSM, one per commit | N |
| C2 | ⧉ Public surfaces in place of the 61 private reach-ins (`rig.goal()`, a crowd API on villagers, `scene_stage.gd`, towns accessors). Each file's owner fixes the calls it makes | N and B2 |
| C3 | Split server.js: the routes table first (a pure move), then `freeciv.js`, `counsel.js`, `campaigns.js`, `treasury.js`, `reign.js`, `view.js`. One module per commit, with a smoke test (`/world`, `/court`, `/decree`) after each. N freezes server.js edits while this runs | B2 |
| C4 | ⧉ Split ui.gd into panels (court first) and main.gd (`shot_harness.gd`, `news.gd`), with frames before and after in the batch | B2 |
| C5 | One house colour (`heraldry.colour()`) and one set of LOD constants | B2 + N |

## Order

- **N:** A2 (in progress) → B1 (the mirror in the tree) → A1 → A4 → B3 → B4 → the awareness work it
  was already doing → B6 → C1.
- **B2:** its current world-object jobs (b, d, c) → A3 → A5 → B2 → B5 → B1 readers → C3 → C4.
- **Together:** C2 and C5, each on its own files.

## Done

- A grep finds one definition of each realm fact.
- Nothing in the view parses `/world` except awareness.gd.
- No view script calls another's `_private` member.
- Every town's people run on LimboAI.
- No file is over about 1,000 lines, except data.
