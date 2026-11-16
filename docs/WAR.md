# War: the biggest decision in the game

Mac, 2026-11-16: "going to war is a big thing and should be treated as such", "when war is declared, its not done in
isolation, the houses take a side, some commit men, some don't, some join the other side", "you need to be able to
simulate these dynamics", "understand intent and think about it holistically".

**The intent.** A war is the King's largest bet. It splits the realm into two camps, it costs every season it runs,
it can be lost, and it is remembered after. The player should feel it before he declares (what will this start?),
see it everywhere while it runs (whose side is everyone on? am I winning? what is it costing?), and live with it after
(towns changed hands, grudges, a league that might form). Everything below serves that.

**Copied from.** EU4's declaration screen (who joins each side, before you confirm); CK3's call to arms, war score
and the war map mode (every realm painted by its side); Total War's diplomacy colours (allies in your tint, enemies
in theirs) and per-turn upkeep; Frostpunk's "every law hurts someone".

## The journey

### 1. Before: the war council (one screen, the decision)

Declaring war opens a council card, not a one-click order (EU4's declare-war dialog). It shows, in the realm's words:
- **The sides.** Every great house in one of three columns, *With you*, *Waits*, *Against you*, each with its men
  and the reason ("sworn to the crown", "bound to Wolfholt by marriage", "cold to the crown"). Likely and possible
  are told apart. (war.js sides: built.)
- **The odds.** Our men and our allies' against theirs and their allies': one line ("we'd likely win") and the two
  sums.
- **The cost.** The price now, the upkeep each season it runs (rising with each war already on), and the alarm it
  raises toward a league.
- **The goal.** What winning takes (their towns one by one, the seat last) and what losing costs (they ask a town).
- Two buttons, the rightmost the one we want pressed only when it is wise: *Declare war* and *Not now*.

### 2. Declaring: an event, not a toast

- A declaration moment: the war horn, the screen's edge goes to war, the chronicle's first line of the war, and the
  sides as they actually fell (the roll, which may differ from the forecast: a house that "may" join did or didn't).
- The map changes at once (below).

### 3. During: the war is everywhere on screen

- **The map's war mode.** While the crown is at war, every realm is painted by its camp: the crown and its allies in
  the crown's colour (allies a lighter tint of it), the foe and its allies in the foe's colour (its allies a tint of
  it), the houses that wait greyed. Borders between camps are the front. (CK3's war map mode, Total War's diplomacy
  colours.) The painting is political_overlay's, from one reading of the camps.
- **The houses strip** groups by camp: with you | waiting | against you, each chip in its camp's tint, the word still
  carrying it (Mac is colour-blind: "Ally", "Foe", "Waits").
- **A war banner in the control plane** (the goal's place while it runs): *War on Wolfholt · 2 of 6 towns taken ·
  winning · 3,000 crowns a season*. A click opens the war card (sides, score, sieges, the peace table's terms).
- **War score** (CK3): towns taken and lost, battles won and lost, from 0 to 100 either way; it sets what the peace
  table can ask (peace.js already measures towns lost each way).
- **The camps move.** An ally whose favour falls, or whose lands are raided, may leave the war; a waiting house may
  join the side that is winning (bandwagoning), or the losing side if the King's alarm is high (balancing).

### 4. Ending: the peace table

- Peace comes by war score (peace.js): winning, the King takes a town or gold; losing, he gives one; even, a white
  peace. Or the seat falls and the house is toppled (war.js topple).
- Allies are paid or remembered: an ally who marched asks a share of the spoils (characters.js); one denied
  remembers.

### 5. After: what the war leaves

- Truces (no war on that house for seasons), grudges in the lords' memories, towns that changed hands restless for
  seasons, the alarm and the league it may bring, the upkeep gone.

## Owners (one per fact)

| Fact | Owner |
| --- | --- |
| The King's wars (plan, target, allies, commitment, since) | war.js, `meta.wars` (a list) |
| Who sides with whom, forecast and roll | war.js `sides` |
| War score and the peace terms | peace.js |
| Upkeep | war.js `upkeepNow` |
| Alarm and the league | coalition.js |
| The camps on the map | political_overlay.gd, from `/world wars` |
| The council card, the banner, the strip's camps | the view, from `/world` |

## Build order (each a ten-minute piece)

1. **Built.** `meta.war` becomes `meta.wars`: several wars, each its own plan and sides; upkeep counts them (no more silent
   replace).
2. **Built** (`/world kingWars[].camps`, `.standing` from peace.js). `/world wars` carries each war's camps (crown side, foe side, waiting) and score.
3. **Built** (`war_council.gd`, bridge `war.js council` on `/world players[].warCouncil`). The war council card: every war order (town card, houses table, the Hand) opens it in main.gd `_order`; Declare war and Not now.
4. **Built** (political_overlay.gd `_war_mode`, from `/world kingWars[].camps`; tints in data/map.json war_mode). The map's war mode: political_overlay paints by camp while a war runs.
5. **Built** (houses_strip.gd `_camps`; words in ui.json houses_strip.camps and .words). The houses strip groups by camp with Ally / Foe / Waits words.
6. The war banner in the control plane, opening the war card.
7. The declaration moment (horn, edge, chronicle line, the sides as they fell).
8. Camps move during the war (allies leave, waiters join the winner or, with alarm high, the loser).
9. War score in peace.js from towns and battles; the peace table's terms by it.
