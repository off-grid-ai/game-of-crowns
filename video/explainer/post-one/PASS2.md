# Pass 2: the living world first, memory as one beat (Mac, 2026-11-05)

Mac's notes on draft 1: "decent", but it leans too hard on memory. The shots need to look better, with better people
in them. The film should spend more time in the world: busy towns, the rider, armies, seasons turning, years flying,
and a chain the King's call set off. Fewer panel shots.

Waits on: the main session's first-impression fixes (docs/buzz/first-impression.md) and its close-ups
(docs/buzz/images/zoom/live/). Nothing is captured from today's footage.

## Shape (~35 s; 9:16 cut ~25 s): about 70% world, 30% panels
| # | s | World or panel | What | Line |
|---|---|---|---|---|
| 1 | 0–3.5 | world | a busy town street, people at work (close-up) | A kingdom that runs itself. |
| 2 | 3.5–6.5 | world | the realm from a low height, towns along a river | — |
| 3 | 6.5–9.5 | world | the same seat, spring → autumn → winter, hard cuts | Years go by in minutes. |
| 4 | 9.5–12 | panel | one decree with its price (the King's call) | You make the big calls. |
| 5 | 12–16 | world | the King's rider on the road (Watch) | — |
| 6 | 16–19 | world | an army marching out, then the clash | The great houses go to war on their own. |
| 7 | 19–24 | panel + world | the memory beat: a lord at court bringing up the King's deed in his own words (the main session's lord test); else Ysolde from r13/09 | Every lord remembers. |
| 8 | 24–29 | world | the consequence on the land: a march on Kingsmere, a siege | — |
| 9 | 29–33 | end card | Game of Crowns. Free on Apple Silicon. github.com/off-grid-ai/game-of-crowns | |

## Captures needed (each through realm/tools/render.sh, one Godot at a time, never over a running game)
- Close-ups: the main session's stills in docs/buzz/images/zoom/live/, or takes of `--clip=street --city=<seat>`.
- `--clip=realm --secs=8`, `--clip=descent`.
- Seasons: `--clip=seat --city=<seat> --season=spring|autumn|winter --secs=0` (stills), or three short takes.
- The rider: a Watch scene, which only the running game makes, so ask the main session for a recording.
- Armies: `--clip=battle --city=<seat>`; `--clip=siege --city=Kingsmere`.
- The memory beat: the main session's lord test (a lord raising a year-old deed at court), as a frame or a clip.

Each take gets checked against first-impression.md before it goes in: no one sunk, no cream boxes, no fog discs,
no stain squares, no progress text, no labels cut by roofs.
