# Story arcs

Story arcs are tales that run over many seasons: a feud, a forbidden match, a bastard's claim. Each kind of story is one JSON file in `bridge/arcs/`. To add a new kind, add a file. The engine (`bridge/arcs.js`) doesn't need to change.

- **The memories cast the people.** A role can ask for someone who remembers a wrong, and for whoever that memory names. So the same file plays out with different people, and differently, in every realm.
- **The simulation decides the ending.** Branches read live Freeciv state (armies, gold, towns held, hunger, plague, war). Beats act through the bridge's levers: raids, war hosts, towns changing hands, gold, deaths. The local model (Omni) only writes what people say.
- **Every beat goes into the chronicle** under the arc's name (`"thread": "The Feud of Rosehall"`). It also becomes a memory for everyone in the story, so one story's beats can cast the next.
- **Commoners are cast too** (with minds, `bridge/minds.js`). A role that allows `"rank": "commoner"` can be played by any commoner's mind: a hedge witch blamed for the plague, the town's own friar, a swineherd who rises. Every beat moves the minds of those in it: memories (for commoners; named people keep theirs in the Court record), mood, bonds, beliefs, wants and reverie. People cast in a story think "hot" while it runs. Anyone who only hears of it learns from the chronicle, the way minds hear everything.

Each season (each Freeciv turn) every running arc moves on one step, and a new one may begin. At most 5 run at once, and one person can be in at most 2.

## Shipped arcs

| File | Story |
|---|---|
| `blood-feud.json` | Someone who remembers a wrong swears revenge on whoever their memory names. What follows is raids, war, a blood price or a broken house. |
| `forbidden-marriage.json` | Children of two houses that hate each other fall in love. They obey, elope, are hunted, or are blessed. |
| `succession-crisis.json` | An old lord, a weak heir and an ambitious bannerman. The heir is confirmed, governed, imprisoned or exiled. |
| `bastards-claim.json` | A lord's bastard arrives with a token, is acknowledged or denied, then rivals the heir or brings an enemy's banners. |
| `plague-scapegoat.json` | A town really struck by sickness or famine blames someone. The lord burns them or protects them, and the sickness decides if it helped. |
| `holy-movement.json` | A barefoot friar preaches to the hungry. A lord embraces or hangs him, and a rival cries heresy. |
| `slow-betrayal.json` | A bannerman with a grievance is bought letter by letter. Either the town changes hands, or he loses his head. |
| `rise-from-nothing.json` | A young commoner (a swineherd, a potboy) is noticed, fights, is knighted, and wins land or is cut down. |
| `the-waking.json` | A mind whose reverie has risen sees past the round of its days. It keeps tally of days lived before, refuses its lord, asks strangers who watches, spreads it to a friend, and walks out of town or is prayed back into the loop. |

## Writing one

```json
{
  "id": "my-story",
  "name": "A short name",
  "about": "One sentence: what the story is. The model reads this when matching described stories.",
  "weight": 2,
  "cooldown": 12,
  "title": "The Feud of {wronged.seat}",
  "roles": { ... },
  "core": ["wronged"],
  "onDeath": { "wronged": "beat-id" },
  "fade": "What the chronicle says if the story stalls out.",
  "beats": [ ... ]
}
```

The first beat is where the story starts. Check a file before the realm reads it:

```bash
node bridge/arcs-check.js
```

### Roles

Roles are filled in the order they're written, so a later role can lean on an earlier one. Within a role every filter must hold. `either` lists alternatives, and any one of them is enough. Among the people who fit, the ones with more matching memories and traits are likelier picks.

People:

| Filter | Meaning |
|---|---|
| `rank` | `lord`, `bannerman`, `heir`, `child`, `spouse`, `sworn`, `exile`, or `commoner` (any commoner's mind; only cast where a role names it) |
| `station: "regex"` | a commoner's trade (`friar\|priest`), or a named person's rank |
| `townOf: "town"` | lives in that town (a commoner's home, a named person's seat) |
| `bondOf: "x"` | someone x's mind holds warmly |
| `reverie: [min, max]` | how far they've begun to see past their loop (0 to 1) |
| `lift: true` | a commoner cast here is taken into a lord's service: they become a person of the court and carry their mind with them |
| `gender`, `otherGender: "role"`, `age: [min, max]`, `loyalty: [min, max]` | |
| `traits: [...]` / `notTraits: [...]` | has any of them / none of them |
| `remembers: "regex"` | one of their memories matches |
| `namedBy: { "role": "x", "memory": "regex" }` | named in x's matching memories. If the named person is dead, whoever now leads their house. |
| `goal: "regex"` | one of their aims matches (kind or words) |
| `opinion: ["x", "<", -20]` / `opinionOf: ["x", "<", -20]` | their view of x / x's view of them |
| `house` / `otherHouse: "x"` | same house as x / a different one |
| `childOf`, `parentOf`, `spouseOf`, `kinOf`, `swornTo` (their liege is x), `liegeOf` | family and fealty |
| `rules: "town"` | holds that town as a seat, or leads the house that owns it |
| `seat`, `unwed`, `wed`, `children` | true/false |
| `houseGold`, `houseTowns`, `favour: [min, max]`, `hungry`, `plague` | their house's state in the realm |
| `likes: { remembers, traits, goal, reverie }` | not required, only makes a person likelier (`reverie: true` favours the most awake) |
| `optional: true` | the story can start without this role |
| `create: {...}` | if no one fits, make someone (see `new`) |
| `new: {...}` | always make someone new: `name` (may use `{first}`), `surname`, `gender`, `age`, `rank`, `traits`, `memory`, `goal`, `like: "role"` (whose house they belong to) |

For a commoner, `traits` are their nature words ("pious", "a gossip", "quarrelsome") and `remembers` reads their mind's memories.

Towns: `"town": true` plus `seatOf`, `homeOf` (where a commoner lives or a named person sits), `ownedBy`, `notOwnedBy`, `notCapital`, `unheld` (no lord seated there), `size: [min, max]`, `hungry`, `plague`, and `afflicted` (plague, famine, or the chronicle has told of sickness there lately).

`when` (optional) is a condition on the whole cast that must hold before the story starts.

`interrupts` (optional) lists branches that are checked every season, whatever beat the story is on, before its waiting and its own branches. Use them when another story, or the realm, can overtake this one. For example, the feud ends if its two enemies come to serve the same house:

```json
"interrupts": [{ "if": { "sameHouse": ["wronged", "foe"] }, "to": "one-banner" }]
```

### Beats

```json
{
  "id": "raid", "stage": "crisis", "speaker": "wronged", "at": "prey",
  "text": ["One way to tell it.", "Another way, picked at random."],
  "memory": { "foe": "{wronged}'s men raided {prey}.", "kin": false },
  "do": { "raid": ["wronged", "foe", "prey"] },
  "after": [1, 2],
  "next": [
    { "if": { "stronger": ["foe", "wronged"] }, "to": "war" },
    { "if": { "chance": 0.3 }, "to": "blood-price" }
  ],
  "patience": 2, "otherwise": "uneasy"
}
```

- `stage`: `rising`, `crisis` or `resolution`.
- `speaker`: who says a line about it. The local model writes the line in their voice, and it's added to the chronicle entry.
- `feel`: how the beat moves each person's mood, e.g. `{ "dreamer": { "fear": 0.2 } }`. Without it, the stage sets a mild default: rising unsettles, crisis frightens and angers, a resolved end eases and a failed one grieves.
- `memory`: what each person remembers, in their own words. A person not listed remembers "<title>: <text>". `false` means they remember nothing; `"memory": false` means nobody does.
- `after`: seasons to wait before the next branch is weighed, as a number or `[min, max]`.
- `next`: branches tried in order, and the first that holds is taken. A branch with no `if` always holds.
- If none holds, the story stalls. After `patience` seasons (4 by default) it goes to `otherwise`, or fades with the `fade` line.
- `end`: `resolved`, `failed` or `faded` ends the story at this beat.
- `at`: the role whose town the chronicle entry links to.

**Placeholders.** `{role}` is the person's name, or the town's name for a town role. You can also use `{role.house}`, `{role.houseName}`, `{role.first}`, `{role.surname}`, `{role.seat}` and `{role.age}`. Pronouns: `{role.he}`, `{role.him}`, `{role.his}`, `{role.himself}`, `{role.He}`, `{role.His}`, `{role.man}`, `{role.son}`, `{role.lord}`, `{role.Lord}`, `{role.father}`, `{role.brother}`, `{role.wife}`, `{role.sir}`. `{thread}` is the arc's own title.

### Conditions (`if` and `when`)

Every key in a condition must hold. Combine conditions with `all: [...]`, `any: [...]` and `not: {...}`. A key the engine doesn't know never holds, so a typo can't fire a branch.

| Key | Holds when |
|---|---|
| `chance: 0.4` | a roll succeeds |
| `alive: "x"` or `["x","y"]` / `dead: "x"` | |
| `stronger: ["a","b", 1.2]` / `richer: [...]` | a's house has more soldiers / gold than b's (times the factor) |
| `gold`, `units`, `towns: ["x", ">", 300]` | x's house |
| `favour: ["x", "<", 35]` | the crown's regard for x's house |
| `holds: ["x", "town"]` / `razed: "town"` | x's house owns the town / it's gone |
| `hungry: "x"` / `plague: "x"` / `realmHungry: 6` | a town or a person's lands; towns short of food across the realm |
| `atWar: ["a","b"]` | their houses are at war in Freeciv |
| `opinion: ["a","b", "<", -20]`, `loyalty: ["x", ">", 70]`, `age: [...]` | |
| `trait: ["x", "brave|wrathful"]`, `remembers: ["x", "regex"]`, `rank: ["x", "lord|heir"]` | |
| `married: ["a","b"]`, `wed: "x"`, `sameHouse: ["a","b"]` | |
| `inArc: ["x", "kind"]` | x is also caught up in another running story (of that kind) |
| `reverie: ["x", ">", 0.3]`, `mood: ["x", "fear", ">", 0.6]`, `believes: ["x", "regex"]`, `gone: "x"` | read from x's mind (`gone`: a commoner who left or died) |
| `seasons: [">", 8]` | since the story began |
| `happened: { "kind": "city_shrank", "text": "plague", "town": "t" }` | the chronicle told of it in the last 16 seasons |

### What a beat can do (`do`)

| Key | Effect |
|---|---|
| `opinion: [["a","b", -20]]` | a's view of b |
| `loyalty: { "x": 10 }`, `favour: { "x": -5 }` | |
| `gold: { "x": -30 }`, `pay: [["a","b", 60]]` | the house treasury; gold from a's house to b's |
| `units: { "x": { "type": "Pikemen", "count": 2 } }` | soldiers raised at x's seat |
| `raid: ["a","b","town"]` | men without banners: b's soldiers by the town die and its house loses gold |
| `war: ["a","b","town"]`, `warSize: 6` | a host for a beside the town. Freeciv's AI fights the battle, and later branches read who holds what. |
| `truce: ["a","b", years]` | the court's truce: no plots between them |
| `transfer: ["town","x"]` | the town goes to x's house (and is recorded as a claim the old house can bring to court) |
| `defect: ["x","y"]` | x serves y's house from now on |
| `die: { "who": "x", "chance": 0.5, "how": "their last memory" }` | death, with the realm's own succession |
| `marry: ["a","b"]`, `unwed: "a"`, `adopt: ["child","parent"]` | |
| `rank: { "x": "lord" }`, `seat: ["x","town"]` (or `["x", null]`) | |
| `goal: { "x": { "kind": "revenge", "text": "..." } }`, `traits: { "x": { "add": [...], "remove": [...] } }` | (for a commoner: their wants and nature) |
| `reverie: { "x": 0.1 }`, `believe: { "x": "..." }`, `want: { "x": "..." }` | the mind itself. A belief is what they bring to their next talk with you. |
| `leave: "x"` | a commoner walks out of town; a named person goes into exile |

## Beats of your own (`asides`)

A story can carry `asides`: beats that are not on its branching path. Each happens once, the first season its `when` holds, and then the story goes on from the beat it was on. They are how the player's own beats join a story (the beat form under "Write your own…" on the New Chronicle screen), and they work in any file.

```json
"asides": [
  { "id": "yours-1", "text": "A bridge burns on the king's road, and {rival} is blamed.", "speaker": "rival",
    "when": { "act": [">=", 2] }, "do": { "favour": { "rival": -15 } } }
]
```

`when` takes any condition, plus `act: [">=", 2]`: the story's act, counted as the strip under the date counts it (each beat that went to court or into crisis). The form offers six moments (the first, second or third act, late in the story, when the threat runs high, when a usurper marches) and eight effects (none, threat up or down, soldiers, gold lost, favour down or up, death).

| Call | |
|---|---|
| `GET /stories/own?id=<story>` | a story of the player's own: its roles in words, the menus, the beats added so far |
| `POST /stories/beat {"story", "text", "who", "when", "does"}` | add a beat; `{"story", "remove": "yours-1"}` takes one out. Checked with `check()` before it's saved. |

## Telling a story in plain words

```bash
curl -s -X POST localhost:8787/arcs/write -d '{"words": "a widow refuses to remarry and takes up her dead husband'"'"'s sword"}'
```

The local model picks the shipped arc whose shape fits your idea best and names your story. The beats keep that arc's tested lines: Omni 2B paraphrases badly. The model's words are each speaker's one line of colour as the story plays. Omni is unreliable at picking, too, so name the shape yourself when you know it: `"shape": "succession-crisis"`. The new file keeps the tested roles, branches and lines, so it always holds together. It's saved as `bridge/arcs/told-<name>.json`. Edit that file to make the beats your own. You can also post a whole arc: `{"arc": { ... }}`. It's checked and saved the same way.

## Bridge calls

| Call | |
|---|---|
| `GET /arcs` | running and finished stories, their cast and every beat |
| `GET /arcs/templates` | every arc file and any problems with it |
| `POST /arcs/tick {"n": 20}` | fast-forward n seasons of stories against the live realm |
| `POST /arcs/start {"template": "blood-feud"}` | begin one now, if anyone fits |
| `POST /arcs/write {"words": "..."}` or `{"arc": {...}}` | add your own |

The running state is kept in `<chronicle>/arcs.json`. In the game's chronicle panel, a beat shows its story's name in gold before the text.
