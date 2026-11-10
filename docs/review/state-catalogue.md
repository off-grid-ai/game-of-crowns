# State catalogue (2026-11-10)

Every kind of thing in the realm, its states, and whether each state does the four things a state should do (the judge's rule): **Show** (a sign in the 3D view), **Move people** (crowd behaviour or gossip), **Raise a matter** (counsel, petition, arc or chronicle line drawn from the real state), **Answer to the King** (a decree or ruling that changes it). Built by a read-only helper from the code; server.js line numbers drift, so search for the field. Frequencies are estimates (one turn is a 40 s season).

| Entity | State | Source | Show | Move | Raise | Answer | Should be |
|---|---|---|---|---|---|---|---|
| Town | growing | Freeciv `size` up | weak: the town rebuilds on a new size (towns.gd:62) | no | no | no | a new house rises under scaffolding for a season |
| Town | shrinking | `city_shrank` | weak: refugees only for famine or plague | famine/plague only | chronicle | relief | a refugee cart for every cause |
| Town | sacked | `city_transferred` conquest → `sack` scene + mark | yes: fire, refugees, ash, stumps | yes | chronicle; `claim` only for treachery | march, grant | add the new owner's banner going up |
| Town | razed | `city_destroyed` → scene + mark | yes: fire, refugees, ruin | yes | chronicle | no | ok |
| Town | famine | `famine` (hadFamine) | yes near: grey fields, beggars, refugees | yes | weak: counsel yes; grain petition and plague card dead (note A) | relief | fix the court's read |
| Town | granary low | `food`, `granary` | no (minimap ping) | no | broken: `c.granary < 0.25` compares a capacity to a fraction | build granary | fix the test; fewer stalls |
| Town | feasting | `celebrating` (rapture); King's `feast` scene | yes: bonfire, revels | rapture only; the King's feast never sets the mood | no | feast decree (doesn't set `celebrating`) | the feast decree gives the town a feast mood for a season |
| Town | disorder | `disorder` (anarchy) | yes near: angry crowd, smoke | crowd yes; gossip no | counsel `unrest`; no chronicle line | relief, sept, market, feast | add a chronicle line |
| Town | plague | `plagueTurn` | refugees | yes | counsel | aqueduct, sept, relief | carts of the dead by night |
| Town | at war | player `wars` / `atWarWith` | weak: red border from raw `atWarWith`, marching armies | no crowd change | counsel | peace, settle, back, sellswords, marriage | guards on the watch, fewer traders, eyes down the road |
| Town | besieged | `siegeLeft`, `besieged`, `sieges()` | yes: siege camp, label countdown | no; the siege sound reads `c.besieged`, which cities never carry | herald arc | press, starve, tribute, march | folk indoors or fearful; fix the sound key |
| Town | building | `building`, `progress`, royal works | yes near: the site rises; drill for units | builders | royal works; `building_built` | build | ok |
| Town | grasping (tithe) | `crown.tithe` | no | weak: anger on a tithe change only | favour drain; counsel | tithe | wagons to Kingsmere; muttering knots |
| Building | damaged or burnt | `building_lost` | weak: it just disappears | no | chronicle | no | a charred shell from the ruins kit |
| Building | abandoned / prosperous | not tracked | no | no | no | no | skip / stalls already scale with size |
| Road | busy, quiet, blocked | not tracked: 3 random travellers near the camera | state-blind | no | `outlaws` petition, random | hunt, pardon | traffic follows peace and prosperity; none between warring houses |
| Field | sown → harvested | season + countryside's own clock | yes | farm work | `harvest_glut` (gate partly dead) | no | ok |
| Field | burnt | battle/sack marks | weak (decals may cover the scar) | no | no | no | blight on fields in a scar |
| Tree | season, burnt | `date.season`, marks | yes | no | no | no | ok |
| People | role | LimboAI roles | yes when the switch is on | n/a | n/a | n/a | turn the switch on (slice 3) |
| People | mood, feelings, memory | minds.js | weak: pace and idle clip; captions | gossip (chatter.js) | no | indirect | ok |
| People | danger | only when the hero strikes | yes | yes | no | no | a battle or sack within 2 tiles sets danger |
| Soldier | hp, activity | `units[]` | no | no | no | no | wounded clips, a fortified stance |
| House | favour | `favour` | weak: banner height | no | counsel | gift, feast, grant, ward, alliance | ok; hard to read at range |
| House | truce | `truces` | no; the border tint still shows a truce as war | no | no | peace, marriage | a herald rider between the seats |
| House | turning (ultimatum) | `turning` | UI chip only | no | ultimatum | gift, feast | drilling at their seat |
| House | sworn | `sworn` | no | no | no | alliance | a crown banner at their seat |
| King | live name | `reign.readings.name` | UI only | no (yes with awareness: banner reactions) | ticker | deeds | ok |
| King | treasury | `crown.treasury` | weak: screen-edge colour | no | counsel | tithe | ok |
| Realm | season, time of day | `date.season`, sky clock | yes | yes | arcs | no | ok |
| Realm | peace | `peace` | weak: red edges | no | readings | many | ok |
| Realm | prosperity | `prosperity` | no: nothing reads it | no | no | no | drives road traffic and market crowds |
| Realm | threat | `threat` | music only | no | counsel | banners, levy, buyoff | ok |
| Mark | battle, sack, razed | marks (12–16 seasons) | yes: ash, stumps, ruins | yes | arcs | no | ok |

## The court's deck

Filtered, then drawn at random. `cast()` keeps cards whose `when` gates pass, then one is drawn by weight with `Math.random`, recently heard kinds weighing less.
- 10 of 34 cards have no gate.
- 8 are gated partly on a dice roll.
- Gates are about the lord (traits, favour, gold, age, kin), not the realm.
- `pirates` and `wildlings` ignore coast and north.
- `border_war` follows opinion, not real wars.

## Top 10 missing links, most frequent first

1. **Houses at war** (every season): Move people; Show weak. *people*
2. **Tithe** (every season): Show; Move beyond a one-off. *world-object*
3. **Turning, truce, sworn** (every season): Show. *world-object*
4. **Town growing** (several a season): Show, Raise, Move. *world-object*
5. **Roads busy, quiet, blocked** (every season): Show tied to state. *world-object*
6. **Granary low** (often): Raise; the counsel test is broken. *court-matter*
7. **Famine** (a few a reign per house): Raise for petitions and cards (note A). *court-matter*
8. **Battle or sack near a town** (many a reign): Move (danger). *people*
9. **Disorder** (several a reign): gossip and a chronicle line. *people*
10. **Siege** (a few a reign): Move; the sound flag is broken. *people*

Next: the King's feast decree never sets the town's feast mood (*people*); soldiers ignore hp and activity (*people*).

## Duplicated state (one owner each, to fix)

- **Hunger, four definitions:**
  - town_life and villagers use `famine`.
  - the minimap uses `famine || food < 10% of granary`.
  - arcs.js uses `food < 3 || famine || plague`.
  - characters.js uses `food < 3` on the raw world, which has no `food` field. **Note A:** the court never sees a hungry town, so the grain petition and the deck's `hungry` gate never fire, and `fed` always passes.
- **At war, two definitions:** terrain.gd builds its own map from raw `atWarWith`. /world's `wars` and `truces` already drop truces, so borders show truces as war.
- **Besieged, three definitions:** `meta.campaigns`, `sieges()` and the realm-map endpoint each count it their own way. main.gd reads `c.besieged`, which doesn't exist.
- **Feasting, two sources:** Freeciv `celebrating` and the bridge's `feast` scenes. Only the first drives mood.
- **Season timing:** countryside.gd keeps its own 40 s clock.
- **Town amenities:** soundscape guesses tavern and market from `size`, not `buildings`.
- **Counsel `mighty`:** uses `b.cities?.length`, but `cities` is a number.

The view's mirror (awareness.gd) is the one owner of these facts in the view; the bridge's /world is their one source.
