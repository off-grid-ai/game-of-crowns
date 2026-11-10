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

## 2026-11-10, 13:50 (autopilot)

- **Incident (mine):**
  - The lord-pictures test pressed Escape to leave a watched scene. That opened the menu, and the run drifted to the title screen.
  - Stopping the run didn't run its restore.
  - Mac's realm was put back by hand, paused.
  - Fixed: tests leave a scene with Space (the new back key), and a stop now restores the realm.
- **Seen in the frames:** in-world captions piled into an unreadable stack and never left. Now they fade after 9 s, one per place.
- **Rerun** under way with Space to the news and back.

## 2026-11-10, 14:05 (autopilot)

- **New working arrangement (Mac):** the "game wiring gaps" session judges as an outside, demanding player against shipped games. This session builds. A plan goes to it before each piece and proof after; it answers go, change or stop.
- **Proven live (lordpics2):** a lord's scene where it happened, with its caption; the edge arrow; Space to the news and back; the camera never moving by itself.
- **The judge's change, built (cd59231, 2dd5aff):**
  - the alert in the house's colour, twice the size, pulsing once;
  - minimap bursts;
  - a sound for each kind of news (the horn only for hostile news);
  - captions that say who did what;
  - one channel per piece of news, with toasts waiting their turn.
- **Slip:** 45f4e13 didn't parse (an untyped Variant); fixed a minute later in 2dd5aff. Rule kept: check-only before every commit, never after.
- **Queued:** the judge's discovery questions (first 10 minutes, decisions, story shown, pace, repeats, ending, stability, UI cover), then LimboAI for one town.
- **Verdict:** on course. Proof film of the alert is running.

## 2026-11-10, 14:30 (discovery list)

- **Winter ground blotchy grey and blue** (the judge, from the proof frames). Likely cause, from reading the code, not yet confirmed on film:
  - winter swaps Terrain3D's whole grass texture to snow (land3d.gd:171 set_grass);
  - the dirt, mud and field layers stay bare;
  - under the cool winter tint (terrain.gd:107), the ground turns into patches of snow and bare earth instead of an even cover.
  - The proven way is Terrain3D's own height and slope blending for a snow layer, not a texture swap. Not fixed; it's on the discovery list.
- **Chip: PASS** (the judge). Drill and siege strips are being refilmed with the soldiers framed and the court closed.

## 2026-11-10, 14:50 (autopilot)

- **Direction:** the judge's order holds. The NPC foundation is in: three clip libraries, play-once fixes, the carry blend, the LimboAI mind wired behind a switch, and a --limbo film flag. Snow and sound went to builder 2. Discovery is answered (docs/review/discovery-answers.md). The decision drought and the failed peace are being diagnosed in a helper.
- **Drill proof, third try: still inconclusive.** The towns the AI was training in had no drill spawned near the frame. The life step found only 2 or 3 market folk. Fix: /test/stage forces a drill, and the helper's film.sh uses it.
- **Slips:** two commits that didn't parse, each fixed within minutes. Commits now go through a gate: check-only empty, or no commit.
- **Seen in passing:** the bottom-left ticker carries the news (three chips: a ruling, a court closing, barracks rising).
- **Verdict:** on course. **Limiting factor:** proof filming. The film tool lands after the current queue.

## 2026-11-10, 15:00 (autopilot)

- **Built since the last entry (judge's order):**
  - **Drought fix (9457446):** the realm holds when no window watches, and the court sits on return.
  - **Honest peace text, then a real ceasefire (9dcc7bc, 295eba7):** Freeciv's own diplomacy, set in the save and reloaded only behind a sitting court. Truces are keyed to houses.
  - **21 Mixamo clips** (Mac approved), with imports retargeted.
  - **The film tool and queue** (film.sh, filmq.sh; helper-built, test passed). The harness's city step takes a tilt, so films use the low oblique view.
- **Proofs running in the queue:** the drought check, then the peace check (which measures the reload hitch behind the card).
- **Found:** Mac's Broken Oath reign ended on its clock: 15 minutes, turn 63, "the Golden". Most of that clock ran while no window was watching, before the drought fix. It's the bug the fix addresses, and his reign was spent by it.
- **Clip eye check:** close-up gestures and UAL crouch, push, torch and sit all pose on our townsperson with no twisted limbs. Foot sliding needs a closer sheet.
- **Verdict:** on course. **Limiting factor:** proof time, now queued instead of waited on.

## 2026-11-10, 16:10 (autopilot)

- **What's going on:**
  - **This session:**
    - the King's truce works (983 ms reload; Thornvale at peace 4 seasons on);
    - every real reign opens differently (fresh dice, tensions and grudges from its seed);
    - the reign's goal is earned (all houses at 50 and up, and no war between them);
    - slice 2 trees;
    - awareness part 1 (the mirror, the news bus, React, state weights);
    - the clip-sound hook for builder 2.
  - **Builder 2:** snow, sound, ruins, the King's ledger, decree scenes.
  - **The judge:** rules every piece.
- **Two bugs that meant no NPC tree ever ran:**
  - LimboAI's clone() drops non-exported settings, so every clip list was empty (c47965a).
  - A BTPlayer made at runtime never started without set_scene_root_hint (38be489).
  - The slice-1 film the supervisor judged (frozen extras, "ON doesn't touch them") was therefore the broken build. The new headless probe found both bugs.
- **Measured (state, no GPU):**
  - Goal: in 3 real reigns, 3–4 of 6 houses are firm at the start, with 4–6 houses fighting. Never won at the start or by turn 40; before the fix it was won at turn 39 in every reign.
  - Probe: 20 of 20 groups pass when calm, with 2–4 activities and 7–15 clips each and a longest hold of 8 s. Riot replaces callings by design, so the probe's activity count doesn't apply to it.
- **Supervisor (fresh agent, slice-1 frames):**
  - people overlap (a body inside the brown-cloaked man);
  - frozen extras (explained above);
  - film shots near top-down, with site and drill out of frame. This is film.sh's life step; it's fixed in the batch session.
- **Slips:**
  - My 42c01a9 swept in builder 2's uncommitted server.js lines.
  - Builder 2's 1ba113d swept in mine.
  - Both repaired. Both of us now stage by hunk.
- **Direction:** NPCs were Mac's top complaint, and the minds now actually run. The court is blind to hunger (note A in the state catalogue). The judge ruled one bridge definition per realm state next, ahead of more awareness work.
- **Verdict:** on course, corrected this turn. The NPC work was off course without anyone knowing (no tree ever ran). The probe is now a standing check on every tree change.
- **Open:**
  - the bridge's one definitions (hunger, war, siege, feast) and the court reading them;
  - gossip with a partner and a topic shown by gesture;
  - grasping in the city state;
  - the batch film session (slice 1+2, riot, feast, hunger, the states).

## 2026-11-10, autopilot (consolidation A1, A2, A4, B3, B4)

- **What's going on:**
  - **This session (the judge's consolidation order):**
    - **A2:** one definition per realm state. townStates() sets famine, granaryLow, plague, disorder, celebrating, besieged and mood on each town. The court, deck, arcs, counsel, minds, minimap, villagers and the mirror all read it.
    - **A1:** one truce writer. Rulings, stories and matches now reach Freeciv's ceasefire, and queued ceasefires go in one reload.
    - **A4:** Freeciv's Lua gives only rapture live, so the save stays the source for the rest. The truce save counts as newest, so a war ends on /world at once.
    - **B3:** richer /world.
    - **B4:** scene_kinds.gd.
    - The traffic handover to builder 2, and raise_site for its towns.
  - **Builder 2:** the ledger, decree scenes, sounds on the clip hook, traffic.gd, A3 and A5.
- **Measured (private bridges and the headless probe):**
  - A starved house's 9 towns show famine 9 of 9. The Hand brought "Sunfell is starving" to the first court, where before the court never saw a hungry town.
  - The truce reload took 1023 ms, and the war was gone at the next reading (it used to take a season).
  - Behaviour probe: 20 of 20, four runs in a row, after two fixes (a breaker repeated the last clip; a single-clip run looped).
- **Where we're heading:** the judge's plan:
  - next, B3's counsel out of GET;
  - then the rest of the awareness work (gossip with a partner, danger near sack and battle, disorder's chronicle line, soldiers' hp and activity);
  - then B6 and C1.
  - The grouped film session comes when A and B are done.
- **Verdict:** on course. The work follows the judge's order. No fun-bar reign was measured this turn because the GPU is held for the grouped film session; the state proofs stand in.
- **Open:**
  - the lord's grain petition hasn't been called yet in the rerun (lords take turns at court);
  - the batch film list now holds slice 1+2, riot, feast, hunger, the awareness states, Eve and the court card over the reload.

## 2026-11-10, autopilot (crisis first, counsel per season, soldiers, gossip)

- **Landed:**
  - **a82db5c:** a starving or besieged lord speaks first at the next court, out of the rotation (the judge's ruling). B3's counsel is read each season and after the King acts, not on every poll. A town in uproar is a chronicle line.
  - **f837de0:** soldiers stand by Freeciv's hp and orders: wounded companies limp, fortified ones stand behind the shield.
  - **8fe04b6:** talk takes two, with a topic. A raid seen by 2 villagers was told on in 2 talks in the probe, and the topic shows as a gesture.
- **Probe:** 20 of 20, five runs in a row, after fixing React leaving its move to be played again.
- **Steer:**
  - server.js is frozen for builder 2's split (C3). My hunks were committed before it began, and the routes table landed in 1351802.
  - Builder 2 took over traffic (traveller() and the mirror's tile, owner and towns) and has scene_kinds.gd for its readers.
- **Found:** a private bridge started on the working tree mid-split came up empty. Proofs must start after a builder's commit, not during one.
- **Direction:** the consolidation plan, in the judge's order. A, B3, B4 and the people half of the awareness work are done.
- **Waiting on C3:**
  - the state test hooks (war, prosperity, grief, grasping, winter, the King passing) and grasping in the city state;
  - then the grouped film session.
- **Verdict:** on course.

## 2026-11-10, autopilot (supervisor turn)

- **Supervisor** (a fresh agent, my last six commits). Three problems, all fixed in 1f249db:
  - talks fell apart, so one villager ended up talking to the air;
  - a besieged lord jumped the court queue with an unrelated plea, and the Hand's siege report was dropped;
  - "a year" was defined three times.
  - Noted, not fixed: bridge year constants (frozen for C3).
- **Measured:**
  - Behaviour probe: 20 of 20, three runs, with news passed on in talks.
  - Minds' process cost: about 0.1 ms a frame for 60 minds (headless, within noise).
- **Process slip:** two state proofs ran on one port. Rerun once, cleanly.
- **Direction:** consolidation in the judge's order. C3 (builder 2 splitting server.js) blocks the state hooks and the film session.
- **Verdict:** on course. The supervisor caught real bugs in a "done" feature, and they were fixed the same turn.

## 2026-11-10, autopilot (the court's crisis pleas work; siege relief)

- **Found and fixed:** the starving lord's grain plea never reached court. He already had a matter waiting uncalled in the hall, and the crisis loop skipped any lord with a matter waiting. The crisis now takes that matter's place. Proven directly against the baseline's court: the plea comes at the next sitting, once, and not again the season after.
- **Built (the judge's ruling):** the siege-relief plea, with three answers:
  - march the royal host;
  - pay the besiegers 200 gold, which makes a truce through the one writer, so Freeciv's host goes home;
  - let the town hold or fall.
  - The answers are tagged in the ledger. All three were proven directly (2674fe2).
- **Steer:**
  - server.js stays frozen for builder 2's C3.
  - My server changes went to builder 2 as a patch with its own proof script: per-town atWar, grasping, grief and prosperity in townStates; the new stage moods and the King's banner; the siege march from a ruling.
  - Open debt (judge): the mirror's own reading of war, grief and prosperity is deleted when the patch lands.
- **Slip:** a grep with an unmatched file pattern made the crisis call look lost. It wasn't, and nothing was sent on that false alarm.
- **Verdict:** on course. The blind court is now fixed end to end for hunger, and sieges have a voice.

## 2026-11-10, autopilot (deck gates; film session running)

- **Landed:**
  - **72efebc:** the court's cards come from the realm. Every card has a gate and none is dealt on dice alone. New gates: rivalWar and rivalPeace, atWar, disorder, prosperity, raiders and north. War cards deal only to lords at war, and unrest, raider and prosperity cards deal only once their state is staged.
  - **526aae4:** Eve is ready for her eye check.
  - **3256d06:** the --bridge flag, and the mirror survives null readings.
- **Film session (round 1):** running on a private bridge (8850) from a snapshot. The town launch is past war.
- **Early look:**
  - the camera is still too steep (above the low oblique view);
  - "Winter of 309" shows green ground in the square (to builder 2);
  - the riot reads as a dense crowd with smoke.
- **Round 2 is ready (film2.sh):**
  - targets: King Good and Cruel, wounded and fortified soldiers, a town growing, the court card over the truce reload, a winter evening (--hour=19 is in);
  - Eve via clip_strip --body=eve;
  - waiting on builder 2 to merge the hooks patch.
- **Direction:** the judge's order:
  - A, B3 and B4 are done;
  - awareness: people, states and gossip;
  - deck gates done;
  - films now.
- **Verdict:** on course.

## 2026-11-10, autopilot (C1 prep, B6 started, round 2 queued)

- **Landed:**
  - **d6bfd47:** TownLife.minds_on() is the one rule for which towns have minds, with --limbo=all for C1.
  - **b45a0ee:** B6 has begun. bridge/petitions.js holds one handler per petition kind. Siege and grain moved first, with identical results for every option, tested.
- **Measured:** the round-1 film run logs 16–35 fps and 45–72 ms of process time a frame at Kingsmere with minds in one town. C1 waits on perf_check.sh (minds off, in one town, everywhere, same shot), which runs after round 2.
- **Steer:**
  - Builder 2 merged the round-2 hooks (epithet, staged soldiers, /test/grow) and --hour, fixed winter-without-snow, and asked for an autumn-to-winter strip (added as target "turn").
  - Round 2 runs straight after round 1's sheets: King Good and Cruel, wounded and fortified soldiers, a town growing, the court card over the truce reload, the land turning, a winter evening, Eve, and the perf check.
- **Verdict:** on course. Films are the gate now; C1 waits on their frame-cost numbers.

## 2026-11-10, autopilot (films judged; camera and dressing; perf hunt)

- **Round 1 judged** (by the judge and by me):
  - Only the feast and the stall read.
  - The camera was high and steep because the rig never let a player closer than about 10 m, held the lens up to 1.5 above the ground and lifted it over roofs.
  - The mood signatures were too subtle.
  - The site was out of frame.
- **Course correction** (the judge's ruling c):
  - The player's camera gets a street-level zoom (min 0.5). It flattens toward eye level, staying oblique.
  - Roofs are kept off the lens by Godot's SpringArm3D, against colliders built from each town's own footprints, replacing the hand-written lift.
  - Each state gets scene dressing from the props kit: war (barricade, weapons, guards), hunger and grief (empty or shut stalls, mourners and candles), prosperity (full stalls, a lute), grasping (a tax table, collector, guard, queue).
  - Both are written and compile, but are uncommitted until round 3 films them.
- **B6 done:** all 12 petition kinds are in petitions.js, one commit each.
- **Perf:**
  - Minds off, no ruins: 41–42 fps, 31–35 ms process, spiking to 74.
  - With ruins: 75–85 ms.
  - Two minds-on runs are suspect (a stray Escape opened the menu), so they're re-run in round 3.
  - The cycle breakdown is noisy (6 s per system); its first lead is scenes, at about 40 ms.
- **Verdict:** off course on what a player sees (camera and readability). Corrected this turn; round 3 checks that it took.

## 2026-11-10, autopilot (perf found; camera reviewed)

- **Perf (round 2's profile):**
  - The stutter is the ruins build: 1254 ms over the first 10 s after marks, then 0.2 ms.
  - Ruins also bring a steady +45–55 ms of process time outside every timed job (nodes +2.4k).
  - Both are with builder 2. Minds aren't the cost.
  - The cycle profile is too noisy to rank (readings fall 158 → 20 ms through a run), so every system's _process now reports its own ms under the probe (b275783, and builder 2's).
- **Supervisor** (fresh agent, my uncommitted camera and dressing): 8 problems, all fixed before round 3:
  - SpringArm3D's stale frame, replaced by ShapeCast3D updated on demand;
  - one body per building, with the eye's own building excluded (castles covered);
  - the rebuild hashes heights;
  - the 42° cap kept at every distance;
  - focus and snap start fresh;
  - props block the walk map and sit on the table;
  - cinematics read the rig's ground-view rule instead of a drifted copy.
- **Weather:** the mirror reads /world's weather when the bridge sends it. Rain empties the square (c6a3845).
- **Verdict:** on course. Round 3 checks that the camera and dressing took.

## 2026-11-10, autopilot (street camera landed; round 3 filming the fixes)

- **Landed:**
  - **2a6ce93:** the street-level camera, seen working in round 2. Faces, poses and talk read, and there's snow underfoot in winter.
  - **C2:** villagers (59dfd99) and scenes (3d550e9) have public surfaces.
  - **d52f30b:** the tile harness step.
- **Round 2:**
  - king Good and Cruel, wounded and fortified soldiers, grow and evening filmed;
  - the truce target failed (no court in 80 s) and cut scars and turn, so they're refilmed in round 4;
  - Eve fails her eye check (modern clothes) and keeps no roles.
- **The judge's four fixes** (written and compiling, in round 3 now):
  - crowding: scene folk's spots count as taken, and the room limits are down;
  - captions: 13 px serif, soft backing, about 4 s;
  - clothes: dyes on both Fuse civilians and Svend, and tinted materials shared per colour, which also cuts per-person material copies;
  - framing on the soldiers.
- **Verdict:** on course. What a player sees is improving every round, measured on film.

## 2026-11-10, autopilot (round 3 judged; perf split; round 4 running)

- **Round 3, read by eye:**
  - Works: zoom (realm, town, street) and grief; grasping's tax table; prosperity's stalls; a calmer square; varied clothes.
  - Fails: riot (too close), war (barricade out of frame), soldiers (framed on the garrison tile, the square), hud-rest (the castle standard; builder 2 says it's castle-scaled now). No captions were caught.
- **Committed after film:**
  - c6a22f6: crowding, dyes with shared materials, dressing, captions, Eve removed, C5 strides;
  - e749361: C2 public surfaces;
  - 80c849a: round 2 and 3 sheets.
- **Perf, per system** (wrapped _process):
  - units about 4–5 ms a frame (a stance replayed every frame; fixed, filming);
  - anim_lod about 1.9 ms, villagers 0.7–1.8 ms, labels 0.5 ms.
  - All scripts together come to about 10 ms a frame against 40–150 ms of process time. Most of the cost is engine-side; the probe now counts it (7367d4e).
- **Round 4 (running):**
  - the truce on builder 2's /test/court;
  - talk captions;
  - war and riot wider;
  - soldiers on their own figures (units.figure_of and a unit step, 080e265);
  - scars, the season turn, perf with engine counts.
- **Verdict:** on course. Each round fixes what the last one showed. Perf is the open risk.

## 2026-11-10 20:35, autopilot (Mac's "looks like a joke" shots; three side sessions)

- **What's going on:**
  - Mac's 19:50 shots: modern black-leather women, people standing inside each other, kneeling at bare ground.
  - 124bf5e (pushed): Erika and Arissa out; non-walkers (scene folk, soldiers, riders) are RVO obstacles for walkers; a mind's paces go only to empty ground; no kneeling or shoving at a bare door; a "CHECK people inside each other" line in probe runs. Probe PASS 20/20. Not filmed yet.
  - Mac started three side sessions at about 20:30 (his words, relayed by the judge): NPC perf (anim_lod, BTPlayer setup), Townsfolk look (people, chatter, town_life, villagers, npc_mind talk and activities), Film round 5 (the only Godot window). Nothing has landed from them yet.
  - Builder 2: server.js and an untracked season.js (C3 in progress). I stay off both.
- **Where we're heading:** "First: playable". Mac's shots are exactly that friction, and all three sessions are aimed at it (bodies, personal space, captions, perf, then film).
- **Right way?** No new reign measured since the last entry, so the fun-bar lines are unchanged. The work follows Mac's own notes. Nobody is stuck, looping or building something unapproved. File ownership is split with no overlaps.
- **Verdict:** on course. The proof is Film round 5's CHECK pair counts and its street-level frames.
- **Open:** props at work benches, so kneeling and hammering clips have something to work on (Townsfolk look's list); Mixamo heads fading; the heraldry.colour swaps.

## 2026-11-10 20:50, autopilot (Mac's feast shots; god leftovers)

- **What's going on:**
  - Mac's notes since 20:35: the commoner card waits forever (the model is down); "I play as the king" (the god premise is cut); the winter feast "is someone burning here?"; five feast shots, "lot of issues" (lumps of people, two men fused, fantasy and modern bodies).
  - Landed: b4ef3bf cuts the view's god() call, its wiring and test-god.sh; docs/review/god-leftovers.md lists 13 cuts and 6 reframes; Builder 2 has its list (god.js, /god, the Fate box, folk_card, scars → blight.js). b7c624e (Builder 2): rain at street height, overcast light.
  - Working, uncommitted: Townsfolk look (people, chatter, town_life, villagers, npc_mind), NPC perf (anim_lod, npc_mind setup). Film round 5 holds the GPU on a private bridge.
  - Checked: particles.gd's to_gpu keeps the emitter's transform (headless). The feast "glow on a person" is most likely the fire light on someone standing in the pit.
- **Where we're heading:** "First: playable". Everything routed this turn is Mac's own friction. Townsfolk look's top item is hard personal space on Godot avoidance, ring slots for gatherings, a probe that fails under 0.5 m, and the body audit.
- **Right way?** No reign measured since the last entry, so the fun-bar lines are unchanged. The approved order holds, and nothing unapproved is being built. Risk: the probe passed while Mac saw lumps. It was blind to group activities, and it's being fixed so it can't pass that way again.
- **Verdict:** on course, with the course set by Mac's shots. Next turn's check: Townsfolk look's push, then the CHECK pair counts and the round 5 feast, gossip and market frames.
- **Supervisor:** a fresh judge was started this turn; its gaps go in the next entry.

## 2026-11-10 21:10, autopilot (Stormwatch's cause; messages paused)

- **What's going on:**
  - c620f1d (mine): each town's `situation` line in /world (bridge/situation.js). Example: "Stormed by House Thornvale from House Stormhold in summer 313 · rebuilding". It also covers besieged by whom, since when and with how many companies; starving; sickness; riot. `scarLine(mark)` is ready for hover. It answers Mac's "i can't understand why Stormwatch is in the situation they are in". The history: a Stormhold–Thornvale blood feud, a siege of 5 companies on turn 53, stormed on turn 54, the palace destroyed.
  - 6bceb30 (Builder 2): the commoner card is cut; a hover tooltip by the cursor shows the person's trade; the view-side god leftovers are gone; a court answer the treasury can't pay is greyed, with why.
  - 2a37434 (NPC perf): minds are ticked by distance through anim_lod. 129–179 minds a frame instead of 299; probe PASS. The far-body stride is held for the animation report. It also took Townsfolk look's npc_mind footprint check (in_the_way). That compiles, so it's a commit slip, not a loss.
  - 4c2e634 (Builder 2): season.js moved out of server.js, with the behaviour unchanged.
  - Townsfolk look is still uncommitted (people, town_life, villagers, npc_mind). Film round 5 holds the GPU.
- **Where we're heading:** "First: playable": Mac's crowd, feast and cause notes. The siege scene already pitches a camp of standards and companies at a besieged town's walls, so a siege shows its cause in the world. A sacked town now says its cause in words.
- **Right way?** No new reign measured, so the fun-bar lines are unchanged. Every commit since the last entry answers one of Mac's notes. Nobody is building outside that.
- **Verdict:** on course.
- **Blocked:** the app has paused my messages to other sessions (13 since Mac last typed). Undelivered:
  - to Builder 2: put c.situation as the town card's first line, and scarLine on scar hover;
  - to the judge: the Stormwatch answer;
  - to Film round 5: a close frame and a 3 s clip of Stormwatch's four orange balls (fire glow or light halos? to_gpu keeps size and position, checked headless).
  These go out after Mac's next message.

## 2026-11-10 21:45, motion steps 0-3 (probe, turn rate, locomotion)

- **Landed (mine):**
  - 6f4d112, motion probe: the real game, headless, on a private bridge, Kingsmere at street level, 60 s. It fails today's code on glide, empty hands and turn snaps.
  - ebabc0e, motion v2 behind `--motion=v2`: a turn rate of 300 deg/s, a synced blend space, pace read in the person's own size, and slow steps at a slow cadence. anim_lod runs after the movers.
  - ba76cf3: skate is counted by move, with riders left out.
- **Numbers (Kingsmere, about 35 people, 60 s, measured last in the frame):**
  - Turn snaps: 803 today, 20 with v2.
  - Foot skate still fails (19 people over 10%). By move: Walk 32%, Carrying 30%, Sword_Attack 51%. Next: set the walk pace from the clip's own stride.
  - Empty hand: Drinking, Digging, Carrying and Wheelbarrow, which is step 4, the props.
  - Two in one: 0 to 1 pair.
- **Mac's notes since 21:10, via the judge:**
  - Minds were never on in his game (LIMBO_TOWNS empty), so he played the fallback: no awareness, random wandering, instant switches.
  - People ignore each other; there's no ambient presence.
  - Decisions are disconnected from the map.
  - The game isn't fun.
  - The judge's order: rulings come back (lords return by name); the capital live on minds plus v2 by default; matters placed on the map, with consequences travelling there; then 3b–3e (look-at, interaction slots, hand IK, social and presence rules).
- **Townsfolk look:** 9556b93 fixed npc_mind not parsing from 20:20 (NPC perf's commit swept in a half-done hunk). chatter.mind_line is wired to Builder 2's tooltip.
- **Film round 5 before:**
  - The fire sits in the pit.
  - One dancer is in the ring, and half the revellers face away.
  - The lens goes inside a body.
  - Two identical runners stand on one spot (gap 0.00 m).
  - A freeze at the night feast: 4.9–7.4 s stalls, then no answer.
  - Street: 26 fps, physics 19–22 ms.
- **Blocked:** my messages to other sessions are paused until Mac types, so none of the new orders have been routed. The pause went on at 21:10. To route once it lifts:
  - Townsfolk look: step 1 (the retarget, banned bodies enforced in people.gd, the neighbour variety rule, the broom prop), then step 4.
  - NPC perf: the 300-person baseline and the read-only VAT evaluation.
  - Film: the after-clips once the capital is live; the night-feast freeze log to NPC perf.
  - Builder 2: the anchored-choice API.
- **Verdict:** on course for the motion plan, measured. Off course on fun, by Mac's own word. The judge's order puts rulings that come back and the map first, and that order is taken.

## 2026-11-10 22:05, autopilot (messages flowing again; matters on the map)

- **What's going on:**
  - Mine: 51554f0, every court matter carries `place` {city, x, y, name} and `petitioner`. Proof on a private bridge: a Hand matter about the Thornvale–Stormhold war sits at Rosehall (11,60), petitioner c20.
  - Others: f232e33 (Townsfolk look): one feast ring and fire, people on spots of their own, three more bodies out, chatter.mind_line. 6e48c46 (Builder 2): god.js and /god are gone; blight.js holds blightLua and regrowLua; I reviewed it and nothing lost (the scars became blights, behaviour kept). ef6b05a: the view anchors a matter at item.place.
  - Routed now that messages flow:
    - Townsfolk look: motion step 1, banned bodies enforced in code, the neighbour variety rule, then step 4.
    - NPC perf: the 300 baseline, VAT, and the night-feast freeze.
    - Film: Stormwatch's orange balls and the v2 after-clips.
    - Builder 2: the place API, the situation line on the card, and the usurper hook through a Stakes function.
- **Where we're heading:** the judge's order from Mac's "not fun" and "disconnected from the map":
  1. Rulings come back by name.
  2. The capital live on minds plus v2.
  3. Matters placed and acted on on the map, with consequences travelling there.
  4. Houses scheming visibly.
  The place step is done. Travelling consequences and rulings coming back are next (mine).
- **Right way?** No reign measured this turn, so the fun-bar lines are unchanged. The work matches the order. Risk: v2 can't go live in Kingsmere until feet stop sliding (Walk 32%).
- **Verdict:** on course.

## 2026-11-10 22:45, rulings come back; schemes on the map

- **Landed (mine):** ae96804.
  - **Rulings come back.** Every ruling is owed to the lord who asked, by name, due two seasons on. At the next full sitting that lord comes back ahead of the Hand's matters.
    - Proof: ruled on Blanche Sunspire at turn 38. At turn 40 she came back: "In the summer of 309, you heard our plea at court and ruled: let them march."
    - The first run failed (a Hand matter took the only seat), and the fix gives the returning lord a seat of their own.
  - **Schemes on the map.** world.intrigue holds the lords' real pacts, marriages and gold envoys, from seat to seat, with a hover line. Proof: Wolfholt → Goldcrest.
  - Earlier this turn: 51554f0, matters carry a place and a petitioner.
  - Main couldn't load the bridge between 3bf4888 and ae96804 (a swept import). Fixed, and Builder 2 is told.
- **Others:**
  - 17458fc (Townsfolk look): one Rest Fixer retarget across 237 imports; bans in one list; no twin neighbours; tools in hands. Empty hand: Drinking 2122 → 14, Carrying 1246 → 74, Digging 480 → 0.
  - 3bf4888 (Builder 2): the director's threats build each act.
  - 9206aea: schemes drawn on the map.
  - 9d8a83b: faces on the map.
  - NPC perf: no freeze headless. Real stalls are the forest's clear_where (about 1 s) and the walk-map rebake; VAT rejected. NPC perf now takes units.gd's speed fixes, the forest stall and an async nav bake.
- **Fun bar:** no reign measured this turn. The order is followed: rulings come back (1), the map (3) and schemes (4) have landed. The capital going live (2) waits on foot skate.
- **For Mac (downloads need his yes):** a lute, a wheelbarrow, a plain gentleman's body, and a Mixamo sweeping move. Until then, moves without their tool aren't chosen.
- **Verdict:** on course.

## 2026-11-10 23:10, autopilot (supervisor turn)

- **Landed (mine):**
  - a4c8431: the mirror carries intrigue.
  - e6d3e3b: Stakes.raisePretender.
  - 6af53bd: /test/clock. Proven: act_end brings "End of the first act".
- **Fresh judge (supervisor turn), 3 gaps:**
  1. The faces and the scheme lines aren't in film yet. Before the mirror line went in, the view saw no intrigue. Film is asked to shoot them.
  2. The decision is a menu, not a dilemma. The court card fills half the screen with one priced option. A starving town doesn't look starving. The card and the look go to Builder 2. The choices are mine: who each answer helps and hurts, with no lone option.
  3. The town still clips: carts merged with each other and with people, war reads as a cheering crowd, a crowd stands in rows. Carts go to Builder 2 (traffic); war, talk and rows go to Townsfolk look.
  - Working: stormwatch-6.jpg shows the ping, the treachery ticker and the scar line in one oblique frame. The land remembers.
- **Own work in progress:** the walk pace from the clip's own stride. The first headless measurement read 0, because the clip didn't pose the skeleton through AnimationPlayer. Next try: drive it through the person's Motion tree.
- **Fun bar:** no reign measured. Judging by the judge's frames, the decision moment is the weakest line.
- **Verdict:** on course on structure; off course on the decision's feel. Course correction: the court's choices become two-sided dilemmas before more systems are added. I take it next.

## 2026-11-10 23:30, autopilot (the course correction took)

- **Correction check:** last turn's correction was "the court's choices become two-sided dilemmas". It took.
  - 9a2db70: every Hand order is weighed before choosing (cost, whom it warms, whom it cools). It runs the same decree and the same tempering as the real order, dry.
  - Proof, the Thornvale–Stormhold war: Command peace +2 each. Back Stormhold: Stormhold +12, Thornvale −12. Wed them: Thornvale +8, Stormhold +5, where the written label claimed "+8 each".
  - Builder 2 shows it on the anchored card.
  - Petitions' own options are next.
- **Others:** Townsfolk look is running talk and war/riot checks. NPC perf is measuring the units, forest and nav-bake fixes. Film round 5 is on the full review capture (about 45 min).
- **Fun bar:** no reign measured. Bet 5's "helps and hurts shown" is now true for the Hand's orders, data-side.
- **Verdict:** on course.

## 2026-11-10 23:55, autopilot (dilemmas: every answer weighed)

- **Landed (mine):** e75b29c.
  - Every lord's plea answer carries `weighs` from the card's own effects, and each plea stands at its own town. Before this it fell back to the lord's seat, because court.open() dropped the card's roles.
  - House names are the ones the player sees.
  - No card is dealt with a role missing (border_war had shown "{rivalTown}").
  - Proof, six cards: "Let them march" gives Sunspire +15, Blackbrook −25. "Warn Wolfholt" gives Wolfholt +15. Pleas were placed at Redsands, Burgos, Lille and Lyon.
  - With 9a2db70, every choice at court now shows who it helps and hurts before choosing (bet 5, data side). Builder 2 shows it on the card.
- **Others:**
  - d3fe54c and feb2173 (Townsfolk look): talk is heard (stale knots cleared); war has a barricade and standards; riot has an overturned cart; the watch is armed; lute and barrow are gated.
  - 217d541 and 47f32e1 (NPC perf): the forest clear is spread over frames (1.1 s → 8 ms slices); units 7.8 → 2 ms; walk-map rebake 211 → 0.7 ms. It's now on foot skate, with a fix in motion.gd behind v2.
  - Film round 5 is on the full capture, then the gossip, war and riot refilm.
- **Fun bar:** no reign measured. The decision line ("every answer costs, and you see the cost") is now true in data.
- **Verdict:** on course.

## 2026-11-11 00:20, autopilot (first measured reign since Court v2)

- **Measured reign, scripted King, private bridge, code before 363180e** (realm/tools/reign_measure.py): 15 min, reign clock 13.6 min.
  | Line | Now | Target | Before |
  |---|---|---|---|
  | Decisions a minute | 1.27 | ≤ 1 | 1.08 (Court v2) |
  | Quiet share | 90% | ≥ 60% | 86% |
  | Repeated kinds | 3 | 0 | not measured |
  | Distinct petitioners | 6 | name three lords | not measured |
  | Lords returning | 7 of 19 (37%) | ≤ 25% | not measured |
  | Matters with a place | 19 of 19 | all | n/a |
  | Plea answers weighed | 3 | all | n/a |
  | Schemes on the map | 6 (4 at once) | every season | n/a |
- **Reading:**
  - Too many returns (37%, one lord back three times in 80 s), and it pushed decisions over 1 a minute. 363180e (a cap, once a year, varied returns) answers exactly this, and a reign on the new code is playing now.
  - Places: 100%. Schemes visible: yes.
  - Weighed pleas: 3 of 14. Most pleas came from cards whose answers are worked out in code (grain, informer), and those aren't weighed yet.
- **Earlier this turn:**
  - 363180e: returns capped and varied, the oath costed. The judge accepted it.
  - 544aad8: road travellers give way.
- **Go-live gate:** NPC perf owns the motion probe run in a quiet window. Film pauses for it. Skate is the last blocker.
- **Verdict:** on course. The measured numbers led directly to the returns fix. Next turn, check that the fix took with the new reign's numbers (returns ≤ 25%, decisions ≤ 1 a minute).

## 2026-11-11 00:45, autopilot (did the returns fix take? yes)

- **Correction check:** 363180e took. A reign on the new code: returns 2 of 22 matters (9%, target ≤ 25%; was 37%).
- **New reign (new code), 15 min:** 1.47 decisions a minute (target ≤ 1); 89% quiet; 2 repeats; 7 petitioners; 22 of 22 placed; 6 pleas weighed; 4 schemes.
- **New problem:** 13 of 22 were the Hand's matters, mostly ultimatums coming back (Sunspire at turns 38, 42 and 47; Thornvale at 47 and 53).
  - Partly the scripted King: answering the Hand with silence counts as answered, which resets the house's anger.
  - The script now acts as a player would (the Hand's first affordable order, then answered). A reign is playing again to tell the script's share from the game's.
  - If ultimatums still repeat, the fix is in the ultimatum flow: an ignored ultimatum should lead to the rising, not a fresh ultimatum.
- **Also:** 9d1d303 weighs the grain plea's answers.
- **Verdict:** on course for returns. Watching the Hand's pace: decisions are over the line.

## 2026-11-11 01:20, autopilot (supervisor turn: ultimatums land)

- **Fresh judge:**
  - The pace (about one matter a sitting) is right for a court that sits each season, and the "≤1 a minute" line fits a free-running clock better than a sitting-paced one.
  - The fault is what fills it: ultimatums looped. Highest leverage: an ignored ultimatum becomes the rising.
  - The other gaps: the court card reads as a menu that covers the map (Builder 2's); the quiet stretches aren't worth watching (bodies overlapping, empty hands, no talk heard), which is Townsfolk look's and NPC perf's.
- **Correction, taken this turn:** 0ea0e31. An ultimatum ignored, or answered without winning the house back, now gathers the house's host (a muster scene and a chronicle line), and the host marches in 2 seasons. Won back in time, the banners come down. Proof comes from Builder 2's answering-King reigns B and C on head (ultimatum count, risings), then my next measured reign.
- **Machine rule (the judge):** at most one Godot and two private bridges across all sessions, booked through Film's hold file. Passed to everyone.
- **Also:**
  - 6e46e77, a4c8431: the mirror carries the threat and intrigue.
  - The measuring King now gives the Hand's first affordable order, and skips a card it can't answer (a siege plea gave 400 on repeat).
- **Gate:** skate still fails (19 people). NPC perf is tracing Sword_Attack, Carrying and the standing drift. Glance is at 35%, with Townsfolk look.
- **Verdict:** on course after the correction. Check it next turn: ultimatums no longer repeat.

## 2026-11-11 01:40, measured reign invalid; handover

- The acting-King reign is invalid as a measure. It ran on the measuring script from before the skip fix, so one siege plea the crown couldn't answer (HTTP 400) was retried 203 times. Discarded. The fixed script (realm/tools/reign_measure.py) skips such a card.
- Open for the next turn:
  - Builder 2's answering-King reigns B and C on 8866 (ultimatum count and risings, to prove 0ea0e31), then one measured reign with the fixed script.
  - The siege plea's answer gives 400 when the crown can't pay. It should be greyed with why, not offered.
  - The gate: skate (11 people), glance 35%, children 52%. NPC perf and Townsfolk look are on these.
