# Turn clips

<!-- new section: start-stop-clips.md is the toolkit for a clip that changes speed along a straight line; a clip whose
root turns (a reversal, a pivot, a turn on the spot) needs its travel, its lean and its review told otherwise, and what
making the first ten taught had no page (kit #1157) -->

What making GDStudio's own reversals, pivots and turns on the spot taught (kit #1157), with the clip toolkit of
[The clip toolkit](clip-toolkit.md#toolkit) and the feet of the starts and stops
([Start and stop clips](start-stop-clips.md#description)). The clips, their variants, their research and their
numbers are in the template's `assets/animation/own/README.md`; the plan they belong to is
[Our own animation set](own-animation.md#waves). One description, `clips/turns.py`, makes all ten.

## How a clip whose root turns is described {#description}

<!-- new section: the root's place and yaw are curves of their own, and the body is posed in the root's frame and put
on the floor; the next turning clip (a curved run, a landing into a turn) starts from this -->

- **The root is a velocity and a facing, apart.** A turn on the spot gives `Turn._root_curves` a speed and a heading;
  a reversal or a cut gives `Turn._root_vectors` a velocity on the floor and the way the body faces as two curves
  (kit #1442), since a reversal faces side-on and back while it still travels the old way. Both are integrated on
  a tenth-of-a-frame grid that runs well past both ends; `Travel(forward, left, turn)` carries them into the build,
  which takes them out (`plan.unroot`) and writes both curves into `clips.json`, and the game reads the place from
  `travel` and the facing from `turn` separately.
- **A change of way spends the old momentum on a plant.** The velocity is the old way's and the new way's mixed by a
  curve (`brake_from`, `stop_at`, `brake_shape`) that is half and half late in the plant's contact (for a reversal,
  where the body stands still), so the mass is carried on over the planted leg before the body goes the new way; a
  reversal comes back on a lane beside its way in (`lane`), toward the turn.
- **The body is posed in the root's frame and put on the floor.** A description builds the spec as if the root were
  at the origin facing +z (the gait's spec at the clock's frame, or the idle's), adds the lean, and `placed` turns
  and moves it: the pelvis's place, and the yaw of the pelvis, the chest and the head (the solver's turns are from
  the standing rest, yaw outermost, so a yaw adds). Feet come from the treads, already in the world.
- **The lean is the root's acceleration in the way it faces**: ahead and to its left, each `atan(a / g)` through a
  spring, with its own shares for the pelvis, the chest and the head; while a plant brakes, most of the lean back is
  taken out and the trunk is carried the old way instead (`carry`, `carry_cut`), which the weight check's side lean
  then reads as a declared limit.
- **The head leads.** The chest's and the head's yaw are the root's a few frames ahead (`chest_lead`,
  `head_lead`) plus the overlap pass's lag, which would otherwise make them trail the hips through a turn.
- **A turn on the spot steps on the idle's own places, turned.** Each step lands a foot where the idle has it with
  the body turned by a share of the angle, its ball carried round the root's middle in the air (`_spot_swing`), so
  the trailing foot goes round in front of the standing one instead of through it.

## What the toolkit gained for them {#toolkit-rows}

<!-- new section: the rows these clips added to the toolkit's table live with the clips that prove them -->

| To | Use |
| --- | --- |
| Check the lean of a body whose root turns | `check_weight` reads the acceleration from the travel's place in the root's frame (`checks._turning_accel`) once the travel turns, not from the change of its speed; the lean into the bend is held to `declared["side_lean_limit"]` over a step, as the forward lean is to `lean_limit` |
| See a turn on the review sheet | a shot's `root` (`[x, z, yaw]`) in `review_render.py`: the character is put on a floor that stays still and the camera follows its place, so the strip shows the turn as the body makes it |
| Pick a reversal in the game | `GaitTransitions` picks a reversal by the side the body turns to (`r` when it turns right), since a reversal turns over the foot it plants and is named for it |

## What the turns taught {#taught}

<!-- new section: the mistakes made on the first clips whose root turns, for the curved runs and landings that follow -->

- **Approach:** Keep a planted foot's contact short while the hips turn over it, and spread the turn over several
  contacts and the flights between them; read every contact's wander on every template body, not only the one the
  clip is solved on. **Watch out for:** the jog reversal's plant stood 15 frames (the studies' 0.5 s) while the hips
  turned 120 degrees over it, and its sole wandered 2.5 mm on `form_female` and 8.3 mm on `form_male`: his hip
  joints are 3 mm closer together than hers, the clip is solved on her, and a hip that swings round a planted foot
  carries that difference round with it (3 mm times the turn in radians, on top of the gait's own 2 mm). An 8-frame
  plant with the turn spread from 14 frames before the slowest moment to 20 after reads 4.2 mm. **Seen:** gdstudio
  #1157, 2026-11-13.
- **Approach:** Give every contact at speed no more frames than the ground a leg can span (the root covers at most
  about 0.9 m while a foot is down), and print each tread's covered ground beside its frames before reading any
  check. **Watch out for:** a braking step held for 11 frames at 4 m/s left the foot 1 m behind the body: the ankle
  was 83 mm out of reach, the pelvis was lowered to the 0.3 m cap and the centre of mass dropped at 3.7 of gravity.
  **Seen:** gdstudio #1157, 2026-11-13 (the `feet` line of `declared` carries the covered metres).
- **Approach:** Measure a turning clip's lean against the acceleration in the root's own frame, forward and to the
  side. **Watch out for:** the weight check took the acceleration as the change of the root's speed, which is the
  same whichever way the root goes: through a reversal it reads a body slowing and then speeding up straight ahead,
  and a bend at a steady speed reads no acceleration at all. **Seen:** gdstudio #1157, 2026-11-13 (fix:
  `checks._turning_accel`; a clip whose root does not turn is read as before, and every earlier file rebuilds to
  the same bytes).
- **Approach:** Turn a reversal over its plant foot: the clip that plants the left foot turns left, round it, and is
  named for that foot. **Watch out for:** the first reversal planted the left foot and turned right, away from it, so
  the swinging right leg had to cross in front of the planted one: 45 mm of calf in calf on every body. **Seen:**
  gdstudio #1157, 2026-11-13 (`GaitTransitions` picks the reversal by the turn's side, `r` for a right turn).
- **Approach:** Keep each foot on its own side of the root's middle line through a bend, at least a few centimetres
  out (`own_side`), and read the thighs on every body once the steps are placed. **Watch out for:** steps placed
  from where a steady step lands, moved by the lean into the bend, crossed the middle line in the pivot, and the
  thighs folded into each other as the hips turned over them. **Seen:** gdstudio #1157, 2026-11-13.
- **Approach:** Set a plant foot turned by a share of the root's turn over its contact (`plant_turn`, about 0.6),
  and try the share both ways before reading any other number. **Watch out for:** a plant foot set as it came in
  left the hips to turn the whole way over a still foot and twisted its thigh into the other; set turned the whole
  way, it pointed the knee across the body the other way. Both put a thigh in the other. **Seen:** gdstudio #1157,
  2026-11-13.
- **Approach:** On a turn on the spot, land the steps before each foot's last one wider than the idle's places
  (`apart`, 0.08 to 0.09 m), and let only the last step land on the idle's own place. **Watch out for:** steps that
  all landed on the idle's circle, turned, put the foot that went round in front within a foot's width of the
  standing one, and the calves and the thighs met on every body. **Seen:** gdstudio #1157, 2026-11-13.
- **Approach:** Start the swing a clip begins inside as the joined gait's own leg and let it go for the clip's
  landing over the swing (`Turn.leg`), and keep every push the description adds to a swing at 0 on frame 0; measure
  the step every bone takes over the first and the last frame against the joined clip's, not only the pose there.
  **Watch out for:** the build's join check read the first pose (0.0 mm) and passed, while frame 1 stepped 97 to
  135 mm off the gait's: the swing in the air at frame 0 was rebuilt toward the clip's own wider landing and pushed
  clear of the standing foot, so the foot jumped sideways between the first two frames. Only the Godot suite
  (`test_own_turns.gd`), never run before the hand-over, caught it. **Seen:** gdstudio #1157, 2026-11-13.
- **Approach:** Cap how fast the tree may run a turning clip to catch up with the body (`transition_pace`), since
  the controller turns far faster than a person. **Watch out for:** a 180 degree reversal played by the angle
  turned ran its 1.13 s of turn in the controller's 0.26 s. **Seen:** gdstudio #1157, 2026-11-13.
- **Approach:** Build a reversal as four phases: the hips go side-on (`side_on`, about 75 degrees), the outside foot
  plants well ahead and stays down long (16 frames at a jog; 18 at a sprint, after three braking steps), the trunk
  is carried the old way over it while it brakes (`carry`, 30 to 44 degrees), and only then does the body turn and
  push off. **Watch out for:** the first reversals turned early and neatly round the inside foot, with no sideways
  shift, no plant ahead and no carried lean, and read as unnatural (this replaces the entry above that turned a
  reversal over its plant foot); a carry over about 44 degrees, or a plant over 0.12 m past the root's stop, folds
  the ankle past its 55 degree cone. **Seen:** gdstudio #1442, 2026-11-13, from the maintainer's review.
