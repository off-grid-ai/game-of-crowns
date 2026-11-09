# Review loop: findings

Each turn of the review loop on the review page (`ARTIFACT_URL`) writes what it found here. The main session builds them; the loop itself never edits code.

## 2026-11-07, evening

Judged every screen changed today against GAME_DESIGN.md, UI.md and the look bar (goc-ux), with marks on the page.

| Screen | Gap (rule) | State |
| --- | --- | --- |
| A castle's courtyard (v3) | The fire pit is cold, though the groom stands at it to warm himself (look bar; every action gets a reaction) | Done (v4): seen on film |
| A castle's courtyard (v3) | The garrison drills in village clothes, not its lord's colours | Done (v4): seen on film |
| The King's grain on the road (v2) | The way between two towns with no road runs under a wood's canopy, so the cart is hidden even from above | Done (v3): the track is cut. New gap: near the coast town the camera sits just over one crown and loses the cart |
| A town up close (v2) | The square still reads as a crowd: half are mourners after a realm event | Waits on Mac: small knots spread out, or one gathering |

Checked and holding: the battle (v4: every man in the fight, the dead stay down, legs follow the ground), the siege (v2), the feast, the handover, the muster (clear camera sides), the mid-zoom town.

## 2026-11-07, late

| Screen | Gap (rule) | State |
| --- | --- | --- |
| The King's grain on the road (v3) | Close to the coast town the camera hangs steep over a wood and crowns fill the bottom of the frame (look bar: low oblique) | Open. The sight check isn't the cause (the cart is never hidden); three tries there changed nothing and were undone. Next: stand back and lower over woods. Later: the real game follows a convoy through the director, which already turns to a side with no crowns (`_clear_sight`); only the test steers the camera itself. Making the test use the director put the camera out over the sea, so it was undone; the test needs the director's world set first |

Shipped: 0.6 on GitHub (v0.6-20261107-b39885f, notarised). **0.6 is live on itch** (mac channel, build #2325751, Notarized Developer ID), 8 Nov ~03:20.

## 2026-11-08, morning

| Screen | Gap (rule) | State |
| --- | --- | --- |
| A battle (v4) | At one distance the fight read as a blob of small men (fidelity: battle camera and clash) | Done (v5): close on the blows, then out on the melee, by turns |
| A town up close | Two crowds in one square: the villagers' cap ignored town life's beggars, mob and revellers | Built and filmed: villagers standing there fell from 12 to 8. The square still reads packed: most of it is a weeping gathering not yet traced to its source, which ties to the mourning call |

## 2026-11-08, camera blocks

| Screen | Gap (rule) | State |
| --- | --- | --- |
| Every close view | Roofs, walls and tree crowns right in front of the lens fill the frame (look bar) | Done: Godot's built-in distance fade (pixel dither) on buildings and tree crowns; whatever is within a few metres of the lens dissolves. Filmed on the convoy and a battle; nothing else changed |
| Scene shots | Hand-built camera direction (framing lock, follow, side-picking) | Tried Phantom Camera v0.11.0.4 (MIT): the rig on one Phantom camera, scenes on another. First films broke: the convoy shot dropped to grass level with washed-out colour, and battle beats stopped coming close. Backed out, nothing committed. Needs its own careful pass |

## 2026-11-09, 12:45 (autopilot)

- **What's going on:** Shipped since the plan: cards stay where the King put them (63e3fbd), one court with the Hand's voice on a yearly rhythm (975c71a), and no single event ending a reign (f0ca5dc, the cause of Mac's abrupt "Golden"). A network drop then stopped both building sessions mid-turn, with uncommitted work in ui.gd, minimap.gd, terrain.gd, characters.js and server.js (play-feedback), and in the camera files (Phantom Camera).
- **Where we're heading:** bet 1, the paused court once a season with 40 s seasons, after play-feedback finishes and commits its steps 3 and 4 (house colours, name and arrows, edges). Then the camera commit, which frees director.gd so the director can start after court.
- **Right way?** On the approved order, yes. No fun-bar numbers have been measured since Mac's reign (2.3 petitions a minute, 3.6 decisions a minute). The court is still yearly, so the "room to breathe" line can't move yet.
- **Verdict:** on course, but stalled by the outage. **Correction:** both sessions told to resume where they stopped; the review dataset research resumed. Check next turn that both are working.
