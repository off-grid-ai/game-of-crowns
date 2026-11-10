# NPC activities on LimboAI: clips, roles, the selector

Discovery and design only. Nothing in the repo was changed and the game was not run.
Read: `realm/assets/anims/**`, `realm/assets/hero/anims/`, `motion.gd`, `people.gd`, `villagers.gd`,
`town_life.gd`, `scenes.gd`, `combat.gd`, `battle_ai.gd`, `interior.gd`, plus `hero_view.gd`, `horse.gd`,
`towns.gd`, `units.gd`, `siege_ai.gd` where they play clips. LimboAI is v1.8.1 (`addons/limboai/version.txt`).

## 0. What I found first (it shapes everything below)

- **Three animation libraries, and the crowd only sees one.** `people.gd` builds every person's library from
  `assets/anims/mixamo/*.fbx` only (151 clips). The 40 clips in `assets/hero/anims/` load only in the close-up
  character view (`hero_view.gd`), and there only `Breathing Idle` plus 7 fidgets ever play outside a test shot.
  The 46 clips inside `assets/anims/AnimationLibrary_Godot_Standard.gltf` (Quaternius Universal Animation
  Library, same set as `UAL1_Standard.fbx`) are loaded by no script at all. That second library holds the
  sitting set, a torch-holding idle, a formal walk, crouch, jog and jump.
- **Carrying and Wheelbarrow never show on the move.** `villagers.gd` plays them as the gait while walking
  (`GAITS`), but `motion.gd` holds back any looping standing move while the person is moving, so the legs
  play `Walk` and the load only shows once they stop. Comments in `people.gd` say this was on purpose, because
  the clips' legs barely swing. I worked this out from reading the code and haven't seen it in the game.
  The fix that needs no new clip is a Godot blend with a bone filter: arms from `Carrying`/`Wheelbarrow`,
  legs from the walk blend space (`AnimationNodeBlend2` with filters, inside the existing tree).
- **Some one-off moves loop.** `motion.gd`'s `ONCE` list decides what loops. `Bow` (a courtly bow) and
  `Axe_Combo_1/2` aren't in it, so they loop. `Getting_Up_2` and `Groin_1` are covered by prefix.
- **Today, every move is one clip held for 3-20 s.** `villagers.gd` picks one `work` clip per stop and holds it
  for `wait`. `town_life.gd`'s LimboHSM (`_job`, switched off: `LIMBO_TOWNS` is empty) does
  Work 6-12 s → Pause 2-5 s → Shift → Work, never the same move twice. That's the right shape. What's missing
  is steps that mean something (fetch, then set down, then work) and run lengths counted in cycles, not seconds.

Abbreviations for "used today": V villagers.gd, TL town_life.gd, SC scenes.gd, CB combat.gd, BA battle_ai.gd,
IN interior.gd, PE people.gd (idle/talk/guard variants), TW towns.gd, UN units.gd, SA siege_ai.gd,
HO horse.gd, HV hero_view.gd. Mentions that only sit in `motion.gd`'s ONCE/WALKS lists don't count as use.
Loop / one-off is what `motion.gd` does today. "→ should be" marks where that's wrong.

## 1. Clip inventory

### 1a. `assets/anims/mixamo/` (151 clips: the crowd's library)

| Clip | What it shows | Loop / one-off | Where it fits | Used today? |
|---|---|---|---|---|
| Arguing | angry two-handed argument | loop | haggling, quarrel, rioter, hall debate | V (haggle, riot, evening), TL (riot, stalls), IN (hall) |
| Axe_Backhand | axe backhand swing | one-off | axe duel, heavy drill | CB axe kit |
| Axe_Block_Idle | axe held across in guard | loop | axe guard | CB |
| Axe_Block_React | axe parry | one-off | axe duel | CB |
| Axe_Combo_1 | multi-swing axe combo (guess) | loop → should be one-off | axe duel, heavy drill | **no** |
| Axe_Combo_2 | second axe combo (guess) | loop → should be one-off | axe duel, heavy drill | **no** |
| Axe_Down | overhead axe chop | one-off | axe duel; woodcutting with an axe prop | CB |
| Axe_Horizontal | flat axe swing | one-off | axe duel, heavy drill | CB |
| Axe_Idle | axe at the ready | loop | axeman's stance; woodcutter resting | CB |
| Axe_Kick | kick, axe in hand | one-off | axe duel | CB |
| Axe_Spin | spinning axe cut | one-off | axe duel (heavy) | CB |
| Axe_Walk | walk carrying an axe | gait | axeman moving; woodcutter to the woods | CB |
| Back_Head | struck on the back of the head | one-off | duel reel | CB |
| Back_Hit | struck in the back | one-off | duel reel; rioter shoved from behind | CB |
| Battlecry | weapon up, rallying shout | one-off | battle, muster, handover, sergeant | SC, BA |
| Body_Big_1 | heavy body blow, goes down | one-off | duel (a floor) | CB |
| Body_Big_2 | heavy body reel | one-off | duel; hit by a charging knight | CB, BA |
| Body_Big_3 | heavy body reel | one-off | duel | CB |
| Body_Block | forearms up, fist guard | loop | fist guard; tavern brawl | CB fists |
| Body_Light_1 | light body reel | one-off | duel; brawl; shoved rioter | CB |
| Body_Light_2 | light body reel | one-off | duel; brawl | CB |
| Body_Light_3 | light body reel | one-off | duel; brawl | CB |
| Bored | restless, bored stance | loop | idle filler: stall, guard, waiting | V (solo idle) |
| Bow | courtly bow | loop → should be one-off | court, greeting the gentry or a priest, end of a dance | IN (great hall) |
| Bow_Aim | holding a drawn bow | loop | archer drill, battle | TL drill |
| Bow_Draw | nocking and drawing | one-off | archer drill, battle | SC, TL |
| Bow_Idle | archer at rest | loop | archer stance | SC, BA, PE, UN |
| Bow_Shoot | loosing an arrow | one-off | archer drill, battle | SC, TL |
| Boxing | boxing stance, bouncing | loop | fists/dagger stance; tavern brawl; children play-fighting | CB |
| Breathing_Idle | standing, breathing | loop | idle variant | PE (IDLES) |
| Carrying | load held in front, small steps | loop (a gait in V) | every fetch-and-carry step | V, TL, IN, TW |
| Cheering | arms up, cheering | loop | feast, toast, victory, welcome | SC, V, TL, BA, IN |
| Crying | weeping | loop | mourner, beggar, refugee, grief | V, TL |
| Dance | dancing | loop | feast, tavern, children | SC, V, TL, IN |
| Death01 | falls dead | death | fists/dagger death; battle | SC, BA, CB |
| Death_Back | falls backward dead | death | battle | SC, BA, CB |
| Death_Front | falls forward dead | death | battle, arrows | SC, BA |
| Defeated | slumped, head hung | loop | hunger, grief, beggar, routed soldier, refugee | V, TL, BA |
| Dodge_Back | steps back from a blow | one-off | duel, battle | BA, CB |
| Dodge_Left | sidesteps left | one-off | duel, battle; children dodging in tag | BA, CB |
| Dodge_Right | sidesteps right | one-off | duel, battle; children dodging in tag | BA, CB |
| Drinking | drinks from a cup | loop | tavern, feast, a swig on a break | V, TL, IN |
| Fall_Back_Death | falls back dead | death | fists, battle | BA, CB |
| Fist_Fight_A | one half of a paired brawl | loop | riot scuffle, tavern brawl | TL (riot) |
| Fist_Fight_B | other half of the brawl | loop | riot scuffle, tavern brawl | TL (riot) |
| Fixing_Kneeling | kneels, works with hands | loop | builder low work, weeding, mending, smith | V, TL |
| GS_Attack | greatsword overhead | one-off | greatsword duel | CB |
| GS_Block_1 | greatsword parry | one-off | greatsword duel | CB |
| GS_Block_2 | greatsword guard held | loop | greatsword guard | CB |
| GS_Death_1 | greatsword man dies | death | duel | CB |
| GS_Death_2 | greatsword man dies | death | duel | CB |
| GS_Idle | greatsword ready | loop | greatsword stance | CB |
| GS_Impact_1 | greatsword man hit | one-off | duel | CB |
| GS_Impact_2 | greatsword man hit | one-off | duel | CB |
| GS_Impact_3 | greatsword man hit | one-off | duel | CB |
| GS_Kick | kick, greatsword in hand | one-off | duel | CB |
| GS_Slash_1 | greatsword slash | one-off | duel, heavy drill | CB |
| GS_Slash_2 | greatsword slash | one-off | duel, heavy drill | **no** |
| GS_Slash_3 | greatsword slash | one-off | duel, heavy drill | CB |
| GS_Slash_4 | greatsword slash | one-off | duel, heavy drill | **no** |
| GS_Spin | spinning greatsword cut | one-off | duel | CB |
| GS_Walk | walk with a greatsword | gait | greatsword man moving | CB |
| Getting_Up | up from the ground | one-off | after a knock-down; drunk getting up | CB |
| Getting_Up_2 | up from the ground, other way (guess: face down) | one-off | after a leg fall; child after a tumble | **no** |
| Groin_1 | kicked low, doubles over | one-off | kick reel | **no** |
| Groin_2 | kicked low, doubles over | one-off | kick reel | CB |
| Happy_Gesture | glad talking gesture | loop | talk variant, feast, deal struck | SC, V, PE |
| Head_Big_1 | heavy head blow | one-off | duel | CB |
| Head_Big_2 | heavy head blow | one-off | duel | CB |
| Head_Light_1 | light head blow | one-off | duel; brawl | CB |
| Head_Light_2 | light head blow | one-off | duel; brawl | CB |
| Head_Light_3 | light head blow | one-off | duel; brawl | CB |
| Hit | generic flinch | one-off | fists/dagger reel; child bumped | CB |
| Idle | standing | loop | everywhere | many |
| Idle_Talking | talking with the hands | loop | every conversation | many |
| Injured_Hurting | clutching a wound (guess) | loop | wounded after battle; beaten rioter; sick in famine | **no** |
| Injured_Idle | standing hurt | loop | badly hurt fighter; wounded after battle | CB |
| Injured_Walk | limping | gait | hurt fighter; drunk staggering home; lame beggar | CB |
| Interact | works with the hands at waist height (guess) | loop | bench, stall, builder, tavern counter | V, TL |
| Kick_Front | front kick | one-off | fists/dagger duel | CB |
| Kidney_Big | heavy side blow | one-off | duel; charge | BA, CB |
| Kidney_Light | light side blow | one-off | kick reel | CB |
| Kneeling | kneels and stays | loop | chapel, beggar, fealty, at a grave | V, TL, IN |
| Knocked_Down | knocked flat | one-off | duel floor | CB |
| Laughing | laughing | loop | tavern, feast, listener | SC, V |
| Legs_1 | struck in the legs, falls | one-off | duel floor | CB |
| Legs_2 | struck in the legs, falls | one-off | duel floor | CB |
| Looking_Around | glancing about | loop | idle, waiting, watching, browsing | V, TL, PE |
| Milking | seated milking (guess) | loop | farmer at the byre, dawn and evening | V, only when a bridge plan says "milk" |
| Nodding | nodding along | loop | listener, deal struck | V, TL |
| PickUp_Table | lifts something from table height | loop | pick up / set down a load; handling goods | V, TL |
| Pick_Fruit | reaches up to pick | loop | harvest, orchard | V |
| Planting | stoops to plant | loop | sowing | V |
| Praying | prays standing (guess) | loop | sept, grief, faith | V, TL, IN |
| Punch_1 | punch | one-off | fists/dagger duel; brawl | CB |
| Punch_2 | punch | one-off | fists/dagger duel; brawl | CB |
| Punch_3 | punch | one-off | fists/dagger duel; brawl | CB |
| Punch_Jab | jab | one-off | fists duel; brawl; children play-fighting | CB |
| Pushing | shoves something heavy | loop | builder, stuck cart, rioter at the door | **no** |
| React_Front | flinches from the front | one-off | struck villager; axe/fists reel | V (struck), CB |
| React_Gut | hit in the gut | one-off | axe reel; brawl | CB |
| React_Head | hit in the head | one-off | axe/fists reel; brawl | CB |
| React_Left | hit from the left | one-off | duel | CB |
| React_Right | hit from the right | one-off | duel | CB |
| Ride_Grasp | in the saddle, hands on the reins | loop | rider at a canter or gallop | HO |
| Ride_Relaxed | in the saddle, at ease (guess) | loop | rider at a walk; lord riding through town | **no** |
| Running | run | gait | flee, refugees, children | SC, V, PE, CB, IN |
| SS_Attack_3 | sword-and-shield attack | one-off | duel, drill | TL drill, CB |
| SS_Attack_4 | sword-and-shield attack | one-off | duel, drill | CB |
| SS_Block_1 | shield block | one-off | duel | CB |
| SS_Block_2 | shield block | one-off | duel | CB |
| SS_Block_Idle | shield raised and held | loop | shield wall, guard | SC, BA, CB, PE |
| SS_Death_1 | sword man dies | death | duel | CB |
| SS_Death_2 | sword man dies | death | duel | CB |
| SS_Idle_2 | sword-and-shield ready | loop | guard stance variant | PE (GUARDS) |
| SS_Impact_1 | sword man hit | one-off | duel | CB |
| SS_Impact_2 | sword man hit | one-off | duel | CB |
| SS_Impact_3 | sword man hit | one-off | duel | CB |
| SS_Kick | shield-man kick | one-off | duel | CB |
| SS_Slash_1 | sword slash | one-off | duel, drill | TL, TW, CB |
| SS_Slash_2 | sword slash | one-off | duel, drill | **no** |
| SS_Slash_3 | sword slash | one-off | duel, drill | CB |
| SS_Slash_4 | sword slash | one-off | duel, drill, muster | SC, TL, TW, CB |
| SS_Slash_5 | sword slash | one-off | duel, drill | CB |
| SS_Walk | walk behind a shield | gait | shield line advancing | SC, SA, BA, CB |
| Salute | salute | one-off | muster, handover, convoy, guard to a lord | SC |
| Shield_Block | shield block | one-off | duel, battle | SC, CB |
| Side_Big | heavy blow to the side | one-off | duel, charge | BA, CB |
| Side_Light | light blow to the side | one-off | duel reel; brawl | **no** |
| Sneak | crouched creeping walk | gait | children's hide-and-seek, poacher, thief, scout | **no** (only in WALKS lists) |
| Spear_Thrust | spear thrust | one-off | drill, battle, gate guard warning a riot | SC, TL, BA, TW |
| Sprint | sprint | gait | charge, rout, messenger | SC, SA, BA, CB |
| Standing_Idle | standing | loop | idle variant | PE |
| Standing_Idle_2 | standing | loop | idle variant | PE |
| Stunned | dazed | one-off | kick reel; drunk; after a brawl | CB |
| Sword_Attack | plain one-handed cut | one-off | sword drill at a post; duel | **no** (only a timing entry in CB) |
| Sword_Attack_2 | one-handed cut | one-off | duel, battle | SC, BA, CB |
| Sword_Death | sword man dies | death | duel, battle | SC, CB |
| Sword_Idle | soldier at the ready | loop | soldier stance, guard | many |
| Talking | talking | loop | talk variant | V, PE |
| Talking_2 | talking | loop | talk variant | V, PE |
| Telling_Secret | leans in to tell a secret | loop | gossip, tavern, gentry | V |
| Terrified | cowering in fear | loop | fear, riot onlookers, struck | V |
| Thinking | hand to chin | loop | listener, inspecting work, browsing | V (LISTEN) |
| Walk | walk | gait | everywhere | many |
| Watering | pours from a can | loop | watering crops; pouring ale (stand-in) | V |
| Waving | waves | loop | greeting, children, welcome | SC, V |
| Weight_Shift | shifts weight | loop | idle variant, breather | PE |
| Wheelbarrow | pushes a barrow | loop (a gait in V) | carting crops, rubble, timber | V, PE |
| Whispering | whispers | loop | gossip, sept, gentry | V, TL |
| Yelling | shouts | loop | rioter, sergeant, stall cry, captain | SC, V, TL, BA, TW |

13 Mixamo clips are never played today: Axe_Combo_1, Axe_Combo_2, GS_Slash_2, GS_Slash_4, SS_Slash_2,
Getting_Up_2, Groin_1, Injured_Hurting, Pushing, Ride_Relaxed, Side_Light, Sneak, Sword_Attack.
Milking plays only if the minds happen to say "milk". 138/151 (91%) are referenced. About 43 of those
appear in town life; the rest are combat only.

### 1b. `assets/hero/anims/` (40 clips: close-up view only)

Same humanoid retarget as the crowd's moves (`hero_view.gd` says they "play on any body people.gd makes").
18 of them repeat a Mixamo-folder move. The other 22 are new and suit the crowd well.

| Clip | What it shows | Loop / one-off (HV rule) | Where it fits | Used today? |
|---|---|---|---|---|
| Acknowledge | a nod and small gesture of thanks | one-off | guard to a passer-by, keeper to a buyer | HV fidget |
| Angry | angry outburst | one-off | rioter, haggler losing, keeper at a drunk | test shot only |
| Annoyed | irritated gesture | one-off | haggler, guard, tavern keeper | test shot only |
| Arguing | = Mixamo Arguing | loop | as Arguing | dupe |
| Bow | = Mixamo Bow | one-off here | as Bow | dupe |
| Breathing Idle | = Mixamo Breathing_Idle | loop | | HV default |
| Cocky | swaggering stance | one-off | reveller, young recruit, sellsword | test shot only |
| Crouch And Point | crouches, points at the ground | one-off | foreman at the work, farmer at a row, child | test shot only |
| Crying | = Mixamo Crying | | | dupe |
| Defeated | = Mixamo Defeated | | | dupe |
| Disappointed | let-down shrug, head drops | one-off | farmer at a poor crop, buyer refused, hunger | test shot only |
| Dismiss | waves someone off | one-off | gentry passing a beggar, keeper to a haggler | test shot only |
| Doubtful | sceptical look | one-off | buyer weighing a price, listener | test shot only |
| Drinking | = Mixamo Drinking | | | dupe |
| Dying | dies slowly | death | wounded man after a battle | test shot only |
| Firm Nod | a firm nod | one-off | deal struck, order taken | test shot only |
| Great Sword Idle | ≈ GS_Idle | loop | greatsword stance | test shot only (dupe in effect) |
| Idle | = Mixamo Idle | | | HV fallback |
| Kneeling Idle | kneels, still | loop | beggar, chapel, fealty, grave | test shot only |
| Laughing | = Mixamo Laughing | | | dupe |
| Look Away | glances away | one-off | shy child, gentry snubbing, breather | HV fidget |
| Nod Yes | nods yes | one-off | buyer agrees, listener | HV fidget |
| Pleased | pleased gesture | one-off | buyer, lady at a stall, beggar given alms | test shot only |
| Praying | = Mixamo Praying | | | dupe |
| Relieved Sigh | sighs with relief | one-off | the breaker after a work run ("wipe brow") | HV fidget |
| Salute | = Mixamo Salute | | | dupe |
| Sarcastic Nod | mocking nod | one-off | tavern talk, rioter at a guard | test shot only |
| Shake No | shakes head no | one-off | buyer refusing, keeper refusing credit | test shot only |
| Slow Nod | slow nod | one-off | elder listening, priest | test shot only |
| Standing Idle | = Mixamo Standing_Idle | | | HV fidget |
| Sword And Shield | sword-and-shield stance | loop | guard stance variant | test shot only |
| Talking Hands | talks with big hand gestures | one-off | preacher, stall cry, storyteller | test shot only |
| Talking | = Mixamo Talking | | | dupe |
| Telling A Secret | = Mixamo Telling_Secret | | | dupe |
| Thinking | = Mixamo Thinking | | | HV fidget |
| Victory Idle | triumphant stance | loop | victors after a battle, tourney winner | test shot only |
| Walking | = Mixamo Walk | | | dupe |
| Waving | = Mixamo Waving | | | dupe |
| Weight Shift | = Mixamo Weight_Shift | | | HV fidget |
| Yelling | = Mixamo Yelling | | | dupe |

I'm treating the 18 matching names as the same move as the Mixamo-folder copy. Someone should check by eye
before loading both.

### 1c. `assets/anims/AnimationLibrary_Godot_Standard.gltf` (UAL, 46 entries; no script loads it)

Clip names come from the glTF `animations` array. Retarget fit with `people.gd`'s skeleton hasn't been
checked. The file name says Godot-standard bones, which is promising. Several names match clips already in
`mixamo/` (Fixing_Kneeling, Interact, PickUp_Table, Death01, Punch_Jab, Sword_Attack, Sword_Idle), so those
folder copies probably came from here.

| Clip | What it shows | Loop / one-off | Where it fits | Used today? |
|---|---|---|---|---|
| A_TPose | T-pose reference | (not a move) | nowhere | no |
| Crouch_Fwd_Loop | crouched walk | loop gait | hide-and-seek, poacher (Sneak alternative) | no |
| Crouch_Idle_Loop | crouched, still | loop | child hiding, gardener at a low bed, hiding during a riot | no |
| Dance_Loop | dance (≈ Dance) | loop | feast, tavern | no (likely dupe) |
| Death01 | = mixamo Death01 | death | | no (dupe) |
| Driving_Loop | seated, steering (guess) | loop | carter on the wagon bench | no |
| Fixing_Kneeling | = mixamo copy | loop | | no (dupe) |
| Hit_Chest | hit in the chest | one-off | brawl, struck villager | no |
| Hit_Head | hit in the head | one-off | brawl, struck villager | no |
| Idle_Loop | idle (≈ Idle) | loop | idle variant | no (likely dupe) |
| Idle_Talking_Loop | talking (≈ Idle_Talking) | loop | talk variant | no (likely dupe) |
| Idle_Torch_Loop | stands holding a torch up | loop | night watch, a procession after dark, the tavern door at night | no |
| Interact | = mixamo copy | loop | | no (dupe) |
| Jog_Fwd_Loop | jog | loop gait | messenger on foot, children, a hurried errand | no |
| Jump_Start / Jump_Loop / Jump_Land | a jump in three parts | one-off ×3 | children leaping a ditch, feast games | no |
| PickUp_Table | = mixamo copy | loop | | no (dupe) |
| Pistol_Aim_Down / Aim_Neutral / Aim_Up / Idle_Loop / Reload / Shoot | handgun moves | various | nowhere (wrong era) | no |
| Punch_Cross | cross punch | one-off | brawl | no |
| Punch_Enter | raises fists | one-off | brawl start, child play-fight | no |
| Punch_Jab | = mixamo copy | one-off | | no (dupe) |
| Push_Loop | pushes something (≈ Pushing) | loop | stuck cart, builder, rioters at the door | no |
| Roll | forward roll | one-off | tumblers at a feast, children | no |
| Roll_RM | the same roll with root motion | one-off | nowhere (people strip root motion; dupe) | no |
| Sitting_Enter | sits down | one-off | tavern bench, doorstep bench, feast table | no |
| Sitting_Idle_Loop | sitting | loop | tavern, bench, elders, beggar, refugees resting | no |
| Sitting_Talking_Loop | sitting and talking | loop | tavern table, elders on the bench | no |
| Sitting_Exit | stands up | one-off | end of any sit | no |
| Spell_Simple_Enter / Idle_Loop / Exit | raises a hand, holds it, lowers it | one-off / loop / one-off | a priest's blessing (guess: check that it doesn't read as magic) | no |
| Spell_Simple_Shoot | casts a bolt | one-off | nowhere (magic) | no |
| Sprint_Loop | sprint (≈ Sprint) | loop gait | | no (likely dupe) |
| Swim_Fwd_Loop / Swim_Idle_Loop | swimming | loop | nowhere: townsfolk never step into water (`villagers.gd` "the shore") | no |
| Sword_Attack | = mixamo copy | one-off | | no (dupe) |
| Sword_Attack_RM | root-motion copy | one-off | nowhere (dupe) | no |
| Sword_Idle | = mixamo copy | loop | | no (dupe) |
| Walk_Formal_Loop | upright, measured walk | loop gait | gentry promenade, priest, procession, herald | no |
| Walk_Loop | walk (≈ Walk) | loop gait | | no (likely dupe) |

## 2. Roles and their activities

### How to read the steps

- An **activity** is a fixed order of steps. A step is a clip pool, a run length and a place.
- **×3-5** on a looping clip means 3-5 cycles of that clip. The step waits `n × length`, which
  `motion.play()` already returns. On a one-off it means 3-5 plays back to back via `people.repeat`.
- **walk** is the walk/run blend (legs follow the ground). **carry** is a walk with a load: the `Carrying`
  arms over walking legs, which needs the arm/leg blend from section 0. Until that exists, play `PickUp_Table`
  at both ends so the load reads.
- **Breakers** run between work runs: one clip, 1-2 cycles or 2-5 s, never the one used last time.
  Shared pools:
  - **rest**: Weight_Shift, Breathing_Idle, Bored, Relieved Sigh\*, Looking_Around
  - **swig**: Drinking ×1-2
  - **look**: Looking_Around, Thinking, Look Away\*
  - **chat**: Idle_Talking / Talking / Talking_2 with a listener on Nodding / Laughing / Slow Nod\*. Only when
    someone is within reach (the existing `SOCIAL`/`_company` rule).
  - **greet**: Waving, Acknowledge\*, Nod Yes\*, when someone walks past within about 0.4.
- \* is a hero clip (needs `hero/anims` in the crowd library). U is a UAL clip (needs that library loaded).
- Places are the ones `villagers.gd` already knows: home/bench (doorstep), field strip, well (the square),
  market, tavern, sept. `town_life.gd` adds: site, drill ground, stalls, the door (riot/hunger), bonfire.
- Time blocks are `villagers._block()`: night <5.5 / ≥21.5, dawn <7, work <12, meal <13, work2 <18, evening.
  Moods are `_town_mood()`: riot (disorder), hunger (famine), feast (celebrating). Each person's own feelings
  come from the minds: grief, fear, hunger, faith, anger, joy.

### Farmer (`role == "farmer"`, peasant)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Sow | walk to strip → Planting ×3-5 → walk 1 pace along the row → Planting ×3-5 → Crouch And Point\* (checks the row) → Planting ×3-5 | rest, swig, look; greet to a neighbour on the next strip | field strip | work/work2, spring (`_field_work`) |
| Water | walk to well → PickUp_Table ×1 (fills the can) → carry to strip → Watering ×3-5 → walk 1 pace → Watering ×3-5 → back to well when "empty" (after 2 runs) | rest, look | well → field | work/work2, spring/summer |
| Weed | walk to strip → Fixing_Kneeling ×3-5 → Getting_Up_2 → walk 1 pace → Fixing_Kneeling ×3-5 → Disappointed\* (1 in 4, poor crop) | rest, Relieved Sigh\*, swig | field strip | summer; spring 1 in 4 |
| Harvest | walk to strip → Pick_Fruit ×3-5 → PickUp_Table ×1 (fills the basket) → Pick_Fruit ×3-5 → PickUp_Table ×1 → Wheelbarrow walk home → PickUp_Table ×1 (unloads) | rest, swig, chat with the next picker | field → home | autumn |
| Milk | walk to the home yard → Milking ×4-6 → Getting_Up → carry the pail to the door → PickUp_Table ×1 | look | home yard / byre | dawn and evening, every season (1 in 3 farmers). Needs a cow prop. |
| Yard chores | Carrying wood to the bench → PickUp_Table ×1 → Axe_Down ×3-5 with an axe prop (split wood) → Fixing_Kneeling ×3-5 (stack) → Pushing ×2-3 (shut the barn door / shift the cart) | rest, Relieved Sigh\* | home bench | winter (no field work), or 15% break roll |
| Hunger | walk to strip → Disappointed\* → Defeated ×3-5 → Looking_Around | Praying | field / door | town mood hunger |

### Builder (`town_life._construction`, peasant at the site)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Raise the frame | walk to a spot on the front → Fixing_Kneeling ×3-5 (low nailing) → Getting_Up → step back 2 paces → Thinking or Looking_Around ×1 (eyes the work) → walk in → Interact ×3-5 (fits at waist height) | rest, swig, Relieved Sigh\* | site front | site exists (`Building` in production), work/work2 |
| Fetch timber | walk to the wood pile → PickUp_Table ×1 → carry to the frame → PickUp_Table ×1 (sets down) → Pushing ×2-3 (shoves the beam home) | rest | wood pile → frame | after every 2 frame runs |
| Cart rubble | PickUp_Table ×1 at the frame → Wheelbarrow walk to the cart → PickUp_Table ×1 | rest, swig | frame → cart | 1 builder in 3, alternating with Fetch |
| Foreman | Thinking ×2 → Crouch And Point\* → Yelling ×1-2 (orders) → Nodding ×2 with a builder → walk the front | Firm Nod\*, look | site, 1 per site | first builder spawned |
| Down tools | Relieved Sigh\* → walk to the tavern or home | | | meal block, or progress hits 100% (then Cheering ×2 together first) |

### Smith / crafter (`role == "crafter"`, home bench)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Bench work | walk to bench → PickUp_Table ×1 (takes up the piece) → Interact ×3-5 (shapes it) → Thinking ×1 (inspects) → Interact ×3-5 → Fixing_Kneeling ×3-5 (low work: a wheel, a barrel hoop) | rest, swig, greet to passers-by | home bench | work/work2, 80% |
| Smith at the anvil | Interact ×3-5 (gap: hammering) → Watering ×1 (quench, stand-in) → Thinking ×1 → Interact ×3-5 | rest, Relieved Sigh\*, swig | bench (a forge prop when the town has one) | crafter whose byname is "the Smith", or 1 crafter in 4 |
| Take goods to market | PickUp_Table ×1 → carry to the market → PickUp_Table ×1 → chat (Idle_Talking ↔ Arguing with a keeper) → Firm Nod\* → walk home | | home → market | work/work2, 20% |
| Mend | walk to a neighbour's door → Fixing_Kneeling ×3-5 → Getting_Up → chat → Acknowledge\* | rest | another home | 1 in 6 work stops |

### Stall keeper (`town_life._trade`, at a stall)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Mind the stall | Interact ×3-5 (sets out goods) → Looking_Around ×1 → PickUp_Table ×1 (moves a crate) → Interact ×3-5 | Bored, Weight_Shift, swig, Whispering with the next keeper | behind the counter | always, as the base loop |
| Cry wares | Yelling ×1-2 → Talking Hands\* ×1 → Waving ×1 | rest | counter | 1 run in 3, more when the market is busy |
| Serve a buyer | turn to the buyer → Idle_Talking ↔ Arguing (haggle, 2-4 turns, taking turns with the buyer) → Firm Nod\* or Shake No\* → PickUp_Table ×1 (hands it over) → Happy_Gesture or Acknowledge\* | | counter | a buyer arrives (blackboard trigger) |
| Pack up | PickUp_Table ×2 → carry home | | stall → home | evening |
| Empty stall | Defeated ×3-5 → Looking_Around → Disappointed\* | | counter | town mood hunger |

### Buyer (market role, gentry, anyone at a stall)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Browse | walk to a stall → Looking_Around ×1 → PickUp_Table ×1 (handles goods) → Thinking or Doubtful\* ×1 → walk to the next stall (2-3 stalls) | look | market | `market` role work; anyone with a plan saying trade/sell |
| Buy | at a keeper → Idle_Talking ↔ Arguing (2-4 turns) → Nod Yes\* or Shake No\* → PickUp_Table ×1 on yes → carry home, or Walk on no | Pleased\* on a good deal | stall → home | after Browse, 1 in 2 |
| Gossip at the stalls | chat with another buyer: Whispering / Telling_Secret / Laughing, 2-4 turns | | market edge | 1 in 3 market stops |

### Tavern keeper (`role == "tavern"`)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Serve | Interact ×3-5 (draws ale) → Watering ×1 (pours, stand-in) → carry to a drinker → PickUp_Table ×1 → chat ×1 → walk back | rest, Laughing | tavern | evening, meal, night (50%) |
| Fetch a keg | walk to the yard → PickUp_Table ×1 → carry in → PickUp_Table ×1 → Pushing ×2 (rolls it into place) | Relieved Sigh\* | tavern yard → tavern | work/work2 |
| Tidy | Interact ×3-5 (wipes; gap: sweeping) → PickUp_Table ×2 (clears cups) | Bored, look | tavern | work, between other jobs |
| Calm a quarrel | walk to the arguers → Annoyed\* → Yelling ×1 → Dismiss\* | | tavern | a brawl or argument starts there |
| Night door | Idle_Torch_Loop U ×3-5 → Looking_Around | Bored | tavern door | night |

### Drinker (`role == "tavern"` customers, anyone sent to the tavern in the evening)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Drink with friends | walk to the tavern → Sitting_Enter U → Sitting_Talking_Loop U ↔ Sitting_Idle_Loop U (taking turns, 2-4) → Drinking ×3-5 (no seat: standing knot, Drinking ↔ Idle_Talking as `kind "drink"` does today) → Sitting_Exit U | Laughing, Telling_Secret, Sarcastic Nod\* | tavern | evening; meal 20% |
| Toast | stand → Cheering ×1-2 (together) → Drinking ×2 → Laughing | | tavern | when the knot has 3+, 1 in 4 |
| Sing and dance | Dance ×3-5 → Cheering ×1 → Drinking ×1 → Dance ×3-5 | Weight_Shift (catches breath) | tavern floor | late evening; joy > 0.6 |
| Stagger home | Injured_Walk (stagger) home → Stunned ×1 halfway → Getting_Up if he falls | | tavern → home | leaves after 3+ drinks, 1 in 4 |
| Brawl | Punch_Enter U → Fist_Fight_A/B pair ~8 s → Punch_Jab / Punch_Cross U ×1-2 → Head_Light_n / Body_Light_n / Side_Light reel → Body_Block → Arguing → apart | | tavern / outside | anger > 0.6 and an argument already going; at most one pair per town |

### Guard / town watch (soldier station; riot door guards in `_crowd`; great hall)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Stand watch | guard stance (Sword_Idle / SS_Idle_2 / SS_Block_Idle / Sword And Shield\*) ×3-5 → Looking_Around ×1 → stance ×3-5 | Bored, Weight_Shift, chat with the other guard | gate, square, hall | default, day |
| Patrol | Walk (or SS_Walk) a short beat → stop → Looking_Around → stance → walk back | Acknowledge\* to passers | street beat | 1 guard in 2, work/work2 |
| Hold the door | SS_Block_Idle ×3-5 → Yelling ×1 → Spear_Thrust ×1 (a warning, not a blow) → SS_Block_Idle | | the door (riot) | town mood riot |
| Honour a lord | Salute ×1, or Bow ×1 (one-off) | | wherever | a named lord, the player's figure or a rider passes within 0.6 |
| Night watch | Idle_Torch_Loop U ×3-5 → Walk a beat → Looking_Around | | gate, square | night |
| Off duty | chat (Laughing, Cocky\*) → swig | | tavern | evening |

### Priest / pious (`role == "pious"`, clergy body 60%)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Pray | walk to the sept → Praying ×3-5 → Kneeling ×3-5 (or Kneeling Idle\*) → Getting_Up → Praying ×3-5 | Whispering with another, Slow Nod\* | sept | dawn; evening; work 40%; faith > 0.8 |
| Preach | stand facing a knot → Talking Hands\* ×1 → Idle_Talking ×3-5 → Happy_Gesture ×1; listeners Nodding / Slow Nod\* / Praying | swig | sept steps, well | 1 pious per town in work2, when 3+ are at the sept |
| Alms | carry from the sept to a beggar → PickUp_Table ×1 (gives) → Kneeling ×1 beside them → Nodding → walk back | | sept → beggar | beggars present (hunger) |
| Bless | Spell_Simple_Enter U → Spell_Simple_Idle_Loop U ×2 → Spell_Simple_Exit U (guess: check it doesn't read as magic) | | sept, feast, funeral | feast start, funeral, handover |
| Lead the mourners | Walk_Formal_Loop U at the head → Praying at the grave ×3-5 → Slow Nod\* to the family | | street → grave | a funeral (see Mourner) |

### Gentry (`role == "gentry"`, noble_lady body)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Promenade | Walk_Formal_Loop U to the market → stop → Looking_Around ×1 → walk on | Look Away\* | street → market | work/work2, 65% |
| Browse (never haggle) | at a stall → Looking_Around ×1 → Thinking ×1 → Pleased\* or Look Away\* → Dismiss\* at a keeper's patter (1 in 4) | | market | after Promenade |
| Gossip | chat with another lady: Telling_Secret ↔ Whispering ↔ Laughing (2-4 turns) | Nodding | market edge, sept | another gentry person within reach |
| Greet | Bow ×1 (one-off) to a priest or lord; Waving to a lady | | anywhere | someone of rank within 0.6 |
| Pray | walk to the sept → Praying ×3-5 → Kneeling ×3-5 | | sept | dawn, evening, 35% of work |
| Pass a beggar | Dismiss\* or Look Away\*; 1 in 5 gives alms (PickUp_Table ×1 → Pleased\*) | | street | a beggar within 0.5 |

### Beggar (`town_life._crowd` not angry; anyone hungry and homeless)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Beg | Kneeling (or Kneeling Idle\*) ×3-5 → Praying ×1 (pleading) → Kneeling ×3-5 → Crying ×1 | Defeated, Looking_Around | by the door, sept steps, market edge | hunger crowd; grief/hunger mood with no work |
| Ask a passer | when someone comes near: Getting_Up → Idle_Talking ×1 facing them → on alms Pleased\* + Nodding; on a snub Defeated ×2 | | same | someone within 0.5 |
| Move on | Injured_Walk (lame) or Walk to another spot → Sitting_Enter U → Sitting_Idle_Loop U ×3-5 | | town edge | after 3 begging runs |
| Night camp | Sitting_Idle_Loop U by the embers → Defeated | | bedrolls by the wall | night |

### Reveller (`town_life._revels`, `scenes._feast`, villagers in feast mood)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Dance round the fire | Dance ×3-5 (the ring turns) → Cheering ×1 → Dance ×3-5 | Weight_Shift (breath), swig | bonfire ring | feast mood, evening 60% / day 30% |
| Toast | Drinking ×2-3 → Cheering ×1 together → Laughing | Happy_Gesture | edge of the square | 1 in 3 revellers |
| Cheer the dancers | Cheering ×1 → Waving ×1 → Laughing ×2 (gap: clapping) | | ring's edge | between dances, the ring's outer people |
| Swagger | Cocky\* → Telling_Secret → Laughing | | edge | young men, joy high |
| Tumble | Roll U ×1 → Getting_Up_2 → Cheering | | ring's middle | feast, 1 per feast, children or young |
| Wind down | Drinking ×2 → Sitting_Idle_Loop U → Stagger home (as Drinker) | | edge → home | late evening |

### Rioter (`town_life._crowd` angry; villagers in riot mood)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Shout at the door | Yelling ×3-5 → Arguing ×3-5 → Angry\* ×1 | Looking_Around (at the guards) | the door | riot mood, 35% (rest watch from their steps) |
| Press forward | walk 2 paces at the guards → Pushing ×2-3 (gap: shoving a man; Push_Loop U too) → Back_Hit or Body_Light_n (the guard shoves back) → walk back | | door | 1 in 4 per run |
| Scuffle | Fist_Fight_A/B pair 7-9 s → React_Head / Hit_Head U → Arguing (as today) | | near the door | 2 pairs per riot (today's rule) |
| Throw | (gap: throwing) Bow_Shoot is wrong; for now Yelling with a raised fist (Battlecry ×1) | | door | gap |
| Scatter | Terrified ×1 → Running home → Looking_Around from the step | | door → home | the guard thrusts, or someone falls |
| Watch from the step | Looking_Around ×3-5 → Terrified ×1 → Crouch_Idle_Loop U (hides) | | home step | riot, the 65% who don't go |

### Recruit (`town_life._drill`; `scenes._muster`)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Sword drill | fall in (Walk) → SS_Idle_2 → cuts ×3-4 drawn from SS_Slash_1-5, SS_Attack_3/4, Sword_Attack (never the same cut twice running) → stance | stand easy: Weight_Shift, Breathing_Idle | drill ground, one rank | town training a sword unit |
| Spear drill | Spear_Thrust ×3-4 → SS_Block_Idle ×1 → Spear_Thrust ×3-4 | stand easy | drill ground | spear unit |
| Bow drill | Bow_Draw → Bow_Aim ×1 → Bow_Shoot, the set ×3-4 → Bow_Idle | stand easy | butts | archer unit |
| Heavy drill | Great Sword Idle\* / GS_Idle stance → GS_Slash_1-4 / GS_Attack ×3-4, or Axe_Down / Axe_Horizontal / Axe_Backhand / Axe_Combo_1/2 ×3-4 | stand easy | drill ground | greatsword or axe unit (needs kit props) |
| Sergeant | Yelling ×1 → Crouch And Point\* → Battlecry ×1 → walk the rank → Firm Nod\* | Annoyed\* | front of the rank | 1 per drill |
| Fall out | Salute ×1 → walk off | | | end of the drill season (40 s today) |

No blocking in the drill. Mac ruled the crouched block reads as a fight (`town_life.gd` comment).

### Child (`role == "child"`)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Tag | Running (or Jog_Fwd_Loop U) after another child ×2-4 laps → Dodge_Left/Right ×1 → Laughing ×1 → swap chaser | Weight_Shift (puffed) | near home, square | work/work2 60%, 2+ children near |
| Hide and seek | seeker: Looking_Around ×3 → walk; hider: Sneak or Crouch_Fwd_Loop U to cover → Crouch_Idle_Loop U ×3-5 → found: Laughing → Running | | between houses | 2+ children, day |
| Play-fight | Punch_Enter U → Boxing ×2 → Punch_Jab ×1-2 → Hit ×1 → Laughing (no reels past "light") | | near home | boys, 1 in 5 |
| Skip and dance | Dance ×3-5 → Jump_Start/Loop/Land U ×1 → Waving | | near home, well | evening 40% |
| Help with chores | follow a parent → PickUp_Table ×1 → carry (Carrying) → PickUp_Table ×1 | | home ↔ well/field | dawn; with a farmer/crafter parent 1 in 3 |
| Wave at riders | Waving ×2 → Running alongside a few paces | | road edge | a rider, convoy or cart passes |
| Tumble and cry | Getting_Up_2 → Crying ×2 → an adult comes: Nodding | | anywhere | rare (1 in 30 runs) |
| Look shy | Look Away\* → walk behind a parent | | | a stranger or the player talks to them |

### Mourner (grief > 0.6; funerals the minds announce)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Funeral walk | Walk at 0.7 behind the priest (Walk_Formal_Loop U for the priest) → stop at the grave | | street → grave/sept yard | a death in town (minds witness) |
| Grieve at the grave | Kneeling ×3-5 → Crying ×3-5 → Praying ×3-5 → Getting_Up | Defeated | grave | after the walk |
| Comfort | knots of 2-3 (Mac's rule): one Crying, the other Idle_Talking softly → Slow Nod\* → Nodding; swap | | home step, sept | grief in 2+ who know each other |
| Grieve alone | Defeated ×3-5 → Sitting_Idle_Loop U on the bench ×3-5 → Crying ×1 | Looking_Around | home bench | grief, no partner |

### Refugee (`scenes._refugees`)

| Activity | Steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Trudge | Walk at 0.7, or Injured_Walk for the hurt, or Carrying (bundle) / Wheelbarrow (their goods) | | road away | spawned walking |
| Flee | Running (1 in 3, today's rule) → Looking_Around back the way they came | | road | the first third |
| Rest by the road | Sitting_Enter U → Sitting_Idle_Loop U ×3-5 → Crying or Defeated ×1 → Sitting_Exit U | Injured_Hurting (the wounded) | roadside | every ~10 s of walking, 1 in 3 |
| Pray for home | Kneeling ×2 → Praying ×3 | | roadside | faith high |

### Others the scripts imply

| Who | Activity: steps, in order | Breakers | Place | Picked when |
|---|---|---|---|---|
| Idler (calling "idler") | Stroll: walk to well or market → Looking_Around ×1 → chat if anyone is there, else Sitting_Idle_Loop U on a bench ×3-5 → walk on | Bored, Weight_Shift, greet | well, market, benches | the "idler" calling, any day block |
| Elder (age "elder") | Sit out: Sitting_Enter U → Sitting_Talking_Loop U with another elder ↔ Slow Nod\* → Sitting_Exit U; walks at 0.75 (today) | Thinking | home bench | elders, work and evening |
| Water carrier | walk to the well → PickUp_Table ×1 → carry home → PickUp_Table ×1 | chat at the well (Whispering) | well → home | dawn 40% (today's rule) |
| Carter (`scenes._traveller`) | walk at the horse's head; on a long road, ride the bench (Driving_Loop U, guess) | Pushing ×2 at a slope (wheel stuck) | road | cart travellers |
| Rider / messenger (`horse.gd`) | on foot: Jog_Fwd_Loop U with a letter; mounted: Ride_Relaxed at a walk → Ride_Grasp at a canter or gallop | | road | riders, lords through town |
| Convoy escort | walk → on arrival Waving / Salute / Cheering ×1 (today) | | road → town | convoy arrives |
| Soldier in a field battle (`battle_ai.gd`, LimboHSM) | Hold (stance, SS_Block_Idle, Battlecry/Yelling) → Advance (Walk, SS_Walk) → Charge (Sprint) → Fight (SS_Slash_1-5, SS_Attack_3/4, Sword_Attack_2, Spear_Thrust; answers SS_Block_1/2, Shield_Block, Dodge_*; reels SS_Impact_*, Body_*, Side_*, Kidney_*) → Run (Sprint, Defeated) or Cheer (Cheering, Battlecry, Yelling, Talking Hands\* boasting, then Victory Idle\*) | | battlefield | battle scene; already on LimboAI |
| Wounded after battle | Dying\* (some), Injured_Hurting ×3-5 → Injured_Idle → Injured_Walk off the field | | battlefield | the beaten side's survivors, after the rout |
| Duellist / the player's melee (`combat.gd` KITS) | sword, greatsword, axe, dagger, fists kits as now, plus SS_Slash_2, GS_Slash_2/4, Axe_Combo_1/2, Sword_Attack in the attack pools, Side_Light in the reels, Groin_1 with Groin_2, Getting_Up_2 after a leg fall | | anywhere | `control.gd` fights |
| Siege attacker / defender (`siege_ai.gd`) | SS_Walk behind shields → Sprint → Spear_Thrust / guard; defenders Bow_Draw → Bow_Shoot from the wall | | walls | siege scene |
| Muster / handover (`scenes.gd`) | ranks in step (Walk), Sword_Idle; sergeant Yelling; drill Spear_Thrust / SS_Slash_4 / Salute; handover Salute / Cheering / Battlecry | | square | those scenes |
| Court (`interior.gd` great hall) | Sword_Idle guards; courtiers chat (Idle_Talking, Arguing, Doubtful\*, Sarcastic Nod\*); Bow ×1 (one-off) when the lord enters | | great hall | inside the hall |
| Struck villager / witness (`villagers.struck`) | React_Front (or Hit_Chest U / Hit_Head U) → Running home → Terrified ×3-5 at the door → Looking_Around | | street → home | the player strikes someone; neighbours within reach flee too |
| Cottage folk (`interior.gd`) | Idle_Talking, Carrying, Sitting_Idle_Loop U at the table, Interact at the hearth (gap: stirring) | | cottage | inside a house |

## 3. The top-level selector (LimboAI)

One `BTPlayer` per townsperson, `update_mode = MANUAL`, ticked by `villagers.gd` on its existing stride
(every frame near the camera, 1 in 4 further out, nothing unseen). Every activity is its own `BehaviorTree`
resource, run through `BTSubtree`. That way a farmer's Sow tree is one file, reused by every farmer.

Custom tasks (a few lines of glue each; everything else is stock LimboAI 1.8.1):

- `PlayRun(pool, min=3, max=5)`: picks a clip from `pool` that isn't `last_clip`, plays it through
  `people.play` (loops) or `people.repeat` (one-offs), waits `n × length` using the length `motion.play`
  returns, then sets `last_clip`.
- `PlayOnce(clip)`: `people.once(..., hold=false)`, waits for its length.
- `GoTo(place_key)`: wraps today's `_at` / `_claim` / `_nav.path` / RVO, and finishes on arrival.
- `Breaker(pool)`: one clip from the pool, not `last_breaker`, for 1-2 cycles.
- `HasCompany(reach)`: today's `_company`.

Blackboard: `role, age, block, season, town_mood, mood{grief,fear,hunger,faith,anger,joy}, plan, danger_from,
last_activity, last_clip, last_breaker, place_key, post` (for posted scene folk).

```
BTPlayer (per person)
└─ BTDynamicSelector  "Life"         # re-checks the top branches every tick, so danger cuts in
   ├─ BTSequence "Dead"              BTCheckAgentProperty(dead) → BTWait(forever)
   ├─ BTSequence "Danger"            # struck, fleeing, a riot turning on them
   │   ├─ BTCheckVar danger_from != null
   │   ├─ PlayOnce React_Front | Hit_Chest | Hit_Head
   │   ├─ GoTo home  (gait Running, pace 2.4)
   │   └─ BTRepeat(3) PlayRun [Terrified, Looking_Around] 1..1  → BTSetVar danger_from = null
   ├─ BTSequence "Hurt"              BTCheckVar hurt → Subtree Wounded
   ├─ BTSequence "Posted"            # town_life / scenes put them at a post (builder, keeper, recruit, beggar…)
   │   ├─ BTCheckVar post != ""
   │   └─ BTSubtree  post_tree       # Raise the frame, Mind the stall, Sword drill …
   ├─ BTSequence "Plan"              # the bridge's day plan (Minds), not at night
   │   ├─ BTCheckVar plan != {} and block != night
   │   └─ PlanToActivity → BTSubtree  # _plan_move's word table, mapped to activities, not single clips
   ├─ BTSequence "TownMood"          # feast / riot / hunger, with today's odds
   │   ├─ BTCheckVar town_mood != "" and block in day
   │   └─ BTProbabilitySelector  Feast(.3/.6 eve) | Riot(.35 go / .65 watch) | Hunger(.35)
   ├─ BTSequence "Feeling"           # grief / fear / hunger / faith over threshold (today's _mood_idle)
   │   └─ BTProbabilitySelector  GrieveAlone | Comfort | WatchFromStep | Pray
   ├─ BTSequence "TimeBlock"         # night, dawn, meal, evening
   │   └─ BTDynamicSelector  Night(home or Night watch / Night door) | Dawn(Water carrier, Pray, Milk, chores)
   │                         | Meal(home or tavern) | Evening(Drink, Pray, Sing, children Skip)
   ├─ BTSequence "Work"              # work / work2, by role
   │   └─ BTProbabilitySelector  (weights per role, section 2)  e.g. farmer: Sow|Water|Weed|Harvest by season,
   │                             Yard chores .15
   └─ BTSequence "Fill"              # nothing else fits
       └─ BTRandomSelector  Stroll | Sit out | chat (if HasCompany) | Breaker(rest)
```

Inside every activity:

```
BTSequence "Sow"
├─ BTCheckVar last_activity != "Sow"          # never the same activity twice in a row
├─ BTSetVar  last_activity = "Sow"
├─ GoTo field
├─ BTRepeat (2..3 rounds)
│   └─ BTSequence
│       ├─ PlayRun [Planting] 3..5            # a working move only in runs of 3-5 cycles
│       ├─ BTProbabilitySelector              # then always broken up
│       │   ├─ Breaker rest  (w .5)
│       │   ├─ PlayRun [Drinking] 1..2  (w .2)
│       │   └─ chat if HasCompany  (w .3)
│       └─ GoTo next row spot (1 pace)
└─ BTTimeLimit wraps the whole thing (20-40 s), so a stop ends and the selector picks again
```

The no-repeat rules:

1. **Work moves only in runs of 3-5.** `PlayRun` is the only way a work clip plays, and a breaker or a step
   always follows. Two runs of the same clip never touch: `PlayRun` skips `last_clip`.
2. **Never the same activity twice in a row.** `BTCheckVar last_activity != X` heads every activity. If a
   probability selector draws the one just done, it fails and the selector tries the next child.
3. **Breakers don't repeat either** (`last_breaker`), and walking is exempt: Walk may repeat freely.
4. **Each person on their own clock.** Start each `BTPlayer` with a `BTRandomWait(0.5-6 s)` and keep today's
   per-person tempo and phase, so a crowd never changes moves in step (the `_job` rule).
5. **Talk takes two.** Any step from the SOCIAL list only runs when `HasCompany` succeeds. Otherwise the
   activity falls back to its solo breaker (today's `_solo` rule).

Notes for building it: keep villagers.gd's movement (nav map, RVO, `_claim`, gatherings, chatter.gd turns).
The tree only decides *what next*. Today's `_set_off` is in effect the "TimeBlock/Work" branches, and
`_follow` is "Plan". `town_life._job`'s LimboHSM gets replaced by the "Posted" branch running the same
activity trees, so builders, keepers and beggars at scenes behave like the villagers do.

## 4. Coverage

**Fits nowhere (11 of 236 clips, all in the UAL file):**

| Clip | Why not |
|---|---|
| Pistol_Aim_Down, Pistol_Aim_Neutral, Pistol_Aim_Up, Pistol_Idle_Loop, Pistol_Reload, Pistol_Shoot | wrong era: handguns |
| Spell_Simple_Shoot | magic bolt: wrong genre (the other three Spell clips are kept as a blessing, pending an eye check) |
| Swim_Fwd_Loop, Swim_Idle_Loop | townsfolk never enter water (`villagers.gd` keeps them on the shore) |
| Roll_RM, Sword_Attack_RM | root-motion copies of Roll / Sword_Attack; people.gd strips root motion, so they add nothing |

A_TPose is a rest pose, not a move, so it's left out of the count.

**Used by the activities above:**

| Library | Fit somewhere | Used today in play |
|---|---|---|
| mixamo/ (151) | 151 (100%) | 138 referenced (91%), about 43 in town life |
| hero/anims (40) | 40 (100%): 22 new moves plus 18 that repeat a Mixamo clip | 8 (Breathing Idle + 7 fidgets), close-up view only |
| UAL gltf (45, without the T-pose) | 34 (76%), about 11 of them likely copies of mixamo/ clips | 0 (not loaded) |
| **All 236** | **225 (95%)** | **146 (62%)**, most of that combat |

The 13 Mixamo clips nobody plays today now have homes: Axe_Combo_1/2 (heavy drill, axe kit),
GS_Slash_2/4 (heavy drill, greatsword kit), SS_Slash_2 and Sword_Attack (sword drill, sword kit),
Getting_Up_2 (weeding, tumbles, leg falls), Groin_1 (kick reel), Injured_Hurting (wounded, refugees),
Pushing (builder, keg, yard, rioters, carter), Ride_Relaxed (riding at a walk), Side_Light (brawl reel),
Sneak (hide-and-seek). Milking gets a real Milk activity instead of one plan keyword.

What it takes to reach that number, beyond the trees:

- Load `assets/hero/anims` and the UAL gltf into the crowd library next to `mixamo/` (`people.gd _init`).
  Both are proven files already on disk. Check the UAL retarget first.
- Add `Bow` and `Axe_Combo` to `motion.gd`'s ONCE list.
- Add the arm/leg blend for Carrying and Wheelbarrow, or carry trips won't read on the move.
- Props for a few steps: an axe at the chopping block, a cow for Milking, a pail, a torch for Idle_Torch_Loop,
  and kit weapons for heavy drill. `weapons.gd` already handles weapons.

## 5. Gaps: activities that want a clip we don't have

Nothing has been downloaded. The Mixamo names are what I'd search for. They aren't verified against the site,
so check the exact name before fetching.

| Activity / step | Missing move | Nearest we have | Mixamo search (free, check the exact name) |
|---|---|---|---|
| Builder, smith: hammering | swing a hammer at a nail or anvil | Interact; Fixing_Kneeling for low work | "Hammering"; failing that "Mining" (an overhead pick swing reads as a sledge) |
| Carry trips on the move | walking with a load in both arms | Carrying arms over Walk legs (the blend) | "Walking With Box" / "Carry Walk" (check) |
| Breaker: wipe brow / stretch | wipes sweat, stretches the back | Relieved Sigh\*, Weight_Shift | "Arm Stretching", "Wiping Sweat" (check) |
| Foreman, sergeant, keeper: pointing | points at something | Crouch And Point\* | "Pointing", "Pointing Forward" |
| Feast, drill review: clapping | claps | Cheering | "Clapping" |
| Yard chores: chopping wood | axe down onto a block | Axe_Down with an axe prop | "Chopping Wood" (check) |
| Farmer, gravedigger, builder footings: digging | spade or hoe work | Planting, Fixing_Kneeling | "Digging", "Shoveling" (check) |
| Tavern keeper, priest: sweeping | sweeps the floor | Interact | "Sweeping" (check) |
| Tavern keeper: pouring | pours from a jug | Watering (stand-in, reads well) | none needed |
| Cottage, feast: cooking | stirs a pot | Interact | "Stirring" (check) |
| Women at the well/river: washing | scrubs clothes, kneeling | Fixing_Kneeling | "Washing" / "Kneeling Scrubbing" (check) |
| Rioter, children: throwing | throws a stone | Battlecry (fist raised) | "Throw", "Throw Object" |
| Mourners: comfort | an arm round a shoulder | Idle_Talking + Slow Nod\* | "Consoling" (check; paired moves are rare on Mixamo) |
| Sleeping rough, drunk, refugee camp | lying down / sleeping | Sitting_Idle_Loop U, Defeated | "Sleeping Idle", "Laying Idle" (check) |
| Beggar, refugee, children: sitting on the ground | sits on the ground | Sitting_Idle_Loop U (that's on a seat), Kneeling | "Sitting Idle" (ground), "Sitting On Ground" (check) |
| Beggar: hand out | holds out a cupped hand | Praying, Kneeling | "Begging" (check) |
| Fisherman at a shore | casts and waits | none | "Fishing Cast", "Fishing Idle" (check) |
| Feast entertainer: a lute | plays an instrument | Dance, Happy_Gesture | "Playing Guitar" as a lute stand-in (check) |
| Muster: drummer | beats a drum | none | "Drumming" (check) |
| Stable, carter: tending a horse | brushes or leads a horse | Interact | none known; leave as Interact |
| Sitting and drinking | sits and drinks | Sitting_Idle_Loop U + Drinking (no blend) | "Sitting Drinking" (check) |
| Rioter: shove a man | two-handed shove | Pushing, Push_Loop U | "Shove" (check) |

If Mac wants a first fetch batch, I'd start with the four the most-seen activities need: Hammering (or Mining),
Pointing, Clapping and a sit-on-the-ground idle. Builders, foremen, revellers and beggars are on screen
most often.
