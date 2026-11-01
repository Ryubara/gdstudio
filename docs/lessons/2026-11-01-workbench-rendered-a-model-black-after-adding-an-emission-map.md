# Workbench rendered a model black after adding an emission map

2026-11-01

- **Saw:** a model rendered solid black on Workbench contact sheets (texture colour), only its glowing lens coloured;
  Godot showed it correctly.
- **Cause:** Workbench's texture colour shows the material's active image node, and the emission map's node, added last,
  became active; the glTF importer can make it active again on re-import.
- **Fix:** make the node feeding Base Color active before rendering.
- **Docs:** [Character variants](../blender/variants.md#a-boss-on-the-shared-rig).
