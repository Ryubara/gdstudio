# Prone and crawl clips

Four clips for a character that lies down and crawls, made by GDStudio from nothing (kit #1009) because the Universal
Animation Library has none. They are in `prone.glb`, which Godot imports as an `AnimationLibrary` the same way as
`assets/animation/universal/`: add it to an `AnimationPlayer` as the library `prone` and the clips are
`prone/Prone_Idle`, `prone/Crawl_Fwd`, `prone/Crouch_To_Prone` and `prone/Prone_To_Crouch` (the import drops `_Loop`
from a looping clip's name and makes it loop). The player scene does not hold the library yet: the prone stance
(kit #1012) adds it with the code that plays it.

| Clip in the file | Length | Loops | What it is |
| --- | --- | --- | --- |
| `Prone_Idle_Loop` | 3.0 s (90 frames) | yes | Lying on the belly, propped on the forearms, head up; one slow breath and a small drift of the head. |
| `Crawl_Fwd_Loop` | 0.933 s (28 frames) | yes | A low crawl: the right elbow and the left foot plant and the body is pulled over them, then the other pair. In place. |
| `Crouch_To_Prone` | 0.9 s (27 frames) | no | From frame 0 of `ual1/Crouch_Idle`: the hands reach for the floor ahead, the feet go back one after the other, the body settles on its forearms. Ends on frame 0 of `Prone_Idle_Loop`. |
| `Prone_To_Crouch` | 1.0 s (30 frames) | no | From frame 0 of `Prone_Idle_Loop`: the hands come back beside the chest and push, the knees draw under the body, the chest rises. Ends on frame 0 of `ual1/Crouch_Idle`. |

All four are at 30 frames a second, the library's rate, keyed on every frame, with no root motion (the game moves the
body), on the 65 bones of the Quaternius universal rig.

## Numbers for the code

Measured by the build on the female mannequin, the template's default (`build_prone_clips.py --report`):

- **Crawl speed: 0.618 m/s** at the clip's own rate. A planted elbow travels 0.30 m under the body in 52 % of the
  cycle; one cycle (two pulls) covers 0.577 m. Play the clip at `speed / 0.618` and nothing slides. A foot is planted
  for the first 30 % of its half of the cycle and then drags straight behind the body.
- **What is planted:** each forearm (elbow and hand) and each pushing foot stay within 0.1 mm of their place on the
  floor while planted. The knee is not planted: it rolls 7 cm outward as the leg straightens, as a real knee does.
- **Where the body lies:** the origin is under the middle of the lying body. Prone idle reaches 1.06 m ahead of the
  origin (the fingertips) and 1.03 m behind it (the toes); the crawl reaches 1.17 m ahead. The body is 0.55 m wide
  lying still, 0.71 m with a knee drawn up in the crawl and up to 0.94 m in the transitions (a knee goes out to the
  side as it bends under the body).
- **Height:** the top of the head is 0.50 m over the floor in the idle and at most 0.52 m in the crawl; the back and
  the hips stay under 0.31 m in the idle and 0.34 m in the crawl.
- **Transitions:** 0.9 s down and 1.0 s up at the clip's own rate; the hands land at 0.33 s going down and leave the
  floor at 0.47 s coming up. Both start and end on the exact poses they join, so no blend is needed at either end.
- **Backing up and turning:** there is no backward or turning clip. Play `Crawl_Fwd` backwards to back up, and turn
  the body while it plays to turn (the shipped games studied do the same or turn without a clip).

On the male mannequin the same clips play (the rig is the same), but his upper arms are 5 cm longer, so a planted
elbow rolls up to 3 cm and his thumb tips sit 2 cm lower. `tests/gameplay/test_prone_clips.gd` holds both models to
these numbers.

## Weapon

The clips are **weapon-free**: both hands lie flat on the floor and carry weight, so a weapon in the hand would be
dragged through the floor. The code holsters or hides the weapon while prone. A prone aim (the weapon held, per kit
`docs/tools/blender/weapons.md#hands-on-the-weapon`) would be a clip set of its own.

## How they are made

`build_prone_clips.py` solves every frame from a few targets (where the pelvis lies, how the spine arches, where each
elbow, hand and foot rests on the floor), keys the result on the female mannequin's armature in the pinned Blender and
exports the armature with a one-triangle stand-in mesh, so the file has a skin for Godot's `Skeleton3D` and no copy of
the mannequin. The chest rides on the planted elbows: the spine pitches and rolls by the amount that keeps each
shoulder one upper arm from its elbow. The only pose read from the library is frame 0 of `Crouch_Idle_Loop`, where the
transitions join. The build fails before it exports when a loop does not close, a planted joint slides, the body sinks
more than 2 cm into the floor or a transition misses the pose it joins.

```text
blender -b --factory-startup -P build_prone_clips.py -- --model <mannequin_female.glb> --library <ual1.glb> --out <prone.glb>
blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <prone.glb> --out <folder> --travel Crawl_Fwd_Loop=0.618
```

`render_clip_sheets.py` renders any clip file on either mannequin the way Godot plays it, from the side, the front and
the top. `tools/capture/prone_clips_tour.tscn` plays the four clips on the mannequin in Godot for a clip or stills.

## Where it comes from

The motion is GDStudio's own work, under this repository's licence; nothing in it is copied from another game, pack or
capture. The skeleton in `prone.glb` (bone names, parents and rest pose) is the Quaternius universal rig's, CC0, taken
from `assets/characters/mannequin/mannequin_female.glb` (its `LICENSE.md` has the source). The timing was set after
studying how shipped games and the army's low crawl are described (kit pull request of #1009).
