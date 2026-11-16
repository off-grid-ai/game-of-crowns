# Battles: who already built this? (survey, 2026-11-16)

Asked by Mac after a day of hand-patching field battles: "isn't there some system or some engine that we can use or
some principle that we can use here?", "don't reinvent the wheel". Five projects were cloned to
`~/code/goc-kits/research/` and read (licence file, last commit, the code and docs named below). Nothing was run.

## What was read

| Project | Licence | Last commit | Engine | What it is | Fit |
| --- | --- | --- | --- | --- | --- |
| [Standard of Iron](https://github.com/djeada/Standard-of-Iron) | MIT | 2026-11-15 | C++20, Qt 6, own renderer | A formation battle game (Second Punic War). About 190,000 lines of game code; a simulation kernel kept apart from presentation; long design docs. | **The reference.** Same model as ours (a troop with stable soldier slots), with the fighting layer we lack. Cannot be dropped in (its own engine); its design and code can be ported with credit. |
| [GDQuest Godot Steering AI Framework](https://github.com/GDQuest/godot-steering-ai-framework) | MIT | 2024-09-13 | Godot 4.1, GDScript | Steering behaviours: arrive, seek, pursue, follow path, face, separation, cohesion, avoid collisions, blend, priority. 1,428 lines, no nodes needed. | **Usable as is** for how one body moves. Its neighbour search is a plain loop over a list, so it must be given short lists (a block and its neighbours), not the whole field. |
| [Open Combat Engine](https://github.com/wadlo/open-combat-engine) | MIT | 2024-03-16 | Godot 4.2, C# | Small 2D combat components (health, knockback, ability timers, target) and a swordsmen-and-archers demo. | No. It needs the .NET build of Godot, is 2D, and has no formations. |
| [Polemos](https://github.com/nihilocrat/polemos) | MIT | 2020-06-08 | Unity | A small Total War/Kohan-like prototype with squads and flank damage. | No. Unity, small, abandoned. |
| [Godot Open RTS](https://github.com/lampe-games/godot-open-rts) | MIT | 2025-01-07 | Godot 4 | An open RTS sample. | No. Single units, no formations or melee. |

Not cloned: 0 A.D. Its formations work as ours do (an invisible controller, each unit steering to an offset), and its
developers describe the two walls we hit: the controller's turns look unnatural, and its combat cannot keep a formation
together while it fights. Its code is GPL, so it is read for how it works and never copied: where a licence does not
allow copying, we take the idea and write our own (Mac, 2026-11-16).

## What Standard of Iron does that we do not

Its `docs/COMBAT_SYSTEM.md` and `docs/FORMATION_ARCHITECTURE.md` describe, as solved problems, most of what Mac
reported on 2026-11-16.

| What Mac saw | Their mechanism | Where |
| --- | --- | --- |
| Blocks swap targets, horses and archers turn after whoever is nearest | **Target commitment**: a chosen target is kept; "repeated proximity queries can cause units to bounce between equally plausible enemies every update" | `target_commitment_system.cpp` (124 lines) |
| Orders re-made every frame ("on the fly") | A chase order is only re-issued when the target moved, never because the attacker did | COMBAT_SYSTEM.md, "When a chase order is re-issued" |
| Eight boxes pressed face to face, only the first row fighting | **Formation overlap**: two squads are only "in contact" once the attacker has pushed deep into the target's block; contact is then worked out soldier slot against soldier slot | `formation_contact.cpp` `resolve_engagement_distance`, `accumulate_slot_contact` |
| The block turns as a rigid thing in a fight | **Melee lock**: the troop's own facing is frozen while it is locked, and "its soldiers turn individually towards the contact" | `combat_system/melee_lock.cpp` (526 lines) |
| A mob, or else nobody joining in | **Engagement slots**: at most 8 attackers on one target, each holding a slot on a ring round it for 2 seconds; the overflow is sent elsewhere | `engagement_slot_system.cpp` (187 lines) |
| Men and horses walking through rocks, houses, their own ranks | Each soldier's slot is pushed out of the real footprint of every prop; any two enemies that touch are locked, whatever their orders | FORMATION_ARCHITECTURE.md, "Soldiers and world props"; `lock_touching_enemies` |
| A formation called "formed" that is not | **Cohesion is measured**: how many soldiers actually stand in their slots; under 0.45 the group is "disrupted", and that raises the damage it takes | FORMATION_ARCHITECTURE.md, "Cohesion", "Formation phases" |
| A charge with no visible effect | Hit feedback (flinch, stagger, block, evade) is its own stage after damage; a mounted charge has its own processor | `hit_feedback_processor.cpp`, `mounted_charge_processor.cpp` |
| No catapults on the field | Siege engines and stone projectiles are part of the same combat pipeline | `siege_special_processor.cpp`, `stone_projectile.cpp` |

Its combat pipeline alone is about 15,700 lines, so "use it" means porting chosen mechanisms, not all of it.

## Second pass (same day): the first pick was wrong on the fight itself

Mac asked for more depth and a level of confidence. Standard of Iron's melee and movement code was then read line by
line (two readers), a wider search was run, the steering library was loaded and timed in our Godot 4.7, and a sixth
project the search found, FLANKS, was cloned and its soldier code read.

**Standard of Iron's melee is the model we already have.** The fight is per troop (one health per troop; soldiers alive
= a share of it); soldiers are presentation steered round a fixed slot. Blocks stop at first body touch (any two
enemies that touch are locked and stopped). A soldier leans at most 0.2 of a spacing toward his nearest enemy; rear
ranks lean and do not move up; holes left by the dead stay open while the fight lasts; the block never turns to a
flank; nothing gives ground in the melee code. Porting it would not cure "only the first row is fighting" or "eight
boxes pressed face to face". Its engagement slots are for whole troops, not soldiers.

**Standard of Iron's movement is the part worth taking.** Tested rules for what took most of 2026-11-16:
- a soldier's speed is scaled by how far his facing is off his way (he turns, then moves: no sliding);
- he chases his slot with the slot's own velocity fed forward, a capped catch-up, an acceleration limit, and a snap
  within 0.12 m (no jitter);
- in a turn each man starts after his own short delay (rear ranks later) and catches up along an arc, which hides the
  rigid wheel;
- a turn over 100 degrees is an about-face in place: the root flips and every man's offset is negated (no wheel-about);
- a group marches at its slowest member's pace, each troop sent to where its slot will be a second ahead; no slot swaps;
- cavalry charge on contact at speed and stay in the melee; riders (not the block) have a turning circle;
- only the troop is a navigation body, never the soldiers.
Its own tests name the invariants (no yaw travel on a straight march, no backtracking, nobody spun in a wheel, nobody
left walking on the spot), close to what `field_clash_probe` now checks.
It admits: troops swapping places walk through each other's blocks; holding a shape on the march works only on open
ground.

**FLANKS (github.com/ggand0/flanks; MIT or Apache-2.0; Rust and Bevy; first commit 2026-07, last 2026-11-15; one
author; 7 stars) simulates every soldier and is tuned against Medieval II: Total War.** `src/sim/soldier.rs` (3,067
lines) is the layer we lack, as named behaviours:
- each man has a home place in his regiment; in melee the regiment's frame is held where it stood at contact;
- a man with an enemy in reach fights at his weapon's length, stepping in and back;
- a man of a fighting regiment who sees no enemy joins "in his own time": a chance each half second when he sees an
  enemy or the comrade beside him going, and patience as the backstop, "so the line rolls up from the contact outward,
  a man at a time";
- a man blocked by a comrade waits or sidesteps toward an open lane;
- bodies that meet share their closing speed by weight, "so a shove travels through a press and a deep mass pushes a
  line": pushing and giving ground come out of the contact, they are not a rule on top;
- separation is a capped, mass-weighted pairwise push, not RVO avoidance.
Its one screenshot shows the look asked for: a ragged seam of individual duels, the dead on the ground, ranks behind
loosening toward the fight.

**The steering library is not needed.** It loads unchanged in Godot 4.7, but 828 men each arriving at a place and
keeping apart from about 90 neighbours cost 9.2 ms a frame (20.6 worst) in GDScript. Neither reference uses RVO or a
steering library for men in a press; the literature (Game AI Pro: Mars and Chanut, Sunshine-Hill) says avoidance of
that kind fights close formations and deadlocks when squeezed, which matches our jitter and our 100 ms frames.

## The pick, revised, with confidence

| Claim | Confidence | Why not higher |
| --- | --- | --- |
| Take Standard of Iron's movement rules for how a block and its men march and turn | High (about 85%) | Read, not seen running; they are specific and each matches a fault we measured |
| The fight needs to be worked out soldier by soldier at the contact; a per-block fight with posed men stays rigid | High (about 80%) | Both per-block projects (ours and Standard of Iron) show it; both per-soldier references (Medieval 2 as FLANKS reads it, Bannerlord) do not |
| Drop RVO and steering for men in a press; use a capped, mass-weighted pairwise push | Medium-high (about 75%) | Not yet tried in our game |
| FLANKS is the right source for that soldier layer | Medium (about 60%) | Four months old, one author, no users to speak of; one still seen, never seen moving; not run by us |
| GDScript can carry it for our 840 men at a steady frame rate | Unknown (about 50%) | Simpler steering already cost 9 ms; FLANKS is built for native speed |

## What would raise the two low ones

1. **See FLANKS run on this Mac** (Rust is installed): build it, film a battle, and let Mac judge the look. Half a day.
   It means building and running a stranger's code, so it waits for Mac's word.
2. **A one-day spike in a scratch project**: two regiments of 45 with FLANKS's join, close-in, sidestep and shared
   contact written in GDScript, timed at 840 men. If it holds a frame budget, port in GDScript; if not, the same loop
   goes into a native extension.

Only after both: replace the fight in `army_field.gd` (the loose-men press written on 2026-11-16) with the soldier
layer, and `mover.gd`'s hand-written block steering with Standard of Iron's rules.

## First pick (superseded above)


1. **Reference and source to port: Standard of Iron.** Keep our model (a regiment with stable soldier slots, one
   captain per host) and port, in this order, the mechanisms above: target commitment, the melee lock, formation
   overlap with slot-against-slot contact, engagement slots, measured cohesion. Each is a few hundred lines there.
   MIT: its licence text goes in our credits and each ported file names its source.
2. **How one body moves: GDQuest Steering AI Framework**, in place of the hand-written steering added to
   `mover.gd` on 2026-11-16 (the horse's arc, slowing in to a mark), with Godot's own avoidance kept for crowding.
3. **Nothing else found is worth integrating.**

## Not verified

- None of these was run. Standard of Iron's behaviour is taken from its docs and code, not seen in play.
- The steering framework targets Godot 4.1; it has not been loaded in our 4.7.
- How its plain GDScript neighbour loops perform with 840 men was not measured.
- Whether Standard of Iron's catapult behaviour suits a 900 AD field battle was not looked at.
