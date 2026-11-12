"""Renders the character in Cycles or EEVEE under three lighting setups (a dark interior with rim light, daylight,
a warm interior), as face close-ups, a three-quarter bust, the full body and a turntable.

    blender -b -P s90_render.py -- --work <dir> --stage s07 --engine CYCLES --shots dark:face,day:bust --out <dir>

`--shots` is `light:shot` pairs; with none given it renders every pair. `--res` scales the frame, `--samples`
overrides the sample count.
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_lib as L  # noqa: E402
from rc_nodes import new_material, principled  # noqa: E402

A = L.args()
HEAD = Vector((0.0, -0.03, 1.60))
# shot: camera position, target, lens (mm), frame (px), f-stop
SHOTS = {
    "face": ((0.10, -0.86, 1.605), (0.0, -0.08, 1.585), 85, (1200, 1500), 4.0),
    "face34": ((0.52, -0.70, 1.615), (0.0, -0.06, 1.585), 85, (1200, 1500), 4.0),
    "profile": ((0.88, -0.04, 1.60), (0.0, -0.04, 1.585), 85, (1200, 1500), 4.0),
    "eye": ((0.075, -0.50, 1.59), (0.034, -0.137, 1.581), 100, (1500, 1000), 11.0),
    "bust": ((0.42, -1.18, 1.30), (0.0, 0.0, 1.37), 50, (1200, 1700), 5.6),
    "back": ((-0.5, 1.25, 1.45), (0.0, 0.0, 1.35), 50, (1200, 1700), 5.6),
    "full": ((0.9, -3.7, 1.0), (0.0, 0.0, 0.87), 50, (1100, 1900), 8.0),
    # Her left hand in the T rest (use with --pose rest or --pose fist): its back, its palm, and from the front.
    "hand_back": ((0.80, -0.02, 2.05), (0.80, 0.0, 1.43), 85, (1200, 900), 11.0),
    "hand_palm": ((0.80, -0.02, 0.80), (0.80, 0.0, 1.43), 85, (1200, 900), 11.0),
    "hand_front": ((0.86, -0.62, 1.50), (0.80, 0.0, 1.42), 85, (1200, 900), 11.0),
    "arm": ((0.50, -1.05, 1.55), (0.50, 0.0, 1.43), 50, (1500, 700), 8.0),
}
TURN = 8
LIGHTS = ("dark", "day", "warm")


def to_rig(o):
    for c in list(o.users_collection):
        c.objects.unlink(o)
    bpy.data.collections["rig_light"].objects.link(o)


def area(name, pos, power, colour, size, target=HEAD):
    d = bpy.data.lights.new(name, "AREA")
    d.energy, d.color, d.size = power, colour, size
    o = bpy.data.objects.new(name, d)
    L.link(o, bpy.data.collections["rig_light"])
    o.location = pos
    L.look_at(o, target)
    return o


def emit_plane(name, pos, size, colour, strength, rot=(math.pi / 2, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=pos, rotation=rot)
    o = bpy.context.object
    o.name = name
    m, g = new_material("mat_" + name)
    out = g.node("ShaderNodeOutputMaterial")
    e = g.node("ShaderNodeEmission")
    e.inputs[0].default_value = (*colour, 1)
    e.inputs[1].default_value = strength
    g.link(e.outputs[0], out.inputs[0])
    o.data.materials.append(m)
    to_rig(o)
    return o


def world(colour, strength):
    w = bpy.context.scene.world or bpy.data.worlds.new("world")
    bpy.context.scene.world = w
    t = w.node_tree
    if t is None:
        w.use_nodes = True
        t = w.node_tree
    bg = next(n for n in t.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (*colour, 1)
    bg.inputs[1].default_value = strength


def lighting(kind):
    old = bpy.data.collections.get("rig_light")
    if old:
        for o in list(old.objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(old)
    c = bpy.data.collections.new("rig_light")
    bpy.context.scene.collection.children.link(c)
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    floor = bpy.context.object
    m, g = new_material("mat_floor")
    p, _ = principled(g)
    p.inputs["Roughness"].default_value = 0.75
    floor.data.materials.append(m)
    to_rig(floor)
    if kind == "dark":
        p.inputs["Base Color"].default_value = (0.03, 0.035, 0.04, 1)
        world((0.010, 0.016, 0.026), 1.0)
        area("key", (0.95, -1.7, 2.15), 42, (0.72, 0.84, 1.0), 1.3)
        area("rim_l", (-1.25, 1.2, 2.05), 300, (0.55, 0.78, 1.0), 0.5)
        area("rim_r", (1.5, 1.0, 1.75), 150, (0.62, 0.82, 1.0), 0.5)
        area("fill", (-0.8, -1.6, 0.9), 5, (0.6, 0.75, 1.0), 1.5)
        emit_plane("backdrop", (0, 3.2, 1.5), 9, (0.045, 0.085, 0.12), 0.55)
    elif kind == "day":
        p.inputs["Base Color"].default_value = (0.22, 0.2, 0.17, 1)
        world((0.42, 0.60, 1.0), 0.85)
        d = bpy.data.lights.new("sun", "SUN")
        d.energy, d.color, d.angle = 4.2, (1.0, 0.93, 0.82), math.radians(1.5)
        o = bpy.data.objects.new("sun", d)
        c.objects.link(o)
        o.rotation_euler = (math.radians(52), 0, math.radians(38))
        area("bounce", (0.2, -1.5, 0.3), 30, (1.0, 0.9, 0.75), 2.0)
    else:
        p.inputs["Base Color"].default_value = (0.09, 0.055, 0.035, 1)
        world((0.020, 0.012, 0.008), 1.0)
        area("key", (-1.05, -1.25, 1.95), 75, (1.0, 0.60, 0.30), 0.8)
        area("rim", (1.25, 1.15, 1.95), 130, (1.0, 0.68, 0.36), 0.45)
        area("bounce", (0.5, -1.2, 0.5), 9, (1.0, 0.55, 0.28), 1.6)
        emit_plane("backdrop", (0, 3.2, 1.5), 9, (0.10, 0.045, 0.018), 0.5)


def engine(sc):
    if A.engine == "CYCLES":
        L.cycles_gpu(sc, A.samples or 192)
        sc.cycles.use_adaptive_sampling = True
        sc.cycles.adaptive_threshold = 0.02
    else:
        try:
            sc.render.engine = "BLENDER_EEVEE"
        except TypeError:
            sc.render.engine = "BLENDER_EEVEE_NEXT"
        ee = sc.eevee
        ee.taa_render_samples = A.samples or 64
        for k, v in (("use_raytracing", True), ("use_shadows", True), ("use_gtao", True)):
            if hasattr(ee, k):
                setattr(ee, k, v)
    vs = sc.view_settings
    vs.view_transform = "AgX"
    try:
        vs.look = "AgX - Medium High Contrast"
    except TypeError:
        pass


def main():
    L.open_stage(A.work, A.stage)
    sc = bpy.context.scene
    engine(sc)
    L.show_hair(A.hair)
    rig = bpy.data.objects.get("rig")
    if rig and A.pose == "relaxed":
        L.pose_relaxed(rig)
    elif rig and A.pose == "fist":
        L.pose_fist(rig)
    sc.cycles.transparent_max_bounces = 64
    out = A.out or f"{A.work}/../renders/{A.stage}"
    os.makedirs(out, exist_ok=True)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    L.link(cam)
    sc.camera = cam
    cam.data.dof.use_dof = True
    pairs = [p.split(":") for p in A.shots.split(",")] if A.shots else [(k, s) for k in LIGHTS for s in SHOTS]
    last = None
    for light, shot in pairs:
        if light != last:
            lighting(light)
            last = light
        frames = [(shot, SHOTS[shot])] if shot != "turn" else []
        if shot == "turn":
            pos, tgt, lens, res, fs = SHOTS["full"]
            for i in range(TURN):
                a = 2 * math.pi * i / TURN
                p = Vector(pos)
                rot = (p.x * math.cos(a) - p.y * math.sin(a), p.x * math.sin(a) + p.y * math.cos(a), p.z)
                frames.append((f"turn{i}", (rot, tgt, lens, (res[0] // 2, res[1] // 2), fs)))
        for name, (pos, tgt, lens, res, fstop) in frames:
            cam.location = pos
            L.look_at(cam, tgt)
            cam.data.lens = lens
            cam.data.dof.focus_distance = (Vector(tgt) - Vector(pos)).length
            cam.data.dof.aperture_fstop = fstop
            sc.render.resolution_x, sc.render.resolution_y = int(res[0] * A.res), int(res[1] * A.res)
            sc.render.filepath = f"{out}/{A.engine.lower()}_{A.hair}_{light}_{name}.png"
            bpy.ops.render.render(write_still=True)
            print("RENDERED", sc.render.filepath)


main()
