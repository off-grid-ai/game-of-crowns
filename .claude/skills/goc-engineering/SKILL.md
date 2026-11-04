---
name: goc-engineering
description: How code is changed, checked and committed in Game of Crowns (realm/ Godot GDScript, bridge/ Node, Freeciv Lua and rulesets). Load before editing code, running checks or committing.
---

# Engineering

1. **Write like the code around it.** GDScript doc comments (`##`) say what a thing is in the game's own words; same naming, density and idiom. Bridge stays plain Node with no npm dependencies.
2. **Glue, not engines.** Our code connects Freeciv, Godot add-ons and assets. A new system needs a reason no existing block covers it.
3. **Check every edit.** GDScript: `arch -arm64 godot --headless --path realm --check-only -s res://scripts/<file>.gd`. Give explicit types to values from untyped nodes (`var d: float = terrain.…`), or it won't parse. Bridge: `node --check <file>.js`.
4. **Reload what you changed.** Bridge: `launchctl kickstart -k gui/$(id -u)/com.realm.bridge`. New or changed assets: `arch -arm64 godot --headless --path realm --import`.
5. **Never freeze the frame.** Big builds (towns, countryside) go through a per-frame budget or a coroutine; never a multi-second loop on a sync.
6. **Small commits.** One change each, by subsystem, staged by name. Never `--no-verify`.
7. **Third-party art stays out of git** (Sketchfab, Mixamo, Quaternius, Poly Haven): only its `.import` files and licences are tracked. Own art, code, docs and the baseline realm go in. See `.gitignore`.
8. **Never wait.** Renders, imports and long calls run in the background; resume from the notification.
9. **Local model:** text only, Off Grid's Omni 2B (or 1.7B), no call budget. Small model: short persona, real conversation turns, plain-text replies; JSON only for simple picks.

## Sessions share one checkout and one git index

Several sessions commit to `main` from the same folder. Never `git add` and leave files staged: another session's commit will take them. Commit only your own paths in one step, `git commit -m "…" -- <your paths>` (new files: `git add <paths> && git commit -m "…" -- <paths>` in the same command), then `git push`; if the push is rejected because another session just pushed, `git pull --rebase -q && git push`. Check the compile output is clean before committing, never after.
