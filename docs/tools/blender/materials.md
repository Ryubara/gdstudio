# Materials

<!-- new section: the material settings sat in the weapons page's build notes; nothing said which material an asset gets,
what survives the glTF export, or why GDStudio bakes no textures -->

The material a GDStudio asset carries in Blender, chosen so that the glTF export gives Godot a `StandardMaterial3D`
that looks the same: one Principled BSDF per asset family, its base colour from the palette atlas
([UV and texturing](uv-and-texturing.md)). Godot's side (surface materials, imports) is on
[Surface materials](../../engines/godot/surface-materials.md).

## One material per family {#atlas-material}

| Setting | Value | Why |
| --- | --- | --- |
| Shader | Principled BSDF | the one node the glTF exporter maps whole |
| Base Color | an Image Texture of the family's atlas, interpolation **Closest** | exports as a nearest-filtered sampler; the cells stay sharp |
| Roughness | 0.415 | the kit's value on every material |
| Metallic | 0.4 on weapons, 0 on props, map pieces and vehicles | 0.4 reads dark at night, with nothing to reflect |
| Backface culling | on | the review renders show inside-out faces |

In Blender 5 every new material already has a node tree: `Material.use_nodes` is deprecated and warns on the pinned
5.2. Make the Image Texture node the active node, or a Workbench preview renders the model black
([Variants](variants.md)). The kits' own files carry 2 to 4 flat-colour materials per asset and a few left at Blender's
default grey: converting one is a palette remap to the nearest cell, not a copy of its materials (Deadnight's style
bible).

## What survives the export {#export}

The exporter writes the Principled BSDF's base colour (factor and texture), metallic, roughness, normal map, emission
and alpha; other nodes in front of them are dropped or baked to nothing. An emissive part works: a black emission map
lit only at the glow cell, Emission Strength above 1, exports as `emissiveTexture` with
`KHR_materials_emissive_strength`, and Godot 4.7.2 imports it with emission on, still one material
([Variants](variants.md)). In the game, Deadnight mostly makes glow in Godot instead, with an emission texture laid out
like the atlas on a copy of the material ([Weapons](weapons.md#palette-cells-in-godot)).

Some kit weapons carry a vertex colour attribute (`COLOR_0`); Blender's importer then routes the base colour through a
vertex-colour node and leaves the socket at its 0.8 default, so a script that reads the material's colour reads the
wrong value. Read `baseColorFactor` from the glTF JSON instead, and strip colour attributes from what you build.

## Palette imports in Godot {#palette-imports}

- **Approach:** Write each palette PNG's `.import` from the build (lossless, `mipmaps/generate=false`, Detect 3D off:
  `detect_3d/compress_to=0`) and check it in pre-commit and CI. **Watch out for:** with Godot's default Detect 3D,
  opening the editor recompressed the palettes with mipmaps, blending neighbouring cells, and rewrote 11 `.import`
  files, while a headless import never does. **Seen:** Deadnight #441, #454, 2026-11-01 (fix: `palette_import.py`
  writes the files and a hook checks them).

## Baking {#baking}

GDStudio's games bake no textures: no normal, ambient-occlusion or colour bakes. A flat-palette asset has nothing to bake,
since every face is one colour and the shading comes from Godot's lights (lightmaps are baked in Godot, on
[Compatibility lighting](../../engines/godot/compat-lighting.md)). "Bake" in the Blender pages means two other things:
baking a pose into clips ([Animation](animation.md#keyframes)) and baking a walker's clip into one action for a preview
([Key art](key-art.md)).

The first texture bakes were made by the realistic character experiment (gdstudio #1151): normals from a Multires
sculpt, painted detail, colour, roughness and ambient occlusion with Cycles, at about 84 pixels per centimetre on a
head, with the settings and the traps on [Realistic characters](realistic-characters.md#baking). A game asset that
needs a bake starts from that section and adds its own numbers here before a second asset copies it.
