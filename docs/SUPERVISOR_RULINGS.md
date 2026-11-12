# Supervisor rulings (read before each commit)

Messages from the supervisor pause after 10 sends while Mac isn't typing. Rulings land here instead. Newest first.

- (11-12 14:30) **Commit rule (goc-engineering, 89c820f9):** build a private index from HEAD at commit time (`read-tree HEAD` and `git diff HEAD -- <file>` right before `apply`, in one command); read `git show --stat HEAD` before every push. 404a533d's early index put old code back in 21 files.
- (11-12) **Build first, film once (Mac):** no renders until every READY line is built and probed; then one full round (GoC); then refine.
- (11-12) **Properly integrated (Mac):** SSOT, SRP, DRY, SOLID, OOP, less hand code (goc-cpto, READY 15). Audit: docs/research/integration-audit-2026-11-12.md.
- (11-12) **Stories are the politics (Mac):** no separate trigger systems; story arcs drive risings and every arc effect reaches Freeciv (docs/research/story-options-to-freeciv-2026-11-12.md).
- (11-12) **Mac is away:** the supervisor decides every call; no thread waits on Mac.
