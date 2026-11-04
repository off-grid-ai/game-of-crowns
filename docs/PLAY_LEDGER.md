# Play ledger

What playing Game of Crowns turned up, and what was done about it. Newest first. Each round: what a player would expect, what the game did instead, the change, and its commit. The aim: a Game of Thrones Westworld, an immersive world simulation where everyone, NPCs included, has a memory, a role and responsibilities, and can deal with you.

How a round is played: `realm/tools/play/*.play` scenarios feed real input (keys, holds, clicks) through `realm/scripts/autoplay.gd` (`--play=<scenario> --out=<dir>`, a test aid that is off in play). Each run saves frames and a log of what the game says at every step (walking or not, the prompt shown, panels open, frame rate).

## 2026-11-05 (overnight)

| # | Expected | Found | Change | Commit |
|---|---|---|---|---|
| 4 | Esc ends a conversation | The talk's text box held the keyboard and swallowed Esc: no way out of a conversation | Walking mode hears Esc before the box does | 03eb103 |
| 5 | Leaving walking clears its screen | The conversation panel and name tags stayed (the panel was freed but still referenced, so the next talk reused a dead one) | Leaving walking closes and forgets the talk, tags and prompt; the microphone is wired once, not again each walk | 03eb103 |
| 6 | The menu is the menu | Opening the menu or Settings while walking left the walk running under it | Opening the menu steps you out of walking first | 03eb103 |
| 1 | Esc leaves walking as the King | The interface took Esc first to close its panels, so walking mode never heard it: no way out | The interface leaves Esc to walking mode while you walk | 89eb154 |
| 2 | Settings drawn over everything | The King's name tag and walking prompts drew on top of the Settings menu | Walking's display sits under the menu | 89eb154 |
| 3 | The camera pad always there (Ali) | It hid until the mouse came near | Always on screen by default; Settings keeps near-only and never | b22f0b1 |
