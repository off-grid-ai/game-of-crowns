---
name: goc-throughput
description: Game of Crowns' way of making the most progress - builders finish code on main with no test runs, the supervisor tests everything that landed together every 12 minutes and removes the bottleneck each round. Use when Mac says "keep going", "finish the code", "no test runs", "group and test", "what's the bottleneck", or "/goc-throughput", and on every supervisor wake-up.
---

# Throughput: finish the code, test as a group, remove the bottleneck

Mac (2026-11-13): "no test runs, nothing, just keep going, finish the code", "finish all the integrations directly on
the main codebase", "no wasting time with side tests", "we all need to work in one codebase", "group and test the
changes together", "constantly look at what the bottleneck is, and then remove that". The loop runs every 12 minutes.

## Builders: finish, don't prove

- Write the real code in the main tree, on main. No branch, no copy, no private bridge, no scratch.
- The only check is a compile check: `node --check` on JS you touched, `arch -arm64 godot --headless --check-only`
  on GDScript, `realm/tools/rules_check.sh`. A file that doesn't load never stays in the tree.
- Run nothing else: no probes, autoplay, reign harness, headless game or render. Find causes by reading the code and
  the logs and frames that already exist.
- Commit small and often, by path (`git commit -- <your files>`, index checked first). Push.
- Report in two lines: what changed, and how to see it (the switch, the view, the demo hook).
- Never wait on a test. Start the next piece at once. A failure comes back from the supervisor; fix it then.

## Supervisor: the 12-minute round

Keep the loop alive with `/loop 12m /goc-throughput` (or `ScheduleWakeup` 720 s). Each round:

1. **What landed.** `git log --since="12 minutes ago" --stat` on main. Nothing new → skip to step 4.
2. **One combined pass** on the shared tree, in the background, one Godot (`pgrep` first): compile check of
   everything, one game run, one batched render of every view the round touched (CLAUDE.md "Renders").
3. **Route the results.** Each failure goes to its owner (SendMessage) with the frame or log line and the commit.
   Don't fix it yourself. Screenshots go to Mac at once, unasked, with the casebook case named.
4. **Find the bottleneck.** Answer these and pick the worst:
   - Who is waiting? On the GPU, a review, Mac, a file another builder owns, a download.
   - Who is idle? Give them the next piece from `docs/PLAN.md`.
   - What is being done twice? Two threads on one job, or a check repeating one already done.
   - Which step is slower than the code it checks?
   - What keeps failing in the combined pass? A file everyone collides on gets one owner.
5. **Remove it** this round: reassign, split a file's ownership, cut the slow step, unblock with a decision
   (Mac delegated product calls; log them). Never add a step or a gate.
6. **Log one line** in `docs/SUPERVISOR_LEDGER.md`: time, what landed, pass/fail, the bottleneck, what was removed.

## Never

- Per-change test runs, private bridges, scratch copies, probes before fixing, per-session renders.
- "Behind a flag", two systems doing one job, keeping the old path (CLAUDE.md "No fallbacks").
- A builder waiting on anything. A supervisor waiting on builders.
- Swapping, stashing, resetting or rebasing the shared tree.

## Related

`goc-engineering` (how code is changed and committed), `goc-run` (running the game and renders),
`goc-release` (pushing and showing Mac).
