# Game of Crowns: interface

The screen rules that serve [GAME_DESIGN.md](GAME_DESIGN.md). A game HUD is read in a glance, mid-battle,
at the edge of attention: quiet, honest, restraint over ornament. The world is the content; the interface
is a thin instrument panel over it. Every screen copies a named proven game, fitted to ours.

## 1. The world is the interface
At rest the HUD covers less than a tenth of the screen. The centre is never covered unless you ask (a
card, a menu). Anything that can live in the world does: banners, town names, building sites, soldiers.

## 2. Corners, not columns
Each anchor has one job:
- **Top-left:** time and the objective (year, reign clock, the one goal you're on).
- **Top-centre:** the state of the realm (crowns, grain, men, the name you're earning).
- **Top-right:** what you can open (court, houses, chronicle, pace, menu).
- **Bottom-centre:** what you've selected: the army's commander portrait, its strength and morale, its
  orders (Warcraft III's command card, Total War's unit bar). Empty when nothing is selected.
- **Bottom-left:** what just happened (the ticker).

Side drawers slide in from the edges and close with Esc.

## 3. Glanceable
- **An icon and a number** replace a label and a number.
- **Words appear on hover** (tooltips) or when opened.
- A value's state reads from its tone (normal, gold when it needs you, red when it's being lost).

## 4. Compact and dense
- 32 px controls, 6–8 px radius, 4/8/12 spacing.
- 13 px text, 11 px mono for numbers and labels.
- Pills and strips, never boxes inside boxes. One hairline, never a border plus a shadow plus a fill.

## 5. Two families and one accent
- **Geist** for words, **Geist Mono** for numbers and labels.
- **Phosphor icons**, regular weight, one size.
- **Aged gold** is the only accent: the thing that needs you (a matter waiting, the active order).
- **Red** only for loss (a town falling, famine, favour collapsing).
- The serif is only for a character's own spoken words.
- House colours belong to the world (banners, roofs, uniforms), not to the HUD chrome.

## 6. Disclose progressively
At rest: numbers. On hover: the explanation and the price. On click: the full card. A first reign shows
the essentials; more appears as the player reaches for it, never all at once.

## 7. Command
- **Left-click** selects an army; drag a box to select several. **Right-click** orders: on ground, march;
  on an enemy army, attack; on an enemy town, besiege; on an ally's town under siege, relieve.
- The cursor shows the order before you click. Every order is answered at once: a voice line or horn,
  a marker on the ground, men turning to go.
- Clicking a person or army in the world opens its card; nothing needs a menu to reach.

## 8. Keyboard

| Key | Action |
|---|---|
| Space | pause |
| 1 / 2 / 3 | pace |
| H | houses |
| C | chronicle |
| K | court |
| Esc | close / deselect |

## 9. The camera
- Low oblique angle by default, never top-down; it stops at roof height.
- **The camera never steals.** No auto-pan. An event gets a ping, an arrow at the screen edge and a key
  that jumps there and back.

## 10. Motion only to direct attention
New events slide in and fade out. A waiting matter gently glows. All motion is 120–200 ms, ease-out.

## 11. Fill the frame, or fit it exactly
A view shows its whole subject edge to edge: no black around a map, no empty strip beside cards. A card
is as tall as its words.

## 12. One world, never a stage set
Ground, sky and light agree. No painting pasted behind a 3D figure, no toy-like stand-in. The realm is
shown only at distances where it reads well.

## 13. Every decision is seen
What an order or answer changed shows where it lives: the house's favour counts to its new value (gold
up, red down) and one line in the bottom-left gives cause and effect ("Ashford relieved: Goldcrest +15",
"You ignored Varn: Stormhold −10"). Big results also show in the world: a banner falling, a building
rising, a town changing colour.

## 14. Change it where you see it; nothing on screen is dead
Edit a thing where it's shown (a name, a story), not through a separate editor. Every card can be put
away. Anything that looks clickable does something; nothing invisible sits over the world. No debug
pickers or animation lists.

## 15. For all ages
No sexual content anywhere: traits, events, pasts, or anything the model writes.
