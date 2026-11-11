# The first ten minutes: today vs the plan (Builder 1, 2026-11-11)

Research: first-ten-minutes-research.md (notes folder; Reigns, Frostpunk, Six Ages, CK3, Against the Storm).
Today's numbers are read from the code; a timed run on a test reign confirms them in the next sitting.

## Today vs the plan

| | Today (code) | Plan |
|---|---|---|
| Screens before play | **5**: splash (2 pages), main menu, new-chronicle form (3 steps), forging, intro storybook (~18 pages, 6-10 s each) | **2**: "Begin your reign", then a name with a default |
| First court card | Court due on turn 1 (court.js:187, `lastSat == null`), so it sits while the player is still in the forge or the intro: **0 s of play** before it, and the realm waits behind the menu | **1:00**, after the camera lands and the Hand speaks |
| First ruling seen | Card turns, result as a toast; the map change isn't pointed at | **1:30**, the result shown on the map at the town |
| First goal | Royal ladder's "Raise a granary in Kingsmere" in the top bar from minute 0 (reign.js:112) | The Hand, once at 2:00: "Hold the realm whole to the first winter", with a seasons-to-winter tracker |
| First setback | Director: a threat rises in season 3 (~100 s) at the coldest house, not from a ruling (director.json quietByAct[0]=3); a cold house can send an ultimatum on turn 1 (season.js:85-123) | ~5:00, from the King's own ruling (the slighted lord returns), survivable |
| "One more season" pull | None designed | By 7:00: a visible countdown on a house's face |
| Hand prompts | None as such; tips on intro pages ("a season every forty seconds") | 5, in the Hand's voice, at 0:30, 0:50, 2:00, 5:00, 9:00 |
| Shown from minute 0 | Treasury, tithe, Court, Houses, Chronicle, Lore, Ledger, war orders on the town card, ultimatums | Court and the map only; the rest opens the first time it matters, with one Hand line |

## What changes, and where (behind `--opening=v2` until judged)

1. **Two screens.** title.gd: first launch skips the form (defaults; the form opens from the second reign).
   main.gd/intro.gd: the storybook becomes the loading card (one painting), skippable when the realm is
   built. splash.gd: off on first launch. *(view, Builder 1; title/ui pieces coordinated with Builder 2)*
2. **The first sitting at 1:00.** court.js: the first sitting waits for the player in the realm (camera
   landed) plus ~30 s, not turn 1. One small first matter with no right answer (a lord's grain plea).
   *(bridge, court.js)*
3. **The ruling seen on the map.** The card turns over (Builder 2's `--court=one`), then the camera-free
   ping at the town: banner tilts, town tint, a line. *(view: scenes/towns, Builder 1)*
4. **Quiet to the first winter.** director.json: no director threat before the first winter; season.js:
   no ultimatums before it (a grace flag); the first setback is the first ruling coming back (favourbook
   already returns weighty rulings after 2 seasons: tune the first to land ~5:00). *(bridge, Builder 2's
   director.js/season.js: their call on the knobs)*
5. **The Hand's five prompts.** One small module (hand_prompts: time and event triggers, shown in the
   Hand's existing voice), silent from the second reign. *(view, Builder 1)*
6. **Hide until the first winter.** top_bar.gd (treasury, tithe, ledger, houses), town_panel.gd (war
   orders): a `revealed` set on the bridge's reign state (one owner), each item revealed the first time it
   matters with one Hand line. *(Builder 2's UI files; Builder 1 owns the reveal state on the bridge)*
7. **Seasons-to-winter tracker** replaces the ladder's first aim until the first winter. *(top_bar, Builder 2)*

## Measure (the fun bar, on a scripted first ten minutes)

Time to first card, to first ruling, to first map feedback; screens before play; prompts shown; first
setback's cause (ruling or not). Today vs `--opening=v2`, same seed.

## Open for the judge
- The new-chronicle form's options (pace, cruelty, story) disappear on the first launch: they come back on
  the second reign. That's narrowing for a first-time player only; flagging per "never lose functionality".
