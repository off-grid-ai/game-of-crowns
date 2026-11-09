---
name: goc-playtest
description: Check the whole of Game of Crowns scene by scene with renders and bridge calls, and report pass/fail with pictures. Use when Mac says "playtest", "check everything", "verify the game", or /goc-playtest.
---

# Playtest

Load `goc-run`, `goc-tests`, `goc-ux`, then, in this session:

1. **Checklist.** One list: do this → you should see this. Cover the title and new-chronicle screens, the realm map (labels, ticker), a town up close (people spread, moves fit places), the character close-up and editing, the court (options and own words), taking control (walk, talk, doors), a duel, each interior, feast, handover, battle, siege.
2. **One render at a time**, natively, each event-timed. Look at every image.
3. **Bridge checks** for what renders can't show: talk replies, rulings, chronicle entries, a death and its heir.
4. **Report each check:** pass with its screenshot, fail with what you saw, or not run and why. Each check's shot or clip goes on the review page as a version; each fail gets a mark on it (`screen-review` section 6).
5. **Score the fun bar.** Play one 15-minute reign and run every test in GAME_DESIGN.md's "The fun bar". Count from its chronicle: decisions per minute, quiet share, repeated matters and names, time from answer to visible change. Report each line's score next to the last run's.
6. **A failure is a bug.** Fix "now" items (broken, frozen, unreadable) here and recheck; log the rest in DESIGN.md's roadmap.
