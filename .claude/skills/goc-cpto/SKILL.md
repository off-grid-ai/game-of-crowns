---
name: goc-cpto
description: Game of Crowns working rules (entry point). Load at the start of substantive work on Game of Crowns (the Aldmere realm: Godot view, Node bridge, Freeciv), or when Mac says "act as CPTO" / "follow the rules".
---

# Game of Crowns rules

**The main thread does all coding and change work.** Every edit to `realm/`, `bridge/`, the docs, every commit and push happens here, one step after another. Don't hand change work to another session, sub-agent or workflow: each starts without the context, and two writers on one file collide.

**Build in batches, test together (Mac, 2026-11-07).** Make all the related changes first, then compile-check them all, launch once, and film and judge them together in one run, rather than launching and testing after each small change. Fix what the run shows, then run again. A change that can break a working system still gets its own before/after on film within that run.

**Never lose functionality.** No change may remove, disable or narrow something the game already does, not even to work around a bug or to make a scene film well. Fix the broken seam instead. If a request or a fix would lose any behaviour, tell Mac first in plain words: what goes, who notices, the alternative that keeps it. Read every diff for it before committing (yours and any other session's): removed branches, forced `false` flags, skipped steps, overridden settings.

**We are system integrators** (CLAUDE.md): survey the proven building blocks before building, and never hand-build a system where one exists.

**Other sessions only fetch assets or look.** A review or test session films, judges and pins notes on the review page (`review-loop` writes its findings to `docs/review/LOOP.md`); it changes no code and hands findings back here. The asset session briefs Codex to download models and moves (Sketchfab, Mixamo) into `downloads/` and `~/Downloads/Aldmere/`, and reports. It changes no game code. Wiring an asset into the game happens here.

**Decisions live in [VISION.md](../../../VISION.md) and [DESIGN.md](../../../DESIGN.md).** Read them first; update them when Mac changes a decision.

Load the skills the work needs. Each is short; apply with judgement.

- `goc-voice`: always. How to talk and decide.
- `goc-engineering`: code, checks, commits, pushes.
- `goc-ux`: any screen, scene, camera or feel.
- `goc-tests`: proving a change works (no unit suite: bridge calls and renders).
- `goc-run`: running the bridge, Freeciv, Godot, the local model, screenshots.
- `goc-release`: the GitHub repo, pushes, screenshots to Mac, docs.
- `goc-playtest`: checking the whole game scene by scene.
- `goc-get-it-live`: all of the above, start to finish.
- `screen-review` / `review-loop`: the review page (`docs/review/ARTIFACT_URL`): versions, clips, and marks on what's wrong.
