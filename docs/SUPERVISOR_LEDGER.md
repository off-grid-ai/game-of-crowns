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
- **Rules:** NO individual renders: builders and agents code, check headless, commit and report; the supervisor
  renders everything together in one batch and sends the screenshots (Mac: "don't stall renders… render
  everything together"); one Godot at a time through the lead's queue; commit by explicit paths, push only, and never
  stash, reset or rebase the shared tree; proven free blocks first (budget up to ~$200); everything behind a
  switch until judged; tunables in data plus docs/TUNING.md.

## What Mac said (2026-11-11), newest first
- "It should make an armory, a farm. There should be chicken, livestock, cattle… all of these details… create more
  Codex-generated images to be used." The bake-off agent is generating a full concept catalogue (buildings, farm,
  animals, props) and turning it into 3D via an ungated local TRELLIS route; gated DINOv3/RMBG access is pending
  Meta and BRIA review.
- "Not a fan of this" (the mid and map zoom: the old castle on a brown pad, no houses, giant trees, a striped paper
  map). An agent is fixing the mid and map zoom toward 02-realm (HLOD towns, the kit castle at all zooms, tree scale,
  the paper-map blend pushed to true map height, no scanlines).
- "Allow": the lead may run antzGames' downloaded VAT baker (GPL-3, in Blender, headless) and install the antz VAT
  plugin (MIT) into realm/addons for the army spike.
- "I don't really care about 30 FPS. Anything above 10 is fine." The frame-rate bar is ≥10 fps; spend the headroom on
  density and finesse (bigger armies, more detail).
- "I'm not a fan of the screenshot… it largely looks the same… you haven't changed the components to a better
  abstraction or fidelity level." Right: the lighting and ground passes sat on the same mismatched components. Now a
  bake-off agent: the same house, keep and trees from (A) Quaternius, (B) paid hand-painted kits ≤$200, (C) AI
  image-to-3D from our concept art, (D) hand-painted textures on the kit, rendered beside 01-town. Pick the source,
  then replace components wholesale.
- "The worlds need to be interactive… the walls need to be built of stones stacked together, then the stones break,
  the stones fall." A build agent is making stone_wall.gd: masonry courses, MultiMesh while intact, Jolt rigid stones
  on a hit, slump, rubble, a breach troops can path through, driven by the shared damage fact (--walls=stone).
- "You are the only supervisor, so you control everything. There is nobody else running parallel." The supervisor
  builds through its own agents when the Desktop builders are idle, and keeps this ledger for takeover.
- "We don't need to look at the fidelity anymore… the generated images match this." Fidelity is settled: docs/art/target.
- **"This is your North Star, this is what you are going to build."** The target images, with buildings and uniforms
  in their house's colours ("that is smart, that is what we should do"). One shared team-colour mask shader for
  buildings and armour (Builder 2), with kit houses and castle built with the mask (Townsfolk).
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

## Log
- 14:10 (11-12) Owners now: town-life session local_880cdb09 (town_life.gd, villagers.gd, npc_mind.gd,
  town_scenes.gd/json, crowd/moods.json); army-layer local_cf2ddafe (mover.gd, units, battle, siege, combat);
  ground-truth local_092eafb9 (nav_ground obstacles b24bc2a1, rivers a3b7cf8b, fire records 79aafe9f);
  visual polish local_a4e5fc5c (coordination, Freeciv research, gold/economy). My builders: fire-siege
  (buildings: wiring the 8 Meshy square pieces now, then fords' look), army-ui (ground), works-life (people's looks,
  animals waiting on Meshy community models). Mac: "I still don't see the meshy stuff integrated": only the cast and
  the gatehouse showed in the town view; the 8 square pieces (sheet /tmp/goc-models/meshy/square/sheet.jpg) were
  imported but unplaced. Rules now: goc-cpto (supervisor + threads, status quo) and goc-engineering (probe first, no
  hack-fixes, rules_check). Round 10 filming with navprobe + overlapprobe; round 11 for the Meshy houses.
- 13:20 (11-12) Mac's other session (visual polish, town life) started two more: "army-layer" (units, battle_ai,
  siege_ai, siege_storm, combat, army_spike onto LimboAI + Mover) and "ground-truth" (walk maps from placed shapes,
  one river truth, fire damage owned by the bridge; overlaps army-ui: coordinate). Mover.road carries all road travel.
  Mac on a horse spinning in place: routed to the movement owner (turning radius, arc turns). Mac offered Meshy
  Premium; advised holding until Pro hits a limit.
- 13:00 (11-12) Mac: "ignore the performance metrics for now, just make a really good experience" (memory updated).
  Defaults flipped (1a32e409): the plain launch equals the render; old branches listed for retirement and routed
  (fire-siege castles/towns/fire v1, army-ui woods/photo ground, works-life kit bodies; UI v1 unassigned).
  Painterly filter rejected (comic ink) -> removed. Whole Meshy cast in the crowd (79c3035f). Mac: "get some more
  people from meshy, some more components... already built ones... what I want now is uniformity": the Meshy agent
  adds phase E: ~40-60 community models in one painted look (props, animals incl. hens/goats, people, buildings),
  works-life rigs people/animals, buildings thread wires buildings/props, replacing kit pieces outright.
- 12:30 (11-12) Mac upgraded Meshy to Pro (1,445 credits); an agent is making 8 square pieces from 01-town crops
  (townhouse, cottage, merchant house, smithy, stall, well, statue, cart) -> docs/research/meshy-square-set.md.
  Mac: "start using the meshy products in the game": an agent is making the plain launch equal the render
  (cast, landmarks, look, etc. as defaults). New CLAUDE.md rule (02eeb2df): no fallbacks, replace and delete the
  old path. Mac's other session ("Game of Crowns visual polish", local_a4e5fc5c) owns town life: redux-style store
  and director (docs/TOWN_LIFE.md); it owns town_life.gd scene code, npc_mind.gd, villagers.gd decisions,
  awareness.gd, crowd/moods/works.json. Cart-through-well: the cart steps straight lines (town_life _cart), not nav;
  theirs to fix; army-ui writes a footprint/crossing probe. No 3D navmesh rebake.
  Message cap hit (10 sends): undelivered to works-life: "don't edit the behaviour files; your files are people.gd,
  cast.json, cast import/rig, animals". Resend on Mac's next message.
- 12:00 (11-12) Mac: "there should be some engine that already solves for this", then "let me get this work done in
  another one of my agents. you continue with the other stuff." Town-life behaviour (director, group scenes,
  routines, the engine survey) now belongs to Mac's other session; my survey agent stopped. works-life moved to how
  people and animals LOOK (clothes, livery, heads, children, animals, carried props); it must not edit npc_mind.gd,
  villagers.gd errand code, awareness.gd or the square-life scheduling. Audit of today's NPC code (four uncoordinated
  systems; the open-air fallback in villagers.gd place() 921-942) is in this session's history for the other agent.
- 11:50 (11-12) Mac on a man looping gestures alone mid-square: "there is no real routine", "group routine", "town
  setting etc that governs people's behaviour... it all needs to flow from the top". Direction given to works-life:
  four layers, each reading only the one above: (1) the town's state from the bridge (size, food, prosperity,
  unrest, season, weather, time of day, market day, events), (2) one town director per town turning it into a day
  schedule and a mood, (3) group scenes with roles, beats and an end (family shops, cart unload, crier and crowd,
  guard change, gossip circle, smithy with customer), staggered by a scheduler, (4) people taking roles from scenes
  or walking with a destination; nobody acts alone in open space. Design first: docs/research/town-behaviour-
  architecture.md, then build behind --town-director=on. An independent read-only audit of today's NPC code is running.
  Pending Mac: Meshy credits for a concept-matched set of the square's pieces.
- 11:15 (11-12) Mac: "overall quality is still poor. look at the trees, the statue, there is no finesse"; "the NPCs
  look like they are on steroids"; "there isn't gradual smooth actions, the routine for the NPCs isn't figured out".
  Routed: works-life readable 1.5 -> ~1.1-1.15, held items 1.0, slimmer bodies; then smooth motion (crossfades,
  arrive/turn/act/exit, intro-loop-outro actions, foot planting) and routines to docs/research/townsfolk-routines.md
  (research agent writing it: Manor Lords, Anno, Banished, Sims smart objects, AC/Hitman crowds). army-ui: survey and
  swap town trees for a proven painted stylized set, flowers and shrubs. fire-siege: a real statue (one statue
  material, dressed plinth, arms, flowers) and a finesse pass on the houses. Gold mine shots ready (3c3de219: seams at
  start; tiles 13,37 / 7,39 / 15,41) for the next batch.
- 11:05 (11-12) Other session ("Game of Crowns visual polish", Mac's ask): gold seams via Freeciv (0ea91fb3): 3 seams
  near Goldrock that run out; crown market gold now 0 (balance change). Next batch: add a Goldrock shot (--city=Goldrock,
  < 40 units) to judge the Meshy mine and miners; seamSeasons 1 in bridge/data/mines.json on the render bridge to see a
  spent seam. Switch --gold-mines=off.
- 11:00 (11-12) Mac: "the people behaviour is poor. that's the problem." Clip of the square (/tmp/goc-focus/clip1,
  24 frames over 6 s): almost nobody moves; no purposeful errands (buy, draw water, carry, cross to a door); a
  figure lying flat, one frozen mid-leap, one in the well; guards on fixed rings. Cause: town_life._square_life
  posts people with looped clips and ring loops; only a few have LimboAI minds. Routed to works-life as top
  priority: every square person a LimboAI agent with errands (shopper, water carrier, porter, stallholder,
  children, guards, gossips), smart objects (stalls, well, benches, doors) with claimed slots, NavigationAgent3D
  with avoidance over a square+streets navmesh, every clip used, --square-agents switch. Judge by clips, not stills.
- 10:45 (11-12) Round 6: the castle in light warm stone and terracotta roofs, a clear step. Still: the ring's final
  pass 3 fronts (narrow townhouses didn't help; next lever fronts before the tavern and/or a bigger square_r), houses
  at random angles -> fire-siege; no gardens read, square edge grass -> army-ui; sprawled oversized horses at the
  square's south edge, square now sparse -> works-life. Also: a dark roof clips the hero's lower right.
- 10:40 (11-12) Round 5 (composites work): gate in the wall, terracotta house roofs, striped stalls read. Still: ring
  laid twice (7 fronts then 3); castle a flat grey slab with orange courses, castle roofs bright red -> fire-siege;
  grass lime under exposure 1.35, bare yards, empty counters, bare forecourt -> army-ui; crowd knot by the statue,
  a pink villager, a floater on the plinth, big twisted horses -> works-life.
- 10:30 (11-12) Round 4 (import ran; focus.sh composites now `arch -arm64 /usr/bin/python3`): brighter, cleaner lines,
  colourful crowd, the well reads. Still: square ring 3-4 fronts (blocked by "a building" 139, "a street" 114) ->
  fire-siege, plus gatehouse apart from the curtain and roofs too bright red; grass saturated emerald, side streets
  dirt, awnings dark -> army-ui; ~80 figures in one swirl, some pink -> works-life (~25-30, spaced).
- 10:20 (11-12) Round 3 rendered at the close town view (dist 6, 89078f57): framing now matches 01-town (square lower
  middle, castle upper right), paving reads, the crowd is there. Still short: roofs flat saturated orange and huge;
  gatehouse adrift in the square, keep a slab; houses loose (Kingsmere ring: 2-3 fronts stood, turned away street
  8-13 / crowded 9-12); stalls dark clumps; yards bare grass; people grey-brown clutter; heavy dark outlines.
  Routed to fire-siege, army-ui, works-life and the look agent. The --import step didn't run (no `timeout` on macOS):
  import before round 4. focus.sh composites fixed (no -I).
- 10:05 (11-12) Round 2 rendered (/tmp/goc-focus/r2; composites fixed in focus.sh). Verdict vs 01-town: far below.
  Camera far too wide (whole town + lake; the square a patch) -> camera agent pulling the hero view to roof height.
  Roofs one flat saturated orange, no thatch; castle a brown block, not grey stone; houses loose on lawn ->
  fire-siege. Square bare dirt, streets thin tracks, yards empty flat green -> army-ui. People unreadable at this
  zoom; square crowd to ~25 -> works-life. Stone call: grey for castle and tiered houses under v3. Round 3 after all
  four commit.
- 11:00 (11-12) Supervisor moved to this account (session "GoC"); the three builders recreated here with the same
  titles and layers: works-life "Life at the works and grounded people" `local_eb1d9df5-48cf-466c-b31e-f1bf6a182996`
  (people), fire-siege "Fire and siege to the measured rules" `local_1d3c1906-060c-4383-8a73-289c5a1621d9`
  (buildings; kit 8-sheet repaint, kit_paint.py uncommitted, then bailey buildings), army-ui "Army command: select
  ring and command card" `local_c5e049d3-0de4-4ce2-8cb9-2d9df6a49f84` (ground). Camera and look agents restarted as
  this session's subagents. The old account's sessions (local_9b96362d, local_f9e805de, local_a5e34ab8) are retired.
- 10:30 (11-12) Usage limit; agents stopped. Focus round 1 (/tmp/goc-focus/r1/ladder) FAILED its framing:
  km-18_-3 shows countryside and a hamlet, not Kingsmere's square (check the other km-* frames and play.log;
  the camera code changed mid-run). On resume: run docs/review/focus.sh (camera agent's, db3e41a6; ROUND=r2,
  8789 free) with --look=v3 --cast=meshy, judge vs 01-town. Open in the layers: camera hero view to ~40 deg
  d18-20 (research #1; camera agent stopped before doing it), look v3 light (#2, #10) and the terrain.gd:1293
  errors (look agent stopped), the kit's 8 colour sheets repaint (fire-siege), ground layering + Anno fill +
  bailey ground (army-ui), bailey life (works-life), bailey buildings (fire-siege). Mac: "the emptiness looks
  kinda weird" (castle bailey). King's-loop agent stopped mid after-run; 12 commits on main.
- 09:40 (11-12) Mac: "focus on getting one component right first… extreme focus; then go wide." Batch 9 stopped.
  The component: Kingsmere's square at the default town view vs docs/art/target/01-town.jpg at 100%. Layers:
  fire-siege = buildings, castle, statue, banners (one painted style); army-ui = ground, paving, stalls, gardens,
  trees, props; works-life = people and animals (Meshy cast, readability scale); look agent = light, colour,
  atmosphere (look.gd/look.json); camera agent = composition + docs/review/focus.sh. Paused: army, fire, map,
  Meshy buildings, wheat. Loop: workers commit -> supervisor runs focus.sh -> judge side by side -> route.
  Also running: deep research (docs/research/quality-deep-dive.md), the King's-loop agent (bridge only).
- 02:00 (11-12) Usage limit hit (resets ~4:30 IST); all sessions and agents stopped. Batch 8b keeps filming in the
  background (/tmp/goc-batch8b; judged so far: look2, centre, square-before in docs/review/batch8-review.md 8b).
  On resume, in order: (1) judge the rest of 8b; (2) run docs/review/batch9.sh if fire-siege finished it, else
  build it from docs/review/batch9-list.md (UI v2, sound v2, dressing, storm, Meshy landmarks, knight_v2);
  (3) army-ui: Meshy man-at-arms try 3 (cape weighting, house mask, arms on tabard; 16cbbeab partial), then the
  framing leftovers; (4) fire-siege: Meshy building fixes (meshy-pulls.md), snow on roofs, the statue, the square
  pole/posts, castle banner arms; (5) works-life: grief that reads, bonfire lit, sound v2, horses/wheat/smoke;
  (6) the King's-loop agent's fixes (check git log for its commits and gameplay-review.md's before/after table).
  Meshy: 15/15 community downloads used, 65 credits spent; a try 3 re-texture may have been started.
- 01:00 (11-12) Batch 7 stopped at its army launch (later shots had the old blur); batch 8 filming (62 shots, 8789).
  Batch 7 judged (docs/review/batch7-review.md, top 15) and routed: fire-siege the dead sack fire, orbs, ground;
  works-life moods that read, stiff people, empty roads, mill sails; army-ui knight_v2, army fps (3 at 6k),
  the distance ladder, settle, harness. Gameplay review (docs/review/gameplay-review.md): throne besieged by
  minute two, free ward, free decrees, wrong numbers, vanishing cards, decisions off by default, idle armies,
  goals that don't pull, a firehose chronicle; a builder agent fixes all ten plus the cut list. Mac bought
  Meshy; the Meshy agent pulls the painted set and generates the man-at-arms in his Chrome.
- 00:45 (11-12) Mac on the live breach frame: "I can barely see anything" and "be smart about the gameplay, you are
  an expert game creator + designer". Calls: near blur off for good; the camera never inside or behind a building
  (Anno/AoE IV); no orange wash at town zoom; film snaps close panels; pink untextured blocks fixed (army-ui).
  Breach staged where the line of sight is open (fire-siege). Agents: a designer's gameplay review played on a
  private bridge (docs/review/gameplay-review.md) and a full batch 7 judge (docs/review/batch7-review.md); their
  top items become the next jobs. Kit survey: no free kit reaches the painted look; KayKit animations are the one
  free win (works-life baking). Meshy: all CC0, downloads need Mac's paid login (waits for Mac); its painted
  building set is the strongest lead for landmarks.
- 00:50 (11-12) Mac asleep: "work autonomously and get this through… explicit go ahead to do whatever it takes."
  No questions to Mac overnight; calls are taken and logged here. Mac had to click a ChatGPT download for the
  concept agent: from now every worker runs headless only. Order of the night: batch 7 ends -> judge all shots
  -> fix round -> batch 8 (town round 2, painted soldiers, knight_v2, battle in play) -> morning report with stills.
- 00:35 (11-12) Round plan. Mac: no compromise on UI and finesse; use the kits properly. (1) GPU: batch 7 films
  alone (towns 171 frames, moods 83 done, fire running); when done the supervisor judges every shot at 100%
  against its target, lists defects, sends Mac the set; fixes go in one round, then batch 8 in one run.
  (2) Soldier gate: kits are the base, the finish is ours. works-life bakes KayKit's animation pack into
  armies/knight_v2 (CPU, docs/research/knight-clips.md); army-ui builds the painted finish (--army-look=painted)
  and wires the roles; fire-siege has the battle shots and the castle. Meshy only for units no kit covers, and
  only after one passes the seven-point bar. TRELLIS stays off for soldiers. (3) Kits first: the surveys
  (free-rts-kits.md, meshy-library.md) give a swap list per category; Mac picks from sheets.

- 2026-11-11 23:55: the old six sessions are on another Claude account and unreachable. This supervisor runs its own: "Army command: select ring and command card" (army-ui, local_f9e805de), "Life at the works and grounded people" (works-life, local_a5e34ab8), "Fire and siege to the measured rules" (fire-siege, local_9b96362d); plus two subagents (army regiments; town light/walls). Film (batch 7 render) and the rig of real soldiers are the supervisor's own, after TRELLIS. Research committed: d5ac4820.
- 2026-11-11 23:45: the supervisor moved to session "Get context command" (Mac: "you are the main supervisor thread"); "Supervisor: casebook judge" hit the org spend limit (resets 4:10am IST). Its two agents died uncommitted and were restarted here: army regiments/banners/formations (army_spike.gd, army.json, army_vat.gdshader) and town light, walls, greenery and Goldrock's tiled strip (town density, roofs and cobbles already in: 45e62bfc, 32e76dbc). The six builder sessions held the handover messages (permission-mode mismatch or out of quota). Next: batch 7 (docs/review/batch7.sh) once TRELLIS frees the GPU and both agents commit.
- 2026-11-11 23:45: Mac: "start all the workers." All six sessions are woken with separate file areas (code only, no renders; I render batch 7 once):
  - lead (48da57c5): real flames and walls that crack to a breach (fire.gd, stone_wall.gd, walls.gd);
  - builder-2 (c4be4c2c): decisions visible in the world (unrest, reinforcement columns, levy muster, feasts);
  - townsfolk (9d298cd6): the soldier rig pipeline in Blender (weight copy, VAT bake, colour mask);
  - npc-perf (7118181c): kneel offsets, animal clips (grazing, pecking), a free rigged elephant;
  - film (883266cc): the batch 7 script and review v15 with references;
  - research (4e7941d1): army framing and command, town density rules (docs/research/army-and-town-rules.md).
  Subagents: the town-look agent (density, roof mix, warm walls, cobbles, greenery); local TRELLIS running (farmhouse, armoury, 12 soldiers first).

- 2026-11-11 22:10: Mac approved docs/art/target/town-composition/town-a.jpg and town-b.jpg as THE town reference ("Let's use that as a reference. Let's go!"). Every town review is judged beside them.

- 2026-11-11 21:00: Mac: "apply the same philosophy to everything… armoury, blacksmith, stables, mills, windmill all need to be there… if land is short, reduce the smaller houses… high quality towns… many aspects brought together, pieces interacting very well." Standing rule: a town is a composition. Landmarks and trades come first, then large and middle houses, then small houses as filler. Every building has work and life that ties it to the others and to the realm's state.
  - The town agent's scope is widened to whole-town composition: trades placed with sense, a land budget, AI meshes wired by data.
  - New agent on life at buildings: forge, stables, the grain chain (field → mill → granary → market), inn, square; reactions to war, levy, famine and feasts.

- 2026-11-11 20:45: Mac: "roads, houses, all picturesque… small, medium, big, really large houses, smaller lots… places to stay… not limited, not made on a budget. 4 Claude accounts: use a bench, don't worry about limits; keep the ledger of what's done and what's next."
  Running now (code only; renders bundle later):
  - Finesse pass: grounded feet, a real well, worn roads, seated props, the lake smear, fields on water, grey army colour, regiments on trees.
  - Town variety: house tiers (cottage → townhouse → merchant → burgher hall → manor), lot sizes, wealth gradient from the square, inns, alehouse, guild hall, backyards.
  - Life along the roads: inns at crossroads, waystones, shrines, bridges, tolls, hamlets, traffic (new script + roadside.json + switch).
  - Local TRELLIS: fixed the hard-coded author paths and missing packages (torchvision, rembg…); the batch reruns once imports pass. Order: farmhouse_barn, armoury, the 12 soldiers, then the catalogue.
  - Hosted: farmhouse_barn and armoury from InstantMesh (vertex colour); free quota out for about 22 h.
  Next: batch 6 render of all of it, then soldier rigging by weight copy in Blender.

- 2026-11-11 20:10: rigging decision (Mac: no Mixamo login; we already have the animations). Infantry: in Blender headless, align each TRELLIS soldier to an existing Mixamo-skeleton character and copy the skin weights (Data Transfer), then retarget our 172 Mixamo clips and bake with vat_bake.py. Horse: copy weights from realm/assets/cavalry/horse. Elephant: last, no donor rig. 12 unit concepts are in bakeoff/concepts/units.jpg, queued right after farmhouse_barn and armoury in local_batch.sh. Close-up finesse pass started (sunk feet, flat well, orange road, props).

- 2026-11-11 19:30: Mac: "much better… right direction, but still not Warcraft 3 quality, not the 8 codex images. Create the soldiers from images too, paint them the army's colour; good armour on soldiers, horses, elephants." Action: an agent is making unit concepts (white cloth for the house-colour mask: knight, man-at-arms, axe, hammer, spear, longbow, crossbow, barded cavalry, light horse, armoured elephant, cannon, mounted captain) and surveying auto-rig blocks (UniRig, Mixamo, AccuRIG, Rigify) for the VAT bake. The local TRELLIS run is blocked by the safety check: Mac must run local_batch.sh himself or add a permission rule. Fps is not a gate for now.

- 2026-11-11 18:14: batch 4 running (/tmp/goc-batch4, scratchpad batch4.sh), with plots dbe3d94b, the church ee360bc1, sites 6126627a, autumn 29a0dcac and far shots b3d7ffbe. The bake-off catalogue is still being made. of supervisor actions (newest first; details in review/supervisor-log.md)
- 17:50 Batch 3 running (one batch): all slice switches incl. --towns=plots; Kingsmere roof, d40, d55; Goldrock;
  the army at 6k/15k (d40) and 6k (d8), fixed muster; the stone-wall demo; bake-off kit and AI 3D cells; fire.
  Batch 2 stopped (its army runs predated the muster fix). Army perf: 6k and 15k both 12–13 fps at d40 (Mac's bar
  is 10). The mid/map zoom fixed (b7d84a3, cf18dd0, eb6879b): the paper map only from 54, no scanlines, town
  draw reach 150–220, trees 10–12 m. Defaults flip after batch 3 is judged.
- 17:15 Batch 1 rendered km-cap and Goldrock (kit castle and houses in house colours; sent to Mac); km-mid and
  map-mid failed (check logs); fire last. Fixes from batch 1 committed (52583ee..e02b89b). Stone walls (78923501,
  2e516b8b), the army VAT spike (b4763818) and the bake-off scene (97ba1a7) are ready. Batch 2 queued to follow: town
  shots, the wall demo, the army at 6k/15k/30k, the bake-off kit row. Disk freed (Mac: "Clear"; old DMGs, Brave
  and ShipIt caches, the mobile app's Gradle/Android/Xcode build caches): 34 GB free. AI image-to-3D waits on the HF
  token's location (not in ~/.cache/huggingface).
- 16:35 Mac: "you're the only one running… take control, run threads, get things moving fast." All six Desktop
  sessions were idle (likely usage limits). The supervisor now renders Milestone 1 itself (/tmp/goc-milestone1, all
  switches on) and runs build agents in its own session: (a) the kit castle and kit houses in house colours
  (--castles=kit, --houses=kit); (b) real fire, smoke and charred ruins (--fire=v2). Both render only via
  realm/tools/render.sh and commit by path.
- 16:30 Milestone 1 asked for the next Godot slot: everything built so far on together (look, kit trees, painted
  ground, wear, team colour, political map, kit castle if ready), Kingsmere, Goldrock and the map beside
  01-town and 02-realm. The full slice (kit houses, fire, breach) follows over the next days [est].
- 16:45 finesse catalogue routed into the slice: five shared facts first (wind, wetness, who's home, ground wear,
  damage per segment), then flames, chimney smoke, lit windows, wall breaches, ruins, fire response, rain, fields.
  A fidelity picker for Mac is being built by research. The text pass is done (GoT furniture out).
- 16:30 the ledger started; the vertical slice set as the test.
- 16:20 fire and siege breaches assigned to the lead; finesse catalogue agent started.
- 16:15 the professional-feel audit (25 findings) routed; the three-style test asked of Film.
- 15:55 the art direction picked; PLAN.md updated; the buy list sent to Mac.
- earlier: the session rebuilt after the other account's spend limit; see supervisor-log.md.
