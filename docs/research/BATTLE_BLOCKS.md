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

## The pick

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
