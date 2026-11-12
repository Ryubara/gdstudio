"""Stage 6: texture sets for the clothes and the gear. Every look (jersey, canvas, leather, webbing, polymer,
steel...) is a small procedural recipe with its wear: fading, sweat, dried mud, scuffs, worn edges. Each mesh bakes
to one set: albedo, normal (the recipe's bump), ORM (ambient occlusion with the body in place, roughness,
metallic) and a mask whose red channel says where the tiling weave normal applies.
"""

import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_lib as L  # noqa: E402
import rc_materials as M  # noqa: E402
from rc_nodes import new_material  # noqa: E402

A = L.args()
TEX = f"{A.work}/tex"
S = L.SCALE
SIZES = {"outfit": 1024 if A.quick else 4096, "gear": 512 if A.quick else 2048}


def cloth(g, colour, fade=0.25, dirt=0.5, weave=1.0, rough=0.86):
    big, mid = g.noise(7, 3), g.noise(45, 4, 0.6)
    col = g.mixc(tuple(v * 0.82 for v in colour), tuple(v * 1.18 for v in colour), mid)
    pale = tuple(min(1.0, v * 1.9 + 0.03) for v in colour)
    col = g.mixc(col, pale, g.ramp(big, 0.45, 0.8, 0, fade))
    grime_n = g.noise(26, 5, 0.7)
    grime = g.ramp(grime_n, 0.48, 0.74, 0, dirt)
    col = g.mixc(col, (0.045, 0.036, 0.028), grime)
    wr = g.ridge(g.noise(1.0, 3, 0.55, stretch=(22, 22, 70)))
    wr2 = g.ridge(g.noise(1.0, 2, 0.5, stretch=(60, 60, 25)))
    h = g.add(g.mul(g.ramp(wr, 0.55, 1.0), 0.7), g.mul(g.ramp(wr2, 0.65, 1.0), 0.3))
    return {"albedo": col, "rough": g.mixf(rough, 0.95, grime), "metal": 0.0, "height": h, "weave": weave, "depth": 0.0011}


def look_top(g):
    p = cloth(g, (0.070, 0.080, 0.050), fade=0.3, dirt=0.45)
    # Sweat soaks the chest, the small of the back and under the arms: darker, a little shinier.
    wet = g.ramp(g.dist((0, -0.10 * S, 1.27 * S)), 0.03, 0.11, 1, 0)
    wet = g.math("MAXIMUM", wet, g.ramp(g.dist((0, 0.10 * S, 1.17 * S)), 0.04, 0.13, 1, 0))
    for sx in (1, -1):
        wet = g.math("MAXIMUM", wet, g.ramp(g.dist((sx * 0.16 * S, 0.0, 1.24 * S)), 0.03, 0.09, 1, 0))
    wet = g.mul(wet, g.ramp(g.noise(18, 4, 0.6), 0.25, 0.7))
    p["albedo"] = g.mixc(p["albedo"], (0.040, 0.046, 0.026), g.mul(wet, 0.72))
    p["rough"] = g.mixf(p["rough"], 0.55, wet)
    return p


def look_trousers(g):
    p = cloth(g, (0.062, 0.054, 0.046), fade=0.3, dirt=0.35, rough=0.9)
    z = g.xyz()[2]
    worn = g.math("MAXIMUM", g.ramp(g.dist((0.107 * S, -0.07 * S, 0.49 * S)), 0.03, 0.10, 1, 0),
                  g.ramp(g.dist((-0.107 * S, -0.07 * S, 0.49 * S)), 0.03, 0.10, 1, 0))
    worn = g.mul(worn, g.ramp(g.noise(60, 4, 0.7), 0.3, 0.7))
    p["albedo"] = g.mixc(p["albedo"], (0.20, 0.18, 0.155), g.mul(worn, 0.55))
    mud = g.mul(g.ramp(z, 0.42, 0.10), g.ramp(g.noise(22, 5, 0.7), 0.42, 0.62))
    p["albedo"] = g.mixc(p["albedo"], (0.21, 0.155, 0.10), g.mul(mud, 0.85))
    p["height"] = g.add(p["height"], g.mul(mud, g.noise(300, 2)))
    return p


def hard(g, colour, rough, metal=0.0, edge=(0.3, 0.3, 0.3), edge_amt=0.6, scratch=0.3, grain=0.0):
    pt = g.ramp(g.pointiness(), 0.53, 0.62)
    wear = g.sat(g.mul(pt, g.ramp(g.noise(120, 3, 0.7), 0.25, 0.7)))
    sc = g.ramp(g.noise(1.0, 2, 0.7, stretch=(900, 40, 40)), 0.68, 0.8, 0, scratch)
    col = g.mixc(tuple(v * 0.85 for v in colour), tuple(v * 1.15 for v in colour), g.noise(30, 3))
    col = g.mixc(col, edge, g.sat(g.add(g.mul(wear, edge_amt), sc)))
    dust = g.ramp(g.noise(18, 5, 0.7), 0.55, 0.8, 0, 0.3)
    col = g.mixc(col, (0.12, 0.095, 0.07), dust)
    h = g.sub(g.mul(g.ramp(g.voronoi(1500, "F1"), 0.0, 0.5), grain), sc)
    return {"albedo": col, "rough": g.mixf(g.mixf(rough, rough * 0.6, wear) if metal else g.mixf(rough, 0.8, wear), 0.9, dust),
            "metal": metal, "height": h, "weave": 0.0, "depth": 0.0004}


def look_boot(g):
    p = hard(g, (0.040, 0.022, 0.012), 0.52, edge=(0.17, 0.105, 0.06), edge_amt=0.5, scratch=0.5, grain=1.0)
    z = g.xyz()[2]
    mud = g.mul(g.ramp(z, 0.07, 0.015), g.ramp(g.noise(40, 5, 0.7), 0.45, 0.7))
    p["albedo"] = g.mixc(p["albedo"], (0.16, 0.12, 0.08), g.mul(mud, 0.8))
    p["rough"] = g.mixf(p["rough"], 0.95, mud)
    creases = g.ridge(g.noise(1.0, 3, 0.5, stretch=(30, 120, 30)))
    p["height"] = g.add(p["height"], g.mul(g.ramp(creases, 0.7, 1.0), -1.5))
    return p


def look_wrap(g):
    p = cloth(g, (0.42, 0.37, 0.29), fade=0.2, dirt=0.75)
    turns = g.math("FRACT", g.mul(g.dot((-0.50, 0.0, -0.87)), 34.0))
    edge = g.ramp(turns, 0.0, 0.10, 1, 0)
    p["albedo"] = g.mixc(p["albedo"], (0.10, 0.085, 0.06), g.mul(edge, 0.6))
    p["height"] = g.add(g.mul(p["height"], 0.4), g.mul(turns, 1.2))
    blood = g.mul(g.ramp(g.dist((-0.335 * S, -0.005, 1.035 * S)), 0.015, 0.05, 1, 0), g.ramp(g.noise(60, 4, 0.7), 0.3, 0.6))
    p["albedo"] = g.mixc(p["albedo"], (0.10, 0.012, 0.010), g.mul(blood, 0.85))
    return p


LOOKS = {
    "top": look_top,
    "bra": lambda g: cloth(g, (0.018, 0.018, 0.022), fade=0.1, dirt=0.2, rough=0.78),
    "trousers": look_trousers,
    "boot": look_boot,
    "sole": lambda g: hard(g, (0.012, 0.012, 0.012), 0.9, edge=(0.06, 0.055, 0.05), scratch=0.2),
    "lace": lambda g: cloth(g, (0.11, 0.09, 0.06), dirt=0.6, weave=0.0),
    "belt": lambda g: hard(g, (0.030, 0.017, 0.010), 0.5, edge=(0.14, 0.085, 0.05), edge_amt=0.7, scratch=0.4, grain=0.8),
    "metal": lambda g: hard(g, (0.40, 0.38, 0.35), 0.40, metal=1.0, edge=(0.6, 0.58, 0.55), scratch=0.25),
    "gunmetal": lambda g: hard(g, (0.030, 0.030, 0.034), 0.36, metal=0.9, edge=(0.42, 0.42, 0.43), edge_amt=0.8, scratch=0.2),
    "grip": lambda g: hard(g, (0.018, 0.016, 0.014), 0.7, edge=(0.06, 0.06, 0.06), scratch=0.1, grain=1.5),
    "polymer": lambda g: hard(g, (0.014, 0.014, 0.016), 0.46, edge=(0.09, 0.09, 0.095), edge_amt=0.7, scratch=0.5),
    "webbing": lambda g: cloth(g, (0.022, 0.026, 0.020), fade=0.3, dirt=0.4, rough=0.82),
    "pouch": lambda g: cloth(g, (0.165, 0.125, 0.075), fade=0.35, dirt=0.5),
    "wrap": look_wrap,
    "glass": lambda g: {"albedo": (0.008, 0.008, 0.010), "rough": 0.06, "metal": 0.0, "height": 0.0, "weave": 0.0, "depth": 0.0001},
}


def weave_tile(size=256):
    """A tiling plain-weave normal map: over-and-under threads, drawn as two crossed cosine ridges."""
    v, u = np.mgrid[0:size, 0:size] / size
    k = 2 * np.pi * 8
    over = (np.sin(k * u / 2) * np.sin(k * v / 2)) > 0
    h = np.where(over, np.cos(k * v) * 0.5 + 0.5, np.cos(k * u) * 0.5 + 0.5) * (0.6 + 0.4 * np.abs(np.sin(k * u / 2) * np.sin(k * v / 2)))
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * size / 16
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * size / 16
    n = np.stack([-dx, -dy, np.ones_like(h) * 4], 2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    img = bpy.data.images.new("weave", size, size, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    px = np.ones((size, size, 4), dtype=np.float32)
    px[..., :3] = n * 0.5 + 0.5
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = f"{TEX}/detail_weave_normal.png"
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def bake_object(sc, obj):
    size = SIZES[obj.name]
    slots = []
    for slot in obj.material_slots:
        look = slot.material.name[3:].split(".")[0]
        m, g = new_material(f"bake_{obj.name}_{look}")
        p = LOOKS[look](g)
        e = g.node("ShaderNodeEmission")
        b = g.node("ShaderNodeBsdfPrincipled")
        bump = g.node("ShaderNodeBump")
        bump.inputs["Distance"].default_value = p["depth"]
        g.set(bump.inputs["Height"], p["height"])
        g.link(bump.outputs[0], b.inputs["Normal"])
        out = g.node("ShaderNodeOutputMaterial")
        t = g.node("ShaderNodeTexImage")
        g.t.nodes.active = t
        slot.material = m
        slots.append((g, p, e, b, out, t))
    L.select_only(obj)
    px = {}
    for name, kind, colour in (("albedo", "EMIT", True), ("rough", "EMIT", False), ("metal", "EMIT", False),
                               ("weave", "EMIT", False), ("normal", "NORMAL", False), ("ao", "AO", False)):
        img = bpy.data.images.new(f"{obj.name}_{name}", size, size, alpha=False)
        img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        for g, p, e, b, out, t in slots:
            t.image = img
            if kind == "EMIT":
                for link in list(e.inputs[0].links):
                    g.t.links.remove(link)
                if isinstance(p[name], (int, float)):
                    e.inputs[0].default_value = (p[name],) * 3 + (1,)
                else:
                    g.set(e.inputs[0], p[name])
                g.link(e.outputs[0], out.inputs[0])
            else:
                g.link(b.outputs[0], out.inputs[0])
        sc.cycles.samples = 48 if kind == "AO" else 12
        bpy.ops.object.bake(type=kind, margin=12, use_clear=True, normal_space="TANGENT")
        a = np.empty(size * size * 4, dtype=np.float32)
        img.pixels.foreach_get(a)
        px[name] = a.reshape(size, size, 4)
        bpy.data.images.remove(img)

    def save(name, rgb, colour):
        img = bpy.data.images.new("out", size, size, alpha=False)
        img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        o = np.ones((size, size, 4), dtype=np.float32)
        o[..., :3] = rgb
        img.pixels.foreach_set(o.ravel())
        img.filepath_raw = f"{TEX}/{obj.name}_{name}.png"
        img.file_format = "PNG"
        img.save()
        bpy.data.images.remove(img)

    save("albedo", px["albedo"][..., :3], True)
    save("normal", px["normal"][..., :3], False)
    save("orm", np.stack([px["ao"][..., 0], px["rough"][..., 0], px["metal"][..., 0]], 2), False)
    save("mask", np.stack([px["weave"][..., 0], np.zeros((size, size)), np.zeros((size, size))], 2), False)
    game = M.pbr(obj.name, TEX, obj.name, detail_scale=320.0 if obj.name == "outfit" else 160.0, two_sided=True)
    obj.data.materials.clear()
    obj.data.materials.append(game)
    obj.data.polygons.foreach_set("material_index", np.zeros(len(obj.data.polygons), dtype=np.int32))
    print("TEXSET", obj.name, size)


def main():
    L.open_stage(A.work, "s05")
    sc = bpy.context.scene
    L.cycles_gpu(sc, 12)
    sc.render.bake.use_multires = False
    weave_tile()
    for name in ("outfit", "gear"):
        bake_object(sc, bpy.data.objects[name])
    L.save_stage(A.work, "s06")


main()
