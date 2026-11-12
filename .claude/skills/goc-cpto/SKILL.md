---
name: goc-cpto
description: Game of Crowns working rules (entry point). Load at the start of substantive work on Game of Crowns (the Aldmere realm: Godot view, Node bridge, Freeciv), or when Mac says "act as CPTO" / "follow the rules".
---

# Game of Crowns rules

**The casebook is the goal (Mac, 2026-11-12: "the casebook is the right one, you know thats our goal right?").**
"What makes a medieval world sim great" (https://claude.ai/artifact/PzdycNn8Wj2xdTp8AX7AYK): 114 cases from 58 games,
each an idea, a shipped game that nails it, the moment players remember and the lesson to steal. It is the bar for
how the game plays and feels; docs/art/target is the bar for how it looks. Every change names the case it serves
(e.g. "towns: The crowd is the census, Stronghold"), every review judges against both, and the casebook's failures
chapter is the list of things we must not ship. Read the chapter for your area before you build.

**One supervisor, several builder threads (Mac, 2026-11-12: "override the threads thing with the status quo").** The supervisor session judges, routes, renders and keeps `docs/SUPERVISOR_LEDGER.md`; builder sessions it starts each own a layer and its files (today: buildings, ground, people's looks), and other sessions Mac starts own whole systems (town life, the army layer, ground truth). Every writer names its files before editing, commits only its own hunks by path, and checks `pgrep -x godot` before any Godot run. Two writers never edit the same file at once: the owner of a file is asked first.

**Build in batches, test together (Mac, 2026-11-07).** Make all the related changes first, then compile-check them all, launch once, and film and judge them together in one run, rather than launching and testing after each small change. Fix what the run shows, then run again. A change that can break a working system still gets its own before/after on film within that run.

**Never lose functionality.** No change may remove, disable or narrow something the game already does, not even to work around a bug or to make a scene film well. Fix the broken seam instead. If a request or a fix would lose any behaviour, tell Mac first in plain words: what goes, who notices, the alternative that keeps it. Read every diff for it before committing (yours and any other session's): removed branches, forced `false` flags, skipped steps, overridden settings.

**We are system integrators** (CLAUDE.md): survey the proven building blocks before building, and never hand-build a system where one exists.

**How we build (Mac, 2026-11-12; CLAUDE.md).** We kept redoing the same fixes because each system was hand-built its own way. So:
- **Engine blocks first.** Godot, Freeciv and their add-ons before our code (Godot's navigation, not hand-made obstacle lists).
- **One store, one direction, like Redux.** Freeciv -> bridge -> `/world` -> one mirror (`awareness.gd`). Changes arrive only as actions (a world sync, an event, a person's done); one reducer per slice decides; everything else reads. Town life: `docs/TOWN_LIFE.md`.
- **One interface per behaviour, everyone inherits it.** Moving is `mover.gd`; nothing else moves a body. Scenes, moods and reactions are rows of data, not hand-written functions.
- **No fallbacks.** The better system replaces the old one in the same change: no switch back, no two systems for one job. We haven't launched, so no save-compatibility shims. The behaviour must carry over (never lose functionality), the old code must not.
- **Rules check themselves.** `realm/tools/rules_check.sh` runs before every commit of `realm/scripts`; its known-breach list only shrinks.

**Review and asset sessions only look or fetch.** A review or test session films, judges and pins notes on the review page (`review-loop` writes its findings to `docs/review/LOOP.md`); it changes no code. An asset session (Codex, Meshy, Sketchfab, Mixamo) downloads into `downloads/`, `~/Downloads/Aldmere/` or `~/code/goc-kits/` and reports; the builder that owns the layer wires it into the game. Renders are batched by the supervisor (CLAUDE.md).

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
