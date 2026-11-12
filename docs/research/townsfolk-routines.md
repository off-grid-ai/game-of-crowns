# Townsfolk routines: how shipped games make a square read as alive

Research, 12 Nov 2026. Ask: Mac, "the town's NPCs have no gradual smooth actions and no figured-out routine."
Scope: Kingsmere's square (target `docs/art/target/01-town.jpg`). No code here; this is the spec the builder
works from. Estimates are tagged *(est.)*; claims from player forums, not studios, are tagged *(player)*.

## The verdict in five lines

1. Our trees are a list of clips, not a chain of jobs on things: every handoff is `PickUp_Table`, nothing changes hands, the stallholder never answers the shopper.
2. Shipped games make every step an **object's offer** (The Sims' advertisements, Unreal/CryEngine smart-object slots): the object says where to stand, which way to face, and plays its own enter, loop and exit.
3. Smooth comes from **enter/loop/exit clips plus a turn before the walk and a slow-down before the stop**, not from longer crossfades.
4. At roof height a player reads a **pair** (buyer and seller facing across a counter, one hands, one takes) and a **thing that moves** (a bucket now full, a sack now on the stall). Single gestures don't read.
5. We already hold most clips we need; about a dozen are missing, nine of them already downloaded in `~/Downloads/Aldmere/mixamo` and never imported.

## 1. What the shipped games do

| Game | Pattern | What we copy |
|---|---|---|
| The Sims (Maxis) | Objects advertise what they give ("sleep here: +10 energy"); dumb people, smart objects; new objects need no new AI ([GMTK via Game Industry Library](https://gameindustrylibrary.com/documents/gmtk-the-genius-ai-behind-the-sims), [Forbus/Wright notes](https://users.cs.northwestern.edu/~forbus/c95-gd/lectures/The_Sims_Under_the_Hood_files/outline.htm)). Routing slots carry a facing and flags; pick-up/put-down has ONE slot per object, on purpose ([Sims dev on EA forum, via ModTheSims SLOT](https://db.modthesims.info/wiki.php?title=SLOT)). | The well, a stall, a street mouth each **advertise** callings and own their slots and clips. One exact hand-off spot per counter. |
| Unreal Smart Objects (Epic) | Slot has offset + facing + tags + behaviour; states Free, Claimed, Occupied, Released; owner change frees all slots and tells the agent ([UE docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview)). | Our `_slot` already claims; add **Occupied** (arrived), facing per slot, and the slot's behaviour (its clips). |
| CryEngine smart objects | Agent walks to an exact start helper so the clip lines up with the object; separate entrance/exit helpers ([CryEngine 5 docs](https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/25534850)). | Approach point is **one step in front** of the use point; the last step is the enter clip, not the walk. |
| Final Fantasy XV town "Ambient AI" (GDC 2018) | Three layers: decide, body, animation; conversation spots chosen from distance and facing of everyone in it; chairs etc. carry their own action and clip; busy market street vs quiet side streets on purpose ([Game Developer](https://gamedeveloper.com/programming/the-ai-systems-that-govern-i-final-fantasy-xv-i-s-believable-npcs)). | Talk spots computed as a circle; a hot square and calm lanes. |
| Assassin's Creed Unity (GDC 2015) | 40 full AIs + 120 high-res bodies carry 10,000 on screen; behaviour LOD by distance, crowd as groups, seamless swap low/high ([GDC Vault](https://www.gdcvault.com/play/1022141/Massive-Crowd-on-Assassin-s), [Game Watch write-up](https://game.watch.impress.co.jp/docs/news/20150307_691715.html)). Systemic crowd events (a fight, a preacher) pull bystanders into a ring ([Blondeau postmortem](https://www.gdcvault.com/play/1022211/Postmortem-Developing-Systemic-Crowd-Events)). | Full minds only near the camera; far people loop a cheap errand. Square events draw a ring. |
| Hitman Absolution / HITMAN (IOI) | 1,200-person crowds at 30 fps; crowd agent upgraded to a full NPC on demand; crowd animation time-sliced across frames ([GDC 2012](https://gdcvault.com/play/1015315/Crowds-in-Hitman), [Intel HITMAN 2 deck](https://www.intel.com/content/dam/develop/external/us/en/documents/06-create-a-scalable-and-destructible-world-in-hitman2-807276.pdf)). | `anim_lod.gd` already time-slices; add the upgrade/downgrade of minds. |
| Kingdom Come: Deliverance 1-2 (GDC) | ~2,400 NPCs, each on a daily routine that runs when the player is gone; routines bend to events ([GDC Vault](https://gdcvault.com/play/1035718/Supporting-Thousands-of-NPCs-in), [Wccftech interview](https://wccftech.com/kingdom-come-deliverance-2-dev-talks-about-dynamic-npc-routines-and-emergent-storytelling-for-side-quests/)). | Part of day picks the role's chain (`villagers.gd` already has dawn/work/meal/work2/evening/night). |
| RDR2 | Townsfolk keep set hours: off to work at 8, asleep at the saloon table at 1 am (observed in follow-a-NPC videos; [Dexerto](https://jamtest.dexerto.com/red-dead-redemption/what-happens-when-you-follow-a-red-dead-redemption-2-npc-for-an-entire-day-215958)) *(player)*. | Everyone has a place to be next; nobody idles in the open without a reason. |
| Manor Lords | Families with a trade set up a stall (about 1 per 5 families); buyers walk to the stall and carry it home ([Hooded Horse wiki](https://wiki.hoodedhorse.com/Manor_Lords/Special:MyLanguage/marketplace), [PC Gamer](https://www.pcgamer.com/games/city-builder/manor-lords-marketplace)); a patch fixed a wrong basket carry clip (0.7.965). | The stallholder is a **family member who brought the goods**; the carry clip matches the good. |
| Foundation | Strict loop of work, needs, free time; villagers buy at the market near home in free time ([Polymorph wiki](https://wiki.polymorph.games/fr/foundation/Needs), [dev news](https://www.polymorph.games/foundation/news/category/dev-news/)). | Shoppers come from the nearest houses at "meal" and "evening". |
| Anno 1800 | Physical goods back: distance on the street network matters ([Anno Union](https://anno-union.com/2018/02/)). | Goods visibly arrive at a stall before they're sold. |
| Stronghold (2001) | One worker carries one ingot mine to stockpile ([Altered Gamer guide](https://www.alteredgamer.com/stronghold/12755-pc-game-guide-the-industry-buildings-category)). | One trip, one visible load, one drop on a pile that grows. |
| For Honor motion matching (GDC 2016) | Starts, stops and turns picked from captured data, no hand-built transitions ([GDC Vault](https://www.gdcvault.com/play/1022985/Motion-Matching-and-The-Road)). | Too heavy for us; we copy its **result** with discrete start/stop/turn clips. |

Gaps: Banished, Farthest Frontier, Anno 117 have no public writing on ambient behaviour; forum notes only *(player)*.
RDR2 and AC slides are not public; their numbers above come from abstracts and press.

## 2. Smart objects for the square (from The Sims, Unreal, CryEngine)

Every place a villager acts is an object that offers:

| Field | Meaning | Example: a stall |
|---|---|---|
| `offers` | callings it serves and their weight | buy 1.0, browse 0.6, deliver 1.0 (porter) |
| `slots` | named spots, each with position, facing, kind | `keeper` (behind, faces out), `buy_1..3` (front, face in), `drop` (side, faces the pile) |
| `approach` | a point one step before the slot | 0.04 units out from `buy_n` *(est.)* |
| `clips` | enter, loop (pool), exit per slot kind | buy: enter `Weight_Shift`, loop `Idle_Talking`/`Pointing_Forward`/`Arguing`, exit `Nod_Yes` or `Shake_No` |
| `pair` | a slot that must be Occupied for this one to run its loop | `buy_n` loops only with `keeper` present |
| `result` | what changes when the exit plays | stall stock −1, buyer gets a held prop |
| `cooldown` | seconds the slot stays shut after release | 2-4 s *(est.; Conan Exiles uses the exit clip's length)* |

States per slot: Free → Claimed (walking to it) → Occupied (arrived, playing) → Released. If the object goes (stall razed, square cleared) all slots release and each agent is told, as Unreal does.
Queueing: when all `buy_n` are taken, a buyer takes a `wait` spot 0.1 units back *(est.)*, stands with `Weight_Shift`/`Looking_Around`, and steps up when one frees. Max one waiting per stall; otherwise the stall is skipped.

Objects on our square: **5 stalls, the well, 3 street mouths, the smithy's anvil, the cart's tail, the statue's steps, the tavern door.**

## 3. Motion polish rules

| Rule | Value | From |
|---|---|---|
| Turn before you walk | turn in place with `Left_Turn`/`Right_Turn` when the heading is >60° off; else turn while walking | For Honor result, CryEngine helper alignment |
| Turn rate on the move | keep `TURN_RATE` 300°/s, ease 6/s (have it) | motion.gd |
| Start | first 0.4 s ramp 0 → walk pace *(est.)*; stride follows real speed (have it, v2 blend space) | Godot BlendSpace1D |
| Arrive | slow from walk pace to 0 over the last 0.08 units *(est. ~0.6 m)*; then face the slot's facing over 0.3 s; then enter clip | Unreal/CryEngine slot entrance, generic arrive steering |
| Crossfade standing → standing | 0.35-0.45 s (have 0.45) | motion.gd |
| Crossfade into a once-clip (hand over, nod) | 0.2 s; out of it 0.3 s | |
| Low ↔ standing | through `Sit_To_Stand`/`Stand_To_Sit`/`Getting_Up`, never a fade (have the rule) | motion.gd |
| Foot planting | no fade between two clips whose feet differ by > a stride; drop to `Idle` for 0.3 s first *(est.)* | |
| Avoidance | RVO on (have it); stopped people are obstacles; conversation circles are one obstacle | Godot NavigationServer2D |
| Talkers | 2-4 in a circle: centre between them, radius 0.05 units (2 people) to 0.08 (4) *(est. ~0.4-0.65 m)*, each faces the centre, speaker turns to whoever spoke last | FFXV face-to-face spots; F-formation |
| Behaviour LOD | near: full tree. Mid: tree ticks every 0.5 s *(est.)*. Far (off screen or beyond 2 square radii): one cheap looping errand, no gestures | AC Unity, HITMAN |
| No repeats | same clip never twice running per person; no two neighbours start a clip in the same 0.5 s (have the rule) | goc-ux 9 |

## 4. What the camera must see to read "she is buying bread"

At roof height a figure is ~40-60 px tall *(est.)*. A gesture alone is noise. What reads:

1. **Two bodies facing across a counter** (keeper and buyer), the only pair facing that way. Distance 0.06-0.08 units *(est.)*.
2. **A hand-over that moves a thing**: the keeper bends to the goods (`PickUp_Table`), turns, holds out; the buyer takes (`Interact` short or `PickUp_Table`), and walks off **carrying** (`Carrying` arms over the walk).
3. **The stall's pile drops by one; a prop (loaf, basket, bucket, sack) is in her hands.** Without a prop the carry pose reads as a hug.
4. **She leaves in a straight line toward a house or street**, not to the next stall.
5. Head shake vs nod before the hand-over (the deal), turned toward the keeper, upper body exaggerated (people.json `readable`).

Same test for the well (rope pulled, bucket now in hand, she walks off heavy) and the porter (sack on shoulder in, stall pile grows, empty-armed out).

## 5. The square's routines (spec)

Square of 28: counts per role, then each routine as a chain. Each step: **place → clips (enter / loop / exit) → dwell → carries after**.

| Role | Count | Driven by | Part of day |
|---|---|---|---|
| Stallholder | 5 (one per stall) | posted, mind `trade` | dawn: sets out; work, meal, work2: sells; evening: packs |
| Shopper | 9 | villager, `market` | work, meal, work2 (peak at meal) |
| Water carrier | 3 | villager, `water` | dawn, meal, evening |
| Porter | 3 | villager, `porter` | dawn, work |
| Carter | 1 + cart | `carter` | work |
| Smith (+ bellows boy) | 2 | posted, `smith`/`bellows` | work, work2 |
| Gossips | 2 knots of 2-3 (5) | villager `gossip` / Talk | meal, evening |
| Children | 2 pairs (4)* | `child` | work2, evening |
| Guards | 1 pair (2)* | `guard` beat | always |

*Children and guards are on top of the 28, as today's posted crowd is. Shoppers/water/porters keep today's 5:2:2 callings, rounded.

### Stallholder (copies Manor Lords' stall family + The Sims' paired object)
| Step | Place | Clips enter / loop / exit | Dwell | After |
|---|---|---|---|---|
| Open | stall `keeper` | `Box_Idle` → `PickUp_Table` ×2 (setting out) | 8-15 s | pile shows |
| Wait | `keeper` | `Weight_Shift`, `Looking_Around`, `Arms_Crossed`†, `Wiping_Sweat` (one each, no repeat) | 4-10 s | |
| Call out (no buyer 20 s+) | `keeper` | `Waving` or `Yelling` once | 2-3 s | |
| Serve (buyer Occupied) | turn to buyer | enter `Weight_Shift`; loop `Talking`/`Idle_Talking`; exit `PickUp_Table` → `Give`† | 6-12 s | stock −1 |
| Restock (pile low) | `drop` slot | `PickUp_Table` from porter's sack | 3 s | stock +n |
| Close (evening) | `keeper` → home | `PickUp_Table` ×2, walk `Carrying` | | stall bare |

### Shopper (Foundation free-time buying + The Sims advertisement)
1. Leave house at meal/work → walk to a street mouth → square.
2. **Browse** (60%): approach stall A `buy_n`, enter `Looking_Around`, loop `Thinking`/`Doubtful` 3-6 s, exit `Shake_No` → next stall. Max 2 browses.
3. **Buy**: claim `buy_n` at stall B (needs `keeper` Occupied). Enter `Weight_Shift`; loop `Pointing_Forward` → `Idle_Talking`/`Arguing` 4-8 s (keeper loops `Talking` facing her); exit `Nod_Yes` (deal, 80%) or `Shake_No` then leave (20%).
4. **Take**: keeper `Give`†, shopper `Take`† (or `PickUp_Table` cut short) — 1.2 s. Prop (loaf/basket/cloth by stall's goods) attaches to her hands.
5. Optional: meets a neighbour (circle of 2, `Talk`, 6-12 s) still holding the prop (`Holding_Idle`).
6. Walks home `Carrying` the prop; at the door `PickUp_Table`, prop gone. Off the square = mind drops to far LOD.

### Water carrier (Stronghold one-trip-one-load)
1. Walk to the well with an empty bucket prop (held at side: `Walk`).
2. Claim a `well_rim` slot (5). Enter: `Stand` face the rim 0.3 s. Loop: `Pull_Rope`† (or `Pushing` as now, as a fallback) 2-3 cycles, 4-6 s. Exit: `PickUp_Table`, bucket now full (swap prop).
3. 40%: chats at the rim while holding (`Holding_Idle` + `Talking`), 5-10 s, with whoever else is Occupied there.
4. Walks home heavy (`Carrying`, pace ×0.85 *(est.)*), or to the tavern door/a stall (sells water), `PickUp_Table`.

### Porter (Anno physical goods)
1. In from a street mouth or the cart's tail: `PickUp_Table` (sack) → walk `Carry_Shoulder`† or `Box_Walk`.
2. Stall `drop` slot: exit `Box_Idle` → `PickUp_Table` (set down). Stall pile +n, keeper turns and `Nodding`.
3. `Wiping_Sweat` or `Arm_Stretching` 2-3 s, out empty-armed to the next load. Max 3 loads, then a rest at the well (`Drinking`).

### Carter
Cart enters on its street, stops at the square edge 6-12 s (have it); carter walks to the tail, `Push_Heavy`, hands sacks to porters (porter claims the cart's `tail` slot), drives off.

### Smith (+ bellows)
`Hammer_Swing` runs of 3-5, breaker `Wiping_Sweat`/`Arm_Stretching`, `Box_Idle` to the rack (`Stock` +1), sells one blade to a buyer at the smithy's counter (pair, as a stall). Bellows: `Pushing` runs, breaker `Looking_Around`.

### Gossips (FFXV conversation spots)
Circle of 2-3 at the statue steps or a tree's shade. Speaker loops `Talking`/`Talking_Hands`, listeners `Nodding`/`Weight_Shift`/`Laughing`, speaker passes every 4-8 s (speaker turns, listeners turn heads). Ends with `Waving`, each off to their next place.

### Children
Chase (have it) → stop at the well, `Crouch_Idle_Loop` peering, → pester a stall (`Pointing_Forward`; keeper `Shake_No` or `Dismiss`) → run off.

### Guards
Beat mouth → well → mouth (have it). At each stop `Looking_Around` 3-5 s. One in five stops: talk with a stallholder (pair, 5 s, `Salute` to leave).

## 6. Transition rules

1. A chain always ends at a **place off the square** (house, street, tavern) or at **the next object** — never in the open with nothing to do.
2. Idle in the open is only allowed as a `wait` slot (queue) or a talk circle.
3. Before any walk: face the heading (turn clip if >60°), then start. Before any slot: slow, face, enter clip.
4. A loop never runs without its pair (buyer without keeper waits or leaves).
5. Every exit leaves a **result**: stock moves, a prop changes, a pile grows.
6. Interrupts (news, danger) release the slot first, then React (have it).
7. Part of day reweights callings; never teleports people. Evening: stalls close and the square empties to ~10 *(est.)*.

## 7. Clips: have, downloaded but not imported, lack

Have in game (`realm/assets/anims/mixamo`, `realm/assets/hero/anims`, Quaternius UAL1 in `AnimationLibrary_Godot_Standard.gltf`):
`Walk`, `Running`, `Carrying`, `Box_Walk`, `Wheelbarrow`, `Push_Heavy`, `Pushing`, `PickUp_Table`, `Interact`, `Idle`, `Standing_Idle(_2)`, `Weight_Shift`, `Looking_Around`, `Bored`, `Thinking`, `Doubtful`, `Talking(_2)`, `Talking_Hands`, `Idle_Talking`, `Arguing`, `Pointing_Forward`, `Pointing_Arm_Bent`, `Nodding`, `Nod_Yes`, `Shake_No`, `Dismiss`, `Pleased`, `Laughing`, `Waving`, `Yelling`, `Wiping_Sweat`, `Arm_Stretching`, `Drinking`, `Hammer_Swing`, `Salute`, `Whispering`, `Telling_Secret`, `Sitting_*`, `Sitting_Enter/Exit` (UAL), `Crouch_Idle_Loop` (UAL), `Getting_Up`.

| Need | Status | Source (licence) |
|---|---|---|
| `Left_Turn`, `Right_Turn` (turn in place) | **downloaded, not imported** (`~/Downloads/Aldmere/mixamo/Left Turn.fbx`, `Right Turn.fbx`) | Mixamo (royalty-free in games; no redistribution of raw files) |
| `Stand_To_Sit`, `Sit_To_Stand` | **downloaded, not imported** | Mixamo |
| `Box_Idle` (standing with a load) | **downloaded** (`Farming Pack/box idle.fbx`); code asks for it already (`CARRIES`) | Mixamo |
| `Holding_Idle` | **downloaded** (`Farming Pack/holding idle.fbx`) | Mixamo |
| `Wheelbarrow_Dump`, `Wheelbarrow_Idle` | **downloaded** | Mixamo |
| `Pull_Plant` (stand-in for hauling a well rope) | **downloaded** | Mixamo |
| `Quick_Formal_Bow`, `Taunt`, `Annoyed_Head_Shake`, `Thoughtful_Head_Shake`, `Lengthy_Head_Nod` | **downloaded** | Mixamo |
| `Arms_Crossed` / leaning on a counter | lack | Mixamo "Leaning", "Standing W/ Arms Crossed" |
| `Give` / `Take` (hand an object over) | lack | Mixamo "Taking Item", "Giving Item"/"Handing Over" (search names); UAL2 interact set *(check viewer)* |
| `Pull_Rope` / draw from well | lack | Mixamo "Pulling Rope" / "Pulling"; fallback `Pull_Plant` |
| `Carry_Shoulder` (sack on shoulder walk) | lack (we fake with Walk + prop, crowd.json `shoulder`) | Mixamo "Carrying"/"Walking With Shopping Bag"; UAL2 farming set |
| `Start_Walking`, `Walk_To_Stop` | lack | Mixamo "Start Walking", "Stop Walking" |
| `Sweeping` (stallholder, evening) | lack | Mixamo "Sweeping"; KayKit Tool set ("generic working") — own rig, retarget needed |
| Bucket/basket carry walk | lack | Quaternius **UAL2** (CC0, farming/fishing sets; free Standard is ~70%; [pack](https://quaternius.com/packs/universalanimationlibrary2.html)) |

Sources ranked: **Mixamo first** (same retarget path as our 140 crowd clips, [licence FAQ](https://community.adobe.com/questions-696/mixamo-faq-licensing-royalties-ownership-eula-and-tos-589400)); **Quaternius UAL2** second (CC0, same Godot humanoid retarget as UAL1 already in `people.gd`); **KayKit Character Animations** last (CC0, 150+ clips, [itch](https://kaylousberg.itch.io/kaykit-character-animations), but Rig_Medium is blocky and needs its own retarget map).

Props needed in hand (not clips): loaf/basket, bucket (empty/full), sack, crate, cloth bolt. `people.gd` already attaches a tool per move (`sync_held`); goods use the same seam.

## 8. Where we stand today (from the code)

- `npc_mind.gd` square trees (`market`, `water`, `porter`) chain go → clip run → `PickUp_Table` → go. Right shape, but: no turn before walking, no enter/exit per object, no pair with the stallholder, no prop change, `Pushing` stands in for drawing water.
- Stallholders (`town_life.gd` ~716) are posted with mind `trade`; they never react to a buyer.
- `villagers.gd _slot` claims slots (stall front ×3, well rim ×5, street mouth ×2): this is the Unreal Claimed state; Occupied, facing per slot, cooldown and queue are missing.
- `motion.gd` has the blend-space legs, 300°/s turning, 0.45 s standing fades and the low-posture rule. Missing: turn-in-place clips, start/stop, arrive slow-down.

## Sources

- GMTK, The Genius AI Behind The Sims: https://gameindustrylibrary.com/documents/gmtk-the-genius-ai-behind-the-sims
- Forbus & Wright, The Sims under the hood: https://users.cs.northwestern.edu/~forbus/c95-gd/lectures/The_Sims_Under_the_Hood_files/outline.htm
- PC Gamer, Wright on Sims autonomy: https://www.pcgamer.com/games/the-sims/will-wright-says-the-original-sims-ai-was-actually-too-good-almost-anything-the-player-did-was-worse-than-the-sims-running-on-autopilot
- ModTheSims SLOT reference: https://db.modthesims.info/wiki.php?title=SLOT
- Unreal Smart Objects overview: https://dev.epicgames.com/documentation/en-us/unreal-engine/smart-objects-in-unreal-engine---overview
- CryEngine 5 Smart Objects: https://www.cryengine.com/docs/static/engines/cryengine-5/categories/23756816/pages/25534850
- FFXV believable NPCs (GDC 2018): https://gamedeveloper.com/programming/the-ai-systems-that-govern-i-final-fantasy-xv-i-s-believable-npcs
- AC Unity AI Recycling (GDC 2015): https://www.gdcvault.com/play/1022141/Massive-Crowd-on-Assassin-s
- AC Unity Systemic Crowd Events (GDC 2015): https://www.gdcvault.com/play/1022211/Postmortem-Developing-Systemic-Crowd-Events
- Game Watch on AC Unity crowds: https://game.watch.impress.co.jp/docs/news/20150307_691715.html
- Crowds in Hitman (GDC 2012): https://gdcvault.com/play/1015315/Crowds-in-Hitman
- Intel, HITMAN 2 scalable world: https://www.intel.com/content/dam/develop/external/us/en/documents/06-create-a-scalable-and-destructible-world-in-hitman2-807276.pdf
- KCD, Supporting Thousands of NPCs (GDC): https://gdcvault.com/play/1035718/Supporting-Thousands-of-NPCs-in
- KCD2 routines interview: https://wccftech.com/kingdom-come-deliverance-2-dev-talks-about-dynamic-npc-routines-and-emergent-storytelling-for-side-quests/
- RDR2 NPC day: https://jamtest.dexerto.com/red-dead-redemption/what-happens-when-you-follow-a-red-dead-redemption-2-npc-for-an-entire-day-215958
- Manor Lords marketplace wiki: https://wiki.hoodedhorse.com/Manor_Lords/Special:MyLanguage/marketplace
- PC Gamer, Manor Lords marketplace: https://www.pcgamer.com/games/city-builder/manor-lords-marketplace
- Foundation needs wiki: https://wiki.polymorph.games/fr/foundation/Needs
- Anno 1800 logistics (Anno Union): https://anno-union.com/2018/02/
- Stronghold industry guide: https://www.alteredgamer.com/stronghold/12755-pc-game-guide-the-industry-buildings-category
- Motion Matching, For Honor (GDC 2016): https://www.gdcvault.com/play/1022985/Motion-Matching-and-The-Road
- Godot AnimationTree: https://docs.godotengine.org/en/4.4/tutorials/animation/animation_tree.html
- Quaternius UAL2: https://quaternius.com/packs/universalanimationlibrary2.html
- KayKit Character Animations: https://kaylousberg.itch.io/kaykit-character-animations
- Mixamo licensing FAQ (Adobe community): https://community.adobe.com/questions-696/mixamo-faq-licensing-royalties-ownership-eula-and-tos-589400
