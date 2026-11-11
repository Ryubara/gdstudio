"""Stage 7: the rig, on the prototype mannequin's skeleton contract (the Universal Animation Library's 65 bones with
the library's rest orientations, a T rest, bodies differing only in rest translations; plus twist, socket and IK
leaves, and two eye bones of our own).

1. A fitting armature with the library's bone names is laid on her joints in the A pose she was modelled in.
2. The whole body is weighted to it by bone heat, and every other mesh takes its weights from the body.
3. The armature is posed to the library's T (arms along X, palms down, legs straight down) and that pose is made
   the rest: the meshes are stored on the T rest.
4. Every bone takes the library rig's rest orientation, read from the template's mannequin file, and the build
   checks each bone's rest rotation in its parent against the library's.

    blender -b -P s07_rig.py -- --work <dir> --base <mannequin_female.glb>
"""

import json
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_lib as L  # noqa: E402

A = L.args()
S = L.SCALE
LIB_PELVIS = 0.9166


def read_library(path):
    """The library rig's rest: for every bone its parent, armature-space matrix and length."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    lib = {b.name: (b.parent.name if b.parent else None, b.matrix_local.copy(), b.length) for b in arm.data.bones}
    order = [b.name for b in arm.data.bones]
    for o in new:
        bpy.data.objects.remove(o)
    return lib, order


def slice_centre(co, z, tol=0.012):
    sel = np.abs(co[:, 2] - z) < tol
    return co[sel].mean(0)


def joints(full, vp, lib):
    """Her joint centres in the A pose (metres), named as the library names its bones."""
    co = L.co_get(full.data)
    j = {"root": Vector((0, 0, 0))}
    for name, p in (("pelvis", (0, 0.012, 0.955)), ("spine_01", (0, 0.018, 1.03)), ("spine_02", (0, 0.022, 1.12)),
                    ("spine_03", (0, 0.026, 1.23)), ("neck_01", (0, 0.022, 1.385)), ("Head", (0, 0.004, 1.468))):
        j[name] = Vector(p) * S
    frames = {}
    for side, sx in (("l", 1), ("r", -1)):
        sel = sx * co[:, 0] > 0
        j[f"clavicle_{side}"] = Vector((sx * 0.022, -0.025, 1.365)) * S
        sh = Vector((sx * 0.158, 0.012, 1.352)) * S
        arm = co[sel & (vp == 3)]
        hand = co[sel & (vp == 4)]
        o = arm.mean(0)
        ax = np.linalg.eigh(np.cov((arm - o).T))[1][:, -1]
        ax = ax if ax[2] < 0 else -ax
        t = (arm - o) @ ax
        wrist = Vector(arm[t > t.max() - 0.012].mean(0))
        k = 0.545
        guess = sh + (wrist - sh) * k
        near = arm[np.abs((arm - np.array(guess)) @ ax) < 0.012]
        elbow = Vector(near.mean(0)) + Vector((0, 0.006, 0))
        j[f"upperarm_{side}"], j[f"lowerarm_{side}"], j[f"hand_{side}"] = sh, elbow, wrist
        # The hand's own frame: along the fingers, towards the thumb, out of the palm.
        ho = hand.mean(0)
        w, v = np.linalg.eigh(np.cov((hand - ho).T))
        a = v[:, 2] if v[:, 2] @ (ho - np.array(wrist)) > 0 else -v[:, 2]
        lat = v[:, 1]
        rel = hand - np.array(wrist)
        along, side_c = rel @ a, rel @ lat
        prox = along < np.percentile(along, 55)
        far = np.abs(side_c[prox]) > np.percentile(np.abs(side_c[prox]), 90)
        th = lat * np.sign(side_c[prox][far].mean())
        th = th - a * (th @ a)
        th /= np.linalg.norm(th)
        palm = np.cross(a, th) * sx
        scale = (along.max()) / (lib[f"middle_04_leaf_{side}"][1].to_translation() - lib[f"hand_{side}"][1].to_translation()).length
        la, lth, lp = Vector((sx, 0, 0)), Vector((0, -1, 0)), Vector((0, 0, -1))
        base = lib[f"hand_{side}"][1].to_translation()
        for name in lib:
            if name.endswith(f"_{side}") and any(f in name for f in ("thumb", "index", "middle", "ring", "pinky")):
                d = lib[name][1].to_translation() - base
                q = np.array(wrist) + scale * ((d @ la) * a + (d @ lth) * th + (d @ lp) * palm)
                j[name] = Vector(q)
        frames[side] = (Vector(a), Vector(palm))
        j[f"thigh_{side}"] = Vector((sx * 0.090, 0.006, 0.915)) * S
        leg = co[sel & (vp == 5)]
        j[f"calf_{side}"] = Vector(slice_centre(leg, 0.488 * S)) + Vector((0, -0.008, 0))
        ankle = Vector(slice_centre(leg, 0.088 * S))
        j[f"foot_{side}"] = ankle
        foot = co[sel & (vp == 6)]
        toe = Vector(foot[foot[:, 1].argmin()])
        fdir = Vector((toe.x - ankle.x, toe.y - ankle.y, 0)).normalized()
        j[f"ball_{side}"] = Vector((ankle.x, ankle.y, 0.015)) + fdir * 0.125 * S
        j[f"ball_leaf_{side}"] = j[f"ball_{side}"] + fdir * 0.07 * S
    return j, frames


def build_fit(j, lib, order):
    data = bpy.data.armatures.new("rig")
    arm = bpy.data.objects.new("rig", data)
    L.link(arm)
    L.select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    for name in order:
        eb = data.edit_bones.new(name)
        eb.head = j[name]
        eb.tail = j[name] + Vector((0, 0, 0.05))
    for name in order:
        eb = data.edit_bones[name]
        if lib[name][0]:
            eb.parent = data.edit_bones[lib[name][0]]
        kids = [c for c in order if lib[c][0] == name]
        main = next((c for c in kids if not any(f in c for f in ("clavicle", "thigh", "thumb", "index", "ring", "pinky"))), kids[0] if kids else None)
        if name == "pelvis":
            main = "spine_01"
        if main and (j[main] - j[name]).length > 1e-4:
            eb.tail = j[main]
        elif eb.parent:
            d = (j[name] - j[lib[name][0]])
            eb.tail = j[name] + (d.normalized() * 0.03 if d.length > 1e-5 else Vector((0, 0, 0.05)))
    data.edit_bones["root"].tail = Vector((0, 0.1, 0))
    data.edit_bones["Head"].tail = j["Head"] + Vector((0, 0, 0.12))
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def child_of(arm, name):
    kids = [b for b in arm.data.bones[name].children]
    pick = next((b for b in kids if not any(f in b.name for f in ("clavicle", "thigh", "thumb", "index", "ring", "pinky"))), kids[0])
    return pick.name


def aim(arm, name, direction, to=None):
    """Turn a pose bone about its head so the line to its child (or to `to`) points along `direction`."""
    bpy.context.view_layer.update()
    pb = arm.pose.bones[name]
    target = arm.pose.bones[to or child_of(arm, name)].head
    cur = (target - pb.head).normalized()
    q = cur.rotation_difference(Vector(direction).normalized())
    turn(arm, name, q)


def turn(arm, name, q):
    pb = arm.pose.bones[name]
    loc = pb.matrix.to_translation()
    pb.matrix = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ pb.matrix
    bpy.context.view_layer.update()


def to_t_pose(arm, frames, lib):
    for side, sx in (("l", 1), ("r", -1)):
        x = Vector((sx, 0, 0))
        aim(arm, f"upperarm_{side}", x)
        aim(arm, f"lowerarm_{side}", x)
        aim(arm, f"hand_{side}", x, to=f"middle_01_{side}")
        # Roll the forearm until the palm faces down.
        hb = arm.pose.bones[f"hand_{side}"]
        palm_rest = frames[side][1]
        palm = (hb.matrix.to_3x3() @ arm.data.bones[hb.name].matrix_local.to_3x3().inverted() @ palm_rest)
        palm = Vector((0, palm.y, palm.z)).normalized()
        ang = palm.angle(Vector((0, 0, -1)))
        if palm.cross(Vector((0, 0, -1))).x < 0:
            ang = -ang
        turn(arm, f"lowerarm_{side}", Quaternion(Vector((1, 0, 0)), ang))
        for f in ("thumb", "index", "middle", "ring", "pinky"):
            for k in (1, 2, 3):
                name = f"{f}_0{k}_{side}"
                nxt = f"{f}_0{k + 1}_{side}" if k < 3 else f"{f}_04_leaf_{side}"
                d = lib[nxt][1].to_translation() - lib[name][1].to_translation()
                aim(arm, name, d, to=nxt)
        aim(arm, f"thigh_{side}", (0, 0, -1))
        aim(arm, f"calf_{side}", (0, 0, -1))
        # The foot keeps the sole flat on the floor: its rest orientation back, then a turn about the vertical
        # until it points forward.
        bpy.context.view_layer.update()
        fb = arm.pose.bones[f"foot_{side}"]
        fb.matrix = Matrix.Translation(fb.matrix.to_translation()) @ arm.data.bones[fb.name].matrix_local.to_3x3().to_4x4()
        bpy.context.view_layer.update()
        d = arm.pose.bones[f"ball_{side}"].head - fb.head
        turn(arm, fb.name, Vector((d.x, d.y, 0)).rotation_difference(Vector((0, -1, 0))))


def skinned(arm):
    return [o for o in bpy.data.objects if o.type == "MESH" and any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers)]


def b_head_x(arm, name):
    return arm.data.bones[name].head_local.x


def body_weights(arm, full, vp):
    """Weights for the whole body: each vertex to the bones of its own body part by distance to the bone's
    segment, then smoothed over the surface so the parts blend at the joints. (Bone heat fails on this mesh: the
    mouth bag and eye sockets are closed pockets it cannot solve.)"""
    co = L.co_get(full.data)
    bones = [b for b in arm.data.bones if not b.name.endswith("_leaf") and b.name != "root"]
    names = [b.name for b in bones]
    n, m = len(co), len(bones)
    dist = np.empty((n, m))
    for k, b in enumerate(bones):
        h, t = np.array(b.head_local), np.array(b.tail_local)
        seg = t - h
        u = np.clip(((co - h) @ seg) / (seg @ seg), 0, 1)
        dist[:, k] = np.linalg.norm(co - (h + u[:, None] * seg), axis=1)
    fingers = ("thumb", "index", "middle", "ring", "pinky")
    allow = np.zeros((n, m), dtype=bool)
    left = co[:, 0] > 0
    for k, name in enumerate(names):
        side = name.endswith("_l"), name.endswith("_r")
        mine = (left if side[0] else ~left) if any(side) else np.ones(n, dtype=bool)
        stem = name[:-2] if any(side) else name
        parts = {"Head": (0, 1), "neck_01": (0, 1, 2), "spine_03": (0, 2, 3), "spine_02": (2,), "spine_01": (2,),
                 "pelvis": (2, 5), "clavicle": (2, 3), "upperarm": (2, 3), "lowerarm": (3, 4), "hand": (3, 4),
                 "thigh": (2, 5), "calf": (5, 6), "foot": (5, 6), "ball": (6,)}.get(stem, (4,) if stem.startswith(fingers) else ())
        allow[:, k] = mine & np.isin(vp, parts)
        if stem == "upperarm":
            # On the trunk only the shoulder's cap follows the arm, not the side of the chest.
            allow[:, k] &= (vp != 2) | (np.abs(co[:, 0]) > abs(b_head_x(arm, name)) - 0.012)
        if stem == "thigh":
            allow[:, k] &= (vp != 2) | (co[:, 2] < 0.93 * S)
    w = np.where(allow, 1.0 / (dist + 0.004) ** 5, 0.0)
    w /= w.sum(1, keepdims=True)
    e = np.empty(len(full.data.edges) * 2, dtype=np.int32)
    full.data.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    deg = np.bincount(e.ravel(), minlength=n)[:, None]
    for _ in range(12):
        acc = np.zeros_like(w)
        np.add.at(acc, e[:, 0], w[e[:, 1]])
        np.add.at(acc, e[:, 1], w[e[:, 0]])
        w = 0.5 * w + 0.5 * acc / np.maximum(deg, 1)
    # The face is rigid on the head: the eyes, lashes and hair are, and a face that gave with the neck would
    # slide over them.
    face = (vp <= 1) & ((co[:, 2] > 1.47 * S) | ((co[:, 1] < -0.03 * S) & (co[:, 2] > 1.42 * S)))
    w[face] = 0.0
    w[face, names.index("Head")] = 1.0
    # Blend the edge of that rigid region back into the neck, keeping the features themselves rigid: a hard
    # edge creases under the jaw when the head turns.
    core = (vp <= 1) & ((co[:, 2] > 1.50 * S) | ((co[:, 1] < -0.055 * S) & (co[:, 2] > 1.445 * S)))
    for _ in range(8):
        acc = np.zeros_like(w)
        np.add.at(acc, e[:, 0], w[e[:, 1]])
        np.add.at(acc, e[:, 1], w[e[:, 0]])
        w = 0.5 * w + 0.5 * acc / np.maximum(deg, 1)
        w[core] = 0.0
        w[core, names.index("Head")] = 1.0
    keep = np.argsort(w, axis=1)[:, -4:]
    groups = [full.vertex_groups.new(name=name) for name in names]
    rows = np.arange(n)
    tot = w[rows[:, None], keep].sum(1)
    for c in range(4):
        col = keep[:, c]
        val = w[rows, col] / tot
        for k in np.unique(col):
            idx = rows[(col == k) & (val > 0.004)]
            if len(idx):
                for i, x in zip(idx.tolist(), val[idx].tolist()):
                    groups[k].add([i], x, "REPLACE")


def bind(arm, full, vp):
    """Bone heat on the whole body, then every mesh takes the body's weights (or one bone, where it is rigid)."""
    full.hide_render = True
    full.parent = arm
    full.modifiers.new("Armature", "ARMATURE").object = arm
    body_weights(arm, full, vp)
    deform = [b.name for b in arm.data.bones if not b.name.endswith("_leaf") and b.name != "root"]
    head_only = {"hair": "Head", "brows_lashes": "Head"}
    for o in bpy.data.objects:
        if o.type != "MESH" or o is full or o.name.startswith(("rig_", "floor")):
            continue
        o.parent = arm
        mod = o.modifiers.new("Armature", "ARMATURE")
        mod.object = arm
        bone = head_only.get(o.name) or ("eye_" + o.name[-1].lower() if o.name[:-2] in ("eye", "cornea") else "Head" if o.name[:-2] in ("eyeocc", "tear") else None)
        if bone:
            o.vertex_groups.new(name=bone).add(range(len(o.data.vertices)), 1.0, "REPLACE")
            continue
        L.select_only(o)
        dt = o.modifiers.new("dt", "DATA_TRANSFER")
        dt.object = full
        dt.use_vert_data = True
        dt.data_types_verts = {"VGROUP_WEIGHTS"}
        dt.vert_mapping = "POLYINTERP_NEAREST"
        bpy.ops.object.datalayout_transfer(modifier="dt")
        bpy.ops.object.modifier_move_to_index(modifier="dt", index=0)
        bpy.ops.object.modifier_apply(modifier="dt")
        if "rigid" in o.data.attributes:
            rigid = L.get_float_attr(o.data, "rigid").astype(int)
            names = [g.name for g in o.vertex_groups]
            w = np.zeros((len(o.data.vertices), len(names)))
            for v in o.data.vertices:
                for ge in v.groups:
                    w[v.index, ge.group] = ge.weight
            for rid in np.unique(rigid[rigid > 0]):
                idx = np.where(rigid == rid)[0]
                best = names[int(w[idx].sum(0).argmax())]
                for g in o.vertex_groups:
                    g.remove(idx.tolist())
                o.vertex_groups[best].add(idx.tolist(), 1.0, "REPLACE")
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    return deform


def apply_pose_as_rest(arm):
    for o in skinned(arm):
        L.select_only(o)
        mod = next(m for m in o.modifiers if m.type == "ARMATURE")
        if o.data.shape_keys:
            continue
        bpy.ops.object.modifier_apply(modifier=mod.name)
        m2 = o.modifiers.new("Armature", "ARMATURE")
        m2.object = arm
    L.select_only(arm)
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def library_rest(arm, lib, eye):
    """Give every bone the library's rest orientation, and add the contract's leaves."""
    L.select_only(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    heads = {b.name: b.head.copy() for b in eb}
    scale = heads["pelvis"].z / lib["pelvis"][1].to_translation().z
    for b in eb:
        b.use_connect = False
    for name, (parent, mat, length) in lib.items():
        b = eb[name]
        b.matrix = Matrix.Translation(heads[name]) @ mat.to_3x3().to_4x4()
        b.length = max(length * scale, 0.01)

    def leaf(name, parent, head, like=None, deform=False):
        b = eb.new(name)
        b.parent = eb[parent]
        b.head, b.tail = Vector(head), Vector(head) + Vector((0, 0.05, 0))
        b.matrix = Matrix.Translation(Vector(head)) @ (eb[like].matrix.to_3x3().to_4x4() if like else Matrix.Identity(4))
        b.length = 0.05
        b.use_deform = deform
        return b

    for side, sx in (("l", 1), ("r", -1)):
        ua, la, th = eb[f"upperarm_{side}"], eb[f"lowerarm_{side}"], eb[f"thigh_{side}"]
        leaf(f"upperarm_twist_01_{side}", ua.name, ua.head, ua.name, True)
        leaf(f"lowerarm_twist_01_{side}", la.name, la.head + (eb[f"hand_{side}"].head - la.head) * 0.8, la.name, True)
        leaf(f"thigh_twist_01_{side}", th.name, th.head, th.name, True)
        hand = eb[f"hand_{side}"]
        mid = (hand.head + eb[f"middle_01_{side}"].head) / 2 + Vector((0, 0, -0.035))
        b = leaf(f"socket_hand_{side}", hand.name, mid)
        # Hand sockets: -X along the fingers, +Y towards the thumb's side.
        xa = Vector((-sx, 0, 0))
        ya = Vector((0, -1, 0))
        b.matrix = Matrix.Translation(mid) @ Matrix((xa, ya, xa.cross(ya))).transposed().to_4x4()
        b.length = 0.05
        leaf(f"socket_hip_{side}", "pelvis", (sx * 0.17 * S, 0.0, 0.93 * S))
        leaf(f"ik_foot_{side}", "root", eb[f"foot_{side}"].head, f"foot_{side}")
        leaf(f"ik_hand_{side}", "root", hand.head, hand.name)
        leaf(f"eye_{side}", "Head", (sx * eye[0], eye[1], eye[2]), deform=True)
    leaf("socket_back", "spine_03", (0, 0.105 * S, 1.30 * S))
    leaf("socket_head", "Head", (0, 0.0, 1.645 * S))
    leaf("socket_camera", "Head", (0, -0.125 * S, 1.535 * S))
    for b in eb:
        if b.name.endswith("_leaf") or b.name == "root":
            b.use_deform = False
    bpy.ops.object.mode_set(mode="OBJECT")


def check(arm, lib):
    bones = arm.data.bones
    worst = 0.0
    for name, (parent, mat, _) in lib.items():
        if not parent:
            continue
        mine = (bones[parent].matrix_local.inverted() @ bones[name].matrix_local).to_3x3()
        theirs = (lib[parent][1].inverted() @ mat).to_3x3()
        worst = max(worst, max(abs(a - b) for ra, rb in zip(mine, theirs) for a, b in zip(ra, rb)))
    assert worst < 1e-4, f"a rest rotation differs from the library's by {worst}"
    low, unweighted, total = 9.0, 0, 0
    for o in skinned(arm):
        dg = bpy.context.evaluated_depsgraph_get()
        ev = o.evaluated_get(dg)
        low = min(low, min((ev.matrix_world @ v.co).z for v in ev.data.vertices))
        if o.name == "body_full":
            continue
        total += L.tri_count(o)
        for v in o.data.vertices:
            s = sum(g.weight for g in v.groups)
            assert len(v.groups) <= 4, f"{o.name}: a vertex has {len(v.groups)} weights"
            if abs(s - 1.0) > 0.01:
                unweighted += 1
    assert unweighted == 0, f"{unweighted} vertices are not fully weighted"
    assert low > -0.004, f"the lowest vertex is {low:.4f} m under the floor"
    assert len(bones) == 65 + 17 + 2, f"{len(bones)} bones"
    print("RIG bones", len(bones), "rest rotation error", f"{worst:.1e}", "lowest", round(low, 4), "triangles", total)
    return total


def main():
    L.open_stage(A.work, "s06")
    lib, order = read_library(A.base)
    full = bpy.data.objects["body_full"]
    part = np.empty(len(full.data.polygons), dtype=np.int32)
    full.data.attributes["part"].data.foreach_get("value", part)
    vp = np.zeros(len(full.data.vertices), dtype=np.int32)
    for p in full.data.polygons:
        for v in p.vertices:
            vp[v] = part[p.index]
    j, frames = joints(full, vp, lib)
    arm = build_fit(j, lib, order)
    # The eye bones exist before the bind so the eyeballs have a group to go to; they are placed for good below.
    eye = bpy.context.scene["eye_center"]
    bind(arm, full, vp)
    to_t_pose(arm, frames, lib)
    apply_pose_as_rest(arm)
    library_rest(arm, lib, eye)
    # Fill any vertex bone heat left bare, then check.
    for o in skinned(arm):
        for v in o.data.vertices:
            if not v.groups:
                o.vertex_groups.get("pelvis") or o.vertex_groups.new(name="pelvis")
                o.vertex_groups["pelvis"].add([v.index], 1.0, "REPLACE")
    total = check(arm, lib)
    pelvis = arm.data.bones["pelvis"].head_local.z
    with open(f"{A.work}/rig.json", "w") as f:
        json.dump({"pelvis_height": pelvis, "motion_scale": pelvis / LIB_PELVIS, "bones": len(arm.data.bones), "triangles": total}, f, indent=1)
    print("RIG pelvis", round(pelvis, 4), "motion_scale", round(pelvis / LIB_PELVIS, 4))
    L.save_stage(A.work, "s07")


main()
