# Supervisor ledger

What the supervisor is doing, why, and what Mac said, so any agent can take over when a session hits its
limit. Newest first. The plan is [PLAN.md](PLAN.md); the running log of checks is
[review/supervisor-log.md](review/supervisor-log.md).

## How to take over (read this first)
- **Role:** supervise the builders, judge their work against the casebook, route Mac's notes, and keep the plan.
  Don't build yourself. Mac delegated product calls; record them so he can flip them.
- **Sessions** (Claude Desktop, linked; message with SendMessage to the id):
  - Lead "Lead: Kingsmere townsfolk gate" `local_48da57c5-2e45-48e4-a8ca-cb0fa880e5e6`: people, scenes,
    bridge state, fire, sieges, the opening; runs the one bundled Godot sitting each round.
  - "Children with parents, pops, talk" (Townsfolk) `local_9d298cd6-1614-4a7b-86ff-23a46b191039`:
    towns, plots, kit houses and castles.
  - "Carrying hands, foot slide, memory" (NPC perf) `local_7118181c-6fd7-4955-bdc4-17b232440833`: perf,
    the asset catalogue, data moves, trees, ground.
  - "Filming and review v14" (Film) `local_883266cc-63b2-41d1-8ff2-c70a8985ef97`: captures, review pages,
    style tests.
  - Builder 2 "Memory, schemes, UI and terrain" `local_c4be4c2c-8b73-4d21-8cf4-eb76c01d2fcb`: UI, court,
    seals, events, director, camera, audio, the look pass.
  - "Casebook research: medieval world sims" `local_4e7941d1-1530-4d30-81f3-017b5ad0e3c2`: research and
    the text pass.
- **Shared notes:** `~/Library/Application Support/Claude/side-session-notes/local_db7df5e6-a688-4652-832c-91640b1273c5/`
  (supervisor-rulings.md, reports, frames). Rulings go there when messages are rate-paused (10 sends
  without Mac typing pauses them).
- **References:** the casebook https://claude.ai/artifact/PzdycNn8Wj2xdTp8AX7AYK; the screen map, copy sheet
  and decisions https://claude.ai/artifact/PQ1pTTcw55iJAKBjuffWmZ; review v14
  https://claude.ai/artifact/A6bCmbxRLwqpgy3XPgaveL (Mac pins notes there; read `comments`).
- **The 10-minute check** is a session cron (CronCreate). Recreate it on takeover.
- **Rules:** one Godot at a time through the lead's queue; commit by explicit paths, push only, and never
  stash, reset or rebase the shared tree; proven free blocks first (budget up to ~$200); everything behind a
  switch until judged; tunables in data plus docs/TUNING.md.

## What Mac said (2026-11-11), newest first
- **"This is the level that we wanted to be at."** On the eight Codex concept images, now the art and interaction
  target in docs/art/target/ (README lists what each sets). Every visual change is judged beside its image.
- **Fidelity picked: "Foundation and mid polished is what I like."** His likes on the fidelity picker
  (https://claude.ai/artifact/VABqP8bqvo7BHqKEbVMoPn, db `fidelity`, 39 likes, 0 dislikes): Age of Empires II DE,
  Age of Mythology Retold, Foundation, Settlers 7 and New Allies, SpellForce 3, Warcraft III, Against the Storm,
  Tiny Glade, Old World, Diplomacy is Not an Option, Northgard, plus classics (Stronghold HD, Settlers II, AoE2).
  **The target is polished mid-fidelity** in that family. Armies: the VAT spike is approved (notes/armies-research.md).
- "Political influence can also be shown better" (the land tinted in the holder's colours, made far richer:
  CK3 map mode in the WC3 look, Builder 2). "Small inns and taverns with army people, roadways with small places
  in between… a really good world is what we need to build… our own twist." Roadside life along the great roads
  (inns, waystations, hamlets, travellers stopping; the lead plus Townsfolk), after the slice. No GoT names.
- **"Warcraft 3 is exactly what we want."** Mid-fidelity, polished, team colours. Armies dense and real ("when
  you say 6,000 soldiers are there, they need to be there"; tens of thousands), with cannons, artillery,
  horses, elephants, archers, swords, hammers, axes, spears and shields. Each house's armour in its own colour,
  with detail. Command my army. See decisions in the world: a displeased house shows visible unrest;
  supporting a house sends my army marching to reinforce them. An armies research agent is running
  (notes/armies-research.md).
- "A mid fidelity is what I want… polished but not hyper-realism… Warcraft II is mid fidelity… show me
  screenshots of other games so I can tell you the fidelity I want… and the world's components must
  interact effectively." A fidelity picker page is being built (research) so he can pick.
- "Beautiful does not mean hyper-realism… even at low or mid fidelity, if the interaction experience is
  great, we'll win. That's what you need to focus on." The slice is judged first on interactions (every
  action answered in the world, things reacting to each other), then on the look at our chosen abstraction.
- "I don't see too much difference since I left it… the gameplay is quite poor… what I'm gunning for is a
  beautiful experience where the world makes sense. We need to figure out whether we can actually create a
  world like that. Maintain a ledger so other agents can take over."
- "The magic is in the nitty-gritties": fire with real flames; walls crack, break and leave a gap;
  components interacting naturally. A stylised, non-real aesthetic is fine.
- Professional and non-gimmicky is priority one; gameplay depth follows. No filming beyond judging stills.
- Win mechanics and balance come later; first, people must want to play to the end.
- The casebook games are the competition; their finish is the bar; nothing below it ships.
- Keep building; components must be swappable (an asset catalogue); research better families in parallel.
- Free first, and purchases up to ~$100–200 are OK for a big jump. The buy list is waiting on Mac (below).
- Reuse proven work; never build from scratch where a block exists.
- Only the loop is ours; copy every screen and UX from proven games.
- Build for easy change: SSOT, SRP, data, TUNING.md.
- No close-up realism: the camera caps at roof height. Fun over fidelity.

## Decisions taken for Mac (reviewable)
- **The art direction:** a painted storybook look (Foundation's town view lit like Tiny Glade) with the free
  Quaternius kits. Report: notes/art-direction-report.md.
- **Seals and one-matter court** on by default; the opening v2 and motion v3 are defaults.
- **No arithmetic** on screen; a sober herald; grounded barks.
- **Waiting on Mac:** buying the Superhive painted-materials add-on ($29.99) and the Quaternius Village Source tier
  ($14.99); whether the "Rule in your own words needs Off Grid AI" line stays in every court card.

## Now (2026-11-11 16:30): prove the world can be beautiful and make sense
**Why:** a day of work behind switches changed little on screen; Mac judges what he sees. Before spreading
effort, prove in one place that we can reach the bar.
**The test, a vertical slice:** Kingsmere and its surroundings, finished to the casebook bar, everything
on by default:
- the lighting and grade pass (--look=one), painted ground, kit trees;
- a kit castle and kit houses in dense plots;
- people with visible jobs;
- real fire, and a siege that breaches a wall;
- a court ruling whose result is seen in the town.
Judged as stills and a short clip beside Foundation, Tiny Glade and Manor Lords. If the slice can't reach the
bar, we say so with evidence and change the approach (style, kit, a purchase) before going wider.
**Running in parallel:** a three-style test sheet (storybook, toon with outlines, 3D pixel; Film); the
professional-feel fixes (Builder 2); a finesse catalogue (an agent); the text pass (research).

## Log of supervisor actions (newest first; details in review/supervisor-log.md)
- 16:45 finesse catalogue routed into the slice: five shared facts first (wind, wetness, who's home, ground wear,
  damage per segment), then flames, chimney smoke, lit windows, wall breaches, ruins, fire response, rain, fields.
  A fidelity picker for Mac is being built by research. The text pass is done (GoT furniture out).
- 16:30 the ledger started; the vertical slice set as the test.
- 16:20 fire and siege breaches assigned to the lead; finesse catalogue agent started.
- 16:15 the professional-feel audit (25 findings) routed; the three-style test asked of Film.
- 15:55 the art direction picked; PLAN.md updated; the buy list sent to Mac.
- earlier: the session rebuilt after the other account's spend limit; see supervisor-log.md.
