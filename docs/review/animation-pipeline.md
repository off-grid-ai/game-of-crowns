# Animation pipeline: why the townsfolk look clumsy, and the blocks that fix it

Discovery, 2026-11-10, after Mac's playtest. Read-only: no game code was changed. Web facts and links are in
the side note `animation-web-research.md` (same session family) and are repeated where they decide something.

## The recommendation (one screen)

**The supervisor's diagnosis is half right.** We already have the right skeleton of a pipeline: every person
has one Godot `AnimationTree` state machine (`realm/scripts/motion.gd:1-21`) with a speed-driven
`BlendSpace1D` for the legs (`motion.gd:79-90`, `:200`), a crossfade on every transition (`:104-120`), a
bone-filtered carry layer (`:91-102`), BoneAttachment3D weapons (`weapons.gd:3`, `:110`) and distance LOD
(`anim_lod.gd`). What makes it look clumsy is **a dozen pieces of hand-written glue around it** that bypass
or mis-feed it. Fix the glue with Godot's own settings and nodes; don't add a second system.

**Chosen blocks (all built into Godot 4.7, MIT; nothing to buy, one add-on to trial later):**

| Problem Mac saw | Block | Why this one |
|---|---|---|
| Glide while standing, feet out of step | `AnimationNodeBlendSpace1D.sync_mode = CYCLIC_MUTABLE` (new in 4.7) + time scale = real pace / clip pace, pace measured in the person's own scale | Godot's built-in stride matching; we already have the blend space, it is just unsynced and fed the wrong pace |
| Hand through body | Import-time retarget on **one** setting for every body and clip: `SkeletonProfileHumanoid` + Rest Fixer (`Overwrite Axis`, `Fix Silhouette`, `Normalize Position Tracks`); stop scaling the chest bones | Today only 3 of 20 bodies and 0 clip files use Fix Silhouette; `_shape()` widens chests 8-13% under Y Bot arm swings |
| Drinks with no cup | `BoneAttachment3D` (what `weapons.gd` already uses), driven by a clip -> prop data row | One module already does this for arms; extend it, don't write a second |
| Moves snap | Facing turned at a turn rate in one mover (not `rotation.y = atan2(...)` in 9 places); `LimitAngularVelocityModifier3D` only if needed | The snaps are mostly body turns, not clip changes |
| Lumps, two people in one spot | Every ground move goes through the walkers' RVO (`NavigationServer2D`), including the mind's small steps, which today are tweens that ignore everyone | One mover, one avoidance |
| Feet on slopes / steps | `TwoBoneIK3D` (Godot 4.6+) + terrain height, near camera only. **Later**, after the above | No maintained foot-IK add-on exists; the built-in node is the block |
| Camera jumps | Keep our rig (Phantom Camera was backed out twice); remove its 4 instant jumps and ease the lens frame-rate-independently | The lens never collides with people or props (it only sees building prisms); the jumps are our own snaps |
| 300 people | Keep per-person AnimationTree on a manual tick near the camera; measure; only if over budget, the antzGames VAT plugin (MIT, 4.5+, ~131 stars) for the far ring | Don't pay for VAT until the perf probe says so |

**Target architecture.**
- **One skeleton:** `GeneralSkeleton` (`SkeletonProfileHumanoid`), every body and every clip imported with the same Rest Fixer settings. One crowd body family (the Mixamo-rigged one, which is what the 172 Y Bot clips were authored on).
- **One decider for "which move now":** the LimboAI tree (`npc_mind.gd`) for every townsperson (today `LIMBO_TOWNS` is empty, `town_life.gd:37`, so the playtest ran on villagers.gd's fallback rules). The tree sets an activity on the person; `motion.gd` is the only thing that picks states, crossfades and props.
- **One mover:** position and facing change in one place per person (villagers.gd's walker loop), with RVO for everyone on the move and avoidance off (or lowest priority, held still) for people standing.
- **One motion layer** (`motion.gd`): legs from real pace with stride sync; activity states; props attached by activity; IK feet last, near only.
- **LOD:** `anim_lod.gd` stays the one ticker (villagers.gd's second culler, flagged in `principles-audit.md:135`, is already gone).
- **Camera:** our rig, with the four snaps removed and one exponential ease on the lens.

**Migration order, behind a switch (one town first).** A switch `MOTION_V2` in `motion.gd` read per town
like `town_life.minds_on()` (`--motion=<town id>` for one run). Each step lands with its probe passing.

| # | Step | Owner | Files |
|---|---|---|---|
| 0 | **Motion probe first** (section 8), on the private bridge, headless. It must FAIL on today's code for the glide, the empty-handed drink, the turn snap and the camera jump | NPC builder (probe), Builder 2 (camera half) | new `realm/scripts/tools/motion_probe.gd` |
| 1 | Re-import every body and clip with one Rest Fixer setting; drop chest girth scaling | NPC builder | `.import` files, `people.gd:435-448` |
| 2 | Locomotion: blend-space sync, pace in own scale, time scale below walk pace, standing loops give way to the legs on any real motion | NPC builder | `motion.gd` |
| 3 | One mover: the mind's `Step` walks through villagers' RVO walker, no tween; no backward moonwalk; facing at a turn rate | NPC builder | `npc_mind.gd:90-137`, `villagers.gd:465-561` |
| 4 | Props by activity: `weapons.gd` becomes the one hand-held module (tools added as data) | NPC builder | `weapons.gd`, `motion.gd` |
| 5 | Camera: the four snaps out, one eased lens | Builder 2 | `camera_rig.gd` |
| 6 | Minds on everywhere (`LIMBO_ALL`), then villagers' fallback clip rules deleted | NPC builder | `town_life.gd:37,53`, `villagers.gd` |
| 7 | Measure 300 people with `GOC_PERF_PROBE`; VAT far ring only if over budget | NPC builder | `anim_lod.gd` |
| 8 | Foot IK near the camera (TwoBoneIK3D) | NPC builder | `motion.gd` |

Steps 1-4 on one town (the capital) behind the switch; film 3-6 s clips of it; then all towns; then delete
the glue listed at the end.

---

## 1. Locomotion: feet that match the ground

**What we have.** `motion.gd`'s `rest` state is a `BlendSpace1D` from stance (0) through `Walk`
(`WALK_PACE` 0.17) to `Running` (0.45) (`motion.gd:79-90`), fed every tick by the person's real ground speed,
eased (`:192-200`). Clips are made in-place at load (`people.gd:150-167`). That's the standard Godot recipe.

**Why they still glide (each with evidence):**
1. **The mind's steps are tweens.** `npc_mind.gd:90-120` (`Step`): plays `Walk`, then
   `create_tween().tween_property(agent, "position", _to, _left)` (`:120`). A linear tween: full speed from
   frame one, no acceleration, so the eased pace (`motion.gd:198`) lags and the legs blend in late and out late.
2. **Backward steps moonwalk.** `Step` with `back > 0` moves the body backwards (`npc_mind.gd:98-100`) while
   playing the forward `Walk` (`:118`). We own `Walking Backwards` (Mixamo Evasion pack, in `~/Downloads/Aldmere/mixamo`,
   asset-audit.md:172) and never use it.
3. **Pace is not measured in the person's own size.** `person.scale` is `height * k * S` (`people.gd:413`):
   children 0.72, elders 0.96, Mixamo bodies by `_height()`. `WALK_PACE` is one constant (`motion.gd:39`), so a
   child walking at 0.17 covers ground with an adult's legs at a child's size: ~30% slide.
4. **The blend space is not synced.** `_feet` never sets sync (`motion.gd:82-90`), so between walk and run the
   two clips drift out of phase. Godot 4.7 replaced the `sync` bool with `sync_mode`; `CYCLIC_MUTABLE`
   time-scales the blended clips to one cycle from their weights: built-in stride matching
   ([BlendSpace1D docs](https://docs.godotengine.org/en/latest/classes/class_animationnodeblendspace1d.html),
   [upgrading to 4.7](https://docs.godotengine.org/en/latest/tutorials/migrating/upgrading_to_godot_4.7.html)).
5. **Below walking pace the legs play at full cadence, half blended.** `speed = maxf(1.0, _pace / RUN_PACE)`
   (`motion.gd:220`): never slower than 1. At half walking pace the tree shows 50% stance + 50% walk at full
   cadence: short, quick, sliding steps. Standard fix: under walk pace, keep walk weight 1 once moving and time
   scale by `pace / WALK_PACE` (with a floor); blend to stance only through the start/stop.
6. **Standing moves ignore small motion.** A looping work or talk move only gives way to the legs after the
   pace passes `MOVING` (0.085, half walking pace) for 0.3 s (`motion.gd:204-210`). Any push or step slower than
   that slides a talking or working body across the ground with no legs. That is Mac's "glide while standing".
7. **Turns snap** (section 6).

**Is RVO pushing standing people?** Not in villagers.gd: a standing walker's agent gets velocity zero and
priority 1 (`villagers.gd:465-468`), and its position is never moved by the avoidance's answer. The sideways
glide comes from 1, 2, 5 and 6 above, from units' settle teleport (`units.gd:183-184`, `n.position = _nav.stand(...)`)
and from wild units lerping (`units.gd:221`) while playing a standing move.

**What shipped Godot work does.** The recipe in Godot's docs and community: BlendSpace on speed, synced, time
scale = actual speed / clip speed, in-place clips or root motion read back with `get_root_motion_position()`
([AnimationMixer docs](https://docs.godotengine.org/en/latest/classes/class_animationmixer.html)). Motion
matching exists ([godot-motion-matching](https://github.com/GuilhermeGSousa/godot-motion-matching), ~255 stars,
MIT, GDExtension, 4.4+, "under development", macOS arm64 build unverified) but is too heavy per person for a
crowd. Not for us.

**Recommendation.** In-place with synced speed (what we have, fixed), not root motion: our movers own position,
and root motion would fight the RVO and the LOD skipping (anim_lod skips frames for far people; root motion
read on a skipped frame jumps). For pushed idle people: **avoidance on, priority lowest, never moved**
(today's behaviour, keep it); anyone who must make room *walks* there through the mover, legs and all. Godot's
docs say avoidance is costly with many agents, so turn it on only for people moving now
([NavigationAgent3D docs](https://docs.godotengine.org/en/latest/classes/class_navigationagent3d.html));
standing people stay as obstacles (as `_avoid_others` already does for scene folk, `villagers.gd` from 124bf5e).

## 2. Foot placement and IK

**Built in (MIT, Godot 4.6+):** `IKModifier3D` family: `TwoBoneIK3D`, `ChainIK3D`, `FABRIK3D`, `CCDIK3D`,
`SplineIK3D`, `JacobianIK3D` (PR [#110120](https://github.com/godotengine/godot/pull/110120), TokageItLab;
[IK returns in 4.6](https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/));
`LookAtModifier3D` (4.4); `CopyTransformModifier3D`, `AimModifier3D` (4.5); `LimitAngularVelocityModifier3D`
(4.6). `TwoBoneIK3D` is deterministic and the cheapest.

**Add-ons:** [Many Bone IK](https://github.com/V-Sekai/many_bone_ik) (~47 stars, MIT, an engine module): its
work became the 4.6 built-ins. [RenIK GDScript port](https://github.com/V-Sekai/renik) (~33 stars, last push
around July 2024, licence unconfirmed): stale. **No maintained foot-IK add-on for Godot 4 exists.** The block
is `TwoBoneIK3D` per leg, target = foot bone dropped to `terrain.height_at()` (no physics ray needed), pole
in front of the knee.

**Cost at crowd scale.** Two solves per person per animated frame, on the CPU, plus the modifier pass. No
published crowd benchmark (unverified). Towns are mostly flat, and foot slide is a locomotion fault (section 1),
not an IK one. So: **IK last, and only for people under `anim_lod.NEAR`** (6 units, every frame), off for the
rest. Look-at (`LookAtModifier3D`, head toward who's speaking) is the cheaper, more visible win for talks.

## 3. One skeleton

**What we have.** Every body and every clip is already mapped to `GeneralSkeleton` with
`SkeletonProfileHumanoid` (BoneMaps in `realm/assets/retarget/`: `mixamo_map`, `ual_map`, `ue_map`, three
`fuse_*_map`). The mapping is right. The **rest-pose handling is not uniform**:

- Fix Silhouette is on for 3 bodies only (`monk`, `noble_lady`, `svend`); off for the other 17 bodies and for
  all 172 Mixamo clip files (checked each `.import`). Fuse civilians come from Sketchfab glTF (A-pose sources
  are common there); Y Bot clips are T-pose. When the rest poses differ, the same shoulder rotation lands the
  arm in a different place: arms swing into the torso. Godot's retarget docs name Overwrite Axis as the key
  option for sharing clips across rigs and Normalize Position Tracks for different body sizes
  ([retargeting docs](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/retargeting_3d_skeletons.html)).
- `_shape()` scales Hips, Spine and Chest by up to 1.08 x 1.134 for stout people (`people.gd:435-448`). The arm
  clips are Y Bot's slim torso. A stout man's swinging hand goes through his own belly. Wide meshes (armoured
  `knight`, `paladin`; `noble_lady`'s gown) do the same with no scaling.

**Recommendation.** One import preset for every body and clip: BoneMap + Overwrite Axis + Fix Silhouette +
Normalize Position Tracks, Remove Tracks: unmapped bones. Re-import and re-film. Drop the chest and spine girth
scale (keep stout by the outfit choice); if girth is wanted, compensate with a small additive arm-out pose
from a `Blend2`/`Add2` filtered to the shoulders, or `CopyTransformModifier3D`, never by scaling the trunk.

**One body family.** Yes: the 172 Y Bot clips (two-thirds of the library) fit Mixamo-rigged bodies best.
Crowds use the Mixamo-rigged family; the Quaternius outfits (`people.gd:21-24`) stay only where the probe
passes them, since UAL clips are authored on their body.

**Period-correct bodies (plain medieval).**

| Station | Keep | Out (asset-audit.md:42 already says never; still in `people.gd:38-62`) |
|---|---|---|
| Peasant | `fuse_civilian_1`, `fuse_civilian_2`, `svend`, `medieval_man`; Quaternius `Male_Peasant`/`Female_Peasant` | `brute` (bare chest, tattoos) |
| Burgher, townsfolk | the Fuse civilians and `svend` with house dyes | `fuse_woman_1` (short tunic over bare legs) |
| Gentry | `noble_lady`; men: `paladin_prop` at court only. Gap: no plain gentleman | `dreyar` (gems, anime hair) |
| Clergy | `monk` (friar's habit) | |
| Mail-clad soldier | `knight`, `paladin`, Quaternius `Male_Ranger` | `heraklios`: check the look (classical-styled); `Maria J J Ong` (asset-audit.md:134) is an unused shieldmaiden |

**Gaps:** no period woman commoner on the Mixamo rig (only the Quaternius `Female_Peasant`), no plain gentleman.
`people.gd:38-62` still casts `brute`, `dreyar` and `fuse_woman_1` that the audit bans: the NPC builder removes them.

## 4. Props in hands

**What we have.** `weapons.gd` puts swords, axes, spears, bows and shields on hand bones with
`BoneAttachment3D`, sized and gripped by a data table (`weapons.gd:20-28`, `_hold` at `:110`). Nothing hands a
townsperson a tool: the `Drinking` clip is in six activities (`npc_mind.gd:21,198,249,838,841,938`) with an
empty hand.

**Block.** `BoneAttachment3D` (proven, already ours). `ModifierBoneTarget3D` is in the 4.7 docs (runs inside the
modifier pass, so IK can target it; [docs](https://docs.godotengine.org/en/latest/classes/class_modifierbonetarget3d.html);
version added unverified): only needed once IK hands hold things. Not now.

**How.** `weapons.gd` becomes the one "held" module: a `TOOLS` table next to `KINDS` (`cup`, `axe`, `hammer`,
`pail`, `torch`, `basket`, `broom`) and one data row per clip: `{"Drinking": "cup", "Hammer_Swing": "hammer",
"Idle_Torch_Loop": "torch", ...}`. `motion.gd` attaches on entering the state and detaches on leaving, so the
cup is in hand exactly while the clip plays. One owner: the clip's row.

**Props we already own** (our look is realistic, so Poly Haven fits and Kenney/Quaternius toy kits don't,
asset-audit.md:42):

| Prop | Source we have | Licence |
|---|---|---|
| Cup | `wooden_bowl_01` (a mazer, period-correct for commoners) in Poly Haven `*_4k.blend.zip` (asset-audit.md:153); market pack Pottery and Bottles (asset-audit.md:75). Poly Haven `brass_goblets` (gentry) to fetch | CC0; market pack CC-BY |
| Axe | `realm/assets/props/weapons/axe` (already sized); Poly Haven `wooden_axe`, `_02`, `_03` | CC-BY; CC0 |
| Hammer | `medieval_tools_set` (unused; tongs, hammers, chisels, asset-audit.md:75); Poly Haven `wooden_hammer_01` | CC-BY; CC0 |
| Pail | Poly Haven bucket (in game, asset-audit.md:76), `wooden_bucket_02` | CC0 |
| Basket | Poly Haven basket (in game), `wicker_basket_02` | CC0 |
| Torch | Quaternius Fantasy Props torches (in `props/`, asset-audit.md:88, stylised, small in hand is fine); Poly Haven `wooden_lantern_01` | CC0 |
| Broom | Poly Haven `wooden_broom` | CC0 |

The `.blend` ones need a one-time export to glTF at 1K. **Gaps:** no pitchfork, no tankard in any free pack
checked.

## 5. Crowd scale and cost

**What we have.** One AnimationTree per person, each on `ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`, advanced by
`anim_lod.gd`: every frame within 6 units, every 3rd to 12, every 6th to `SEEN_TO` 18, none off screen
(`anim_lod.gd:20-24`, `:94-117`). Meshes stop at `SEEN_TO` via `visibility_range_end` (`people.gd:408`).
That is the community's recommended near-ring setup.

**What others report.** No formal benchmark exists. A Jan 2026 Godot forum thread: ~300 units at 36 fps on an
iGPU, 50-100 "safe"; the biggest win was turning distant and off-screen animation off; AnimationTree costs
more than AnimationPlayer ([thread](https://forum.godotengine.org/t/performance-of-crowds-of-animated-rigged-characters-in-3d/130409)).
For far crowds the block is [antzGames' Vertex Animation Textures plugin](https://github.com/antzGames/Godot_Vertex_Animation_Textures_Plugin)
(~131 stars, MIT, Godot 4.5+, benchmarked on 4.7.1, last commit 5 Oct 2026; 2000 instances at 349-768 fps).
Limits: under 8192 vertices per mesh, no blending between clips, baked in Blender. Our bodies are mostly over
8192 vertices, so VAT needs a decimated far body.

**Recommendation.** Keep per-person AnimationTree on the manual tick (villagers' old second culler is already gone).
Measure 300 people with `GOC_PERF_PROBE`
(`perf_tools.gd`), splitting `anim_lod` time. Only if over budget: a VAT far ring (12-18 units), where people
are a few pixels and no blending is needed. `callback_mode_discrete` stays the AnimationTree default.

## 6. Blending, transitions, one decider

**Clip crossfades are fine:** 0.2 s, 0.1 s into blows (`motion.gd:26-27`), two slots per kind, so it always
crossfades (`:17-19`). Loops start at a random phase (`:278-289`), so no crowd moves as one.

**What snaps is the body, not the clip.** Facing is set instantly in at least nine places:
`villagers.gd:561` (every walking frame, so RVO jitter flips the facing frame to frame),
`npc_mind.gd:117`, `:136` (back to the work in one frame), `:341`, `:716`, `town_life.gd:396,435,453,569,585,595,707`.
Only `units.gd:242` and `villagers.gd:440` turn with `lerp_angle`. Fix: the mover turns at a turn rate
(about 360°/s, eased) toward a wanted facing; minds set the wanted facing, never `rotation.y`. The Mixamo Root
pack's `Left Turn` / `Right Turn` (asset-audit.md:172) can play for turns over 60° while standing.

**Who decides "which move now".** `motion.gd` is the only player of moves (`principles-audit.md:229`), but
**five deciders call it**: `npc_mind.gd` (LimboAI), `villagers.gd` (fallback rules, `:442`, `:481`, `:549-561`,
`:771-775`, `:1101`, `:1128`), `town_life.gd` (`:224-258`), `units.gd` (`:250-258`), plus scenes and battles.
And the minds are off: `LIMBO_TOWNS` is empty and `LIMBO_ALL` false (`town_life.gd:37,53`), so the playtest ran
on the fallback rules.

**Target (SSOT, SRP):**
- The LimboAI tree is the one decider per person. It does not call `play()` per frame; its tasks set the
  activity (`activity`, `held`, `facing`) on the person, and `motion.gd` maps activity to state, crossfade and prop.
- Locomotion is never asked for: `motion.gd` reads pace and goes to `rest` on its own (it already does,
  `:204-210`); `People.play(n, "Walk")` calls (`villagers.gd:561`, `npc_mind.gd:118`, `units.gd:250`) go.
- Movers move, minds decide, motion animates. No file does two.

## 7. Camera

**What it collides with.** Only building prisms on its own layer (`camera_rig.gd:273`, `:307-321`, mask at
`:52`, `:336`). **People and props are not in it.** The jumps come from four snaps in our own code:

1. **The lens snaps in.** `_hit = free if ... free < _hit` (`camera_rig.gd:343`): any roof entering the sweep
   moves the lens in one frame; out it eases at 0.15 per frame (frame-rate dependent).
2. **The roof guard switches on at a threshold.** Below distance 4 it runs, above it `_hit = -1.0`
   (`:470-473`): zooming across 4.0 with a building behind jumps the lens.
3. **The trees lift in 0.3 steps.** `pos.y += 0.3` up to 12 times in one frame (`:466-469`): up to 3.6 units at once.
4. **The look height switches rule.** `_look_y` follows the ground exactly once `ground_view > 0.5`, eased
   otherwise (`:436`): on a slope the aim jumps as you zoom through that point.

**Blocks.** [Phantom Camera](https://github.com/ramokz/phantom-camera) (~3.7k stars, MIT, 4.4+, v0.11.0.4):
its Third Person mode is a SpringArm3D with collision mask and margin; it has no RTS zoom-tilt curve. We tried
it twice: battle takes lost their aim (identity rotation on alternate takes), and its manager reset
`physics_jitter_fix` (`docs/review/LOOP.md:54-66`). RTS camera add-ons
([GodotRTSCamera3D](https://godotengine.org/asset-library/asset/edit/13256), MIT, built for 4.2;
[3D-RTS-Camera](https://godotengine.org/asset-library/asset/edit/15258), MIT, 4.3) are smaller than our rig and
have no street-level collision. Godot's `SpringArm3D` (shape cast, `collision_mask`, `add_excluded_object`) is
what our ShapeCast3D already does, and it doesn't smooth either.

**Recommendation: fix our rig, don't adopt a block.** No block does RTS-to-street with roof avoidance, and the
one we tried broke battle aim. Builder 2:
- one damped ease on the final lens position and the aim, `1 - exp(-delta * k)` like the rest of the rig
  (`:387`), with snap-in kept only when the lens would be inside a prism (not merely behind one);
- the roof guard always on, its strength faded in from 4.5 to 3.5;
- the tree lift solved to a target height and eased;
- `_look_y` eased at every distance, with a faster rate close in;
- people and props stay out of the lens layer (as now).

## 8. Proof: a motion probe that would have failed tonight

Headless works: Godot computes skeleton poses on the CPU without a GPU, so bone world positions are real in a
`--headless` run on the private bridge (8788/5557, per the state-checks rule). One probe,
`realm/scripts/tools/motion_probe.gd`, behind `--probe`, runs one town for 60 s with every person ticked every
frame (`anim_lod.flat = true`) and prints PASS/FAIL per check:

| Check | Measured | Fails when | Would have failed tonight because |
|---|---|---|---|
| Foot skate | Per person, per frame, `LeftFoot`/`RightFoot`/toe bones in the person's own space (divide by `person.scale`, so units are the clip's metres). Planted = under 5 cm above the lowest foot of the clip. Skate = planted with more than 2.5 cm horizontal travel that frame. The "foot skating ratio" of GMD (Karunratanakul et al. 2023, [paper](https://ar5iv.labs.arxiv.org/html/2305.12577), sec. 6.1), also used by OmniControl | Over 10% of planted frames skate, for any person, over 60 s (estimate, to be tuned on a clean walk) | Talk/work loops slide with no legs (`motion.gd:204-210`); tweened steps; children |
| Hand in body | Hand bones against a capsule from Hips to Neck, radius from the body's mesh AABB at rest | A hand inside the capsule for 3+ frames outside clips that touch the body (a list: `Clapping`, `Praying`, ...) | Stout chest scaling; unfixed silhouettes |
| Empty hand | Clip in the props table playing, no BoneAttachment3D under the hand | Any frame | `Drinking` with no cup |
| Turn snap | Body yaw change per frame | Over 15° in one frame (about 900°/s at 60 fps) | `villagers.gd:561`, `npc_mind.gd:136` |
| Two in one | People pairs closer than 0.06 (the CHECK already in villagers.gd from 124bf5e) | Any pair for 1+ s | Tweened steps ignore RVO |
| Camera jump | Lens position change per frame against `distance`, while no focus or snap was asked | Over 5% of distance in one frame | `camera_rig.gd:343`, `:466-473`, `:436` |

Then the clips: 3-6 s films of the capital's square and a walking street, read as frame strips
(`realm/tools/clip_strip.gd`), before and after each step. The probe decides; the clips confirm.

## Risks

- **Re-importing every body and clip** (step 1) changes every pose in the game at once. Behind the switch is
  impossible for imports; do it on a copy of the import settings first, film the capital, then commit.
  Weapon grips (`weapons.gd` sockets) may need re-fitting after the axis change.
- **`sync_mode` is new in 4.7** (per the 4.7 docs). Confirm it exists in our build with `--check-only` before
  relying on it.
- **Turning minds on everywhere** (`LIMBO_ALL`) changes every town's life at once; the behaviour probe in
  goc-engineering must pass first.
- **IK** costs CPU per person; near only, and measured.
- **VAT** loses blending and needs decimated bodies; only if measured need.
- **Camera** changes touch battle takes; re-film a battle first (the lesson from Phantom Camera).

## What to delete afterwards (the glue)

- `npc_mind.gd` `Step`'s tween and its `rotation.y` sets (`:90-137`): steps go through the mover.
- `People.play(n, "Walk")` and gait calls from movers (`villagers.gd:561`, `npc_mind.gd:118`, `units.gd:250`): legs follow pace.
- Every direct `rotation.y = atan2(...)` on a person (list in section 6), replaced by one wanted-facing.
- `motion.gd`'s `MOVING`/`SETTLE`/`_wish` waiting dance (`:41-42`, `:204-217`) once standing moves give way on real motion.
- `motion.gd`'s `speed = maxf(1.0, _pace / RUN_PACE)` (`:220`): the synced blend space and time scale replace it.
- `people.gd` `_shape()` trunk scaling (`:435-448`), and `brute`, `dreyar`, `fuse_woman_1` from `BODIES`.
- villagers.gd's fallback clip rules once minds are on everywhere.
- `camera_rig.gd`'s stepped tree lift (`:466-469`) and its threshold switch (`:470-473`).
