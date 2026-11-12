# Every decision, and what the King gets back (2026-11-12)

The rule (GAME_DESIGN.md's feedback ladder; Mac): every action gets a reaction the King **sees** at the town,
**hears**, and **reads**, within seconds. References: Frostpunk's laws (a law signed: the city's people react on
the street at once, and the discontent/hope bars move), CK3's event results (the result line names whose opinion
moved and why), Stronghold's popularity cues (the crowd's mood and a sound you learn: cheering, booing).

Read from the bridge as it stands today (after the cut list a92cee9d, costs 4211e5c3, host march 727cdc40, ward
fix 3eb32736): `bridge/data/decrees.json` and `crown.js`, `routes_decree.js`, `court.js` (`rule`, `rulingScene`),
`rulings.js`, `hosts.js`, `events.js`, and on the view side `news.gd`, `soundscape.gd`, `sounds.json` (v2),
`main.gd` (Juice: the seal at the click, the result told at the town).

What every decree already gets, whatever it is:
- **Hears:** the seal at the click (`ui("seal")`); coins when it costs (`paid`); the error sound on a refusal.
  With sound v2 on, the bell over the realm (`ui_seal`).
- **Reads:** the result at the town as the latest news (edge arrow, Space to look); the result card names whose
  favour moved and the price; a chronicle line (kind `decree`).

So the gaps are mostly **sees at the town** and **hears it land** (the town's own sound, not the seal).

Marks: ✅ there; ◐ partly (only on the road, or only later); ❌ nothing; — not needed.

## Decrees (the King's orders; `decrees.json`)

| Decision | Sees at the town | Hears it land | Reads | Gap, worst first |
|---|---|---|---|---|
| **Relief** (grain) | ◐ a grain wagon on the road (only when the town is not the seat); the town itself unchanged; at the seat nothing at all | ❌ | ✅ | **1.** No mark in the town: the relief dressing (buyers at every stall, goods heaped, the herald cheered) exists for court rulings but not for the decree. At the seat the decree is invisible. |
| **Grant** (a town given or taken) | ◐ the handover scene, the town's colours change | ✅ quiet fanfare (King's handover) | ✅ | **2.** The grant dressing (the new house's banners round the square, its holding begun) is not posted. |
| **Build** (the crown pays a building) | ◐ the rider on the road; the building site rises at a crown town | ✅ gallop | ✅ | **3.** No builders at the site: the build ruling dressing is not posted. |
| **Feast** | ✅ feast at the seat: bonfire, tables, bunting, dancers (celebrating) | ❌ no cheer (the cheer plays only for a lord's feast) | ✅ | **4.** Silent feast. |
| **Marriage** | ✅ feast at both seats | ❌ no bells (the chronicle line is `decree`, not `marriage`) | ✅ | **4.** Silent (same fix as the feast). |
| **Promise** (a council seat) | ❌ nothing anywhere | ❌ | ✅ | **5.** Nothing at the lord's town: no rider carries the word. |
| **Ward** (an heir to court) | ◐ the ward's party on the road | ❌ | ✅ | **6.** Silent on the road. |
| **March** (the royal host) | ✅ the host moves on the map; siege on arrival | ❌ no drum or horn at the order | ✅ (+ a line on arrival) | **7.** Silent order. |
| **Levy** | ✅ muster in the square, files of men march out, the armoury racked, smiths hammer faster | ✅ drum and march (+ v2 levy drum) | ✅ | — |
| **Banners** | ✅ muster at the seat (+ garrison) | ✅ drum and march | ✅ | — |
| **Peace** | ◐ riders to both houses; the war mood lifts only when Freeciv's war ends | ✅ gallop | ✅ | Later: the war mood could stand down at once. |
| **Alliance** | ◐ rider to the house | ✅ gallop | ✅ | Later: the house's banners at the King's seat. |
| **Buy-off** | ◐ rider | ✅ gallop | ✅ | Later. |
| **Cede** | ✅ the town changes hands (handover scene from the transfer) | ✅ quiet fanfare | ✅ | — |
| Gift, sellswords, back, settle | (off in decrees.json: the cut list) | | | — |

## Court answers (petitions and the Hand's matters; `court.js rule`)

Every answer: a scene (`rulingScene`: a vigil for a hanging or burning, a feast or a muster at Kingsmere, grain, a
purse, a ward or a rider on the road) and a ruling kept at the town it touches for two seasons (`rulings.js`:
relief, justice, levy, feast, build, grant), which the town dresses and the herald cries in the square with the
crowd cheering or dismayed. Reads: the chronicle line and the court card.

| Answer kind | Sees | Hears | Reads | Gap |
|---|---|---|---|---|
| Justice (hang, burn, punish) | ✅ the vigil; gallows, guards and a silent crowd | ✅ the slow drum | ✅ | — |
| Relief, feast, levy, build, grant | ✅ dressing and herald | ◐ rider gallop / muster drum; **grain, purse and feast silent** | ✅ | **4/6.** Grain, purse (tribute) and the King's feast make no sound. |
| An answer whose words match no kind | ◐ the rider only | ✅ gallop | ✅ | Acceptable: a word carried. |

## Host orders (`hosts.js`: hold, march, garrison, return, split)

| Order | Sees | Hears | Reads | Gap |
|---|---|---|---|---|
| March, garrison, return | ✅ the host turns and walks the road | ❌ | ✅ toast; a chronicle line on arrival | **7.** Silent: no drum as the host sets off. |
| Hold, split | ✅ the host stops / divides | ❌ | ✅ toast | Minor. |

## Event cards (`events.js`)

Off in `events.json` (the decks now come to court as petitions, which have the court's reactions above). When on,
an answer shows only its text on the card: no scene, ruling or sound. Not worked on while off.

## Fixes, in order (each behind data, each committed)

Done 2026-11-12: 1 and 2 (1b0d2b35), 3 and 4 (the commit after). The gaps marked 1-7 above are closed in code; not yet heard or seen in a run.

1. Decrees leave their ruling in the town (relief, grant, build): `bridge/data/rulings.json` `decrees` maps a
   decree to a ruling kind; `routes_decree.js` posts it at the town (Rulings.post), so the town dresses and the
   herald cries it, at the seat as anywhere.
2. Promise: a rider carries the King's word to the lord's town (`decrees.json` promise.rider: the label).
3. The King's scenes are heard when they land: `realm/data/sounds.json` `staged` maps a staged scene to a sound
   event (feast: cheer; grain and tribute: cart and coins; ward: gallop), on top of the old vigil, rider and
   muster; a lord's scene keeps its own cue (news.gd), never both.
4. Host orders are heard: `sounds.json` `orders` (march, garrison, return: the drum and the march).
