"""Shared helpers of the realistic character build (kit docs: tools/blender/realistic-characters.md).

Every stage is run headless by build.py as `blender -b -P <stage>.py -- --work <dir> [--base <blend>]`; a stage
opens the .blend the stage before it saved in the work folder and saves its own.
"""

import argparse
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

SCALE = 1.03  # the base body is 1.64 m; ours stands 1.69 m


def args():
    p = argparse.ArgumentParser()
    p.add_argument("--work", required=True)
    p.add_argument("--base", default="")
    p.add_argument("--quick", action="store_true")
    p.add_argument("--only", default="")
    p.add_argument("--engine", default="CYCLES")
    p.add_argument("--res", type=float, default=1.0)
    p.add_argument("--stage", default="")
    p.add_argument("--shots", default="")
    p.add_argument("--samples", type=int, default=0)
    p.add_argument("--out", default="")
    p.add_argument("--hair", default="ponytail", help="the hairstyle a render shows: ponytail or long")
    p.add_argument("--pose", default="relaxed", help="the pose a render uses: relaxed, rest or fist")
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    a = p.parse_args(argv)
    a.work = a.work.replace("\\", "/").rstrip("/")
    os.makedirs(a.work, exist_ok=True)
    return a


def open_stage(work, name):
    bpy.ops.wm.open_mainfile(filepath=f"{work}/{name}.blend")


def save_stage(work, name):
    bpy.ops.wm.save_as_mainfile(filepath=f"{work}/{name}.blend", compress=True)
    print("SAVED", f"{work}/{name}.blend")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def co_get(mesh):
    a = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", a)
    return a.reshape(-1, 3).astype(np.float64)


def co_set(mesh, co):
    mesh.vertices.foreach_set("co", co.astype(np.float32).ravel())
    mesh.update()


def normals_get(mesh):
    a = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("normal", a)
    return a.reshape(-1, 3).astype(np.float64)


def tri_count(obj):
    m = obj.data
    m.calc_loop_triangles()
    return len(m.loop_triangles)


def select_only(obj):
    for o in bpy.context.view_layer.objects:
        if o is not None:
            o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def link(obj, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def new_mesh_obj(name, verts, faces, coll=None):
    m = bpy.data.meshes.new(name)
    m.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    m.update()
    o = bpy.data.objects.new(name, m)
    link(o, coll)
    return o


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def gauss(co, c, sigma):
    d = co - np.asarray(c, dtype=np.float64)
    if np.isscalar(sigma):
        return np.exp(-(d * d).sum(1) / (2 * sigma * sigma))
    s = np.asarray(sigma, dtype=np.float64)
    return np.exp(-((d / s) ** 2).sum(1) / 2)


def set_float_attr(mesh, name, values, domain="POINT"):
    a = mesh.attributes.get(name) or mesh.attributes.new(name, "FLOAT", domain)
    a.data.foreach_set("value", np.asarray(values, dtype=np.float32))


def get_float_attr(mesh, name):
    a = mesh.attributes[name]
    out = np.empty(len(a.data), dtype=np.float32)
    a.data.foreach_get("value", out)
    return out


def value_noise3(p, seed=0):
    """Cheap smooth value noise on an (n, 3) array, in 0..1 (for masks on vertices)."""
    pi = np.floor(p).astype(np.int64)
    pf = p - pi
    w = pf * pf * (3 - 2 * pf)

    def h(i, j, k):
        n = (i * 374761393 + j * 668265263 + k * 2147483647 + seed * 974711) & 0xFFFFFFFF
        n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

    x0, y0, z0 = pi[:, 0], pi[:, 1], pi[:, 2]
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                wx = w[:, 0] if dx else 1 - w[:, 0]
                wy = w[:, 1] if dy else 1 - w[:, 1]
                wz = w[:, 2] if dz else 1 - w[:, 2]
                out = out + h(x0 + dx, y0 + dy, z0 + dz) * wx * wy * wz
    return out


def fbm3(p, octaves=4, seed=0):
    out = 0
    amp = 0.5
    for o in range(octaves):
        out = out + amp * value_noise3(p * (2**o), seed + o * 17)
        amp *= 0.5
    return out / (1 - 0.5**octaves)


def write_png16(path, rgb):
    """A 16-bit RGB PNG from a float array (height, width, 3) in 0..1, first row at the bottom as Blender stores
    it. Blender's own image save writes 8 bits unless it goes through a render's colour management; a normal map
    needs neither."""
    import struct
    import zlib

    a = (np.clip(rgb[::-1], 0, 1) * 65535 + 0.5).astype(">u2")
    h, w = a.shape[:2]
    raw = np.concatenate([np.zeros((h, 1), dtype=np.uint8), np.ascontiguousarray(a).reshape(h, w * 3).view(np.uint8)], 1).tobytes()

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(bytes([137, 80, 78, 71, 13, 10, 26, 10]) + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 3)) + chunk(b"IEND", b""))


# Her hair: a chestnut brown, in linear RGB. The strands of the atlas vary around it and a share are sun-lightened;
# the scalp under the cards is painted in its shade so no gap between cards shows skin or a black cap.
HAIR_RGB = np.array([0.105, 0.056, 0.027])
HAIR_LIGHT = np.array([0.30, 0.185, 0.090])


HAIRSTYLES = ("ponytail", "long")


def show_hair(style):
    """Only one hairstyle is ever drawn: hide the others from the viewport and the render."""
    for name in HAIRSTYLES:
        o = bpy.data.objects.get("hair_" + name)
        if o:
            o.hide_render = name != style
            o.hide_viewport = name != style


def cycles_gpu(scene, samples=128):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for kind in ("OPTIX", "CUDA"):
        try:
            prefs.compute_device_type = kind
            prefs.get_devices()
            used = False
            for d in prefs.devices:
                d.use = d.type == kind
                used = used or d.use
            if used:
                scene.cycles.device = "GPU"
                break
        except Exception:
            continue
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    return scene.cycles.device


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def deg(x):
    return math.radians(x)


def scalp_mask(c, soft=0.0):
    """Where hair grows, 0..1, for positions in the base mesh's metres (position / SCALE). The hairline of a head
    seen from the side: from the forehead it falls to the front of the ear (a line, receding at the temples, with
    a sideburn), passes over the ear, drops behind it and runs level across the nape. `soft` widens the edge
    (metres each way): the painted scalp fades over a centimetre, the cards start inside it. (The first build cut
    one plane from the forehead to the nape, which left the head bare behind the ears: fine under a short cut,
    an undercut under a ponytail.)"""
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    f, n = np.array([-0.122, 1.597]), np.array([-0.030, 1.532])
    d = n - f
    nrm = np.array([-d[1], d[0]]) / np.linalg.norm(d)
    s = (np.stack([y, z], 1) - f) @ nrm
    s -= 0.013 * np.exp(-(((ax - 0.060) / 0.016) ** 2)) * (y < -0.045)
    s += 0.012 * np.exp(-(((y + 0.030) / 0.010) ** 2 + ((z - 1.535) / 0.02) ** 2)) * (ax > 0.06)
    low = 1.558 - (1.558 - 1.476) * smoothstep(0.010, 0.050, y)   # over the ear, then down to the nape
    s = np.minimum(s, z - low)
    s += 0.006 * (fbm3(c * 60, 3, 1) - 0.5)
    ear = np.maximum(gauss(c, (0.086, 0.012, 1.515), 0.022), gauss(c, (-0.086, 0.012, 1.515), 0.022))
    return smoothstep(-0.003 - soft, 0.006 + soft, s) * (z > 1.44) * (1 - np.clip(ear * 1.8, 0, 1))


def brow_field(c):
    """The eyebrows for positions in the base mesh's metres: (mask 0..1, position along the brow 0 inner..1 tail).
    A centre line rises to a peak and falls to the tail; the hair thins towards the tail."""
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    front = (y < -0.035) & (z > 1.40)
    bx = np.clip((ax - 0.010) / 0.046, 0, 1)
    bz = np.where(bx < 0.62, 1.5445 + (1.5508 - 1.5445) * smoothstep(0, 1, bx / 0.62),
                  1.5508 - (1.5508 - 1.5462) * ((bx - 0.62) / 0.38) ** 1.3)
    bh = 0.0040 - 0.0029 * bx**1.4
    brow = smoothstep(1.0, 0.25, np.abs(z - bz) / bh) * (ax > 0.0085) * (ax < 0.0565) * front
    brow *= smoothstep(0.0, 0.08, bx) * (1 - 0.7 * smoothstep(0.8, 1.0, bx))
    return brow, bx


def pose_turn(arm, name, q):
    """Turn a pose bone about its own head by quaternion `q`, given in armature space."""
    from mathutils import Matrix

    pb = arm.pose.bones[name]
    loc = pb.matrix.to_translation()
    pb.matrix = Matrix.Translation(loc) @ q.to_matrix().to_4x4() @ Matrix.Translation(-loc) @ pb.matrix
    bpy.context.view_layer.update()


def pose_aim(arm, name, child, direction):
    """Turn a pose bone so the line from its head to `child`'s head points along `direction`."""
    bpy.context.view_layer.update()
    pb = arm.pose.bones[name]
    cur = (arm.pose.bones[child].head - pb.head).normalized()
    pose_turn(arm, name, cur.rotation_difference(Vector(direction).normalized()))


def pose_relaxed(arm):
    """The pose the renders use: standing at ease, arms hanging a little off the body, the left knee soft, the
    head turned to her left. Set from the T rest by aiming each limb."""
    from mathutils import Matrix, Quaternion

    z = Vector((0, 0, 1))
    pose_turn(arm, "spine_03", Quaternion(z, math.radians(5)))
    pose_turn(arm, "neck_01", Quaternion(z, math.radians(5)))
    pose_turn(arm, "Head", Quaternion(z, math.radians(9)))
    pose_turn(arm, "Head", Quaternion(Vector((0, 1, 0)), math.radians(-3)))
    for side, sx, upper, lower in (("l", 1, (0.20, -0.04, -1), (0.10, -0.22, -1)), ("r", -1, (-0.30, 0.03, -1), (-0.16, -0.38, -1))):
        pose_aim(arm, f"upperarm_{side}", f"lowerarm_{side}", upper)
        pose_aim(arm, f"lowerarm_{side}", f"hand_{side}", lower)
        pose_aim(arm, f"hand_{side}", f"middle_01_{side}", (lower[0] * 0.5, lower[1] * 1.3, -1))
        hb = arm.pose.bones[f"hand_{side}"]
        delta = hb.matrix.to_3x3() @ arm.data.bones[hb.name].matrix_local.to_3x3().inverted()
        axis = delta @ Vector((0, 1, 0))
        for f in ("index", "middle", "ring", "pinky"):
            for k, a in ((1, 16), (2, 22), (3, 14)):
                pose_turn(arm, f"{f}_0{k}_{side}", Quaternion(axis, math.radians(a * sx)))
    pose_aim(arm, "thigh_l", "calf_l", (0.06, -0.13, -1))
    pose_aim(arm, "calf_l", "foot_l", (0.03, 0.09, -1))
    bpy.context.view_layer.update()
    fb = arm.pose.bones["foot_l"]
    yaw = Quaternion(z, math.radians(14)).to_matrix()
    fb.matrix = Matrix.Translation(fb.matrix.to_translation()) @ (yaw @ arm.data.bones["foot_l"].matrix_local.to_3x3()).to_4x4()
    bpy.context.view_layer.update()


# Female hand proportions the build fits and checks (shares of standing height unless said otherwise). Sources:
# the US Army's ANSUR II survey of women (hand length 181 mm and hand breadth 79 mm at a stature of 1,629 mm:
# 11.1 % and 4.9 %) and Drillis and Contini's segment lengths (hand 10.8 %, forearm 14.6 %: a hand is 0.74 of a
# forearm). The first build's hands were 11.7 % long and 5.4 % wide on a forearm of 13.3 %.
HAND_LENGTH = 0.107
HAND_BREADTH = 0.048
HAND_TO_FOREARM = (0.70, 0.80)
ELBOW_SHARE = 0.585  # the elbow's place on the line from the shoulder joint to the wrist


def vertex_parts(mesh):
    """For a mesh with the `part` face attribute: boolean vertex masks (in the arm tile, in the hand tile)."""
    part = np.empty(len(mesh.polygons), dtype=np.int32)
    mesh.attributes["part"].data.foreach_get("value", part)
    lt = np.empty(len(mesh.polygons), dtype=np.int32)
    mesh.polygons.foreach_get("loop_total", lt)
    lv = np.empty(len(mesh.loops), dtype=np.int32)
    mesh.loops.foreach_get("vertex_index", lv)
    lp = np.repeat(part, lt)
    arm = np.zeros(len(mesh.vertices), dtype=bool)
    hand = np.zeros(len(mesh.vertices), dtype=bool)
    arm[lv[lp == 3]] = True
    hand[lv[lp == 4]] = True
    return arm, hand


def hand_frame(co, arm, hand, sx):
    """Measures one hand of a body in any pose. The base mesh's hand tile starts 8 cm up the forearm, so the
    wrist is found, not read: the last section before the palm flares (within 10 % of the thinnest). Returns a dict with `wrist`
    (the section's centre), the unit axes `a` (to the fingertips), `lat` (to the thumb's side) and `th`, the hand's
    `length` (wrist to the tip of the longest finger), its `breadth` (across the knuckles, thumb left out) and
    `knuckle` (how far along the knuckle line is)."""
    side = sx * co[:, 0] > 0
    pts = co[side & hand]
    seam = co[side & hand & arm].mean(0)
    mean = pts.mean(0)
    w, v = np.linalg.eigh(np.cov((pts - mean).T))
    a = v[:, 2] if v[:, 2] @ (mean - seam) > 0 else -v[:, 2]
    lat, th = v[:, 1], v[:, 0]
    al, s, t = (pts - seam) @ a, (pts - seam) @ lat, (pts - seam) @ th
    full = al.max()
    xs, areas = [], []
    for x in np.arange(0.02, 0.5 * full, 0.0025):
        sl = np.abs(al - x) < 0.005
        if sl.sum() >= 6:
            xs.append(x)
            areas.append(np.ptp(s[sl]) * np.ptp(t[sl]))
    # The forearm's last centimetres are nearly even: the wrist is where that ends and the palm starts to flare.
    at = max(x for x, area in zip(xs, areas) if area < 1.10 * min(areas))
    sl = np.abs(al - at) < 0.005
    wrist = seam + a * at + lat * (s[sl].max() + s[sl].min()) / 2 + th * (t[sl].max() + t[sl].min()) / 2
    al, s = (pts - wrist) @ a, (pts - wrist) @ lat
    length = al.max()
    # The thumb's side: where the hand is widest before the fingers part.
    near = (al > 0.2 * length) & (al < 0.5 * length)
    if abs(s[near].max()) < abs(s[near].min()):
        lat, s = -lat, -s
    # The knuckle line: the last section before the fingers part. Hand breadth leaves the thumb out, so it is read
    # only once the thumb stands clear of the palm (a gap on its side), and the thumb's part is dropped.
    breadth, knuckle, clear = 0.0, 0.0, False
    for x in np.arange(0.30 * length, 0.70 * length, 0.0025):
        sl = np.abs(al - x) < 0.004
        ss = np.sort(s[sl])
        wide = np.where(np.diff(ss) > 0.006)[0]
        thumb = [i for i in wide if ss[i] > 0.25 * ss.max()]
        if len(wide) > len(thumb):
            break
        if thumb:
            clear = True
            ss = ss[: thumb[0] + 1]
        if clear:
            breadth, knuckle = float(np.ptp(ss)), float(x)
    if np.cross(a, lat) @ th < 0:
        th = -th
    return {"wrist": wrist, "a": a, "lat": lat, "th": th, "length": float(length), "breadth": breadth,
            "knuckle": knuckle, "seam": seam}


def pose_fist(arm):
    """Both hands closed, from the T rest: each finger joint turned about the hand's knuckle axis (armature Y in
    the T pose), the thumb folded over the index. The check of the finger joints and weights."""
    from mathutils import Quaternion

    y, z, x = Vector((0, 1, 0)), Vector((0, 0, 1)), Vector((1, 0, 0))
    for side, sx in (("l", 1), ("r", -1)):
        for f in ("index", "middle", "ring", "pinky"):
            for k, a in ((1, 78), (2, 98), (3, 62)):
                pose_turn(arm, f"{f}_0{k}_{side}", Quaternion(y, math.radians(a * sx)))
        pose_turn(arm, f"thumb_01_{side}", Quaternion(x, math.radians(-38 * sx)))
        pose_turn(arm, f"thumb_01_{side}", Quaternion(z, math.radians(22 * sx)))
        pose_turn(arm, f"thumb_02_{side}", Quaternion(z, math.radians(32 * sx)))
        pose_turn(arm, f"thumb_03_{side}", Quaternion(z, math.radians(48 * sx)))
    bpy.context.view_layer.update()
