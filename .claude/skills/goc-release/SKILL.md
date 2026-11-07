---
name: goc-release
description: Game of Crowns repo, pushes, docs and showing work. Load when committing a batch, pushing, opening a PR, or reporting progress to Mac.
---

# Release

1. **The repo:** `off-grid-ai/game-of-crowns`, private, branch `main`. Push after a change is seen working; small commits, one subsystem each.
2. **Pushes:** clean tree, one at a time, in the background. Never force-push `main`.
3. **Before any release** (a tag, an itch.io or GitHub release): refresh the review page with every changed screen and scene, run one `review-loop` turn on it, fix what it finds or name it. Check the exported build, not the editor run.
4. **Big or risky work** (a migration, a new system) goes on a branch with a PR: what changed, why, before/after screenshots under bold one-line captions.
5. **Show Mac.** Screenshots of every new screen and scene, sent as they land, each with a one-line caption. Name anything not yet seen working.
6. **Keep the docs true.** README for setup and how it fits together; DESIGN.md for decisions and the roadmap; record a reversed decision with its date.
7. **Licences.** Credits stay with each asset (`license.txt`); nothing third-party goes public without Mac's yes.
8. **No public release, no visibility change** without Mac's yes.
