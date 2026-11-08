+++
agent = "blender-artist"
kind = "blender"
deliver = ["barrel_textured.glb", "build.py", "preview.png"]
read = ["tools/blender/build-scripts.md#checks", "tools/blender/variants.md#modular-parts"]
+++

# UV and texture a barrel on the palette atlas

`barrel.glb` in this folder is a barrel with no UVs and no material. Texture it the way GDStudio's low-poly assets
are textured: one material whose base colour is the palette atlas `palette.png` (flat colour cells), every face
showing one cell's colour.

`palette.json` names the cells to use (column and row, row 0 at the top of the image):

- the staves (the side between and outside the bands): `wood`;
- the two metal bands (the side rings from 0.15 to 0.25 m and from 0.65 to 0.75 m high): `iron`;
- the top and bottom lids: `wood_dark`.

Do not change the geometry. Deliver, in this folder:

- `barrel_textured.glb`: the textured barrel, exported for Godot, with the atlas in it.
- `build.py`: the Blender script that makes it from `barrel.glb` and `palette.png`, run headless from this folder as
  `blender -b --factory-startup -P build.py -- --out <path>.glb`.
- `preview.png`: a render of the barrel you looked at, at least 512 px wide.

## The numbers it must meet

| Measure | Limit |
| --- | --- |
| Triangles | the same as `barrel.glb` |
| Bounds | within 1 mm of `barrel.glb` |
| Materials | exactly 1 |
| Base colour | an image texture that is `palette.png`, pixels unchanged |
| Texture filter | nearest (Closest) |
| Triangles with every UV inside 0 to 1 | 100% |
| Triangles whose UVs lie inside one cell, at least 1 px in from its edge | 100% |
| Triangles that show their part's colour | 100% |
| `build.py` | rebuilds the same triangle count |
| `preview.png` | at least 512 px wide |

`gds eval check uv-palette <this folder>` measures all of them through the pinned Blender. Work from the brief, not
from the check script.
