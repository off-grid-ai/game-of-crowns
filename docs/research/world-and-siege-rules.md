# The countryside, fire and siege, and decisions in the world: rules to judge renders by (2026-11-11)

Research for the builders and the supervisor. Three questions: what fills the land between towns, how a
burning or besieged town reads from a high camera, and how a ruler's decisions show on the map without UI.
Each part ends with rules, and the last section checks our current tunables against them.

Tags: **DESIGNER** (the studio said it), **HISTORY** (historians or reference works), **MANUAL** (official
guide or patch notes), **PLAYERS** (forums, guides), **KNOWN** (how the game plays, from my own knowledge, not
re-checked against a source this session), **ESTIMATE** (my judgement; tune on renders).

Our world is compressed (a game unit is about 8 m, and towns stand far closer than real ones), so each rule is
given two ways where it matters: real distances, and "per screen of road" at the mid zoom.

---

## 1. Roads and countryside between towns

### What the references do

- **The Witcher 3: something to see every 40 seconds.** The world team tested how long players stayed
  interested and set a rule that a player must meet something every 40 seconds: an animal, a campfire, soldiers
  on the road, a landmark. DESIGNER (via the noclip documentary):
  [TweakTown](https://www.tweaktown.com/news/59420/witcher-3s-40-second-rule-kept-players-engaged/index.html),
  [GameSpot](https://www.gamespot.com/articles/cd-projekt-red-explains-why-the-witcher-3s-open-wo/1100-6477549/).
- **And its limit.** One of its designers later said he overcrowded a map with points of interest. Density
  without rhythm reads as clutter. DESIGNER:
  [Nintendo Life](https://www.nintendolife.com/news/2022/07/witcher-3-dev-admits-he-overcrowded-one-map-with-too-many-points-of-interest).
- **Kingdom Come: real land, squeezed.** The map is a real 16 km² of Bohemia from satellite data; Warhorse cut
  the "boring parts" and moved the villages closer together so it felt populated. Rivers and hills stay where
  they really are. DESIGNER:
  [Warhorse interview](https://www.adventurecorner.de/articles/8334/interview-mit-warhorse-studios-zu-kingdom-come-deliverance-englische-version),
  [Welcome to Bohemia](https://news.xbox.com/en-us/2018/02/12/kingdom-come-deliverance-welcome-to-bohemia/).
  It holds about 13 named settlements, roughly one per 1.2 km², with about half of them keeping a tavern. KNOWN.
- **Manor Lords.** Fields are drawn as fenced strips beside the village and worked on a three-field rotation
  with a fallow; oxen plough them. The village sits in a ring of fields, then woods. KNOWN.
- **Anno 1800.** Each farm owns a block of field tiles; from above the countryside is a patchwork of single
  crops with windmills on the ridge behind the town. KNOWN, and visible in its store shots.

### What the real land looked like (HISTORY)

- A ploughing strip (a selion) was typically one furlong long and one chain wide: 201 m × 20 m, one acre. A
  holding strip was one to three of them side by side.
  [Selion](https://en.wikipedia.org/wiki/Selion),
  [Laxton, University of Nottingham](https://nottingham.ac.uk/manuscriptsandspecialcollections/learning/laxton/theme1/lands.aspx).
- Strips lay in blocks, also called furlongs, of up to forty; every strip in a block runs the same way, and
  neighbouring blocks run at different angles. A village had two or three great fields of several hundred acres
  each, with no hedges between strips. [Open-field system](https://en.wikipedia.org/wiki/Open-field_system).
- Domesday Book records about 6,000 water mills.
  [Mills in Domesday](https://windmillworld.com/watermills/domesday.htm). Against its roughly 13,000 places,
  that is about one mill for every two villages (my arithmetic; the place count is KNOWN, not re-checked). One
  local study puts it at one mill per 50 households, and notes mills often stood at valley crossings.
  [Hampshire Mills Group](https://hampshiremills.org/Newsletters/106%20Autumn%2014%20Newsletter/106%20Page%209.htm).

### Rules

**How often there is something to see**
1. At the mid zoom, every screen of road shows at least one roadside site and at most three. ESTIMATE, from
   the 40-second rule turned into a camera rule.
2. Rhythm, not a comb: a busy node (crossroads, bridge or ford) every 3–5 screens holding 2–4 sites together
   (inn, shrine, mill, toll), and one small site per screen between nodes. ESTIMATE, from the overcrowding
   lesson.
3. Never the same kind of site twice in a row along one road.

**Kinds of site and their mix (real spacing, then our ratio)**
4. Milestone or waystone: every mile (1.6 km). Wayside shrine or cross: every 2–3 km and at every crossroads.
   Farmstead or hamlet: every 1–2 km in farmed land. Village: every 3–5 km. Inn: at every market town and main
   crossroads, about a day's stage apart otherwise (15–25 km). HISTORY (general), ESTIMATE for the figures.
5. So per inn there should be at least 2–3 hamlets, about 3 shrines and 5 or more waystones. Kingdom Come's
   one tavern per two settlements is the dense end. ESTIMATE.
6. Other sites worth one each per road: woodcutters' or charcoal camp at a wood's edge, gallows at a crossroads
   near a seat, toll gate at a bridge or town approach, a ruined tower or burnt farm (a scar with a story), a
   shepherd's fold on open ground. KNOWN (Kingdom Come, The Witcher 3).

**Traffic**
7. Main road: 2–4 moving parties per screen by day; a track: 0–1. Double it within one screen of a town.
   ESTIMATE.
8. Mix by day: about half walkers and pedlars, a quarter carts, 15% riders, 10% herds or flocks. A convoy or a
   lord's party is rare enough to notice. At night only a torchlit patrol or a late rider. ESTIMATE.
9. Traffic has a purpose the player can read: carts go toward the market town in the morning and away at
   dusk; herds move between fold and pasture. KNOWN (Kingdom Come's routines).

**Fields round a town**
10. Rings: houses, then gardens and orchards behind the plots (to about 150 m), then the open fields (to about
    1 km), then meadow along the water, common pasture and woods at the edge. HISTORY.
11. Fields are bundles of parallel strips, each strip 8–10 times longer than wide (real: 201 × 20 m; shrink
    both by the world's scale, keep the ratio). A bundle holds 8–20 strips; neighbouring bundles lie at
    different angles. HISTORY.
12. Three great fields: one in winter grain (gold by late summer), one in spring crop (green), one fallow
    (brown-green, with sheep on it). No hedges between strips. HISTORY.
13. Hedges and fences belong to the closes by the village, orchards and road edges only. One orchard per 5–10
    houses, 10–30 trees in rows. ESTIMATE.
14. Farmed land covers 50–70% of the ground within a screen of a lowland town; the rest is meadow, pasture and
    wood. ESTIMATE.

**Rivers, bridges and mills**
15. A town sits at a crossing. Where a road meets a river there is a bridge (main road) or a ford (track),
    never a road that simply ends at water.
16. A water mill stands within 50–300 m of the bridge, on a side channel with a weir, on about half the
    crossings: one mill per two villages. HISTORY (ratio), ESTIMATE (distance).
17. Meadow follows both banks; willows or alders line the bank every 10–20 m. ESTIMATE.

---

## 2. Fire and siege reads

### What the references do

- **Total War.** Smoke is the far read: separate dark columns, one per burning building, leaning one way with
  the wind; flames are small and bright on roof lines; the ruin outlasts the fire for turns on the campaign
  map. BY EYE on Attila and Three Kingdoms store shots (see `fire-smoke-research.md` in the session notes).
- **Total War: Warhammer III sieges.** The rework's aim was to make the fight interesting after the wall
  falls: bigger settlement maps, capture points inside, and towers and barricades the defender builds.
  DESIGNER: [How sieges work](https://www.totalwar.com/?p=15524); PRESS:
  [PC Gamer](https://www.pcgamer.com/total-war-warhammers-unloved-sieges-are-being-reworked-in-the-third-game).
  Any unit can batter a gate down, which critics call the weak point: a wall that falls too easily stops being
  a wall. PRESS: [PC Gamer](https://www.pcgamer.com/games/strategy/total-war-warhammer-3-siege-rework).
- **Total War walls.** A section goes whole, then damaged (cracks, lost battlements), then breached (a rubble
  ramp troops can cross). Gates go whole, damaged, down. Each section and gate has its own health. KNOWN.
- **Age of Empires II and IV.** A damaged building shows fire that grows in steps as its health falls, so its
  state reads without a health bar. KNOWN. In IV, stone walls ignore torches and swords; only siege engines
  hurt them, and rams are built in the field by infantry. PLAYERS/MANUAL:
  [stone walls guide](https://www.gamepressure.com/age-of-empires-iv/relics-what-are-they/zcf05a),
  [battering ram](https://ageofempires.fandom.com/wiki/Battering_Ram_(Age_of_Empires_IV)).
- **Stronghold.** A wall loses height hit by hit until men can climb the stump; fire jumps from building to
  building and the player watches it travel. KNOWN. Its remake's players list uncontrolled fire spread among
  their top complaints (the casebook's review data): spread must be readable and stoppable.
- **Manor Lords.** Raiders march in and torch houses; fire spreads house to house; villagers run to wells but
  a building that burns is left as rubble. PLAYERS:
  [Dot Esports](https://dotesports.com/manor-lords/news/how-to-put-out-fires-in-manor-lords).

### Rules

**Fire: the far read**
1. One smoke column per burning building, at most 6 per town. Each stands at least 3 × the house's height and
   is visible from the farthest zoom at which the town itself is drawn. ESTIMATE, from Attila.
2. Smoke is dark and lit by the sun (near-black brown at the base, grey-brown at the top), all columns leaning
   one way. In daylight the contrast is dark smoke against sky and land; glow belongs to night. BY EYE.
3. Flames stay on the building's silhouette: on the ridge, out of windows and the door. At peak they are
   0.5–1 × the house's height and never hide the house. ESTIMATE.
4. Buildings catch one at a time, 3–12 s apart, never two neighbours first. A sack burns about 40% of houses,
   a razing 70–100%. ESTIMATE.

**Fire: stages and how long to hold each**
5. Four stages, each a visible change. Catching (smoke first, small flames): about 5 s. Burning (full flames,
   embers, tall column): 25–50 s. Collapse (roof falls in, a burst of sparks, flames drop): 2–3 s. Smouldering
   (thin grey wisp, glowing cracks): 20 s or more, then out. ESTIMATE.
6. The ruin stays: charred shell and ground scorch for 3–5 seasons, then weathered grey until rebuilt. One
   burnt house in three has lost its roof. ESTIMATE.
7. Damage short of fire shows too: a building at half health has broken roof patches and a little smoke
   (the Age of Empires ladder). KNOWN.

**Walls: breach stages**
8. A wall section shows four states. Whole. Cracked: a dark crack band and dust, battlements chipped.
   Crumbling: top courses gone, rubble at the foot. Breached: a gap at least two men wide with a rubble ramp.
   KNOWN (Total War, Stronghold).
9. Every blow pays out at once: a dust puff for 1–2 s, stones seen falling, a sound. No blow lands with
   nothing to see. ESTIMATE.
10. Hold each state for at least 3 blows or 8 s near the camera, so the player sees the wall failing in steps.
    From whole to breach under steady bombardment: 30–60 s on screen. Away from the camera, jump to the
    state. ESTIMATE.
11. Only engines breach stone; men use ladders, towers or the gate. A gate is its own piece with its own
    stages (whole, splintered, down). KNOWN (Age of Empires IV, Total War).
12. The breach changes the fight: attackers stream to it, defenders mass behind it. If nobody reacts to the
    gap, it does not read as a breach. DESIGNER lesson from the Warhammer III rework.

**The siege as a whole, from the high camera**
13. Three rings read at a glance: the town and its wall, a band of open ground with engines and assault
    parties, and the besiegers' camp of tents and cook fires behind it. KNOWN (Total War, Mount & Blade).
14. The besieger's banners stand over the camp, the holder's over the gate; when the town falls the gate's
    banner changes first.
15. A siege that is starving the town, not storming it, looks different: no engines firing, thin smoke from
    the town, the camp settled with more fires. ESTIMATE.

---

## 3. Decisions shown in the world

### What the references do

- **Frostpunk.** Laws become places: sign a law and its building appears in the city (a public house, a
  fighting pit, a guard station, a propaganda centre). When discontent is high, people gather and protest in
  front of the generator; the two bars only confirm what the street shows. KNOWN. The studio on how discontent
  and hope came about: DESIGNER:
  [PC Gamer](https://www.pcgamer.com/frostpunk-developers-on-hope-misery-and-the-ultimately-terrifying-book-of-laws).
  A critic's caution: when the numbers move and the city doesn't, the system feels hollow. PRESS:
  [Slant](https://www.slantmagazine.com/games/review/frostpunk).
- **Crusader Kings III.** A feast, hunt or tournament is a camp of tents on the map at the place it is held
  (visible in its Tours and Tournaments store shots). Raised levies gather at a rally flag. A revolt is an
  army of peasants standing on the county. KNOWN.
- **Manor Lords.** Calling the militia empties the town: men drop their tools, run to the rally point and form
  up, and the workshops stand idle. Homeless families camp in tents by the market. KNOWN.
- **Tropico.** Protesters stand with placards outside the building they are angry about; shacks spread where
  housing is short; rebels attack named buildings. KNOWN; rebels:
  [Tropico 4](https://en.wikipedia.org/wiki/Tropico_4).
- **Total War.** Low public order ends as a rebel army beside the town; a garrison is a figure standing on the
  settlement; a sacked town smokes on the campaign map for turns. KNOWN.

### Rules

1. **Three cues at three sizes** for every standing state: a silhouette cue (the banner's state), a crowd cue
   (where people stand and how many) and a prop or effect cue (smoke, barred shops, lanterns). Sound is a
   fourth. A state with one cue is missed. ESTIMATE, from Frostpunk and Tropico.
2. **The crowd's shape is the signal.** Unrest: a tight ring round a speaker. Levy: a queue at a table.
   Garrison: a formed block at the gate. Feast: people scattered round fires and tables. Four shapes, never
   two alike. ESTIMATE.
3. **Enough people to read from roof height:** at least 12 figures for a crowd, 8 for a queue, 12 in a block.
   ESTIMATE.
4. **Colour temperature separates good from bad.** Feast: warm light, bright cloth, lanterns. Unrest: cold,
   darker, grey smoke, shut shutters. A viewer should tell them apart with the picture blurred. ESTIMATE.
5. **Banners carry allegiance and mood.** Flying whole: content. Lowered or torn: cold or angry. The royal
   standard at a gate: the King's men are here. BY EYE (art target 07 and 08).
6. **States escalate in steps** the player can count: cold (crowd, lowered banner, a few shops shut), angry
   (bigger crowd, guards doubled, smoke, a burnt cart), risen (a host under its own banner). Each step adds
   cues; none replaces the last. KNOWN (Total War's order ladder).
7. **It stays while it is true and leaves a mark after.** A state fades in over 1–2 s when the cause begins,
   holds as long as the realm says so, and leaves one mark for a season or two (the burnt cart, trampled
   ground, feast litter). ESTIMATE.
8. **It is at the place, and it survives zooming out.** The cue stands where the decision landed (the gate,
   the square). At realm zoom it collapses to one readable thing on the town: a lowered banner, a smoke
   plume, a lantern glow at night, a standard at the gate. KNOWN (Total War's campaign map).
9. **A decision is seen leaving and arriving.** Grain goes as carts on the road; a levy marches out of the
   gate; a garrison marches in. The journey is the proof the order was given. KNOWN (Manor Lords' rally).
10. **Work stops when people are called away.** A levy or a riot leaves workshops shut and fields empty for as
    long as it lasts. KNOWN (Manor Lords).

---

## 4. Our current tunables against the rules

Read from `realm/data/roadside.json`, `fire.json`, `walls.json` and `decisions.json` as committed today. I have
not seen renders; these are what to look at first.

| Rule | Ours now | Suggestion |
|---|---|---|
| 1.5 Hamlets per inn | hamlet every 15 units, inn every 18: about 1.2 hamlets per inn | 2–3 hamlets per inn: hamlets every 8–10 units, or inns every 25–30 |
| 1.4 Waystones | every 4.5 units (about 36 m) | fine as a rhythm marker; check it doesn't read as a fence at mid zoom |
| 1.7 Traffic | at most 4 parties within 20 units, a new one every 6–12 s | matches 2–4 per screen; add the doubling near towns |
| 1.8 Traffic mix | herds 35% of spawns | herds nearer 10%; add carts and riders by share |
| 2.1 Smoke column height | life 7 s × rise 0.12–0.22 units/s: about 1.2 units, or 9–10 m | at least 3 × house height: about 2.5–3.5 units (longer life or faster rise) |
| 2.1 Smoke seen from far | drawn to 45 units | draw the columns as far as the town is drawn |
| 2.4 Share burning in a sack | 0.4 | matches |
| 2.5 Smoulder | glow fades in 20 s | matches; confirm a thin wisp remains after |
| 2.8 Wall states | 8 sections, wear per section, crack band and ragged breach in data | confirm four distinct looks per section on the render |
| 2.10 Hold per state | a blow every 2.6 s | 3 blows per state gives about 8 s: matches if wear steps are sized so |
| 3.3 Unrest crowd | 6 (cold), 12 (angry) | 12 and 24 |
| 3.3 Levy queue | 6 recruits | 8–12 |
| 3.3 Garrison | 6 guards, 2 standards | a block of 12 or more with the 2 standards |
| 3.1 Feast cues | 10 lanterns, 4 banners | add scattered people at tables and fires as the crowd cue |

## Caveats

- Items tagged KNOWN come from how these games play, not from a page read this session; the Frostpunk protest
  and Age of Empires fire-step details most need a check before quoting.
- I found no developer source for wall-breach stage timings in any of the games; every duration here is an
  estimate to tune on the render.
- The Domesday place count and the spacing figures for inns, shrines and villages are general history, not
  taken from one cited study.
