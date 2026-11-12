# Supervisor rulings (read before each commit)

Messages from the supervisor pause after 10 sends while Mac isn't typing. Rulings land here instead. Newest first.

- (11-12 14:45) **Army layer: go on both READY 3 hunks yourself.** (a) scenes.gd "muster" → `march_out`, delete `_muster` and its tween. (b) The war effect in `characters.js:1141` and `arcs.js:750` raises a muster at the attacker's seat. All three files were clean in the tree at 14:45. Freeciv thread: army layer holds those two war hunks; don't edit them until it pushes, then build story gap 1 (war declares war) on top. Read-tree HEAD at commit time.
- (11-12 14:40) **READY 3, march out: two calls.** (a) **Army layer** edits `scenes.gd`'s "muster" case itself (GoC's call, confirmed): it raises the host through `army.gd march_out`, and `_muster` and its tween are deleted in the same change. Nothing lost for any raiser (decrees, court, director, risings). Read-tree HEAD at commit time; scenes.gd has other writers. (b) **Freeciv thread:** the bridge's war effect (`characters.js:1141`, `arcs.js:750` `war`, and the story `war` gap 1) raises a muster event at the attacker's seat in `/world`, which the view turns into `march_out`. Do it together with gap 1 (war declares war in Freeciv), through `Lua.*`.
- (11-12 14:40) main.gd check-only is clean again (supervisor ran it at 14:40); the shot_harness.gd:390 report is stale.
- (11-12 14:30) **Commit rule (goc-engineering, 89c820f9):** build a private index from HEAD at commit time (`read-tree HEAD` and `git diff HEAD -- <file>` right before `apply`, in one command); read `git show --stat HEAD` before every push. 404a533d's early index put old code back in 21 files.
- (11-12) **Build first, film once (Mac):** no renders until every READY line is built and probed; then one full round (GoC); then refine.
- (11-12) **Properly integrated (Mac):** SSOT, SRP, DRY, SOLID, OOP, less hand code (goc-cpto, READY 15). Audit: docs/research/integration-audit-2026-11-12.md.
- (11-12) **Stories are the politics (Mac):** no separate trigger systems; story arcs drive risings and every arc effect reaches Freeciv (docs/research/story-options-to-freeciv-2026-11-12.md).
- (11-12) **Mac is away:** the supervisor decides every call; no thread waits on Mac.
