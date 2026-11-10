# Autopilot: how the game gets better while Mac is away

The plan the recurring loop follows, one turn every 10 minutes. Read it at the start of every turn.

## Who we are

System integrators with design taste (CLAUDE.md, VISION.md "Decided"). We build a good consumer
experience: a ruler game that is fun, readable and beautiful. Every layer comes from a proven block, and
our code is glue. Every change is judged as a demanding player would judge it, against **the fun bar** in
GAME_DESIGN.md, and measured from a real reign rather than guessed.

## What we're building

Mac approved all six bets in the fun brief (https://claude.ai/artifact/5T4M33vrEY2KABfzs3ypQZ,
collections `decisions`, `picks`, `notes`). In leverage order:

1. **Room to breathe:** a paused court once a season, 40 s seasons, one matter rising to three, the camera
   tours the realm between courts.
2. **Read the realm:** house colours at every zoom, a ranked ladder of houses, the name you're earning
   shown live, peace, wealth and strength arrows, blood and soot at the screen edges.
3. **A shape and an ending:** acts by the clock, a named final threat at three-quarters, ultimatums before
   any rising, an epilogue flight, no Endless reigns.
4. **Lords worth caring about:** a face on every Court card, one want per lord, unique names, choices that
   change what's asked, no repeats.
5. **Every answer weighs:** who an answer helps and hurts is shown before choosing, and the result glows
   on the card.
6. **Stories and the player's own beats to the same bar:** no early or coin-flip endings, an ultimatum
   before every march, beats that bring matters to court and react to rulings.

## Now building (Mac, 2026-11-10: "it isn't fun; research what makes it fun, then build it")
In order, each judged by GAME_DESIGN.md's engagement model and fun bar:
1. **C, the royal ladder:** one aim always on screen, a reward in the world, the next aim named. (built)
2. **A, the Crown's lands to build:** pick one build a season; it rises over seasons and produces; finished ones unlock the next.
3. **B, the royal host:** one order a season, a battle with a forecast ("about 60% to hold"), the camera cuts to it, and a town taken turns to the Crown.
4. **A verb between courts:** a few royal acts a season (send the host, rush a building, spend favour), one meter that refills each season.
5. **Pending outcomes:** some answers start things that land in 1–2 seasons, marked on the map with a countdown.
6. **Readable rules:** the Hand names a rule of the realm once, and later matters reward knowing it.
7. **Juice:** every answer and order gets a seal, a sound, a reaction in the world, and a camera move in under 2 s.
8. **Near-misses and named stakes:** "Varn: 2 favour from rebellion"; how close you are to the next name.
9. **Rhythm across the acts:** build, then army, then the threat, then the battle you prepared for; the interlude asks what you'll do next act.
10. **Houses react to your project:** lords petition about your walls and your host.

## Who does what

- **This session builds everything,** one step after another (goc-cpto; Mac, 2026-11-09: no parallel builders). Read-only agents may review, research or find causes; they never edit.
- **Performance is dropped** (Mac, 2026-11-09).
- **Order:** the three UI review fixes (play-feedback commits them, then stops) → bet 3 (four acts by the clock with interludes, ambitions, Endless dropped) → bet 4 (faces on Court cards, one want per lord, asks that remember rulings, a voice per house) → bet 5 (who each answer helps and hurts, shown before choosing; the result glowing on the card; the camera to the biggest ruling) → the rest of bet 6 (an ultimatum before every story march, player beats that bring matters to court, no free answers, rulings count toward the name) → smaller items (workers and carts on the roads, following a house's army, council votes) → the review page for each.
- **Proof:** logic is proven with bridge calls; only visual items get films, batched into one film run per batch.

## One turn

0. **Skills.** Load `goc-cpto`, `goc-voice`, `goc-ux`, `goc-engineering`, `goc-tests`, `goc-run` and
   `goc-release` if they aren't loaded this session. Load `screen-review` and `review-loop` before
   touching the review page.
1. **Status.**
   - `git log` since the last LOOP.md entry.
   - The linked sessions' state and notes, and any messages waiting.
   - The brief's `decisions`, `picks` and `notes`.
   - The review page's open comments.
2. **Check the direction, every turn.** Answer these four, in LOOP.md, with evidence:
   - **What's going on?** What each session is doing right now and what landed since last turn.
   - **Where are we heading?** The next approved item in leverage order, and whether that is what's
     being built.
   - **Are we moving the right way?**
     - The fun-bar numbers from the latest measured reign compared with the last, line by line.
     - Whether the work follows the approved bets and their order.
     - Whether any session is stuck, looping, redoing work, polishing something low-leverage, building
       something unapproved, or breaking what works.
   - **Verdict:** on course, or off course and why.
3. **Course-correct when off course.** Act the same turn:
   - Tell the owning session exactly what to stop and what to do instead.
   - Reorder its queue to the leverage order.
   - Unblock it, or take over a stalled item whose files are free.
   - Revert a change that lowered a fun-bar line or lost behaviour.
   - If a whole bet is pointing the wrong way, say so on the brief with the evidence, and park it for
     Mac's call.
   - Check the next turn that the correction took.
4. **Steer.**
   - Answer blocked sessions.
   - Read every new commit's diff: no lost behaviour, no line of the fun bar dropping, UI.md kept.
   - Send corrections to the session that owns the files. Free files the moment a session commits.
5. **Supervise, every other turn.** Spawn a fresh agent, not my own review. It judges the newest shots and
   clips plus the last commits against GAME_DESIGN.md's fun bar, UI.md and goc-ux's look bar, as a
   demanding strategy player, and returns the 3 biggest gaps. Route each gap in scope to the owning
   session. Log the rest in LOOP.md.
6. **Measure.**
   - When a pacing, court or story change lands and no Godot is running, play one 15-minute reign on its
     own chronicle.
   - Count the fun bar from that chronicle: decisions a minute, quiet share, repeats, names, time to
     feedback.
   - Put the numbers in the brief's measured table, next to the last run's.
7. **Review page.**
   - When shots or clips are committed in `docs/review/screens.json`, publish or refresh the review page
     from this session, following screen-review sections 3 and 5.
   - Its URL is in `docs/review/ARTIFACT_URL`. The old page belongs to another claude.ai account, so the
     first publish makes a new one.
   - Every changed screen gets its before and after and a Claude note: what changed, why, and its
     fun-bar numbers.
   - Promoting a change is Mac's call. Read his comments with `review-loop` and act on them.
8. **Research.** Fold any pending research (the Steam review dataset) into the brief, tagged measured,
   sourced or estimated.
9. **Own work.** If nothing needs steering, take the next approved item in nobody else's files: build it,
   film it (3-8 s, read as frame strips), fix, prove it, commit.
10. **Log and ship.**
   - Add a dated entry to `docs/review/LOOP.md`: what changed, the numbers, what's open.
   - Commit with `git commit -- <explicit paths>` and push. Main only.
11. **Tell Mac.**
   - Something changed: two or three short bullets.
   - Nothing changed: one line.

## Rules

- `arch -arm64 godot`, one copy only, renders through `realm/tools/render.sh`.
- Long runs go in the background. Never wait on a render: do the next thing meanwhile.
- If Mac is playing, never take the game.
- Never lose existing behaviour. Look for a proven block before building anything.
- Only approved work: the six bets, the fun bar and Mac's notes. Anything new goes in the brief as a
  proposal for Mac.
- Decide without asking Mac. Stop only for outward-facing or irreversible steps: releases, posts,
  deleting data.
- Short sentences and small bullets to Mac. Player words, never mechanics.

## Done

Every approved change is on the review page with its before and after, and its fun-bar numbers are at
target, or the gap is named with the next step.
