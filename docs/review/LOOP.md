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

## 2026-11-09, 13:05 (autopilot)

- **What's going on:** The GPU is the bottleneck. One render runs at a time, and both sessions are queued behind it. Phantom Camera is not committed: in battles the lens looked level at the castle across the water instead of down at the clash, a regression the camera session caught. It is timeboxed to 13:25: fixed and filmed by then, or backed out to free director.gd and main.gd. play-feedback holds steps 3 and 4 uncommitted, waiting for its film.
- **Where we're heading:** commit steps 3 and 4 (read the realm), then Court v2 (bet 1).
- **Right way?** The order is right. Risk: a large uncommitted batch, and a low-leverage camera move blocking top move 2. No new fun-bar numbers yet.
- **Verdict:** on course, with one correction already in force (the camera timebox). This turn's supervisor is reviewing play-feedback's uncommitted batch for lost behaviour and UI.md breaches before it lands.

## 2026-11-09, 13:10 (Phantom Camera, second try, backed out)

- **Result:** backed out again. director.gd, main.gd, camera_rig.gd and project.godot are back at HEAD; the add-on is out of `realm/addons`. Nothing of it is committed.
- **What held:** convoy, town and castle shots matched the old camera on film (the castle framed over the gate, the cart followed).
- **What broke:** battle close beats. The beats fired on time (shot log: distance 1.6 to 2.8 every ~3 s), but on the 2.8 takes the lens pointed straight along -Z, level and unaimed, so it looked across the water at the castle. The lens log showed one of the two alternating takes ending up with an identity rotation; the add-on's look-at never turned it.
- **Learned for next time:**
  - The add-on needs its manager registered as an autoload (`PhantomCameraManager`), or every phantom camera fails.
  - Its manager sets `Engine.physics_jitter_fix = 0`; restore the project's value after it loads.
  - Short films weren't the camera. The game ran all its frames, but the movie recorder skips frames while the game window can't draw (covered, another desktop). Check `Engine.get_process_frames()` against the film's frame count before blaming code.
  - The bridge is shared: another session's testing moves the world on (season, place), so judge before and after by behaviour, or film both in one run.
  - Next pass: drive take rotation ourselves (look-at mode off, aim in `_aim`) instead of the add-on's look-at, and re-film the battle first.

## 2026-11-09, 13:25 (autopilot)

- **What's going on:**
  - Phantom Camera is backed out (7498fd0) after the timebox, so the camera files are free.
  - A new review page is published from this account (b0e3927).
  - play-feedback applied the supervisor's fixes: risings get an ultimatum 2 seasons ahead, also when unwatched; no drain before the treasury loads; a cheaper screen-edge shader.
  - That session is idle, no render is running, and its batch has been uncommitted for over an hour.
- **Where we're heading:** land steps 3 and 4 on the review page, then Court v2 and the director start after court (top moves 1 and 2).
- **Right way?** The order is right, but the work is stalled: a big uncommitted batch and an idle builder. No new fun-bar numbers yet.
- **Verdict:** off course on cadence. **Correction:** play-feedback told to land the batch this turn, with review-page versions, then go straight to Court v2. Next turn: check the commit landed.

## 2026-11-09, 13:45 (autopilot)

- **What's going on:**
  - Step 3 landed (6747ff8): house colours on the land at every zoom, the minimap wash and seven ranked sigils.
  - It's on the review page with Claude notes and two marks: contradictory transfer lines over the church, and a map label under the treasury bar.
  - Step 4's film is about halfway; movie capture runs at about a quarter of real time.
- **Where we're heading:** Court v2 (a paused seasonal court, 40 s seasons) and the director touring after court: top moves 1 and 2.
- **Right way?**
  - Fun bar, "I can read the board": ownership now shows at 3 of 3 zooms, up from 0 (play-feedback's count from shots).
  - Off on order: the top-leverage Court v2 was queued behind a standalone flood clip, and code edits were held for every film.
- **Verdict:** off course on sequencing. **Correction:** Court v2 starts the moment step 4 loads. The flood clip and both mark fixes fold into Court v2's single test run (build in batches, test together), and that run is measured for decisions a minute and quiet share. Supervisor this turn: a fresh agent reviewing 6747ff8 and its shots.

## 2026-11-09, 14:05 (autopilot)

- **What's going on:**
  - Step 4 landed (d76ecc9): the name being earned shown live, an ultimatum before any rising, the last act at three-quarters, and the epilogue flight.
  - It's on the review page with notes and three marks: the heading is too small to read, the court card covers the treasury bar, and the HUD stays up during the ending.
  - The supervisor's review of step 3 added two marks: land colour doesn't match the house, and the ladder doesn't rank. It also flagged shader cost.
  - All of it is folded into the Court v2 batch, which play-feedback started after the last turn's correction (the correction took).
- **Where we're heading:** Court v2 (a paused seasonal court, 40 s seasons, the director after court), measured in one test run.
- **Right way?** On the leverage order. Fun bar (play-feedback's counts):
  - "It says who I am": from the end screen only to always on screen.
  - "Failure feels fair": from risings with no warning to an ultimatum every time.
  - "Room to breathe" is still unmeasured (Mac's reign: 3.6 decisions a minute).
- **Verdict:** on course. Next turn: check Court v2's edits are moving and its run is queued.

## 2026-11-09, 14:25 (autopilot)

- **What's going on:**
  - The Court v2 batch is built, with every review mark folded in.
  - Run #1 found two bugs, both fixed: a settled matter could hold the court and the realm shut, and the edge signs had zero size.
  - Run #3 is recording now. Nothing is committed since d76ecc9.
- **Where we're heading:** commit Court v2 with "Room to breathe" measured.
- **Right way?** Yes on content and order. Three runs means fixes are converging, not looping; each run found a new real bug. Watch item: the director didn't tour in run #1, and a probe is checking why.
- **Verdict:** on course. Supervisor this turn: a fresh agent reviewing the uncommitted Court v2 diff for lost behaviour, deadlocks and the pacing arithmetic, before commit.

## 2026-11-09, 14:35 (supervisor findings on Court v2)

- **Deadlocks:**
  - A race in courtSeason can leave the realm paused forever (server.js:893/965).
  - The realm can pause with no card showing (server.js:968/1012).
  - The flood queue can stall (land3d.gd:299).
- **Lost behaviour:**
  - The Hand's crisis push-in is gone.
  - Only one crisis is heard per sitting.
  - Unwatched realms freeze mid-sitting.
  - The petitions setting is half dead.
- **Pacing, by the code's arithmetic:** about 1.7 decisions a minute and 77% quiet. The quiet passes; "≤1 a minute" fails, because a court every 40 s season can't pass it.
- **Course correction:** all of it sent back before commit. Pacing fix within approval: 40 s seasons and "one rising to three" kept, plus a budget so the court sits only when it has something worth hearing (about every other season early, every season at the climax), targeting ≤1 a minute and ≥60% quiet. Flagged on the brief for Mac.
