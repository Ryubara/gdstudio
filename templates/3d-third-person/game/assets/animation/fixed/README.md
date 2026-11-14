# Fixed library clips

Three clips of the Universal Animation Library put a forearm through a shin on the template's bodies (the prototype
`form` pair), whose shins and forearms are thicker than the Quaternius mannequins' the clips were keyed on. `fixed.glb`
holds those clips with that one arm swung clear; everything else in them is the library's. The game plays
`fixed/Slide_Exit` (`CharacterClips.SLIDE_EXIT`), and `fixed/Jump_Land` is the stand-in of GDStudio's own
landing (`gds/Land_Soft`, kit #1161); `CharacterClips.STAND_INS` names the
library clip each came from, for a game whose bodies the library's suit.

| Clip | From | Swung | Peak | Frames | form_female before, after | form_male | Quaternius female, male |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `Jump_Land` | `ual1` | left upper arm, out | 4.0 degrees | 6 to 19 of 38 | 6.6 mm, 0.0 | 0.0, 0.0 | 3.3 and 0.0, unchanged |
| `Slide_Exit` | `ual2` | right upper arm, out | 11.0 degrees | 2 to 14 of 15 | 11.1 mm, 0.0 | 1.0, 1.0 | 0.0 and 0.0, unchanged |
| `NinjaJump_Land` | `ual2` | left upper arm, out | 4.0 degrees | 6 to 19 of 38 | 12.2 mm, 0.0 | 0.0, 0.0 | 3.3 and 0.0, unchanged |

Two more clips, which the template does not play, passed one thigh through the other while the body turns a quarter
in two frames (kit #1320). There a leg is swivelled: turned about the line from its hip to its ankle, so the knee and
the thigh move and the foot does not, and the foot bone is keyed back to the library's turn. In `Sword_Dash` the left
upper arm is then swung 3 degrees, for the hand that was in the thigh on frame 4.

| Clip | From | Swivelled | Peak | Frames | form_female before, after | form_male | Quaternius female, male | Foot off the library's |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `Sword_Dash` | `ual2` | left leg | 34.0 degrees | 1 to 4 of 47 | 29.4 mm, 0.0 | 25.5, 0.0 | 8.0 to 2.4, 23.3 to 0.9 | 0.48 mm on the `form` pair, 0.0 on Quaternius's |
| `Sword_Heavy_Combo` | `ual2` | right leg | 28.0 degrees | 8 to 20 of 130 | 16.8 mm, 0.0 | 5.8, 0.0 | 0.0 and 11.0, unchanged | 0.18 mm, 0.0 |

The numbers are the deepest any body part is inside another on any frame, on the skinned mesh
(`../limb_overlap.py`, limit 5 mm). `fixed_clips.json` has them per clip and body with the swing on every frame and
the hash of the file measured; `tests/assets/test_fixed_clips.gd` fails when `fixed.glb` is not that file, when a
bone other than the swung one (and a swivelled leg's foot) differs from the library's clip, when the first or last
pose does, or when a swivelled leg's foot is 1 mm from the library's on a template body.

Build it with the pinned Blender, headless (under a minute; a rebuild writes the same bytes):

```sh
blender -b --factory-startup -P build_fixed_clips.py
```

To fix another clip, add it to `FIXES` in the script (the bone to swing, the bone at the limb's end, the way), add
its name to `CharacterClips.ALL` and `STAND_INS`, and rebuild. The build refuses a swing over 30 degrees: a limb that
far inside another needs its pose keyed again, not a correction. A leg that crosses the other leg with its foot on
the floor takes the way `swivel` (the thigh, its foot bone), up to 45 degrees; give a crossing in the clip's first
frames a short ease (`0, 3` after the way: no hold, three frames wide).
