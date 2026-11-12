# Prone and crawl clips

Four clips for a character that lies down and crawls, made by GDStudio from nothing (kit #1009) because the Universal
Animation Library has none. They are in `prone.glb`, which Godot imports as an `AnimationLibrary` the same way as
`assets/animation/universal/`: add it to an `AnimationPlayer` as the library `prone` and the clips are
`prone/Prone_Idle`, `prone/Crawl_Fwd`, `prone/Crouch_To_Prone` and `prone/Prone_To_Crouch` (the import drops `_Loop`
from a looping clip's name and makes it loop). The player scene does not hold the library yet: the prone stance
(kit #1012) adds it with the code that plays it.

| Clip in the file | Length | Loops | What it is |
| --- | --- | --- | --- |
| `Prone_Idle_Loop` | 3.0 s (90 frames) | yes | Lying on the belly, propped on the forearms, which point inward and rest on their outer edges, the hands closed into fists near the centre line in front of the head, the right a little ahead; one slow breath and a small drift of the head. |
| `Crawl_Fwd_Loop` | 0.933 s (28 frames) | yes | A crawl on the forearms, the body kept low: the right elbow and the left foot plant and the body is pulled over them, then the other pair. Each forearm lands pointing inward on its outer edge, its fist in front of the head and ahead of the other fist. In place. |
| `Crouch_To_Prone` | 0.9 s (27 frames) | no | From frame 0 of `gds/Crouch_Idle` (our own crouch, `../own/`, since kit #1160): the open hands reach for the floor ahead and catch the body, the feet go back one after the other, and as the elbows come down the forearms roll onto their outer edges and the hands close. Ends on frame 0 of `Prone_Idle_Loop`. |
| `Prone_To_Crouch` | 1.0 s (30 frames) | no | From frame 0 of `Prone_Idle_Loop`: the fists open and the hands come back beside the chest, push on flat palms, the knees draw under the body, the chest rises. Ends on frame 0 of `gds/Crouch_Idle`. |

All four are at 30 frames a second, the library's rate, keyed on every frame, with no root motion (the game moves the
body), on the 65 bones of the Quaternius universal rig.

## Numbers for the code

Measured by the build on the female mannequin, the template's default (`build_prone_clips.py --report`):

- **Crawl speed: 0.618 m/s** at the clip's own rate. A planted elbow travels 0.30 m under the body in 52 % of the
  cycle; one cycle (two pulls) covers 0.577 m. Play the clip at `speed / 0.618` and nothing slides. A foot is planted
  for the first 30 % of its half of the cycle and then drags straight behind the body.
- **What is planted:** each forearm (elbow and fist) and each pushing foot stay within 0.1 mm of their place on the
  floor while planted. The knee is not planted: it rolls 7 cm outward as the leg straightens, as a real knee does.
- **Where the body lies:** the origin is under the middle of the lying body. It reaches 0.96 m ahead of the origin
  lying still (the fists), 1.07 m while the open hands land going down and 1.03 m behind it (the toes); the crawl
  reaches 1.08 m ahead. The body is 0.59 m wide lying still, 0.72 m with a knee drawn up in the crawl and
  up to 0.96 m in the transitions (a knee goes out to the side as it bends under the body).
- **Height:** the top of the head is 0.49 m over the floor in the idle and at most 0.52 m in the crawl; the back and
  the hips stay under 0.30 m in the idle and 0.34 m in the crawl.
- **The arms:** a planted forearm points 40 degrees inward of straight ahead in the crawl (29.5 in the idle), with
  the elbow 8.5 cm outside its shoulder and the wrist 7 cm from the body's centre line (12.5 cm in the idle), the
  knuckles on the centre line. A fist plants 0.29 m ahead of the other, and the swinging forearm opens to 14
  degrees so its fist passes outside the planted one. Why these numbers: the research below.
- **Forearms on their outer edge, hands in fists:** a resting forearm is rolled 45 degrees onto its outer edge (the
  little finger's side down, the thumb's side up, the palm facing down and in toward the other arm) and its hand is
  a fist in line with it, the thumb wrapped outside the index and middle fingers. The weight is on the forearm's
  edge near the elbow and on the fist's edge, not on a flat palm: a forearm turned palm down is twisted as far as
  it goes and a flat hand bends the wrist back, which nobody keeps up for long. The elbow joint is 4.1 cm and the
  wrist joint 6.6 cm over the floor; the female's forearm and fist skin press 0.6 and 1.2 mm into it. A carried
  fist loosens by an eighth. The fist is one pose for both mannequins, set between their hands: on the female no
  finger is more than 1.3 mm into another piece of the hand (the thumb on the index finger) and the fingertips are
  1 to 5 mm short of the palm; on the male the fingertips are 2 to 2.6 mm in the palm and the thumb 4 mm off the
  fingers.
- **Transitions:** 0.9 s down and 1.0 s up at the clip's own rate; the hands land at 0.33 s going down and leave the
  floor at 0.43 s (the left) and 0.47 s (the right) coming up. Both start and end on the exact poses they join, so
  no blend is needed at either end. Going down, the open hands land flat (0.30 to 0.40 s), lift 4 cm and close while
  the forearms roll (0.40 to 0.63 s); coming up, the fists open between 0.10 and 0.23 s on the way to the push.
- **Nothing passes through anything:** on every frame of the four clips, on both mannequins' skinned meshes, no part
  of the body is more than 5 mm inside another (0.0 mm everywhere but the male's left knee against his upper arm
  going down, 0.8 mm on one frame), and the female's lowest vertex is 1.4 cm under the floor (a shoulder in the
  crawl, where the chest presses on the ground); her hands are never more than 2.7 mm under it (the flat palms in
  the transitions).
- **Backing up and turning:** there is no backward or turning clip. Play `Crawl_Fwd` backwards to back up, and turn
  the body while it plays to turn (the shipped games studied do the same or turn without a clip).

On the male mannequin the same clips play (the rig is the same), but his upper arms are 5 cm longer and his limbs
thicker, so a planted elbow rolls up to 3 cm and he lies in the floor: the build measures his forearms 3.7 cm (lying
still) to 4.4 cm (crawling) and his fists 2.3 to 3.0 cm under it, and his thighs and shins about 3 cm (with flat palms
the forearms were 4.3 to 4.6 cm and the hands 3.1 to 3.5 cm under). One clip file cannot rest both bodies on the
floor; a set solved on his own body would (kit #1090). `tests/gameplay/test_prone_clips.gd` holds both models to the
bone numbers, the forearms' roll and the fists.

## Weapon

The clips are **weapon-free**: both hands are fists on the floor and carry weight, so a weapon in the hand would be
dragged through the floor. The code holsters or hides the weapon while prone. A prone aim (the weapon held, per kit
`docs/tools/blender/weapons.md#hands-on-the-weapon`) would be a clip set of its own.

## How they are made

`build_prone_clips.py` solves every frame from a few targets (where the pelvis lies, how the spine arches, where each
elbow, hand and foot rests on the floor), keys the result on the female mannequin's armature in the pinned Blender and
exports the armature with a one-triangle stand-in mesh, so the file has a skin for Godot's `Skeleton3D` and no copy of
the mannequin. The chest rides on the planted elbows: the spine pitches and rolls by the amount that keeps each
shoulder one upper arm from its elbow. The only pose read from another file is frame 0 of our own `Crouch_Idle_Loop`
(`../own/locomotion.glb`, kit #1160; the library's until then), where the transitions join: its right foot stands a
step behind the left on its ball, and is lifted the rest of the way back and forward, not slid. The build fails before
it exports when a loop does not close, a planted joint slides, the body sinks more than 2 cm into the floor, a
transition misses the pose it joins, a part of the body goes more than 5 mm into another on either mannequin
(`../limb_overlap.py`, the check the template's clip builds share), a hand of the female goes more than 5 mm under the
floor on any frame, or the fist does not fit on either mannequin (a finger piece more than 3 mm inside the palm or
another finger, or the thumb more than 5 mm off the fingers: `fist_numbers`, on the mesh's own pieces). The report
(`--report`) has every frame's lowest hand and forearm vertex on both mannequins (`floor_mm`) and the fists' fit
(`fist_mm`).

```text
blender -b --factory-startup -P build_prone_clips.py -- --model <mannequin_female.glb> --male <mannequin_male.glb> --library <../own/locomotion.glb> --out <prone.glb>
blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <prone.glb> --out <folder> --travel Crawl_Fwd_Loop=0.618
blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <prone.glb> --out <folder> --clip Crawl_Fwd_Loop --travel Crawl_Fwd_Loop=0.618 --views top --scale 1.35 --ahead 0.6 --frames 15 --wrap 5 --tile 420x360
```

`render_clip_sheets.py` renders any clip file on either mannequin the way Godot plays it, from the side, the front and
the top; the third line is the close-up of the arms from above over one cycle, and `--range 12-24` spreads the
frames over a part of a clip. `tools/capture/prone_clips_tour.tscn` plays the four clips on the mannequin in Godot
from the side, the front quarter, the game camera's place and close over the arms, for a clip or stills
(`PRONE_FISTS=<folder>`: one sheet of the forearms and fists at five moments of the crawl and in the idle, from the
game camera's place, the side, the front and above; `MODEL=male` for the other mannequin).

## How people crawl (the research behind the arms)

Read before the arms were reworked (kit pull request #1020): the first version had the right limbs moving together
and the right speed, but both forearms pointed almost straight ahead, shoulder-width apart, which nobody does.

| Source | What it says |
| --- | --- |
| US Army, low and high crawl (FM 21-75, 1984, chapter 3; task 071-326-0502 of STP 21-1-SMCT; an ROTC course text that restates them, <https://www.uakron.edu/armyrotc/MS1/9.pdf>) | Low crawl: the body flat; both arms pushed forward and one leg drawn up together, then a pull with both arms and a push with that leg; legs switched when tired. High crawl: the trunk off the ground on the forearms and lower legs, knees kept behind the buttocks; the right elbow moves with the left knee, then the left elbow with the right knee. |
| Skvortsov, Anisimov and Aizenshtein, Experimental Study of Military Crawl as a Special Type of Human Quadripedal Automatic Locomotion, Applied Sciences 11(16), 7666, 2021 (<https://doi.org/10.3390/app11167666>): eight adults crawling 4 m on their bellies, optical motion capture | A cycle takes 2.2 s (plus or minus 0.8) and covers 1.2 m at 0.5 m/s. The other side starts half a cycle later (48 to 52 %). Seen from above, the knee bends through 117 degrees and the hip through 79, both peaking at 33 to 36 % of the cycle; the elbow bends through about 90 degrees and the shoulder through 75 to 78, peaking at 51 to 59 %: the arm of a side follows its own leg by about a fifth of a cycle, so it moves with the other side's leg. The shoulder line turns against the hip line by up to 56 degrees, one way at 32 % and the other at 79 %. |
| Vitali, Cain, Davidson and Perkins, Human crawling performance and technique revealed by inertial measurement units, Journal of Biomechanics 84, 2019 (<https://doi.org/10.1016/j.jbiomech.2018.12.030>): 33 people on a military obstacle course | The fast crawlers use a diagonal gait: an arm and the opposite leg move together. The slow ones have longer cycles and looser coupling. |
| Patrick, Noah and Yang, Interlimb Coordination in Human Crawling Reveals Similarities in Development and Neural Control With Quadrupeds, Journal of Neurophysiology 101, 2009 (abstract) | Adults on hands and knees pair the diagonal limbs like a trot; at low speeds the four limbs move at even intervals. |
| Twelve public-domain photographs of soldiers in the low and the high crawl on Wikimedia Commons (search: low crawl soldier, high crawl soldier; among them four soldiers side by side in a 25 m high crawl and a low crawl sequence of three), kept in the workspace's reference folder | Every one has the elbows outside the shoulders and the forearms pointing inward, 45 to 80 degrees from the body's long axis, the hands or fists under the chin on the centre line. The reaching arm's hand lands in front of the face, across the centre line or on it; the pulling arm's forearm ends lying nearly across under the chest. One hand is always ahead of the other. Nobody has parallel forearms. |

What the clips take from it:

| What | In people | In the clips |
| --- | --- | --- |
| Forearm to the body's long axis | 45 to 80 degrees inward on the planted arm (photographs) | 40 degrees planted in the crawl, 29.5 in the idle: a stronger angle with wider elbows put the forearm 5 to 11 mm into its own shoulder at the end of the pull and the chest 2 cm into the floor on this rig |
| How far the hands come in | fists under the chin, on the centre line or across it | wrist 7 cm from the centre line, knuckles on it (crawl); wrists 12.5 cm out, knuckles 6 cm short of it (idle) |
| How the forearm and hand rest | the forearm on its outer edge, the thumb's side up, the hand a fist or closed on the weapon (four of the photographs looked at again for the hands, eleven soldiers: none has a palm flat on the ground) | rolled 45 degrees onto the outer edge, the hand a fist in line with the forearm, the thumb outside |
| One hand past the other | the reaching hand lands ahead of the other, in front of the face | a hand plants 0.29 m ahead of the other (the whole stride), and passes outside it on the way, the forearm opened to 14 degrees |
| Which limbs move together | an elbow with the opposite knee (high crawl, the fast crawlers, the motion capture) | the right elbow with the left foot, then the other pair, half a cycle apart |
| The elbow's path | lifts a few centimetres, travels forward outside the shoulder, lands ahead of it and stays put while the trunk passes over it, ending beside the ribs | lifts 5 cm, swings 3 cm outward, lands 17 cm ahead of the shoulder and 8.5 cm outside it, stays put for 52 % of the cycle and ends 13 cm behind the shoulder |
| Stride and time | 1.2 m and 2.2 s a cycle, 0.5 m/s, in people who do not practise it | 0.58 m and 0.93 s, 0.618 m/s: a shorter, quicker pull, since the forearm is planted whole (a person also slides the hand); the game slows the clip for a slower crawl |

## Where it comes from

The motion is GDStudio's own work, under this repository's licence; nothing in it is copied from another game, pack or
capture. The skeleton in `prone.glb` (bone names, parents and rest pose) is the Quaternius universal rig's, CC0, taken
from `assets/characters/mannequin/mannequin_female.glb` (its `LICENSE.md` has the source). The timing was set after
studying how shipped games and the army's low crawl are described (kit pull request of #1009).
