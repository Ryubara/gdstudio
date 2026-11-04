# AnimationTree

How Godot 4.7's AnimationTree behaves where a game layers clips: reading where a clip is, locking one branch to
another, and what a test that steps the tree by hand sees. Learned on Deadnight's sprint carry (Deadnight #459: an
upper-body clip that must stay on the legs' Run frame for frame). The crowd side (throttling, manual advance) is on
[Crowds](crowds.md).

## Reading where a clip is

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

## Locking one branch to another

Two clips in different branches (an upper-body layer and the legs) drift unless one is driven from the other. Put an
`AnimationNodeTimeSeek` in front of the follower and, every frame, seek it to the leader's `current_position` plus
its `current_delta`: the place the leader reaches in the coming step. Both then land on the same frame at any play
rate (measured: within 0.002 s over 40 frames at 1.3 times the clip's pace). Where the leader jumps (its state
restarted) or stops (in the air), let the follower hold or catch up over a few frames instead of seeking across the
cycle: a seek is a cut.

## Stepping a tree by hand in tests

`callback_mode_process = ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`, the owner's `_process(delta)` then
`tree.advance(delta)`, one fixed step at a time: no clock is read.

- Read bones off the skeleton (`get_bone_global_pose`) after `advance`. A `BoneAttachment3D` on that bone has not
  moved yet in the same step: it follows on the skeleton's next update, so a test reading the attachment saw a hand
  that did not move at all.
- Measure a hand against the hips, not the skeleton: the locomotion's bob (the kit Run's Body moves 21 cm at kit
  scale) is in the skeleton's frame and swamps an arm's swing.

## A clip on top of a pose a modifier fades out

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

## A state machine that starts at Start and has no way out

A `AnimationNodeStateMachine` begins in its `Start` node, and a state reached only by `travel()` from the locomotion
(Deadnight's crouch) is unreachable from there if `Start` has no automatic transition out. A played body left `Start`
by falling onto the lot at the spawn; a drawn copy of another player, standing on the floor from its first frame, never
did, so its crouch never began. Call `playback.start(&"locomotion")` in `_ready`, and test a body that was never
airborne.

## A modifier that aims in the world needs the world value written on every turn

`WeaponHandsIK` (Deadnight) poses the arms against a world yaw its view writes (`aim_yaw`); nothing in the modifier
reads the body's own turn. A view that turns the body and writes the yaw only inside an "animated" step (Deadnight's
menu stage in a still, or with reduced motion) leaves the weapon fixed in the world while the body turns through it,
and a modifier built for a new weapon starts at yaw 0. Write the yaw together with the body's turn (one `face(yaw)`),
at build time, and pose on every step with a delta of 0 when the clock is stopped: `AnimationPlayer.advance(0.0)`
applies the clip once, so the skeleton is not left in the model's arms-out rest. Test every level the view can run at,
reading the bones at `skeleton_updated`. Deadnight #940.

## One action state for every body

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
