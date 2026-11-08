"""Check of the uv-palette eval (TASK.md beside this file)."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bpy  # noqa: E402
import evallib  # noqa: E402

opts = evallib.args()
result = evallib.Result("uv-palette")
glb = opts.dir / "barrel_textured.glb"
spec = json.loads((opts.dir / "palette.json").read_text(encoding="utf-8"))
CELL, GRID = spec["cell_px"], spec["grid"]
SIZE = CELL * GRID
BANDS = [(0.15, 0.25), (0.65, 0.75)]


def pixels(image) -> list[float]:
    return list(image.pixels[:])


def colour_at(px: list[float], width: int, u: float, v: float) -> tuple:
    x = min(width - 1, max(0, int(u * width)))
    y = min(width - 1, max(0, int(v * width)))  # Blender's pixel rows start at the bottom, as UV v does
    i = (y * width + x) * 4
    return tuple(round(c * 255) for c in px[i : i + 3])


def expected_part(centroid, normal) -> str:
    if abs(normal.z) > 0.9:
        return "wood_dark"
    if any(lo < centroid.z < hi for lo, hi in BANDS):
        return "iron"
    return "wood"


def measure_geometry():
    objs = evallib.meshes()
    tris = sum(evallib.triangles(o) for o in objs)
    points = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return objs, tris, evallib.bounds(points) if points else None


evallib.empty_scene()
palette = bpy.data.images.load(str(opts.dir / "palette.png"))
palette_px = pixels(palette)
named = {}
for name, cell in spec["cells"].items():
    u = (cell["column"] + 0.5) / GRID
    v = 1 - (cell["row"] + 0.5) / GRID
    named[name] = colour_at(palette_px, SIZE, u, v)

evallib.import_glb(opts.dir / "barrel.glb")
_, input_tris, input_bounds = measure_geometry()

if not glb.is_file():
    result.error("barrel_textured.glb is missing")
    result.row("barrel_textured.glb delivered", False, "==", True)
else:
    evallib.import_glb(glb)
    palette = bpy.data.images.load(str(opts.dir / "palette.png"))
    palette_px = pixels(palette)
    objs, tris, bnds = measure_geometry()
    result.row("triangles (as the input)", tris, "==", input_tris)
    off = max(max(abs(a - b) for a, b in zip(bnds[0], input_bounds[0])), max(abs(a - b) for a, b in zip(bnds[1], input_bounds[1])))
    result.row("bounds moved from the input", off, "<=", 0.001, "m")
    materials = {m for o in objs for m in o.data.materials if m}
    result.row("materials", len(materials), "==", 1)
    image, interpolation = None, None
    for mat in materials:
        if not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED" and node.inputs["Base Color"].links:
                src = node.inputs["Base Color"].links[0].from_node
                if src.type == "TEX_IMAGE":
                    image, interpolation = src.image, src.interpolation
    same_image = False
    if image is not None and tuple(image.size) == (SIZE, SIZE):
        got = pixels(image)
        same_image = max(abs(a - b) for a, b in zip(got, palette_px)) <= 2 / 255
    result.row("base colour is palette.png, unchanged", same_image, "==", True)
    result.row("texture filter nearest", interpolation == "Closest", "==", True)
    inside_unit = inside_cell = right_colour = total = 0
    margin = 1.0 / SIZE
    for obj in objs:
        mesh = obj.data
        if not mesh.uv_layers:
            total += len(mesh.polygons)
            continue
        uv = mesh.uv_layers.active.data
        mesh.calc_loop_triangles()
        for lt in mesh.loop_triangles:
            total += 1
            uvs = [uv[i].uv for i in lt.loops]
            if all(0 <= c.x <= 1 and 0 <= c.y <= 1 for c in uvs):
                inside_unit += 1
            cu = sum(c.x for c in uvs) / 3
            cv = sum(c.y for c in uvs) / 3
            col, row = int(cu * GRID), int(cv * GRID)
            lo_u, lo_v = col / GRID + margin, row / GRID + margin
            hi_u, hi_v = (col + 1) / GRID - margin, (row + 1) / GRID - margin
            if all(lo_u <= c.x <= hi_u and lo_v <= c.y <= hi_v for c in uvs):
                inside_cell += 1
            centroid = obj.matrix_world @ lt.center
            normal = (obj.matrix_world.to_3x3() @ lt.normal).normalized()
            want = named[expected_part(centroid, normal)]
            got = colour_at(palette_px, SIZE, cu, cv)
            if max(abs(a - b) for a, b in zip(got, want)) <= 2:
                right_colour += 1
    total = max(total, 1)
    result.row("triangles with UVs inside 0-1", 100.0 * inside_unit / total, ">=", 100.0, "%")
    result.row("triangles inside one cell, 1 px in from its edge", 100.0 * inside_cell / total, ">=", 100.0, "%")
    result.row("triangles on their part's colour", 100.0 * right_colour / total, ">=", 100.0, "%")

    def compare(_path):
        _, n_tris, n_bounds = measure_geometry()
        return n_tris == tris and n_bounds is not None, f"{n_tris} triangles against {tris}"

    evallib.rebuild(opts.dir, result, compare)
evallib.preview(opts.dir, result)
result.write(opts.json)
