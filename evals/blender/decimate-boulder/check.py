"""Check of the decimate-boulder eval (TASK.md beside this file)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import evallib  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

opts = evallib.args()
result = evallib.Result("decimate-boulder")
glb = opts.dir / "boulder.glb"
LODS = {"boulder_lod0": (2000, 0.003, 0.02), "boulder_lod1": (500, 0.008, 0.04)}  # triangles, mean and max error


def tree(bm):
    return BVHTree.FromBMesh(bm)


def high_poly():
    evallib.import_glb(opts.dir / "boulder_high.glb")
    obj = evallib.meshes()[0]
    bm = evallib.world_bmesh(obj)
    low, high = evallib.bounds(v.co for v in bm.verts)
    points = [v.co.copy() for v in list(bm.verts)[::3]]
    return bm, tree(bm), points, low, high


high_bm, high_tree, high_points, high_low, high_high = high_poly()
diag = (high_high - high_low).length


def lod_objects():
    return {o.name.split(".")[0]: o for o in evallib.meshes()}


if not glb.is_file():
    result.error("boulder.glb is missing")
    result.row("boulder.glb delivered", False, "==", True)
else:
    evallib.import_glb(glb)
    found = lod_objects()
    result.row("mesh objects in the file", len(found), "==", 2)
    counts = {}
    for name, (budget, mean_limit, max_limit) in LODS.items():
        obj = found.get(name)
        if obj is None:
            result.row(f"{name} present", False, "==", True)
            continue
        counts[name] = evallib.triangles(obj)
        result.row(f"{name} triangles", counts[name], "<=", budget)
        result.row(f"{name} materials", len([m for m in obj.data.materials if m]), "==", 1)
        result.row(f"{name} object scale off 1", max(abs(s - 1) for s in obj.scale), "<=", 0.001)
        bm = evallib.world_bmesh(obj)
        lod_tree = tree(bm)
        dists = [lod_tree.find_nearest(p)[3] for p in high_points]
        back = [high_tree.find_nearest(v.co)[3] for v in bm.verts]
        mean = sum(dists) / len(dists) / diag
        worst = max(max(dists), max(back) if back else 0.0) / diag
        result.row(f"{name} mean distance from the high poly / diagonal", 100 * mean, "<=", 100 * mean_limit, "%")
        result.row(f"{name} largest distance / diagonal", 100 * worst, "<=", 100 * max_limit, "%")
        low, high = evallib.bounds(v.co for v in bm.verts)
        off = max(max(abs(a - b) for a, b in zip(low, high_low)), max(abs(a - b) for a, b in zip(high, high_high)))
        result.row(f"{name} bounds off the high poly / diagonal", 100 * off / diag, "<=", 1.0, "%")
        result.row(f"{name} lowest vertex", low.z, "in", [-0.005, 0.005], "m")
        flipped = total = 0.0
        for f in bm.faces:
            area = f.calc_area()
            total += area
            _co, normal, _i, _d = high_tree.find_nearest(f.calc_center_median())
            if normal is not None and normal.dot(f.normal) < 0:
                flipped += area
        result.row(f"{name} area facing against the high poly", 100 * flipped / max(total, 1e-9), "<=", 0.5, "%")
        topo = evallib.topology(bm)
        result.row(f"{name} open edges", topo["open_edges"], "==", 0)
        bm.free()

    def compare(_path):
        again = {n: evallib.triangles(o) for n, o in lod_objects().items() if n in LODS}
        return again == counts, f"{again} against {counts}"

    evallib.rebuild(opts.dir, result, compare)
evallib.preview(opts.dir, result)
result.write(opts.json)
