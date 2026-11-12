# Using Freeciv properly: what moves in, what stays, what stops (12 November 2026)

Mac: "I largely think that we're using freeciv wrong." Research only. No code changed.
Read against Freeciv 3.2.6 (our server, `/opt/homebrew/bin/freeciv-server`), its local docs
(`/opt/homebrew/share/doc/freeciv/README.*`) and the S3_2 / S3_3 source on GitHub.

## Short answer

**Mac is right.** Our ruleset is stock civ2civ3 with names changed. Every rule that makes this a king game
lives in the bridge, beside Freeciv. So Freeciv's AI can't see our rules, and its saves don't keep them.
The houses plan wars knowing nothing of the tithe, favour, oaths or the King's peace.

**Move into Freeciv (its AI reasons about these; its save keeps them):**
1. **Royal decrees that last become "decree buildings".** An invisible building per decree (no one can
   build it), placed or removed by `edit.create_building` / `edit.remove_building`. Its effects go in
   `effects.ruleset`: content towns, defence, upkeep, AI love. The AI scores effects; the save keeps buildings.
2. **Unrest and risings run on Freeciv's own unrest.** Low favour makes towns unhappy through a decree
   building. Freeciv then riots, counts riot turns (a "Disorder" counter) and splits houses in civil war
   (`edit.civil_war`, `civil_war_enabled`). The bridge keeps the ultimatum and the court card.
3. **Sieges are fought, not rolled.** The King's siege is decided by `Math.random` and handed over by
   `transfer_city`. Let Freeciv's combat and its "Conquer City" action decide. A breach removes City Walls in Freeciv.
4. **Seasons, famine, blight and fire are Freeciv's.** Turn fragments give four seasons a year.
   Disasters (up to 10) give blight, fire and flood. Freeciv already runs famine and plague.
5. **Ruleset Lua runs in the ruleset.** Our Lua is loaded from the console (`lua file`), so it isn't in the
   save. It goes into `realmrules/script.lua` on `turn_begin`. The mines already show how.
6. **Clear out the modern ruleset.** Communism, Federation, Democracy, nuclear accidents, spaceship
   achievements. Add medieval policies (multipliers) the house AIs set for themselves.

**The bridge keeps:** the court, petitions, rulings, seals, the Director, story arcs, the chronicle, minds,
the King's orders to his host, and favour as a number until Freeciv can hold it. That is the game layer.
Freeciv has no court and should not get one.

**Stop doing:**
- **Stopping Freeciv to rewrite its save** to force a truce (`bridge/server.js:187-233`). It's the clearest
  sign we're fighting the engine.
- **Rolling sieges in JavaScript** (`bridge/campaigns.js:154-158`).
- **Armies from nothing:** pretenders, allies, levies and barracks men made by `edit.create_unit`, often with
  no home town, so they cost nothing to keep (`bridge/lua/events.lua:173-190`, `bridge/treasury.js:107-108`).
- **Teleporting hosts tile by tile** (`bridge/hosts.js:144-148`): it skips movement rules and zones of control.
- **Turning farmland to Desert as "blight"** (`bridge/blight.js:10-18`): a weather event leaves a lasting map edit.
- **Gold gifts by `edit.change_gold`**, where the AI should notice: it only gains love from gold given in a treaty
  (`ai/default/daidiplomacy.c:781-788`).

**The hard limit, said plainly.** Freeciv 3.2's Lua can't set diplomacy, AI love, policies, food or city
size. Three ways past it, in order:
1. Use what 3.2 does have: buildings, effects, counters, disasters, civil war, signals.
2. **Freeciv 3.3** adds `Player:love`, `Player:add_love`, `Player:cancel_pact`, `edit.change_city_size` and
   `edit.change_citizen_nationality` (`server/scripting/tolua_server.pkg` on S3_3, lines 255-258, 580-585). That
   makes favour into real AI love, and levies taken from real townsfolk. It isn't released yet (no R3_3 tag;
   Homebrew has 3.2.7). Move when it is, not before. [estimate: 1 day to switch, once released]
3. **Connect the Crown as a client**, like freeciv-web: real treaties (alliance oaths, gifts the AI counts, the
   King's own ceasefires) and the Crown's own policies. A big job; only if 1 and 2 fall short. [estimate: 1-2 weeks]

## Where this agrees and differs with the integration plan

[freeciv-integration-plan-2026-11-12.md](freeciv-integration-plan-2026-11-12.md):
- **Agree:** houses are players with their own gold; specialists renamed (done: Minstrels, Scholars,
  Reeves, `cities.ruleset:48-79`); no gold from nothing (done: `marketGold` 0); mines run out in Lua (done:
  `lua/events.lua:137-162`).
- **Answers its [check]:** the Lua save keeps numbers, booleans, strings and Freeciv objects, **not tables**
  (`common/scriptcore/tolua_common_a.pkg:136-170`, `_freeciv_state_dump`). That's why the seams are packed into
  one string. Store Lua state the same way.
- **Answers its other [check]:** 3.2's Lua can't list worked tiles. The ruleset can: the `CityTile "Worked"`
  requirement (README.effects). The seam count uses "inside a town's radius" instead (`lua/events.lua:88-94`).
- **Differs:** that plan covers only the economy. The bigger gap is politics and war: favour, risings, truces,
  oaths and sieges. Those drive the reign, and Freeciv's AI knows nothing of them.
- **Fits Mac's "own sim" call (12 Nov):** people, jobs and goods stay in our sim. Map, war, diplomacy, towns
  and gold belong to Freeciv. This note moves the rules that belong to Freeciv into it.

## Rule by rule

Effort is always an [estimate]. "Move" = into ruleset or ruleset Lua. "Keep" = the bridge stays the owner.

### Money

| Our rule | Where | Freeciv's own way | Call | Effort |
|---|---|---|---|---|
| Tithe: a share of each house's town size, a quarter a season, taken by `change_gold` | `crown.js:53-75`, `treasury.js:116-143` | No tribute between players exists. Run it in ruleset Lua on `turn_begin`, rate as a Lua number (saved). | Move the running; keep the rate set by the King | ½ day |
| Heavy tithe wears favour, towns mutter | `treasury.js:139`, `economy.json` tithe.wear | A "Heavy Tithe" decree building: `Make_Content` −1 in houses' towns (README.effects:453) | Move | ½ day |
| Crown upkeep: 2 + 2 a town + share of purse | `crown.js:46-48` | Building upkeep: a "Royal Court" building in Kingsmere with gold upkeep; `Upkeep_Factor` | Move | 2 h |
| Royal works: built after 2 seasons by `create_building` | `treasury.js:82-104` | Fine (Freeciv owns the building). Could be bought into the town's build queue, but Lua can't set production. | Keep | — |
| Barracks give a free company each year | `treasury.js:107-108` | Freeciv builds units from shields; `Veteran_Build`, `Unit_Upkeep_Free_Per_City` | Stop | 1 h |
| Gifts, debts, story gold by `change_gold` | `crown.js:148-155`, `characters.js:1162-1173`, `arcs.js:723`, `events.js:137`, `reign.js:264` | Gold clause in a treaty (AI gains love, `daidiplomacy.c:781-788`): needs a client or 3.3 `add_love` | Keep now; add `add_love` on 3.3 | 2 h on 3.3 |
| Gold seams run out | `mines.js`, `lua/events.lua:137-162` | Already Lua with saved state. Wire to `turn_begin` in `script.lua` instead of the bridge's call each season. | Move (finish) | 2 h |
| Gold from markets | `treasury.js:106` | Freeciv tax (already 0 extra) | Done | — |

### Favour, unrest, risings

| Our rule | Where | Freeciv's own way | Call | Effort |
|---|---|---|---|---|
| Favour 0-100 per house, bands loyal/sworn/steady/cooling | `favour.js:6-20`, shifted from ~40 places | AI love (−1000..1000), saved per pair (the save's "ai" rows). 3.2: no Lua to set it. 3.3: `add_love`. | Keep the number; mirror into love on 3.3 | 1 day on 3.3 |
| A house turns: ultimatum, banners, rising in 2 seasons | `season.js:92-141`, `154-180` | Riots: `Make_Content` −n from a "Grievance" building at low favour; a `Disorder` counter (`sandbox/game.ruleset:795-850`) reaching its checkpoint is the rising | Move the trigger; keep the ultimatum card | 1 day |
| The rising itself: a host spawned at the seat | `stakes.js:126-150`, `lua/events.lua:173-190` | `edit.civil_war` splits a house; `edit.place_partisans`; units the house already has | Move | 1 day |
| Pretender's claim | `stakes.js:110-120`, `director.js:125` | Civil war (`Civil_War_Chance`, README.effects:318; `civil_war_bonus_*`, `game.ruleset:146-152`) | Move the split; keep the story | with the above |
| Feast, relief: favour up | `crown.js:138-146`, `200-213` | A timed "Feast" building: `Make_Content` / `Make_Happy` for N turns, removed by Lua after. Relief moves no grain (3.2 can't add food; 3.3 can grow a town). | Move | ½ day |
| Ward at court: house won't rise | `crown.js:214`, `season.js:97` | Keep (court rule); add `Gain_AI_Love` only if 3.3 isn't out | Keep | — |

### War and peace

| Our rule | Where | Freeciv's own way | Call | Effort |
|---|---|---|---|---|
| King's truce between two houses: stop Freeciv, edit diplstate and AI rows, reload | `server.js:187-233`, `characters.js:1206-1214` | None in 3.2 Lua or console. 3.3: `add_love` so the AI sues for peace itself, and `cancel_pact`. | Stop on 3.3; keep till then as a known hack | 1 day on 3.3 |
| Oath (sworn house fights the King's wars) | `crown.js:315-325`, `campaigns.js:65` (allies spawned) | A real alliance (treaty clause, `game.ruleset:705`) needs a client. Until then: send the sworn house's own units, not new ones. | Keep the oath; stop spawning | ½ day |
| King's siege: odds, then `Math.random`, then `transfer_city` | `campaigns.js:75-95`, `139-158` | Freeciv combat and "Conquer City" (README.actions); `Defend_Bonus` from City Walls | Move | 1-2 days |
| Siege terms (pay to lift, press, starve) | `campaigns.js:101-130` | Keep: a court card. Starving: Freeciv food box. | Keep | — |
| Wall wear and breach (view only) | `damage.js:14-42` | Breach removes City Walls (`edit.remove_building`), so Freeciv's defence drops too; wear as a Lua-raised counter [check: whether Lua may raise a counter of type Owned] | Move the breach | ½ day |
| Burnt houses (kindled) | `damage.js:53-65` | View detail. Freeciv's "Fire" disaster destroys a building. | Keep | — |
| Garrison: King's men stand in a town | `garrison.js:16-29` | Units are Freeciv's already. Home them to the town so they cost upkeep. | Keep | 1 h |
| Levy, sellswords, banners: men appear at Kingsmere | `crown.js:85-137`, `157-174` | Same `create_unit`, but homed to Kingsmere (upkeep). Levies from townsfolk need 3.3 `change_city_size`. | Keep, homed | 1 h |
| Hosts walk by teleport | `hosts.js:144-148` | `edit.unit_move` (respects move cost; tolua_server.pkg S3_2) [check: zones of control] | Move | ½ day |
| Who won a battle | `battles.js` | Already read from Freeciv's `unit_lost` | Keep (right) | — |
| Grant or cede a town | `crown.js:295`, `337-352`, `petitions.js:46` | `transfer_city` is the native call | Keep | — |
| Peace decree (sends hosts home) | `crown.js:262-284` | With the truce above | Keep for now | — |

### Seasons and fate

| Our rule | Where | Freeciv's own way | Call | Effort |
|---|---|---|---|---|
| Seasons from the turn number | `stakes.js:14-27` | Calendar `fragments = 4` (`game.ruleset:407`, now 0); `MinCalFrag` requirement for winter effects | Move | ½ day |
| Weather rolled per season | `weather.js:22-43` | No weather in Freeciv. Winter by fragments; storms stay ours. | Keep | — |
| Blight and famine: farmland turned to Desert, granary removed | `blight.js:10-18`, `director.js:157`, `189-190` | A disaster with `EmptyFoodStock` / `ReducePopulation` (`game.ruleset:420-445`), reqs on terrain and season | Move | ½ day |
| Plague | read from the save (`savefile.js:96`) | Already Freeciv's `[illness]` (`game.ruleset:207`) | Keep (right) | — |
| The dead and wildlings | `lua/events.lua:168-190`, `stakes.js:170-195` | Barbarians (`set barbarians`, `edit.unleash_barbarians`), a barbarian player | Keep the waves; use barbarian rules | — |
| Disaster frequency | `routes_realm.js:165`, `realm.serv:24` | Already the `disasters` setting | Keep (right) | — |

### The ruleset itself

| What | Where | Freeciv's own way | Call | Effort |
|---|---|---|---|---|
| Effects are civ2civ3's but for river wading | `realmrules/effects.ruleset:424-432` | Our own effects: decree buildings, seasons, walls | Move | with the rows above |
| Modern governments | `governments.ruleset:232` (Communism), `322` (Federation), `402` (Democracy) | Medieval set: Tribal, Despotism, Monarchy, Feudal, Merchant Republic | Change | ½ day |
| Nuclear and industrial disasters, spaceship achievement | `game.ruleset:472-488`, `514` | Remove | Change | 1 h |
| Royal goals (the goal ladder) | `reign.js:250-265` | Achievements: Rich, Metropolis, Killer, Cultured (README.achievements); `achievement_gained` signal | Move where they fit | ½ day |
| House temperaments | `data/nation/*.ruleset` traits; `realm.serv:28` | Already Freeciv traits; `edit.trait_mod` changes them in play | Keep (right) | — |
| No policies | none | Multipliers (`sandbox/governments.ruleset:470-530`; effects take `multiplier =`). The AI sets its own (`ai/default/daidata.c:442`, `dai_adjust_policies`). The Crown can't from Lua or console in 3.2. | Add for the houses | 1 day |
| One trade good | `game.ruleset:666` | Several goods (`sandbox/game.ruleset:664-700`) | Later | — |
| Our Lua loaded from the console | `realm.serv`, `resume.serv` (`lua file lua/events.lua`) | `realmrules/script.lua` loads with the ruleset, every time | Move | ½ day |

### What the bridge rightly keeps

The court, petitions and rulings (`court.js`, `petitions.js`, `rulings.js`), seals (`seals.js`), the Director
(`director.js`), story arcs (`arcs.js`), the chronicle and minds. Freeciv has nothing like them. They act on
Freeciv only through its native calls: buildings, units, towns, gold.

## How others drive Freeciv

- **freeciv-web** runs the official server, patched for a WebSocket/JSON protocol behind a Python proxy. The
  browser is a real client: treaties, tax rates and policies go through the protocol, not Lua. Our option 3.
- **Longturn** (Freeciv21 fork): game rules live in each game's ruleset folder, `script.lua` and `parser.lua`
  beside the `.ruleset` files. Rules are effects first, Lua second.
- **Freeciv's own scenarios** (`data/scenarios/tutorial.sav`): Lua in the save's `[script]` section, wired to
  signals (`turn_begin`, `city_built`, `unit_moved`...). The game drives the script, not an outside caller.
- **Common pattern:** state in effects and buildings, the AI left to play them, Lua only for what effects
  can't say. We do the reverse.

## Order of work (if Mac says build)

1. Lua into `script.lua` on `turn_begin`; strip the modern ruleset. [estimate: 1 day]
2. Decree buildings: feast, heavy tithe, grievance, royal court. [estimate: 1-2 days]
3. Risings through riots and civil war. [estimate: 1-2 days]
4. Sieges by Freeciv combat; breach removes walls; hosts walk by `unit_move`. [estimate: 2 days]
5. Seasons by fragments; blight as a disaster. [estimate: 1 day]
6. On Freeciv 3.3: favour into love, truces without the reload, levies from townsfolk. [estimate: 2-3 days]

Each step gets a state check on the private bridge: AI behaviour changes, and a save and reload keeps it.

## Sources

- Freeciv 3.2.6 docs, installed: `/opt/homebrew/share/doc/freeciv/README.effects` (effect types 165-801,
  requirement types 54-110), `README.actions`, `README.achievements`, `README.scenarios`.
- Rulesets, installed: `/opt/homebrew/share/freeciv/sandbox/game.ruleset` (counters 795-850, goods 664-700),
  `sandbox/governments.ruleset:470-530` (multipliers), `sandbox/effects.ruleset:949-975` (`multiplier =`),
  `civ2civ3/game.ruleset:420-488` (disasters).
- Lua API, S3_2: [tolua_server.pkg](https://github.com/freeciv/freeciv/blob/S3_2/server/scripting/tolua_server.pkg),
  [api_game_methods.h](https://github.com/freeciv/freeciv/blob/S3_2/common/scriptcore/api_game_methods.h),
  [tolua_common_a.pkg](https://github.com/freeciv/freeciv/blob/S3_2/common/scriptcore/tolua_common_a.pkg) (state dump),
  [script_server.c](https://github.com/freeciv/freeciv/blob/S3_2/server/scripting/script_server.c) (39 signals; `script.vars` save).
- Lua API, S3_3: [tolua_server.pkg](https://github.com/freeciv/freeciv/blob/S3_3/server/scripting/tolua_server.pkg) (love, add_love, cancel_pact, change_city_size).
- AI: [daidiplomacy.c](https://github.com/freeciv/freeciv/blob/S3_2/ai/default/daidiplomacy.c) (love from gifts 781-788, `Gain_AI_Love` 1120-1123),
  [daidata.c](https://github.com/freeciv/freeciv/blob/S3_2/ai/default/daidata.c) (`dai_adjust_policies` 442).
- [freeciv-web](https://github.com/freeciv/freeciv-web); [Longturn Lua scripting](https://longturn.readthedocs.io/en/latest/Modding/Rulesets/script.html);
  [Longturn game admin guide](https://longturn.readthedocs.io/en/stable/Contributing/game-admin.html).
- Our code: line numbers above, read on 12 November 2026 from the shared checkout (other threads are editing it).

## Built (12 November 2026, same day)

All seven steps landed, each with a headless probe in `bridge/tools/*_probe.mjs` (bare Freeciv, our ruleset).

| Step | Commit | What changed |
|---|---|---|
| 1 Ruleset Lua | 20c2ee09 | `lua/events.lua` is in `realmrules/script.lua`; mine numbers in `realmrules/luadata.txt` |
| 2 Medieval ruleset | c56a5f0d | Modern governments, nukes and spaceship gone; three policies the AI sets |
| 3 Decree buildings | 9a3ac0cc | Royal Feast, Royal Relief, Heavy Tithe |
| 4 Grievance | 98f85600 (files in f7de4b61) | Cold houses lose content citizens; small wonders, because negative Make_Content does nothing |
| 5 Sieges | aad88002 | War on march; Freeciv fights each assault; conquest by `edit.unit_move`; breach removes City Walls |
| 6 Seasons | dc961492 | Four named fragments a year, winter food -20%, Blight building and disaster; `blight.js` gone |
| 7 Real moves | d58878d4 | Hosts move by `edit.unit_move`; raised companies homed (upkeep) |

**Findings while building:**
- A negative Make_Content makes no one unhappy (`common/city.c` citizen_content_buildings). Unrest has to lower City_Unhappy_Size, and only a wonder reaches a whole house.
- Freeciv's AI never lets a town riot, so the Disorder counter can't be a clock.
- Attack enablers must require war (hard rule); Lua's `perform_action` "Conquer City" is refused even through the native enabler, while `edit.unit_move(..., conquer_city)` works.
- The server console cuts long lines: long Lua goes in a file (`lua file`).

**The one diplomacy writer:** `server.js` `setDiplomacy` (a truce or a war) rewrites the save and resumes. Measured reload cost: 874 ms and 995 ms [2 samples, bridge.log]. Freeciv 3.3's `Player:cancel_pact` and `Player:add_love` replace it once 3.3 is released.

## Hand edits of Freeciv state still in the bridge (12 November 2026, after 2585c496)

The four "send them home" decrees no longer kill (2585c496: a homeward march and Disband Unit Recover). What is left, by kind:

| Hand edit | Where | Freeciv's own way | Call |
|---|---|---|---|
| Raids: half a town's men killed by dice, gold taken | was `arcs.js`, `characters.js` (three copies) | Barbarians: `Tile:unleash_barbarians()` beside the town; Freeciv's barbarian AI raids, pillages and plunders | **Done:** `realm_raid` (ruleset Lua) unleashes on an empty tile two out; `onsetbarbs` 1 in game.ruleset (the 3.2 setting's name; the old probe's `onsetbarbarian` was not a setting, so onset stayed at the ruleset's 120 and nothing came); raiders "Some" is `huts_only` (no wild hordes of their own). Probe `tools/raid_probe.mjs` |
| Gold moved between players (tithe, gifts, debts, decree costs, story gold, plunder) | `crown.js` (`Lua.gold`), `treasury.js`, `campaigns.js:138`, `characters.js`, `arcs.js:723`, `events.js:137`, `court.js:57`, `reign.js:264` | Only a treaty's gold clause (a client connection); 3.3 adds none | Keep. Freeciv has no tribute between players |
| Units raised by decree, story, petition or reward (levy, sellswords, garrison, hunt, rebels, reign reward, barracks yearly) | `crown.js:135,174,183`, `garrison.js:25`, `petitions.js:132-133`, `characters.js:614,1115`, `arcs.js:740`, `reign.js:261`, `treasury.js:109` | Bought in a town's production (no Lua for production or buying in 3.2) | Keep. All are homed to a town, so Freeciv charges their upkeep |
| Hosts raised for stories, threats, pretenders, allies | `realm_host`: `stakes.js:58`, `director.js:152,181`, `campaigns.js:67`, `arcs.js:754`, `characters.js:1142`, `crown.js:377` | The house's own units, ordered (no Lua orders in 3.2) | Keep. Homed since d58878d4 |
| Banners: a house's men taken off and raised again for the crown | `crown.js:132` | Unit ownership change (none in 3.2's Lua) | Keep, a transfer (commented) |
| Towns handed over (grants, cession, story seizures, a threat's capture) | `Lua.transferCity`: `crown.js:319,325,363`, `director.js:180`, `petitions.js:46`, `characters.js:568`, `arcs.js:765` | `edit.transfer_city` is Freeciv's own call | Keep |
| Royal works finished | `treasury.js:98` (`edit.create_building`) | City production and buying (no Lua in 3.2) | Keep (paid for, built over two seasons) |
| A famine takes the granary | `director.js:189` (`edit.remove_building`) | A disaster with `DestroyBuilding` hits a random building, not the granary | Keep |
| Reign-start options (house wealth, the King's purse, a strong or small royal host) | `server.js:389,426,428,431`, `chronicles.js:220` | Scenario setup, like `world_setup.lua` | Keep |

## The case each change serves (casebook, Mac's goal since 12 November 2026)

| Change | Case | How |
|---|---|---|
| Step 2: house policies (levies, tolls, granaries) | "Every answer costs" (Reigns) | Each policy step buys something and costs something; the house's AI weighs both |
| Step 3: feast, relief, heavy tithe as buildings | "Every answer costs" (Reigns) | A heavy tithe fills the purse and empties the houses' content; a feast or relief helps for its seasons, then lapses |
| Step 4: Grievance | "Opinions run one way" (Crusader Kings II) | Favour is the one visible number; below 25 the house's own people pay for it in Freeciv, and its AI acts on that |
| Step 5: sieges fought by Freeciv | "A siege is a season" (Total War: Attila) | One assault a season, terms from the herald between, the walls cracking, up to four seasons before the host breaks |
| Step 6: seasons, winter food, blight | "Winter changes every number" (Northgard); "Winter as the exam" (Banished) | Winter cuts every field by a fifth; a granary filled in autumn is what carries a town through |
| Step 7: hosts move and cost upkeep | "The march feeds the battle" (Bannerlord) | The men raised for a war are fed by a town all the way there, and walk by the land's rules |
| Homeward march (2585c496) | "Binding promises" (Crusader Kings III) | When the King buys off a pretender or makes two houses stop, their men really go home and disband; the promise is kept in the world |
| Step 1: the game's Lua in the ruleset | The genre's promise: "a world … that remembers what you did" | Freeciv's save keeps every decree, seam and grievance |

Raids as Freeciv barbarians (open, needs Mac's onset call) would serve "Every answer costs" for the houses: a town left without soldiers is a town the raiders find.
