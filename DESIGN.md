# Realm: design

**How we build:** system integrators with taste. Every system comes from an existing project (Freeciv for the world, Quaternius for art, Sky3D and Terrain3D for light and land, Godot to render). Our code is glue, and the glue is the design: what you see, when you see it, and how it feels. Before building anything, ask "who already built this?" Before shipping anything, ask "does this meet the pillars and the art direction?"

## Pillars
Every feature has to serve at least one of these, and none may break any of them.
1. **A world that lives without you.** Houses grow, starve, scheme and fight on their own. Nothing happens only because you pressed a button.
2. **See every consequence.** When the simulation changes, something on screen moves. A famine is brown fields and a queue at the granary, not a line of text.
3. **Rule, don't micromanage.** You are the King. You act through decrees, gold, armies and favour, not by placing every house.
4. **Peace is hard-won.** The houses want land, grain and glory. Keeping them from each other's throats while the realm prospers is the game.
5. **You are part of the story.** The reference is the *Warcraft* film: you're inside it, with people you care about, facing something bigger than any one kingdom.
   - The King is a person: a queen, an heir, a sworn champion and a small council who speak, disagree and can die.
   - You can ride out with the royal host. The camera follows your banner, and in battle you command your knights directly.
   - The reign has an arc: a threat from beyond the realm (the dead in the far north, or invaders from the sea) grows over time and forces the proud houses to unite under you, or fall apart.

## Story and experience
This is a game for one player, and it has to be engaging and fun, not just correct. Taste and storytelling are judged as seriously as the simulation.
- **People, not nations.** Each house has a living lord, spouse, heirs and a rival, with names, ages, traits and ambitions. Lords age and die, heirs inherit, a weak heir invites rebellion.
- **Major and minor lords.** Each great house rules through bannermen: minor lords holding its lesser towns, each with a name, sigil, ambitions and loyalty. Bannermen can be won over by the crown, bought by a rival, or rise against a weak liege. Every town that isn't a seat has a minor house.
- **Institutions of the realm** (each simulated, not just flavour):
  - **The Watch:** a sworn brotherhood on the old wall in the far north (its own Freeciv player). It survives on the men and grain the houses send; neglected in a long winter, the wall falls.
  - **The Kingsguard:** seven named, sworn knights with their own stories and loyalties, led by your champion. They ride with you and can die for you, or betray you.
  - **The small council:** Hand, Master of Coin, Master of Whispers, Master of Laws, Grand Maester. Each advises, each has an agenda, each is drawn from a house. Appointing and dismissing them is a political lever.
  - **Alliances, marriages, wards and oaths:** marriages bind houses, wards keep them honest, oaths of fealty are renewed or broken.
  - **Tourneys:** cost gold, raise favour, show strength, and sometimes end in blood.
- **NPCs with agency and memory.** Lords, ladies, heirs, bannermen, Kingsguard, council, and smaller folk: a merchant prince, an informant, a hedge knight seeking a patron, a septon preaching against your taxes. Each has wants, temperament and memory of how you treated them. They come to you, scheme, marry, betray and die. Freeciv gives them a world; Claude gives them voices grounded in the live simulation and their history with you.
- **The character layer (Crusader Kings-style, above Freeciv).**
  - Every lord has a family (spouse, children, wards) with ages, traits and ambitions.
  - Schemes run on their own: a minor lord angles to marry his daughter to a great lord's son, a widow plots for her son's inheritance, a younger son covets his brother's seat.
  - Some schemes need your consent as King (marriages that bind houses, disputed inheritances, broken betrothals).
  - Outcomes flow back into Freeciv: married houses ally, spurned houses sour, a claimant becomes a rebel.
  - This is glue we write (no open project simulates medieval families well); Claude gives it voice.
- **House strategies.** Each house's Freeciv AI plays its own temperament (traits set per nation): Ironreach raids, Stormhold seeks glory, Goldcrest trades, Thornvale builds and schemes, Sunspire and Highfell defend. Alliances, truces and wars between houses emerge from Freeciv's own diplomacy.
- **Emergent people (the goal: even you can't predict them).** Every named character carries:
  - identity: name, gender, age, house;
  - **allegiance:** liege, and how loyal;
  - **personality:** traits;
  - **personal goals:** "see my daughter wed above her station", "avenge my brother", "become Hand";
  - **relationships:** love, rivalry, debt, grudge, with memory of who did what.
  - **How it runs:** each season every character weighs their goals against the world and picks a move: scheme, marry, ally, betray, petition the King, rebel. Moves change others' goals and relationships, so it chains.
  - **Simple rules, many agents, memory:** that's where the unpredictability comes from.
  - **The deciding layer:** a utility system scores routine choices, cheap and deterministic. The pivotal choices of major lords (betrayal, war, marriage) go to Claude, given that character's file, memories and the live state, so they surprise even us.
  - **Grounding:** outcomes feed back into Freeciv (alliances, wars, city transfers, civil wars), so the world reacts.
- **Political favour as currency.**
  - Every house, bannerman and councillor has favour toward the crown, moved by decrees, gifts, marriages, appointments and judgments.
  - Favours are traded explicitly ("Stormhold backs your truce if Lord Robb is made Master of Laws").
  - A ledger of debts records who owes the crown and whom the crown owes. Call in a favour when you need it; leave a debt unpaid and it sours into a grudge.
- **Characters are editable text.** Every character (lords, ladies, heirs, Kingsguard, council, bannermen, smallfolk) is a plain file in the chronicle's `characters/` folder: name, house, age, traits, ambitions, relationships, voice, backstory. The simulation and the Maester read them. Edit an ambition and the character behaves differently; write a new file and a new person enters the story.
- **The court.** Each season, petitioners bring dilemmas drawn from the live simulation (grain, borders, marriages, feuds, crimes). Every choice has a cost and a visible consequence, and houses remember how you ruled.
- **A narrator with a voice.** The Maester writes the chronicle as a story: foreshadowing, callbacks to old grudges, the arc of your reign. Generated by Claude from simulation state, never generic.
- **Cinematic moments.** Big events (siege, battle, death of a lord, coronation of an heir) briefly take the camera there, then hand control back.
- **Stakes.** Your reign can fail: if the houses lose faith, a usurper marches on the capital. Survive, and earn a legacy title at the end of your reign.
- **Sound.** Ambient town life, war drums, bells for deaths and births, music that follows the mood of the realm.

## Core loop (every 2–5 minutes)
1. **Watch:** the realm lives; the camera invites you to look closer.
2. **Notice:** trouble surfaces visually first (armies massing, fields failing, unrest), then in the chronicle.
3. **Decide:** issue a royal decree.
4. **See it play out:** carts of grain on the road, the royal host marching, scaffolding rising.
5. **The realm answers:** houses' attitudes shift; Peace and Prosperity move.

## Time
- One Freeciv turn is one season; a year is about 4 minutes at normal pace. Dynasties rise and fall over an evening.
- No dead time between turns. The view interpolates everything: builders keep building, armies keep walking.

## Feedback map: every state change and what you see
| Simulation state (from the Freeciv save) | On screen | Also |
|---|---|---|
| Building in progress (shield stock / cost) | Staked foundation → scaffolding rising with progress → finished building; builders carrying materials | Chronicle on completion |
| Food stock low | Fields paling, queue at the granary, people moving slowly | Town banner icon |
| Famine (shrank from famine) | Brown fields, mourners, graves, families leaving with carts | Chronicle, sombre sound |
| Growth or celebration | Golden fields, market crowds, new houses at the town's edge, festival fires | |
| Unit in training | Recruits drilling in the barracks yard | |
| Army on the march (unit orders) | Column with house banner walking the road toward its goal | Border arrow at realm zoom |
| War between houses | Red border between them at realm zoom; battles where armies meet | Peace meter drops |
| City captured | Smoke, the banner changes, refugees | |
| Plague | Fewer people in the streets, sick in doorways, carts at night | |

## The King's decrees (player verbs)
Grain to a house · gold to a house · raise the royal host and march it · command a truce between two houses · grant a castle · strip a castle · raise a building in a town · fund a festival. Each costs royal treasury or favour, so every choice has a price.

## Resources and the royal treasury (ruling under constraint)
Every decree costs something, so ruling means choosing.
- **Gold:** from trade, taxes and gold deposits. Spent raising the host, on bribes, on festivals.
- **Grain:** town food stores. Spent on relief to starving houses and on feeding armies on campaign.
- **Timber:** from forests worked by towns. Spent on buildings, ships and siege engines.
- **Stone:** from hills and mountains. Spent on walls, castles and temples.
- **Iron:** from iron deposits. Spent arming the host.
- **Horses:** from horse-rich plains. Spent on knights.
- Derived honestly from Freeciv: food stores, worked tiles' terrain and specials, production and trade.
- **The tithe:** the crown takes a share of every house's output. A higher tithe makes you rich and the houses resentful; a lower one makes you loved and poor.
- **The ledger** shows realm totals, each house's holdings and your own stores, each with history charts.

## Chronicles: managing simulations
- **Many simulations side by side,** each with its own Freeciv saves, chronicle and scores (Freeciv's save files are the storage).
- **New from a scenario** (Aldmere, or saved custom ones) or **fully random:** random continent, houses, temperaments and fault lines.
- **Alter a simulation:** pace, fate frequency (plague, famine, the dead), house temperaments, starting wealth and grudges.
- **Set the length:** 5 minutes, 10, an hour, or indefinitely. When time is up, the reign ends with a verdict and a final score.
- **Long-running realms** keep going in the background (already true: the realm runs at login).
- **Hall of records:** every finished reign's score, verdict, length, and the key moments of its chronicle.

## Later: game night (multiplayer)
Parked until the single-player game is good. Freeciv is multiplayer at heart: 2–6 friends each take a great house (one may be King) for a timed 60–90 minute reign, with secret ambitions, table-talk alliances and betrayal, scored in the Hall of Records. Everything built for one player (decrees, favour, scoring, timed reigns) is what this mode needs.

## Measures
- **Peace:** share of house pairs not at war, weighted by battles fought.
- **Prosperity:** total population, food security, treasury.
- **Favour per house:** how each house regards the crown. A house with low favour rebels.

## Tone (your references: *Warcraft*, *300*, *Game of Thrones*, *Vikings*)
- Gritty and epic, never whimsical. Honour and its price, brotherhood and betrayal, raids from the sea, shield walls and last stands.
- Battles are framed like film: banners at dawn, slow push-ins on the clash, the horn before the charge.
- The Maester writes like a saga, not a report.
- Music is drums, horns and low strings.

## Art direction
- Locked to the gallery: Quaternius MegaKits (Village, Nature, Props), Sky3D light, Terrain3D land.
- Warm and painterly, never toy-like. Muted saturation, golden-hour light, soft atmospheric haze.
- Buildings are small against a large landscape.
- Nothing from mismatched packs; placeholder art never ships.
- **One animation family: Mixamo, for everyone** (decided 2026-11-04, replacing the 2026-11-03 "crowds stay Quaternius" split). Townsfolk and soldiers keep their modular Quaternius bodies (outfits, heads, hair, body shapes), but every model and every clip is retargeted at import to Godot's humanoid skeleton (`realm/assets/retarget/*_map.tres`), so any Mixamo move plays on any person: walking, work, haggling, prayer, grief, fighting. The townsfolk library is `realm/assets/anims/mixamo/`, each file one move named for what the game asks for ("Walk", "Sword_Idle", "Praying"). Quaternius's own Universal Animation Library is retired: its clips don't survive the retarget. The character close-up still uses its own Fuse/Mixamo rigs. The user downloads Mixamo moves (Adobe login); Claude wires them in.
- Heraldry: every house's banner and sigil lives in `realm/assets/heraldry` (prompts in ASSET_PROMPTS.md).

## World
- One hand-shaped continent rather than random noise. Regions with character: cold north, rich western hills, iron isles, green reach, stormlands, southern sands, high vale.
- Each house has a seat, history, wants, rivals and words, with old grudges seeded so drama starts on day one.
- Strictly medieval: a custom Freeciv ruleset stops research at the high middle ages.

## Strategy: functionality first, then polish passes
- Agreed 2026-11-03: get every system working end to end at a quality floor (readable, never looks broken), then polish in dedicated passes ordered by screen time.
- **UI/UX is approved** (see UI.md).
- **Polish pass 1:** battles and mustering are placeholders and not exciting. To do:
  - formations (shield walls, a charge, cavalry);
  - banners falling, the camera framing the clash;
  - drilling in ranks with spears, companies marching out through the gate.
- Then towns and life, then lighting.

## Build order
1. Medieval ruleset and hand-shaped map, with houses placed by the world bible.
2. **Vertical slice:** one region, two rival houses, one fully alive town, every row of the feedback map working, the King's decrees, Peace and Prosperity. Judge it together.
3. Scale to the whole realm. Scenarios, restart and the ledger with charts.

## Agreed roadmap (2026-11-03), in order
Done today: ground painted onto the land, court dilemma deck (43), battle rework, sieges, heraldry and ground art from Codex.
1. Panels never overlap (layout fix inside the approved UI).
2. "While you were away": a digest of the big events since you last looked.
3. Director camera: when you leave the camera alone, it drifts to whatever is happening.
4. Readable realm map at full zoom: house-coloured territory, red borders at war, legible names and sigils.
5. Seasons you can see: snow in winter, bare trees in autumn, blossom in spring.
6. Court rulings visible in the world: riders, wards arriving, outlaws hanged.
7. The royal host marching out of Kingsmere to where it's sent.
8. Ledger with charts (treasury, food, armies, towns per house).
9. Character view (Mixamo hero layer, see Art direction). *Done 2026-11-04, with editing a character's nature, aim and loyalty.*
10. Taking control of a character; interiors. *Built 2026-11-04: walk any lord or knight through their seat in third person, talk to townsfolk, and step through doors into the great hall, tavern, chapel or a cottage. Interiors are their own small worlds at true scale; the real rooms come from Codex (INTERIORS brief), with town-kit buildings standing in until then.*
11. Sound and music.
12. Polish passes: battles (shield walls, cavalry, drill, marching out), then towns and life, then lighting.
No dragons (dropped 2026-11-03).
