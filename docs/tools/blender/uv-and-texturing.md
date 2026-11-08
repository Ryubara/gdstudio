# UV and texturing

<!-- new section: UV and palette rules were spread over the weapons, kit and variants pages as side notes; no page
said how an asset is textured -->

How a GDStudio asset gets its colour: not by unwrapping and painting, but by putting every face on one cell of a shared
palette atlas. This is the CC0 kits' own method (the Quaternius zombie has 100% of its faces under one texel), and it
keeps one material and one draw call per asset family. The material that shows the atlas is on
[Materials](materials.md); how Godot reads the cells is on [Weapons](weapons.md#palette-cells-in-godot).

## The palette atlas {#palette-atlas}

A palette atlas is a small square PNG of flat colour cells in a grid, row 0 at the top of the image. Deadnight's are 32
by 32 with 8 px cells for the weapons (4 by 4), 40 by 40 for props (5 by 5), 80 by 80 with 16 px cells for the drive-in
and the small map, and 64 by 64 for the helicopter; the soldier's 256 by 64 has a row of tintable channels and a row of
fixed colours. One atlas serves a family of assets (characters, zombies, weapons, props), so they share a material.

Write the palette's sRGB bytes straight into `image.pixels` and save it as PNG: converting to linear first stored
`#9a968c` as `#524e43` ([Modular kits](modular-kits.md)). Grow an atlas only into empty cells or at the end, so the UVs
of every asset already built keep their colour ([Modular kits](modular-kits.md), [Weapons](weapons.md#palette-cells-in-godot)).

## Faces on swatches {#swatch-uvs}

There is no unwrapping: each face's UVs are collapsed onto the centre of its cell, so the face shows one flat colour
whatever the filtering or mipmap. For a grid of `G` cells a side, the cell in column `col` and row `row` (counted from
the top) is at

```python
u, v = (col + 0.5) / G, 1 - (row + 0.5) / G
```

The `1 -` is the trap: Blender's UV `v` and its image pixel rows both run from the bottom, while a palette's rows are
counted from the top and glTF flips `v` again on export (Godot reads the cell as `floor(u * G) + G * floor(v * G)` on
the flipped value). A face whose UVs straddle two cells, or sit within a pixel of a cell's edge, blends the neighbour in
under linear filtering or a mipmap; collapsed UVs never do. There is no texel density to keep, because there is no
detail to keep.

- **Approach:** Pick a face's cell by what the face is (its part, its height band, its normal), set every loop of the
  face to that cell's centre, and assert after the build that each face's UVs fall inside one cell, 1 px in from its
  edge. **Watch out for:** a cell's row counted from the bottom lands every face one or more rows off, on a colour that
  looks plausible in a dim render. **Seen:** gdstudio #774, 2026-11-07 (fix: the `uv-palette` eval checks every
  triangle's cell and colour through the exported glb).

## Bands and patterns {#bands}

A painted band (a stripe round a sleeve, a ring round a barrel) is cut into the mesh with `bisect_plane` and its faces
put on the band's cell, never chosen by face centre on uncut geometry, which leaves a sawtooth edge
([Variants](variants.md#modular-parts)). A pattern (camouflage, a check) is a small tile drawn in one cell with the
face's UVs spread across that cell, which costs far fewer triangles than modelling it: 160 triangles of faces saved on
one garment ([Variants](variants.md#clothes-that-stand-off-the-body)).

A mesh joined from parts keeps one UV layer per name: a part whose layer is named differently lands on texel (0, 0)
after the join, so name every part's layer like the body's ([Variants](variants.md)).

## The UV eval {#eval}

The `uv-palette` eval ([Agent evals](../../studio/agent-evals.md)) textures a barrel on a given atlas and measures every
triangle: UVs inside one cell, the colour of its part, the atlas unchanged and nearest filtering.
