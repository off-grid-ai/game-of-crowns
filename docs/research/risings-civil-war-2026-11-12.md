# Risings as Freeciv's own civil war (design only, 12 November 2026)

Status: **design for Mac's call. No code.** Supervisor's ask: the engine for VISION.md's planned "ignored promises
build into rebellion and riots" (Decisions that matter, item 2) and GAME_DESIGN.md's pillar 2 ("a house always gives
an ultimatum two seasons before it rises"). The usurper (a whole house marching on Kingsmere, `stakes.js`) already
exists. A rising is the other half: a house that **splits**, with part of its towns going over to a rival.

## Short answer

- Freeciv 3.2 has the whole mechanic: `edit.civil_war(player, chance)` splits a house in two, and Freeciv's own odds
  (its government, its unhappy and celebrating towns) can decide whether it happens.
- On its own it makes a dull rising, measured: a foreign nation and name, a random split, and rebels who never fight
  (40 turns, 0 attacks). That is the casebook's failure "The AI that doesn't play" (Medieval II).
- So the bridge supplies the parts Freeciv lacks: **when** (the ultimatum), **who** (the house's named rival), **a
  host** for the rebels and **an end** that the King rules on. Freeciv still does the split, the odds, the fighting
  and the town changes.

## What `edit.civil_war` does in 3.2 (source: `server/plrhand.c` S3_2, `api_server_edit.c`)

- **Call:** `edit.civil_war(p, chance)`. `chance` 1-100 is a fixed roll. `0` uses Freeciv's own odds
  (`civil_war_triggered`): the government's `Civil_War_Chance` (ours: Despotism 80, Monarchy 70, Republic 40,
  Anarchy 99) plus `civil_war_bonus_unhappy` (+5) for each unhappy town and `civil_war_bonus_celebrating` (-5)
  for each celebrating one (game.ruleset). It returns the new player, or nil.
- **Who can split:** `civil_war_enabled` (on in our ruleset) and at least 2 towns. The script call ignores the
  `civilwarsize` server option. It fails if the player slots or free nations run out.
- **Which towns:** the capital never goes. Of the rest, about half go, **chosen at random** (`fc_rand(2)` per town,
  forced so at least one goes and roughly half do). It's not by geography: a rebel town can sit beside the seat.
- **Units:** the men in a town go with it. Men in the field go with the town that supports them. Mixed stacks are
  moved to the nearest town of their own side.
- **The new player:** always AI, at the game's skill level, with no capital flag. Its nation comes at random from the
  house's `civilwar_nations` (e.g. Welsh lists Cornish), and its leader is that nation's leader name. It gets half the
  gold, all known techs and the map. It starts at no-contact with everyone, then war with its parent on first
  contact. One free capital building set and Freeciv's mid-game starting units go to a random rebel town.
- **The parent house:** falls into Anarchy for one turn, loses its embassies, and its research progress resets.
- **Signals:** each town sends `city_transferred` with reason `"civil_war"`, which our ruleset Lua already emits to
  the bridge as an event.

## Measured: one civil war on a fresh baseline (T38, 40 turns, all AI, no bridge)

`edit.civil_war(Stormhold, 100)` on the baseline save (`baseline/aldmere/saves/realm-T0038`):

| What | Result |
|---|---|
| Towns split | Stormhold had 6. The rebels took 2 (Abertawe, Caerdydd). It kept Y Barri (its seat), Burgos, Rainhold and Stormwatch |
| The rebels | Player 9, **Cornish**, leader **"Arthur Gernow"** (Freeciv's names, not ours). War with Stormhold from T38 |
| Their men | 1 unit at the split, 0-2 for the next 40 turns |
| Fighting | **0 rebel attacks, 0 towns changed hands between the two in 40 turns** |
| How it ended | **It didn't.** The rebels founded 3 more towns (2 → 5) and became a permanent ninth house. Stormhold lost a town to Thornvale meanwhile |

The rising works as a split and fails as drama. Like the raiders before their pillage season, Freeciv's AI with few
men and no target just sits.

## How a rising would start, from the bridge's existing state

Everything it needs is already kept:

1. **The fuse is the ultimatum we already have.** A house left cold (favour below the Grievance band) after the King
   ignores or refuses its matters at court sends the ultimatum (court.js, "a house always gives an ultimatum two
   seasons before it rises"). Today, when it's refused, the pretender path marches the **whole house** on Kingsmere
   (stakes.js). Proposal: the same ultimatum can come from **inside** a house. That's the house's named rival or a
   weak heir (characters.js roles `rival`, `heir`) against a lord the King has kept close, or whom the King has let
   rot. The casebook calls this "Lords with their own needs" (Norland: let a lord's loyalty sit too low for too long
   and his heir rebels).
2. **The bridge decides when; Freeciv decides whether.** On a refused or ignored ultimatum, the bridge calls
   `edit.civil_war(house, 0)`. Freeciv's own odds then apply. Grievance (already built: a cold house's towns lose
   content citizens) pushes towns unhappy and raises the odds. A Royal Feast or Royal Relief (already built) can make
   towns celebrate and lower them. So the King's earlier decrees really change the chance, and the bridge can show
   that number. One owner for each fact: Freeciv owns the odds and the split; the court owns the rival and the
   ultimatum.
3. **A death is the other fuse.** "The funeral is the crisis" (CK2): when a lord dies and a weak or child heir
   inherits, the same check runs once.

## What the bridge adds (so it doesn't fail like the measured one)

- **Our names.** The rebel player is the house's rival, recorded by the bridge (rebel player id → house and leader),
  so the realm says (e.g.) "Stormhold is divided: Ser Owain Stormhold holds Abertawe and Caerdydd against his brother." The
  narrator maps players to houses by that record, not by nation. Each house's `civilwar_nations` in
  `baseline/aldmere/data/nation/*.ruleset` gets pointed at unused nations, so Freeciv never picks one of the eight.
- **A host for the rebels.** At the split, `realm_host` (already used by the usurper) raises the rival's men beside a
  rebel town and sends them at the nearest loyal town. Freeciv's sieges (step 5, built) fight it out. Without this
  the measured rebels never moved.
- **An end the King rules on, within N seasons (in data).** The rising ends three ways:
  - **Crushed:** all rebel towns are retaken by Freeciv conquest. The rebel player dies.
  - **Settled by the King:** at court he can back the lord (the royal host marches, an existing decree), back the
    rival (the rival keeps his towns as a new lesser house), or broker terms (the towns return by
    `edit.transfer_city`, Freeciv's own call; the rival is pardoned or exiled).
  - **Left alone:** after N seasons, the side holding more towns keeps them.

  "Defeat is a chapter" (Kenshi): a lost rising leaves a smaller house and a grudge, not a game over.
- **The random split stays.** Freeciv picks the towns. We don't hand-swap towns afterwards, because that would be a
  hand edit with no game reason. The chronicle names which towns went over, so it reads as the towns' choice.

## What the King sees and can do

- **Before:** the ultimatum card two seasons ahead (as today), with one line of odds from Freeciv's own numbers: "3
  of Stormhold's 6 towns are restless. A rising is likely." The houses table shows the house's banner wavering. The
  casebook's "Starving next to full barns" failure (Banished) says hidden causes make players blame the game, so the
  cause is always on screen.
- **To head it off:** answer the matter, grant what the rival wants, or hold a feast or relief in that house's towns.
  Each of these lowers Freeciv's odds, and the card says by how much ("Dice that feel like cheating", Battle
  Brothers: show the odds and the tools).
- **During:** the split is shown on the map (banners change in the rebel towns), the rebel host marches, and each
  season's court has the rising as a matter: back the lord, back the rival, broker terms, or stay out.
- **After:** the chronicle and the reign's verdict remember it ("the King who let Stormhold break").

## Casebook cases it serves

- **Lords with their own needs** (Norland; towns chapter): a lord's low loyalty, left too long, makes his heir rebel.
- **Opinions run one way** (CK2; court chapter): the rival's grudge is one visible number, and the AI acts on it.
- **The funeral is the crisis** (CK2; dynasties chapter): a death with a weak heir is the riskiest moment.
- **Pushback** (CK3; engaging chapter): factions push back harder as the realm grows.
- **Defeat is a chapter** (Kenshi; stories chapter).
- Failures it must avoid: **The AI that doesn't play** (Medieval II; measured above, fixed by the host and the end),
  **Starving next to full barns** (Banished; the cause is always shown), **Dice that feel like cheating** (Battle
  Brothers; the odds and the tools are shown), **The blob** (EU4; strife at home as growth's friction),
  **Neither plot nor script** (CK3; the rising follows reasons the player saw).

## Open for Mac

1. Can the Crown itself split? It holds 2 towns in the baseline, so the capital stays and only the other town could go
   over. I'd leave it out: the usurper already covers a rising against the King.
2. When the King backs the rival, does the rival become a ninth great house in the houses table, or a lesser house?
3. N seasons before a rising settles itself (proposed: 8, like the raids).

Estimate if Mac says build: about 2 days [estimate] (Lua `realm_rising`, the court matter, the narrator record, the
host and end, a probe on the baseline).
