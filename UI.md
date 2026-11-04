# Aldmere: interface philosophy

Inherits Off Grid's disposition (quiet, honest, restraint over ornament) and adapts it to a game. A game HUD is read in a glance, mid-action, at the edge of attention. The world is the content; the interface is a thin instrument panel over it.

## 1. The world is the interface
At rest the HUD covers less than a tenth of the screen. The centre is never covered unless you ask (the court, a menu). Anything that can live in the world does: banners, town names, building sites and their progress, soldiers drilling.

## 2. Corners, not columns
Four anchors, each with one job:
- **Top-left:** where you are in time (year, reign clock).
- **Top-centre:** the state of the realm (treasury, peace, souls, tithe).
- **Top-right:** what you can do (court, houses, chronicle, pace, menu).
- **Bottom-left:** what just happened (the ticker).

Side drawers slide in from the edges and close with Esc.

## 3. Glanceable
- **An icon and a number** replace a label and a number.
- **Words appear on hover** (tooltips) or when opened.
- A value's state reads from its tone (normal, gold when it needs you, red when it's being lost), never from a legend.

## 4. Compact and dense
- 32 px controls, 6–8 px radius, 4/8/12 spacing.
- 13 px text, 11 px mono for numbers and labels.
- Pills and strips, never boxes inside boxes.
- One hairline, never a border plus a shadow plus a fill.

## 5. Two families and one accent
- **Geist** for words, **Geist Mono** for numbers and labels.
- **Phosphor icons** (the Off Grid icon set), regular weight, one size.
- **Aged gold** is the only accent: the thing that needs you (petitioners waiting, the active pace).
- **Red** only for loss (famine, war, death, favour collapsing).
- The serif exists only for a character's own spoken words.

## 6. Disclose progressively
At rest: numbers. On hover: the explanation and the price. On click: the full panel. Nothing needs configuring before it works.

## 7. Keyboard first

| Key | Action |
|---|---|
| Space | pause |
| 1 / 2 / 3 | pace |
| H | houses |
| C | chronicle |
| K | court |
| Esc | close |

## 8. Motion only to direct attention
New events slide in and fade out. A waiting court gently glows. Nothing else moves. All motion is 120–200 ms, ease-out.
