# Society and economy sim: what exists, what to build on — 12 November 2026

Research only. No code changed. Scope: people, families, ageing, jobs, routines, towns rising and falling, production chains, finite deposits, hauling, markets, prices, trade, taxes, noble houses.
Engine choice and the Unity Classic City Builder Kit are covered in [independent-foundation-audit-2026-11-12.md](independent-foundation-audit-2026-11-12.md). Not repeated here.
Tags: **[fact]** = checked, with link or file:line. **[judgement]** = my opinion. **[est]** = effort estimate, not measured.

## 1. The answer, plain

1. Godot is not the mistake. No engine ships a medieval society. Every deep sim you named wrote its own sim; what they skipped was the renderer, not the sim. [judgement, section B]
2. The mistake: nobody owns the people. Freeciv owns a town as one number, the bridge owns nobles, and the Godot view makes up commoners each frame. No commoner exists anywhere long enough to age, marry or work. [fact, section C]
3. Freeciv's model sets the ceiling. Gold is one number per house. The "Gold" mountain resource never runs out. There are no goods, stocks or prices. You can't get a gold mine owned by a noble house out of it. [fact, section C]
4. Most of the effort has gone into dressing the view: 1,818 commits since 4 November; 5,198 file touches in realm/assets, 1,932 in realm/scripts, 907 in bridge/. [fact, git log]
5. No complete pre-built society and economy can ship in a commercial medieval game. Mods of Bannerlord, CK3 and RimWorld can't be sold as your own game. Open games that have it (Widelands, Veloren) are GPL, so their code would make the whole game GPL. [fact plus judgement, section A]
6. Build on this: one sim, owned in one place. Pops per town by trade (the OpenVic-Simulation layout: MIT, C++, already a Godot 4.7 GDExtension). Prices from a BazaarBot-style double auction (MIT). Named people only for nobles and anyone the camera is near (the CK3 and RimWorld level-of-detail pattern). LimboAI runs their day from the sim's schedule. Freeciv stays only for map, war and diplomacy, or goes. [judgement]
7. Under the project's rule ("if no block exists, say so and let Mac decide"): **no block exists for the society sim. Mac has to decide to own it**, kept small and built on borrowed models and algorithms. [judgement]

## 2. Need → best existing block → what stays custom

| Need | Best existing block (licence) | What it gives | What stays ours |
|---|---|---|---|
| One home for every fact (people, stocks, deposits, money) | **OpenVic-Simulation** layout (MIT, C++, GDExtension for Godot 4.7.2) [fact](https://github.com/OpenVicProject/OpenVic) | Separate managers for pops, goods, buildings, production and trading; save and load | Medieval data, plus our houses and the crown |
| Townsfolk at scale | OpenVic **PopsAggregate / PopType** (MIT) [fact](https://github.com/OpenVicProject/OpenVic-Simulation/tree/master/src/openvic-simulation/population); the same idea as Victoria 3 pops [fact](https://forum.paradoxplaza.com/forum/threads/victoria-3-dev-diary-105-migration-in-1-6.1624226/) | Size, trade, needs, cash and growth or decline per town group | Medieval trades, plus ageing as cohorts within a pop |
| Named people, families, ageing, heirs | Ours already: [characters.js:400-456](../../bridge/characters.js) (age, death, heir). Pattern from **Talk of the Town** (MIT, Python) [fact](https://github.com/james-owen-ryan/talktown) | Rules for households, marriage, jobs, businesses and life events to copy | Moving it into the one sim; "promoting" a commoner out of a pop when the camera or a story needs one |
| Daily routine, sleep, work | **LimboAI** (already in) + the sim's clock | Behaviour trees | Schedule data per trade (sleep, work, market, church) |
| Jobs and production chains | OpenVic **economy/production** (MIT); design from **Widelands** (GPL, design only) [fact](https://github.com/widelands/widelands/blob/master/src/economy/economy.cc) | Recipes, input to output, worker slots | Medieval recipe table (ore → smelter → bullion) |
| Finite deposits (gold mine) | **Widelands mine rule**, copied as design: a deposit runs down, then gives 5–10% odds when spent [fact, forum](https://www.widelands.org/forum/post/11476) | A proven rule players already understand | One deposit field and a tune line |
| Hauling | Widelands carriers (GPL: design only); Unity CCBK delivery tasks if we move engine | Pattern | Carts as goods in transit inside the sim; the view only draws them |
| Markets and prices | **BazaarBot** (MIT, Haxe, last push 2020) [fact](https://github.com/larsiusprime/bazaarbot), from Doran & Parberry 2010 [fact](https://ianparberry.com/pubs/econ.pdf) | Bids and asks, clearing price, agents adjusting their price beliefs | Port of about 300 lines; run it on pops, not individuals |
| Trade between towns | OpenVic **trading** (MIT); Veloren's merchant-trip idea (GPL: design only) [fact](https://veloren.net/blog/devblog-99/) | Moving goods between markets | Roads and caravan risk |
| Taxes, tithe, house treasuries | OpenVic country budget (MIT) as the shape | Income and spend per owner | Replace [treasury.js:93-99](../../bridge/treasury.js), which creates gold from nothing |
| Noble houses owning assets | Nothing pre-built does feudal ownership. CK3 has it but can't be licensed | — | An `owner_house` on every building, deposit and stock. Small. |
| Seasons | Ours already ([season.js](../../bridge/season.js), countryside.gd) | — | Seasonal modifiers in the sim's data |
| Testing the sim headless at scale | **Mesa** (Apache-2.0, v3.5.2, 28 Oct 2026) [fact](https://github.com/mesa/mesa) | Run 100 years in seconds, batch runs, charts | A Python twin of the rules for tuning only (optional) |

## 3. The gold mine, end to end, on the recommended blocks

[judgement: proposed design. Nothing here exists yet.]

1. **Deposit.** At world generation, a mountain tile gets `deposit{good: gold_ore, left: 40,000, owner_house: Ashby}`. It lives in the sim's map store, not in Freeciv. (Freeciv's "Gold" is an endless trade bonus: [terrain.ruleset:758, 1918](../../bridge/data/realmrules/terrain.ruleset).)
2. **Mine building.** An OpenVic-style building: recipe `labour → gold_ore`, 12 miner slots, owned by Ashby.
3. **Miners.** The `miner` pop in the nearby town fills the slots. Pay and food come from the pop's needs. If the pop shrinks (famine, plague, levy), output falls.
4. **Deposit runs down.** Each season, `left` drops by output. At 0, output falls to 5–10% odds (the Widelands rule). The town's miners lose pay, migrate or starve, and the town declines: the decline is visible and has a cause.
5. **Hauling.** Ore becomes a cart, a sim object with a load and a route, to the smelter town. Bandits or war on the road can take it. The view draws only the carts it is given.
6. **Smelting.** Recipe `gold_ore + charcoal → bullion`. Charcoal comes from the forest chain, so a mine needs woodcutters too.
7. **Market.** Bullion sells in the market town's BazaarBot round. Its price drops if three houses flood it. Ashby's stock becomes coin in Ashby's treasury.
8. **Taxes.** The crown's tithe takes a share of Ashby's real income, not `markets * 40` ([treasury.js:98](../../bridge/treasury.js)). Ashby grows rich, buys men and land, and its lord's goals in characters.js read its real wealth.
9. **The King sees it.** Mine slots → miners at work in the view (LimboAI, with real headcount). Carts on the road. Ashby's purse on its house card. A "mine is spent" event when `left` hits 0.
10. **Save.** Deposit, carts, stocks and purses are one save, owned by the sim. The camera never creates or destroys any of it.

## 4. Next steps, ranked

| # | Step | Effort | Confidence |
|---|---|---|---|
| 1 | Mac decides: does the sim become ours (one owner), and does Freeciv keep only map, war and diplomacy, or go? Without this, every step below is wasted. | 1 conversation | high |
| 2 | Build and run OpenVic on this Mac (macos-universal preset). Read its pop, economy and trading code. Decide whether to fork it as the base or copy its shape. Also confirm what its default mode runs without Victoria 2 data. | 1–2 days [est] | medium |
| 3 | Write the sim's data model on one page: person, household, pop, building, recipe, deposit, stock, cart, market, house, owner. One owner per fact. | 0.5–1 day [est] | high |
| 4 | Headless prototype: 1 region, 3 towns, the gold-mine chain, a BazaarBot market, the tithe. Run 100 years. Check that goods and gold are conserved, towns rise and fall, and the mine runs out. No graphics. | 3–6 days [est] | medium |
| 5 | Level of detail for people: promote a commoner out of a pop near the camera (family drawn from Talk of the Town rules), and fold them back in on leaving. Nobles stay named for ever (port characters.js). | 3–5 days [est] | medium |
| 6 | View reads the sim only: villagers.gd and town_life.gd draw what the sim says (headcount, trade, hour). They stop inventing it. | 1–2 weeks [est] | medium |
| 7 | Read Talk of the Town's code and James Ryan's thesis for the household and life-event rules. | 1 day [est] | medium |
| 8 | Only if staying with Freeciv: check whether its Lua and counters (3.2+) can hold deposits and stocks. Expect no, because the server's output model is fixed. | 0.5 day [est] | low |

---

## A. Candidates

"Ship?" asks whether a standalone commercial game can be built on it.

| Candidate | What it supplies | Last activity / release | Licence, cost | Apple Silicon | Headless / agent-scriptable | Ship? | Integration [est] |
|---|---|---|---|---|---|---|---|
| **Freeciv** (current) | Map, cities as size numbers, food, shields, trade, gold per player, caravans and trade routes ([units.ruleset:2603](../../bridge/data/realmrules/units.ruleset), [game.ruleset:606](../../bridge/data/realmrules/game.ruleset)), AI, diplomacy | Repo pushed 12 Nov 2026 [fact](https://github.com/freeciv/freeciv) | GPL-2.0, free | yes (running now) | yes (server + Lua) | yes, as GPL | in use; **the economy can't go deeper** |
| **OpenVic(-Simulation)** | Victoria 2-style pops, goods, buildings, production, trading, country budgets; C++ GDExtension for **Godot 4.7.2** | Pushed 11 Nov 2026; last tagged release v0.02, May 2023 [fact](https://github.com/OpenVicProject/OpenVic) | MIT, free | macos-universal build preset [fact] | C++ core, separate from the view | yes (MIT) | 2–6 weeks to medievalise [est]; early-stage project |
| **Widelands** | Full Settlers-style economy: wares, workers, carriers, flags, mines that run down, production sites | v1.3.1, 22 Feb 2026 [fact](https://github.com/widelands/widelands/releases) | GPL-2.0 | Mac builds exist [unverified] | partly (Lua scenarios) | only if the whole game is GPL | design source; an extraction port is months [est] |
| **Unknown Horizons** | Anno-style chains, settler levels, taxes | Last tag 2019; Godot 4 port "no playable content" [fact](https://github.com/unknown-horizons/godot-port) | GPL-2.0 | — | — | GPL only | not recommended |
| **Veloren economy** | Sites, labour value, merchant trips, regional prices; had hyperinflation and cycles [fact](https://veloren.net/blog/devblog-99/) | v0.18.0, Jan 2026 [fact](https://gitlab.com/veloren/veloren) | GPL-3.0 | yes | Rust server | GPL only | design source only |
| **0 A.D.** | Gatherers, drop sites, dynamic gather rates; no families or prices | R28, Feb 2026 [fact](https://play0ad.com/?p=5185) | GPL / CC BY-SA | native M1 build | JS sim, can run headless | yes, as GPL | see foundation audit |
| **OpenTTD / Simutrans** | Industry chains, cargo, towns growing with service | OpenTTD 15.3, Apr 2026 [fact](https://github.com/OpenTTD/OpenTTD/releases) | GPL-2 / Artistic | yes | yes (GameScript) | GPL | wrong genre; growth-by-service idea only |
| **BazaarBot** | Double-auction market, agent price beliefs | Last push Jun 2020 [fact](https://github.com/larsiusprime/bazaarbot) | MIT, free | n/a (algorithm) | yes | yes | 2–3 days to port [est] |
| **Talk of the Town** | Town sim: people, households, marriage, businesses, jobs, routines over 140 years [fact](https://cdn.aaai.org/ojs/12825/12825-52-16341-1-2-20201228.pdf) | Last push Sep 2024 [fact](https://github.com/james-owen-ryan/talktown) | MIT | Python | yes | yes | rules source; 1 week to port the core [est] |
| **Mesa** | Python agent-based modelling framework | v3.5.2, 28 Oct 2026 [fact](https://github.com/mesa/mesa) | Apache-2.0 | yes | yes | yes, but it's a tool, not a game layer | balancing harness only |
| **GAMA** | GAML agent platform, spatial, research grade | 2026.11.0, 3 Nov 2026 [fact](https://github.com/gama-platform/gama) | GPL-3.0 | Java | yes (headless mode) | GPL | not for shipping |
| **Bannerlord (mod)** | Towns with prosperity, workshops, caravans, clans, notables | live | EULA; I found no published terms allowing sale [fact: search found none] | **no macOS** [judgement] | C# modules | **no**: a mod, not your game | n/a |
| **CK3 (mod)** | Dynasties, ageing, inheritance, holdings | live; Paradox sells modder packs only through Paradox [fact](https://www.paradoxinteractive.com/media/press-releases/press-release/enjoy-all-crusader-kings-iii-content-through-subscription) | EULA | yes | script | **no** | n/a |
| **RimWorld (mod)** | Pawns, needs, jobs, relationships | live; EULA needs Ludeon's written consent for commercial use [fact](https://cdn1.epicgames.com/eulatracking-download/rimworld/en/v1/r1/eef0e74a0525ef36d5df83e7521aeb8c.pdf) | EULA | yes | C# | **no** | n/a |
| **Dwarf Fortress** | Deepest history and individual sim | live | closed | yes | no | **no** | n/a |
| **Godot sim add-ons** | Nothing complete. IdleCity and ColonySim are small games, not frameworks [fact](https://forum.godotengine.org/t/looking-for-base-builder-or-colony-sim-guidance/116283) | — | MIT mostly | yes | yes | yes | not worth it |
| **Unity CCBK** | see [foundation audit](independent-foundation-audit-2026-11-12.md) | — | US$60 | — | — | yes | — |

## B. How small teams who ship deep sims do it

| Game | Start point | Didn't build | Pops or individuals | Level of detail |
|---|---|---|---|---|
| CK3 | Paradox in-house engine | — | Individuals, but only nobles and court | Character count costs performance; CK2 devs pruned aggressively, and CK3 mods cut lowborn for about 30% speed [fact: community](https://catalogue.smods.ru/archives/400869); "time per tick" is the metric [fact](https://admin-forum.paradoxplaza.com/forum/developer-diary/dev-diary-164-realm-maintenance.1730576) |
| Victoria 3 | same | — | **Pops** (aggregates) | Devs: cost is "the number of Pops", not population; they avoid splitting pops [fact](https://forum.paradoxplaza.com/forum/threads/victoria-3-dev-diary-105-migration-in-1-6.1624226/) |
| Dwarf Fortress | own engine, 20+ years | graphics (ASCII, later licensed tilesets) | Individuals for history figures; abstract armies in world generation | World generation "plays a strategy game with itself"; the fort is in full detail [fact](https://pcgamer.com/dwarf-fortress-creator-on-how-hes-42-towards-simulating-existence) |
| RimWorld | Unity | renderer, physics | Individuals (about 20 colonists) | Off-map pawns mostly deleted or "mothballed" [fact: community, not primary](https://steamcommunity.com/app/294100/discussions/0/3810655055431734476) |
| Banished | own engine, one person, 3 years of tech first [fact](https://shiningrocksoftware.com/about/) | — | Individuals (hundreds) | small towns only |
| Songs of Syx | own Java engine, one person | — | Individuals, 10,000+ [fact: dev](https://red.ks32.dev/r/BaseBuildingGames/comments/dj6109/) | sprite 2D keeps that cheap |
| Manor Lords | Unreal 4→5 + Megascans, one person, programmers added near launch [fact](https://www.unrealengine.com/developer-interviews/solo-dev-makes-sophisticated-sim-manor-lords-using-unreal-engine) | renderer, scans | **Families as the unit** (a burgage plot = a family) [judgement: well known from play] | one region |
| Kenshi | OGRE engine, about 6 years solo of 12 [fact](https://www.gamepressure.com/newsroom/kenshi-comes-from-12-years-of-work-by-lone-developer/zd5d13) | renderer | Individuals plus faction abstractions | squads off-screen |

**Pattern** [judgement]: the sim is always theirs and is the first thing built. Small teams take an engine for drawing, keep the sim small, set the unit of detail (family, pop, character) on day one, and abstract everything off-screen. None of them bolted a strategy server under a 3D view and faked town life in the view.

## C. Our likely mistakes, from the repo

1. **Commoners are made up and forgotten.** [townsfolk.js:1-4](../../bridge/townsfolk.js): "generated from the town's id, so nothing to track". Ages and families are rolled on each call ([townsfolk.js:68-104](../../bridge/townsfolk.js)). Nobody can age, marry, die or change jobs. [fact]
2. **The view invents behaviour with no state behind it.** [villagers.gd:3-5](../../realm/scripts/villagers.gd): "Purely visual: the simulation of how many people there are belongs to Freeciv". [works.gd:3-6](../../realm/scripts/works.gd): "decides nothing". Yet villagers.gd (2,343 lines), town_life.gd (2,548) and npc_mind.gd (1,575) carry work, sleep and market life. Of the code, 53k lines are GDScript and 12k are bridge JS. [fact]
3. **People are one number.** Souls = town size × 600 ([routes_people.js:36](../../bridge/routes_people.js)). A town's population is a Freeciv size step. [fact]
4. **Money is created by command, not produced.** Each royal market gives `markets * 40` gold through `edit.change_gold` ([treasury.js:98-99](../../bridge/treasury.js)). A player's gold is one field ([snapshot.lua:45](../../bridge/lua/snapshot.lua)). The decree price is a share of the purse ([treasury.js:38](../../bridge/treasury.js)). No goods, stock or price exists. [fact]
5. **The "gold mine" can't exist in Freeciv.** "Gold" is a tile resource on mountains ([terrain.ruleset:758, 1918](../../bridge/data/realmrules/terrain.ruleset)): an endless trade bonus to whichever city works it. Houses are Freeciv players, so a house can't own one mine inside another's land. [fact]
6. **A CK-style genealogy was hand-built beside Freeciv** ([characters.js:400-456](../../bridge/characters.js): age++, death risk, heir takes the seat). It's fine to own, but it's a third owner of "people", next to Freeciv size and the view's villagers. [fact plus judgement]
7. **Effort went to the look.** 1,818 commits in 8 days (first commit 4 Nov 2026). Recent subjects: apples, flower boxes, awnings, repainted textures. File touches: realm/assets 5,198, realm/scripts 1,932, bridge 907. [fact, git log]
8. **The rule "never hand-build" pointed at the wrong layer.** Blocks were hunted for each visual (cobbles, kits, Meshy), while the one layer every shipped sim owns (the society model) had no owner. [judgement]

## Sources not verified

- Widelands macOS build status. GAMA on Apple Silicon. Bannerlord macOS (believed none). OpenVic's playable state and what its free default mode needs.
- Manor Lords "family per burgage" comes from play knowledge, not a dev source.
- RimWorld off-map pawn handling: community posts only.
- Talk of the Town's Python version: not read.
