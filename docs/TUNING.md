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

## Worn paths (NPC perf; finesse catalogue D3)
- Paths worn where people walk, growing back where they don't: `realm/data/ground.json`: `wear.on` (or `--wear=on`); how fast it wears and grows back, how often it's stamped and drawn, the bare earth's colour: `wear.*`.

## Sizes (NPC perf)
- How tall each world component should stand, in metres: `realm/data/assets.json`: `components.<id>.heightRange`; `realm/tools/scale_check.gd` fails any model outside it. A model whose length misleads is scaled by its true height instead: a variant's `height`.

## The woods (NPC perf; art direction fix 4)
- Kit castles and kit houses: `realm/data/towns.json`: `castles` and `houses` (`pack`, the downloaded models, today; `kit`, raised from the Quaternius Medieval Village kit by `castle_builder.gd` and `house_builder.gd`); `--castles=kit` or `--houses=kit` for one run. Each castle's size by the seat's rank (bailey cells, wall, keep and tower storeys, side towers, banner size) and each kit house's cells, floors and style: `realm/data/assets.json`: `components.<castle|hall|house_rich|house_poor|tavern>.kit`. Kit banners take the holder's colour: `realm/data/look.json`: `team.materials.MI_Banner`.
- Which trees the woods grow: `realm/data/assets.json`: `woods.set` (`pack`, the realistic packs, today; `kit`, Quaternius' painted trees); `--trees=kit` or `--trees=pack` for one run.
- The kit's trees, their true heights and how tall young trees and saplings stand: `realm/data/assets.json`: `woods.kit.*`.

## The ground (NPC perf; art direction fix 5)
- Painted ground on or off: `realm/data/ground.json`: `painted` (or `--ground=painted` / `--ground=photo` for one run). Each layer's colour and how broad its pattern: `layers.<layer>.tint`, `.scale`; the grass's broad colour patches: `macro`.
- The coast: how far the beach runs above the waterline, and the surf at the shore: `realm/data/ground.json`: `beach.top`, `surf`.
- Roads: the grass verge's width and colour, the track's tint: `realm/data/ground.json`: `roads.*`. The farm hedges' bush: `realm/data/assets.json`: `hedge` (photo), `hedge_painted`.
- Which painted texture each ground layer draws (the CC0 watercolor set, packed by `realm/tools/pack_painted_ground.gd`): `realm/data/ground.json`: `layers.<layer>.painting` (rerun the tool and `--import` after changing one).

## Battles (NPC perf)
- How hard a field battle is: blows a man takes, the chance a blow lands for each side, when the beaten side breaks and how long they fight: `realm/data/battle.json`: `hp`, `hit.*`, `breakAt`, `longest`.
- Knights' charges (how many passes, how fast): `realm/data/battle.json`: `charge.*`. Kicks, dodges and heavy blows that floor a man: `kickOdds`, `kickLands`, `dodge`, `floored`.

## Not yet in data (to move)
- Sound levels and the music's silences: literals in `realm/scripts/soundscape.gd` (`BEDS`, `STINGS`, `MUSIC_DB`, `CALM_GAP`).

## The opening, first ten minutes (Builder 1; the default; `--opening=v1` for the old one)
- How long after the King lands in his realm the first court sits: `bridge/data/opening.json`: `firstCourtAfterLandingSec`.
- When it sits anyway if no landing is heard (the intro skipped): `bridge/data/opening.json`: `firstCourtWithoutLandingSec`.

## Townsfolk (Builder 1)
- Which towns' people have minds: `--limbo=none` (the old rules everywhere) or `--limbo=<ids>` (only those towns); default every town (`realm/scripts/town_life.gd`: `LIMBO_ALL`).
- Motion: v3 is the default (props follow the errand, rising through Getting_Up); `--motion=v1` the old motion.

## Every click answers (Builder 1; on by default, `--barks=off`)
- What a lord says when their sigil is clicked, by favour band; the annoyed lines; after how many clicks; the no-repeat window: `realm/data/barks.json`.

## The Hand's prompts in a first reign (Builder 1; the opening v2, the default)
- Each prompt's words, its moment and its delay: `realm/data/opening.json`: `prompts`.
- Juice on or off (the seal at the click, the treasury counted down, results at the town, music by tension): `realm/data/juice.json`: `on` (or `--juice=on`).
- How long the treasury counts to its new sum, how big the spent seal swells: `realm/data/juice.json`: `coins_seconds`, `seal_punch`.
- How tense the realm must be before the music turns dark, and calm before it settles: `realm/data/juice.json`: `music_tension_above`, `music_calm_below`.
- Court results' wordings, and the local model adding more (on, how many per result): `bridge/data/results.json` (and `reword`).
- Bannermen's surnames, dealt fresh each real reign: `bridge/data/surnames.json`.
- One court matter at a time, and how likely a season brings one by the stage of the reign: `bridge/data/court.json`: `one`.
- The herald: on or off, how many notices wait, how long each is read, its dry voices: `realm/data/herald.json`.
- How often a royal seal comes (0.5: every other season): `bridge/data/seals.json`: `perSeason`.
- What the tithe brings the crown, per town size: `bridge/data/economy.json`: `tithe.perSize`.
- How often event cards come, and never in a breather (chanceInBreather 0): `bridge/data/events.json`: `settings.chance`, `settings.chanceInBreather`.

## The crowd thinks out loud (Builder 1; on by default, view `--thoughts=off`)
- What a town says after a ruling (by who it helped or hurt), when hungry, besieged or levied; how many thoughts a town shows; Omni's prompt; on/off: `bridge/data/thoughts.json`.
- How near the camera must be to see a town's talk, and how often it changes: `realm/data/thoughts.json`: `near`, `cycle_sec`.

## Who's home and the hearths (Builder 1; on by default, `--hearths=off`)
- Chimney smoke only where someone's home: how often it's checked, how near a person must be to their door: `realm/data/hearths.json`.

## Damage to towns: walls and burnt houses (Builder 1; the bridge owns it)
- How fast besiegers batter a wall section, when it shows cracked and breached, how fast it's mended, how much a sack or razing burns and how fast it's rebuilt, how many sections: `bridge/data/damage.json`.

## Fire (lead; behind `--fire=v2`, `--fire=v1` for the old puffs)
- On by default or not: `realm/data/fire.json`: `on`.
- The flames on a burning roof (how many, how big, how tall for their width, how fast they rise, how far they lean downwind, how fine their licks): `realm/data/fire.json`: `flames.*`; the smaller ones out of the front: `front.*`.
- The flames' three colours (core, body, edge) and their brightness: `realm/data/fire.json`: `colours.*`.
- Embers, and the smoke column (how dark, how big, how high, how far it drifts on the wind): `realm/data/fire.json`: `embers.*`, `smoke.*`.
- The fire's light on the street: `realm/data/fire.json`: `light_energy`, `light_range`.
- How much of a burnt house's roof falls in, how long its char glows: `realm/data/fire.json`: `char.collapse`, `char.glow_out`; the scorch under it: `scorch_size`.
- Which houses stay burnt and for how long: the bridge's damage fact, `bridge/data/damage.json` (above). How many catch when a sack plays before that fact arrives: `realm/data/fire.json`: `share_sack`, `share_razed`.
- Yard fires: `realm/data/fire.json`: `hearth.*`.
- The wind everything leans with: the weather's (`realm/scripts/weather_fx.gd`: `LOOKS.*.wind`, `PREVAILING_FROM`, `WIND_FULL`).
