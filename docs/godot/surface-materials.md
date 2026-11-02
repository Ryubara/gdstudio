# Surface materials in Compatibility

How to paint a level built from CSG boxes (a greybox) with textures that stay cheap on the Compatibility renderer and
WebGL2, learned on Deadnight's drive-in lot (its issue #217; the shader and the generator are in that game's
`game/assets/lot/` and `tools/world/build_lot_textures.py`). The game's own numbers (tints, tile sizes) are in its
style bible; this page is how Godot behaves.

## What works

| Need | Do | Why |
| --- | --- | --- |
| A pattern at true scale on boxes of any size, no UVs | a small spatial shader that projects in world space onto the face's own plane: in `vertex()`, take the world position and normal, pick the dominant axis, pass `plane / metres_per_tile` as a varying | A `CSGBox3D`'s UVs do not grow with its size. A box face is flat, so the axis picked per vertex is the same across the face and the projection is exact; neighbouring boxes share one grid and line up |
| Flat toon colour with a pattern | a greyscale texture (lightest tone near 250 of 255, seams 100-150) times a `source_color` tint uniform | One texture serves every colour: the lot has 8 textures for 30 materials, and the colour stays the palette's, which matches a flat-colour kit |
| Matte and cheap | `render_mode diffuse_lambert, specular_disabled;` (and `specular_mode = 2` on a flat `StandardMaterial3D`) | No specular term per light per pixel |
| Paint on the ground (parking lines, road dashes) | one `MultiMeshInstance3D` of a thin `BoxMesh` per set, written as `transform_format = 1` and a `buffer` of 12 floats per instance (basis rows, each followed by its origin) | One draw call for a hundred lines, no collision, nothing for a navigation bake. `Decal` is documented as Forward+ and Mobile only |
| Texture cost | 256 x 256 greyscale PNG, lossless, mipmapped | the lot's 8 textures are about 12 KB of PNG together |

## What did not

- **`StandardMaterial3D` world triplanar** (`uv1_triplanar`, `uv1_world_triplanar`) gives the same picture with no
  code, but reads the texture three times a pixel and blends. In the web build under Chromium's software renderer
  (SwiftShader, fill-rate bound) a night frame went from 79 to 90 ms on average (two runs each, main against the
  branch). See [Measured](#measured) for the shader.

## Pitfalls

- **State every texture import; turn Detect 3D off.** Set `detect_3d/compress_to=0` and spell out
  `compress/mode` and `mipmaps/generate` in every texture `.import`. With Detect 3D on (the default), the first
  editor session switches a texture used in 3D to VRAM compression with mipmaps, which a headless import never does,
  so the `.import` files change on the maintainer's machine and the colours shift. Palettes: lossless, no mipmaps;
  tiling textures: lossless, mipmaps (or the far ground aliases). Check it in pre-commit and CI.
- **Two floors at the same height flicker** where they overlap (z-fighting). With flat colours nobody noticed; with
  patterns it shows. Give the overlapping floors the same material (both world-projected, so they agree pixel for
  pixel) or move one.
- `metallic` above 0 only darkens a surface when there is nothing to reflect (no sky, no reflection probe): keep
  ground and walls at metallic 0.

## Measured

Deadnight's web export in Chromium (`tools/web_smoke/smoke.py`: 1280 x 720, a 45 s night from the start, frame time
from `requestAnimationFrame`), the software renderer (SwiftShader), each build run twice and alternated with main:

| Build | Night frame, mean of the two runs | p95 (median of samples) |
| --- | --- | --- |
| main: flat-colour `StandardMaterial3D`, roughness 1 | 79 / 83 ms (two pairs of runs) | 100-117 ms |
| `StandardMaterial3D` world triplanar, roughness 1 | 90 ms | 117 ms |
| the lot shader: one read, Lambert, no specular | 68 ms | 100 ms |

The shader is cheaper than the flat colours it replaced: dropping the specular term saves more than the one texture
read costs. SwiftShader is a CPU rasteriser, so these are relative numbers for a fill-bound device, not what a
graphics card shows; the menu (no 3D) held 38-40 ms in every run, which is the run-to-run noise.
