---
name: goc-engineering
description: How code is changed, checked and committed in Game of Crowns (realm/ Godot GDScript, bridge/ Node, Freeciv Lua and rulesets). Load before editing code, running checks or committing.
---

# Engineering

## Before any change: who already solved this? (Mac, 2026-11-10)

Every change, even a one-line fix, passes this gate first. A fix that places, times or decides something by
hand is a sign we're rebuilding a solved problem.

1. **Name the problem in general terms**: "a horse pulling a cart along a road", "people choosing what to do",
   "UI that fits any window", "show the player where an event is". Not "the horse is 0.16 off".
2. **Find how it's solved**, in this order:
   - Godot itself: nodes and servers (PathFollow3D, AnimationTree, NavigationServer, Containers and anchors,
     content scaling, Tween, AudioStreamRandomizer, Jolt).
   - The add-ons we already have (LimboAI for anything that decides or behaves, Sky3D, the water shaders).
   - Mature free add-ons and asset kits (MIT, CC0): stars, last release, Godot 4.7 fit.
   - How shipped games do it (Civ, RollerCoaster Tycoon, Warcraft II, CK3, RimWorld, Manor Lords).
3. **Use that.** Our code only configures and connects it.
4. **None exists?** Say so in the commit and LOOP.md, and keep the hand-written part small. For anything big,
   Mac decides first.
5. **Patching a hand-built part again?** Stop and replace it with the block instead.

1. **Write like the code around it.** GDScript doc comments (`##`) say what a thing is in the game's own words; same naming, density and idiom. Bridge stays plain Node with no npm dependencies.
2. **Additive.** No unrelated refactors. Ask Mac before a new abstraction, a change to the saved realm's format (`bridge/chronicles/*/state`, `meta.json`) or a migration: old chronicles must still open.
3. **Glue, not engines.** Our code connects Freeciv, Godot add-ons and assets. A new system needs a reason no existing block covers it.
4. **Check every edit.** GDScript: `arch -arm64 godot --headless --path realm --check-only -s res://scripts/<file>.gd`. Give explicit types to values from untyped nodes (`var d: float = terrain.…`), or it won't parse. Bridge: `node --check <file>.js`.
5. **Reload what you changed.** Bridge: `launchctl kickstart -k gui/$(id -u)/com.realm.bridge`. New or changed assets: `arch -arm64 godot --headless --path realm --import`.
6. **Never freeze the frame.** Big builds (towns, countryside) go through a per-frame budget or a coroutine; never a multi-second loop on a sync.
7. **Small commits.** One change each, by subsystem, staged by name. Never `--no-verify`.
8. **Third-party art stays out of git** (Sketchfab, Mixamo, Quaternius, Poly Haven): only its `.import` files and licences are tracked. Own art, code, docs and the baseline realm go in. See `.gitignore`.
9. **Never wait.** Renders, imports and long calls run in the background; resume from the notification.
10. **Local model:** text only, Off Grid's Omni 2B (or 1.7B), no call budget. Small model: short persona, real conversation turns, plain-text replies; JSON only for simple picks.

## Sessions share one checkout and one git index

Several sessions commit to `main` from the same folder. Never `git add` and leave files staged: another session's commit will take them. Commit only your own changes, in one step. A path commit takes the whole file, so if `git diff <file>` shows any lines that aren't yours (another session is editing it too), stage just your hunks (`git diff <file> > /tmp/mine.patch`, trim it to your hunks, `git apply --cached /tmp/mine.patch`) and run a plain `git commit -m "…"`. If the file is yours alone, `git commit -m "…" -- <paths>` is fine (new files: `git add <paths> && git commit … -- <paths>` in the same command). Then `git push`; if the push is rejected because another session just pushed, `git pull --rebase -q && git push`. Check the compile output is clean before committing, never after.

## Production grade

Mac's bar is a shippable game. Nothing debug reaches the player or the log: no animation lists, test pickers, key-help strips, internal names, `print()` traces or frame probes in committed code (keep test aids behind an explicit shot flag such as `--probe`, off in play). The player sees the world and the choices that matter; the game makes the rest of the calls. Read the run log of every render you take, and fix any recurring ERROR or WARNING rather than ignoring it.
