# AnimationTree

How Godot 4.7's AnimationTree behaves where a game layers clips: reading where a clip is, locking one branch to
another, and what a test that steps the tree by hand sees. Learned on Deadnight's sprint carry (Deadnight #459: an
upper-body clip that must stay on the legs' Run frame for frame). The crowd side (throttling, manual advance) is on
[Crowds](crowds.md).

## Reading where a clip is {#reading-where-a-clip-is}

Every node of a tree publishes read-only parameters: `current_position`, `current_length` and `current_delta`
(seconds; the last is the step it took in the last process). For a clip inside a blend space in a state machine:

```gdscript
var at: float = tree.get(&"parameters/body/locomotion/move/run/current_position")
var step: float = tree.get(&"parameters/body/locomotion/move/run/current_delta")
```

List them with `tree.get_property_list()` filtered on `parameters/`: there is no older `time` parameter in 4.7.

- They hold the values of the **last** process. Read from a script's `_process`, they are the frame before the tree's
  next step.
- A blend space with `sync = true` advances every point, so a clip at weight 0 keeps its place (and its
  `current_delta`); with `sync = false` it stops at weight 0.
- A state machine state that is not playing is not processed: its clips keep their last position. A transition with
  `reset = true` (the default) restarts the state's clips at 0 when it is entered again (a landing back into the
  locomotion restarts the Run).

## Locking one branch to another {#locking-one-branch-to-another}

Two clips in different branches (an upper-body layer and the legs) drift unless one is driven from the other. Put an
`AnimationNodeTimeSeek` in front of the follower and, every frame, seek it to the leader's `current_position` plus
its `current_delta`: the place the leader reaches in the coming step. Both then land on the same frame at any play
rate (measured: within 0.002 s over 40 frames at 1.3 times the clip's pace). Where the leader jumps (its state
restarted) or stops (in the air), let the follower hold or catch up over a few frames instead of seeking across the
cycle: a seek is a cut.

## A tree built in code for a player {#a-tree-built-in-code}

<!-- new section: the page had Deadnight's layered clips; nothing said how a small controller's tree is made and read -->

- **Approach:** Build a character's tree in code from its clip names (a state machine whose `ground` state is a blend
  space on ground speed, plus a one-shot layer for any other clip), expose `body_state()` and `is_acting()` for tests and
  `play_clip(clip, duration)` for games, and read the state from `parameters/<machine>/playback`. **Watch out for:**
  `AnimationNodeBlendSpace1D.add_blend_point` wants a name in 4.7 (a warning per point otherwise), and a one-shot clip
  node is set to the new clip by writing its `animation` before the request, with an `AnimationNodeTimeScale` in front
  to fit the clip to the time the game holds the body (the 2 s Interact clip into 0.7 s). **Seen:** gdstudio #821,
  2026-11-08 ([The 3D Third Person template](third-person-template.md#animation-libraries)).
- **Approach:** Keep a tree in code when agents develop the project, and make the editor show it too: `@tool` on the
  builder, `tree_root` and `anim_player` built in `_ready` for editor and game, `Engine.is_editor_hint()` guards on all
  driving, and setters on the clip exports that rebuild it in the editor. Take both off the node on
  `NOTIFICATION_EDITOR_PRE_SAVE` and build them again on `..._POST_SAVE`; test it by reading the `.tscn` files for
  `tree_root`, `AnimationNode` and `anim_player`. **Watch out for:** a tree built in `_ready` of a non-`@tool` script
  left the editor's AnimationTree empty, with a warning and no graph. A tree dragged together by hand is saved in the
  scene instead, never also built. **Seen:** gdstudio #830, 2026-11-08 (fix: `PlayerAnimation` is `@tool`;
  [screenshots](editor-screenshots.md#how)).

## Stepping a tree by hand in tests {#stepping-a-tree-by-hand-in-tests}

`callback_mode_process = ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`, the owner's `_process(delta)` then
`tree.advance(delta)`, one fixed step at a time: no clock is read.

- Read bones off the skeleton (`get_bone_global_pose`) after `advance`. A `BoneAttachment3D` on that bone has not
  moved yet in the same step: it follows on the skeleton's next update, so a test reading the attachment saw a hand
  that did not move at all.
- Keep a clip's time in a `float` from step to step. Passed through a `Vector2` (32-bit components) a time of
  2.4999999 became 2.5, so the clip's last event fired a step before its end check.
- Measure a hand against the hips, not the skeleton: the locomotion's bob (the kit Run's Body moves 21 cm at kit
  scale) is in the skeleton's frame and swamps an arm's swing.

- **Approach:** To read a clip's pose from a script, put the model and an `AnimationPlayer` in the tree, set the
  manual callback mode, then `play(clip)`, `seek(time, true)` and `advance(0.0)` before `get_bone_global_pose`.
  **Watch out for:** in a `SceneTree` script's `_init` (`--script`) the same calls left every bone where it was: a
  probe printed one hand place for seven frames. **Seen:** gdstudio #1010, 2026-11-10 (`tools/capture/vault_study.gd`
  and `tests/assets/test_vault_clips.gd` in the 3D Third Person template).
- **Approach:** Hold the clip (`pause()`, or `speed_scale` 0) after sampling a pose, and repeat a measure that awaits
  a few times in one process before choosing a limit for it. **Watch out for:** `ClipFit.pose` left the clip playing,
  so readings made after two awaited physics frames came from a later pose (a knee moved up to 6 cm) and one pose gave
  0.144, 0.142 and 0.1348; it failed two of three pull requests that touched no character file. **Seen:** Deadnight
  #1143, 2026-11-04 (fix: `_player.pause()` after the sample; eight repeats gave 0.1348 each).

## A clip on top of a pose a modifier fades out {#a-clip-on-top-of-a-pose-a-modifier-fades-out}

A `SkeletonModifier3D` that holds the arms (Deadnight's `WeaponHandsIK`, the gun at the shoulder) and fades its
`influence` out over a few frames when a one-shot clip takes the arms does not give the clip the arms at once: at an
influence of 0.2 the modifier still pulled the hand 0.2 m off the clip (its pull is not linear in the influence),
the clip's wind-up was flattened to half its travel for the first fifth of a second, and when the fade reached zero
and the modifier was switched off, the arms jumped 0.25 m in one frame. For a clip that is the arms' work from its
first frame, set the influence to 0 and the modifier off in the frame the clip starts, and let it rise again from
zero once the clip is over. Measure it: the weapon's place in the player's frame, every tick of the clip, in a test
that steps the tree by hand.

The cause (Godot 4.7, measured in Deadnight #619): with a modifier on, the bones it turns do not all follow `influence`.
The chest and the hand bones blend linearly with it, but the upper and lower arm bones of an IK chain stay in the
modifier's pose at any influence, 0 included, so switching the modifier off at 0 snaps them to the clip's (27 to 66
degrees in one tick, a hand 0.7 m). Fading it out for any other reason (a sprint carry that takes the arms back
over 0.2 s) pops the same way. Leave `influence` at 1 and blend inside `_process_modification`: keep each bone's local
rotation before solving, then `set_bone_pose_rotation(bone, before.slerp(solved, weight))` for every bone the modifier
turns. At weight 0 the pose is the clip's, so switching off moves nothing. The modified pose is only readable at
`skeleton_updated`; record the bones there, every tick, and fail on a per-tick turn or move far above the clip's own
stride.

- **Approach:** When a modifier or additive fades out, record the drawn bones every tick through the fade, for the
  player and the puppet, and fail on a per-tick jump. **Watch out for:** Deadnight #525 faded the hands IK by the
  modifier's `influence` and switched it off at 0, but Godot blends only the chest and hand bones by `influence`, so the
  arms stayed in the IK pose and snapped to the carry clip in one tick (66 degrees) as a sprint began. **Seen:**
  Deadnight #619, 2026-11-02 (fix: deadnight #645 added the per-tick test).

## A state machine that starts at Start and has no way out {#a-state-machine-that-starts-at-start-and-has-no-way-out}

A `AnimationNodeStateMachine` begins in its `Start` node, and a state reached only by `travel()` from the locomotion
(Deadnight's crouch) is unreachable from there if `Start` has no automatic transition out. A played body left `Start`
by falling onto the lot at the spawn; a drawn copy of another player, standing on the floor from its first frame, never
did, so its crouch never began. Call `playback.start(&"locomotion")` in `_ready`, and test a body that was never
airborne.

## World aim is written on every turn {#a-modifier-that-aims-in-the-world-needs-the-world-value-written-on-every-turn}

`WeaponHandsIK` (Deadnight) poses the arms against a world yaw its view writes (`aim_yaw`); nothing in the modifier
reads the body's own turn. A view that turns the body and writes the yaw only inside an "animated" step (Deadnight's
menu stage in a still, or with reduced motion) leaves the weapon fixed in the world while the body turns through it,
and a modifier built for a new weapon starts at yaw 0. Write the yaw together with the body's turn (one `face(yaw)`),
at build time, and pose on every step with a delta of 0 when the clock is stopped: `AnimationPlayer.advance(0.0)`
applies the clip once, so the skeleton is not left in the model's arms-out rest. Test every level the view can run at,
reading the bones at `skeleton_updated`. Deadnight #940.

- **Approach:** Set a held weapon's aim from the body's own facing every frame, whatever the stage's motion level, and
  test the stage through each of its paths (animated, still, reduced motion) at a sweep of turn angles with every
  weapon, hands and muzzle in front of the chest. **Watch out for:** the arms were posed in world space along an
  `aim_yaw` written only in the animated step, so in a still or with reduced motion the idle clip never applied and the
  weapon pointed backwards through a turned body. **Seen:** Deadnight #940, 2026-11-03 (fix: the yaw is written with the
  body's turn, as above).

## One action state for every body {#one-action-state-for-every-body}

A state machine that picks its states by mode (move, attack, stagger, die) and by body only for the move state plays
the standing clip in the actions of a body that cannot stand. Deadnight's crippled zombie (a crawler, legless, lying on
its hands) played the walker's `Punch` when it swung and its `HitReact` when hit: its head went from 0.2 to 0.99 m (kit
scale) for the blow, 4 times its crawl height (#971). Give the body its own state for each action it can take (a
`crawl_attack` beside `attack`, chosen by one test of the look in the view), author the clip from the body's own
locomotion frame so it starts and ends on it, and keep three things that follow the clip in step with it: the hit set
(fitted to the clip, not to the clip the other body plays), the reach and the telegraph (data on the type, read by the
simulation and the view from one place) and the time scale that puts the clip's blow frame on the telegraph.
Measure the result as the highest point of the skinned mesh over the clip against the locomotion's (the standing punch
on the crawler's mesh: 1.84 m, the crawl: 0.85 m, the new attack: 0.87 m), and in the real night as the highest bone of
the view's skeleton in the mode against the crawl's.

Do it for every action in one change, and test the list by looping over the mode enum (`ZombieBody.Mode.values()`) so a
mode added later is measured too: #971 fixed the attack only, and the stagger (`HitReact`, 1.66 m) and the death
(`Death`, 1.81 m) kept standing the crawler up until #1000 gave it `Crawl_Stagger` and `Crawl_Death` (0.87 m and
0.85 m). A flinch is as long as the stagger the simulation holds (0.4 s: the clip is played from its start on every
entry and is not scaled), and a fall is a clip that holds its last frame while the body lies.

- **Approach:** For every movement state (walk, run, sprint, crouch, air), list what each body layer plays and capture
  it from the player's camera; a layered rig never leaves a layer in a pose meant for another state. **Watch out for:**
  a sprint is a whole-body action, but the legs played `Run` while the upper layer kept looping `Aim_<Class>`, so arms
  and gun froze and the kit's `Run_Gun` clip sat unused; only the camera sway had been tuned. **Seen:** Deadnight #459,
  2026-11-02 (fix: deadnight #525 added the sprint carry, posed from the shoulder camera's side
  ([Blender](../../tools/blender/rig-sharing.md#bone-axes-in-godot-and-clips-that-hold-a-weapon))).
- **Approach:** For every body state (standing, crawling, downed, climbing), list each action's clip, hit set and reach,
  and test through the real night that the body's highest bone in each action stays within that state's height. **Watch
  out for:** the view picked its state by mode and only the move state had a crawl branch, so every crawler rose into
  the standing `Punch` (the mesh from 0.85 to 1.84 m), with one reach and windup for every zombie. **Seen:**
  Deadnight #971, 2026-11-04 (fix: a crawl attack of its own, as above);
  Deadnight #1000, 2026-11-04 (fix: `Crawl_Stagger` and `Crawl_Death` too, and a test that loops over the mode enum).

## Two clips half a turn apart on a bone {#two-clips-half-a-turn-apart-on-a-bone}

The tree blends a bone's rotation between two clips along the shorter arc. Where the two are near half a turn apart
(a hand rolled over between a gun hold and a carry), the shorter arc swaps sides as either clip moves, and the bone
spins most of a turn in one tick of the crossfade. Deadnight's sprint carries had the left wrist 175-180 degrees off
the gun hold's; the build now rolls the forearm about its own axis until every frame is within 150 degrees, and
prints the worst (`CARRY_WRIST_MAX`). Keeping a modifier's own slerp on one arc does not help when the flip is in
the tree. Any clip the tree blends against another keeps each bone's local turn well under half a turn from the
other's: print it at build time.

## A clip driven by place {#a-clip-driven-by-place}

When the simulation carries a body over an obstacle at its own pace (Deadnight's dead over a window's sill, 1.2 to 6 m/s),
a clip played by time drifts off the ledge. Make its frames places on the way instead: the clip behind an
`AnimationNodeTimeSeek` and an `AnimationNodeTimeScale`, the scale's parameter set to 0 once on each tree, and a seek
request written on every snapshot from the body's position. Only the seek moves it, so a body that stops stops the
clip, and the order is output, scale, seek, clip: the seek reaches the clip through a scale of 0 (a seek is not scaled).
The state's transitions from the gait carry `xfade_time` and the view uses `travel`, not `start`, which cuts; a state
with no path is teleported to, so a stagger into the climb still works. Blender writes such a clip in the obstacle's
space: [Clips written in the world's space](../../tools/blender/rig-sharing.md#clips-written-in-the-worlds-space).

- **Approach:** When a clip moves a body far from its origin (a climb over a sill), grep for the hit sets and every aim
  offset in the same change: give the clip its own hit set, chosen by the snapshot's bit, and read every aim point
  (bots, the autopilot, touch aim assist) from that set. **Watch out for:** shots and aim points are placed over the
  origin and never look at the clip, so a head over a window's sill was drawn 0.9 m under the standing head zone at the
  lifted origin, and the bots aimed 1.1 m over it, at nothing. **Seen:** Deadnight #991, 2026-11-04 (fix: a hit set of
  its own for the climb, twice the shapes, and the aim read from it).

## Build the state machine once, share it between trees {#build-the-state-machine-once-share-it-between-trees}

An `AnimationTree` keeps its own playback, parameters and seek requests (`parameters/...`); the `tree_root`
(`AnimationNodeStateMachine` with its blend spaces, blend trees, clip nodes and transitions) is only the recipe. One
machine can be the `tree_root` of every body's tree. Deadnight built a machine in `attach` for each zombie: 46 objects
a body (measured as `Performance.OBJECT_COUNT` before and after `attach`), 3 once the machine was shared, and the two
climb states added to it were what took the late-round budget over its object limit (20 839 against 20 500 at the
same run, 15 589 shared). The library (`AnimationLibrary`) was shared already; the machine is the same kind of thing.
Release the static that holds it with the library.
