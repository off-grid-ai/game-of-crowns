# Game of Crowns

**We are system integrators with design taste** ([VISION.md](VISION.md), "Decided"). Every layer comes from an existing project (Freeciv for the world, Godot and its add-ons, asset kits); our code is glue. Before building anything, ask "who already built this?": survey the proven building blocks (maturity, Godot 4.7 fit, licence), show Mac the pick, then integrate. Never hand-build a system where a block exists; if none does, say so and let Mac decide.

Read these before deciding anything about the game:

- [GAME_DESIGN.md](GAME_DESIGN.md): how it should play and feel (the promise, the core loop, the pillars, the feedback ladder, how we decide). Start here.
- [UI.md](UI.md): the interface philosophy (corners, glanceable, one accent, every decision is seen).
- [VISION.md](VISION.md): decisions and scope, including the "Decisions that matter" plan and the roadmap.
- [DESIGN.md](DESIGN.md): the world, its systems and the art direction.

**Renders: build everything, then render everything once (Mac, 2026-11-11, said many times).** Never queue
renders per session, per agent or per change. Builders and agents code, check with a headless `--check-only`,
commit and report their switches and demo hooks. Then the supervisor runs one batched render of every view and
change together, takes all the screenshots at once and sends them to Mac straight away. A builder that renders
on its own stalls everyone behind the one GPU.

**No fallbacks: replace, don't keep the old way (Mac, 2026-11-12).** When a proven block or a better system
replaces hand-built code, the old code goes in the same change. No switches back to the old path, no "behind a
flag until judged", no two systems doing one job. Keep moving forward. The game hasn't launched, so old saves and old
chronicles need no compatibility shims either.

**One way to move (Mac, 2026-11-12).** Everything that moves (people, carts, horses, soldiers, beasts) moves
through one Mover (`realm/scripts/mover.gd`): ask it to go somewhere, it asks the navigation for the route and
walks it. Nothing tweens or sets a position to travel. One base, every mover inherits it, so nothing can drive
through a well by forgetting to ask. `realm/tools/rules_check.sh` checks it before every commit of `realm/scripts` (its known-breach
list, `tools/rules_known.txt`, only shrinks).

**Smooth play first (Mac, 2026-11-14).** No beach ball, smooth panning and zooming, a fast load, with no loss of
look. Heavy work never blocks a frame: every staged loop draws on the one frame budget (`ViewTier.spend_ok`), views
react to the store's `record_changed` instead of re-walking the world, far towns stream, repeated things draw in
bulk (`bulk.gd`).

Where things stand right now is the top of [docs/SUPERVISOR_LEDGER.md](docs/SUPERVISOR_LEDGER.md). Working rules
are the project skills in `.claude/skills/` (start with `goc-cpto`). Marketing copy follows
the mac-voice skill: only what the player gets, said the way a person talks.
