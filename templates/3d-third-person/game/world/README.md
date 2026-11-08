# world

Maps, levels and lighting: `world/<map>/` for each map, `world/lighting/` for the sun and sky rigs a map instances,
`world/blocks/` for the solid pieces a map is built from.

- `world/prototype/prototype_level.tscn` is the template's level: build in it, or copy it for a new map. Its
  lightmap (`prototype_level.lmbake`) is baked: after moving or resizing a block, select the `LightmapGI` node and
  press "Bake Lightmaps" (in the Forward+ editor, the project's default).
- `world/blocks/proto_block.tscn` is a box, cylinder, ramp or staircase made from one `size`, with collision.
- `world/lighting/graphics_profile.gd` turns on what only Forward+ draws; it does nothing on the web build.
- May use `core/`; never `ui/`.
