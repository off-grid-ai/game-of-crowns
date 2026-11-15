# Game of Crowns: the world and the art

What the realm is made of and how it looks. How it plays is [GAME_DESIGN.md](GAME_DESIGN.md); the
houses, places and lore are in [WORLD.md](WORLD.md).

## How the world runs
- **Freeciv runs the world:** land, towns, production, armies and battles between houses. One turn is one
  season; a year is about four minutes at normal pace. The view fills the time between turns, so armies
  keep walking and builders keep building.
- **Our own people and economy sim** sits beside it. One owner per fact: each fact has one source, and
  the view mirrors it.
- **Each house plays its temperament** from WORLD.md: Ironreach raids, Goldcrest buys what others
  fight for, Stormhold seeks glory.
- **Strictly medieval:** the ruleset stops research at the high middle ages.

## Houses and people
- **People, not nations.** Each great house has a lord, family, heirs and a rival, with names, traits
  and wants. Lords age and die; a weak heir invites rebellion.
- **Bannermen** hold the lesser towns. They can be won by the Crown, bought by a rival, or rise against a
  weak liege.
- **The Crown's household:** the King, his commanders, champion and small council, each a person with
  a story and an agenda.
- **Favour** is how each house regards the Crown, moved by your orders, gifts, oaths and rulings. Debts
  and grudges are kept for named acts. A house with low favour gives its ultimatum, then rises.
- **Minds.** Routine choices are scored by simple rules; a major lord's big turns (betrayal, war,
  marriage) can be voiced by the optional local model. Outcomes flow back into the world: married houses
  ally, spurned houses sour, a claimant becomes a rebel.
- **The Watch** on the old wall in the north lives on the men and grain the houses send; neglected in a
  long winter, the wall falls.

## Resources
- **Crowns:** from taxes and trade, every season. Buy men, walls and favour.
- **Grain:** town stores. Feed armies on campaign; relieve starving towns.
- **Men:** levied from towns; the army's size.
- **The tithe:** a higher share makes the Crown rich and the houses resentful; lower makes you loved and
  poor.

## The world shows its state
| State | On screen |
|---|---|
| Building in progress | Staked ground, scaffolding rising with progress, then the building |
| Food low / famine | Paling then brown fields, a queue at the granary, families leaving with carts |
| Growth | Golden fields, market crowds, new houses at the edge, festival fires |
| Training | Recruits drilling in the yard |
| An army marching | A column in house colours on the road toward its goal |
| War between houses | Red borders at realm zoom; battles where armies meet |
| Siege | Walls crack into a breach, attackers pour through, houses burn with real flames |
| Town taken | Smoke, the banner changes, roofs and banners recolour, refugees |
| A displeased house | Torn, lowered banners, an angry crowd, doubled guards, shuttered shops |

## Tone
Gritty and epic, never whimsical (*Warcraft*, *300*, *Game of Thrones*, *Vikings*). Honour and its price,
brotherhood and betrayal, shield walls and last stands. Battles framed like film: banners at dawn, the
horn before the charge. The chronicle reads like a saga, not a report. Music is drums, horns and low
strings.

## Art
- **The target is [docs/art/target](docs/art/target/README.md):** eight approved concepts (town, realm,
  army, siege, court, inn, unrest, reinforce). Every visual change is judged beside the matching image at
  the same framing. Fidelity: polished mid, Warcraft III and Age of Empires II DE.
- **House colours everywhere:** roofs, trims, shutters, banners and uniforms wear the holding house's
  colour; walls and stone stay natural. A town that changes hands recolours.
- **Real armies:** dense formed blocks of many unit types (spears and shields, axes, archers, horsemen),
  around 900 AD in dress and arms.
- **Warm and painterly, never toy-like.** Golden light, soft haze, buildings small against a big land.
- **One look:** every model goes through one look standard; nothing from mismatched kits, no placeholder
  ships.
- **One animation family:** every body and clip is retargeted to Godot's humanoid skeleton, so any move
  plays on anyone. Use every clip we have.
- **Heraldry:** every house's banner and sigil lives in `realm/assets/heraldry`.
