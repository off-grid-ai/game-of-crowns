# Decisions seen in the world (one page, Builder 2, 2026-11-11)

**Mac:** "Warcraft 3 is exactly what we want." **Rule:** every decision shows on the map, where it lands, within two seconds, and it stays visible while it's true. A notice is not enough.

**References:**
- **Warcraft III:** an order is a unit moving on the map.
- **CK3:** a county's unrest shows as a mark at the county.
- **Total War:** reinforcements march along the roads and stand in the town.

## What we have
| Already shown | Where it comes from |
|---|---|
| Grain and gold wagons on the road, riders, a muster at a seat, a feast, a siege, a battle, a sack | `scenes.gd` scene kinds, posted by the bridge's `decreeScenes` and `rulingScene` |
| The royal host marching on a town | `campaigns.js` `startCampaign` |
| An order's result as the latest news at its town (edge arrow, Space) | `news.point_at`; juice is on by default |

**What's missing:**
- A house's mood leaves no mark at its seat.
- Backing a house (the `back` decree) only moves gold.

## Two additions

### 1. Unrest at a displeased house's seat (CK3's county unrest, made visible)
- **The state is on the bridge.** One reading per house, from its favour band (`favour.json`), which the bridge already sends with `/world`:
  - **Content:** nothing.
  - **Cold:** unrest.
  - **Angry, or an ultimatum sent:** high unrest.
- **The view, one owner** (a new `unrest.gd`), at the seat:
  - **Cold:** the house's banners at half-mast, and a small knot of townsfolk gathered in the square. These are the existing crowd and gossip-knot people, so no new assets.
  - **High:** guards doubled at the gate (the existing guard figures, from the asset catalogue), braziers lit, and the crowd larger.
  - **Banners gathering (`turning.riseAt`):** the existing muster scene keeps running at the seat until the host marches or the house is won back.
- **Won back above the band:** it eases away over a season (crowd disperses, banners rise) rather than vanishing.

### 2. Backing a house sends the royal host to garrison (Total War's reinforcements)
- **The bridge:** the `back` decree also detaches a royal company, sized from the King's host. It is `startCampaign`'s march with a new end state: `garrison` at the backed house's most threatened town, for N seasons (data).
  - While there, the company adds to the town's defence in Freeciv, the way the existing garrison units already sit in towns.
  - When its seasons run out, it marches home.
  - The cost is the gold the decree already takes, plus the absent men in Kingsmere's own defence: a real trade.
- **The view:** the company walks the roads (the existing host and march path, so it is seen on the map), arrives, and its royal banner stands over the town beside the house's.
  - The town card says "A royal company holds X (3 seasons)", in words.

## Order and owners
1. **The unrest marks.** View only: Builder 2, with the people from the lead's crowd module. About a day.
2. **The garrison march.** Bridge (`crown.js` `back`, `campaigns.js`): Builder 2. The armies themselves (unit look, density, WC3 command): the lead, after the armies research.

**Done when:** in the Kingsmere slice, refuse a house and see its seat sour within one season; back a house and watch the company walk there and stand.
