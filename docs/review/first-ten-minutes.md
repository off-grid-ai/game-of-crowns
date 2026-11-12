# The first ten minutes, as a new player sees them (2026-11-12)

From the title screen to the third court sitting, read from the code and the v2 opening (the default since gate
r6; docs/review/first-ten-minutes-plan.md is the plan it came from). The bridge side (pacing, the first court's
timing and matter, prices, the Hand's numbers, the chronicle's firehose) is the gameplay agent's
(docs/review/gameplay-review.md); this review is the view's side, and names the bridge's only where they meet.

References: CK3's opening (your ruler and realm shown first, then one clear first decision), Frostpunk's first
minutes (one goal, the pressure always on screen), AoE IV's first minute (the camera on your own town, one obvious
action). The house rule: no tutorial pop-ups; the Hand's line and the first card teach.

## Minute by minute

| When | Now (v2) | Reference | Fix (view, behind data / UI v2) |
|---|---|---|---|
| Title | Begin on the first page of the form, the rest at defaults (title.gd:617); no splash (main.gd:401). | Frostpunk, Reigns: one button to play. | Keep. |
| Loading (0:00-~0:40) | The storybook: 16+ painted pages (realm, kings, the realm never waits, Kingsmere, six houses, court, lords, war, the realm at a glance, tips), several with **key strips** ("drag pan, scroll zoom, Q E turn, WASD move"; "B the Lore"). Any key ends it once the realm is built. | CK3: one splash of your realm and ruler. AoE IV: one civ card. | **Three pages** in v2 (the land, Kingsmere is yours, the court), **no key strips** (Mac's rule: the game decides; no key help on screen). opening.json `storybook`. |
| Landing (~0:40) | The camera frames Kingsmere's town (main.gd `_home_view`). The UI appears, all of it: date card with the royal ladder's first aim, treasury, readings, eight toolbar keys, minimap, rank strip. The Hand: "The realm is yours, Your Grace. The court is waiting." | CK3: the ruler's portrait and title first. AoE IV: camera on your town centre, one thing lit to press. | **The crowning (first minute):** the camera on the castle's keep, the royal standard raised over it, the bells, and one line in the middle of the realm for a few seconds: "Long live <the King's name>, King of Aldmere" (from the realm's own readings). Then the Hand's line. opening.json `crowning`. |
| The goal (0:40-) | The top bar's first line is the royal ladder's aim ("Muster a royal host of 2,400 men"; batch 7/8 frames), and the Hand's goal line "Hold the realm whole to the first winter" comes only after the first ruling. Two different goals. | Frostpunk: one goal, and the pressure (the storm's countdown) always on screen. | **One goal from the landing:** until the first winter, the date card's aim line reads "Hold the realm whole · winter in N seasons" (the plan's seasons-to-winter tracker, item 7), counting down from the realm's own date. opening.json `tracker`. |
| First card (~1:00) | The court waits at a lord's town: the edge arrow and the Hand's "A lord asks for you. Go to him." Space or the arrow goes there; the card stands by the town. (The court no longer takes the camera by itself: e87d2394.) | CK3's first decision is shown, not hidden. | The Hand's line names the gold arrow instead of "go to him", so the one obvious action is named: "A lord asks for you. Follow the gold arrow." (text, opening.json). |
| First ruling (~1:30) | The card turns, a toast, the decree's mark in the town (1b0d2b35, 1b4a4c30). The Hand: the winter goal. | Reigns: the meters move as you swipe. | Kept (the decision-reactions work). The Hand's goal line now repeats the tracker rather than introducing it. |
| Minutes 2-10 | All the toolbar's keys stand from minute 0 (court, houses, chronicle, lore, ledger, pace, settings, menu); the chronicle, if opened, is a firehose from before the crowning (gameplay-review #9). The second and third sittings come each season or so. The first setback is the bridge's (gameplay-review #1: a siege in minute two). | Frostpunk and Against the Storm open their panels as they matter; AoE IV's first minute has one obvious button. | **Hide what doesn't matter yet (the plan's item 6), view side:** until the first winter, in the first reign, the lore and ledger keys rest hidden (their keys still work); each appears with the winter. opening.json `hideUntilWinter`. The chronicle's firehose and the early siege are the bridge's (gameplay-review #1, #9). |

## Not changed here (named for the owners)
- The first setback's timing and the opening houses' favour (bridge; gameplay-review #1).
- The chronicle opening with 37 seasons from before the crowning (bridge; gameplay-review #9).
- The court's first matter (bridge, court.js).
- The new-chronicle form's options stay one page away (title.gd); first-time players play the defaults.

## How it's switched
Everything above is behind the v2 opening (on by default; `--opening=v1` for the old), with its numbers and words in
`realm/data/opening.json`; the hidden keys also need UI v2 (`--ui=v2`). Before/after shots: docs/review/batch9-list.md.
