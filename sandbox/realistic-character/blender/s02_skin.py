"""Stage 2: the skin's texture sets. Paints the skin by rule (zones on the vertices of the level-3 surface, fine
detail as 3D procedural textures) and bakes it to the head and body sets:

- `<set>_albedo.png` (sRGB), `<set>_normal.png` (tangent space, +Y), `<set>_orm.png` (R ambient occlusion,
  G roughness, B unused) and `<set>_mask.png` (R subsurface amount, G sweat film, B unused).

The normal map is two bakes combined: the sculpt's levels 1 against 3 (Blender's multires bake) and the painted
pores and creases (a Cycles normal bake of the level-3 surface in its own UVs).
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
SIZE = 1024 if A.quick else 4096
SETS = ("head", "body")
TEX = f"{A.work}/tex"


def paint_masks(obj):
    """Zones as float attributes on the vertices: where the skin is red, oily, lips, brow, scalp, dirty, wet."""
    mesh = obj.data
    c = L.co_get(mesh) / L.SCALE  # the landmarks below are in the base mesh's metres
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    head = z > 1.40
    front = (y < -0.035) & head

    def gxz(x0, z0, sx, sz):
        return np.exp(-(((ax - x0) / sx) ** 2 + ((z - z0) / sz) ** 2) / 2) * front

    def g3(c0, s, mirror=True):
        out = L.gauss(c, c0, s)
        if mirror:
            out = np.maximum(out, L.gauss(c, (-c0[0], c0[1], c0[2]), s))
        return out

    def seg(p0, p1, sigma):
        """Distance falloff from a segment drawn on the face in the front view (x, z)."""
        p = np.stack([x, z], 1)
        a, b = np.array(p0), np.array(p1)
        t = np.clip(((p - a) @ (b - a)) / ((b - a) @ (b - a)), 0, 1)
        d = np.linalg.norm(p - (a + t[:, None] * (b - a)), axis=1)
        return np.exp(-((d / sigma) ** 2) / 2) * front

    n1 = L.fbm3(c * 60, 3, 1)
    n2 = L.fbm3(c * 25, 3, 5)
    hand = (ax > 0.29) & (z < 0.97)
    arm = (ax > 0.14) & (z < 1.30) & ~hand
    ear = g3((0.086, 0.012, 1.515), 0.022)

    red = 0.85 * gxz(0.046, 1.494, 0.017, 0.014) + 0.9 * gxz(0.0, 1.502, 0.012, 0.010)
    red += 0.5 * gxz(0.0165, 1.497, 0.007, 0.006) + 0.35 * gxz(0.0, 1.437, 0.014, 0.008) + 0.9 * ear
    red += 0.35 * hand * n1 * 2 + 0.25 * g3((0.0, -0.07, 1.36), 0.06, False) * (z < 1.40)
    yellow = gxz(0.0, 1.588, 0.045, 0.020)
    blue = 0.9 * gxz(0.033, 1.5215, 0.013, 0.005) + 0.55 * gxz(0.033, 1.5435, 0.012, 0.004)
    blue += 0.3 * gxz(0.066, 1.545, 0.010, 0.012)
    oily = np.clip(gxz(0.0, 1.585, 0.04, 0.02) + gxz(0.0, 1.51, 0.012, 0.022) + 0.7 * gxz(0.0, 1.44, 0.014, 0.01)
                   + 0.6 * gxz(0.052, 1.515, 0.014, 0.008), 0, 1)

    # Lips: between an upper and a lower border drawn around the mouth line.
    zm, half = 1.4662, 0.0270
    xn = np.clip(ax / half, 0, 1)
    upper = zm + 0.0098 * (1 - xn**2) ** 0.75 - 0.0013 * np.exp(-((x / 0.004) ** 2))
    lower = zm - 0.0092 * (1 - xn**2.2) ** 0.6
    lip = L.smoothstep(-0.0006, 0.0008, upper - z) * L.smoothstep(-0.0006, 0.0008, z - lower)
    lip *= (ax < half) * (y < -0.085) * head

    brow = L.brow_field(c)[0]
    scalp = L.scalp_mask(c)

    freckle = np.clip(gxz(0.0, 1.512, 0.055, 0.017) + 0.22 * ((z > 1.24) & (z < 1.44)) + 0.10 * arm, 0, 1)
    grime = 0.55 * g3((0.058, -0.085, 1.482), 0.018, False) + 0.5 * g3((-0.035, -0.10, 1.588), 0.020, False)
    grime += 0.6 * g3((-0.06, -0.02, 1.40), 0.035, False) + 0.5 * g3((0.10, -0.06, 1.33), 0.05, False)
    grime += 0.7 * hand + 0.45 * arm * L.smoothstep(1.25, 0.95, z) + 0.15 * arm
    grime = np.clip(grime * (0.6 + 0.8 * n2), 0, 1)
    sweat = np.clip(0.9 * oily + 0.6 * gxz(0.0, 1.482, 0.02, 0.005) + 0.5 * head * (y < 0.0) + 0.7 * ((z > 1.24) & (z <= 1.40))
                    + 0.45 * arm, 0, 1) * (1 - 0.7 * hand)
    thin = np.clip(ear + gxz(0.0, 1.500, 0.014, 0.010) + 0.6 * lip, 0, 1)
    mole = np.zeros(len(c))
    for p in ((0.047, -0.107, 1.483), (-0.022, -0.085, 1.413), (-0.062, -0.07, 1.468), (0.15, -0.03, 1.375),
              (-0.115, -0.075, 1.30), (0.028, -0.125, 1.557)):
        mole = np.maximum(mole, L.gauss(c, p, 0.0011))
    scar = seg((0.0345, 1.566), (0.0425, 1.5405), 0.0008)
    cut = seg((-0.052, 1.5075), (-0.039, 1.5030), 0.0007)
    for name, v in (("m_red", red), ("m_yellow", yellow), ("m_blue", blue), ("m_oily", oily), ("m_lip", lip),
                    ("m_brow", brow * (1 - scar)), ("m_scalp", scalp), ("m_freckle", freckle), ("m_grime", grime),
                    ("m_sweat", sweat), ("m_thin", thin), ("m_mole", mole), ("m_scar", scar), ("m_cut", cut)):
        L.set_float_attr(mesh, name, np.clip(v, 0, 1))


def paint(g):
    """The painted skin as sockets: colour, roughness, two bump heights, subsurface amount and sweat film."""
    a = {k: g.attr("m_" + k) for k in ("red", "yellow", "blue", "oily", "lip", "brow", "scalp", "freckle", "grime",
                                       "sweat", "thin", "mole", "scar", "cut")}
    blotch = g.noise(55, 3, 0.55)
    fine = g.noise(650, 2, 0.6)
    col = g.mixc((0.365, 0.196, 0.128), (0.42, 0.20, 0.14), g.ramp(blotch, 0.3, 0.7))
    col = g.mixc(col, (0.40, 0.25, 0.15), g.ramp(g.noise(30, 2), 0.35, 0.75, 0, 0.5))
    col = g.mixc(col, (0.44, 0.28, 0.15), g.mul(a["yellow"], 0.22))
    col = g.mixc(col, (0.46, 0.13, 0.10), g.mul(a["red"], g.ramp(blotch, 0.2, 0.8, 0.28, 0.5)))
    col = g.mixc(col, (0.20, 0.105, 0.11), g.mul(a["blue"], 0.42))
    # Freckles: voronoi cells, a random share of them a dot.
    fd = g.voronoi(620, "F1", 1.0, 0)
    fr = g.sep(g.voronoi(620, "F1", 1.0, 1))[0]
    dots = g.mul(g.ramp(fd, 0.16, 0.34, 1, 0), g.ramp(fr, 0.52, 0.60))
    dots = g.mul(dots, g.ramp(g.noise(90, 2), 0.35, 0.6))
    col = g.mixc(col, (0.20, 0.09, 0.05), g.mul(g.mul(dots, a["freckle"]), 0.6))
    col = g.mixc(col, (0.07, 0.035, 0.025), g.ramp(a["mole"], 0.3, 0.7, 0, 0.92))
    # Lips, with darker vertical lines.
    liplines = g.noise(1.0, 3, 0.6, stretch=(2600, 260, 160))
    lipcol = g.mixc((0.36, 0.105, 0.095), (0.25, 0.065, 0.065), g.ramp(liplines, 0.35, 0.7))
    col = g.mixc(col, lipcol, g.mul(a["lip"], 0.9))
    # Scars: an old pale one through the brow, a fresh scab on the cheek.
    col = g.mixc(col, (0.50, 0.30, 0.25), g.mul(a["scar"], 0.7))
    col = g.mixc(col, (0.20, 0.035, 0.03), g.ramp(a["cut"], 0.35, 0.8, 0, 0.92))
    col = g.mixc(col, (0.50, 0.13, 0.11), g.mul(g.ramp(a["cut"], 0.02, 0.4), 0.35))
    # Value breakup at pore scale.
    col = g.mixc(col, (0.20, 0.10, 0.07), g.ramp(fine, 0.5, 0.85, 0, 0.16))
    # Brow and scalp: the painted layer under the hair cards, drawn as strokes.
    strokes = g.noise(1.0, 2, 0.5, stretch=(900, 300, 3200))
    browhair = g.mul(a["brow"], g.ramp(strokes, 0.30, 0.62, 0.55, 1.0))
    col = g.mixc(col, (0.022, 0.015, 0.011), g.sat(g.mul(browhair, 1.1)))
    stubble = g.ramp(g.voronoi(2600, "F1", 1.0, 0), 0.25, 0.6, 1, 0)
    scalp = g.sat(g.add(g.mul(a["scalp"], 0.75), g.mul(g.mul(a["scalp"], stubble), 0.5)))
    col = g.mixc(col, (0.020, 0.015, 0.012), scalp)
    # Grime: dirt that sits in patches and thins to a film at the edges.
    dirt_n = g.noise(38, 5, 0.6)
    dirt = g.mul(a["grime"], g.ramp(dirt_n, 0.35, 0.75))
    dirt = g.sat(g.add(dirt, g.mul(a["grime"], 0.18)))
    streak = g.ramp(g.noise(1.0, 3, 0.6, stretch=(420, 420, 40)), 0.45, 0.75)
    dirt = g.sat(g.mul(dirt, g.mixf(1.0, 0.45, streak)))
    col = g.mixc(col, (0.085, 0.058, 0.040), g.mul(dirt, 0.6))

    # Roughness: oil and sweat lower it, lips are wet, dirt and hair raise it.
    creases = g.voronoi(1500, "DISTANCE_TO_EDGE", 1.0, 0)
    rough = g.mixf(0.50, 0.34, a["oily"])
    rough = g.add(rough, g.ramp(creases, 0.0, 0.12, 0.07, 0.0))
    beads = g.ramp(g.noise(1100, 3, 0.6), 0.62, 0.72)
    film = g.sat(g.add(g.mul(a["sweat"], g.ramp(g.noise(45, 4, 0.6), 0.25, 0.75, 0.2, 0.6)), g.mul(g.mul(beads, a["sweat"]), 0.35)))
    rough = g.mixf(rough, 0.22, g.mul(film, 0.55))
    rough = g.mixf(rough, 0.24, a["lip"])
    rough = g.mixf(rough, 0.78, g.mul(dirt, 0.8))
    rough = g.mixf(rough, 0.55, scalp)
    sweat = g.mul(film, g.sub(1.0, g.mul(dirt, 0.8)))

    # Bump: pores and the crease net, then the larger lines.
    pores = g.ramp(g.voronoi(1900, "F1", 1.0, 0), 0.0, 0.42)
    skin_h = g.add(g.mul(g.ramp(creases, 0.0, 0.10), 0.6), g.mul(pores, 0.4))
    skin_h = g.mixf(skin_h, 0.5, g.sat(g.add(a["lip"], scalp)))
    lines_h = g.mul(a["lip"], g.ramp(liplines, 0.3, 0.7, 1, 0))
    lines_h = g.add(lines_h, g.mul(g.ramp(a["scar"], 0.2, 0.8), -0.7))
    lines_h = g.add(lines_h, g.mul(g.ramp(a["cut"], 0.3, 0.8), 0.9))
    lines_h = g.add(lines_h, g.mul(g.ramp(a["mole"], 0.3, 0.7), 0.8))
    lines_h = g.add(lines_h, g.mul(browhair, g.ramp(strokes, 0.3, 0.6, 0.0, 0.5)))
    lines_h = g.add(lines_h, g.mul(dirt, g.ramp(dirt_n, 0.4, 0.8, 0.0, 0.25)))
    sss = g.mixf(g.mixf(0.75, 1.0, a["thin"]), 0.25, g.sat(g.add(scalp, g.mul(dirt, 0.7))))
    return {"albedo": col, "rough": rough, "h_fine": skin_h, "h_lines": lines_h, "sss": sss, "sweat": sweat}


def new_image(name, colour):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    return img


def pixels(img):
    a = np.empty(SIZE * SIZE * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(SIZE, SIZE, 4)


def save_png(name, rgb, colour):
    img = new_image("out_" + name, colour)
    px = np.ones((SIZE, SIZE, 4), dtype=np.float32)
    px[..., :3] = rgb
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = f"{TEX}/{name}.png"
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def combine_normals(base, detail):
    """Reoriented normal mapping: `detail` laid over `base`, both tangent space in 0..1."""
    t = base[..., :3] * np.array([2, 2, 2], dtype=np.float32) + np.array([-1, -1, 0], dtype=np.float32)
    u = detail[..., :3] * np.array([-2, -2, 2], dtype=np.float32) + np.array([1, 1, -1], dtype=np.float32)
    r = t * (t * u).sum(-1, keepdims=True) / np.maximum(t[..., 2:3], 1e-4) - u
    r /= np.linalg.norm(r, axis=-1, keepdims=True) + 1e-8
    return r * 0.5 + 0.5


def main():
    L.open_stage(A.work, "s01")
    os.makedirs(TEX, exist_ok=True)
    sc = bpy.context.scene
    L.cycles_gpu(sc, 8)
    high, cage, mid = (bpy.data.objects[n] for n in ("high", "body_mr", "mid"))
    paint_masks(high)

    mats, targets, emit, sockets, bsdf, outs = {}, {}, {}, {}, {}, {}
    for i, s in enumerate(SETS):
        m, g = new_material("bake_" + s)
        p = paint(g)
        e = g.node("ShaderNodeEmission")
        b = g.node("ShaderNodeBsdfPrincipled")
        b1 = g.node("ShaderNodeBump")
        b1.inputs["Distance"].default_value = 0.00009
        g.link(p["h_fine"], b1.inputs["Height"])
        b2 = g.node("ShaderNodeBump")
        b2.inputs["Distance"].default_value = 0.00030
        g.link(p["h_lines"], b2.inputs["Height"])
        g.link(b1.outputs[0], b2.inputs["Normal"])
        g.link(b2.outputs[0], b.inputs["Normal"])
        out = g.node("ShaderNodeOutputMaterial")
        t = g.node("ShaderNodeTexImage")
        g.t.nodes.active = t
        mats[s], targets[s], emit[s], sockets[s], bsdf[s], outs[s] = m, t, e, p, b, out
        for o in (high, cage):
            o.material_slots[i].material = m
    done = {}

    def bake(obj, kind, name, colour=False, socket=None, multires=False):
        for s in SETS:
            img = new_image(f"{s}_{name}", colour)
            targets[s].image = img
            done[(s, name)] = img
            t = mats[s].node_tree
            if socket:
                t.links.new(sockets[s][socket], emit[s].inputs[0])
                t.links.new(emit[s].outputs[0], outs[s].inputs[0])
            else:
                t.links.new(bsdf[s].outputs[0], outs[s].inputs[0])
        L.select_only(obj)
        sc.render.bake.use_multires = multires
        sc.render.bake.margin = 16
        if multires:
            sc.render.bake.type = "NORMALS"
            obj.modifiers[0].levels = 1
            obj.modifiers[0].render_levels = 3
            bpy.ops.object.bake_image()
        else:
            if kind == "NORMAL":
                sc.cycles.samples = 16
            else:
                sc.cycles.samples = 48 if kind == "AO" else 8
            bpy.ops.object.bake(type=kind, margin=16, use_clear=True, normal_space="TANGENT")
        print("BAKED", name)

    bake(cage, "NORMALS", "n_geo", multires=True)
    bake(high, "NORMAL", "n_detail")
    bake(high, "AO", "ao")
    for name, colour in (("albedo", True), ("rough", False), ("sss", False), ("sweat", False)):
        bake(high, "EMIT", name, colour=colour, socket=name)

    for s in SETS:
        px = {n: pixels(done[(s, n)]) for n in ("n_geo", "n_detail", "ao", "albedo", "rough", "sss", "sweat")}
        save_png(f"{s}_albedo", px["albedo"][..., :3], True)
        save_png(f"{s}_normal", combine_normals(px["n_geo"], px["n_detail"]), False)
        orm = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
        orm[..., 0] = px["ao"][..., 0]
        orm[..., 1] = px["rough"][..., 0]
        save_png(f"{s}_orm", orm, False)
        mask = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
        mask[..., 0] = px["sss"][..., 0]
        mask[..., 1] = px["sweat"][..., 0]
        save_png(f"{s}_mask", mask, False)
        print("TEXSET", s, SIZE)
    for img in done.values():
        bpy.data.images.remove(img)

    # The bake sources are done: keep only what later stages read.
    for o in (high, cage):
        bpy.data.objects.remove(o)
    for i, s in enumerate(SETS):
        mid.material_slots[i].material = M.skin(f"skin_{s}", TEX, s)
    mid.name = mid.data.name = "skin"
    L.save_stage(A.work, "s02")


main()
