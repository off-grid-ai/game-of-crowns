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

## 4. The plan, in phases
Each phase ends with a measured reign against the fun bar, film judged against the copy sheet, and Mac
playing it. Work inside a phase runs in parallel by owner; one bundled Godot run per round.

### Phase 1, now: a reign that grips (the loop)
| Item | Owner | Done when |
|---|---|---|
| Seals that force a choice (two-way line, competing needs, a biased Hand and a second voice) | Builder 2 | 2+ worthwhile uses in ≥50% of seasons; always-the-Hand no longer clearly wins; then on by default |
| One court flow with painted faces, opened at the matter's town, results in words | Builder 2 | filmed at the town; no stacking; on by default |
| Event cards (~120, the director draws one a season by wave) | Builder 2 | no repeat within 8 seasons; a third start a consequence that lands; decision load held |
| The first ten minutes (opening v2: 2 screens, first card at 1:00, the ruling seen on the map, quiet to winter, 5 Hand prompts, reveal as it matters) | Lead | the timed harness shows first card ≤1:00, first ruling ≤1:30, setback from a ruling ~5:00 |
| Motion that reads at roof height (v3 props and posture; the square budget; no statues) | Lead + Townsfolk | gate equals or beats v2 on every line |

### Phase 2: a realm worth looking at (the look)
| Item | Owner | Done when |
|---|---|---|
| One building pipeline (research → pick → 30 types in one style) | Research, then a builder | prototype house and keep beside Manor Lords; Mac approves the look |
| Dense plot towns along growing streets | Townsfolk | ~20 houses at Kingsmere, ≥90% facing a street, beside the Manor Lords shot |
| Fire, smoke, sack and razing that read as fire | Lead | a still beside the reference |
| Light, grade, seasons and the map at three zooms, judged against the copy sheet | Builder 2 | side-by-side stills pass |
| Play at ≥30 fps at roof height in the busiest town | NPC perf | --perf numbers at Goldrock and Kingsmere |

### Phase 3: stories and people (immersion and the AI edge)
House pages and a lord's sheet (CK3's character window, one house page, never the whole dynasty);
lords' own words, rule in your own words, gossip; the chronicle feeding one reign-end sequence and act
interludes; the host's battle result card (CK3's war panels).

### Phase 4: the package
Main menu, loading card, saves as reigns, merged settings, sound and juice pass, ≥30 fps everywhere,
a filmed trailer from real play.

## 5. One change to the fun bar, said out loud
GAME_DESIGN.md's "≤1 decision a minute" was written before the King had his own verbs (seals, cards,
the host). It now reads: **court rulings about 1 a minute; all decisions together 1.5–2.5 a minute;
≥50% of time with no prompt up; no dead stretch over 45 s.** Measured today: 2.4–2.8 with seals, so
event cards thin out in breathers first if load rises.

## 6. How we work (so Mac can change anything while playing)
- Copy, don't invent: every screen names its reference from the copy sheet.
- One owner per fact; tunables in data; every system's knobs listed in docs/TUNING.md.
- New behaviour behind a switch until judged; the old path deleted once the new one is default.
- Batches tested together in one bundled run, judged on film and numbers, before claiming done.
- Proven blocks over hand-built code; first principles before patches.

## 7. Not now
Eye-level views and street walking; close-up realism; foot locking and turn-in-place; art policy;
endless reigns; any panel that competes with the world.
