# Story options mapped to Freeciv — 12 November 2026

Mac: "our stories should be enough… they just need to be wired in." "Take a look at all the configuration
options in a story and map those to Freeciv." Source: docs/STORY_ARCS.md and `bridge/arcs.js` (`test()` for
conditions, the `do` block around line 720 for effects). Read from the code by the supervisor, not run.

Legend: **Freeciv** = acts in Freeciv today. **Bridge** = bridge-only state (court, minds), which is right when
Freeciv has no such thing. **GAP** = Freeciv has the thing and the story doesn't use it.

## What a beat does (`do`)

| Option | Today | Freeciv's own way | Verdict |
|---|---|---|---|
| `gold`, `pay` | `edit.change_gold` per house | same | **Freeciv** ✓ |
| `units` | `edit.create_unit` at the seat | same | **Freeciv** ✓ |
| `raid` | `realm_raid(town)`: Freeciv barbarians strike, pillage, leave (444bdcb2) | same | **Freeciv** ✓ |
| `war` | `realm_host`: units raised beside the town. **No war is declared**, so Freeciv's AI may not fight them | `setDiplomacy` war (the one war writer, bridge) first, then the host | **GAP 1** |
| `truce` | the court's truce only (no plots) | Freeciv peace/ceasefire via the same `setDiplomacy` writer | **GAP 2** |
| `transfer` | `edit.transfer_city` | same | **Freeciv** ✓ |
| `defect` | a named person changes house in the court only | if the defector holds a seat: `edit.transfer_city` of that seat (the town goes with him) | **GAP 3** |
| `die` | the court's death and succession | Freeciv has no named nobles; if the dead was the house's leader with a weak heir, that is the moment for Freeciv's civil war (`edit.civil_war`) | **GAP 4** (risings) |
| `favour` | bridge favour | Freeciv 3.3 AI love (`add_love`); 3.2 has none | Bridge, waits on 3.3 |
| `opinion`, `loyalty`, `marry`, `unwed`, `adopt`, `rank`, `goal`, `traits`, `reverie`, `believe`, `want`, `leave` | court and minds | Freeciv has no people | **Bridge** ✓ (right) |
| `seat` | the court only | none needed, but a seat must be a town the house owns in Freeciv | Bridge, add a check |
| `usurper` (declare + host) | `ctx.declare` → stakes.js, war through the war writer | same | **Freeciv** ✓ (verify the host marches) |

## What a story reads (`if`, `when`, role filters)

| Option | Reads | Verdict |
|---|---|---|
| `gold`, `units`, `towns`, `stronger`, `richer`, `holds`, `razed`, `houseGold`, `houseTowns`, `size`, `ownedBy`, `notCapital` | the Freeciv snapshot in `/world` | **Freeciv** ✓ |
| `atWar` | `ctx.atWar` (Freeciv diplomacy) | **Freeciv** ✓, but stories can't make war true (GAP 1) |
| `hungry`, `realmHungry` | bridge hunger from the snapshot's food | **Freeciv** ✓ |
| `plague`, `afflicted` | bridge town state (`ctx.town(id).plague`) | Freeciv has illness (civ2civ3 `illness`); read Freeciv's instead | **GAP 5** |
| `happened` | the chronicle (Freeciv events among others) | ✓ |
| `favour`, `opinion`, `loyalty`, `age`, `trait`, `remembers`, `rank`, `married`, `mood`, `reverie`, `believes`, `gone`, `inArc`, `seasons`, `act`, `threat`, `ruled`, `chance` | court, minds, the story itself | **Bridge** ✓ (right) |
| `usurper` | stakes.js stage | Bridge ✓ |

## The gaps, in order

1. **`war` declares war in Freeciv** through the one war writer before raising the host, so the host fights and
   `atWar` turns true. Without it, a feud's war is soldiers standing by a town (the casebook failure "The AI
   that doesn't play").
2. **`truce` makes peace in Freeciv** through the same writer (about 0.9 s a call until 3.3).
3. **`defect` takes the seat along:** a bannerman who defects with a seat hands that town to the new house.
4. **Risings:** a story beat (succession crisis, slow betrayal, the usurper's rise) calls `realm_rising`, which runs
   Freeciv's `edit.civil_war` (risings-civil-war-2026-11-12.md: its odds and split). The story supplies when,
   names and voice. No separate trigger system.
5. **`plague` reads Freeciv's illness**, so a story's plague is the one the town really has.

Each gap gets a probe that fails on HEAD (a story beat run against the baseline, the Freeciv state read back).
Owner: the Freeciv thread.
