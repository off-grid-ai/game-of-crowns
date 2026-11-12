# Town behaviour architecture: from the town's state down to each person

Design, 12 Nov 2026 (works-life). Ask: Mac, "town setting etc that governs people's behaviour... it all needs to
flow from the top", "there is no real routine", "group routine". Scope: Kingsmere's square first, then every
town. No code here; this is what the builder builds, in stages, behind `--town-director=on`.

## The verdict in five lines

1. Today nothing decides what the square is doing. Four systems each fill it on their own: posted figures
   (`town_life.gd`), plain movers (`town_life.gd` SquareLife), villagers with LimboAI minds (`villagers.gd` +
   `npc_mind.gd`), and the bailey's own folk (`castle_folk.gd`).
2. The villagers' "routine" is a weighted random pick of the next activity (`npc_mind` Weigh, a
   BTProbabilitySelector), bent by the town's state. Only "never the same activity twice running" stops a loop.
   That is why a man cycles gestures alone on the cobbles: nothing above him said where to be or why.
3. The fix is four layers, each reading only the one above: **state → director → scenes → people**.
4. People never choose. A scene gives each member a role and a cue; anyone not in a scene walks somewhere with a
   reason (home, work, the next scene's place) or leaves the square.
5. We keep the blocks we have: the awareness mirror (layer 1), LimboAI (layers 2-4), NavigationServer2D walking
   with RVO, the smart-object slots, the smooth-motion rules, the clips. We retire the random activity picks,
   the posted crowd and the plain movers for the square.

## 1. Today's code: what drives each figure in Kingsmere's square (the honest map)

| Figure | System and file | What decides its next step | Real routine? |
|---|---|---|---|
| Stallholders (one a stall, some keep two) | posted, `town_life._trade`; mind `trade` (`npc_mind.post_activities`) + `serve()` | Weighted random of two activities ("mind", "cry") at the post; `serve()` takes over when a shopper stands at the stall's front | Half: serving is a real pair; the rest is gestures on a spot |
| Smith, bellows boy | posted, `town_life._forge`; minds `smith`, `bellows` | Weighted random of 4 and 3 activities at the anvil/hearth; quench walks to the trough, the boy to the store | Half: work at the right things, but the order is random |
| Crier and listeners | posted, `town_life._crier`; minds `crier`, `listener` | Random activities; listeners stand in a fixed ring whether or not he speaks | No |
| Beggars | posted at the sept; mind `beg` | Random activities on the spot | No |
| The one posted gossip knot (2-3) | posted, `town_life._square_life`; mind `gossip` | Random talk clips on a spot, forever | No: a knot that never meets or parts |
| Drill recruits (levy) | posted, `town_life._drill`; mind `drill`/`bows` or a Timer (`_drill_routine`) | Random cut/thrust runs on a spot; fall out after a season | Partly: drill is drill, but no sergeant, no start or end in view |
| Guards at the forge and the castle side | posted, `town_life._square_more`; mind `guard` | Random idles on a spot | No |
| The guard pair on patrol | SquareLife (plain `_process`, no LimboAI), `town_life._beat` | A fixed list of stops walked in a loop, a look at each | No: a ring, mechanical |
| Children chasing | SquareLife | Random open-cobble goals, a breather after a catch | No: endless |
| Carriers on straight errands (2) | SquareLife | A shuffled list of places walked in a loop | No |
| Dogs | SquareLife | Follow someone, lie about | No (fine as background) |
| The market cart and its horse | SquareLife `_cart` | Fixed stops along the streets, waits at the market | Half: real path, no unloading beat of its own |
| The open-air smith, carter and buyer, porters at the stall ends | posted, `town_life._market_day` (open smith off when the smithy stands on the square) | Random activities on a spot | No |
| Villagers (shoppers, water carriers, porters, gossips, and the town's other callings passing through) | `villagers.gd` (spawn, NavigationServer2D walking, RVO, slots) + `npc_mind.give_villager` (LimboAI) | A BTDynamicSelector: danger, fire, news, a call to talk, moods, night/rain/winter, then **Weigh: a weighted random pick** among the calling's activities (`villager_activities`) | Partly: each activity is a chain (street → stall → haggle → take → street), but which chain comes next is random and nothing ties two people's chains together |
| Bailey folk (drill lines, archers, smith, servants, grooms) | `castle_folk.gd`, Timers and tweens | Fixed timers | No (out of the square) |

**Checked against an independent read-only audit (supervisor, 12 Nov):** it agrees, and adds what my map missed:
the posted crowd is only partly cut with square agents on (`square_agents.posted` cuts the gossip knots, straight
carriers, chase pairs, patrol and stall buyers; the crier and his 3 listeners, 2 beggars, 6 guards at the forge and
the castle side, the cart's seller and buyer, the 2 porters at the stall ends and the weeders stay); a quarter of the
crown's villagers keep the old callings (the pious preaching at the well, idlers watching, gentry promenading),
alone at `_claim` ring spots; the well's "chat" and the porter's "rest" talk to the well rim alone; and a Talk whose
partner never came succeeded after 8 s, so the moves after it played alone.

Numbers today (crown seat, square agents on): about 28 villagers on square errands at once at most; the posted
crowd cut to keepers, the drill, one gossip knot, two carriers, two child pairs, one guard pair, the smith and boy.

**Where the looping man comes from (most likely, to be confirmed by the probe below):** a villager whose
activity's slot was not to be had. `villagers.place()` falls back from a full slot ("stall", "draw") to the old
"market" ring round the market's middle, an open spot on the cobbles; the activity then plays its clips there
(Thinking, Doubtful, Looking_Around, Idle_Talking) with nothing in front of him, and Weigh picks another activity
that does the same. Second candidates: the posted gossip knot left with one member when the others found no room,
or a crier's listener standing in his ring with no crier. The cause in every case is the same: an action allowed
without an object or a partner.

Fixed at once (not waiting for the director, `--square-agents=on` only): a slot that can't be had no longer falls back
to an open spot (`villagers.place` returns no place, GoTo fails, the tree goes on to something else), and a Talk whose
partner doesn't come fails instead of succeeding. **Rule for the new design: a failed claim means walk on or leave,
never act in place.**

## 2. The four layers

```
 Freeciv ─► bridge (/world) ─► 1. TOWN STATE (awareness.gd town scope)          facts only
                                   │
                                   ▼
                               2. TOWN DIRECTOR (town_director.gd, one a town)   schedule + mood → which scenes
                                   │
                                   ▼
                               3. SCENES (scene coordinator BTs, scenes.json)    roles, beats, an end
                                   │
                                   ▼
                               4. PEOPLE (villagers.gd bodies, npc_mind role trees, smooth motion)
```

Each layer reads only the one above. A person never picks a random action; the director never invents a fact;
a scene never reads the bridge.

### Layer 1: the town's state (facts)

Owner: the bridge; mirrored once in the view by `awareness.gd`'s town scope (already the SSOT). Read by layer 2
only.

| Fact | From | Already in the mirror? |
|---|---|---|
| size, food, granary, granaryLow, famine | Freeciv city | yes (`/world` city) |
| prosperity, treasury | bridge realm state | prosperity yes; treasury realm-wide |
| happiness / unrest (mood: hunger, riot, feast) | bridge | yes (`mood`) |
| season, weather | bridge `/world` | yes |
| time of day | the view's clock (`villagers.hour`, main.gd) | the one fact the view owns: presentation time |
| market day | **missing**: a rule on the bridge (e.g. every turn, or the crown's seat daily) | add to `/world` |
| events at the town: levy raised, war near, feast, fire, a ruling, a death (grief), gold seam spent | bridge scenes/rulings, awareness stimuli | yes (levy, atWar, grief, ruling, feast); gold seam spent: add |

### Layer 2: the town director (`town_director.gd`, one per town in view)

Where it plugs in (the audit's pointer): `awareness.gd` already gives each town a Blackboard scope that every mind's
blackboard is parented to. The director writes there (booked slots, role assignments, scene cues); a person's tree
reads them with a BTCheckVar ahead of everything else in `give_villager`'s BTDynamicSelector; square-wide events go
out through `awareness.stimulus()`.

A LimboAI HSM per town (states = parts of the day), its blackboard parented to the town's awareness scope. It
reads the facts, keeps a **schedule** and a **mood**, and asks the scene scheduler for scenes. It owns nothing the
bridge owns.

**The day (schedule), crown's seat on a market day:**

| Part | Hours | What the square is | Scenes the director asks for |
|---|---|---|---|
| Dawn | 5:30-7:00 | waking, setting up | stalls set out, the cart arrives and unloads, smith lights the forge, water at the well |
| Morning | 7:00-12:00 | market at its busiest | family shops ×2, gossip circle, cart unload, crier, smithy customer, guard change at 9:00 |
| Noon | 12:00-13:00 | a lull, meals | gossip circle, water at the well, children play, stalls quiet |
| Afternoon | 13:00-18:00 | trade again, lighter | family shops, smithy customer, crier, guard change at 15:00 |
| Evening | 18:00-21:30 | stalls close, tavern fills | stalls pack up, children called home, drinkers to the tavern, guard change at 19:00 |
| Night | 21:30-5:30 | watch only | guard pair walks; nothing else in the square |

A non-market day drops the busiest morning scenes; a hamlet keeps dawn water, a gossip circle and evening.

**Mood bends the day** (from the facts, one rule each, data):

| Mood (fact) | Bend |
|---|---|
| hunger / famine | a queue at the granary scene, fewer stalls open (`moods.json stalls_open`), short tempers (arguing beats in family shops), no music |
| prosperity | every stall open with full piles, a minstrel scene, more family shops |
| levy raised | a muster scene in the square (sergeant, men falling in, families seeing them off), fewer shoppers |
| war near | guards doubled (two guard pairs), people hurry (walk pace up, shorter dwell), stalls close early |
| feast | bunting, a crowd scene round the fire, dancing, the tavern full |
| grief | a funeral procession scene, mourning cloth, the square half empty, no crier |
| a ruling at the town | the crier's scene reads it out |
| rain | most scenes off; people hurry home |

### Layer 3: scenes (group routines)

A scene is a small play: **roles, a gathering place (smart objects), beats, and an end**. One coordinator task
(LimboAI BT) runs the beats and cues each member; members' own trees wait on their cue. Copied from RDR2's
scenarios, AC Unity's systemic crowd events and The Sims' group activities.

Each scene in data (`realm/data/scenes.json`): roles (who can play each, how many), the objects it uses (stall,
well, cart tail, gate, forge, a talk ring), beats (who does what, which clips, how long, what it waits for), the
result each beat leaves (a pile grows, a basket in hand), an end (everyone released with a destination), and a
cooldown.

**The first six:**

| Scene | Roles | Beats | Ends |
|---|---|---|---|
| a. A family shops | mother (leads), 2 children | in off a street, the children following a step behind; at a stall she haggles with the keeper (keeper serves), the children fidget (Bored, Looking_Around, tug: Pointing_Forward); the hand-over; basket in her hands | walk home together, the children beside her |
| b. The cart unloads | carter, 2 porters, the stallholder | cart halts at the market; porters take sacks off the tail in turn (one walks while the other lifts), carry on the shoulder to the stall, set down; keeper stacks (PickUp_Table, Nodding) | the carter climbs up, the cart leaves along the street; porters walk off |
| c. The crier | crier, 6-10 listeners | he rings a bell (Yelling), people turn and gather in a half-ring facing him; he reads (Talking_Hands, Pointing_Forward); they listen, nod, a cheer or a mutter by the news's tone | he walks off; the ring disperses in different directions |
| d. Guard change | 2 fresh guards, the 2 on duty | the fresh pair march out of the gate to the well; the two pairs face each other; salute; swap places | the old pair march back in through the gate; the new pair take up the beat |
| e. Gossip circle | 3-4 women with buckets | meet at the well, set buckets down, a ring facing in, talk with turn-taking (chatter.gd floor), laughs | one picks up her bucket and leaves, then the others one by one, each a different way |
| f. The smithy | smith, apprentice, a customer and horse | the customer leads a horse in and ties it; the boy works the bellows; the smith fetches the shoe, hammers, fits it (Crouch_Idle at the hoof), the customer waits (Weight_Shift, Arms) | the customer pays, unties the horse and leads it off |

Later: stalls set out and pack up, the funeral, the muster and seeing off, the feast round the fire, a granary
queue, children called home, drinkers to the tavern, a minstrel, a quarrel the guards break up.

**The scheduler** (part of the director): keeps 3-4 scenes running in view at once (data), staggered so one starts
or ends every 20-40 s; never two of the same kind side by side; a scene starts only when its roles can be cast
from people nearby or walking in, and its objects are free (the smart-object slots).

### Layer 4: people

Bodies, walking and motion stay as they are (`villagers.gd`, NavigationServer2D with RVO, smooth-motion rules,
the turn clips). Each person's tree becomes small: **on a cue, play the beat; with no cue, walk to the destination
the director gave, or leave the square.** No Weigh, no activity of their own. Rules, enforced by the probe:

1. Nobody acts in open space: every beat names an object or a partner within 1 m.
2. No clip held more than 8 s; no person plays the same scene role twice in a row.
3. Nobody stands still more than 10 s without a claimed slot.

## 3. What maps where, and what is retired

| Today | Becomes | Retired? |
|---|---|---|
| `awareness.gd` town scope | layer 1, as is (+ market day, gold seam spent from the bridge) | kept |
| `villagers._block` (parts of the day) | the director's day HSM | moved |
| `npc_mind` Weigh / `villager_activities` for square callings | scene roles | retired for the square (kept for other towns until they move) |
| `npc_mind` GoTo, Turn, Talk, JoinCircle, serve, Sack, spot_step, PlayRun | beat tasks the scenes use | kept |
| `villagers._slot` (stall, well, street, cart) | the scenes' objects | kept, + Occupied state |
| `town_life` posted crowd at the square (gossip knot, listeners, guards on spots, buyers, porters at the stall ends, open smith) | scenes c, d, e, b | retired with the switch on |
| SquareLife patrol, straight errands, chase | scene d; walkers with a destination; a children's play scene | retired with the switch on |
| the remaining posted crowd (crier's listeners, beggars, guards on spots, cart seller and buyer, stall-end porters, weeders) | scene members cast by the director, or nothing | retired with the switch on |
| the old callings at the crown (pious, idler, gentry) in the square | walkers passing through with a destination, or scene members | retired for the square |
| `villagers.place` fallback from a full slot to the "market" ring | none: a failed claim walks on or leaves | retired (already, with square agents on) |
| SquareLife cart | scene b drives it | moved |
| keepers, smith and bellows (posted) | scene members with standing roles | kept as members |
| `castle_folk.gd` | out of scope (the bailey); later its own scenes | kept |

## 4. Probes (headless)

- `tools/square_probe.gd` (new): stands Kingsmere's square up on flat ground with stalls, a well, a gate, a forge,
  runs it 60 s at 10×, and prints: agents acting with no object or partner within 1 m (with role and activity),
  agents still > 10 s without a claimed slot, clips held > 8 s, a role repeated twice running; then each scene of
  the six run to its end (started, beats in order, ended, everyone released). Exit 1 on any non-zero.
- `mind_probe` keeps checking the beat trees.

## 5. Stages (each pushed and filmed)

1. The square probe, run on today's code: name the looping man and count the faults (the baseline).
2. The director skeleton behind `--town-director=on`: the day HSM from the clock and the facts; the scheduler with
   one scene (e, the gossip circle at the well); no Weigh in the square; anyone not cast walks with a destination.
3. Scenes b (cart unload) and a (family shops).
4. Scenes c (crier) and d (guard change); the posted crowd and SquareLife movers off with the switch.
5. Scene f (smithy with a customer and a horse); mood bends (hunger, prosperity, levy, war, feast, grief).
6. Market day and gold seam spent from the bridge (bridge change: owned there, read here).

Clips still missing (from townsfolk-routines.md): hand over / take, pull a well rope, a bell ring, salute is in,
shoe a horse (Crouch_Idle stands in), arms crossed, start/stop walking.
