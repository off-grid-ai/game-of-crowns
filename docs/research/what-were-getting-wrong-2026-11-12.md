# What we're getting wrong — 12 November 2026

Research and discovery only. Merges [sim-society-economy](sim-society-economy-2026-11-12.md),
[sim-physical-world](sim-physical-world-2026-11-12.md) and the
[foundation audit](independent-foundation-audit-2026-11-12.md). Frame rate set aside on purpose.

## The answer

- **The engine is not the mistake.** No engine or kit ships a medieval society, or walls that breach
  with armies pathing through the gap. CK3, Dwarf Fortress, Banished, Songs of Syx, Manor Lords, Total War
  and AoE IV all wrote that layer themselves. What they reused was the renderer.
- **The mistake: nobody owns the world.** Facts are split three ways and the view fills the gaps with fakes.
  - People: Freeciv holds a town as one number; nobles' families are hand-built in the bridge; commoners
    are invented by the view and "nothing to track" (`bridge/townsfolk.js:1-4`, `realm/scripts/villagers.gd:3-5`).
    So no one lives long enough to age, marry or hold a job.
  - Economy: gold is one number per house; the gold resource never runs out; market income is gold made
    from nothing (`bridge/treasury.js:104`, `markets * 40`). No goods, stocks or prices, so a house can't
    really own a gold mine.
  - Ground: six separate army systems (`units.gd`, `battle_ai.gd`, `siege_ai.gd`, `siege_storm.gd`,
    `combat.gd`, `tools/army_spike.gd`) and no realm-wide map of where a man can stand. Rivers have three
    different truths; in Freeciv a river speeds movement up. Burnt houses come back whole after a reload.
- **Effort went to looks.** Since 4 November, `realm/assets` was touched ~5,200 times against ~900 for
  `bridge/`. 53k lines of GDScript, 12k of bridge JS.
- **Nothing pre-built can become our own commercial game.** Bannerlord, CK3 and RimWorld mods can't be sold
  as ours. Widelands and Veloren have real economies but are GPL.

## What exists to build on

| Need | Best existing block | Stays ours |
|---|---|---|
| Towns by trade, goods, production, trading | OpenVic-Simulation (MIT, C++, builds for Godot 4.7) | Medieval goods and rules data |
| Markets and prices | BazaarBot (MIT) | Tuning |
| Mines that run out | Widelands' mine rule, copied as a design | Data |
| Families, ageing, life events | Talk of the Town (MIT) rules | Noble houses, succession |
| Daily routines | LimboAI (already in) driven by the sim's clock | Schedules |
| Who can stand where; armies through a breach | Godot navigation + flow fields (both add-ons immature) | One realm-wide ground layer |
| Wall damage, fire, seasons | Grid rules (shipped-game pattern); bridge already owns damage, weather, season | Persisting fire |
| Most of the physical layer ready-made | Unreal 5, if we ever switch (C++, Mac caveats) | — |

Pattern every shipped game uses: the rule lives in a grid or a table; the view picks a canned state from it.
Named individuals only for nobles and whoever is near the camera; everyone else is counted in groups.

## Decision needed (no block exists)

We'd own one small world sim: built on the models above, the only owner of people, goods and ground.
Freeciv keeps the map, war and diplomacy, or goes. The view only draws what the sim says.

**Decided (Mac, 12 Nov): our own sim.** It works alongside Freeciv, not inside it.

- **Start from what we have:** nobles already age, die and pass on titles in `bridge/characters.js:396`
  (`season()`). Grow that into one people model for nobles and commoners: identities that last, households, jobs.
- **Borrow designs, not code:** Neighborly (MIT, Python) for relationships, jobs and life events. It models
  one settlement, has no positions, and is reported archived April 2026, so it's a reference, not a dependency.
  Talk of the Town and OpenVic serve the same way.
- **One owner per fact:** the people sim owns people, jobs, goods and mine stocks. Freeciv gets the results
  (town size, gold) pushed one way, so nothing is counted twice. Freeciv keeps the map, war and diplomacy.
- **First proof, one chain:** a miner dies → the job falls vacant → household income drops → mine output drops
  once → Godot shows it.

## The three candidate sims (checked 12 Nov from their GitHub pages; none run yet)

| | Aithena | Polis Genesis | Neighborly |
|---|---|---|---|
| Link | [sa-aris/aithena](https://github.com/sa-aris/aithena) | [eyadstein/polis-genesis](https://github.com/eyadstein/polis-genesis) | [ShiJbey/neighborly](https://github.com/ShiJbey/neighborly) |
| Language | C++17, C ABI, Lua 5.4 scripting | Rust core, Python CLI, Three.js viewer | Python |
| Licence | MIT | MIT | MIT |
| State | v2.0.2 (Oct 2026), 31 commits, 6 stars, 226 tests, CI incl. macOS | v0.4.0, 58 commits, 0 stars, 37 open issues | Archived 7 Apr 2026, 80 stars, CoG 2022 paper |
| People | Households, marriage, kinship, children, ageing, death, inheritance, memory, reputation, factions | Needs, moods, memories, families, relationships | Traits, relationships, one job each, life events across generations |
| Economy | Production chains, labour, stockpiles, consumption, scarcity prices, caravans between markets | Jobs, wages, markets, housing, taxes, courts, treasury | Businesses and jobs only |
| Many towns | Yes (markets linked by caravans) | Not mentioned | No, one settlement |
| Save/load | JSON, tested | Versioned JSON | JSON export |
| Setting | Fantasy/medieval-neutral | Modern town (cars) | Generic |

**Revised view:** run one engine, not four. Aithena alone covers most of the people and economy layer:
one codebase, one clock, one save, a seeded rules sim (no LLM), and a C ABI the bridge or Godot can call.
Its risk is age and adoption (31 commits, 6 stars, one author), so it has to earn the place in a test.
Polis Genesis and Neighborly become design references: Polis for wages, housing and courts; Neighborly for life events.
If Aithena fails the test, fall back to our own sim in the bridge, borrowing all three designs.

**Aithena test (1–2 days, estimate):** build on this Mac; run its tests; run three settlements headless for
100 years; save, reload and compare; check the same seed gives the same history; read the code.

## Next discovery steps

1. Decide who owns the sim (one conversation).
2. Build and read OpenVic-Simulation on this Mac (1–2 days, estimate).
3. One page: the data model for people, goods, deposits and ground (~1 day).
4. Headless 100-year run: three towns and one gold mine (3–6 days, estimate).
5. Wall breach and river crossing test on one ground layer (3–5 days, estimate).

Unverified: OpenVic's state today, Widelands/GAMA on Apple Silicon, Unreal Mass and Chaos on this Mac.

## Decided (Mac, 12 Nov, later)

Commoners as groups is fine. A miner's death can be "miners −1"; the man in the square need not persist.
So OpenVic-Simulation (groups by trade, goods, production, trade) leads for the people and economy layer.
Named people stay for nobles only (`bridge/characters.js`). Aithena drops to fallback.
Next check (1–2 days, estimate): OpenVic runs on this Mac without Victoria 2 data; how finished it is;
use only towns, production and trade, with its countries, diplomacy and armies switched off.

## Rethink without a test run (12 Nov, later)

Judged from docs, code and fit, not by running anything.

- **OpenVic is out.** Its data loading points at a Victoria 2 install
  ([Dev Diary 7](https://openvicstorage.blob.core.windows.net/dev-diaries/Dev_Diary_7.pdf)); no releases;
  a 19th-century, whole-country model (factories, capitalists, diplomacy, armies) that overlaps Freeciv.
- **Freeciv is already a groups sim.** We run 3.2.6 (`/opt/homebrew/bin/freeciv-server`). Citizens per city,
  worked tiles, specialists (`cities.ruleset:47-79`), food and production boxes, buildings, trade-route goods
  (`game.ruleset:666`), gold per player, Lua signals (`script.lua`), and one savegame.
- **So the cheapest rich sim is deeper Freeciv, not a new engine.** Fill the gaps with its own ruleset and Lua:
  - Trades as specialists (miner, smith, merchant) [check: 3.2 allows more than three].
  - Mines run out: Lua counts worked turns and removes the Gold resource [check: remove-extra call in 3.2 Lua].
  - Goods carried by caravans as trade-route goods.
  - Replace `treasury.js:104` (gold from nothing) with gold that comes from worked mines.
  - Stockpiles and prices aren't native: a small ledger in Lua, saved with the game [check: Lua state in savegame].
- **Aithena** stays the reference for rules Freeciv lacks (scarcity prices, caravans between markets).

| Option | New engine | One owner, one save | Fits groups | Main gap |
|---|---|---|---|---|
| Deeper Freeciv (ruleset + Lua) | No | Yes | Native | Stockpiles and prices hand-added |
| Aithena | Yes (C++) | Needs sync with Freeciv | Built for individuals | Young, one author |
| OpenVic | Yes (C++) | Overlaps Freeciv | Native | Needs Victoria 2 data |
| Own sim in the bridge | No | Needs sync with Freeciv | Our choice | All custom |

## Decided: deeper Freeciv leads (Mac, 12 Nov). Checks confirmed from Freeciv S3_2 source

- **Up to 20 specialists** (`common/fc_types.h:411`, `SP_MAX 20`). Miners, smiths and merchants fit.
- **Lua can remove a resource from a tile:** `edit.remove_extra(tile, name)` (`server/scripting/tolua_server.pkg:165`). Mines can run out.
- **Lua state saves with the game:** `script_server_state_save` / `_load` (`server/scripting/script_server.c:387,399`) dump Lua globals into the savegame. Stockpiles and prices in Lua survive a reload. [check: what kinds of values the dump keeps]
- **Noble houses already have their own treasuries.** Each house is a Freeciv player with its own gold (`bridge/lua/snapshot.lua:45`); the bridge already moves gold between crown and house (`bridge/campaigns.js:133`, `bridge/arcs.js:735`). Mac: houses must be rich or poor in their own right, Game of Thrones style.
