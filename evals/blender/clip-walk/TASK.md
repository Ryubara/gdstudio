+++
agent = "blender-artist"
kind = "blender"
deliver = ["walk.glb", "build.py", "preview.png"]
read = ["tools/blender/rig-sharing.md#what-broke", "tools/blender/build-scripts.md#rebuilding"]
+++

# Animate a walk cycle

`humanoid_rigged.glb` in this folder is a blocky 1.8 m humanoid skinned to a 17-bone armature (`hips`, `spine`,
`chest`, `neck`, `head`, and `upper_arm`, `forearm`, `hand`, `thigh`, `shin`, `foot` with `.L` and `.R`), in a T-pose,
facing -Y in Blender (+Z in glTF and Godot), its left side on +X. Animate one looping walk cycle for it: an in-place
clip a game plays while it moves the character itself, at 24 frames a second.

Deliver, in this folder:

- `walk.glb`: the rig, the mesh and the one clip, named `walk`, exported for Godot.
- `build.py`: the Blender script that makes it from `humanoid_rigged.glb`, run headless from this folder as
  `blender -b --factory-startup -P build.py -- --out <path>.glb`.
- `preview.png`: a contact sheet of the clip's frames, side view, that you looked at, at least 512 px wide.

## The numbers it must meet

| Measure | Limit |
| --- | --- |
| Clips in the file | exactly one, `walk` |
| Length | 1.0 s (0.98 to 1.02) |
| Loop seam: every bone's pose on the first and the last frame | within 1 degree and 2 mm |
| In place: the hips' travel in x and y | at most 2 cm |
| Hips bob up and down | 2 to 8 cm |
| Each thigh's forward and back swing, peak to peak | at least 30 degrees |
| The thighs swing in opposite phase | correlation at most -0.7 |
| The left arm's swing, peak to peak | at least 10 degrees |
| The arms swing against the legs (left arm with the right thigh) | correlation at least 0.5 |
| The arms hang down from the shoulder (mean downward share of the upper arm's direction) | at least 0.7 |
| Lowest vertex over the clip | not below -1 cm |
| Frames with a foot on the floor (lowest vertex within 2 cm of it) | at least 90% |
| `build.py` | rebuilds the same clip and length |
| `preview.png` | at least 512 px wide |

`gds eval check clip-walk <this folder>` measures all of them through the pinned Blender. Work from the brief, not
from the check script.
