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
starts a replacement effort unasked.

| Topic | Page |
| --- | --- |
| Cleaning Quaternius characters and exporting their clips for a shared animation library | [Rig sharing](rig-sharing.md) |
| Rendering app icons and key art from the game's own models with Cycles | [Key art and icons](key-art.md) |
