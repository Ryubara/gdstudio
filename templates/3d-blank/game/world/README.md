# world

Maps, levels and lighting: `world/<map>/` for each map, `world/lighting/` for the sun and sky rigs a map instances.

- `world/prototype/prototype_level.tscn` is the template's level: a 50 m floor and four 4 m walls on the prototype grid,
  with a sun, a sky and baked bounce light. Build in it, or copy it for a new map. Its lightmap
  (`prototype_level.lmbake`) is baked: after moving or resizing a piece, select the `LightmapGI` node and press "Bake
  Lightmaps" (in the Forward+ editor, the project's default). Only the editor can build a mesh's lightmap UVs, so a
  piece you add needs a mesh saved with UV2 (a script that adds meshes at run time gets no baked light).
- `world/lighting/graphics_profile.gd` turns on what only Forward+ draws; it does nothing on the web build.
- May use `core/`; never `ui/`.
