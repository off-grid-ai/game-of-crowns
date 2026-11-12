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
| 1 | The square | Matches or beats r11 c01: open (visible paving ≥ 55%), detailed (≥ 16 stalls, ≥ 226 goods), people at the stalls, no one stacked or inside a building | Fire and siege, Town life | built (22bd0e9c square, 8b93de23 and bb90a325 people, f4049612 one inside-check) |
| 2 | People can walk the town | Kingsmere's walk map bakes (nav_dense_probe PASS); nobody stands still for lack of a path | Army command | built (996f29bb, nav_dense PASS) |
| 3 | War: the armies march out | When war is declared, the host forms up at its seat and marches out along the roads, seen from the town and the realm views | Army layer | built (b7f20217, 851cc670, 3731a4a5) |
| 4 | The right banner | Every regiment carries its own house's emblem and colours, on banner and livery, at every zoom | Army layer | built (1514f7ee, army_probe 10) |
| 5 | They fight | A battle reads on film: lines meet, men fall, a rout starts where they break and runs along the line ("Panic spreads") | Army layer | built (4e62a758, army_probe 8-9) |
| 6 | They lay siege | A host besieges a walled town: camps, engines, the walls take hits and breach, the assault goes in through the breach | Fire and siege (siege), Freeciv (the rules) | built (cd0c63ba, 8c29d79c, storm_probe 7/7) |
| 7 | Capture a town | The King's host can take a town by siege or storm, and it changes hands in Freeciv and on screen (banners, colours, the town card) | Freeciv (rule), Army command (the order) | built (76f2151b hamlets kept, 5fbb4361 Besiege order) |
| 8 | Command the army | Select a regiment or a host (select ring), give it orders from the command card: march, attack, besiege, hold, go home | Army command | built (5af67493 card, 5fbb4361 Besiege, d0a609b9 Attack and face, 26f6b930 select_host) |
| 9 | Politics you can see | A house's mood shows in the world (unrest in its towns, its land tinted in its colours); supporting a house sends your army to reinforce it; decrees have a cost you see; the story arcs are the politics (Mac: "our stories should be enough… they just need to be wired in"): every arc effect reaches Freeciv (a rising beat calls Freeciv's civil war; the usurper's and rebels' hosts march and fight) | Freeciv (state), Town life (unrest in the streets) | built: reinforce 687f170b; risings from stories b5bbac66; story war and defect d28e91c7; streets 5f1b558c, 070e8ddd, warning 1510732c; truce and plague wired since d28e91c7, story_gaps PASS |
| 10 | The world makes sense | A full reign plays end to end: no crash, no frozen screen, no unit vanishing, every action gets a reaction | Supervisor (playtest) | open |

## The foundations (Mac: "I want to see all of that in one shot… that's what I mean when I say everything in")

Audit 2026-11-12 (supervisor): what the design homework planned against what landed. These lines pass like the ones above.

| # | Line | What passes looks like | Owner | Status |
|---|------|------------------------|-------|--------|
| 11 | One store | Every view reads only `awareness.gd`: no raw `/world` handed to views (`main.gd` `_on_world`), no view fetching the bridge itself (`chatter.gd`, `villagers.gd`), no mind writing another's state (`fire.gd`, `npc_mind.gd`, `field_work.gd`); named actions with one reducer per slice; `rules_check.sh` enforces it | One store (new thread) | built: rules_known has no view-fetch/raw-world/cross-mind lines, rules_check exit 0, store_probe PASS (e6b55d48, 92ba7f74, edc1365b, 26bc543c) |
| 12 | Freeciv does the rules | Story arcs wired into Freeciv (line 9); reinforce decree; hamlets never razed; barracks' free company gone; levy and garrison at the rule sizes; Royal Court upkeep, tithe in ruleset Lua; income by source per house; miners and carts at worked mines | Freeciv | built: Freeciv side done (e516adac income by source, tithe/court f9b577dc, raid guard 444bdcb2, seam town 5739b093), miners and carts 3b135332 (mines_probe PASS) |
| 13 | People live by a plan | The director owns the day plan (no `villagers._block`, no random `Weigh` pick in the square); `square_probe.gd`; unrest in the streets reads mood from the mirror | Life at the works (moved from town life) | built: 6c092bdf square_probe, 69d2e8e3 day rows, d5b08bdb weighted round-robin, 86d10f8b bridge plan as one input (square_probe PASS) |
| 14 | Command card on | Attack and besiege orders exist, drag-to-face, and `host_command.json` is switched on | Army command | built (d0a609b9; host_command.json on since 5af67493) |
| 15 | Properly integrated | Mac: "everything properly integrated: SSOT, SRP, DRY, SOLID, OOP." Every finding of the architecture audit (supervisor, 12 Nov) fixed at its seam: one writer per fact, no duplicated logic, god files split, no second path left; less hand code (Mac: "make sure that there is less hand code"): what an engine block, add-on, Freeciv rule or data row can do is deleted from our code, and the hand-code line count goes down | All threads, by file owner | in progress: landed #1, #2, #3, #4, #5, #7, #8, #9, #10, #12, #13, #14, #16, #17, #18, #19; left #6 (one store), #11 (works-life, scenes.gd split), #15 (town life, dressings), #20 (all: knobs into data) |

## Look pass (Mac 11-12 16:20: "finish the build first", then this)
Mac on the war-slice frames: "the heavy cavalry looks so childish… even the banner sigils are off… even the trees look childish… this isn't what we agreed". The probes proved function, not the look. After lines 10 and 15 are built, before the full round is called done, each item below is judged by eye beside docs/art/target/03-army.jpg (and 01-town for trees) at the same framing.
| # | Item | Today | Target |
|---|---|---|---|
| L1 | Cavalry, knights, engines | KayKit chibi riders on a pack horse (`armies/cavalry`, `knight_v2`); engines drawn as knights | Meshy riders and horses in the regiments' painted set; engines are the Meshy catapult |
| L2 | Banners and shields | every regiment flies the crown's arms (crown over eagle); canton glyphs (arrow, cross, crescent that reads Ottoman) | each house's own arms on banner and shield, house colours on livery; no crescent |
| L3 | Trees | broadleaf lollipops on thin red trunks | painted broadleaf and pine as in 01-town and 03-army |
| L4 | Brown company | no house colour, reads modern | in house colours like every regiment |

## Milestone clips (part of the plan, never a stop)

Mac: "make this part of the plan. I don't want to lose time." A clip is cut when a group of lines is built. GoC renders it in the background through render.sh, and no builder waits for it or stops for it. Headless probes keep running beside it. Defects it shows go to their owners as normal items.

| Milestone | Lines | Clip |
|---|---|---|
| 1. The war slice | 1 (square), 2-8, 14 | /tmp/goc-focus/milestone1/milestone1.mp4 (rendering) |
| 2. The living realm | 9 (stories as politics, unrest), 13 (day plan), 11 (one store) | when built |
| 3. Ready to play | 10 (a full reign), 12, 15 | the one full round; then Mac plays |
