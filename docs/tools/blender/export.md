# Export to Godot

<!-- new section: the glTF export flags were only given for rigs (rig-sharing.md); nothing gave them for static models,
the axes, shared atlases or what to check after the import -->

How a GDStudio asset leaves Blender for Godot: glTF, from a script, with flags that depend on what the file holds, and
an import in Godot that is checked, not trusted. How Godot then uses the model is on
[Godot](../../engines/godot/index.md); running and rebuilding the scripts is on [Build scripts](build-scripts.md).

## The export flags {#gltf-settings}

| Flag | Static model (prop, kit piece, weapon) | Rigged character |
| --- | --- | --- |
| `export_format` | `GLB` for one self-contained file; `GLTF_SEPARATE` for a family sharing one atlas | `GLB` |
| `export_yup` | `True` | `True` |
| `use_selection` | `True`: only what the build made | `True` |
| `export_apply` | `True`: modifiers applied | `False`: the Armature modifier stays |
| `export_materials` | `"EXPORT"` | `"EXPORT"` |
| `export_keep_originals` | `True` with `GLTF_SEPARATE`: every file points at the one palette PNG | |
| `export_image_format` | `"AUTO"`: a PNG atlas goes in as PNG, its pixels unchanged | `"AUTO"` |
| Animation | | `export_animation_mode="NLA_TRACKS"`, `export_force_sampling=True`, `export_def_bones=False`, `export_leaf_bone=False`, `export_optimize_animation_size=False` |

`export_materials="PLACEHOLDER"` keeps the material slots (one surface per slot) and writes no material: Godot gets
the surfaces with no named material, so a game that builds the materials itself (a realistic character's, whose
maps glTF cannot describe) matches each surface by its mesh's node name (gdstudio #1151).

Deadnight's props, map pieces and helicopter use `GLTF_SEPARATE` with `export_keep_originals=True`, so a dozen models
load one palette image once; its characters, zombies and weapons are GLB. The rig flags and why each is set are on
[Rig sharing](rig-sharing.md); the clip export on [Animation](animation.md#export).

## Axes and scale {#axes}

Blender is Z up and glTF Y up; with `export_yup` a Blender point (x, y, z) arrives in Godot at (x, z, -y). A model
facing -Y in Blender faces +Z in Godot, and an empty's +Y points along Godot's -Z, which is how a `Muzzle` empty points
down the barrel ([Weapons](weapons.md#attachment-points)). Apply the object transform before export (scale 1, rotation
0), so the node Godot makes has no transform of its own; a raw kit file instead arrives as `RootNode/...` at scale 100
([Rig sharing](rig-sharing.md)).

## Shared atlases in Godot {#shared-atlas}

- **Approach:** For a family of models on one atlas, map the glTF material to one external `.tres` in each
  `.glb.import` (`_subresources`, `use_external`) and set `gltf/embedded_image_handling=0`. **Watch out for:** left at
  the defaults, seven zombie variants imported seven identical atlas PNGs and seven materials, so nothing was shared.
  **Seen:** Deadnight #128, 2026-11-01 (fix: every variant's `.import` names `zombie_atlas.tres`; remap again if a
  rebuild renames the material).

The palette PNGs Godot extracts or loads are imported lossless and without mipmaps
([Materials](materials.md#palette-imports)).

## After the import {#import-checks}

Import the exported file with the pinned Godot, headless, and read the output for `ERROR`; then check in Godot what the
game relies on: node names, the surface count and material, the bones and clips. Compare a rebuilt model by its nodes,
vertex buffers and triangle set, never by bytes, since the exporter does not keep the triangle order
([Build scripts](build-scripts.md#rebuilding)). Models are Git LFS files: `git show` of one prints its pointer, and a
pointer imported as a model leaves a broken `.import` behind ([Build scripts](build-scripts.md#rebuilding)).

- **Approach:** Give a new glb that holds only clips `importer="animation_library"` in its `.import` (the Import dock's
  "Import As: Animation Library") before the commit, as the template's other clip files have. **Watch out for:**
  Godot imports a new glb as a scene by default, so the clips sat in a scene nothing loads as a library and the
  player found no animation under the library's name. **Seen:** gdstudio #1090 (PR #1113), 2026-11-11
  ([the libraries](../../engines/godot/third-person/character.md#animation-libraries)).

## Reading a glb back in Blender {#reimport}

A script that measures or rebuilds from an exported file reads it back with Blender's glTF importer, which does not
give back what was exported: vertices are split at every hard edge and UV seam (weld them before anything that reads
the topology, [Optimisation](optimisation.md#decimation)), bone tails are guessed ([Rigging](rigging.md#joints)), and
an armature brings an extra object. An older revision of a model is read through `git show <rev>:<file> | git lfs
smudge`, never `git show` alone, which gives the LFS pointer ([Build scripts](build-scripts.md#rebuilding)).

- **Approach:** After importing a file with an armature, take the meshes skinned to it (an Armature modifier pointing
  at the rig) instead of every mesh in the scene, or delete the collection `glTF_not_exported`. **Watch out for:**
  Blender 5.2's importer adds an `Icosphere` of radius 1, unparented, as every bone's custom shape, so a lowest-vertex
  or triangle count over the scene's meshes reads a sphere reaching 1 m under the floor. **Seen:** gdstudio #774,
  2026-11-07 (fix: the `clip-walk` baseline run deleted it; the eval checks read only skinned meshes); the Blender
  model duel, 2026-11-10 (an entry's triangle count of its rigged character counted the sphere).

## In the evals {#eval}

Every Blender eval ([Agent evals](../../studio/agent-evals.md)) is judged on the exported glb, read back through
Blender's importer: what Godot gets, not the `.blend`.
