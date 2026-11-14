# Game of Crowns: the plan

One plan for the whole package, built from everything we have: GAME_DESIGN.md (the promise, the
loop, the fun bar, the engagement model), VISION.md (our track), UI.md, the casebook
(docs/casebook, https://claude.ai/artifact/PzdycNn8Wj2xdTp8AX7AYK), the screen map and its copy sheet
(https://claude.ai/artifact/PQ1pTTcw55iJAKBjuffWmZ), the research notes (event cards, house trees,
the first ten minutes, portraits) and what our own reigns and films measured on 2026-11-11.
Owner: the supervisor. When an idea disagrees with this file, change the file out loud.

## 1. The game
**Find out what kind of king you'd be.** A short, timed reign (15–60 minutes) ruled from above. Seven
great houses want your throne; you hold it at court and on the map, with grain, gold, marriages, your
seal and your word. History names you at the end.

What's ours, and nowhere else: **the loop** (court, seals, costs, houses that remember, pressure in
waves, a reign with a shape) and **lords who answer in their own words** through on-device AI. Everything
else is copied, screen by screen, from games that proved it (the screen map's copy sheet).

## 2. The three things that make it great, together
Quality means the whole package. None of these carries the game alone.

### Fun: the loop (most weight)
- **Every minute has a verb.** Rule at court; spend a seal (one a season, banked to two) on what you can't
  all do; answer an event card; order the host; build the Crown's lands. The King chooses *what* to do,
  not only how to answer.
- **Every answer costs, and none is always right.** Two worthwhile uses compete for each seal; the Hand
  argues one side and a second voice the other (King of Dragon Pass's council).
- **Goals at every distance.** The next thing (seconds), the season's seal (a minute), the ladder aim
  (minutes), the act's threat (a quarter), your name (the reign).
- **Tension in waves, the ending gets the most care.** Breather after every crisis; the last act builds to
  a named finale (proven: middle crisis share 0.50 → 0.20, last quarter 0.17 → 0.50).
- **Your choices come back,** by name, as grudges and debts, at court and on the map.
- **Juice:** every input answered within 0.2 s (a seal, a sound, a change in the world), and every result
  seen where it lands ("go and see", one key back).

### Feel: immersion
- **Decide on the map and see it there.** The court card opens at the matter's town, with the
  petitioner's painted face; the result plays in the world.
- **A world that lives without you:** busy towns where everyone has a visible job, houses scheming on
  the map, seasons, weather, light, sound.
- **One thing on screen at a time;** the interface at rest is one line.

### Look: one coherent style at our altitude
- **Our camera is roof height and above;** nothing is built for eye level. Good visuals mean beautiful *at
  that altitude*: light, colour grade, seasons, silhouettes, a busy readable town, a gorgeous map.
- **One art style across everything.** Today's buildings are mismatched kits (a grey box castle, an
  out-of-scale barn). A single building pipeline gives ~30 types in one look; painted portraits share
  one grade and frame.
- **Towns read as towns:** dense Manor Lords plots along growing streets, fields beyond, a clear edge.

## 3. On-device AI (Off Grid AI): our edge
The game plays fully without it and is much better with it. In order of payoff:
1. Lords and petitioners speak their matters in their own words, from the real state of the realm.
2. **Rule in your own words** at court: the King's sentence becomes the ruling.
3. Townsfolk gossip that repeats your rulings back to you.
4. The chronicle and the reign's ending written about *your* reign.
The local model only words what the rules decide; choices and costs stay authored.

## 4. One list, built at once (Mac, 2026-11-14: "single phase, do everything in one go")
No phases. Every thread builds its part of this list at the same time; the supervisor renders everything that landed
together each round. Status from the audit of 2026-11-14 (11 done, 28 partly, 5 not started); done items are left out.

| Owner | What's left (player impact first) |
|---|---|
| **Loop** (court, cards, juice, herald, opening, sound, menus, settings, saves UI, lord's sheet) | Seals that force a choice (competing needs, a biased Hand, a second voice); event cards 20 → ~120, no repeat within 8 seasons; one matter at a time with riders and deadlines; every click answers out loud; sound_v2 on as the one sound system; juice with sound; kill the repeats (≥90% distinct lines); the crowd echoes rulings; the King's works with a crown pennant that can be threatened; an ending (Omni epitaph) and a grudge into the next reign; court and inn frames in the render pass against 05-court and 06-inn; a lord's sheet; one settings screen; saves as reigns (UI) |
| **Bridge** (bridge/*, Freeciv rules) | Raid strength and framing (047bee66 to judge); event card data and the deadline/rider rules with Loop; saves as reigns (bridge side); the host's battle result card data; our own people sim: lasting households beyond the 8-54 sample; the epitaph and grudge data |
| **Army** (units.gd, army*.gd) | Raid band (b63f0f62 to judge); siege taken (0 taken lines at g24-25); decisions seen on the map, on (07-unrest, 08-reinforce); the host's battle result card |
| **Square** (towns, town_life, smoke) | Street (e1db9235 to judge); smoke (5c115280 to judge); the ten Meshy house pieces placed so houses share one style; crowd density down to the target (9.4 → ~6 per 100 m², groups of 2-4 up from 0.23 to ~0.65) |
| **Look** (woods, stone, terrain, grade, fire, snow) | Seasons (7883bc4e to judge); snow passed; one grade frame beside the target; a sacked town; the map's middle zoom; the other cities checked (coastal, small, hill) |
| **Supervisor** | Renders of everything that landed, every round; a trailer from real play once the list is mostly done |

## 5. One change to the fun bar, said out loud
GAME_DESIGN.md's "≤1 decision a minute" was written before the King had his own verbs (seals, cards,
the host). It now reads: **court rulings about 1 a minute; all decisions together 1.5–2.5 a minute;
≥50% of time with no prompt up; no dead stretch over 45 s.** Measured today: 2.4–2.8 with seals, so
event cards thin out in breathers first if load rises.

## The first test: would they play to the end? (Mac, 2026-11-11)
How a reign is won (money, men, support) gets tuned later. First, a player must want to play to the end, so
nothing may feel gimmicky and everything must feel professional: consistent type, spacing, timing and
sound; eased transitions; no placeholder text, gags or arithmetic; no bugs on screen. This is priority
number one; gameplay depth follows once it's true. No filming beyond the stills needed to judge a change.

## The world is made of its parts (Mac, 2026-11-11)
Move up to our fidelity level, then make the world make sense: each thing is built from the parts it's really made
of, and they behave. Walls are stacked stones that crack and fall; fire is flames and smoke that spread with the
wind; an army is its soldiers in formation; a town is its houses and the people who live and work in them. No
faked whole objects where the parts should act. Finesse is in how the parts behave together.

## The target images (Mac approved, 2026-11-11)
docs/art/target/: eight concept images (town, realm map, army, siege, court, inn, unrest, reinforcement) at
polished mid-fidelity, Warcraft III/Foundation family. Every visual change is judged beside its image.

## The bar (Mac, 2026-11-11)
The casebook games are the competition, and their finish is the bar; nothing below it ships. Every visual
change is judged as a still or clip at the same framing beside its reference shot from the casebook and
the screen map (Foundation and Tiny Glade for towns and light, Manor Lords for layout, CK3 and KoDP for
the court and faces). It goes on by default only when it holds up beside that shot, judged by the
supervisor and shown to Mac. Where a free kit can't reach the bar, say so and price the fix (budget up to
~$200).

## 6. How we work (so Mac can change anything while playing)
- Copy, don't invent: every screen names its reference from the copy sheet.
- One owner per fact; tunables in data; every system's knobs listed in docs/TUNING.md.
- New behaviour behind a switch until judged; the old path deleted once the new one is default.
- Batches tested together in one bundled run, judged on film and numbers, before claiming done.
- Proven blocks over hand-built code; first principles before patches.
- Every world component comes through one asset catalogue (component id → model, scale, footprint,
  variants), so a better free asset family can replace today's in parallel, as a data edit. Building never
  waits for the art pick.

## 7. Not now
Eye-level views and street walking; close-up realism; foot locking and turn-in-place; art policy;
endless reigns; any panel that competes with the world.
