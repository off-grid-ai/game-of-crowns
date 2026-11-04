# Play ledger

What playing Game of Crowns turned up, and what was done about it. Newest first. Each round: what a player would expect, what the game did instead, the change, and its commit. The aim: a Game of Thrones Westworld, an immersive world simulation where everyone, NPCs included, has a memory, a role and responsibilities, and can deal with you.

How a round is played: `realm/tools/play/*.play` scenarios feed real input (keys, holds, clicks) through `realm/scripts/autoplay.gd` (`--play=<scenario> --out=<dir>`, a test aid that is off in play). Each run saves frames and a log of what the game says at every step (walking or not, the prompt shown, panels open, frame rate).

## 2026-11-05 (overnight)

**Supervisor 04:22** (independent review of r01–r04): (1) the opening: three panels cover the map and the Hand's counsel, banners and marriage were never captured; re-capture until each has a frame. (2) Favour means nothing yet: all 28, no reasons; show why (CK3-style: "+10 marriage, −15 taxed") and what each band does. (3) Guard what the player reads: garbled model lines, engine words ("Training Settlers 6%", "20 t of 400 t"), the Crown's row of dots, a 0 purse with no reason. Also seen: the timed reign ended on a newcomer; the Crown razed towns unbidden (both fixed in 74949fb, not yet re-captured). Call kept: the houses and chronicle panels stay open by default (Ali asked for that view); the counsel must stand out with them.

| # | Expected | Found | Change | Commit |
|---|---|---|---|---|
| 30 | The King can stop a war | The counsel's answer to a war was "a feast for each" (r06/04-first-view) | Command peace: both warm (40+) obey, their soldiers by the other's towns go home, war appetite cools, a truce holds; a cold house refuses. The engine still counts them at war; the fighting stops. In the counsel beside "Wed them to each other" | daf44c6 |
| 29 | The counsel stays in view | It covered the bottom of the houses panel ("Your word") | "Proclaim your word…" folds to one line until wanted | daf44c6 |
| 28 | Read what the people say (supervisor #3) | Model lines that loop ("a liege's liege, not my liege's liege") and stray quotes | Two sentences at most, no stray quotes, looping lines dropped | f4f3e02 |
| 27 | The King's own numbers | The Crown's row was a row of dots | Its towns, men, crowns, grain and souls | 2bc8e79 |
| 26 | Favour that varies, in view (verified, r06/04-first-view) | — | Seen: favour 41–62 by house, coldest first, coloured; counsel bottom-left; "Raising pikemen · 3%"; treasury 143k | r06 |
| 25 | A new reign starts cleanly (verified, r06/01–03) | — | Seen: three cards, the name follows the card, Begin, the loading story | r06 |
| 24 | The King can always act | The purse sat at 0 for good (upkeep charged soldiers the engine already pays for), so every decree failed silently (r05/05-banners) | Upkeep is the court and castles only; a decree the purse can't pay is greyed with why and how to fill it | de1cb08 |
| 23 | The counsel doesn't hide the table | The Hand's card sat over the houses' favour column and under the story offer (r05/03-counsel) | Bottom-left in plain type, clear of the table, the offers and a town's card | de1cb08 |
| 22 | Towns speak the realm's language | "Training Settlers 6%", "grain 20 t of 400 t" | "Raising settlers for a new town · 6%", "granary half full" | a3f305d |
| 21 | Favour has reasons (supervisor #2) | A number with no why | Every change records its cause; hovering shows them and what the level means | 913e98a |
| 20 | A newcomer's realm doesn't just end | A 10-minute reign ended mid-play; the menu offered only "View" (r04/03-realm) | Rule on (endless, score kept); Endless first, timed reigns as a chosen challenge | 74949fb, 28883ea |
| 19 | The King's army obeys the King | "Gildport is razed to the ground by The Crown", unbidden (r04) | The Crown's AI defends and builds, never conquers on its own | 74949fb |
| 18 | Houses differ | Every house at the same favour (28 on Tough) | Each starts from its own history with the crown (world bible) | 74949fb |
| 17 | The Hand's counsel shows (verified) | Seen working in r05/03-counsel: the coldest house with Gift crowns / A feast, petitioners with Hear them, the thin treasury with Raise the tithe | | r05 |
| 16 | The King can bind houses together (political alliances) | No royal diplomacy at all: alliances were chronicle lines between lords | A royal match on any house's card: both houses warm to the crown, the lords to each other, heirs named, a long truce against raids and plots | 70aa696 |
| 15 | The King can raise an army from his vassals | Only a paid royal levy; houses' loyalty never tested | Call the banners: loyal houses send men at once, wary ones a few with excuses, cold ones refuse; the men join the royal host. Once a year | 372e1c5 |
| 14 | The menu's first choice is obvious and easy to hit | Small thin text over a bright sky; a click landed between two entries (r03) | Bigger entries with a dark edge, Continue in gold | a10dddf |
| 13 | A newcomer can read the houses table | Identical numbers, an unlabelled red bar, "all bannermen grow restless" as the example (r01) | Favour as a number in its danger colour with a heading that explains it, coldest house first, a sensible example | d695898 |
| 12 | A new King knows what to do next (genre brief: learn by playing) | Nothing said what to aim for or try first (r01, 04-realm-opening) | The Hand of the King advises: the 2–3 most pressing matters, why each matters, and the decree that answers it as a button | af24212 |
| 11 | The King, not a god | Fate (drought, plague, treason), "The gods cannot", VISION's "you're its god" | God powers gone from the King's game; failed orders say "The crown cannot"; the settings are "What tests the reign" | 04546f4, d4ed5a7 |
| 10 | v1 is the strategy game (Ali) | Walking, fighting, riding as a character | All behind one switch, features.gd WALKING (off), for v2 | 2a05b9c |
| 9 | A ruling's words make sense | "The crown pays for a city walls in Kingsmere. The Crown is grateful." | In the King's own town no self-thanks; buildings read right | 700a262 |
| 8 | People speak first when approached | "You approach them." then silence until you typed | They greet you first (v2 with walking) | 700a262 |
| 7 | A new chronicle is quick to start (genre brief: depth on request) | One tall page of every choice, taller than the window (its heading ran off the top), voices repeated from Settings | Three reign cards (Gentle, Balanced, Tough) with what each means, a name and Begin up front; the rest folded behind "Customise every choice", sized to the window | 89428b6 |
| 4 | Esc ends a conversation | The talk's text box held the keyboard and swallowed Esc: no way out of a conversation | Walking mode hears Esc before the box does | 03eb103 |
| 5 | Leaving walking clears its screen | The conversation panel and name tags stayed (the panel was freed but still referenced, so the next talk reused a dead one) | Leaving walking closes and forgets the talk, tags and prompt; the microphone is wired once, not again each walk | 03eb103 |
| 6 | The menu is the menu | Opening the menu or Settings while walking left the walk running under it | Opening the menu steps you out of walking first | 03eb103 |
| 1 | Esc leaves walking as the King | The interface took Esc first to close its panels, so walking mode never heard it: no way out | The interface leaves Esc to walking mode while you walk | 89eb154 |
| 2 | Settings drawn over everything | The King's name tag and walking prompts drew on top of the Settings menu | Walking's display sits under the menu | 89eb154 |
| 3 | The camera pad always there (Ali) | It hid until the mouse came near | Always on screen by default; Settings keeps near-only and never | b22f0b1 |
