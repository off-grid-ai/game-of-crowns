# Motion from first principles (Builder 1, 2026-11-11)

The judge's question, at Mac's ask: are four gate failures one root, and who already solved it?

## 1. The goal

**A player at street level believes Kingsmere is alive.** The motion probe is a proxy for that, nothing more.

- We had started bending the proxy: clips taken out of the skate check (`IN_PLACE`), SS_Attack_3 added today.
- **Ruled here:** no clip leaves a check without a frame strip showing the feet really hold. SS_Attack_3
  skids 66% of planted frames *with the body held still* (NPC perf, `clip_skate_probe.gd`): a player sees
  that skid. It stays in the check. Fix it by not using that clip in a crowd, not by not looking.
- Today's `IN_PLACE` list gets the same test: each entry needs a strip, or it goes back in.

## 2. One root? Checked against the code

Three deciders touch one body: **position** (`villagers.gd` `_step`: route x pace x RVO velocity),
**clip** (`motion.gd`: a hand-built AnimationTree, legs driven by measured pace, `STRIDE` table) and
**prop** (`weapons.gd` `CLIP_TOOLS`, keyed by the clip on screen). Each symptom against that:

| Symptom | Hypothesis | Verdict from the code |
|---|---|---|
| Skate (Walk 19%, Carrying 30%, Idle 15%) | mover speed ≠ clip stride | **Confirmed, and one more cause.** The legs chase the mover's pace (`track()` eases `_pace` 20/s, sets the blend position, scales `speed`): any change RVO makes to velocity reaches the feet a few frames late, so they slip. Second cause: **turning on the spot** (`_face()`, `TURN_RATE` 300°/s) rotates the body with no turning steps, so planted feet pivot. That's why standing clips (Idle, Standing_Idle_2, Spear_Thrust) skate at all. |
| Empty hands (Carrying 24-28 frames) | prop follows the clip, not the person's state | **Confirmed.** `CLIP_TOOLS` is keyed by clip; `held_clip()` must guess which clip the state machine is *about* to show. Every edge in the machine (travel lands a frame late, blend over walking legs, a stop) is a frame where the guess and the body disagree. NPC perf's `_to` fix closed one edge; 24 frames remain. The person *is carrying a basket* for the whole errand, whatever the legs do. |
| Pops (all "after Interact") | a clip switch with no real transition | **Partly.** There *is* a real transition: Godot's AnimationNodeStateMachine with a 0.2-0.45 s crossfade. What's missing is **posture**: Interact is on one knee (hips 0.32-0.42 vs 0.95), and a crossfade from kneeling to standing lifts the hips in 0.45 s. The fix in the tree (Getting_Up first, `GetUp.GROUND`) is a hand-kept list of which clips are low. |
| Children (21% on the tree, 27-56% on HEAD) | chasing a position, not moving as a group | **Confirmed.** `_follow_parents` re-routes the child to the parent's *current* position when it strays; RVO then holds the child still to avoid others (Townsfolk measured safe velocity ~0.01 while 3-6 m behind). `_walk_beside` copies the parent's route once at set-off, an offset frozen at departure. Neither is the parent leading. |

**One root:** the body is three loosely synced opinions. Position, clip and prop each read the others a
frame or more late, and each gap shows as a symptom. Posture (standing, kneeling, sitting) isn't owned
by anyone.

## 3. Who already solved it

| Problem | Proven block | Maturity / Godot 4.7 fit | Use? |
|---|---|---|---|
| Feet that can't slide | **Root motion**: the clip moves the body; the mover only steers (`AnimationMixer.root_motion_track`, `get_root_motion_position()`) | Built in, mature. **Blocker:** all our Mixamo clips are *In Place*, so there's no root motion to read. We'd need every locomotion clip again with root motion (Mixamo, free). It also fights RVO and anim_lod's frame skipping (the reason animation-pipeline.md §1 chose in-place). | **No**, not for crowds. |
| Feet that can't slide, mover owns position | **Stride warping + foot locking** (UE5 Animation Warping; Godot: `TwoBoneIK3D` foot lock, built in since 4.6) | IK built in and mature; foot locking on top of it is a pattern (~60 lines of glue), not a node | **Yes, near the camera only** (LOD, as planned in §2 of the pipeline) |
| Turning on the spot | **Turn-in-place clips** (Mixamo "Left Turn 90" / "Right Turn 90", free), played by the state machine when the yaw error passes ~45° | Standard in every shipped third-person game; clips free | **Yes.** It removes the standing-clip skate at its cause |
| Prop bound to state | **BoneAttachment3D shown by state** (the person's `carrying` fact on the blackboard, not the clip) | Already ours (`weapons.gd`); only the key changes, from clip to activity | **Yes**: smallest change, biggest win |
| Posture changes | **Posture graph** (The Sims' posture system; Unreal state machines with entry/exit states): every clip tagged stand/kneel/sit/lie; the machine moves between postures only through their transition clips | AnimationNodeStateMachine already supports it (states plus transitions with `advance_condition`); our clips are already there (Getting_Up, Kneeling, Sitting_*) | **Yes**: replaces the hand-kept GROUND list with one tag per clip, in one table |
| A child with a parent | **Offset pursuit / leader following** (Reynolds, "Steering Behaviors", 1999): the follower steers to a slot fixed in the leader's frame, every frame | The textbook answer, decades old. Godot ports of GDQuest's Steering AI Framework exist for Godot 3; a Godot 4 port isn't verified. The behaviour itself is ~30 lines on the RVO agent we have. LimboAI has no group-steering task. | **Yes**: the slot comes from the parent's transform each frame; the child's agent gets top priority so RVO doesn't hold it |

## 4. What it costs

| Change | Our glue: removed / added (est.) | Risk to what passes (overlaps, glances, greetings, station, no turn snaps) | Behind |
|---|---|---|---|
| Prop by state | -40 (`held_clip`, `_to`, `held_state`, the clip-keyed sync) / +25 | Low. Hands only. | `--motion=v3` |
| Posture tags | -15 (GROUND, rise_first) / +30 (one tag table, transitions) | Low-medium: pops may move to new spots; the probe sees them | `--motion=v3` |
| Turn-in-place clips | +40, 2-4 free clips | Medium: turn snaps must stay 0; turns may get slower, which affects greetings and glances | `--motion=v3` |
| Children by offset pursuit | -60 (`_walk_beside`, catch_up, `_for_the_child` re-routing) / +35 | Medium: overlaps (a child slot near others); RVO priority shifts | `--motion=v3` |
| Foot lock near the camera | +60 | Medium: IK cost; only within street-level range | `--motion=v3`, near LOD |
| Root motion | n/a | High | not proposed |

**Net:** about -115 lines of our glue out, about +190 in, but the new lines are configuration of named
blocks (state machine postures, BoneAttachment by state, Reynolds steering, IK), not hand-tuned guesses.

**Staged path:** `--motion=v3` on top of v2, one change at a time in this order: prop by state, posture
tags, children, turn-in-place, foot lock. Each stage goes through the bundled gate and a 3-6 s strip of
the symptom; v2 stays the default until v3 equals or beats it on every line. Nothing working is touched.

## What I'll do now

- Hold the SS_Attack_3 exclusion (not committed).
- Commit from today's bundled gate only what passes and doesn't bend the probe.
- Start v3 stage 1 (prop by state) once the judge agrees.
