# Army command and town look: rules from the reference games (2026-11-11)

Research for the builders. Two questions: how the big strategy games frame and command a large army, and what
makes the best builder towns read picturesque from a high oblique camera.

How to read the tags: **DESIGNER** (the studio said it), **MANUAL** (official manual or patch notes),
**PLAYERS** (forums), **MEASURED** (taken from store screenshots with a script, see the method note),
**BY EYE** (counted on a screenshot), **ESTIMATE** (my judgement; tune on renders).

---

## 1. Framing and commanding a large army

### What each game does

**Warcraft III** (the fidelity target)
- Team colour is worn, not drawn on top: a mask on each model's cloth, shields and roofs takes the player's
  colour. From any zoom, colour says whose it is. BY EYE (Reforged gameplay shots).
- A selection circle sits on the ground under each selected unit; its size follows the unit's footprint. BY EYE.
- Selection is capped at 12 units. Mixed selections split into subgroups by unit type, and the command card
  shows only the active subgroup. Control groups are Ctrl + a number. MANUAL:
  [Blizzard's special commands guide](https://classic.battle.net/war3/basics/specialcommands.shtml).
- A moving group keeps a formation: ranged units travel at the rear and fast units slow to the slowest.
  Players note this "falls apart with larger group sizes". PLAYERS:
  [Blizzard forum](https://us.forums.blizzard.com/en/warcraft3/t/one-big-reason-we-should-keep-the-12-unit-control-group-cap/13260?page=4).
- The command card is a fixed 4 × 3 grid, bottom right; an order always sits in the same cell, so hotkeys are
  muscle memory. BY EYE.
- Lesson: it frames a dozen heroes and squads beautifully, and does not scale to thousands. Take the colour
  mask, the ground ring and the fixed command grid; do not take per-man selection.

**Age of Empires II: Definitive Edition**
- Four formations: line, box (weak units in the middle), staggered (spread against siege) and flank (two
  wings that try to surround). PLAYERS:
  [AoE forum](https://forums.ageofempires.com/t/we-now-really-need-more-unit-formations-and-commands/206030).
- A formation moves at the speed of its slowest unit so it arrives together. Reverse-engineered:
  [openage formation notes](https://simonsan.github.io/openage-webdocs/sphinx/doc/reverse_engineering/game_mechanics/formations.html).
- Players ask for a toggle between a marching column and a fighting line, because one shape cannot do both.
  PLAYERS: [AoE forum](https://forums.ageofempires.com/t/formation-add-movement-formation-toggle/191870).
- Team colour is on tunics, shields and building trims. Armies read as blocks of colour from far away. BY EYE.

**Age of Mythology: Retold**
- "Select all military" and newer hotkeys for all melee infantry, all melee cavalry and all ranged cavalry,
  each with an on-screen variant. MANUAL:
  [update 18.21333](https://www.ageofempires.com/news/age-of-mythology-retold-update-18-21333/),
  [update 17.36100](https://www.ageofempires.com/news/age-of-mythology-retold-update-17-36100/).
- The military radial menu is split into abilities and formations. Formation slots that land inside terrain or
  across a wall were fixed in patches: formations must respect the ground. MANUAL (same notes).
- Lesson: selecting by type ("all cavalry") is how a player handles a big army without clicking men.

**Total War** (the scale reference)
- The unit of command is the regiment, never the man. Each regiment has a banner floating above it; the banner
  identifies its side, glows when selected, and can be clicked to select it. Its card in the bottom bar turns
  yellow. MANUAL: [banners](https://r2enc.totalwar.com/en/manual/single-player/0079_enc_page_battle_play_phase_conflict_banners).
- Regiments are grouped (Ctrl + G); a group's cards sit under one numbered tab, the group can take a fixed
  formation, and a locked group keeps its shape while moving. MANUAL:
  [groups](https://r2enc.totalwar.com/en/manual/single-player/0082_enc_page_battle_play_phase_conflict_groups),
  [Warhammer wiki](https://totalwarwarhammer.fandom.com/wiki/Unit_movement).
- Three Kingdoms lets you drag a whole selection into a formation in one motion, melee placed ahead of ranged.
  DESIGNER: [Creative Assembly's quality-of-life post](https://www.totalwar.com/?p=16273).
- Shogun 2's banner carried three facts with no extra icons: unit type painted on it, the flag more ragged as
  men die, and a faint flash when wavering. Players prefer it to later icon clutter. PLAYERS:
  [r/totalwar](https://lr.us.psf.lt/r/totalwar/comments/13xmk33/icon_bloat_is_getting_ridiculous_pharaoh_vs/jmi4llk/?context=3).
- Open-source reference for the same idea: 0 A.D.'s
  [formation design](https://docs.wildfiregames.com/design/gameplay/main/formations.html) and its
  [battalion standards thread](https://wildfiregames.com/forum/topic/68008-formation-standards-total-war-style-flags-over-battalions).

### The pattern for a King commanding thousands

Our armies are VAT regiments in house colours. Recommended: **Total War's regiment and banner, Warcraft III's
colour mask and command grid, Age of Empires' formations and select-by-type.**

1. **Command regiments, not men.** A regiment is 100–200 men (ESTIMATE); an army is 5–20 regiments. One click
   selects a regiment; a double click selects every regiment of that type; a drag box selects all it touches.
2. **House colour is worn.** The shared team-colour mask (already our north star) on tunics, shields and
   banners. Rule: at least 30% of a regiment's visible pixels are house colour (ESTIMATE), so a block reads as
   one colour from the far camera.
3. **One banner per regiment.** A pole above the regiment's centre, about 2.5 × a man's height (ESTIMATE),
   house colour field with a unit-type glyph (spear, bow, horse, engine). Strength shows as the flag fraying or
   as up to five pips under it; a wavering regiment's banner flashes. Beyond a set distance the banner keeps a
   constant size on screen, so it never vanishes.
4. **One army standard.** Larger, with the lord's arms, over the commander's regiment. It is the handle for the
   whole army: click it to select every regiment.
5. **Selection on the ground.** A rectangle decal under the regiment's footprint in house colour, brighter when
   selected, plus the banner glow. No ring per man.
6. **Two shapes, switched by the game.** On the march: a column 4–6 men wide on roads, regiments nose to tail
   (matches the art target's "armies as coloured columns"). On contact or on order: a line, melee in front,
   archers behind, cavalry on the wings. The army moves at its slowest regiment's speed.
7. **Drag to face.** Right-click and drag draws the line the army will form on, with ghost markers per
   regiment, before the order is given (Total War).
8. **A small fixed command card.** Six to eight orders in fixed cells with fixed hotkeys: March, Attack, Hold,
   Line / Column, Retreat, Besiege, Garrison. Nothing else.
9. **Cards for regiments.** A row of regiment cards (type glyph, house colour, strength) at the bottom, only
   while an army is selected; groups under numbered tabs.
10. **Far zoom collapses.** On the realm map an army is one marching column with its standard and a strength
    number. Zooming in swaps to regiments with banners; the colour and the standard stay the same throughout.
11. **Friend and foe.** Colour says which house; a small shape on the banner tip says relation to the crown
    (ours, sworn, at war), so it never rests on red against green alone.

---

## 2. Towns that read picturesque and alive from a high oblique camera

### Measured from store screenshots

Share of the frame by colour family, mean brightness (0–1) and mean saturation (0–1). MEASURED.

| Shot | Green | Red roofs | Warm earth, thatch, timber | Grey | Blue | Brightness | Saturation |
|---|---|---|---|---|---|---|---|
| Manor Lords, village | 37% | 3% | 27% | 18% | 15% | 0.33 | 0.33 |
| Manor Lords, valley | 21% | 1% | 27% | 10% | 41% | 0.30 | 0.34 |
| Anno 1800, town and fields | 20% | 9% | 21% | 28% | 22% | 0.38 | 0.30 |
| Anno 1800, New World town | 33% | 16% | 37% | 7% | 6% | 0.34 | 0.46 |
| Foundation, town in fields | 42% | 2% | 48% | 3% | 5% | 0.36 | 0.49 |
| Foundation, market square | 19% | 9% | 58% | 8% | 6% | 0.40 | 0.48 |
| Farthest Frontier, city plaza | 5% | 41% | 39% | 15% | 0% | 0.39 | 0.31 |
| Farthest Frontier, city by a lake | 29% | 31% | 27% | 12% | 0% | 0.35 | 0.30 |
| **Ours, Kingsmere** | 28% | 5% | 57% | 8% | 2% | 0.30 | 0.38 |
| **Ours, town at mid zoom** | 7% | 26% | 43% | 20% | 2% | 0.24 | 0.29 |

What the table says:
- Twelve shots were measured; the eight clearest are shown. All twelve fall between brightness 0.29 and 0.48,
  most at 0.33–0.40. Ours is 0.24–0.30: **too dark**, most of all at mid zoom.
- Realistic games sit near saturation 0.30; the stylised one Mac liked (Foundation) sits at 0.48.
- Villages and towns keep 20–40% green in frame. Only the densest city cores drop to 2–5%, and those still
  show trees in their squares. Our mid-zoom town has 7%.

### Counted on the screenshots (BY EYE)

| | Manor Lords village | Farthest Frontier city | Foundation town | Anno 1800 town |
|---|---|---|---|---|
| Houses in frame | ~35 | ~60 | ~15 | ~150 |
| Frontage per house | 10–12 m, gaps are yards | 7–9 m, continuous | 8–10 m, loose | 8–10 m, continuous blocks |
| Roof mix | ~100% thatch, varied tone | ~90% terracotta tile, ~10% slate | ~60% orange tile, ~25% brown shingle, ~15% blue slate | ~60% red tile, ~30% dark slate, ~10% copper green |
| Trees | 1 per 3–4 houses, plus forest edge | 1 per 4–5 houses, in squares and streets | 1 per 2–3 buildings | street trees and park blocks |
| Props | fence round every plot, vegetable beds, woodpiles | planters every ~5 m of plaza, statues, benches | 4 stalls, barrels, a well, fences in one square | carts, crates, chimneys smoking |
| People visible | few, on roads | few at this height | ~12 in one square | dozens, deliberately oversized |
| Tall landmark | church at the edge | domed hall on the plaza | manor tower | factory chimneys, church |

### What the studios say

- Anno 1800: visual feedback exists so the player can read the city (a building looks busy, idle or on fire)
  and so the world is believable. DESIGNER: [DevBlog: Visual Feedback](https://anno-union.com/?p=9905).
- Anno 1800: the era should show "without becoming too dark or dirty". DESIGNER:
  [concept art DevBlog](https://anno-union.com/?p=9801). Its walking residents are drawn out of scale on
  purpose, for readability. DESIGNER (community Q&A, same site).
- Manor Lords: plots were inspired by medieval burgage plots; the aim is "a balance between gameplay and
  realism", not strict accuracy. DESIGNER:
  [PC Gamer](https://www.pcgamer.com/games/strategy/runaway-city-building-success-manor-lords-is-getting-a-major-overhaul-to-its-systems-its-not-just-a-new-feature-or-two-its-a-full-rework/),
  [GamesRadar](https://gamesradar.com/games/city-builder/manor-lords-dev-doesnt-like-calling-the-city-builder-historically-accurate-because-nothing-truly-is-and-wants-to-find-a-balance-between-gameplay-and-realism).
- Farthest Frontier: decorations raise a home's desirability most, and "the more variety you bring to an area,
  the more the desirability will rise". The game pays players to make streets varied. DESIGNER:
  [Crate's guide](https://www.farthestfrontier.com/?p=1754).
- Foundation: houses only upgrade inside "beautification areas" made of decorations. DESIGNER:
  [Polymorph changelog](https://www.polymorph.games/foundation/news/?p=1916).

### Rules for our builders

Numbers marked ESTIMATE are starting points to tune on renders. They agree with `town-plots-research.md` in the
session notes.

**Density**
1. Village: 8–10 houses per 100 m of street per side (10–12 m plots, gaps are yards). BY EYE.
2. Town centre: 14–16 per 100 m per side (6–7 m fronts, walls touching). ESTIMATE from the history and
   Farthest Frontier.
3. Density falls from the market outwards: centre 100% of the street front filled, middle about 80%, edge
   about 50%.

**Roofs and colour**
4. One dominant roof at 60–70%, a second at 20–30%, an accent at 10–15% at most. BY EYE (all four games).
5. Roof follows wealth: thatch, then shingle, then tile. House colour goes on tile roofs, trims, shutters and
   awnings (the north star); keep at least 30% of roofs natural thatch or wood so the colour doesn't flood.
6. Vary each roof's tone by about ±8% and its ridge direction; four or more house models per wealth tier,
   mirrored and turned ±5° off the street line. ESTIMATE.
7. Frame targets at roof height: brightness 0.36–0.42, saturation 0.40–0.48 (the Foundation end, which Mac
   liked), grey under 20% of the frame. MEASURED range.

**Greenery**
8. Never a street with no green. Village: 1 tree per 3 plots and a garden behind every house. Town centre:
   1 tree per 5 houses, clustered at the square, the church and crossroads. BY EYE.
9. Green covers 20–40% of the frame for a village or small town, at least 5–10% even in a city core. MEASURED.

**Props and life**
10. A fence or hedge along at least 70% of back plots: fence lines draw the plot grid from above. BY EYE
    (Manor Lords).
11. One prop cluster per 10 m of street in the centre (barrels, a cart, a stall, a woodpile); never the same
    prop twice within 15 m. ESTIMATE, from Farthest Frontier's variety rule.
12. A market has 4–8 stalls with coloured awnings; one well or shrine per 40–60 m of main street. BY EYE.
13. Smoke from 1 chimney in 4–5; a visible walker every 10–15 m of centre street; people drawn 1.2–1.3 × true
    scale so they read at roof height. ESTIMATE (Anno's out-of-scale residents).
14. A building shows its state: working (smoke, open shutters, goods outside), idle (shut), hurt (fire,
    char). DESIGNER rule from Anno.

**Shape and light**
15. One tall landmark per town, 2.5–3 × house height (church tower, keep), placed on the square or at the
    edge, never lost in the middle of a block. BY EYE.
16. Streets bend; plots stay square to their own street. Dirt lanes 4–5 m with soft edges in a village, cobbles
    8–10 m in a centre, a 25–35 m market place.
17. Sun at 35–45° so shadows are 1–1.5 × building height: long enough to model the roofs, short enough to keep
    streets lit. Warm key light, cooler shadows, a light haze with distance. BY EYE (Manor Lords, Farthest
    Frontier).

---

## Method and caveats

- MEASURED: each store screenshot was scaled to 160 × 90 and every pixel classed by hue and saturation
  (green 65–170°, red 340–25°, warm 25–65°, blue 170–260°, grey under 0.15 saturation). It is a coarse
  measure: sky, water and UI count too, so compare like with like.
- Store screenshots are marketing frames. Treat them as the ceiling.
- No developer source was found for Warcraft III's 12-unit cap or for Total War's banner design reasoning;
  those points rest on the manuals, forum posts and what the screenshots show.
- Ours was measured from `docs/review/screens/v/town-5.jpg` and `midtown-3.jpg`, which may be behind the
  current build.
