---
name: goc-get-it-live
description: Take Game of Crowns work all the way to done: built, seen working, pushed, shown. Use when Mac says "get it live", "finish all the work", "ship it" or /goc-get-it-live on Game of Crowns.
---

# Get it live

You do the work, in this session, start to finish. Only asset fetching goes to the asset session (see `goc-cpto`). Load `goc-voice`, `goc-engineering`, `goc-ux`, `goc-tests`, `goc-run`, `goc-release`.

1. **State.** Read `git log`, DESIGN.md's roadmap, the asset reports (`downloads/realistic/*REPORT.md`, `~/Downloads/Aldmere/mixamo/*STATUS.md`) and what Mac has asked this session. List what's left. Never redo done work.
2. **Order the work.** One list, top to bottom: what blocks other work first, then what Mac can see. Keep Mac's exact words and the bar (`goc-ux` rule 1) in front of you.
3. **Build and prove each item.** Compile check, bridge call or render (`goc-tests`). Look at every render against `goc-ux`; fix a gap before moving on.
4. **Commit and push** each item as it's proven (`goc-release`).
5. **Review page.** Every finished item goes on the review page as a version with a Claude note; anything still wrong gets a mark (`screen-review`). Before a release, one `review-loop` turn (`goc-release` rule 3).
6. **Report.** Short status with screenshots: done, in progress, left (with rough times), and what needs Mac's hands (an Adobe login, a model loaded, a site allowed in Brave).
