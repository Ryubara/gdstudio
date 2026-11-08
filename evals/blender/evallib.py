"""Shared helpers of the Blender eval checks (kit docs/studio/agent-evals.md).

Runs inside the pinned Blender: `blender -b --factory-startup --python-exit-code 1 -P check.py -- --dir <task folder>
--json <result file>`. A check imports what the agent delivered (always the exported .glb, the file Godot gets),
measures it and records one row per number: its value, its limit and whether it met it.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


class Result:
    """The rows of one check run, written as JSON at the end."""

    def __init__(self, task: str) -> None:
        self.task = task
        self.rows: list[dict] = []
        self.errors: list[str] = []

    def row(self, name: str, value, op: str, limit, unit: str = "") -> bool:
        """Record `value op limit`; op is one of <=, >=, ==, in (limit a [low, high] pair)."""
        if value is None:
            ok = False
        elif op == "<=":
            ok = value <= limit
        elif op == ">=":
            ok = value >= limit
        elif op == "==":
            ok = value == limit
        elif op == "in":
            ok = limit[0] <= value <= limit[1]
        else:
            raise ValueError(op)
        if isinstance(value, float):
            value = round(value, 4)
        self.rows.append({"name": name, "value": value, "op": op, "limit": limit, "unit": unit, "pass": ok})
        return ok

    def error(self, text: str) -> None:
        self.errors.append(text)

    def write(self, path: Path) -> None:
        passed = sum(1 for r in self.rows if r["pass"])
        data = {"task": self.task, "passed": passed, "total": len(self.rows), "rows": self.rows, "errors": self.errors}
        path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True, type=Path)
    parser.add_argument("--json", required=True, type=Path)
    return parser.parse_args(argv)


def empty_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path: Path) -> list[bpy.types.Object]:
    """Import a .glb into an empty scene; the new objects."""
    empty_scene()
    bpy.ops.import_scene.gltf(filepath=str(path))
    return list(bpy.context.scene.objects)


def meshes(objects=None) -> list[bpy.types.Object]:
    return [o for o in (objects or bpy.context.scene.objects) if o.type == "MESH"]


def triangles(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def world_bmesh(obj: bpy.types.Object, merge: float = 1e-4) -> bmesh.types.BMesh:
    """The object's mesh in world space, evaluated (modifiers, pose), with the glTF seam splits welded."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    evaluated.to_mesh_clear()
    bm.transform(obj.matrix_world)
    if merge:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    return bm


def bounds(points) -> tuple[Vector, Vector]:
    pts = list(points)
    low = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    high = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return low, high


def topology(bm: bmesh.types.BMesh) -> dict:
    """Open edges, degenerate faces and inside-out closed shells.

    Welding the glTF seam splits also welds separate closed parts that touch (kitbashed parts are never joined), so an
    edge with more than two faces is not counted as a fault, and a shell is closed when no edge has exactly one face.
    """
    open_edges = sum(1 for e in bm.edges if len(e.link_faces) == 1)
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    inside_out = 0
    seen: set[int] = set()
    for face in bm.faces:
        if face.index in seen:
            continue
        shell, stack = [], [face]
        seen.add(face.index)
        while stack:
            f = stack.pop()
            shell.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        closed = all(len(e.link_faces) >= 2 for f in shell for e in f.edges)
        if closed and signed_volume(shell) < 0:
            inside_out += 1
    return {"open_edges": open_edges, "degenerate": degenerate, "inside_out": inside_out}


def signed_volume(faces) -> float:
    total = 0.0
    for f in faces:
        verts = [v.co for v in f.verts]
        for i in range(1, len(verts) - 1):
            total += verts[0].dot(verts[i].cross(verts[i + 1])) / 6.0
    return total


def rebuild(task_dir: Path, result: Result, compare) -> None:
    """Run the agent's build.py into a temporary .glb and record whether it gives the same file as the delivered one.

    `compare(path)` returns (same: bool, note: str) for the rebuilt file; it runs after the import of that file.
    """
    script = task_dir / "build.py"
    if not script.is_file():
        result.row("build.py rebuilds the delivery", None, "==", True)
        result.error("build.py is missing")
        return
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "rebuilt.glb"
        cmd = [bpy.app.binary_path, "-b", "--factory-startup", "--python-exit-code", "1", "-P", str(script)]
        try:
            run = subprocess.run(
                [*cmd, "--", "--out", str(out)], capture_output=True, text=True, timeout=600, cwd=task_dir
            )
        except subprocess.TimeoutExpired:
            result.row("build.py rebuilds the delivery", False, "==", True)
            result.error("build.py ran past 600 s")
            return
        if run.returncode != 0 or not out.is_file():
            result.row("build.py rebuilds the delivery", False, "==", True)
            result.error(f"build.py failed (exit {run.returncode}): {run.stderr[-600:]}")
            return
        import_glb(out)
        same, note = compare(out)
        result.row("build.py rebuilds the delivery", same, "==", True)
        if not same:
            result.error(f"the rebuilt file differs: {note}")


def preview(task_dir: Path, result: Result, min_width: int = 512) -> None:
    path = task_dir / "preview.png"
    width = 0
    if path.is_file():
        image = bpy.data.images.load(str(path))
        width = image.size[0]
    result.row("preview.png width", width, ">=", min_width, "px")


def degrees(radians: float) -> float:
    return radians * 180.0 / math.pi


def glb_json(path: Path) -> dict:
    """The JSON chunk of a .glb, read without Blender's importer."""
    data = path.read_bytes()
    length = int.from_bytes(data[12:16], "little")
    return json.loads(data[20 : 20 + length])
