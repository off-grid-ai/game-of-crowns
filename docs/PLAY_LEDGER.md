# Play ledger

What playing Game of Crowns turned up, and what was done about it. Newest first. Each round: what a player would expect, what the game did instead, the change, and its commit. The aim: a Game of Thrones Westworld, an immersive world simulation where everyone, NPCs included, has a memory, a role and responsibilities, and can deal with you.

How a round is played: `realm/tools/play/*.play` scenarios feed real input (keys, holds, clicks) through `realm/scripts/autoplay.gd` (`--play=<scenario> --out=<dir>`, a test aid that is off in play). Each run saves frames and a log of what the game says at every step (walking or not, the prompt shown, panels open, frame rate).

## 2026-11-05 (overnight)

| # | Expected | Found | Change | Commit |
|---|---|---|---|---|
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
