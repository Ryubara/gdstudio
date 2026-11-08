"""Check of the rig-humanoid eval (TASK.md beside this file)."""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bpy  # noqa: E402
import evallib  # noqa: E402
import humanoid  # noqa: E402
from mathutils import Quaternion, Vector  # noqa: E402

opts = evallib.args()
result = evallib.Result("rig-humanoid")
glb = opts.dir / "humanoid_rigged.glb"


def find_rig():
    rigs = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if not rigs:
        return None, []
    rig = rigs[0]
    skinned = [
        o for o in evallib.meshes() if any(m.type == "ARMATURE" and m.object == rig for m in o.modifiers)
    ]
    return rig, skinned


def positions(obj) -> list[Vector]:
    """World positions of the object's vertices after its modifiers (the pose), in the mesh's own order."""
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    out = [obj.matrix_world @ v.co for v in mesh.vertices]
    evaluated.to_mesh_clear()
    return out


def weights(obj) -> list[dict[str, float]]:
    names = {g.index: g.name for g in obj.vertex_groups}
    return [{names[g.group]: g.weight for g in v.groups if g.weight > 0.001} for v in obj.data.vertices]


def bend(rig, skinned, bone: str, follower: str, still_side: str) -> tuple[float, float]:
    """Rotate `bone` 90 degrees; the largest error of `follower`'s vertices from moving rigidly with it, and the
    largest movement of the vertices on the other side of the body (`still_side` of x)."""
    rest = [(o, positions(o)) for o in skinned]
    pb = rig.pose.bones[bone]
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Quaternion((1, 0, 0), math.radians(90))
    bpy.context.view_layer.update()
    m = rig.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted() @ rig.matrix_world.inverted()
    follow_err = still_move = 0.0
    for obj, before in rest:
        after = positions(obj)
        for p0, p1 in zip(before, after):
            owner = humanoid.expected_bone(p0)
            if owner == follower:
                follow_err = max(follow_err, (m @ p0 - p1).length)
            if p0.x < -0.05 if still_side == "-" else p0.x > 0.05:
                still_move = max(still_move, (p1 - p0).length)
    pb.rotation_quaternion = Quaternion()
    bpy.context.view_layer.update()
    return follow_err, still_move


def summary(rig, skinned):
    bones = {b.name: b for b in rig.data.bones} if rig else {}
    heads = {n: rig.matrix_world @ b.head_local for n, b in bones.items()} if rig else {}
    return bones, heads, sum(len(o.data.vertices) for o in skinned)


if not glb.is_file():
    result.error("humanoid_rigged.glb is missing")
    result.row("humanoid_rigged.glb delivered", False, "==", True)
else:
    evallib.import_glb(glb)
    rig, skinned = find_rig()
    result.row("armature in the file", rig is not None, "==", True)
    result.row("skinned meshes", len(skinned), ">=", 1)
    bones, heads, vert_count = summary(rig, skinned)
    want = set(humanoid.JOINTS)
    result.row("bones named as the brief", len(want & set(bones)), "==", len(want))
    result.row("extra bones", len(set(bones) - want), "==", 0)
    parents_ok = sum(
        1
        for n, p in humanoid.PARENTS.items()
        if n in bones and (bones[n].parent.name if bones[n].parent else None) == p
    )
    result.row("bones with the right parent", parents_ok, "==", len(want))
    placed = sum(1 for n in want if n in heads and (heads[n] - Vector(humanoid.JOINTS[n])).length <= 0.06)
    result.row("joints within 6 cm of the body's joints", placed, "==", len(want))
    total = unweighted = over4 = unnormal = scored = right = 0
    mirror_pairs = mirror_ok = 0
    for obj in skinned:
        vw = weights(obj)
        cos = [obj.matrix_world @ v.co for v in obj.data.vertices]
        index = {(round(c.x, 3), round(c.y, 3), round(c.z, 3)): i for i, c in enumerate(cos)}
        for i, (co, w) in enumerate(zip(cos, vw)):
            total += 1
            if not w:
                unweighted += 1
                continue
            over4 += len(w) > 4
            unnormal += abs(sum(w.values()) - 1) > 0.01
            owner = humanoid.expected_bone(co)
            if owner is not None:
                scored += 1
                right += max(w, key=w.get) == owner
            if co.x > 0.01:
                j = index.get((round(-co.x, 3), round(co.y, 3), round(co.z, 3)))
                if j is not None:
                    mirror_pairs += 1
                    other = {n.replace(".R", ".l").replace(".L", ".R").replace(".l", ".L"): v for n, v in vw[j].items()}
                    keys = set(w) | set(other)
                    mirror_ok += max(abs(w.get(k, 0) - other.get(k, 0)) for k in keys) <= 0.05
    total = max(total, 1)
    result.row("unweighted vertices", unweighted, "==", 0)
    result.row("vertices with more than 4 bones", over4, "==", 0)
    result.row("vertices whose weights do not sum to 1", unnormal, "==", 0)
    result.row("vertices led by their body part's bone", 100.0 * right / max(scored, 1), ">=", 95.0, "%")
    result.row("mirrored vertices with mirrored weights", 100.0 * mirror_ok / max(mirror_pairs, 1), ">=", 95.0, "%")
    if rig and {"forearm.L", "shin.R"} <= set(bones):
        err, still = bend(rig, skinned, "forearm.L", "hand.L", "-")
        result.row("elbow bent 90: hand follows the forearm, error", err, "<=", 0.01, "m")
        result.row("elbow bent 90: right side moves", still, "<=", 0.001, "m")
        err, still = bend(rig, skinned, "shin.R", "foot.R", "+")
        result.row("knee bent 90: foot follows the shin, error", err, "<=", 0.01, "m")
        result.row("knee bent 90: left leg moves", still, "<=", 0.001, "m")
    else:
        for name in ("elbow bend", "knee bend"):
            result.row(name, None, "==", True)

    def compare(_path):
        r2, s2 = find_rig()
        b2, h2, n2 = summary(r2, s2)
        same = set(b2) == set(bones) and n2 == vert_count
        same = same and all((h2[n] - heads[n]).length <= 0.001 for n in bones)
        return same, f"{len(b2)} bones and {n2} vertices against {len(bones)} and {vert_count}"

    evallib.rebuild(opts.dir, result, compare)
evallib.preview(opts.dir, result)
result.write(opts.json)
