"""The blocky humanoid of the rig and clip evals: its mesh, its joints and the bone each part of it belongs to.

1.8 m tall, in a T-pose, facing -Y (glTF and Godot +Z), its left side on +X. Each body part is a box with edge loops
every few centimetres, so it bends at the joints.
"""

from __future__ import annotations

import bmesh
import bpy
from mathutils import Vector

STEP = 0.04
ZONE = 0.04  # vertices this close to a joint may belong to either bone

JOINTS = {
    "hips": (0.0, 0.0, 0.92),
    "spine": (0.0, 0.0, 1.02),
    "chest": (0.0, 0.0, 1.2),
    "neck": (0.0, 0.0, 1.45),
    "head": (0.0, 0.0, 1.57),
}
for side, sx in (("L", 1.0), ("R", -1.0)):
    JOINTS.update(
        {
            f"upper_arm.{side}": (0.2 * sx, 0.0, 1.4),
            f"forearm.{side}": (0.46 * sx, 0.0, 1.4),
            f"hand.{side}": (0.70 * sx, 0.0, 1.4),
            f"thigh.{side}": (0.1 * sx, 0.0, 0.9),
            f"shin.{side}": (0.1 * sx, 0.0, 0.5),
            f"foot.{side}": (0.1 * sx, 0.0, 0.08),
        }
    )

PARENTS = {"hips": None, "spine": "hips", "chest": "spine", "neck": "chest", "head": "neck"}
for side in "LR":
    PARENTS.update(
        {
            f"upper_arm.{side}": "chest",
            f"forearm.{side}": f"upper_arm.{side}",
            f"hand.{side}": f"forearm.{side}",
            f"thigh.{side}": "hips",
            f"shin.{side}": f"thigh.{side}",
            f"foot.{side}": f"shin.{side}",
        }
    )

# (name, low corner, high corner, long axis): the shells of the mesh
BOXES = [
    ("torso", (-0.18, -0.1, 0.88), (0.18, 0.1, 1.45), 2),
    ("neck", (-0.05, -0.05, 1.45), (0.05, 0.05, 1.57), 2),
    ("head", (-0.12, -0.13, 1.57), (0.12, 0.11, 1.8), 2),
]
for side, sx in (("L", 1.0), ("R", -1.0)):
    arm = sorted((0.18 * sx, 0.86 * sx))
    leg = sorted((0.035 * sx, 0.165 * sx))
    BOXES += [
        (f"arm.{side}", (arm[0], -0.045, 1.355), (arm[1], 0.045, 1.445), 0),
        (f"leg.{side}", (leg[0], -0.065, 0.08), (leg[1], 0.065, 0.88), 2),
        (f"foot.{side}", (leg[0], -0.2, 0.0), (leg[1], 0.06, 0.08), 1),
    ]


def expected_bone(p: Vector) -> str | None:
    """The bone a rest-pose vertex at `p` belongs to, or None inside a joint's zone."""
    x, y, z = p
    side = "L" if x > 0 else "R"
    ax = abs(x)

    def near(value: float, *planes: float) -> bool:
        return any(abs(value - plane) < ZONE for plane in planes)

    if z <= 0.08 + 1e-6 and y < 0.061 and ax > 0.03:
        return None if z > 0.08 - ZONE and abs(y) < 0.07 else f"foot.{side}"
    if 1.355 - 1e-6 <= z <= 1.445 + 1e-6 and ax >= 0.18 - 1e-6:
        if ax < 0.2 + ZONE or near(ax, 0.46, 0.70):
            return None
        return f"upper_arm.{side}" if ax < 0.46 else f"forearm.{side}" if ax < 0.70 else f"hand.{side}"
    if z < 0.88 - 1e-6:
        if near(z, 0.5) or z > 0.88 - ZONE or z < 0.08 + ZONE:
            return None
        return f"thigh.{side}" if z > 0.5 else f"shin.{side}"
    if z <= 1.45 + 1e-6 and ax <= 0.18 + 1e-6 and abs(y) <= 0.1 + 1e-6:
        if near(z, 1.02, 1.2) or z > 1.45 - ZONE or z < 0.88 + ZONE:
            return None
        return "hips" if z < 1.02 else "spine" if z < 1.2 else "chest"
    if z <= 1.57 + 1e-6:
        return None if near(z, 1.45, 1.57) else "neck"
    return None if z < 1.57 + ZONE else "head"


def _box(bm: bmesh.types.BMesh, low, high, axis: int) -> list:
    """A closed box with a ring of vertices every STEP along `axis`."""
    length = high[axis] - low[axis]
    count = max(1, round(length / STEP))
    others = [a for a in range(3) if a != axis]
    rings = []
    for i in range(count + 1):
        t = low[axis] + length * i / count
        ring = []
        for a, b in ((0, 0), (1, 0), (1, 1), (0, 1)):
            co = [0.0, 0.0, 0.0]
            co[axis] = t
            co[others[0]] = (low, high)[a][others[0]]
            co[others[1]] = (low, high)[b][others[1]]
            ring.append(bm.verts.new(co))
        rings.append(ring)
    faces = []
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(4):
            k = (j + 1) % 4
            faces.append(bm.faces.new((r0[j], r0[k], r1[k], r1[j])))
    faces.append(bm.faces.new(list(reversed(rings[0]))))
    faces.append(bm.faces.new(rings[-1]))
    return faces


def build_mesh() -> bpy.types.Object:
    bm = bmesh.new()
    for _name, low, high, axis in BOXES:
        _box(bm, low, high, axis)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("body")
    bm.to_mesh(mesh)
    bm.free()
    mat = bpy.data.materials.new("body")
    mat.diffuse_color = (0.55, 0.6, 0.7, 1.0)
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("body", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def tail_of(name: str) -> Vector:
    children = [c for c, p in PARENTS.items() if p == name and not c.startswith(("upper_arm", "thigh"))]
    if name == "hips":
        return Vector(JOINTS["spine"])
    if children:
        return Vector(JOINTS[children[0]])
    head = Vector(JOINTS[name])
    if name.startswith("hand"):
        return head + Vector((0.14 if head.x > 0 else -0.14, 0, 0))
    if name.startswith("foot"):
        return head + Vector((0, -0.16, -0.04))
    return head + Vector((0, 0, 0.2))  # head


def build_rig(body: bpy.types.Object) -> bpy.types.Object:
    """An armature with the bones of JOINTS, the body skinned to it by region with a blend across each joint."""
    arm_data = bpy.data.armatures.new("Armature")
    rig = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    bones = {}
    for name in JOINTS:
        bone = arm_data.edit_bones.new(name)
        bone.head = JOINTS[name]
        bone.tail = tail_of(name)
        bones[name] = bone
    for name, parent in PARENTS.items():
        if parent:
            bones[name].parent = bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    groups = {name: body.vertex_groups.new(name=name) for name in JOINTS}
    for v in body.data.vertices:
        name = expected_bone(v.co)
        if name is None:
            name, other, t = _blend(v.co)
            groups[name].add([v.index], 1.0 - t, "REPLACE")
            if other:
                groups[other].add([v.index], t, "REPLACE")
        else:
            groups[name].add([v.index], 1.0, "REPLACE")
    body.parent = rig
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    return rig


def _blend(p: Vector) -> tuple[str, str | None, float]:
    """For a vertex in a joint's zone: the bone below the joint, the one above, and the share of the one above."""
    x, y, z = p
    side = "L" if x > 0 else "R"
    ax = abs(x)

    def ramp(value: float, plane: float) -> float:
        return min(1.0, max(0.0, (value - (plane - ZONE)) / (2 * ZONE)))

    if z <= 0.08 + 1e-6 and y < 0.061 and ax > 0.03:
        return f"shin.{side}", f"foot.{side}", 0.5
    if 1.355 - 1e-6 <= z <= 1.445 + 1e-6 and ax >= 0.18 - 1e-6:
        if ax < 0.2 + ZONE:
            return "chest", f"upper_arm.{side}", ramp(ax, 0.2)
        if abs(ax - 0.46) < ZONE:
            return f"upper_arm.{side}", f"forearm.{side}", ramp(ax, 0.46)
        return f"forearm.{side}", f"hand.{side}", ramp(ax, 0.70)
    if z < 0.88 - 1e-6:
        if z > 0.88 - ZONE:
            return f"thigh.{side}", "hips", ramp(z, 0.88)
        if z < 0.08 + ZONE:
            return f"foot.{side}", f"shin.{side}", ramp(z, 0.08)
        return f"shin.{side}", f"thigh.{side}", ramp(z, 0.5)
    if z <= 1.45 + 1e-6 and ax <= 0.18 + 1e-6 and abs(y) <= 0.1 + 1e-6:
        if z < 0.88 + ZONE:
            return "hips", None, 0.0
        if abs(z - 1.02) < ZONE:
            return "hips", "spine", ramp(z, 1.02)
        if abs(z - 1.2) < ZONE:
            return "spine", "chest", ramp(z, 1.2)
        return "chest", None, 0.0
    if z <= 1.57 + 1e-6:
        return ("chest", "neck", ramp(z, 1.45)) if z < 1.51 else ("neck", "head", ramp(z, 1.57))
    return "neck", "head", ramp(z, 1.57)
