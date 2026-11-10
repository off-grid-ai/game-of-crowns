# Discovery answers: Game of Crowns

Read-only. Nothing was edited and the game was not run.
`S` = `/private/tmp/claude-501/-Users-user-wednesday-civilization/98b39ed0-34fa-4bb7-9bf7-c780e67f617b/scratchpad`
`R` = `/Users/user/wednesday/civilization`
`BO` = `R/bridge/chronicles/the-broken-oath-mwac9ufd` (the founder's real reign)

Context that frames everything:
- Every reign, test or real, uses seed 1066 and starts from the same baseline at turn 38 (`meta.json` "seed", "fromBaseline": 38 in all 40 reigns). Turns 1-38 are pre-simulated. Play starts at turn 39, autumn 309.
- The friction run restored the-broken-oath at turn 39 (`S/friction/run.txt`). That is the same point where a new reign starts, so its first frames stand in for a new player's first minutes. The menu and new-reign screens before that were not captured, so they **need a film**.
- Frame times come from file mtimes (`stat` on `S/friction/*.jpg`). The run went from 12:40:18 to 13:01:41.

---

## A. First minutes

**A1. Minutes 1, 2 and 3**
- **0:00-0:30.** Two painted loading cards: "Its own clock" and "The chronicle", with "click or press any key to begin" (`S/friction/001.jpg`, `002.jpg`).
- **~0:31.** The realm appears with the court card already up: "THE COURT SITS · THE REALM HOLDS STILL". This is the **first decision**: Thornvale and Stormhold are at war. The choices are Command peace (15k), Back Stormhold (15k), Wed them (40k), Later, or Close the court (`S/friction/003.jpg`).
  - In the friction run the Houses and Chronicle panels are also open. In friction2 and lordpics2 only the court card is open, so that is the default (`S/friction2/004.jpg`, `S/lordpics2/003.jpg`).
- **Minute 1, ~0:46.** The court closes. The Houses and Chronicle panels show, the aim "Muster a royal host of twelve companies 5 of 12" appears top left, and a "Feud of Stormwatch · Watch" chip shows (`004.jpg`). The Kingsmere town card offers royal decrees, and the script orders a granary (`004t.jpg`, `run.txt`).
- **Minute 2 (005-008).** Watch chips appear ("The Treason of Redmarch"). The second court comes at ~1:53: Cecily Stormhold's deserters, with three answers plus "Or rule in your own words" (`008.jpg`).
- **Minute 3 (009-012).** The King's rider leaves for Stormwatch, with a caption in the world (`010.jpg`, `011.jpg`). The third court comes at ~3:25: the Goldcrest–Thornvale war (`012.jpg`).
- The player does: 3 court answers and 1 decree in about 3.5 minutes. The rest of the time they read panels.

**A2. When the game makes clear what it wants**
- The aim line "◆ Muster a royal host of twelve companies, 5 of 12" at ~0:46 (`S/friction/004.jpg`). At 0:31 the court card hides it (`003.jpg`).
- The three ambitions ("promises") appear only as ◇◇◇ and "Promises kept: 0 of 3" (`S/lordpics2/004.jpg`). Their text is first referred to at the act card, ~4:12: "Of the three things you swore to do, none is done yet" (`S/friction/015.jpg`). No frame lists them. Where they are shown **needs a film**.

**A3. Delight and confusion** (a demanding player's judgement from stills)
- **First delight, ~0:31.** The first court: a lord's figure and sigil, the Hand's one-line advice, and every answer carrying its price and effect (`S/friction/003.jpg`).
  - Runner-up, ~4:12: the camera finally leaves the panels for Stormwatch, burning after Thornvale storms it, under "In the taverns they call you the Golden" (`015.jpg`).
- **First confusion, ~0:46.** The Houses board says "All 6 great houses would answer your banners… The realm is at peace with itself", yet four rows read WAR. Peace was commanded seconds earlier, and Stormhold still shows "WAR · SUNSPIRE" (`004.jpg`).
- **The intro card contradicts itself.** It says "a season every twenty seconds" (`S/friction/001.jpg`) and in another run "every forty seconds" (`S/lordpics2/001.jpg`). The server uses 40 s (`R/bridge/server.js:123`).

## B. Decisions

**B4. Every decision in one reign**
- **Founder's reign, the-broken-oath** (`BO/state/chronicle.jsonl`, `BO/court.json`). It ran 15 minutes; the clock used is 795 s.
  1. Turn 39, ~1:44 after the start (98 s with the court open): "Goldcrest rides between Thornvale and Stormhold" (settle).
  2. Turn 40, ~3:35: Thornvale's heir taken as a ward.
  3. After that, none. Two great councils (turns 49 and 55) and three story petitions (turns 39, 49, 55, `answered: false`) went unanswered. Two ambitions were met with no decision.
  - **2 decisions, 111 s apart, then about 20 seasons (~10 min of reign) without one.** GAME_DESIGN pillar 1 asks for "about one decision a minute".
- **Scripted friction run** (`S/friction/run.txt`, `chronicle.json`):
  - court ~0:31; decree (granary) ~0:55; court ~1:53; court ~3:25; decree (royal host marches) ~10:00. The turn-45 court was never reached.
  - **5 in about 10 min. Gaps: 24 s, 58 s, 92 s, 6.5 min.**

**B5. Is there an option that's almost always best?** (`R/bridge/data/dilemmas.json`, `R/bridge/crown.js` DECREES, `R/bridge/server.js:740-770` DOES)
- **Test choice rates mean nothing.** The harness's `answer` step always presses the first button (`R/realm/scripts/autoplay.gd`, the "answer" step).
- **Money barely binds.**
  - The treasury is 111k-129k crowns. Prices are 5k-40k (1 gold = 100 crowns on screen). The net is about −1.8k a season (`S/friction/chronicle.json`, turn 40 tithe).
  - So a paid option usually wins.
- **The Hand's war matter: "Command peace" is near-dominant.** It costs 15k, gives +2 to each house plus a truce, and nobody loses favour.
  - "Wed them" (40k, +8 each) beats it whenever the purse allows, which is almost always.
  - "Back the weaker" (+12/−12) and "Sit it out" lose.
  - Note: the peace commanded at turn 39 did not hold. An arc marched Thornvale on Stormwatch at turn 43 and stormed it at turn 44 (`S/friction/chronicle.json`).
- **Town decrees: feast beats gift.** Feast is 10k for +15; gift is 15k for +10.
- **Dilemmas where one answer dominates:**
  - Paid answers that cost no favour: maester, healers, fleet, rebuild, pardon deserters (+5 and 2 pikemen, versus hang at −15), turn the spy, fund tourney.
  - Free answers that are simply better: lord_sick swear (+20 vs −5), hostage_swap accept, royal_match accept, secret_alliance bless.
  - envoy_insult: expel equals duel minus the opinion hit, so expel dominates.
- **Real trade-offs:** abduction, border_war, raid_reprisal, heretic_lord, spy_caught, bridge_toll, bannerman_slight, old_lord_dotage, faithless_wife, dragon_egg, challenge_heir.
- **Caveat.** The hidden "memory" and "goal" effects pay out later and are not costed. Whether they change these picks **needs a film** or a long sim.

**B6. A decision whose result showed in the world later**
- **Yes: the deserters ruling.** Ruled at turn 41 (~1:53, `S/friction/008.jpg`).
  - The King's rider leaves Kingsmere with a "bound for Stormwatch · Watch" chip and a caption in the world (`010.jpg`, `011.jpg`).
  - At turn 44 the chronicle says "The King's rider reaches Stormwatch". The caption floats over Stormwatch (`015.jpg`).
  - About 2.5 minutes later.
- **Granary (turn 40):** "stands finished" at turn 42, but as text only. That a building rises in the world **needs a film**.
- **Royal host (~10:00):** only a "Done:" toast in this run (`020.jpg`). In friction2: "The King's levy musters at Kingsmere · Watch" (`S/friction2/021.jpg`), then Wolfholt shows "WAR · THE CROWN", favour 15 (`S/friction2/037.jpg`).

## C. Story events

**C7. Story events in one reign, and how many became a scene** (`BO/state/chronicle.jsonl`, turns 39-60: 125 entries)
- The mapping comes from `server.js picture()` (lines 90-106), `onEvent` (lines 505-511), `sieges()` (line 459), `rulingScene` (line 470) and the decree scenes (lines 2313-2325).
- **Has a scene: 40.**
  - death 9 → rider
  - city_shrank 9 → plague or famine
  - alliance 6 → rider
  - betrayal 5 → handover
  - succession 4 → feast
  - raid 3 → sack
  - city_transferred 3 → sack or handover
  - city_destroyed 1 → razed
- **Partly shown: 33.** Arcs. Watch takes the camera to the town or the commoner (`main.gd:1561`), but the beat itself is words.
- **Text only: 52.**
  - scheme 7: "refuses… daughter's hand" carries no `with`, so there is no rider
  - building_built 8, city_built 6, court 6, year 5, act 4, unrest 3, decree 3 (settle and ward have no scene in code), tech 3, tithe 3, council 2, ambition 2
- **About 32% shown, 26% partly, 42% text only.**
- Even the "shown" scenes are only offered: the lords' news at most once every 20 s, and as an edge arrow when off screen (`main.gd:1530-1550`). How many a player actually sees **needs a film**.

**C8. Text-only events, by how often they fire** (all 40 reigns, turn 39 on)
1. building_built 1,500
2. year 604
3. city_built 602 (the town appears, but with no scene)
4. rebellion 476 (no picture() case; whether a siege on Kingsmere is staged **needs a film**)
5. scheme ~410 (most have no `with`)
6. court 317
7. unrest 294
8. tithe 263
9. tech 204
10. crown 93
11. building_lost 49
12. act 30
13. marriage 27 (a feast only for a match blessed at court)
14. person 25
15. disaster 18
16. council 4
17. ambition 3

## D. Tension

**D9. Tension over time in one reign** (BO, from the chronicle; history.jsonl has no war field, so "peace" comes from `BO/state/history.jsonl`)
- Counts per season, turns 39-60:

| turn | peace | war/raid | unrest (ultimatum, plague, famine) | threat (betrayal, Hand call) | siege/storm |
|---|---|---|---|---|---|
| 39 | .87 | 0 | 1 | 1 | 0 |
| 40 | .87 | 1 | 0 | 2 | 0 |
| 41 | .93 | 0 | 2 | 1 | 0 |
| 42 | .93 | 0 | 2 | 1 | 0 |
| 43-45 | .87 | 0 | 0-1 | 0-1 | 0-1 |
| 46 | **.73** | 2 | 0 | 0 | 2 |
| 47-52 | .80-.93 | 0 | 0-1 | 0-1 | 0 |
| 53 | .93 | 1 | 0 | 0 | 1 (razed) |
| 54-55 | .93-.87 | 0 | 0-1 | 0 | 0 |
| 56 | .87 | 2 | 0 | 1 | 1 |
| 57 | **.73** | 0 | 2 | 0 | 0 |
| 58-60 | .80 | 0-1 | 0 | 0-1 | 0 |

- **Flat, with noise.** Each season has 0-4 events. Peace swings between .73 and .93 with no build. The "last act" was named at turn 57 ("The Broken Oath"), and nothing came of it by turn 60.

**D10. The longest stretch with nothing to do or watch**
- **About 17 minutes**, `S/friction/015.jpg` to `038.jpg` (12:44:30 to 13:01:41).
  - The same Stormwatch view with "THE FIRST ACT ENDS" and no Continue button.
  - The turn froze at 45 from frame 021 on.
  - Every panel was hidden; steps.log lines 42-99 have `panels: []`.
- **Without that stuck card, about 3.5 minutes:** `S/friction2/020.jpg` to `035.jpg`.
  - The turn was held at 45 by a waiting court.
  - The only cue was a "1" badge on Court.

## E. Repeats

**E11. Repeats in one reign** (BO)
- **Petitions by lord:** Ysolde Thornvale brought 7 of 13; Stormhold 2; the others 1 each (`BO/court.json`). By kind, all differ except arc ×3.
  - Both real reigns have identical petitions for turns 4-36 and identical claims. This is the shared baseline (`R/bridge/chronicles/the-grain-lords-mwac0hik/court.json`).
- **Lines, turns 39-60:**
  - "Ravens fly between House Wolfholt and House Goldcrest…" ×6, word for word
  - "X refuses Y's offer of his daughter's hand" ×7, one quote verbatim twice ("No, Edith is not my daughter…", turns 52 and 60)
  - Plague in a town ×6 (Goldrock ×2, Redsands ×2 identical)
  - "Barracks rise… House Thornvale is arming" ×6
  - "Treachery! … opens the gates" ×5
  - The Thornvale ultimatum ×2, identical
- **Captions in the friction frames:**
  - "The doors of the court close, and the realm moves again" at every court close
  - "The Feud of Stormwatch · Watch" ×3, "The Treason of Redmarch · Watch" ×3
  - In friction2, "The Feud of Redmarch" ×3 and "The Preaching of Colin Green" ×2
  - The Hand's war line, "Every season of war burns fields…", in 4 of the first 5 courts across runs

## F. Endings

**F12. How the last test reign ended, and what would make a second reign different**
- **The last ended test reigns** are council-test-mw9gkvpa and act-test-mw9e3r7x, both 1-minute reigns (`S/old-tests/<reign>/meta.json`).
  - Both ended "The appointed time has passed".
  - Both got title "The King the Golden", verdict "A steady hand. The realm endured and grew.", **score 2007**, end turn 40, peace .96.
  - Both epilogues read "You set out with three ambitions, and met none of them." Even the last chronicle lines match.
  - The most recent test, proof-film-mwag369q, is still running at turn 50.
- **What repeats:** the same seed, map, houses, baseline history, the turn-39 war matter and the petition deck.
- **What varies:**
  - Options and story (`meta.options`)
  - The draw of three ambitions
  - The arcs: friction got "Feud of Stormwatch", friction2 got "Durand Greyford / Colin Green"
  - The lords' names and lines (Eva vs Demelza Goldcrest)
- A second reign starts in the same place with the same first decision.

## G. Logs

**G13. Every ERROR and WARNING in game.log** (`S/friction/game.log`, `S/friction2/game.log`, `S/lordpics2/game.log`)
- **ERROR "NavigationPolygon convex partition failed".** 3 in friction, from `town_nav.gd:96 _bake`, called by `villagers.gd`.
- **WARNING "Navigation region synchronization had 1/2 edge error(s)".** 9 in friction, 2 in friction2, 3 in lordpics2.
- **ERROR "timeout waiting for fence"** (Metal, `rendering_device_driver_metal3.cpp:54`, from `autoplay.gd:143 _play`, the snap step). 10 in friction, 3 in lordpics2.
- **WARNING "This control can't grab focus".** 1 in friction2, 1 in lordpics2.
- **Visible breaks:**
  - The friction act card stuck for about 17 minutes with no Continue button, the realm held (ui.gd 2399-2423 should show Continue and close after 15 s; it did in friction2, `S/friction2/019.jpg`). The fence timeouts fall in the same window. The cause is unproven: **needs a film**.
  - The ground turned grey-blue during the act card (`S/friction/015.jpg`-`019i.jpg`), then green from `020.jpg`. This is likely the known winter-ground issue.
  - The navigation errors had no visible effect in the frames.

## M. Drift questions

**M1. Share of time with a panel open, and screen covered** (`steps.log`)
- **Share of steps with a panel open:**
  - friction 41% (31% after the intro), but the other 58% is the stuck act card
  - friction2 66% (59%)
  - lordpics2 57% (41%)
  - Across runs, court 60, town 40, houses 47, chronicle 47, ledger 4
- **Screen covered** (measured on 1600×920 frames):
  - **At rest:** about 28%. Heading, top bar, minimap and camera pad (`S/friction2/006.jpg`).
  - With Houses and Chronicle open: ~65% (`S/friction/004.jpg`).
  - With the court card too: ~85% (`003.jpg`).
  - With the ledger: ~90% (`S/friction2/037.jpg`).
  - UI.md §1 asks for "less than a tenth" at rest.

**M2. Every panel and board, the question it answers, and whether the world already shows it**
- **Heading (top left).** When am I, how long is left, what am I called, what's my aim? *World:* no. Season shows only in the ground tint.
- **Strip.** Treasury, income per season, peace, souls, tithe: is the realm OK? *World:* no.
- **Court card.** What must I decide now, and what does each answer cost? *World:* no (by design).
- **Houses board.** Who is strong, who is at war, who loves me? *World:* partly. The minimap colours territory, and banners show sieges; favour and war are not shown.
- **Chronicle.** What just happened? *World:* about a third (see C7).
- **Town card.** What is this town, and what can I order here? *World:* partly. Walls and buildings are visible; souls and granary are not.
- **Ledger.** Is the realm trending up or down, and who is richest? *World:* no.
- **Lore.** Who are these houses and people (`ui.gd:686`)? Not seen open: **needs a film**.
- **Minimap.** Where is everyone? *World:* yes, it is the world itself.
- **Watch chip and edge arrow.** Where is something happening? It points into the world.
- **Act card.** How am I doing so far? *World:* no.
- **Toasts.** What did my order do? *World:* no.

**M3. Decision kinds: where they're made, where the result shows, how fast**

| Kind | Made on | Result shows in | Speed |
|---|---|---|---|
| Hand's matter (war, cold house, ultimatum) | Court card | Text (toast, chronicle) and numbers (TRUCE, favour). Settle, peace and ward have no scene in code | Immediate |
| Petition (dilemma) | Court card, or free text | Text and favour numbers, then a rider, tribute, grain or ward going from Kingsmere to the seat | Text now; world ~2-3 seasons (deserters: turn 41 to 44) |
| Town decree (feast, gift, grain, build, alliance) | Town card | Numbers, plus a feast, convoy or rider in the world. A building finishes 2 seasons later (granary turn 40 to 42) as text | Seconds to ~80 s |
| Royal host, march | Town card | Muster scene and siege (world); house goes to WAR (numbers) | 1 season |
| Great council | Court card | Text only | **Needs a film** |
| Tithe | Strip ± buttons | Numbers | Each season |
| Ambitions and aims | None (passive) | "Done:" toast and the act card | Whenever met |

**M4. Ten consecutive chronicle lines from a real reign** (BO, turns 44-45, file order)
1. alliance "Ravens fly between Wolfholt and Goldcrest": **partly** (a rider between towns, if offered)
2. scheme "Ysolde Thornvale refuses Cecily Sunspire's offer…": **text only**
3. arc Ironreach Succession, "Cedric Kettle kneels…": **partly** (Watch goes to the town)
4. arc Pestilence of Redsands, "Sickness comes…": **partly**
5. betrayal "Cedric Marsh opens the gates of Sunfell": **shown** (handover)
6. city_built "Wolfholt founds Windcrag": **partly** (the town appears, no scene)
7. city_built "Goldcrest founds Lionhall": **partly**
8. year "The year 311 AC begins": **text only**
9. arc Treason of King's Mere, "Thornvale marches…": **partly** (the march itself is not staged)
10. arc Rise of Dick Thatcher, "taken as a squire": **partly**

Tally: 1 shown, 7 partly shown, 2 text only.

**M5. Which model the game matches today, and which it aims for**
- **Today it is closest to CK3: panels over a map backdrop.**
  - Decisions are made on cards.
  - Most results are numbers and chronicle text. The Houses board, chronicle and ledger carry the state.
  - Several boards are open at once, covering 65-90% of the screen (`S/friction/003.jpg`, `S/friction2/037.jpg`).
  - In the founder's reign, the chronicle was read far more than the world was watched.
  - Frostpunk-like touches: riders, convoys, sieges and buildings land in the towns (`S/friction/010.jpg`, `015.jpg`).
- **It aims for Frostpunk, with Kingdom Two Crowns leanings.**
  - GAME_DESIGN pillar 3: "Every decision is seen… the camera goes to the biggest result: banners rise and fall, funded buildings appear, carts and feasts arrive."
  - GAME_DESIGN pillar 6: "One card at a time."
  - UI.md §1: "The world is the interface… less than a tenth of the screen."
  - VISION.md:52 names Frostpunk's promises.
  - None of the docs aim at CK3's panel-heavy model. Kingdom Two Crowns' everything-in-the-world is the direction UI.md §1 points, but no doc commits to it.
