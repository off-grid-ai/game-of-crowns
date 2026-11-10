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

## 2026-11-09, night (autopilot)

- **Landed:** bets 3–6 (7da38d2). Proven by two test reigns, the interlude on film, and a petition's figure, want and voice on a copy of the save. On the review page with notes and one mark: the camera pad during the telling, already fixed.
- **Built, under film now (the smaller items):**
  - carters and pedlars between neighbouring towns near the view, three at most at a time;
  - clicking a house on the ladder follows its host, or goes to its seat;
  - the great council at two fifths and two thirds of the reign over a war between houses, with each house's stand; commanding peace sends both hosts home.
- **Verdict:** on course. Every approved item is now built; what's left is proof on film and the review page.

## 2026-11-09, night (autopilot)

- **What's going on:**
  - The smaller items are built and fixed after a fresh review: the council's peace (no double charge, a real truce, no repeat war); travellers (land routes only, a horse for carters, varied people); following a house (soldiers only, the biggest stack).
  - Side panels now hide during a telling.
  - The film harness is hardened: it presses Continue until the realm opens and clicks through interludes. The film is rerunning.
- **Verdict:** on course. The harness failures cost two film runs, but each one caught a real flaw (panels showing during an interlude).

## 2026-11-09, night (incident)

- **What happened:** my test script moved its test reign away before the server had switched back to Mac's realm, and the server crash-looped on the missing folder.
- **Fixed:** the server points at The Broken Oath again; it's running and paused.
- **Prevention:** the script now waits for the server to answer before it starts, and only moves a test reign once Mac's realm is confirmed active.
- **Side effect:** The Broken Oath's world moved on during tests (now turn 257). That reign had already ended and been scored.

## 2026-11-09, night (measured reign)

- **Run:** 8.5 minutes of a timed 15-minute reign, after every bet landed. The harness answered the court, read the interludes and followed a house.
- **Room to breathe:** about 0.65 decisions a minute (target ≤1; Mac's reign was 3.6). Once flowing, a sitting took 8–11 s from opening to closing.
  - The realm was held for about half of wall time, but most of that was the harness: two minutes to clear the opening screen, and an unanswerable crisis card. That needs a human run to read properly.
- **Filmed:**
  - A lord's petition card: face, want, and the chips for who each answer helps and hurts.
  - Following a house: the camera rode with a host into a skirmish.
  - The roads.
- **Not yet seen:** the council in the game window (it opened on the server test). The first act's interlude fired; the three ambitions were picked, none met.
- **New mark:** the ground reads as grey static on the coast (a look-pass item).
- **Verdict:** on course. All approved items are built and pushed, with most on the review page.

## 2026-11-09, late (autopilot)

- **Direction:** every approved item is built and pushed; the review page carries all but the council.
- **Left:** a film of the council in the game window (proven on the server already). The coast ground "grey static" mark is a look item for Mac's call, not approved work.
- **Verdict:** on course; nothing approved left to build. Waiting on Mac's review.

## 2026-11-10 (autopilot)

- **Direction (Mac: "it isn't fun; research what makes it fun, then build"):** the engagement model is in GAME_DESIGN.md, and the ten changes are ordered in AUTOPILOT.md.
- **Landed (8e6f8a2):** C, the ladder; A, the Crown's own works; B, marching with odds. Proven on the live bridge: the market rose over two seasons, stood and paid (+40 gold a season); the muster aim was met and rewarded; Lionreach was taken at "about even", with its cause line.
- **Next:**
  - a fresh review of 8e6f8a2;
  - a film of the three loops for the review page;
  - then the plan's items 5 (things the King started, marked on the map), 7 (a seal, sound and reaction on each click) and 8 (named stakes).
- **Verdict:** on course.

## 2026-11-10, later (autopilot)

- **Landed:**
  - b5038b6, the review's fixes: no paying twice, the Hand's emergency builds stay instant, a forecast that matches the outcome, lost towns refunded.
  - e4ecaa4: the ladder goes on past six with aims from the realm, by name; a bigger aim line.
- **Filmed:** the aim under the date, "The King's marketplace rising · 57%", and "March on Lionreach · they'd break before us", then Lionreach taken 14 companies to 4. All on the review page with notes; one mark (the aim was too small), now fixed in the tree.
- **Next, from the review's gaps:**
  - the building site visible in the town itself (not only on the card);
  - a siege to watch: a camp, and a press-or-withdraw choice mid-siege;
  - then juice and named stakes.
- **Verdict:** on course.

## 2026-11-10, noon (autopilot)

- **What's going on:** Mac asked for a CEO report on the game; it's drafted and through two reviewers. No game open, no comments from Mac on the review page.
- **Where we're heading:** AUTOPILOT items 5, 7 and 8 (projects on the map with seasons left, a reaction to every click, named stakes). These are also the report's "quick three".
- **Right way?**
  - Fun-bar numbers unchanged since the last measured run (0.65 decisions a minute).
  - Work follows the approved order: item 5 started this turn.
- **Supervisor (fresh agent) on 5e6613f, the siege terms — three gaps, all fixed this turn:**
  - The herald could arrive with no court to hear him, so the siege was decided first and a late "press" still cost 200 gold. Now the court sits for a herald; the siege waits up to two seasons for the King's word; a ruling on a siege already over is refused with nothing charged.
  - Pressing bought nothing over starving (both capped at 95). Now the bonuses add to the odds (press +20, starve +10, a season later), and each answer shows its own odds, with a warning when starving runs into winter.
  - The tribute came from nowhere. Now it's what the house can pay (up to 150), taken from its own chest, and no tribute is offered if it has under 50.
- **Built:** the King's open matters under the town's name on the map ("The King's marketplace · 2 seasons", "The King's siege · 1 season"), readable from as far as a seat.
- **Verdict:** on course.
- **Film:** the bridge side is proven (Kingsmere's marketplace 2 seasons left; the siege of Lionreach 2 seasons left). The shots don't show the marks: the camera was too close (names fade in under 10) and the Houses panel was open. Refilm next turn, pulled back, panels shut.
- **Incident:** the film script had a syntax error after the shots, so it never put Mac's realm back. Caught at once; The Broken Oath reopened and paused by hand, the test reign moved out.
- **The siege fixes** are syntax-checked; prove them on the live bridge next turn (court sits for the herald, a stale ruling refused, the tribute taken from the house).
- **CEO report** (https://claude.ai/artifact/L7x9ySuXriGXhCAsapAm4k) through both reviewers and republished: a near tie (715 against 710), the quick three, then Mac plays.
- **Mac, mid-turn:** asked for mini goals like "a royal army of 10,000". The ladder already does this; what it lacks is progress ("7 of 12 companies"). Offered, not built.

## 2026-11-10, 12:30 (Mac playing)

- **Mac, playing The Grain Lords:** "almost nothing is making sense". What he hit, and why:
  - "21 of 12 companies" with the aim not met: aims were only checked while the clock ran, and the court or a pause holds it. Now checked every five seconds whatever the clock.
  - "Back Stormhold, the weaker" read wrong against the ledger, where favour sat beside strength. The answer now says it: "(800 men to 2,200)".
  - No face on the Hand's card: only lords' own petitions carried one. The Hand's matters now bring the lord's face.
  - **My film harness was driving the same game window while Mac watched it:** it closed courts, moved the camera and toggled panels. Stopped the moment I saw his reign was the active one. Rule kept from now on: no harness while a game window is open that I didn't open in the same run, and a film run checks the active realm before every step.
- None of this is live until the bridge and game restart; Mac's game is left as it is.
- **Verdict:** off course on trust. The pieces work alone but the whole doesn't read. Next: stop adding, and play one full reign as a person would, listing everything that doesn't make sense.

## 2026-11-10, 13:00 (Mac: "fix these as well", the designers' top 10)

- **Plan:** the five gaps are now in GAME_DESIGN.md (engagement model 11–15) and in AUTOPILOT's order: repetition, grudges for named acts, tension in waves, new questions each act, test with real players.
- **Repetition, measured on Mac's reign (The Grain Lords, 12 matters):** no kind of matter repeated, but **Ysolde Thornvale brought 6 of 12, five sittings running**, because the strongest lord won the yearly turn every year. And two Cecilys and two Ysoldes again: the starting cast was written before the unique-names rule (the baseline has 29 shared first names).
- **Fixed:**
  - A lord who brought one of the last three matters waits their turn; a sitting calls the lords heard longest ago first.
  - Every new reign's cast gets distinct first names, the lords keeping theirs; court, stories and records follow (tested on a copy of the baseline: 0 shared names among 101 living, files still parse).
  - Portraits stand on the card with no box behind them (Mac).
- **Not yet proven live:** the court spread and the clear portraits need a new test reign; Mac is playing.

## 2026-11-10, 13:20 (Mac playing: "functional, not playable or fun")

- **Camera:** the director took the camera after every court and after 90 s idle, mid-move. It now never moves by itself; what's worth seeing is offered (Watch) and goes only on a click. Mac: "overriding user behaviour with system behaviour is amateur".
- **A match offered that couldn't happen:** "Wed them" showed with no one to wed, then was refused. Every match offer now checks for a real pair first.
- **Ultimatum cause:** named "the realm's mood at your crowning". It now names what the King did and when ("You marched the royal host on our walls, in the autumn of 309"), or says the crown has done nothing for them.
- **Verdict:** off course. Mac's whole-game read: functional, not playable, not fun. Features keep landing on a game that doesn't yet hold together moment to moment. Stop features; fix playability first, from a person's play, then rethink the minute-to-minute loop with Mac.

## 2026-11-10, 13:40 (autopilot)

- **What's going on:** Mac is playing (game window open); nothing to take or restart. Seven playability fixes from his notes are pushed, none yet seen live.
- **Where we're heading:** playability first; AUTOPILOT now says no new features until Mac picks how (a friction pass, a core-loop rethink, or both).
- **Right way?** Course corrected: the designers' list (grudges, tension waves, act questions) is parked behind playability.
- **Verdict:** on the corrected course; waiting on Mac's call and his game.

## 2026-11-10, 12:46 (autopilot)

- **What's going on:** the friction run is playing (frame 16 of ~80). Mac approved: friction fixes first, then two swaps onto proven blocks (townsfolk on LimboAI, one cart scene; the cart is done). The engineering rules now gate every change on "who already solved this?".
- **Already seen at frame 12, before the full review:**
  - The ledger and chronicle open by default and box in half the world.
  - The ledger's footer says "the realm is at peace with itself" while four houses show WAR.
  - The aim counts companies, the ledger counts men (5 companies = "1,000 men").
- **Verdict:** on the corrected course: playability first, proven blocks only.

## 2026-11-10, 12:55 (autopilot)

- **Friction run, frame 25:** the first act's telling sat on screen for four frames (over a minute) with the clock held: no visible way to go on ("click to continue" is nowhere). The harness's click missed it too. Closed by hand to keep the run going; logged as friction.
- **Pace:** 14 minutes of wall time covered only 3 seasons of the reign; held clocks (court, telling) dominate.
- **Verdict:** on the corrected course; collecting the list.

## 2026-11-10, 13:20 (friction pass)

- **Review of the 50-frame run (fresh agent as a demanding player), top frictions and what's done:**
  1. The act's telling held the game six minutes with no way on → Continue button, any key, closes itself after 15 s.
  2. Panels piled on the court card → the court is modal; ledger and chronicle step aside.
  3. Text contradicting the state ("at peace" amid wars) → fixed for the ledger line. Still open: a truce shown while besieging, and a quote denying the treachery it heads.
  4. The goal not linked to its means → click the aim and its town's card opens.
  5. Two units for soldiers → men everywhere.
  6. Cut-off names at the screen edge → whole or hidden.
  7. "Later" against "Close the court" → each says what it does.
- **Still open, in order:** card template slips ("Stormhold and Stormhold"), unlabelled numbers ("▼ 13"), leftover floating text, big events weighted like small ones, and dead air between courts (the core-loop question for Mac).
- **Proof:** a check reign is running with these live; frames next turn.

## 2026-11-10, 13:30 (autopilot)

- **Seen live in the check reign:**
  - "Continue" on the act's telling; the reign moved on a frame later (it had held six minutes before).
  - "1,000 of 2,400 men" under the aim.
  - "The King's granary · 1 season" over Kingsmere.
  - The UI at 1600 x 920 now fits: the treasury bar shows (it was hidden before).
- **Caught live and fixed:** the court hid the ledger and chronicle and didn't bring them back. Now the court card is simply drawn on top (the modal pattern).
- **Also fixed:**
  - Story titles name each person's own family ("Stormhold and Dale").
  - The favour drift reads "54 ▼13".
- **Verdict:** on course: friction first, each fix seen in a game.

## 2026-11-10, 13:36 (autopilot)

- **What's going on:** a test reign is filming the lords' deeds as scenes. Since last turn:
  - all story and court text rewritten in plain speech (27 stories, 34 cards, checked field by field);
  - lords' deeds play existing scenes;
  - minimap pings, an edge arrow and Space for the latest news;
  - the screen opens on the world; moods are words.
- **Checked a research claim:** "seasons forced to 20 s" is not true now. The live bridge reports 40 s seasons (server.js sets 40 on load; the 20 is only a default before a realm loads).
- **Direction:** Mac's rules hold. The camera never moves by itself, only what the world can show gets told, and proven patterns are used (RTS news, modal court, quest-log aim).
- **Verdict:** on course. Next: proof frames from the running reign, then the townsfolk on LimboAI.
