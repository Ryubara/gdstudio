# Fixed library clips

Three clips of the Universal Animation Library put a forearm through a shin on the template's bodies (the prototype
`form` pair), whose shins and forearms are thicker than the Quaternius mannequins' the clips were keyed on. `fixed.glb`
holds those clips with that one arm swung clear; everything else in them is the library's. The game plays
`fixed/Jump_Land` and `fixed/Slide_Exit` (`CharacterClips.LAND`, `SLIDE_EXIT`); `CharacterClips.STAND_INS` names the
library clip each came from, for a game whose bodies the library's suit.

| Clip | From | Swung | Peak | Frames | form_female before, after | form_male | Quaternius female, male |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `Jump_Land` | `ual1` | left upper arm, out | 4.0 degrees | 6 to 19 of 38 | 6.5 mm, 0.0 | 0.0, 0.0 | 3.3 and 0.0, unchanged |
| `Slide_Exit` | `ual2` | right upper arm, out | 11.0 degrees | 2 to 14 of 15 | 11.1 mm, 0.0 | 1.0, 1.0 | 0.0 and 0.0, unchanged |
| `NinjaJump_Land` | `ual2` | left upper arm, out | 4.0 degrees | 6 to 19 of 38 | 12.3 mm, 0.0 | 0.0, 0.0 | 3.3 and 0.0, unchanged |

The numbers are the deepest any body part is inside another on any frame, on the skinned mesh
(`../limb_overlap.py`, limit 5 mm). `fixed_clips.json` has them per clip and body with the swing on every frame and
the hash of the file measured; `tests/assets/test_fixed_clips.gd` fails when `fixed.glb` is not that file, when a
bone other than the swung one differs from the library's clip, or when the first or last pose does.

Build it with the pinned Blender, headless (about four minutes; a rebuild writes the same bytes):

```sh
blender -b --factory-startup -P build_fixed_clips.py
```

To fix another clip, add it to `FIXES` in the script (the bone to swing, the bone at the limb's end, the way), add
its name to `CharacterClips.ALL` and `STAND_INS`, and rebuild. The build refuses a swing over 30 degrees: a limb that
far inside another needs its pose keyed again, not a correction. `Sword_Dash` and `Sword_Heavy_Combo` are that case
(their thighs pass through each other while the body turns) and are not here.
