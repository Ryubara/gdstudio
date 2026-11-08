"""Check of the model-crate eval (TASK.md beside this file)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import evallib  # noqa: E402

opts = evallib.args()
result = evallib.Result("model-crate")
glb = opts.dir / "crate.glb"


def measure() -> dict | None:
    objs = evallib.meshes()
    named = [o for o in objs if o.name.split(".")[0] == "crate"]
    if not named:
        return None
    obj = named[0]
    bm = evallib.world_bmesh(obj)
    low, high = evallib.bounds(v.co for v in bm.verts)
    size = high - low
    topo = evallib.topology(bm)
    volume = evallib.signed_volume(bm.faces)
    bm.free()
    return {
        "objects": len(objs),
        "obj": obj,
        "tris": evallib.triangles(obj),
        "materials": len([m for m in obj.data.materials if m]),
        "size": size,
        "low": low,
        "high": high,
        "volume_ratio": volume / (size.x * size.y * size.z) if size.x * size.y * size.z > 0 else 0.0,
        **topo,
    }


if not glb.is_file():
    result.error("crate.glb is missing")
    result.row("crate.glb delivered", False, "==", True)
else:
    evallib.import_glb(glb)
    m = measure()
    if m is None:
        result.error("no mesh object named crate in crate.glb")
        result.row("a mesh named crate", False, "==", True)
    else:
        obj = m["obj"]
        result.row("mesh objects in the file", m["objects"], "==", 1)
        result.row("triangles", m["tris"], "in", [120, 500])
        result.row("materials", m["materials"], "in", [1, 2])
        for axis, value in zip("xyz", m["size"]):
            result.row(f"size {axis}", value, "in", [0.98, 1.02], "m")
        result.row("lowest vertex", m["low"].z, "in", [-0.005, 0.005], "m")
        centre = (m["low"] + m["high"]) / 2
        result.row("bounds centre off the origin (x, y)", max(abs(centre.x), abs(centre.y)), "<=", 0.01, "m")
        result.row("object scale off 1", max(abs(s - 1) for s in obj.scale), "<=", 0.001)
        result.row("object rotation", max(abs(r) for r in obj.rotation_euler), "<=", 0.001, "rad")
        result.row("open edges", m["open_edges"], "==", 0)
        result.row("degenerate faces", m["degenerate"], "==", 0)
        result.row("inside-out shells", m["inside_out"], "==", 0)
        result.row("volume / bounds volume (not a plain box)", m["volume_ratio"], "in", [0.6, 0.97])
        tris, size = m["tris"], m["size"]

        def compare(_path):
            n = measure()
            if n is None:
                return False, "no crate mesh"
            diff = max(abs(a - b) for a, b in zip(n["size"], size))
            return n["tris"] == tris and diff <= 0.001, f"{n['tris']} triangles against {tris}, size off {diff:.4f} m"

        evallib.rebuild(opts.dir, result, compare)
evallib.preview(opts.dir, result)
result.write(opts.json)
