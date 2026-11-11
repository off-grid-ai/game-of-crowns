# Tuning while you play

Each line: to change X, edit `<file>`: `<key>`. Bridge files take effect after the bridge restarts
(`launchctl kickstart -k gui/$(id -u)/com.realm.bridge`); view files at the game's next launch.
Switches (`--name`) go after `--` on the game's command line.

## Camera (Builder 2)
- How close the camera may come (the roof-height floor): `realm/data/camera.json`: `floor`.
- How far a town, a castle or a followed host is framed from: `realm/data/camera.json`: `go_to.*`.
- How many headings "go to" tries before settling for the least blocked: `realm/data/camera.json`: `sight_steps`.
- How close a roof, wall or tree may come before it dissolves out of the view (gone nearer than, whole from): `realm/data/camera.json`: `near_fade.buildings`, `near_fade.trees`, `near_fade.castle` (a castle's walls, sooner).
- How a still or film frames a town's square (`--city=`): from the side away from its castle, turned a little, the square set right of the town card: `realm/data/camera.json`: `town_shot.*`.
- Where the flat atlas comes in over the 3D land (only just before the painted overview takes over at distance 60; below it the 3D land is all there is): `realm/data/camera.json`: `map.atlas_from`, `map.atlas_to`, `map.atlas_most`.
- How far from the lens a town's houses, halls and castle still draw (so a town stays a town at mid zoom; Godot's detail levels lighten them): `realm/data/camera.json`: `map.reach.*` (clutter, small, house, great, castle).

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

## The house colours and the target town (art target 01-town, 02-realm)
- The political map's wash by zoom: `realm/data/look.json`: `politics.wash_near`, `wash_far`, and `map_from` / `map_to` (the camera's height over the ground where the wash, band and stripes come in; below it the land stays natural and only the border line shows); `--politics=on`.
- The same `map_from` / `map_to` hold back the plain (politics off) far wash of a house's colour, so the land round a town stays painted ground at mid zoom.
- How soon the sea's swell settles into a flat sheen away from the lens (further out it aliased into stripes): `realm/data/look.json`: `sea.waves_fade`.
- Where a house's colour sits on its buildings: `realm/data/look.json`: `team.materials` (roof tiles, shutters `MI_Shutter`, timber `MI_WoodTrim`, banners), `team.ranks` (which components are ordinary houses), `team.paint.ordinary_share` (an ordinary house's share of the colour on its trims and shutters), `team.paint.saturation`, `team.paint.warm` (the colour toned to painted reds); `--team=on`.
- Each house's roof (thatch, terracotta, dark tile or the house's colour), for cottages and townhouses: `realm/data/look.json`: `team.roofs.cottage`, `team.roofs.town` (shares, in that order), `team.roofs.thatch`, `team.roofs.dark_tile` (colours). The castle's and hall's roofs always wear the house's colour. How the thatch reads (straw bundles down the slope, each roof its own age, a ragged darker eave): `team.roofs.thatch_old` (the weathered colour) and `team.roofs.straw.*` (`fibre`, `clump`, `eave_dark`, `eave_band`, `storey`).
- The woods in autumn, per kit tree: `realm/data/assets.json`: `woods.kit.seasons` (a tint per model file per season), `woods.kit.leaf_texture` (a leaf texture swapped by material name).
- The kit castle's gate: how high the portcullis hangs: `realm/data/assets.json`: `components.castle.kit[].spec.gate_portcullis` (metres; 2.4).
- How many houses a town raises, and the crown's seat packed tighter: `realm/data/towns.json`: `density.*`, `density.crown.*`.
- Towns along their roads in burgage plots instead of rings: `realm/data/towns.json`: `layout` (`rings` today, `plots`); `--towns=plots` or `--towns=rings` for one run. The plots' depth of yard, gap between houses, lanes (how often, how long, how many by size, the most), how much a street wanders, how far the plots run, the ring of houses round the square, the yards' fence: `plots.*`; the crown's seat's own, and how many more houses it raises on plots: `plots.crown.*`. The yards' light fence model: `realm/data/assets.json`: `components.fence_yard`. How near something already standing (the square, the castle, a landmark, a house) a house must be to stand, so a town grows out from its heart with one clear edge and no house alone out on the fields: `plots.near` (0 turns it off). The crown's seat packed close round its castle and square (art target 01-town): `plots.crown.edge_more`, `lane_every`, `lane_length`, `yard`, and `wander` (lower: straighter streets, houses squarer to each other). A plot that would stand on another street or on a house already cut slides along its own street until it is clear (town_plots.gd), so corners hold a house instead of a gap. Each plotted town prints `CHECK town plots:` with its plots cut, houses stood and why the rest were turned away (another street, another house, the realm's road, crowded, water or a cliff, alone: never reached by the town); more lanes or `edge_more` when it falls short.
- The crown's market at midday (more stalls, buyers per stall, a smith, carters, porters, how many the square and each of its places hold, how many of its people are out, how many keep a city trade instead of farming): `realm/data/towns.json`: `market.crown.*`. Other towns keep the square's budget by size.

## The woods (NPC perf; art direction fix 4)
- Kit castles and kit houses: `realm/data/towns.json`: `castles` and `houses` (`pack`, the downloaded models, today; `kit`, raised from the Quaternius Medieval Village kit by `castle_builder.gd` and `house_builder.gd`); `--castles=kit` or `--houses=kit` for one run. Each castle's size by the seat's rank (bailey cells, wall, keep and tower storeys, side towers, banner size) and each kit house's cells, floors, style and chance of a chimney (the hall on the square: 3 by 5 cells, 6 by 10 m, always a chimney): `realm/data/assets.json`: `components.<castle|hall|house_rich|house_poor|tavern>.kit`. Kit banners take the holder's colour: `realm/data/look.json`: `team.materials.MI_Banner`.
- Kit house tiers (hovel, cottage, townhouse, merchant, burgher, manor; the inn, alehouse, guild hall and the trades' buildings): `realm/data/assets.json`: `house_kit.tiers.<tier>` (cells across and deep, floors, gable or eaves to the street, roof coverings and wall mixes by weight, washes, jetty, dormers, chimneys, windows, shutters, shop front, arcade, extras: porch, sign, lean-to, outside stair, balcony, window boxes, vines; props baked in), `house_kit.washes`, `house_kit.roof_tints`, `house_kit.pitch`, `house_kit.jetty_m`; how many models of each tier: `components.<house_hovel|house_poor|house_rich|house_merchant|house_burgher|house_manor|house_corner|tavern|alehouse|guild_hall>.kit[].count`. Shown with `--houses=kit`.
- Which house stands where (wealth from the square outward, corners, no two neighbours alike): `realm/data/towns.json`: `tiers` (`ladder`, `wealth.square|main|lane` near and far, `min_size`, `seat_size`, `manor_most`, `corner`, `corner_share`, `corner_up`).
- A town's working buildings (guild hall, armoury, forge, stables, alehouse, watermill, windmill, granary, barn, tannery, dyer) and where each stands: `realm/data/towns.json`: `trades.list` (`needs`: the bridge's buildings that call for it, `min_size`, `seat`, `where`, `t`); their models: `realm/data/assets.json`: `components.<id>` (`variants`, or `ai` with `towns.json trade_art` `ai` / `--trade_art=ai`); where their people work: `components.<id>.work` and `hearth`.
- Which trees the woods grow: `realm/data/assets.json`: `woods.set` (`pack`, the realistic packs, today; `kit`, Quaternius' painted trees); `--trees=kit` or `--trees=pack` for one run.
- The kit's trees, their true heights and how tall young trees and saplings stand: `realm/data/assets.json`: `woods.kit.*`.
- How tall the realistic pack's trees stand (a share of their true 13-31 m): `realm/data/assets.json`: `woods.pack_scale`. The grown kit trees' allowed heights (one to two houses; `tools/scale_check.gd` fails outside it): `woods.tree_range`.

## The ground (NPC perf; art direction fix 5)
- Painted ground on or off: `realm/data/ground.json`: `painted` (or `--ground=painted` / `--ground=photo` for one run). Each layer's colour and how broad its pattern: `layers.<layer>.tint`, `.scale`; the grass's broad colour patches: `macro`.
- The coast: how far the beach runs above the waterline, and the surf at the shore: `realm/data/ground.json`: `beach.top`, `surf`.
- How far out the land keeps its fine shape (Terrain3D's rings round the lens; too coarse and a lake's low shore sinks under the water at the mid zoom): `realm/data/ground.json`: `mesh.size`, `mesh.lods`.
- From what distance the sea's colour stops reading the depth to its bed (nearer shows clear shallows, but the bed's coarser rings show as seams further out): `realm/data/look.json`: `sea.depth_fade`.
- Rivers' ends and colour (how far a mouth sinks under the sea or a lake and over how many points, how a spring or a joining river narrows, the water's shallow and deep colour): `realm/data/ground.json`: `rivers.*`.
- Roads: every road's, street's and track's earth colour and the King's road's shade (`roads.tint`, `roads.kingsShade`), how a track frays into the grass and how dark its ruts (`roads.edge.*`), the painted look's grass verge (`roads.verge`, `roads.vergeTint`): `realm/data/ground.json`. The farm hedges' bush: `realm/data/assets.json`: `hedge` (photo), `hedge_painted`.
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

## Life along the roads (off until judged: `on` in the file, or `--roadside=on` / `--roadside=off`)
- Which roads get it, how far from towns, farms and roads.gd's own inns it keeps: `realm/data/roadside.json`: `roads`, `town_clear`, `farm_room`, `inn_room`.
- How often each kind stands along a road (inns a day's ride apart and at crossroads, hamlets, woodcutters in the woods, shrines, waystones), how far off the road and how much room each takes: `realm/data/roadside.json`: `kinds.<kind>.first`, `every`, `gap`, `chance`, `out`, `room`, `tiles`.
- What each site is made of (catalogue pieces, where and how turned), its smoke, yard fire and the inn's sign and names: `realm/data/roadside.json`: `kinds.<kind>.pieces`, `smoke`, `fire`, `sign`; a hamlet's cottages, ring and fields: `kinds.hamlet.*`; bridges (how narrow a river gets one, the span) and fords: `kinds.bridge`, `kinds.ford`; the mill on a stream: `kinds.mill`; toll gates out of castle towns: `kinds.toll`; the gallows by the crown's seat: `kinds.gallows`.
- Who is about at each (horses, drinkers, soldiers, stablehand, farmers, woodcutters, pilgrims, toll guards, beasts), their moves, how near the camera they appear and how often they change what they do: `realm/data/roadside.json`: `kinds.<kind>.life`, `life.*`, `animals`.
- Travellers and herds to and from inns, hamlets, mills and camps (how often, how many, herd beasts and pace): `realm/data/roadside.json`: `traffic.*`. Models still missing, for image-to-3D: `candidates`. Check: `arch -arm64 godot --headless --path realm -s res://tools/roadside_probe.gd`.

## Damage to towns: walls and burnt houses (Builder 1; the bridge owns it)
- How fast besiegers batter a wall section, when it shows cracked and breached, how fast it's mended, how much a sack or razing burns and how fast it's rebuilt, how many sections: `bridge/data/damage.json`.
- Stone walls that break stone by stone (on with `walls: "stone"` or `--walls=stone`): the stones' sizes, joints, tint and which painted blocks they show (`block`, `bricks`), the merlons, how stones fall (gravity, weight, friction, how much of a stone must stay carried before it slumps, how long they take to settle), how a section's wear opens the breach (`breach`: widths, how deep at what wear, the cracked band, what gap counts as a way through), a town ring's height and sections, the catapult blows that bring doomed stones down (`strike`: how often, how hard, how wide, how many before the rest gives way), how near the camera the fall is simulated (`sim_radius`, world units), the dust, and the test demo: `realm/data/walls.json`.

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

## The massed army (the army spike, `--army-spike=<men>`)
- Men to a regiment, the frontages a regiment may stand in (lines and columns), a man's height, the spacing between men and between regiments, how loosely each man stands (off his mark, turned, taller or shorter), how much open ground the host needs and how far from the seat, the share still marching in (from how far, how fast), the share standing at the ready, the paint's brightness under the sun, which palette cells take the house colour and how much (`team.rects`: the cloth fully, the breastplate as painted steel), and how far round a regiment no tree, road or track may stand (`muster.keepOff`): `realm/data/army.json`.

## Feet on the ground (on by default, `--feet=off` for the clips' own keys)
- How each move is planted on its feet (the reference skeleton, poses measured per clip, the most a clip or body is raised, what counts as sat, lying or kneeling, the moves sat on a seat that are left alone, the moves a body's own legs are measured in): `realm/data/people.json`: `feet.*`. Check it with `arch -arm64 godot --headless --path realm -s res://tools/feet_check.gd`.
- How often a road traveller's path takes its height from the ground: `realm/data/people.json`: `travel.groundStep`.

## The square's things (props, the well)
- Which model draws the square's well (a stone curb, posts, a roof, the winch and bucket): `realm/data/assets.json`: `well` (its true height in metres: `height`).
- How far a prop on the square sits into the ground below the lowest of its middle and corners: `realm/data/towns.json`: `props.sink`.
- How steep a farmstead's field may be before it isn't laid: `realm/data/towns.json`: `farms.fieldRise`. A hay bale's and the market stall's true size: `realm/data/assets.json`: `haystack`, `market_stall` (`length`, metres).

## Borders on the ground (the political map)
- From what camera height the border line fades in and by what height it is whole, how wide its soft painted band, and how much of it is the fine line: `realm/data/look.json`: `politics.line_from`, `line_to`, `line_soft`, `line_crisp`.

## Life at the working buildings (on by default, `--works=off`)
- Where each trade's work happens when the town agent lists a building with no spots of its own (the anvil, bellows, trough, the armoury's rack, the paddock's middle and gate, the mill's door and sacks, the granary's queue, the inn's benches, rail, yard and windows), other names for the trades, and which building stands in for a missing one (a granary bakes where there's no bakery): `realm/data/works.json`: `spots`, `aliases`, `fallback`. A model can carry its own spots: `realm/data/assets.json`: `components.<name>.work`.
- How many work at each building in peace, war, a levy, a low granary, hunger, a feast and good times (smiths, horses, bench drinkers, revellers, travellers, the granary queue, the levy at the armoury, the crier's listeners, millers, tanners), and which state wins: `realm/data/works.json`: `counts`, `priority`.
- Which townsfolk take a trade (apprentice, groom, carters) and how many: `realm/data/works.json`: `jobs`.
- How a town's state shifts what they choose (the forge works double in war, the granary grumbles when low, the inn's yard drinks at a feast): `realm/data/works.json`: `weights`.
- The forge's glow and sparks, the mills' turning parts and speed, the inn's lit windows, the working day's hours, the crier's place, the horses' grazing and leading, the stacks at the rack, mill and granary: `realm/data/works.json`: `forge`, `mill`, `inn`, `day`, `crier`, `paddock`, `stock`.
- The roadside's people (inns, hamlets, camps, shrines, tolls) now think on the same minds: each `life` row's `post` in `realm/data/roadside.json` (no post: the old clip timer). Check it all with `tools/mind_probe.gd` and `tools/works_probe.gd`.
