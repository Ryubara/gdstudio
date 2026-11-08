# Merging meshes at runtime, and what a build costs

Many small props of one material drawn as one mesh, built when the scene is built: Deadnight's prize crane merges a
tiny model of every weapon in its pool (each weapon's far level) into one `ArrayMesh`, and its fixed boxes into one
mesh per material (Deadnight #830). Godot 4.7.2, Compatibility renderer, measured on a desktop (RTX 5080).

## What works

- **Copy the surfaces yourself.** `mesh.surface_get_arrays(i)` gives positions, normals, UVs and indices (or none);
  move positions by the transform and normals by its basis' inverse transposed, offset the indices, and add one
  surface with `add_surface_from_arrays`. `SurfaceTool.append_from` refuses surfaces whose formats differ, and imported
  models do not all carry the same attributes.
- **One material for the lot.** Models that share an atlas (every face on one swatch) take the atlas with the most
  cells; a duplicate of the models' own material with that texture adds no shader (the texture is not part of it).
- **Share it through the engine's cache, not a `static var`.** A `static var` that holds a resource is still holding
  it at exit, and the engine prints leaked meshes, materials and textures. Give the built mesh a made-up path
  (`take_over_path("res://<folder>/pile_<hash>")`) and look for it with `ResourceLoader.has_cached` and
  `get_cached_ref`: the cache holds it only while something uses it.
- **Do not reach into a class with static state just for a constant.** Reading `PlayerAnimation.HOLDS_DIR` loaded the
  animation script and the clips it keeps, and a tool that used it leaked them at exit; name the constant locally and
  keep a test that the two agree.

## What a build costs

| Step | Cost |
| --- | --- |
| `load()` of a resource already in the cache | about 0.9 ms (100 calls: 87 to 92 ms): load each once per build |
| `ResourceLoader.exists()` | 0.07 to 0.17 ms |
| A small glb scene, first load / instantiate | 3 ms / 0.02 ms |
| The crane (8 near models, 8 far levels merged, boxes merged) | 60 ms the first time, 15 ms with its models cached |

## Pitfalls

- A `SphereMesh` is 64 x 32 segments by default (about 4,000 triangles). As a `CPUParticles3D` mesh it is multiplied
  by the particle count: 36 sparks were 145,000 triangles. Give particles a box or a low sphere.
- `gdformat` run through `uvx` on Windows wrote CRLF into the files it reformatted; a later scripted replace then
  matched nothing. Convert back (`sed -i 's/\r$//'`) before editing by script.
