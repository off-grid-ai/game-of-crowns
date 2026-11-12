# Supervisor state (kept by the top supervisor every turn; Mac never has to remember)
- 22:15 Crossing LANDED 7b10e42d; pikemen LANDED 468f3213 (no forward jab yet). Only cypress/flowers/rocks left (look audit), then the one render pass.
- 22:00 Ruling: King's crossing = host walks to nearest reachable coast, crown raises real Freeciv Triremes there (charged Freeciv build cost per hull from the treasury, refused with reason if unaffordable), sails, lands, disbands. Crown-port rule deleted. Why: neither crown town is coastal, so the wanted crossing could never happen; paying keeps it an engine fact.
- 21:55 Nature swap LANDED 44acc885 (Quaternius gone), harness fix 3f7decca. Only asset left: pikemen. Then one render pass (rm /tmp/goc-no-render).
- 21:40 Assets left: One store nature swap + Quaternius delete (nature set 0f5c2752 all six); pikemen round 2 (body + pike prop). Hall/church/guild hall DONE 5347140d. Crossing d70ca994, cleanup c9b7ead8 DONE.
- 21:20 Look audit: nature 4/6 in (c288eb25), oak_a/pine_a judging, then One store swaps + deletes Quaternius. Hall/church/guild hall and two-handed pikemen building. Archer colour DONE (dbe14762).

- 21:10 Mac: no game run until every asset is in. Render pass stopped, /tmp/goc-no-render back. Still missing: nature-set swap (trees, ground cover; 4 pieces imported c288eb25, not wired), hall/church/guild hall, remade pikemen.

Updated 2026-11-12 ~19:45.

## Waiting on Mac
- Nothing.

## Mode (Mac, 20:15)
Code first. No Godot windows or renders until every coding change is done and every new asset is wired. Headless probes only. Then one off-screen render pass. Before it: restart the game bridge (launchctl kickstart -k gui/$(id -u)/com.realm.bridge) so /world carries units' men (a1e42ae0). hosts.js order: fire-siege's siege-hold commit, then One store's per-host orders.

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

## Asset wiring (look audit)
In: Meshy army (67c15196), horse legs (174883d1), castle ck_* and houses hs_* (2dcec252), cog (cbc97f6f), castle banners in house colour, crowd colour. Coming: 3 soldiers remade (they fail army_colour_probe today), nature set. Town walls stay kit until fire-siege closes; then walls' look goes to the look audit. Square fill: GoC. Fields from Freeciv (9dbdf1ec), plague shown (a0778c91).

## Decisions and why
- Remove what we won't use (Mac, 11-12): unused art, the replaced off-family packs, dead code and switches. Delete outright, no archive (Mac: "no fallback, be bold, and ambitious"). Nothing the game loads or a feature uses goes. Owner: One store, after the crown-town fix.
- The King's sea crossing is wanted (Mac: ships move armies). Owner: One store (bridge), after the cleanup.
- Army density (supervisor): keep drawPerMan 0.1 (Mac's fps rule) plus a per-regiment floor (40), so every regiment reads as a block; the plate shows the real men; bigger hosts still look bigger. Reversible in army.json.
- One order per host per season (supervisor, on Mac's "just get this right"): each army acts each season, closer to the WC3 command bar; the season still sets the pace. Reversible in hosts.json.
- The square keeps the r11 openness floor and fills with life to 01-town's density (supervisor): both are Mac's picks, and filling serves both.
- Art stays local in the shared tree; film copies link to it (Mac: "as of now it's ok if it's local").
- Engines and visuals are one: nothing drawn without an engine fact; the engine first (Mac).
- Ships carry armies and fight nothing (Mac), so the ruleset drops warships and the art set makes one transport hull.
- Four threads, not nine: collisions and idle waits cost more than parallelism gave (Mac).
- Art: stay on Meshy; one style and scale sheet (docs/art/STANDARDS.md); the frame gate (look audit).
- Commits: private index, private message file, HEAD == base.

## Open questions being worked (not Mac's)
- Graph engineering for prompting: its own thread, graph-eng (local_1d9fce50); a read-only audit of community skills is forwarded to it when done.
