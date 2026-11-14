# Turns by root motion

<!-- new section: clips.md reached the size limit when gdstudio #1442 met #1369's jump clips -->

## Turns moved by their clip {#turn-root-motion}

<!-- new section: the reversals and pivots stopped being drawn over a body the controller turned in 0.26 s and became
the body's own motion (gdstudio #1442); control, AI paths and the network change with it -->

A body on its feet at a jog or a sprint that is asked to go back the way it came (`CharacterTuning.reversal_angle`,
135 degrees between where it moves and where the stick points) or to cut off (`pivot_angle`, 60) is moved by the
clip's own root (`CharacterTurnMotion`, in the step): each tick its velocity is the change of the record's `travel`
over the tick, turned into the frame it ran in as the clip began and scaled by the tuning's gait speed over the
clip's at its first frame, and its facing is where it began plus `turn`. Travel and facing are read apart, so the body
brakes the old way while it already faces round and only then speeds up the new way. `GaitTransitions` plays the clip
the step started at the step's time into it (`turn_motion.clip`, `elapsed`, a new one on each `serial`), so the feet
drawn are the ones the body moves by: on open floor the body is on the travel curve to 0.1 mm and on the turn curve to
0.01 degrees every committed tick (`test_turn_root_motion.gd`). Inspector: `CharacterTuning` > Turns (`turn_root_motion`,
`pivot_angle`, `reversal_angle`, `turn_hand_back`, `reversal_clips`, `pivot_clips`), and `CharacterController.turn_clips`.

- **Control.** The clip is picked on the tick the stick asks for the turn (no added latency: the body brakes from
  that tick), its side by the way the stick asks the body to turn. The body is then committed: the stick's direction
  is not read until the turn is made: the frame the record's `turn` reaches its last yaw, or its `free` event if
  that comes first (from the shipped clips: 1.83 s of the jog reversal, 2.23 s of the sprint's, 1.53 s of the
  pivot; the rest of each clip is the gait's run-out). Then the body's own steering takes over, its velocity blended
  from the clip's into the steering's over `turn_hand_back` (0.25 s): the jog reversal hands back at 2.8 m/s and the
  sprint's at 3.0 m/s, and the velocity changes by at most the steering's own acceleration a tick on the way up to
  the gait's speed. Letting go of the stick, a jump, a
  crouch, the aim, a hit, lying down, a slide or leaving the ground ends it at once, and the body's own steering
  takes over from the velocity it has. A body arriving at a jog and asked to cut off is committed to the pivot too:
  a scripted route that must turn sharply on a point stops on it first.
- **AI paths.** An AI's controller turns `turn_clips` off, so its body keeps to the navigator's path and turns by its
  steering as before (the clip, picked by the tree, plays at its own pace over it). On, a reversal would carry the body
  3.7 m past the point it turned at from a jog and 6.3 m from a sprint, and a pivot would cut its corner by 0.58 m (the
  shipped clips), so a game that turns it on for its AI leaves the navigator
  that much room at a turn.
- **The network.** It is simulation, never cosmetic: the server and the predicting client step it from the same
  command and the same record (`locomotion.json` ships in both), and its step state is in `CharacterState.turn`, so a
  correction puts a body back mid-turn on the same path. A sprint reversal online ends with the client's body
  0.000000 m from the server's and no correction (`test_net_turn_root_motion.gd`). A body drawn from the network never
  steps: it shows the capsule's path in its gait, and its turn clips are picked by the tree as before (a follow-up
  like `PuppetVault`'s would show them).
- **Approach:** Drive a turn that a clip describes from the clip's own travel and turn curves inside the step, with
  facing and travel read apart, and show the clip at the step's time. **Watch out for:** a body the controller turns
  in 0.26 s under a clip seeked by the angle turned, raced to catch up (`transition_pace`), turned too soon and too
  neatly, with no brake ahead of the body. **Seen:** gdstudio #1442, 2026-11-13, from the maintainer's review.
- **Approach:** In a suite that compares two bodies stepped side by side to a few micrometres (helper tracks on and
  off, a setting on and off), switch `turn_root_motion` off in both tunings when the commands reverse or cut, so
  the tree plays the clip over the steering. **Watch out for:** a body moved by its clip's root is placed from its
  own spot, so two bodies at x -3 and 3 end 1e-6 m apart after a sprint reversal, and the stop that follows turns
  their spines 0.001 degrees apart, over a 1e-5 radian limit. **Seen:** gdstudio #1442, 2026-11-14
  (`test_helper_tracks.gd` from #1488, red only after main was merged in).
- **Approach:** After merging a change to how a body stops or steers, run the full suite: a suite that walks a body
  forward and back by fixed times (a pickup, a route) gets a reversal moved by its clip whenever the body still moves
  when it turns, and one not about turns sets `controller.turn_clips = false`. **Watch out for:** since the stops
  carry the body on (#1422), a walk back 0.3 s after letting go is a jog reversal that goes 3.7 m on before turning;
  the pickup was never walked over again, and a stalled client with the walk taken out was lost once. **Seen:**
  gdstudio #1442 merging #1422, 2026-11-14 (`test_weapon_pickup.gd`, `test_net_client_prediction.gd`).

**How a stop moves the body** (gdstudio #1415). A body on its feet with the stick let go slows by the stop deceleration
of the gait whose speed band it is in (`CharacterTuning` > Ground > Stops): `walk_stop_deceleration` 2.84 m/s² up to
`walk_speed`, `run_stop_deceleration` 4.38 up to `run_speed`, `sprint_stop_deceleration` 4.57 above. At the template's
60 ticks a second they cover each stop clip's travel: 0.48 m from the walk, 1.96 m from the jog, 4.82 m from the sprint,
in 0.60, 1.13 and 1.67 s (0.11 and 0.18 s from the jog and the sprint before). The stop clip is played by that ground
until the body is at rest (`GaitTransitions.STOP_DONE`, 0.02 m/s), counted from the tick the stick was let go, so its
planted feet hold the floor (under 3 mm in `test_gait_stops.gd`). Crouched, in the air or held by an action the body
stops by `deceleration` (36) as before. The rate is a function of the speed alone, so a predicting client and the server
stop a body at the same place (`test_net_gait_stops.gd`), and an AI's navigator lets go that far before its goal
([stopping](ai-navigator.md#navigator)). A game that changes a gait's speed or its stop clip sets the matching stop
deceleration to `(v_top² - v_bottom²) / (2 × travel)` over the band; a faster stop leaves the clip's feet sliding under
a body at rest.

**What a lean clip needs** (gdstudio #1159): its first frame is the pose leaning one way; what the tree adds is that
pose's difference from the idle's first frame, so it keys every bone the idle keys, the `ik_` targets too (where
its hands and feet are), or the difference pulls an unkeyed one back toward its rest. The template's own are
`gds/Lean_Left`, `Lean_Right`, `Lean_Fwd` and `Lean_Back` (`assets/animation/own/clips/lean.py`); each record says
its `lean` (`way`, degrees to the left of ahead, and the `degrees` the full pose leans) and its `reference`
(`Lean_Ref`, within 0.3 degrees a bone of the idle's first frame). On the player at full weight the head goes 210
to 330 mm the pose's way and the feet and targets stay within 0.1 mm (`test_own_directions.gd`).

The cost, from `tools/bench/gait_cost.tscn` (`gds template bench-web 3d-third-person gait_cost --run`, headless
Chrome on a workstation, the settings off and on in turns, players walking, blending, sprinting and stopping): 38 µs a
frame for one character, 17 µs a character with 40 (4.28 ms off, 4.97 ms on); headless desktop, 12 µs a character
with 40. The momentum blend reads 25 body bones a frame on each character and turns the ones that differ for 0.4 s
after a change; the transitions ask nothing of the body while no transition clip is in the libraries.

**The lean's cost** (gdstudio #1403). Built as one `AnimationNodeSub2` and two whole clips a way, the lean was the
dearest part of the tree: the parts bench read the tree at 1.96 to 2.03 times the body's step and the script at 1.23
to 1.25 (25 walking), and the budget case's ten walkers 1.76 to 1.92 times the calibration (1.31 to 1.46 with the
lean off). Since #1403 each axis takes its base off once (an `AnimationNodeAdd2` at minus the axis's lean, as only
one way of an axis leans at a time) and `LeanClips` keeps of each clip only the 23 of 61 tracks the poses move:
the tree 1.35 to 1.38 and the script 1.09 to 1.11, the budget case 1.48 to 1.64, the drawn bones within 0.0005 mm
of the old build (`test_gait_lean.gd`). Nothing depends on distance or sight. In headless Chrome
(`gait_cost.py` with `lean_off,on`), the lean a character a frame:

| | 10 walking | 40 walking |
| --- | ---: | ---: |
| Before | 32 to 37 µs (frame 1.82 to 1.92 ms) | 35 to 51 µs (7.9 to 8.9 ms) |
| After | 14 to 26 µs (1.74 ms) | 12 to 15 µs (6.2 to 6.7 ms) |
