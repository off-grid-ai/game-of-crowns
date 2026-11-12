# Supervisor state (kept by the top supervisor every turn; Mac never has to remember)

Updated 2026-11-12 ~19:45.

## Waiting on Mac
- Orders a season: one per host (recommended) or one for all hosts (hosts.json ordersPerSeason; today 1 for all).
- The square: keep the r11 openness floor (paving >= 55%) and fill it with life (recommended), or lower the floor and shrink it toward 01-town's packed square.

## Threads (4 + 1 closing)
| Thread | Session | Doing now | Next |
|---|---|---|---|
| Look audit (art set) | local_1116fb7d | Army set LANDED 67c15196 (meshy_knight, cavalry on the horse rig, KayKit knight_v2 deleted). Open: barding, surcoat and plumes are cream on the turntable; they must take the house colour (mask or repaint). Castle (4) and houses (6) made, importing; nature set and cog in progress | Houses (roofs first), trees, ground; judges every frame beside the target |
| Army layer | local_7f29ed9b | Crash RETRACTED (it was the window being closed); told to kill the re-signed Godot copy (it set off a macOS malware box) and drop the lldb runner | 397 replay view faults; battle density (~60 of 600 drawn, lines still); routes coloured by house; ship view (map done 131fd48b) |
| One store | local_dad14ab9 | Land use from Freeciv's worked tiles and specials (scratch copy; land in use 15% to 72%) | Gardens, shores; engine-visual gaps (sync order proof, plague shown, house income shown); ruleset: ships transport-only |
| GoC | local_22c5fa46 | READY 8 click fix (autoplay viewport vs window coords, x1.34): verifying, then land and retake | Step 6 camera and contrast frames (data edits ready, uncommitted); UNPAUSED for the army: rendering the 03-army framing and a close cavalry frame for look audit to judge; then muster, battle and siege with the new army |
| Fire and siege (kept for one fix) | local_7100b3cd | READY 7: the capture chain FAILs at link 3 (probe 2f1e8e1b). The besiegers leave the walls; no assault; the campaign ends when the town changes hands | Fix in bridge hosts.js/campaigns.js (it has the trace), then archive |

## READY
Art step 6 (town camera) landed: people 2.5x larger, house colours. castle_builder.gd: the look audit wires its Meshy castle there; fire-siege keeps walls.gd.

Built: 1-6, 9, 11-15. Reopened: 7 (capture chain fails at link 3), 8 (film click; fix in hand). Open: 10 (a full reign: muster crash, view faults). Look pass: started (owner look audit).

## Decisions and why
- Engines and visuals are one: nothing drawn without an engine fact; the engine first (Mac).
- Ships carry armies and fight nothing (Mac), so the ruleset drops warships and the art set makes one transport hull.
- Four threads, not nine: collisions and idle waits cost more than parallelism gave (Mac).
- Art: stay on Meshy; one style and scale sheet (docs/art/STANDARDS.md); the frame gate (look audit).
- Commits: private index, private message file, HEAD == base.

## Open questions being worked (not Mac's)
- Graph engineering for prompting: its own thread, graph-eng (local_1d9fce50); a read-only audit of community skills is forwarded to it when done.
