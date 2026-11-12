---
name: goc-engineering
description: How code is changed, checked and committed in Game of Crowns (realm/ Godot GDScript, bridge/ Node, Freeciv Lua and rulesets). Load before editing code, running checks or committing.
---

# Engineering

## Change the real tree, never a copy (Mac, 2026-11-12)

Mac: "changes need to be made directly, they cannot / shouldn't be made in scratchpads." Every edit is made in the
shared checkout's own files, the ones the game runs. No working copies of `realm/` or `bridge/` in a scratchpad to edit
and copy back, no "after" tree built beside it. A scratch copy is allowed only to run a probe's before-run against
HEAD's untouched code (read-only, deleted after). Keep the tree working while you edit: make each edit whole, run its
load or compile check at once, and land it; a file that doesn't load (a ruleset, a script) is never left in the tree.

## No hack-fixes: reproduce it, then fix the system (Mac, 2026-11-12)

Mac: "that's where we've been struggling, cause you keep making hackfixes." A bug seen on screen (a cart through a
well, a horse spinning) is a symptom. Before any code:
1. **Reproduce it with a headless probe first** (no GPU: a script under `realm/tools/` that sets the scene up and
   asserts the rule: nobody spins on the spot, no path crosses a footprint, everyone arrives). It must fail now.
2. **Name the general problem and the block that solves it** (the gate below). Write 3-5 lines of design in the
   commit or `docs/` before code when a shared system changes: which block, what hand-written code it replaces.
3. **Fix the system, not the instance.** The probe passes; it stays as a guard and runs on every later change.
No fix lands without its probe. Patching the same area twice means the first fix was a hack: stop and redesign.

## Before any change: who already solved this? (Mac, 2026-11-10)

Every change, even a one-line fix, passes this gate first. A fix that places, times or decides something by
hand is a sign we're rebuilding a solved problem.

1. **Name the problem in general terms**: "a horse pulling a cart along a road", "people choosing what to do",
   "UI that fits any window", "show the player where an event is". Not "the horse is 0.16 off".
2. **Find how it's solved, and look wide.** The world is big; we are rarely the first.
   - **Engines and their ecosystems:** Godot's own nodes and servers, the Godot Asset Library, and what Unity,
     Unreal and Bevy users reach for (free content, open-source ports, techniques we can bring over).
   - **Open-source games and sims:** 0 A.D., OpenRA, Widelands, Freeciv itself, Mindustry, OpenTTD,
     OpenRCT2, Battle for Wesnoth, Dwarf Fortress-likes. Read how their code solves it.
   - **Game AI and design craft:** GDC talks and postmortems, *Game AI Pro* (free online), utility AI,
     GOAP, behaviour trees, Celia Hodent's game UX, the Game Accessibility Guidelines.
   - **Asset commons:** Mixamo, Quaternius, KayKit, Kenney, Poly Haven, ambientCG, OpenGameArt, Freesound.
   - **Outside games:** film and animation craft (Disney's twelve principles, cinematography), theme-park
     and crowd design, theatre staging, board-game design, interface guidelines (Apple, Material), and
     research papers.
   - **Shipped games' answers:** Civ, RollerCoaster Tycoon, Warcraft II, CK3, RimWorld, Manor Lords,
     Frostpunk, Reigns, and what their players and modders say worked.
3. **Use that.** Our code only configures and connects it.
4. **None exists?** Say so in the commit and LOOP.md, and keep the hand-written part small. For anything big,
   Mac decides first.
5. **Patching a hand-built part again?** Stop and replace it with the block instead.

## Architecture: SSOT, SRP, DRY, SOLID (Mac, 2026-11-10)

Every change follows these. A plan that breaks one isn't approved.

- **SSOT, one owner per fact.**
  - Freeciv owns the simulation: units, cities, diplomacy, terrain.
  - The bridge owns the realm state: court, deeds and ledger, marks, minds, chronicle, reign. Each fact sits in one place there.
  - The view keeps one mirror: `awareness.gd`'s realm and town blackboard scopes, filled only from `/world`. No other script parses `/world` or caches its own copy; they read the mirror.
  - Every plan names the owner of each new piece of state, and says nothing else holds a copy.
- **SRP, one decider per behaviour.**
  - Every agent's "what next" (townsfolk, soldiers, battles) runs on LimboAI trees. Movement code only moves.
  - A file or function doing two jobs gets split by job, not grown.
- **DRY: one place per rule.** A threshold, colour, time block, mood rule, clip pool or event shape is defined once and imported. Two copies of a rule is a bug waiting to drift.
- **SOLID.**
  - New behaviour arrives as a new tree, task, handler or data row, not as another branch in a growing `match` on kind strings.
  - Depend on the mirror's interface and on signals, not on another script's internals or on raw bridge JSON shapes.
- **Consolidating is expected; no fallbacks (Mac, 2026-11-12).** Rewrites toward these principles are welcome. The new code replaces the old in the same change: no switch back to the old path, no two systems doing one job. Carry every behaviour over (nothing lost), delete the old code. They're exempt from "additive" below.
- **One interface per behaviour.** Everything that moves goes through `realm/scripts/mover.gd` (`Mover.of(body).go(to, then)`): it asks the navigation for the route. Nothing tweens or sets a position to travel. Town life is one store and one reducer (`docs/TOWN_LIFE.md`): scenes, moods and reactions are data rows in `realm/data/town_scenes.json`, never new hand-written scene functions.
- **Check the rules.** Run `realm/tools/rules_check.sh` before committing `realm/scripts`; a breach is fixed, not added to `tools/rules_known.txt` (that list only shrinks).
- **Proof includes behaviour.** Compiling isn't working. Every NPC or tree change passes the headless behaviour probe (distinct activities, no repeats outside runs, no over-long holds, pools non-empty after clone) before it's committed.

1. **Write like the code around it.** GDScript doc comments (`##`) say what a thing is in the game's own words; same naming, density and idiom. Bridge stays plain Node with no npm dependencies.
2. **Additive.** No unrelated refactors. Ask Mac before a new abstraction. The game hasn't launched: a change to the saved realm's format (`bridge/chronicles/*/state`, `meta.json`) needs no migration or compatibility shim (Mac, 2026-11-12).
3. **Glue, not engines.** Our code connects Freeciv, Godot add-ons and assets. A new system needs a reason no existing block covers it.
4. **Check every edit.** GDScript: `arch -arm64 godot --headless --path realm --check-only -s res://scripts/<file>.gd`. Give explicit types to values from untyped nodes (`var d: float = terrain.…`), or it won't parse. Bridge: `node --check <file>.js`.
5. **Reload what you changed.** Bridge: `launchctl kickstart -k gui/$(id -u)/com.realm.bridge`. New or changed assets: `arch -arm64 godot --headless --path realm --import`.
6. **Never freeze the frame.** Big builds (towns, countryside) go through a per-frame budget or a coroutine; never a multi-second loop on a sync.
7. **Small commits.** One change each, by subsystem, staged by name. Never `--no-verify`.
8. **Third-party art stays out of git** (Sketchfab, Mixamo, Quaternius, Poly Haven): only its `.import` files and licences are tracked. Own art, code, docs and the baseline realm go in. See `.gitignore`.
9. **Never wait.** Renders, imports and long calls run in the background; resume from the notification.
10. **Local model:** text only, Off Grid's Omni 2B (or 1.7B), no call budget. Small model: short persona, real conversation turns, plain-text replies; JSON only for simple picks.

## Sessions share one checkout and one git index

Several sessions commit to `main` from the same folder. Never `git add` and leave files staged: another session's commit will take them. Commit only your own changes, in one step. A path commit takes the whole file, so if `git diff <file>` shows any lines that aren't yours (another session is editing it too), commit your hunks from a private index, so nobody else's staged or unstaged work can ride along (army-ui, 12 Nov: a path commit took three sessions' TUNING.md lines, and a plain commit swept the Freeciv thread's staged files):
  ```
  git diff <file> > /tmp/mine.patch   # trim to your hunks
  export GIT_INDEX_FILE=$(mktemp -u); git read-tree HEAD
  git apply --cached /tmp/mine.patch && git commit -m "…"; unset GIT_INDEX_FILE
  git reset -q -- <your paths>        # refresh the shared index to the new HEAD for those paths only
  ```
  Build the private index from HEAD **at commit time**: run `read-tree HEAD` right before `apply`, in the same command, never earlier. Make your patch with `git diff HEAD -- <file>` at that moment. Before pushing, read `git show --stat HEAD`: every file listed must be one you meant to change, with your line counts. (12 Nov: 404a533d's index was read before 620e8baf landed and put the old code back in 21 of the store thread's files.)
  Without that last line the shared index still holds the old blob, so every other session sees a staged revert of
  your change and its next commit undoes it (GoC). It touches the index only, never the files.
  The shared index is never touched. If the file is yours alone, `git commit --only -m "…" -- <paths>` (new files: `git add <paths> && git commit --only … -- <paths>` in the same command). Never a bare `git commit` in the shared folder. Then `git push`; if the push is rejected because another session just pushed, `git pull --rebase -q && git push`. Check the compile output is clean before committing, never after.

## Production grade

Mac's bar is a shippable game. Nothing debug reaches the player or the log: no animation lists, test pickers, key-help strips, internal names, `print()` traces or frame probes in committed code (keep test aids behind an explicit shot flag such as `--probe`, off in play). The player sees the world and the choices that matter; the game makes the rest of the calls. Read the run log of every render you take, and fix any recurring ERROR or WARNING rather than ignoring it.
