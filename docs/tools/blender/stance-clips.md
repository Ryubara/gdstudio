# Crouch and stance clips

<!-- new section: animation.md's toolkit section reached the page's size limit; a crouch needs these -->

What making GDStudio's own crouch idle, crouch walk and the two stance changes taught (kit #1160), with the clip
toolkit of [Animation](animation.md#toolkit). The clips, their variants and their numbers are in the template's
`assets/animation/own/README.md`; what a gait's feet taught is on [Gaits](gaits.md#what-broke).

**The bodies.** Clips are solved on `form_female`, the body the template's player wears (`REFERENCE` in
`build_own.py`), and checked on `form_male` and the Quaternius pair as well (`BODIES`). A shipped file's deepest
limb crossing per clip and body is written beside it as `bodies_overlap.json` with the file's SHA-256 (and the
measure script's and each body's, kit #1479), which `tests/gameplay/test_own_clips.gd` reads. What one file
cannot do for two bodies is under [Clips on other proportions](mannequin-rig.md#proportions).

## What the toolkit gained for them {#toolkit-rows}

<!-- new section: animation.md is at its size limit, so the rows the crouch clips added live here -->

Rows of [the toolkit's table](animation.md#toolkit) that the crouch and stance clips added and prove (kit #1160:
both ends of a stance change within 0.2 mm and 0.09 degrees of the idles' first poses). The `ik_` targets are keyed
in every shipped clip since the reference body has them, and nothing in the game reads them yet.

| To | Use |
| --- | --- |
| Join another clip | `clips/joined.py` (`Joined`: the picked variant of another clip, its first frame as a spec and its solved pose), `Clip.meet` (the exact end poses, with the frames the difference is let go over) and `declared["joins"]`: the pose and the speed a first or last frame must meet |
| Hold or raise a heel | `Footfall.heel` for a foot that stands on its ball for a whole contact (the swing lands on it with the toes already bent), or `ContactPlan.raised(rig, side, frame, heel)` for a heel that moves; name the side in `declared["heel_up"]` so `clips.json`'s `flat` says no frame of it is flat. The foot is set down by the lowest of its own skin (the rig's `tread`), so the ball's joint may go down a few millimetres as the heel rises |
| Give each side its own pose | a pair `[left, right]` for every number of a description that a side could own (foot place and turn, heel, knee, each arm's numbers, each hand's curl), read with `AT[side]`; a description never shares one number between two limbs |
| Lay a forearm on a thigh | the arm's `rest` (`{"on": side, "gap": metres, "hand": metres}`): the arm comes down until its forearm's line is `gap` from that thigh's and shin's on every body, measured at each body's own joints; leave that arm out of `Clip.chains` |
| Step a foot inside a transition | two `Footfall`s of that side with the step between them (`clips/stance.py`, `stance_plan`): the plan swings the foot, and `toe_reach` clears the longest toes |
| Take a body down or up | `Clip.stretch` as a function of the frame; the weight check fails a drop over 1.05 of gravity with a foot down; `declared["ceiling"]` holds a crouched clip under its capsule on every body |

## What the crouch clips taught {#crouch}

<!-- new section: animation.md's toolkit section reached the page's size limit; a crouch needs these -->

- **Approach:** Time a move that lowers or raises the body from the fall of its centre of mass, and let the check
  refuse what gravity does not allow, before fitting it to a controller's number. **Watch out for:** the
  controller's `crouch_time` is 0.2 s and the crouch lowers the centre of mass 0.45 m, which a free fall takes
  0.30 s over; a 12-frame drop asked 1.33 of gravity and a 12-frame rise had to stop at 1.6 of it. **Seen:**
  gdstudio #1160, 2026-11-11 (fix: `checks.FALL` with its self-test; the shortest drop is 13 frames, the rise 14).
- **Approach:** Check a crouched pose against the capsule on every body before tuning how it looks, and fold the
  spine before the hips. **Watch out for:** the first crouch stood 1.26 m tall in a 1.1 m capsule; tipping the
  pelvis to lower it turned the thigh 143 degrees from its rest (the limit is 125); the male mannequin's head is
  24 mm higher in the same pose, and his longer forearm was 30 mm inside a thigh the female's cleared.
  **Seen:** gdstudio #1160, 2026-11-11 (fix: `declared["ceiling"]`, the pelvis tipped 12 degrees under an 80
  degree fold, the arms hung forward).
- **Approach:** Write a held pose from how a person rests in it, one side at a time: read the clip it replaces
  from the front, the side and above, write down what each foot, knee, hip, shoulder and hand does, and give every
  number a side could own a value per side (a pair in the description and the style files). **Watch out for:** the
  first crouch shared one `heel`, `knee_out`, `arm_swing` and `elbow` between both sides and stood on the standing
  idle's feet so that no foot had to move, so it was a level squat with its hands hung evenly and failed review;
  a variant that changes only timing and amplitude is the same stance three times. **Seen:** gdstudio #1160
  (PR #1285), 2026-11-11, a maintainer correction (fix: pairs in `clips/crouch_idle.py` and `crouch_walk.py`, a
  right foot a step behind on its ball, a forearm on a knee, three stances, a Godot test that the pose is no
  mirror).
- **Approach:** Measure a limb that rests on another on every body's own joints (`Solver._joint_on`), and leave it
  out of the overlap pass. **Watch out for:** a forearm laid 105 mm from the reference body's thigh line was 49 mm
  inside the male mannequin's thigh, whose longer legs put the knee elsewhere; the overlap pass then trailed the
  resting forearm 14 mm into the shin whatever the gap asked for, and the same number came back four builds running
  before the pass was suspected; a hanging arm's `clear` opens the arm on one frame as a thigh passes it, which
  reads as a pop on a landing frame. **Seen:** gdstudio #1160 (PR #1285), 2026-11-11 (fix: `rest` reads each
  body, resting arms are not in `chains`, the walk carries both arms outside the thighs).
- **Approach:** Film a review clip in a game made from the branch (`gds template test <template> --suite <one
  suite> --keep`, then `gds capture frames --project game` in the kept folder), and count the frames it wrote.
  **Watch out for:** the template's own `game/` folder has no kit addons, so the capture scene did not parse
  (`AudioSettings` not declared) and Movie Maker still wrote 300 frames of an empty scene; an import there
  rewrote three `.exr.import` files. **Seen:** gdstudio #1160, 2026-11-11.
- **Approach:** Read the audit's planted rows on a review sheet beside the build's own (`planted` in the report,
  which uses the declared contacts), and say in the variant's notes when they differ and why. **Watch out for:**
  `audit_clips.py` calls a foot planted while its lowest vertex is within a fifth of the swing's lift of the floor
  (6.2 mm here); on the `form` body the frame before each landing is 6.0 mm up, so two variants read 38 and 41 mm of
  wander and a planted speed 5 % low where the declared contacts wander 2.2 mm. **Seen:** gdstudio #1160
  (PR #1285), 2026-11-11 (fix: the sheet's `sole wanders in its declared contacts` rows and a note per variant).
- **Approach:** Hold an imported clip's planted joints in Godot to what the import gives on each body, measured
  once and written beside the limit, and hold the skin against the floor with `BodyMeasure.feet_lowest`.
  **Watch out for:** the file's own keys keep a planted joint within 0.2 mm, and compressed tracks add up to
  1.1 mm at a foot under a pelvis that travels 73 mm (1.5 mm on a body whose hips or shins differ by a millimetre);
  a 1 mm limit fitted to one build failed on the next with nothing wrong in the clip. **Seen:** gdstudio #1160
  (PR #1285), 2026-11-11 (`PLANTED`, `BALL_SINKS` and the skin test in `test_own_clips.gd`).
- **Approach:** After rebuilding a shipped clip, and again after every merge of main into the branch that rebuilds
  it, search the game for numbers measured on that clip's pose and measure them again; run the whole template suite,
  not only the clip suites. **Watch out for:** this branch rebuilt `Idle` on the form body while main (#1256)
  measured `Weapon.no_muzzle_offset` on the old `Idle` and tightened its test from 50 mm to 5: each side passed alone
  and the two together put the aimed muzzle 6.2 mm from the offset, so the pull request's check went red in a weapon
  suite no clip change had touched. **Seen:** gdstudio #1160 (PR #1285), 2026-11-12 (the offset measured again:
  0.2 mm off; and once more after #1262 moved the pistol's seat, 6 mm off until measured).
- **Approach:** Before pushing a merge, fetch again and run the suites main added since the last merge on the branch's
  clips; a test that reads a pose (the head on the neck, a muzzle, a hand) was fitted to the clip main plays.
  **Watch out for:** main (#1353) landed a head test between this branch's local run and its push: on the library's
  crouch the aimed head rolls under 8 degrees on the neck, on our crouch, whose shoulders turn 17 degrees over a trunk
  folded 84, it reads 15.4 while level in the world, so 240 assertions failed in CI only. **Seen:** gdstudio #1160
  (PR #1285), 2026-11-12 (fix: `AimLayer.head_crouch_neck_share`, 0.5: 10.9 each; the crouch's limit is 12).
