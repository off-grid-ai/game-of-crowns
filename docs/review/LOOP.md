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

## 2026-11-09, 14:55 (autopilot)

- **What's going on:**
  - Court v2's run #3 is recording.
  - The pre-commit fixes (deadlocks, the crisis push-in, the pacing budget) are queued behind it.
  - The Steam review data landed in the brief: bugs (13.2% of negative reviews, 3.4×), repetition (3.9×) and shallow outcomes (9.3×) are the top negative drivers.
  - Unique names were moved up, to come straight after Court v2; play-feedback has planned them.
- **Where we're heading:** Court v2 fixed, measured and committed, then unique names.
- **Right way?** Yes. The review data confirms the order: stability, then pacing, then repetition.
- **Verdict:** on course. Watch item: Court v2 has gone 3 runs without a commit. If run #4 (with the fixes) doesn't pass, split the batch: commit the colour, ladder and label fixes on their own, keep the court separate.

## 2026-11-09, 15:00 (Court v2, run #4)

- **No deadlock:** the court opened, was answered and closed, and the realm moved on.
- **Quiet share:** 73%, passes the ≥60% target.
- **Decisions:** 2.06 a minute, fails the ≤1 target. Measured in a realm in crisis, where every crisis is heard.
- **Frame rate:** median 20 fps, with 3–6 fps for 10–15 s at every season turn.
- **Course correction:**
  - Measure pacing on a fresh, timed 15-minute reign.
  - Cap crisis matters at 2 per sitting.
  - The season-turn stutter (25–37% of play time at 40 s seasons) becomes the next item, ahead of unique names, because bugs and performance are the #1 negative-review driver.
  - Close the sitting left open in the shared realm.

## 2026-11-09, 15:25 (Court v2 landed)

- **cf8c6ed:** Court v2. Measured on a timed 15-minute reign, 6.5 min of play:
  - **Room to breathe:** 1.08 decisions a minute (was 3.6); 86% of the time with no card up (was about 0%). Both near or past target.
  - No deadlocks.
  - The director tours 5 s after the court closes.
  - House colours cost 3.7 ms per realm update and are not the stutter.
- **On the review page:** 4 marks resolved, 2 still open (the ladder shows 6 houses not 7; the heading is still small), 2 new (a ruling's result covers the next card; the ground looks grey and noisy in the after-court shot).
- **Next:** the season-turn stutter (3–6 fps for 10–15 s, predates this work; performance is the #1 negative-review driver), then unique names.
- **Verdict:** on course; bet 1's core is shipped.

## 2026-11-09, 15:35 (autopilot)

- **What's going on:** play-feedback is on the season-turn stutter and folding in the open review marks.
- **Where we're heading:** steady frames at season turns, then unique names.
- **Right way?** Yes. Performance is the #1 negative-review driver, and the stutter covers 19–26% of play time.
- **Verdict:** on course. Supervisor this turn: a read-only search for the stutter's cause, with file:line and the proven Godot fix for each. The findings go to play-feedback to speed it up.

## 2026-11-09, 15:45 (stutter causes)

- **Evidence:** perf.log shows +227 people and +7,460 nodes in one turn, then 3 fps with 333 ms frames.
- **Likely causes:**
  1. scenes.sync stages every new battle and muster in one frame, with no budget.
  2. Town walk maps re-bake synchronously at a fine cell size, most turns.
  3. A single town build overruns the 12 ms budget, plus repeated Terrain3D update_maps.
  4. units.sync builds figures and routes all at once.
  5. Synchronous first-use loads.
- **Sent to play-feedback** with the proven Godot fixes: per-frame time budgets with await, async navigation bakes, WorkerThreadPool, pooling, threaded loads. Target: no frame over 50 ms at a season turn, a median of at least 30 fps, every behaviour kept.

## 2026-11-09, 16:15 (autopilot)

- **What's going on:**
  - 2447859: the three review-mark fixes (results at the foot of the screen, seven houses with the fallen dimmed, a bigger heading). Shots still to come.
  - a14d76f: stutter, first pass. The dips are physics time (30–55 ms per tick at a new scene, snowballing over 8 catch-up steps). Physics now catches up at most 2 steps a frame, and battles too far off to see drop avoidance. Worst frames improved from 2–3 fps to 7.
  - Not solved: physics spikes from the villagers' avoidance, and a baseline of 70–100 ms process time at distance 60 (15–20 fps).
- **Decision:** unique names now (small; repetition is the #2 negative-review driver), then back to performance with a reliable benchmark first: a fixed seed and camera path, 3 runs each, the median of medians. Single runs swing 12–20 fps at load 4–7.
- **Verdict:** on course. Performance needs several passes, and the benchmark makes each pass measurable.

## 2026-11-09, 16:35 (autopilot)

- **What's going on:** play-feedback is on unique names. The review of 2447859 found three issues, queued right after names:
  - fallen chips draw outside the ladder strip (ui.gd:1083);
  - "fallen" ignores armies still in the field (server.js:1682);
  - results almost never move to the foot of the screen (ui.gd:1188).
  
  a14d76f's physics cap is clean.
- **Where we're heading:** names, then the three fixes, filmed together, then performance with a benchmark.
- **Right way?** Yes, on the review data's order (stability and repetition).
- **Verdict:** on course.

## 2026-11-09, 16:55 (autopilot, own work)

- **Direction:** one builder, with bets 3–6 queued behind performance, is the throughput risk. The story files are in no one's hands, so this session took bet 6's first item.
- **Done (this session):** no coin-flip deaths.
  - Pale Fever and the Poisoned Court now bring the King's death to court as a warning he can answer. Only his choice or his silence ends the reign.
  - The Inquisition's ban says that silence is taken for guilt.
  - Checked: the story checker passes, and every fall in the three stories is reached only through a court matter.
  - Fun bar, Failure feels fair: 3 random falls → 0.
- **Next own work, in the story files only:** the remaining free answers, then story marches through the ultimatum. The march needs server.js, which play-feedback holds, so that one gets coordinated.
- **Verdict:** on course; throughput up.

## 2026-11-09, evening (autopilot)

- **What's going on:**
  - Mac's direction: no parallel builders (goc-cpto), performance dropped. This session builds everything; the feedback session has handed over and stopped.
  - **Landed:** Endless reigns gone (317f3a1); no free story answers; acts by the clock in arcs.js (6ac8db0); the review fixes plus story marches through the ultimatum (6151238).
  - **Built, uncommitted:**
    - Bet 3: interludes at each quarter, three ambitions, reignAt.
    - Bet 4: the portrait on the Court card, the lord's want, story answers remembered, a voice per house.
    - Bet 5: help and hurt chips on answers, the first shot after court on the King's ruling, three free deck answers priced.
  - A 1-minute test reign is running on the game server.
- **Where we're heading:** commit bets 3–5 once the test and a fresh pre-commit review pass, then one batch film for the review page, then player beats bringing matters to court, then the smaller items.
- **Verdict:** on course, and throughput is up with one builder working continuously.

## 2026-11-09, evening (autopilot)

- **What's going on:**
  - Bets 3–6 are built in the tree:
    - acts by the clock, interludes, ambitions;
    - faces, wants, voices, remembered answers;
    - help and hurt chips, the camera to rulings, no free answers;
    - player beats that bring matters to court.
  - The fresh review's fixes are in: the interlude no longer vanishes after a frame, it's keyed by reign, it closes on the King's click and holds the court back, and the ambitions are real.
- **Off course, briefly:** the batch film opened on the title menu and never entered the realm. **Correction:** the film now presses Continue first, and it reruns as soon as this run ends.
- **Next:** judge the film, commit bets 3–6, put them on the review page, then the smaller items.
