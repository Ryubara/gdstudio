"""Inputs of the uv-palette eval: barrel.glb (no UVs, no material), palette.png and palette.json."""

import colorsys
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bmesh  # noqa: E402
import bpy  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1 :]
out = Path(argv[argv.index("--dir") + 1])

SIDES = 16
RINGS = [0.0, 0.15, 0.25, 0.65, 0.75, 0.9]  # the bands are 0.15-0.25 and 0.65-0.75
CELL = 16
GRID = 8
NAMED = {"wood": (2, 3), "iron": (6, 0), "wood_dark": (2, 5)}  # [column, row], row 0 at the top of the image


def radius(z: float) -> float:
    return 0.27 + 0.05 * math.sin(math.pi * z / 0.9)


def barrel() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    rings = []
    for z in RINGS:
        r = radius(z)
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / SIDES), r * math.sin(2 * math.pi * i / SIDES), z))
                      for i in range(SIDES)])
    for low, high in zip(rings, rings[1:]):
        for i in range(SIDES):
            j = (i + 1) % SIDES
            bm.faces.new((low[i], low[j], high[j], high[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("barrel")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("barrel", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.ops.export_scene.gltf(filepath=str(out / "barrel.glb"), export_format="GLB", export_materials="NONE")


def palette() -> None:
    size = CELL * GRID
    image = bpy.data.images.new("palette", size, size, alpha=False)
    pixels = [0.0] * (size * size * 4)
    for row in range(GRID):
        for col in range(GRID):
            hue = row / GRID
            sat = 0.35 + 0.08 * col
            val = 0.95 - 0.07 * col
            r, g, b = colorsys.hsv_to_rgb(hue, sat, val)
            r, g, b = (round(c * 255) / 255 for c in (r, g, b))
            for y in range(CELL):
                for x in range(CELL):
                    px = col * CELL + x
                    py = size - 1 - (row * CELL + y)  # Blender's pixel rows start at the bottom
                    i = (py * size + px) * 4
                    pixels[i : i + 4] = [r, g, b, 1.0]
    image.pixels = pixels
    image.filepath_raw = str(out / "palette.png")
    image.file_format = "PNG"
    image.save()
    names = {name: {"column": c, "row": r} for name, (c, r) in NAMED.items()}
    (out / "palette.json").write_text(
        json.dumps({"image": "palette.png", "cell_px": CELL, "grid": GRID, "row_0": "top", "cells": names}, indent=2),
        encoding="utf-8",
    )


barrel()
palette()
