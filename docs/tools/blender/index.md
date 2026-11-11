# Blender

How GDStudio uses the pinned Blender (`gds tool path blender`, always headless `-b -P script.py` for anything
repeatable) to clean, make and export assets for Godot. Each topic gets a page once someone learns something about it.

**Belongs here:** modelling, UV and texturing, materials, baking, rigging, animation, optimisation and export in
Blender, with the scripts that repeat them. **Not here:** how Godot imports and uses the result
([Godot](../../engines/godot/index.md)).

**Third-party art is a stage.** Games lean on CC0 kits for now (Deadnight on Quaternius's Toon Shooter kit), credited
on the Credits screen and with a licence entry. The plan, much later, is GDStudio's own art. So when an agent builds
or changes art, it records the measured style (proportions, palette, silhouettes, triangle counts) in the game's docs,
which will guide the original assets, and it prefers generated or original work where that costs the same. Nobody
starts a replacement effort unasked. Animation is the first one asked for: every clip the template plays gets a
replacement of our own ([Our own animation set](own-animation.md), kit #1150).

Each stage of making an asset has a page; the asset classes and the tooling have theirs.

| Stage or topic | Page |
| --- | --- |
| Measuring the style, scale, bevels, kitbashing, origins, normals, building with bmesh | [Modelling](modelling.md) |
| The palette atlas, faces on swatches, bands and patterns | [UV and texturing](uv-and-texturing.md) |
| The atlas material, what survives the export, palette imports, baking | [Materials](materials.md) |
| One skeleton per body type, joints, weights, sockets, checking a rig | [Rigging](rigging.md) |
| Clip conventions, keyframes, actions and slots, clip export | [Animation](animation.md) |
| Triangle budgets per class, decimation, levels of detail, fewer meshes | [Optimisation](optimisation.md) |
| glTF flags, axes, shared atlases, reading a glb back, checks after the import | [Export to Godot](export.md) |
| Running build scripts, rebuilding committed files, the checks a build makes | [Build scripts](build-scripts.md) |
| Cleaning Quaternius characters and exporting their clips for a shared animation library | [Rig sharing](rig-sharing.md) |
| Locomotion clips from a kit's Run, at a known ground speed | [Gaits](gaits.md) |
| The plan to own every clip: the library's clips measured, the research, the set, checks, variants and review | [Our own animation set](own-animation.md) |
| Modular kit pieces, props, stairs and backdrops for a map | [Modular kits](modular-kits.md) |
| Character variants, clothes and modular parts on one rig | [Variants](variants.md) |
| Weapons in the kit's style: axes, sockets, hands, budgets | [Weapons](weapons.md) |
| Rendering app icons and key art from the game's own models with Cycles | [Key art and icons](key-art.md) |

The `blender-artist` agent is measured on these pages by five small tasks with numbers to meet
([Agent evals](../../studio/agent-evals.md)).
