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
