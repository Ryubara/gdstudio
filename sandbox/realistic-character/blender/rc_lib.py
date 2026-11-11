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


def scalp_mask(c):
    """Where hair grows, 0..1, for positions in the base mesh's metres (position / SCALE): above a plane from the
    forehead's hairline to the nape, receding at the temples, with sideburns, the ears left out."""
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    f, n = np.array([-0.122, 1.597]), np.array([0.078, 1.492])
    d = n - f
    nrm = np.array([-d[1], d[0]]) / np.linalg.norm(d)
    s = (np.stack([y, z], 1) - f) @ nrm
    s -= 0.013 * np.exp(-(((ax - 0.060) / 0.016) ** 2)) * (y < -0.045)
    s += 0.020 * np.exp(-(((y + 0.025) / 0.012) ** 2 + ((z - 1.535) / 0.02) ** 2)) * (ax > 0.06)
    s += 0.006 * (fbm3(c * 60, 3, 1) - 0.5)
    ear = np.maximum(gauss(c, (0.086, 0.012, 1.515), 0.022), gauss(c, (-0.086, 0.012, 1.515), 0.022))
    return smoothstep(-0.003, 0.006, s) * (z > 1.44) * (1 - np.clip(ear * 1.8, 0, 1))


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
