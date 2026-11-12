# Supervisor state (kept by the top supervisor every turn; Mac never has to remember)

Updated 2026-11-12 ~19:20.

## Waiting on Mac
- Nothing.

## Threads (4 + 1 closing)
| Thread | Session | Doing now | Next |
|---|---|---|---|
| Look audit (art set) | local_1116fb7d | Army set in Meshy: knight, horse redraw (Mac said yes), then a transport cog | Houses (roofs first), trees, ground; judges every frame beside the target |
| Army layer | local_7f29ed9b | Muster crash: windowed only, after "mover gave up" (lead: re-entrant NavigationServer call) | 397 replay view faults; battle density (~60 of 600 drawn, lines still); routes coloured by house; ship view (map done 131fd48b) |
| One store | local_dad14ab9 | Land use from Freeciv's worked tiles and specials (scratch copy; land in use 15% to 72%) | Gardens, shores; engine-visual gaps (sync order proof, plague shown, house income shown); ruleset: ships transport-only |
| GoC | local_22c5fa46 | READY 8 click fix (autoplay viewport vs window coords, x1.34): verifying, then land and retake | Step 6 camera and contrast frames (data edits ready, uncommitted); milestone retakes PAUSED until the Meshy army set lands (Mac killed the game: no filming of art about to be replaced) |
| Fire and siege (closing) | local_7100b3cd | Capture-chain probe (a town changing hands mid-siege) | Land it, then archive |

## READY
Built: 1-7, 9, 11-15. Reopened: 8 (film click; fix in hand). Open: 10 (a full reign: muster crash, view faults). Look pass: started (owner look audit).

## Decisions and why
- Engines and visuals are one: nothing drawn without an engine fact; the engine first (Mac).
- Ships carry armies and fight nothing (Mac), so the ruleset drops warships and the art set makes one transport hull.
- Four threads, not nine: collisions and idle waits cost more than parallelism gave (Mac).
- Art: stay on Meshy; one style and scale sheet (docs/art/STANDARDS.md); the frame gate (look audit).
- Commits: private index, private message file, HEAD == base.

## Open questions being worked (not Mac's)
- Graph engineering for prompting: its own thread, graph-eng (local_1d9fce50); a read-only audit of community skills is forwarded to it when done.
