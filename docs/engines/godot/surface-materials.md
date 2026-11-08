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

## Re-skinning a model that is already painted

Learned on Deadnight's re-cut weapon skin (its issue #787): a look that has to sit on every model, present and future,
with no texture work, and must not cost a draw call.

- **Swap the surface's material, never overlay it.** `MeshInstance3D.set_surface_override_material(i, shader_material)`
  puts the skin where the model's own material was: one surface, one draw call, as before. `material_overlay` draws
  every surface a second time (a weapon of 6 surfaces is 12 calls), and the phone's budget is draw calls. Keep the old
  override (usually null) and put it back to take the skin off; the imported mesh's own material is never touched.
- **Read the model's material, do not ask the model for anything.** A glTF palette material imports as a
  `StandardMaterial3D` with `albedo_texture`, `albedo_color`, `metallic` and `roughness`; copy those into uniforms of the
  skin shader (`palette : source_color, filter_nearest`) so the skin keeps the swatches (a grip still reads as a grip) and
  the metal the model had until the skin changes it. Skip a surface whose material is transparent or a shader of its own
  (a lens, a glow); a mesh with a `material_override` of its own is left alone.
- **Draw the pattern from the model's coordinates, not its UVs** (a palette's UVs are swatches). In `vertex()` pass
  `(to_root * vec4(VERTEX, 1.0)).xyz` and `mat3(to_root) * NORMAL` as varyings, with `to_root` a `mat4` uniform the
  caller sets from the node's transform up to the model's root, so a pattern runs across the whole weapon and not from
  each child mesh's origin. Pick the pattern's plane by the dominant axis of the model normal.
- A `Transform3D` goes into a `mat4` uniform as `Projection(transform)`; read it back with `Transform3D(projection)`.
- **Check every parameter name you set against `Shader.get_shader_uniform_list()`** in a test: `set_shader_parameter`
  with a name the shader does not have is silent.
- A new shader is a new GL program the first time it is drawn: draw one skinned copy of every model on the warm-up stage
  ([first-use hitches](first-use-hitches.md)).
- A GdUnit4 checkout lives only in the main repository's `game/addons/gdUnit4` (excluded from git); a worktree has to
  copy that folder to run suites there.

## Pitfalls {#pitfalls}

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

- **Approach:** Check the `.import` settings of every new 3D texture in review. **Watch out for:** a headless import
  left new textures without mipmaps, so the far ground aliased. **Seen:** Deadnight, 2026-11-01 (fix: looking at the far
  ground in a capture showed it; the import settings to keep are listed above).

## Measured {#measured}

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

- **Approach:** Measure the frame time of the web build for every material or lighting change. **Watch out for:** the
  world triplanar materials slowed the web frame from 79 to 90 ms, which a desktop run does not show. **Seen:**
  Deadnight, 2026-11-01 (fix: a frame-time measurement in the browser caught it).
