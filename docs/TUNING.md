# Tuning while you play

Each line: to change X, edit `<file>`: `<key>`. Bridge files take effect after the bridge restarts
(`launchctl kickstart -k gui/$(id -u)/com.realm.bridge`); view files at the game's next launch.
Switches (`--name`) go after `--` on the game's command line.

## Camera (Builder 2)
- How close the camera may come (the roof-height floor): `realm/data/camera.json`: `floor`.
- How far a town, a castle or a followed host is framed from: `realm/data/camera.json`: `go_to.*`.
- How many headings "go to" tries before settling for the least blocked: `realm/data/camera.json`: `sight_steps`.
- How close a roof, wall or tree may come before it dissolves out of the view (gone nearer than, whole from): `realm/data/camera.json`: `near_fade.buildings`, `near_fade.trees`.

## Castles (Builder 2)
- Where a seat's castle may stand when the first search fails (headings, rings, sizes, water allowed at its edge): `realm/data/towns.json`: `castle.*`.

## The director: threats and the shape of a reign (Builder 2)
- How quiet the realm must be, and for how long, before a threat rises: `bridge/data/director.json`: `quietBelow`, `quietSeasons`, `quietByAct` (by act).
- The breather after any crisis, in seasons: `bridge/data/director.json`: `breather`.
- When the last act's finale lands, as a share of the reign's clock: `bridge/data/director.json`: `finale.landAt`.
- Each threat's growth, words and the orders that answer it: `bridge/data/director.json`: `threats.<kind>.*`.
- How a too-comfortable King draws envy: `bridge/data/director.json`: `pushback.*`.

## The King's season: royal seals (Builder 2)
- On or off for reigns that don't say: `bridge/data/seals.json`: `on`. A new reign can set it with `options.seals`.
- Seals a season, and how many he can keep: `bridge/data/seals.json`: `perSeason`, `bank`, `bankLastAct`.
- How near a threat must be to top the "next thing" line: `bridge/data/next.json`: `soon`.
- The uses always on offer for a royal seal, after the urgent ones (a feast or a ward for the coldest house, the banners, walls, the levy): `bridge/data/next.json`: `standing`.

## Decrees and their prices (Builder 2)
- Each decree's price and words: `bridge/data/decrees.json`: `<decree>.cost`, `.label`.

## The court (Builder 2)
- One court flow (in, decide, see it, out): the switch `--court=one` (off until filmed and judged).
- How often the court sits and how many it hears, by stage of the reign: `bridge/data/court.json`: `stages`, `noClock`.
- What the reign's petitions setting (rare, often) shifts: `bridge/data/court.json`: `petitions`, `wantMin`, `wantMax`.
- How often the Hand may call the King in for a crisis between sittings: `bridge/data/court.json`: `handYear`.

## Event cards (Builder 2)
- On or off for reigns that don't say: `bridge/data/events.json`: `settings.on` (a reign can set `options.events`).
- How likely a card is each season, and in a breather: `bridge/data/events.json`: `settings.chance`, `settings.chanceInBreather`.
- How long before a card can come again: `bridge/data/events.json`: `settings.rest` (or a card's own `rest`).
- Which decks a breather may draw, and how much war and famine weigh in the build-up: `bridge/data/events.json`: `settings.breatherDecks`, `settings.boost`.
- A card's words, choices, costs and what doing nothing costs: `bridge/data/events.json`: `cards[]`.

## The realm's clock and the houses' favour (NPC perf; changeability audit)
- How long a season lasts, in every realm: `bridge/data/pace.json`: `season`. The view reads it from /world (`turnSeconds`); crops, snow, sieges and the recruits' drill follow it.
- How fast or slow the speed buttons may set a season: `bridge/data/pace.json`: `fastest`, `slowest`.
- What a house's favour means (loyal, sworn, steady, cooling): `bridge/data/favour.json`. The houses panel's words, the court, counsel, the reign's goal and the townsfolk's mood all follow it.
- When the treasury counts as thin (the Hand says so, the court may hear of it): `bridge/data/economy.json`: `thin`.

## Measuring (NPC perf)
- A frame-time run drawn as the game is played, not at film quality: `--perf` with `--shot`'s framing (`--perf=smooth` or `--perf=beautiful` to pick).

## The world's models (NPC perf; the asset catalogue)
- Which model draws each world component (houses, tavern, hall, barn, mill, castle, church, carts, stalls, fences, clutter, ruins), its true size, the parts the land supplies itself, how often each variant is picked: `realm/data/assets.json`: `components.<id>.variants`. Forests, crops, people and the built keeps and towers join as their placers move over.

## Battles (NPC perf)
- How hard a field battle is: blows a man takes, the chance a blow lands for each side, when the beaten side breaks and how long they fight: `realm/data/battle.json`: `hp`, `hit.*`, `breakAt`, `longest`.
- Knights' charges (how many passes, how fast): `realm/data/battle.json`: `charge.*`. Kicks, dodges and heavy blows that floor a man: `kickOdds`, `kickLands`, `dodge`, `floored`.

## Not yet in data (to move)
- Sound levels and the music's silences: literals in `realm/scripts/soundscape.gd` (`BEDS`, `STINGS`, `MUSIC_DB`, `CALM_GAP`).

## The opening, first ten minutes (Builder 1; `--opening=v2`)
- How long after the King lands in his realm the first court sits: `bridge/data/opening.json`: `firstCourtAfterLandingSec`.
- When it sits anyway if no landing is heard (the intro skipped): `bridge/data/opening.json`: `firstCourtWithoutLandingSec`.

## Townsfolk (Builder 1)
- Which towns' people have minds: `--limbo=none` (the old rules everywhere) or `--limbo=<ids>` (only those towns); default every town (`realm/scripts/town_life.gd`: `LIMBO_ALL`).
- Motion v3 (props follow the errand, rising through Getting_Up): `--motion=v3`; `--motion=v1` for the old motion.

## Every click answers (Builder 1; `--barks`)
- What a lord says when their sigil is clicked, by favour band; the annoyed lines; after how many clicks; the no-repeat window: `realm/data/barks.json`.

## The Hand's prompts in a first reign (Builder 1; `--opening=v2`)
- Each prompt's words, its moment and its delay: `realm/data/opening.json`: `prompts`.
