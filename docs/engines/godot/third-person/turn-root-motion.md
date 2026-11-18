# Turns by root motion

<!-- new section: clips.md reached the size limit when gdstudio #1442 met #1369's jump clips -->

## Turns moved by their clip {#turn-root-motion}

<!-- new section: the reversals and pivots stopped being drawn over a body the controller turned in 0.26 s and became
the body's own motion (gdstudio #1442); control, AI paths and the network change with it -->

**Off by default since gdstudio #1565** (`CharacterTuning.turn_root_motion` false): a body on its clip's path
answered the stick 1.5 to 2.2 s late, and movement input is never held by a look. By default the body steers itself
every tick and the clip is drawn over it as a short look ([the look](#turn-look)); what follows is the opt-in mode.
With it on, a body on its feet at a jog or a sprint that is asked to go back the way it came
(`CharacterTuning.reversal_angle`, 135 degrees between where it moves and where the stick points) or to cut off
(`pivot_angle`, 60) is moved by the clip's own root (`CharacterTurnMotion`, in the step): each tick its velocity is
the change of the record's `travel`
over the tick, turned into the frame it ran in as the clip began and scaled by the tuning's gait speed over the
clip's at its first frame, and its facing is where it began plus `turn`. Travel and facing are read apart, so the body
brakes the old way while it already faces round and only then speeds up the new way. `GaitTransitions` plays the clip
the step started at the step's time into it (`turn_motion.clip`, `elapsed`, a new one on each `serial`), so the feet
drawn are the ones the body moves by: on open floor the body is on the travel curve to 0.1 mm and on the turn curve to
0.01 degrees every committed tick (`test_turn_root_motion.gd`). Inspector: `CharacterTuning` > Turns (`turn_root_motion`,
`pivot_angle`, `reversal_angle`, `turn_hand_back`, `reversal_clips`, `pivot_clips`), and `CharacterController.turn_clips`.

- **Control.** The clip is picked on the tick the stick asks for the turn, its side by the way the stick asks the
  body to turn. The body then follows the clip until the turn is made or the stick turns
  `CharacterTurnMotion.WISH_CHANGE` (40 degrees) or more from the way it asked for (since gdstudio #1565; before, the
  stick's direction was not read at all): the frame the record's `turn` reaches its last yaw, or its `free` event if
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

- **Approach:** Let the step follow the input every tick and draw a turn, start, stop or landing recovery as a look
  over the body's own motion, cut the tick the wish moves or an action comes; give the brake to the controller
  (`brake_deceleration`) and measure ticks per key change on the real input (`test_move_key_matrix.gd`).
  **Watch out for:** a clip that owns velocity and facing until its turn is made ignores every key meanwhile: a
  sprint reversal ran 6.3 m on, W+A to W+D started a committed pivot that read as a stop, and #1564 routed an opposing
  press into the same reversal; the tests asked which clip played, not how fast the body answered. **Seen:** gdstudio
  #1565, 2026-11-15, found by the maintainer playing 3D Third Person (a jog's velocity turned after 21 to 23 ticks;
  now 1).

### The look over a body that steers {#turn-look}

<!-- new section: the default reversal and pivot became a short look drawn over the body's own steering (gdstudio
#1565); how it is timed, drawn and cut had no place -->

The body brakes and turns by the controller: the part of its velocity across or against the wish goes at
`CharacterTuning.brake_deceleration` (40 m/s²) while the part along it speeds up at `acceleration` (28), so a straight
run is as before (`CharacterTuning.steer_toward`, shared by the AI's lean tick). A sprint reversal brakes in 0.16 s
over 0.53 m and runs the new way at full speed about 0.4 s after the press (on the clip's root: 6.3 m on, the turn
made at 2.23 s); a quarter turn of the keys is within 30 degrees in 5 to 7 ticks. `GaitTransitions` picks the
reversal (from `CharacterTuning.look_reversal_angle`, 135) or the pivot (`look_pivot_angle`, 100: a quarter turn of the
keys is a steer) on the frame the wish turns, the gait from the speed of the frame before (the brake has slowed it by
then), and plays the clip from `turn_look_lead` (0.2 s) before its turn begins to its turn's end, sped up to last the
gait's look time (`jog_reversal_look_time` 0.5 s, `sprint_reversal_look_time` 0.6, `pivot_look_time` 0.4). `TurnLook`
turns the rig under the model so the drawn body goes from the yaw drawn on the frame before to the way asked, along the
share of the clip's turn curve played, against the capsule's facing: the hips swing round over the planted foot while
the capsule already goes the new way. A difference left by an end or a cut halves every `turn_look_settle` (0.06 s).
A wish that moves `turn_look_cut_angle` (40 degrees) or more from the one it was drawn for, or an aim taken, a crouch,
lying down, a slide or an action ends it that frame; the momentum blend smooths the cut. Every one of these is read
when a turn begins, so a change in the inspector shows on the next turn (`test_turn_look_tuning.gd`). Cosmetic: never
sent; a puppet draws it from its own velocity and goal.

On foot the capsule faces where it goes at `turn_speed` (9 rad/s, the share of the turn left a second) and at most
`turn_rate_most` (400 degrees a second; `CharacterTuning.turn_facing`, shared with the AI's lean tick): simulation, so
the server and a predicting client turn it alike. From the press (gdstudio #1574, `test_turn_look_tuning.gd`'s
`TURNTIME` lines, the velocity answering on the first tick in every case):

| From the press | Half way round | Within 10 degrees of the new way | Before #1574 |
| --- | ---: | ---: | ---: |
| Jog reversal (W to S) | 0.35 s | 0.48 s | 0.12 s, 0.27 s |
| Sprint reversal (W to S) | 0.42 s | 0.57 s | 0.12 s, 0.27 s |
| Quarter turn of the keys (W+A to W+D, a steer) | 0.13 s | 0.28 s | 0.08 s, 0.17 s |

| Clip | Length | Its turn (from the plant) | On the clip's root (opt-in) | The look (default) |
| --- | ---: | ---: | ---: | ---: |
| `gds/Jog_Turn_180_*` | 2.90 s | 0.70 to 1.83 s | committed 1.83 s | 1.33 s of clip in 0.5 s (2.7 times) |
| `gds/Sprint_Turn_180_*` | 3.53 s | 0.97 to 2.23 s | committed 2.23 s | 1.47 s in 0.6 s (2.4 times) |
| `gds/Jog_Turn_90_*` | 2.73 s | 0.60 to 1.53 s | committed 1.53 s | 1.13 s in 0.4 s (2.8 times) |

The sprint reversal's turn comes in two parts over two contacts (about 75 degrees, a held stride in profile, then the
rest): sped up, the hold reads as the weight going over the planted foot for about 0.12 s. A look whose capsule faced
round faster than the clip leaves the drawn body up to 69 degrees behind the facing mid-turn (sprint) and 46 (jog),
back to under 3 at its end; nothing drawn follows the capsule's facing but the rig, which carries the offset.

The gait cycles they leave are 0.67 s (jog) and 0.60 s (sprint): each clip was four to six cycles long. A turn on the
spot (aiming while standing) is seeked by the body's turn, at most `transition_pace` (4 since #1565, 2 before) times
its pace. Starts are played by the ground the body covers (0.67 s from a walk, 0.83 from a jog, 1.1 from a sprint in
the matrix) and now end when the wish moves. The stops are not sped up: each stop deceleration covers its clip's
travel so the planted feet hold the floor (`test_gait_stops.gd`), and a faster stop would need shorter stop clips
(the sprint's 1.67 s to rest is a follow-up for the clip toolkit); any key ends a stop the next tick. Epic's Game
Animation Sample follows the capsule's own movement with its start, stop and turn clips, and its characters change
direction by about 85 degrees at once ([a thread on the sample's root motion and trajectory](https://forums.unrealengine.com/t/how-to-perfectly-align-animation-root-motion-with-the-movercomponents-trajectory/2746566),
[its 5.7 notes on responsiveness](https://www.unrealengine.com/en-US/tech-blog/explore-the-updates-to-the-game-animation-sample-project-in-ue-5-7));
Lyra warps the lower body's orientation to the movement rather than waiting for a clip
([adapting Lyra's animation](https://www.unrealengine.com/tech-blog/adapting-lyra-animation-to-your-ue5-game)).

**What it costs** (gdstudio #1569). In `tools/bench/gait_cost.tscn` each body stops and then walks off the other
way while it still moves. Before #1565 the clip's root carried that as a reversal: 2.7 a body a run, the tree in the
transition's single clip on 90 % of frames. Now it is a stop and a start picked by the tree (0.1 reversals a body, in
a transition on 41 % of frames), and the reversal look itself costs under 0.1 µs a character a frame. The bench's
figure (`on` less `off`, 40 players, headless Chrome) read 11 µs a character before #1565, 25 on main after it and
23 after #1569 (medians of three rounds; single rounds spread 10 to 40); headless on the desktop 17 on main and 11
after #1569 (three interleaved rounds, 10.6 to 13.9 against 16.6 to 20.4). Timed by part in the web build, the same
spans in each build and the tree by `advance()` in a span (median of 4 to 8 pairs, µs a character a frame):

| `on` less `off` | Script | Tree | Momentum blend |
| --- | ---: | ---: | ---: |
| Before #1565 | 10.8 | -9.3 | 6.5 |
| #1565 | 19.2 | -0.5 | 8.8 |
| #1569 | 14.3 | 0.9 | 8.1 |

The tree's row is the floor: a body in a transition draws one clip, one on the ground the four synced points of its
blend space, so the bodies parked in the root motion's clip drew 9 µs less tree than with the settings off, which no
change of code gives back short of parking them again. The momentum blend starts more often (a stop and a start where
one reversal was). What #1569 took off the script: the travel curves read packed and by halves (`GaitClips.Travel`,
3.0 to 1.5 µs a read on the desktop), the crouch space left unset while nothing draws it (`GaitBlend._crouch_drawn`,
`CROUCH_HOLD` 0.5 s after the last crouch), the planted-foot trim without its arrays and lambda, a moving body's turn
rejected from a dot product before the angle, and the tree's action parameter read only once a clip is picked (the
transitions) or while a start or a blend is under way (the momentum blend). Each draws the same bones
(`test_gait_cost_cuts.gd`: two bodies side by side, one setting every space, 0.000 mm apart).

- **Approach:** Set a drawn turn's pace by the time from the press to facing the new way, measured on the real input
  for each gait and a quarter turn, and draw it from the yaw shown on the frame before to the way asked, scaled along
  the clip's turn curve; put every number that shapes it on the character's tuning, read when the turn begins.
  **Watch out for:** a look sped up to 0.3 s turned the body round in 0.17 to 0.27 s, faster than a body can, and
  the clip's own 180 degrees added to a facing that had already turned (the tree saw the wish a frame or more late)
  overshot the way asked; an uncapped exponential facing turned a quarter of the keys half way in 5 ticks.
  **Seen:** gdstudio #1574, 2026-11-17, found by the maintainer playing 3D Third Person after #1566.
- **Approach:** Measure a drawn pose's jump between ticks in `skeleton_updated`, with each tick its own engine frame,
  and hold an action's hand-off from a clip against the same action from the steady gait. **Watch out for:** read
  after `advance()`, `get_bone_global_pose` gives the tree's pose without the modifiers (the momentum blend among
  them), and a hand-stepped skeleton draws once a frame, so six ticks a frame read a prone hand-off as 1.3 m in one
  tick and a crouch as 1 m; the drawn crouch from a stop still moved a toe 0.25 m a frame on main. Two more settle
  frames into the crouch alone fixed it (`CharacterGait.CROUCH_SETTLE`); five for every state moved the aimed
  take-off's blend past `test_aimed_takeoff.gd`'s bound. **Seen:** gdstudio #1565, 2026-11-15
  (`tests/fixtures/move_response.gd`).
- **Approach:** When an action's own clip moves a bone faster than the hand-off bound (a leg sweep), bound what the
  hand-off adds: each tick may move what the clip alone moves then, read from the clip played from rest, plus the
  bound; and check that reference starts on the drawn pose (its first ticks under 0.04 m). **Watch out for:** the
  bound above reads as a raw move a tick, and the to-prone clip moves a toe 0.33 m a tick, more than the crouch's
  whole bound, so no hand-off could pass it ([prone](moves.md#prone)). **Seen:** gdstudio #1568 (PR #1570),
  2026-11-15.

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
