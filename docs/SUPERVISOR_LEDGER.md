# Supervisor ledger

What the supervisor is doing, why, and what Mac said, so any agent can take over when a session hits its
limit. Newest first. The plan is [PLAN.md](PLAN.md); the running log of checks is
[review/supervisor-log.md](review/supervisor-log.md).

## How to take over (read this first)
- **Takeover 2026-11-13 11:39 (goc-throughput):** four threads on main, no test runs of their own: look `local_4e190f95-c310-4c7c-bb6d-d6c3f89fb652`, bridge `local_b8152a85-f9b5-40cc-9db6-5447648fa31e`, army-command `local_adc9a41f-852d-4c0a-be25-d3c9128b2e14`, square `local_35cb3d2c-b119-4f59-a0ac-937a64827297`. Every older GoC session archived. The supervisor runs the 12-minute round (cron :04/:16/:28/:40/:52).
- **Takeover 2026-11-12 (account switch):** the "Claude" account ran out of credits. The supervisor moved to a new
  session in another account and restarted only the threads with open work (Army layer, Life at the works and
  Ground truth were done and idle, so they were not restarted). Current ids, which replace the older list below:
  - Supervisor "Game of Crowns visual polish": this session (its id is shown by ListAgents).
  - "Freeciv: move the king's rules into Freeciv" `local_0a0368db-d8d8-4522-ae5d-d1c9f4328888`: raids as Freeciv barbarians.
  - "Town life: one director, hand-written scenes gone" `local_6abf9bb7-7230-46ea-875c-8e253bc08578`: blackboard "clip" error, parked bodies.
  - "Army layer: six systems into one" `local_f87ba101-b783-4de0-9186-5b9ba1e2f8ba`: READY 3, 4, 5.
  - "Life at the works and grounded people" `local_bbc2c617-c985-48f2-8ffc-c905f7a9f920`: works_probe, trades' workers.
  - "One store: every view reads awareness" `local_b52a8672-a42c-4e63-b841-6c4fa594c361`: READY 11.
  - "GoC" `local_9c8426ac-4628-4b65-9396-561a0acc3de3`: the round clock; it restarts its children "Fire and siege to the
    measured rules" (trades wave) and "Army command: select ring and command card" (walk map, double-click pan).
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
- 11-14 04:46 round: landed army a76aa20b (muster halts on the first clear stretch), look 9de3f58b (realm tint), a1f76cc4 + 4f857fbf (nature-tree leaves). g15 running (siege battle realm), g16 queued behind it (muster crossing realm). Bottleneck: GPU, kept full.
- 11-14 04:45 g14: town PASS (children by the well, small); muster FAIL 4th pass (among farm cottages and hedges): army told to reuse the open-ground pick that passed command. Bridge landed b921c75e 9fd28478 912d2ef6 cdc4b85d f9153955 c304a91b (every host marches; none appears at the walls; finale on its clock). g15 started (siege battle realm). Product calls: finale sets off early to land on time; no host spawns at walls.
- 11-14 04:33 round: landed army 70839c30 (muster beyond the last house, lens down the column), square 74dbe675 (children by the well). g14 started (muster town). Look quiet since 028fb9ad (white quads, shore trees open).
- 11-14 04:30 g13 done: muster FAIL (blocks among cottages, one cut by the frame, lens on a field), to army as its last open frame. Passing now: town, castle, siege, command, host5, crossing; realm improving.
- 11-14 04:21 g13 half: town PASS (one look, tavern matched, carts and horses). Forge glow still not seen after 5 passes: parked (my product call: minor, frame reads as 01-town). Square moved to gardens, washing lines, children. Bottleneck removed: a five-pass loop on a minor detail.
- 11-14 04:19 g12: crossing PASS (men packed on the cog's deck under standards, 406ee551).
- 11-14 04:09 round: landed army 406ee551 (host on the cog's deck). g12 started (crossing). Square silent on the smithy. Bottleneck: smithy, 4 passes.
- 11-14 04:07 g11: crossing FAIL (host's standard floats on the water, no men, deck empty: army); town has carts and horses in the square, tavern moved to the back but still dark, forge not in frame (square, 4th pass). Bottleneck: the smithy on square, 4 passes; asked for its place and the lens.
- 11-14 03:57 round: landed army 36abd21b (column to the cog, men on deck), look 028fb9ad (no snow on the winter shore), square 55981da2 (smithy room, tavern out of the near left). g11 started (crossing town). Bottleneck: none new.
- 11-14 03:48 g10 done: crossing now catches the cog at the shore (1b1f1075 works) but the host is one rider, deck empty (army), white quads, faceted shore trees, white sand (look). Muster: a big closed block plus blocks by the cottage, better. Bottleneck: ferried host drawn as its leader only.
- 11-14 03:45 g10 half: town smithy still out of frame after 02f8419d (third pass), the dark tilted building near left unchanged; back to square with the lens log. Nothing new landed. Bottleneck: square fixing blind; told to read the frame's .out/.play for the lens.
- 11-14 03:33 round: landed bridge 1b1f1075 (crossing frame with the host aboard), square 02f8419d (smithy faces the town lens). g10 started (crossing town muster). Bottleneck: none new; disk still on Mac.
- 11-14 03:31 g9 done: host5 PASS (first: closed blocks nose to tail on the road under standards); muster better (a column of blocks, still beside a cottage); crossing FAIL (frame of empty water after the ships put out; cog deck empty, host drawn as one rider): to bridge. Bottleneck: crossing frame timing after 9b8a7d7c.
- 11-14 03:21 g9 half: realm borders now bold and saturated (red and gold edges read): better than g8; town smithy fire still not in frame (square), setts brown and wet this pass. Nothing new landed. Bottleneck: disk still on Mac.
- 11-14 03:08 round: landed army bf4374e4 (closed ranks, muster on the road), square 5ec65938 (forge fire), look b8d74ee5 (bold borders). g9 started at once (realm town host5 muster crossing); its tree deleted on exit. Bottleneck: disk (16 GB), still on Mac.
- 11-14 03:05 g8 done: command PASS (first time: host in open ground, standard, selection square); siege PASS; host5 unchanged from g7 (51ffc2d9 not reaching the halted column), to army. Bottleneck: disk, one pass of room; g8 tree deleted at once.
- 11-14 02:57 g8 half: town smoke reads, smithy dark and fireless (square); realm edges present but faint (look); muster closer (two closed blocks with standards past the houses), still not a road column. Nothing new landed. Bottleneck: disk for g9 (waiting on Mac).
- 11-14 02:44 round: landed army f140da3c (command host clear of towns), 51ffc2d9 (muster past the houses, column closes up); look 20674fe8 (smooth tree crowns near the lens). g8 running at 1d3fb7f9 with all of them. Bottleneck: disk (16 GB, one pass of headroom), waiting on Mac for the 15 GB 11-12 scratchpad.
- 11-14 02:43 g8 refused: 13 GB free, render_pass needs 15. Freed 3.4 GB (old passes' tree copies). Restarted g8 at once. Bottleneck: disk; each pass keeps a 384 MB tree, so a pass now deletes its old trees. A 15 GB scratchpad from 11-12 (session 723231f3) awaits Mac.
- 11-14 02:34 g7: castle PASS, town PASS; host5 spaced on the road, off buildings (ranks loose); muster on dry land, low, but round a cottage; command UNCHANGED from g6 (16bf432d misses its lens path), back to army. Landed look 490f1730 (border edges), square 001d686e (smoke), 8c0a6321 (smithy). g8 queued after crossing. Bottleneck: command frame failed three passes; army told to trace the actual camera call from the .play log.
- 11-14 02:22 g7 half: town PASS (closest to 01-town), realm colours read but no bold edges (look). Landed bridge 5f451692 (siege ends, host leaves), 00980c74 (starved town hungry). Bottleneck: four threads idle, messages paused; look given realm edges, square given 01-town details (smoke, smithy, gardens, cart).
- 11-14 02:09 round: landed army 3130320a (block clears buildings), 16bf432d (command lens clear of walls), 4e438f06 (gate march); bridge 8c8cb623 (Peace march home), fc9a094c (raiders walk off), 9b8a7d7c (ships sail off). g7 started at 9b8a7d7c with all of them. Bottleneck: g7's 15-min grace for army; army landed early, grace cut, GPU busy 13 min sooner.
- 11-14 02:10 g6 (75050ca9), 0 script errors: siege PASS (breach, catapult, red blocks at the wall). Realm woods are masses, house colours faint (f8f8636f after). Muster high over the strait (74d5dbc3 after). host5 blocks on the road by the river but crowding a cottage; command lens inside a castle tower, no host: both to army. g7 queued (realm muster command host5 town castle crossing), 15 min grace for army's fix. Bottleneck: command frame keeps missing its host; one owner (army) on it.
- 11-14 01:35 g5 (0d8bad68), 0 script errors: town PASS (grey stone, red eagle cloths, grey setts; closest to 01-town yet). Realm big step (warm, relief, roads) but thin woods, faint colours, small seats (fixed after: 0979b1e9, 17f9f188, 21da3495, b1dd22d1). Muster a column but inside town (aba1c73f). host5 blocks on the road, head scatters. Command host hidden in forest; trees lime puffballs. g6 queued. Bottleneck: GPU; threads idle between passes.
- 11-14 01:10 g4 (2b59ac46) stopped after siege: a404e92d's freed-model error (9 per frame, no castle) made its other frames moot; fixed 5893e803. g4 showed muster as closed blocks with standards (scattered, fixed 0d8bad68), realm reframed (mostly sea; reframed again 0e12d21e). g5 started at once with every fix (castle, checkerboard 8de71614, trodden ground 2b64f396, warm map air 453f654a, seat castles 2b3c340d, muster column, crossing bounded). Bottleneck removed: no waiting on a pass whose frames a known break already spoils.
- 11-14 00:45 g3 (b99ca2ff): PASS town setts + castle stone, siege (breach open, catapult, red blocks), breach (gap open, small, no rubble spill yet). FAIL tower cloths blank (a404e92d), realm flat (look: sea/coast/border/framing landed; square: seat standards e2f713f5), command one figure (a985bfee: rec('hosts') was empty), muster off-road (b4f6c7eb), rust ground + faceted trees (ff0d00dd, aa9462a0). g4 queued behind g3 with full import, capped 90 min. Bottleneck: GPU; threads idle waiting on g4.
- 11-14 00:16 BOTTLENECK: g2's crossing frame hung 11 h (12:30 -> 00:16) after 'ordered over water', no Godot, blocking g3 and every render; the rounds checked the wrong thing. Killed; bridge bounds every wait in render_pass.sh's crossing block. g3 (9 views, everything to 3587972e and later) started 00:16. Rule taken: every round checks the render pass's last log line's age, kills a frame silent >15 min.
- 11-13 12:34 round 6: landed ddc6f494 regiments 8-10 abreast, 36542e73 field host as the muster column, 4b6d9875 open-country ground, b4b3a3b4 mood on the realm map, 720cdb03 washer and baker, 884553c0 wall towers' arms. g2 street: square houses, flower boxes and people read well; setts orange (fixed after in f6cc41c8). Bottleneck: g2's crossing frame holds the GPU up to 15 min, so it's left out of g3; g3 (9 views, every fix so far) queued behind it. Look, bridge and army-command wait on g3's results (by choice, to save spend).
- 11-13 12:24 round 5: landed f484eb98 breach pace, a4c16b47 Meshy catapults in a line, 640d95d7 red not pink, 1b5b1a4b painted fields, 712eb5d4 tents, f6cc41c8 setts from disk, dd473c4d castle dressed. g2 (8ebf9043): castle stone PASS, battle line PASS; FAIL setts orange + blank cloths (fixed after, in g3), marching host drawn as one figure (needs an owner: army layer archived -> army-command), open country flat lawn (look). Bottleneck: the app's 10-message cap paused routing until Mac types; all four threads idle.
- 11-13 12:08 round 4: landed b2f8fdf5 pike jab, 530a1188 setts grey, 45620832 render race fixed, ab485720 smooth leaves, c2d11aaf selection ring on the land, 8ebf9043 sea. g1 done: siege framing PASS; FAIL command no soldiers (army-command), breach not drawn + no engines (bridge, was idle), pink soldiers + striped fields (look). g2 (code 8ebf9043, fresh import) rendering 8 views. Bottleneck: the GPU pass (~6 min a frame); all four threads busy.
- 11-13 12:05 round 3: landed 7dc36e6c yards, 2cf30f28 alleys, 90b2d2f0 alley walkers, 5d58200b coverage cap (r11 court), f5340001 army lens + host5/season framing, 0bc9ec9c yards take painted pieces, b5ae0eae old ground gone. g1 town (code 194107ec): FAIL castle/wall stone still red, banners blank, setts orange -> look; square open and busy, 0 script errors. Bottleneck: the render pass, ~6 min a frame, on a code copy fixed at its start; kept to the views each round touches. Bridge idle by design, waits for failures.
- 11-13 12:00 Mac: the square keeps round 11's space (/tmp/goc-focus/r11/c01.jpg: a big open court, stalls in one block, open setts round the statue and the gate; paving >= r11's 59%); square thread told, streets and yards must not shrink it. Landed: bbad5f56 coverage, bed81993 click, 1940db8c siege framing, 94b03a87 crossing, 194107ec castle. Group test g1 (town siege breach command) rendering. Idle look -> yard pieces (Meshy), idle army-command -> pike jab clip + host5/season framing.
- 11-13 11:55 round 1: nothing landed yet (all four working). Bottleneck: stray test runs (reign harness, director probe, a test game, a scratch cloth.gd) killed; the rule is in goc-engineering and goc-throughput.
- (11-12) Mac asked for a short gameplay clip at a realistic milestone. Supervisor's call: milestone 1 is the war slice (READY 2-8, 14, all built): square, muster and march-out, command card, battle and rout, siege and breach, capture. GoC renders one ~60-90 s MP4 (/tmp/goc-focus/milestone1/), the one exception to build-first; broken parts are cut and listed as defects, not shipped.
- (11-12) GoC's call, approved (audit #7): one wall owner, walls.gd + stone_wall.gd, reading damage.js wear per section, so a town's own wall cracks and breaches in play. The dead kit-panel ring, the bay mesh and the on() switch go. The intact curtain keeps the kit look (slits, merlons, r11's walls); the stones show only where the wall is worn. Then, as its own change: a town has a stone wall when Freeciv's City Walls says so (SSOT), not by view rank; measure first, and seed the ruleset if too few towns have walls.
- (11-12) GoC r16 (/tmp/goc-focus/r16/sheets): square matches r11's look (openness 62% vs 59, setts 0.200 vs 0.210, 18 stalls, 98 people) but READY 1 FAIL on people stacked at (158,330) + east third bare; READY 2 PASS (0 convex errors, 1/200 walks crossing). Battle not filmed (minimap.gd parse break: 604 script errors), siege on the pre-cd0c63ba steps: lines 4-6 unjudged. Round clock stopped (Mac: build everything, then one full round).
- (11-12) Mac: "finish all your work and then play the game, and then refine… it's not making sense to play the game in between." No more 15-minute rounds: GoC's round clock and the supervisor's check are stopped. Build every READY line with headless probes; then one full filmed round; then refine.
- (11-12) Mac: "work autonomously. I'm not going to be here to approve anything, so just do what you think is right." The supervisor decides every call and logs it here; no thread waits on Mac. The goal: every line of docs/READY.md passes on film, then the game opens for him.
- (11-12) Mac on politics: "our stories should be enough right? … they just need to be wired in." Risings are not a separate trigger system: the story arcs drive them, and every arc effect reaches Freeciv. Supersedes the risings triggers in risings-civil-war-2026-11-12.md.
- (11-12) Mac: build risings ("Yes, my defaults"): the Crown never splits, a backed rival becomes a lesser house, a rising settles after 8 seasons. Freeciv thread, after line 7; it is the core of READY line 9.
- (11-12) Mac's "ready to play" list is docs/READY.md (10 lines: square, walking, march out, banners, fight, siege, capture, command, politics, a full reign). The game opens for him only when all pass on film.
- (11-12) Mac: "I want to be able to capture a town." Correction (Freeciv thread, 8d8eea11): it already worked. The King's march decree takes a town through edit.unit_move with conquer; the Norman ban in actions.ruleset binds only Freeciv's AI and stays. Call: a captured hamlet must never be razed.
- (11-12) Mac on what he likes in r11: "the level of detail, the openness". The square: wide and open at r11's size, house fronts at r11's distance, filled with many small readable things (wares, crates, goods, people). Openness is measured as the visible paving share of c01, with r11 as the floor.
- (11-12) Mac on r11 | r15 | 01-town: "tbh I like the first one" (r11 over the 01-town concept too). r11 c01 is the look to match for the square.
- (11-12) GoC r15 (/tmp/goc-focus/r15/sheets): square tighter and busier but 5 stalls, setts 0.092 FAIL (sand); rout logged t=29 one break then three at t=49 (half staggered), unreadable on film (camera far, 56-body clumps): routed to army-layer via top. GoC taken over in a new account; builders restarted (trades 176d0121, paving 747b57ef). r16 judged beside r11 + 01-town.
- (11-12) Mac: "Big square, 16 stalls". Kingsmere's square goes back to square_r ~1.8 with r11's stall and goods density and walk lanes (fire-siege); the tight 01-town square (7a8153dd) is overruled. Paving reads as stones again (747b57ef).
- (11-12) Supervisor's call: a raid strikes, pillages and leaves (disband after N turns, N in data). Why: with no town to take (a04b97d6), Freeciv's barbarian AI stood idle ~25 turns and pillaged 0 tiles. Mac can flip it.
- (11-12) Supervisor's call: Freeciv barbarians may not "Conquer City" (actions.ruleset), at every raiders level. Why: with raids as real barbarians (55bad97d), one raid took 9 towns in 20 turns (raid-guard-2026-11-12.md). Raiders still kill men and pillage. Mac can flip it.
- (11-12) Mac: "round 11 looks much better than round 15". Agreed: the market density was lost after r11 (01236c8d, a6c3c016), and in r15 the paving reads as sand (6a7746cf). r11 c01 is now the floor and 01-town the target; GoC routed density to fire-siege and paving to army-command.
- 18:20 (11-12) Mac: "the casebook is the right one... thats our goal" -> goc-cpto 6a5a4b04: casebook = bar for play,
  docs/art/target = bar for look; every change names its case. Freeciv move: steps 1-7 landed (sieges by Freeciv
  combat, seasons/blight, real moves, homed companies); setDiplomacy the one war writer until 3.3. Raids call
  (Claude's): Freeciv barbarians with onsetbarbarian 1, lowest level where unleash works, measured (>1 unprovoked town
  lost in 60 turns -> stop). Army: a tenth drawn + open ranks (160e97bd); Panic spreads next (army_morale.gd). squarelife
  (429fdf49). Tight square (7a8153dd). Bridge chronicle crash fixed (f21947a1).
- 17:25 (11-12) Round 13 sent (/tmp/goc-focus/r13): LIGHT PASS (mean 0.43, sat 0.466), 0 script errors. Wrong: square
  too big/empty (fire-siege: tighten to 01-town), 18 people inside things, several parked at (0,0) (town-life),
  navprobe empty map from blocks not water (army-ui), dclick pans rather than steps in (army-ui). Landed since:
  puddles off paving bc1c3500, wind read 2fae6748, cobbles true size 2cb050a2, kerb 91ee9fb2, soldiers a tenth and
  spaced 160e97bd (Mac: "let's see how that looks"), smith at the open front 3e7c8019, pen fit f0ed7cc8, bake-off
  retired 8e0a6021 (pick: current tree). Round 14 with the battle rendering.
- 17:40 (11-12) Mac: "i'm ok to reduce the soliders to 1/10th of the current" (round 12 field battle: 560 men, 1-6 fps).
  Army layer: one drawn soldier per ten, one ratio in army.json for every regiment, muster, battle, storm, siege; the
  UI keeps full strength; fps before/after. Round 12 sent to Mac beside his "super weird" shot. Ground truth on the
  server.js:449 private-bridge crash. Horses/carts landed 0ca5b08f.
- 16:45 (11-12) Round 12 (/tmp/goc-focus/r12, autumn, 0 script errors), sent to Mac. Big step: clean Meshy roofs,
  statue, well, 7 stalls at the edge, no planks/trees on paving. Light: mean 0.417 / clipped 0.04% / sat 0.42 vs 01-town
  0.431 / 0.5% / 0.47 (pass but for colour; r11 was winter 0.50/7%). Wrong: square thin, 16 people inside things
  (town-life); shadow blob right of the statue + brown smears (army-ui); dclick zooms OUT (army-ui); navprobe found
  no path, "ready after 0.0 s" (army-ui/ground-truth). Tree pick (delegated): no. 4, the current tree; bake-off retired
  (fire-siege). Rules: Mac "follow goc-cpto/goc-engineering", edit real files, private-index commits (17b74a57).
- 17:15 (11-12) RULING (pending delivery, message cap): Freeciv step 5 stays with the Freeciv thread (built, uncommitted:
  campaigns.js dice gone, Lua.assault, Royal Siege decree). Ground truth takes only D (breach removes City Walls, from
  damage.js). Reverses 16:40's B: in the baseline the King is at war with only Norwegian (0 towns) and the Orca, so B
  would forbid almost every march. Accepted: ctx.diplomacy (the save rewrite) as the ONE sanctioned war writer until
  Freeciv 3.3, owned by the Freeciv thread, its reload cost noted; no second writer. Mac: changes go in the real tree,
  never scratch copies (goc-engineering 82b95552); private-index commits refresh the shared index (b9dacd7c).
- 16:55 (11-12) Double-click zoom landed (f7de4b61, probe double_click_probe.gd: 20->13, aim on the spot, floor-capped).
  Double-click a soldier to select all of a kind (WC3): deferred to RTS command after the square (multi-select is a
  new system; hosts select one at a time today). Commits: always `git commit --only -- <paths>` (a bare commit swept
  the Freeciv thread's staged files into f7de4b61; nothing lost, 98f85600).
- 16:40 (11-12) Round 12 void: film bridge's Freeciv failed to load the ruleset (Freeciv thread's uncommitted step-3
  edits in the shared tree); stopped it; Freeciv thread told to land ruleset edits only after a load check; GoC rounds
  now abort without a world (players>=2, cities>=6). Square rounds every 15 min (Mac). Headless runs: 3 at once,
  bounded by perl alarm + watchdog.gd (2eeae236). Double-click (Mac, "whatever is the norm"): ground/building -> glide
  there, 35% closer, floor-capped (Total War, CK3); person -> select all of that kind on screen (WC3, AoE II); army-ui.
  Siege call (Claude's, reviewable): no war setter in Freeciv 3.2 Lua, so the breach removes City Walls in Freeciv, and
  the King's march is fought by Freeciv only on houses already at war (else refused with a clear line); dice deleted;
  no save rewrite; native war declaration is the open question (3.3 not stable; client-side pact cancel to look at).
- 16:05 (11-12) Freeciv move steps 1-2 landed (20c2ee09 ruleset Lua in realmrules/script.lua; c56a5f0d medieval
  ruleset, policies Levy Muster / Market Tolls / Granary Stores), main bridge restarted. Per Mac (via that thread): no
  private-bridge runs for it; probe, commit, reload. Route past 3.2's Lua limit: decree buildings now, favour as AI
  love on 3.3. Mac asked about Tripo AI vs Meshy: bake-off first (one building + the hen, same inputs), via GoC.
- 16:00 (11-12) Mac gave a Meshy API key (macOS keychain: `security find-generic-password -a goc -s meshy-api-key -w`;
  never printed, filed or committed). All Meshy work goes through the API, no browser. Balance 1,060 credits.
  fire-siege pushed the square fixes (13429948 roof patches gone, 01236c8d 7 stalls round the edge, 24084252 bake-off
  stands, 2759f0f9 awnings painted); works-life c49a6ae1 crowd dressed as 01-town. Round 12 waits on army-ui's dressing.
- 15:45 (11-12) Meshy API key from Mac, in the macOS keychain (`security find-generic-password -a goc -s
  meshy-api-key -w`; never in files or git). Balance 1,060 credits. All Meshy generation is headless via the API now
  (the square set had been made by driving meshy.ai in Chrome). Army layer landed 4e789399.
- 15:30 (11-12) Mac: "why not just start a thread to move the rules into freeciv?" Right: it's bridge + ruleset work,
  no Godot, no square files, so it runs in parallel. Session local_02d81d9f (renamed "Freeciv: move the king's rules
  into Freeciv") builds the note's steps in order, private bridge 8788/5557, no realm/ edits. Supersedes 15:20's "after".
- 15:20 (11-12) Freeciv research landed (22c72fe2, docs/research/freeciv-leverage-2026-11-12.md): our ruleset is stock
  civ2civ3; every king-game rule lives in the bridge, unseen by Freeciv's AI and its saves. Mac: move rules into
  Freeciv "after the square". Until then no new bridge rules; then decree buildings, riots/civil war, fought sieges,
  seasons/disasters, ruleset Lua; stop save-rewrite truces, dice sieges, armies from nothing, teleport walking.
- 15:40 (11-12) Light: 38f9f33d (look.json v3 exposure 1.35->1.25, white 5->8, bloom 0.08->0, saturation 1.25;
  weather roof snow 1.6->1.2; probe realm/tools/still_probe.py vs 01-town). Offline estimate only; next square round
  judges it (r11: mean 0.517, 7.7% blown, sat 0.39; target 0.431/0.5%/0.47). Ground snow tint -> army-ui.
  works-life: 1a7ebba6 own stride per body; animals approved square-first (chicken + dog, 70 Meshy credits, Mac's Chrome
  as before). Next round waits on fire-siege (roof smears, stalls) and army-ui (planks, crates).
- 15:20 (11-12) Mac: "Yes, square first": Kingsmere's square is the one gate; next render judged on it alone.
  fire-siege pushed 98b8e119 (Meshy square set, probe 0->17), 43283b40 (no trees on paving, 421->0), dc39742c (seats
  get the Meshy well, kit fountain deleted; Mac's "grey fountain" was the kit fountain). Next: roof-mask smears, 5-7
  varied stalls round the edges, bake-off standing; bridges later through roadside.gd (one system, roads.gd code goes).
  army-ui: square dressing (planks, crates). works-life: square people's looks + animals. Light: supervisor's agent
  tunes look data from round 11's numbers (luma 0.50/7% clipped/sat 0.38 vs 01-town 0.43/0.5%/0.47), no own renders.
- 14:50 (11-12) Mac: "Yes, square first". The Kingsmere square is the one gate until it's really right; every thread
  serves it, the next render is judged only on it. Mac on a square still: "its SUPER weird" (crowd knot, horse/cart in
  props, planks and tipped tables, strewn crates, grey fountain-well, trees in paving, washed-out light); on the Meshy
  king's statue: "this actually looks good" (the bar for every square piece). Meshy Agent/batch UI: not adopted (web
  clicks, drops Multi-view/texture options); the API pipeline stays and runs the next wave (farm, armory, animals).
  Army battle work and bridges wait; no new bridge rules until the Freeciv research lands.
- 15:00 (11-12) Round 11 (shared tree, Meshy wiring uncommitted; /tmp/goc-focus/r11/, 0 script errors), sent to Mac:
  Meshy houses, statue, well show round the square. Defects: roof house-colour mask reads as red smears, stray planks,
  stalls packed in rows. overlapprobe 19/53 inside something (18 people, 1 cart) -> parent routes. navprobe walked 0
  (broken) -> army-ui. Tree bake-off didn't stand ("work Kingsmere tree_bakeoff: none") -> fire-siege; no tree pick.
- 14:45 (11-12) Mac like: the Meshy king's statue in the square, "this actually looks good". It's the bar for the
  square set (full painted colour, gold trim, house banner on the plinth, clear silhouette). Mac on the square still,
  "SUPER weird": routed (note supervisor-routing-square-weird.md in the shared notes): grey fountain-well and trees
  in the paving -> fire-siege local_601300c6; angled planks/tipped tables and strewn crates -> army-ui local_3c38400b;
  crowd knot -> town-life; horses/carts in props -> army-layer; washed-out light held by the supervisor. Builders
  running: fire-siege local_601300c6, army-ui local_3c38400b, works-life local_a120f392. Round 11 rendering (the before).
- 14:25 (11-12) Takeover: the Claude-4 account hit its limit; all 8 threads restarted on this account, same tree.
  "Game of Crowns visual polish" (top) → army-layer local_e7013866 (mover.gd + army files; fixes the mover.gd compile
  break first), ground-truth local_2b1ad043 (commit its probes + GROUND_TRUTH.md), town-life local_964c05dc
  (director, probe first), GoC supervisor local_c8794c09 → restarts fire-siege (Meshy square wiring + bridges,
  uncommitted), army-ui, works-life, and runs rounds 10/11. Freeciv-leverage research rerun (its note was never written).
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
