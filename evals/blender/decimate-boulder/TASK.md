+++
agent = "blender-artist"
kind = "blender"
deliver = ["boulder.glb", "build.py", "preview.png"]
read = ["tools/blender/build-scripts.md#checks", "tools/blender/variants.md#modular-parts"]
+++

# Decimate a boulder into two levels of detail

`boulder_high.glb` in this folder is a sculpted boulder of 20,480 triangles, far too heavy for a web game. Make
the two meshes the game draws: a near level for gameplay distance and a far level, keeping its shape, its flat
bottom and its one material.

Deliver, in this folder:

- `boulder.glb`: two mesh objects, `boulder_lod0` (near) and `boulder_lod1` (far), in place over each other, exported
  for Godot.
- `build.py`: the Blender script that makes them from `boulder_high.glb`, run headless from this folder as
  `blender -b --factory-startup -P build.py -- --out <path>.glb`.
- `preview.png`: the high poly and both levels side by side, that you looked at, at least 512 px wide.

## The numbers it must meet

| Measure | `boulder_lod0` | `boulder_lod1` |
| --- | --- | --- |
| Triangles | at most 2,000 | at most 500 |
| Mean distance of the high poly's surface from it, over the bounding-box diagonal | at most 0.3% | at most 0.8% |
| Largest distance either way, over the diagonal | at most 2% | at most 4% |
| Bounds off the high poly's, over the diagonal | at most 1% | at most 1% |
| Lowest vertex | 0 (within 5 mm) | 0 (within 5 mm) |
| Area facing against the high poly's surface | at most 0.5% | at most 0.5% |
| Open edges | 0 | 0 |
| Materials; object scale | 1; 1 | 1; 1 |

Also: exactly those two mesh objects in the file, `build.py` rebuilds the same triangle counts, and `preview.png` is
at least 512 px wide.

`gds eval check decimate-boulder <this folder>` measures all of them through the pinned Blender. Work from the brief,
not from the check script.
