# Start and stop clips

<!-- new section: own-animation.md plans the starts and stops and clip-toolkit.md is the toolkit as the loops left
it; what a clip that changes speed needs of the toolkit, and what making the first twelve taught, had no page
(kit #1156) -->

What making GDStudio's own starts and stops of the walk, the jog and the sprint taught (kit #1156), with the clip
toolkit of [The clip toolkit](clip-toolkit.md#toolkit). The clips, their variants, their research and their numbers
are in the template's `assets/animation/own/README.md`; the plan they belong to is
[Our own animation set](own-animation.md#waves). One description, `clips/moves.py`, makes all twelve: a start or a
stop is a gait's table, a foot and a style's numbers.

## How a clip that changes speed is described {#description}

<!-- new section: a transition that travels is written differently from a loop and from a stance change; the next
one (a pivot, a reversal, a landing into a run) starts from this -->

- **The root's speed is the first input.** A start's speed is a body falling forward over its feet (its
  acceleration is `g / h` times how far the centre of mass is ahead of where the feet press, up to what stepping
  feet can keep up), scaled until the gait's speed is reached at a frame the style names; a stop's braking comes on
  at once, holds and eases. The root is still on the idle's frame and at the gait's speed on the gait's, which the
  join check reads from the travel (`first_speed`, `last_speed`).
- **The footfalls are the second.** A style gives each step's frames and how long each foot outlasts the next
  landing (`steps`, `air`: under 0 is a flight). The last two landings of a start are the gait's own contacts,
  placed from where the gait's root would be, and the first contact of a stop is the gait's; the last two landings
  of a stop are the idle's own places. Every foot has stepped at least once between the two clips, since an idle's
  foot stands wider and turned out otherwise than a gait's lands. The steps between are the clip's own: where a
  steady step at the root's speed would land, moved back or ahead by the acceleration's lean, no further than a
  leg reaches (`reach_fore`, `reach_back`), with foot numbers mixed from a slow step's to the gait's (`gait_like`).
- **The body is mixed on a clock.** The pelvis over the root, the trunk, the arms and the hands go from the
  shipped idle's first frame to the shipped gait's spec at the gait's frame the feet are in. That frame is a clock
  that passes through every landing at the landing foot's own frame of the cycle, so each arm keeps swinging with
  the other side's leg while the steps are not yet the gait's.
- **The ends are the joined clips' own specs.** `spec(0)` and `spec(frames)` return the idle's and the gait's
  spec with the root moved, not the mix, so the poses meet by construction and `Clip.meet` has only the overlap
  pass's remainder to take out (0.0 mm and 0.09 degrees in the build's check on every one of the 36 variants).
- **Left and right are two solves.** `moves.family(kind, start)` returns the clip on the left foot and the one on
  the right from one description; neither is the other's mirror, because the idle and the gaits have a number per
  side ([no mirror poses](own-animation.md#feel)).

## What the toolkit gained for them {#toolkit-rows}

<!-- new section: the rows these clips added to the toolkit's table live with the clips that prove them, as the
crouch's do on stance-clips.md -->

| To | Use |
| --- | --- |
| Begin a clip inside a gait | `Clip.lead`: frames before frame 0 that are solved for the overlap pass and dropped (`spec` is asked for frames under 0), so the arms and the chest are already trailing on the first frame |
| Hold a stepping body's lean to its acceleration | `declared["lean_over"]` (the frames of a step) and `lean_limit`: `check_weight` reads, on each frame, the range of lean the soles on the floor can hold (from over the foremost point down to over the rearmost) and fails when the acceleration's lean is outside it by more than the limit over a step |
| Make a family of clips of one type | `FAMILIES` in `build_own.py`: `review <type>` builds every member under every letter into one review file, one letter of `picks.json` picks them all, and each member has its own name in the group's frozen list |
| Name the frame a join meets | `declared["join_names"]`: `{"first": "Idle", "last": "Walk", "last_frame": 13}`; `clips.json` carries it as `joins` |
| Say where the game may cut | an event `free` in `Clip.events` |

## What the starts and stops taught {#taught}

<!-- new section: the mistakes made on the first clips that change speed, for the pivots, reversals and landings
that follow -->

- **Approach:** Copy a loop's seam pose with every table it carries (`local` and `places`), and compare a loop's
  first and second frame for every keyed bone, the `ik_` targets too, after any change to how the root's travel is
  taken out. **Watch out for:** `build_clip` copied a loop's first pose for its seam and the two shared one `places`
  table, so `unroot` took the travel out of it twice: the shipped walk, jog, sprint and crouch walk had their four
  `ik_` targets a stride (1.47 m in the walk) behind on frame 0 and on the last frame. Nothing in the game reads
  the targets yet and the seam test compares a loop's last pose with its first, which were wrong alike; a start
  that joins the walk's first pose found it, 1473 mm off. **Seen:** gdstudio #1156, 2026-11-12 (fix: the copy in
  `build.build_clip` and `retarget`, as kit #1161 wrote it; the four loops rebuilt).
- **Approach:** Shape a start's speed as a body can make it (a fall forward over the feet that grows with the
  distance fallen), give the schedule the frames that needs, and read the lean check before looking at the clip.
  **Watch out for:** the first speed curve was an ease from rest to the walk's speed in 26 frames with its hardest
  push in the middle: 4 m/s2 while the centre of mass was 6 cm ahead of the only foot on the floor, a lean of 3
  degrees for an acceleration that needs 22. **Seen:** gdstudio #1156, 2026-11-12 (fix: `Move._travel`; the
  grounded walk start takes 32 to 35 frames and reads 7 to 8 degrees off over a step).
- **Approach:** Check a stepping body's lean over a step and against everything the soles can press on
  (`lean_over`), and declare a limit per clip with the reason in the variant's notes. **Watch out for:** the weight
  check compared each frame's lean, measured from the ball of the foot, with the acceleration's: a body walking at
  a steady speed is 24 degrees behind its foot as the heel lands and as far ahead as the toes leave, and a body
  standing still reads 6 degrees back, so no clip with a step in it could pass at 5. **Seen:** gdstudio #1156,
  2026-11-12 (the check had been proved on made-up motion only).
- **Approach:** Clamp where a step may land by what a leg reaches from the root, and cap any pass that moves the
  pelvis until a constraint holds. **Watch out for:** feet placed a full `h * a / g` behind the body at 7 m/s2
  were 0.8 m back, half a metre out of reach, and the pass that lowers the pelvis until the legs reach ran twelve
  rounds and put the body 1.2 m under the floor. **Seen:** gdstudio #1156, 2026-11-12 (fix: `reach_fore`,
  `reach_back`, the cap in `Move.settle`; the hips come down with the lean by `lean_low` instead).
- **Approach:** Keep a contact at speed as short as the gait's (4 frames at 6.5 m/s cover 0.87 m), run the
  gait's clock at the gait's pace through a flight, and give the clip's own steps only a share of the gait's rise
  and fall (`bob`). **Watch out for:** a brake step held for 6 frames at 6 m/s covered more ground than two legs
  span; a clock pinned to both ends of a one-frame flight raced through four frames of the gait in one, and both
  upper arms turned 2 to 5 degrees on that landing frame by themselves; with the clock eased, the gait's take-off
  was played while the foot was still down and the centre of mass dropped at 1.4 of gravity. **Seen:** gdstudio
  #1156, 2026-11-12 (fix: `Move._clock`, `bob`, and a guard in `Move.settle` that smooths the height where the drop
  passes 0.9).
- **Approach:** Open the arms from the body while the hips are low (`arm_wide`), and run the limbs check on the
  Quaternius female before tuning anything else: her hips are the widest. **Watch out for:** every one of the 36
  variants passed every numpy check and 30 of them had a hand 6 to 41 mm inside a thigh in Blender; an arm's
  `clear` keeps the hand from the thigh's line as the body stands, and a thigh folded forward under a low pelvis is
  not there. **Seen:** gdstudio #1156, 2026-11-12 (0 failures after `arm_wide`).
- **Approach:** Fade every correction a pass adds (a lowering, a smoothing) to nothing over the frames beside a
  join, and measure the step each bone takes over the join's frame against the joined clip's step, not only the
  pose. **Watch out for:** the reach guard's lowering was smoothed over five frames and reached frame 1 of the
  sprint stop: the pose at frame 0 was the gait's to the bit and the pelvis left it 14 mm a frame faster than the
  gait moves, a pop the join check does not read. **Seen:** gdstudio #1156, 2026-11-12 (1.2 mm after the fade;
  `tests/gameplay/test_own_moves.gd` holds the step to 12 mm on the imported clips).
- **Approach:** Import the library with 32 KiB compression pages, as the jump's clips do
  ([animation libraries](../../engines/godot/third-person/clips.md#animation-libraries)), and compare every bone
  of every new clip, imported, with the same file read uncompressed before any test of planted feet.
  **Watch out for:** with 8 KiB pages the import held `Idle_To_Walk_L`'s pelvis place still from frame 13 to 26
  while the file's keys were right, and the planted-foot tests read 46 mm and 31 mm for that one clip, which looks
  like a fault of the clip. The import bakes a key a frame, so only fewer tracks make it smaller: 289,356 bytes
  for 43.7 s at 32 KiB (6.6 KB a second; 286,880 at 64), 275,564 without the hands'
  `ik_` targets, over 6 (the plan's 7 now).
  **Seen:** gdstudio #1156, 2026-11-12 (`tests/gameplay/test_own_moves.gd`'s
  `test_the_import_keeps_every_start_and_stop_s_motion`).
