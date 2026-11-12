# Ready to play: Mac's checklist

Mac (2026-11-12): "I want to play only once you've got everything in." "I want the game to be playable…
the world to be interactive, the world to make sense. I want the armies to march, to fight, to lay siege.
I want the politics to be better. When we actually have a war, I want to see the armies march out. I want
the armies to have the right emblem or banner. I want to be able to capture a town."

Build every line first, proven by its headless probe; no renders in between (Mac: "finish all your work and then play the game, and then refine"). Then one full round (GoC) films every line, and the game opens for Mac when every line passes, judged
against the casebook and docs/art/target. Each line has one owner, a probe that fails before the fix, and a
shot or clip that shows it. The status column is updated by the supervisor only.

| # | Line | What passes looks like | Owner | Status |
|---|------|------------------------|-------|--------|
| 1 | The square | Matches or beats r11 c01: open (visible paving ≥ 55%), detailed (≥ 16 stalls, ≥ 226 goods), people at the stalls, no one stacked or inside a building | Fire and siege, Town life | square built (22bd0e9c); people built (8b93de23, bb90a325); one inside-a-building check open (town life) |
| 2 | People can walk the town | Kingsmere's walk map bakes (nav_dense_probe PASS); nobody stands still for lack of a path | Army command | built (996f29bb, nav_dense PASS) |
| 3 | War: the armies march out | When war is declared, the host forms up at its seat and marches out along the roads, seen from the town and the realm views | Army layer | built (b7f20217, 851cc670, 3731a4a5) |
| 4 | The right banner | Every regiment carries its own house's emblem and colours, on banner and livery, at every zoom | Army layer | built (1514f7ee, army_probe 10) |
| 5 | They fight | A battle reads on film: lines meet, men fall, a rout starts where they break and runs along the line ("Panic spreads") | Army layer | built (4e62a758, army_probe 8-9) |
| 6 | They lay siege | A host besieges a walled town: camps, engines, the walls take hits and breach, the assault goes in through the breach | Fire and siege (siege), Freeciv (the rules) | built (cd0c63ba, 8c29d79c, storm_probe 7/7) |
| 7 | Capture a town | The King's host can take a town by siege or storm, and it changes hands in Freeciv and on screen (banners, colours, the town card) | Freeciv (rule), Army command (the order) | built (76f2151b hamlets kept, 5fbb4361 Besiege order) |
| 8 | Command the army | Select a regiment or a host (select ring), give it orders from the command card: march, attack, besiege, hold, go home | Army command | built (5af67493 card, 5fbb4361 Besiege, d0a609b9 Attack and face, 26f6b930 select_host) |
| 9 | Politics you can see | A house's mood shows in the world (unrest in its towns, its land tinted in its colours); supporting a house sends your army to reinforce it; decrees have a cost you see; the story arcs are the politics (Mac: "our stories should be enough… they just need to be wired in"): every arc effect reaches Freeciv (a rising beat calls Freeciv's civil war; the usurper's and rebels' hosts march and fight) | Freeciv (state), Town life (unrest in the streets) | reinforce built (687f170b), risings (6e14d444, triggers moving into stories); story wiring and unrest open |
| 10 | The world makes sense | A full reign plays end to end: no crash, no frozen screen, no unit vanishing, every action gets a reaction | Supervisor (playtest) | open |

## The foundations (Mac: "I want to see all of that in one shot… that's what I mean when I say everything in")

Audit 2026-11-12 (supervisor): what the design homework planned against what landed. These lines pass like the ones above.

| # | Line | What passes looks like | Owner | Status |
|---|------|------------------------|-------|--------|
| 11 | One store | Every view reads only `awareness.gd`: no raw `/world` handed to views (`main.gd` `_on_world`), no view fetching the bridge itself (`chatter.gd`, `villagers.gd`), no mind writing another's state (`fire.gd`, `npc_mind.gd`, `field_work.gd`); named actions with one reducer per slice; `rules_check.sh` enforces it | One store (new thread) | open |
| 12 | Freeciv does the rules | Story arcs wired into Freeciv (line 9); reinforce decree; hamlets never razed; barracks' free company gone; levy and garrison at the rule sizes; Royal Court upkeep, tithe in ruleset Lua; income by source per house; miners and carts at worked mines | Freeciv | open |
| 13 | People live by a plan | The director owns the day plan (no `villagers._block`, no random `Weigh` pick in the square); `square_probe.gd`; unrest in the streets reads mood from the mirror | Town life | open |
| 14 | Command card on | Attack and besiege orders exist, drag-to-face, and `host_command.json` is switched on | Army command | built (d0a609b9; host_command.json on since 5af67493) |
| 15 | Properly integrated | Mac: "everything properly integrated: SSOT, SRP, DRY, SOLID, OOP." Every finding of the architecture audit (supervisor, 12 Nov) fixed at its seam: one writer per fact, no duplicated logic, god files split, no second path left; less hand code (Mac: "make sure that there is less hand code"): what an engine block, add-on, Freeciv rule or data row can do is deleted from our code, and the hand-code line count goes down | All threads, by file owner | open |
