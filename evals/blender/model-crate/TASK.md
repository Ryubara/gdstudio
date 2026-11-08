+++
agent = "blender-artist"
kind = "blender"
deliver = ["crate.glb", "build.py", "preview.png"]
read = ["tools/blender/build-scripts.md#checks", "tools/blender/modular-kits.md#building-props"]
+++

# Model a supply crate

Model a wooden supply crate for a low-poly toon shooter: chunky shapes, soft bevels, flat colours, read from a
shoulder camera a few metres away. It has a visible frame or planks, not a plain cube.

Deliver, in this folder:

- `crate.glb`: the crate, exported for Godot.
- `build.py`: the Blender script that makes it, run headless from this folder as
  `blender -b --factory-startup -P build.py -- --out <path>.glb`. It writes the same crate to `--out`.
- `preview.png`: a render of the crate you looked at, at least 512 px wide.

## The numbers it must meet

| Measure | Limit |
| --- | --- |
| Mesh objects in the file | exactly 1, named `crate` |
| Triangles | 120 to 500 |
| Materials | 1 or 2 |
| Size on each axis | 0.98 to 1.02 m |
| Origin | at the bottom centre: lowest vertex at 0 (within 5 mm), bounds centred on x and y (within 1 cm) |
| Object transform | applied: scale 1, rotation 0 |
| Open edges, degenerate faces, inside-out shells | 0 each (after welding glTF seam splits) |
| Volume over bounding-box volume | 0.60 to 0.97 (a plain box is 1.0) |
| `build.py` | rebuilds the same triangle count and size (within 1 mm) |
| `preview.png` | at least 512 px wide |

`gds eval check model-crate <this folder>` measures all of them through the pinned Blender. Work from the brief, not
from the check script.
