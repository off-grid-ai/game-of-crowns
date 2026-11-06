# The r/godot post

Scored with RUBRIC.md; the evidence is in STUDY.md. Nothing has been posted.

## Recommendation first
**Hold r/godot until the 26 image-model assets are replaced** (the banners, sigils and six ground textures listed in `realm/assets/generation-prompts.json`), then post the version below.
- Rule 10 removes AI-generated content, and self-promo posts that disclose AI use are mod-removed 21% of the time, against 2.9% overall.
- Those banners show in nearly every in-engine shot, and the repo that the post links to publishes the generation prompts. Hiding them won't hold, and disclosing them invites removal.
- r/godot brings Godot developers, not many players: the median self-promo post scores 6. A pile-on here costs more than a good post brings.

If Mac wants to post before the swap, use the same post with the disclosure line marked below, and expect a real chance of removal.

**Don't use the launch film here.** Its paintings come from an image model (Rule 10), and its painted look is exactly what r/godot reads as AI.

## The planned draft, scored
From docs/buzz/launch-today.md (read only):
> **I built a medieval kingdom in Godot 4 where history names you for how you ruled. It's out on Mac today**
> Godot draws everything you see… a Freeciv server runs the world, and a small Node bridge… Ask me anything about running Freeciv under Godot.

| Gate | T1 | T2 | T3 | T4 | P1 | P2 | P3 | P4 | P5 | P6 | Total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Fails if it uses the launch film | 1 | 1 | 1 | 2 | 1 | 1 | 1 | 1 | 1 | 2 | **12/20** (flop range) |

What drags it down:
- The title is a premise plus a release line, with nothing to look at.
- The media isn't chosen.
- The architecture is named but nothing is taught.
- The marketing paragraph reads like the store page.
- No AI disclosure, in a sub that hunts for it.

What it gets right is putting Godot at the centre.

The technical claims are true against the code: Godot draws the land, towns, crowds, castles and map; Freeciv runs underneath (`bridge/server.js` spawns `freeciv-server`); the bridge keeps the lords' memories (`bridge/minds.js`).

## Titles
| Title | T1 | T2 | T3 | T4 | /8 |
|---|---|---|---|---|---|
| **Freeciv runs my medieval kingdom sim headless, and Godot draws all of it** (recommended) | 2 | 2 | 2 | 2 | **8** |
| A medieval kingdom sim where history names you for how you ruled (Mac's HN line) | 1 | 2 | 2 | 2 | **7** |

Mac's line is the better line for players, and it won the HN study for a reason. r/godot rewards a thing to look at and a surprise about how it's made, and its strategy premises flop: Houses of Veyra, a noble-houses pitch, scored 2 and then 5. Use Mac's line on r/macgaming and itch, and the Freeciv line here.

## The post (Mac's final copy of 6 Nov, flair `selfpromo (games)`)
The body is Mac's final copy (docs/buzz/hn/POST.md, 03a5804), word for word. For r/godot I added three things: the title, one short Godot paragraph (the study shows a real "how" is what earns votes here, and Rule 8 wants Godot at the centre), and the link on its own line at the end (a Reddit post has no URL field). Off Grid AI and "nothing leaves your Mac" stay out of the post, for replies only.

**Title:** Freeciv runs my medieval kingdom sim headless, and Godot draws all of it

Game of Crowns is a medieval kingdom sim. You're the king, and seven great houses want your throne. You hold it with grain, gold, marriages and your rulings at court. Side against a house in a war, and ten years later its lord stands up at court to remind you. When your reign ends, history names you: the Golden, the Bloody, or the Deposed.

I wanted my own Game of Thrones story, so I built one where you can rename anyone, rewrite their past and pick the story that comes for your throne. A season passes every 20 seconds, so a whole reign fits in an evening.

With an optional local model, you can answer petitioners in your own words instead of picking from a list, and it can write you a new story for your next reign.

Godot draws all of it: the land on Terrain3D, the towns and their crowds, and the painted map you get when you pull all the way back. Freeciv runs headless underneath, and Godot asks it for the world once a second. Godot animates every AnimationPlayer every frame unless you stop it, so the crowds are on manual. People near the camera move every frame, people further out every third frame, and nobody out of view moves at all.

It's free and open source on Apple Silicon Macs, with Windows next. I built it with Claude on top of Freeciv, and I'm happy to go into how any of it works.

https://github.com/off-grid-ai/game-of-crowns

*Only if posting before the asset swap:* after "I built it with Claude on top of Freeciv", add "(the house banners, sigils and some ground textures came from an image model)".

**Score:** gate passes after the swap; title 8; post P1 2 (with the clip below), P2 2 (the AnimationPlayer paragraph), P3 2 (short, human, one link at the end), P4 2, P5 2 ("I built it with Claude", plain and not the subject), P6 2. **20/20, or 19/20 with Mac's title.** Without the Godot paragraph, P2 drops to 0 and P6 to 1: 17/20. The rubric can't see how good the clip looks, which is probably what decides it, so treat the 20 as "no known mistakes", not a forecast.

**Every claim, checked in the code:**
- Terrain3D is the ground (`realm/addons/terrain_3d`, `realm/scripts/terrain.gd`).
- Freeciv is spawned headless by `bridge/server.js` (`freeciv-server -p … -b 127.0.0.1`).
- `bridge/lua/events.lua` prints `EVENT {json}` lines that the bridge reads from stdout.
- The HTTP API runs on 127.0.0.1:8787 (`bridge/server.js`), and `realm/scripts/bridge.gd` polls it on a 1.0 s timer.
- The painted map is drawn by `realm/scripts/realm_map.gd`.
- The crowd stepping is in `realm/scripts/anim_lod.gd`: `ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`; within `NEAR` = 6 world units every frame; otherwise one frame in `STRIDE` = 3 with the owed time added back; nothing once out of frustum or past `SEEN_TO`.
- People are Mixamo (`realm/assets/people/mixamo`), and the licence is MIT (`LICENSE`).
- The rest of the body is Mac's copy, checked against the README and ledger: seasons of 20 s (shipped in beb839b), renaming and rewriting anyone, picking the story, the local model writing stories (docs/play/r42-generate), and Windows listed as coming.

The post says "near the camera" rather than a distance, because world units aren't metres.

## What to post with it
1. **Best: a new 20-30 s single take in-engine, no captions**, recorded after the asset swap. Start on the painted map, scroll into Goldrock, and keep going down to street level among the crowd, so the clip shows the title's claim (Godot drawing all of it). Native upload as video, not a YouTube link: uploaded video reaches 100 points 16.3% of the time, YouTube 0.6%. Optional, and the strongest r/godot pattern if cheap: a second pass with each person tinted by animation rate (every frame, every third, off). That's the Psych Rift move (2,364), but it means building a debug view, so only if it's small.
2. **From what exists: `docs/buzz/video/every-lord-remembers-16x9.mp4`** (40 s). It's all in-engine, opens on a town, and ends on the GitHub link, but it's a captioned trailer and the banners are in shot.
3. **Not:** `game-of-crowns-launch-16x9.mp4` (image-model paintings). `one-call-16x9.mp4` and `game-of-crowns-0.4-hook-16x9.mp4` aren't right either: both caption "runs itself", which Mac cut from copy, and the 0.4 hook ends on the old itch link, though its zoom from town to map is the right shot.

## In the thread
- Post between 06:00 and 15:00 UTC (11:30-20:30 IST). Video posts there reach 100 points 18-20% of the time, against 13% late at night.
- Stay and answer for the first hours, which the flair requires. Winners' posters replied a median of 17 times.
- Answer "how" questions with the file and the node. Answer "was this vibe coded?" with what Mac did and what Claude did, in one plain sentence, and don't argue AI.
- Expect a "what fps?" question and answer it honestly. The ledger measured about 10 fps at town zoom on 5 Nov, with test workers loading the machine.
