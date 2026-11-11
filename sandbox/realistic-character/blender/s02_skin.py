"""Stage 2: the skin's texture sets. Paints the skin by rule (zones on the vertices of the level-3 surface, lines and
fine detail as 3D procedural textures) and bakes it to the head and body sets:

- `<set>_albedo.png` (sRGB), `<set>_normal.png` (tangent space, +Y, 16 bits a channel), `<set>_orm.png` (R ambient
  occlusion, G roughness, B unused) and `<set>_mask.png` (R subsurface amount, G the oil film, B peach fuzz);
- `skin_detail_normal.png`, a tiling map of pores and the crease net for the engine to lay over them up close.

The normal map is ONE Cycles bake from the painted level-3 surface onto the game mesh itself (selected to active):
the map then corrects for exactly the triangles, vertex normals and MikkTSpace tangents the export hands to
Godot. The first build baked with Blender's Multires baker and drew a ridge along every edge loop of the game
mesh (kit docs: tools/blender/realistic-characters.md#limb-lines).
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
S = L.SCALE


def paint_masks(obj):
    """Zones as float attributes on the vertices: where the skin is red, oily, lips, brow, scalp, dirty, lined."""
    mesh = obj.data
    full = L.co_get(mesh)
    c = full / L.SCALE  # the landmarks below are in the base mesh's metres
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

    def seg(p0, p1, sigma, mirror=False):
        """Distance falloff from a segment drawn on the face in the front view (x, z)."""
        p = np.stack([ax if mirror else x, z], 1)
        a, b = np.array(p0), np.array(p1)
        t = np.clip(((p - a) @ (b - a)) / ((b - a) @ (b - a)), 0, 1)
        d = np.linalg.norm(p - (a + t[:, None] * (b - a)), axis=1)
        return np.exp(-((d / sigma) ** 2) / 2) * front

    n1 = L.fbm3(c * 60, 3, 1)
    n2 = L.fbm3(c * 25, 3, 5)
    ear = g3((0.086, 0.012, 1.515), 0.022)

    # The hands and wrists, each in its own frame (found on this surface: the arms are in the A pose).
    arm_v, hand_v = L.vertex_parts(mesh)
    hand = np.zeros(len(c))
    knuckle = np.zeros(len(c))
    vein = np.zeros(len(c))
    for sx in (1, -1):
        f = L.hand_frame(full, arm_v, hand_v, sx)
        rel = full - f["wrist"]
        t, s, h = rel @ f["a"], rel @ f["lat"], rel @ f["th"]
        near = (sx * full[:, 0] > 0.12) & (np.abs(s) < 0.12) & (t > -0.2)
        # The palm's side is the one the thumb's tip leans to.
        thumb = near & (s > 0.6 * s[near & (t > 0)].max()) & (t > 0)
        palm = np.sign(h[thumb].mean())
        back = L.smoothstep(-0.004, 0.006, -palm * h)
        on_hand = near * L.smoothstep(-0.01, 0.01, t)
        hand = np.maximum(hand, on_hand)
        ln = f["length"]
        knuckle = np.maximum(knuckle, near * back * np.exp(-(((t - 0.47 * ln) / (0.07 * ln)) ** 2) / 2))
        inner = near * (1 - back) * np.exp(-(((t + 0.03) / 0.035) ** 2) / 2)
        outer = near * back * L.smoothstep(0.0, 0.03, t) * L.smoothstep(0.50 * ln, 0.36 * ln, t)
        vein = np.maximum(vein, np.maximum(0.9 * inner, 0.8 * outer))
    arm = (ax > 0.14) & (z < 1.30) & (hand < 0.5)
    elbow = np.zeros(len(c))
    if arm.any():
        # The elbow's point: the back of the arm about 59 % of the way from the shoulder to the wrist.
        for sx in (1, -1):
            sh, wr = np.array([sx * 0.158, 0.012, 1.352]), L.hand_frame(full, arm_v, hand_v, sx)["wrist"] / L.SCALE
            e = sh + (wr - sh) * L.ELBOW_SHARE + np.array([0, 0.03, 0])
            elbow = np.maximum(elbow, L.gauss(c, e, 0.028))

    red = 0.95 * gxz(0.046, 1.494, 0.019, 0.015) + 1.0 * gxz(0.0, 1.502, 0.012, 0.010)
    red += 0.7 * gxz(0.0165, 1.497, 0.007, 0.006) + 0.4 * gxz(0.0, 1.437, 0.014, 0.008) + 1.0 * ear
    red += 0.30 * knuckle + 0.12 * hand * n1 + 0.45 * elbow + 0.25 * g3((0.0, -0.07, 1.36), 0.06, False) * (z < 1.40)
    yellow = gxz(0.0, 1.588, 0.045, 0.020)
    blue = 0.9 * gxz(0.033, 1.5215, 0.013, 0.005) + 0.55 * gxz(0.033, 1.5435, 0.012, 0.004)
    blue += 0.3 * gxz(0.066, 1.545, 0.010, 0.012)
    oily = np.clip(gxz(0.0, 1.585, 0.035, 0.016) + gxz(0.0, 1.51, 0.011, 0.020) + 0.5 * gxz(0.0, 1.44, 0.012, 0.008)
                   + 0.35 * gxz(0.050, 1.515, 0.012, 0.007), 0, 1)
    # Where pores are large and open: the nose, the inner cheeks, the chin, the middle of the forehead.
    pore = np.clip(gxz(0.0, 1.505, 0.016, 0.016) + 0.9 * gxz(0.034, 1.497, 0.015, 0.013) + 0.6 * gxz(0.0, 1.44, 0.014, 0.01)
                   + 0.55 * gxz(0.0, 1.575, 0.03, 0.014), 0, 1)

    # Lips: between an upper and a lower border drawn around the mouth line.
    zm, half = 1.4662, 0.0270
    xn = np.clip(ax / half, 0, 1)
    upper = zm + 0.0098 * (1 - xn**2) ** 0.75 - 0.0013 * np.exp(-((x / 0.004) ** 2))
    lower = zm - 0.0092 * (1 - xn**2.2) ** 0.6
    lip = L.smoothstep(-0.0006, 0.0008, upper - z) * L.smoothstep(-0.0006, 0.0008, z - lower)
    lip *= (ax < half) * (y < -0.085) * head
    lipline = lip * np.exp(-(((z - zm) / 0.0016) ** 2) / 2)

    brow = L.brow_field(c)[0]
    scalp = L.scalp_mask(c, soft=0.007)

    # Where fine lines sit. The lines themselves are drawn by the shader; these say where and how strongly.
    forehead = gxz(0.0, 1.583, 0.042, 0.013) * (1 - scalp)
    undereye = gxz(0.034, 1.5195, 0.013, 0.0042)
    crow = gxz(0.0545, 1.5335, 0.0065, 0.0075)
    fold = seg((0.0205, 1.493), (0.0315, 1.4655), 0.0022, mirror=True)      # nose wing to mouth corner
    fold = np.maximum(fold, 0.6 * seg((0.0285, 1.4625), (0.0305, 1.4500), 0.0018, mirror=True))
    neck = ((z > 1.33) & (z < 1.415) & (y < 0.02)) * 1.0
    neckline = np.maximum(np.exp(-(((z - 1.385 - 0.02 * ax) / 0.0016) ** 2) / 2),
                          0.7 * np.exp(-(((z - 1.358 - 0.03 * ax) / 0.0016) ** 2) / 2)) * neck * (ax < 0.05)
    philtrum = np.exp(-((x / 0.0035) ** 2 + ((z - 1.4835) / 0.006) ** 2) / 2) * front

    freckle = np.clip(gxz(0.0, 1.512, 0.055, 0.017) + 0.22 * ((z > 1.24) & (z < 1.44)) + 0.10 * arm, 0, 1)
    grime = 0.45 * g3((0.058, -0.085, 1.482), 0.018, False) + 0.4 * g3((-0.035, -0.10, 1.588), 0.020, False)
    grime += 0.5 * g3((-0.06, -0.02, 1.40), 0.035, False) + 0.4 * g3((0.10, -0.06, 1.33), 0.05, False)
    grime += 0.45 * hand + 0.35 * arm * L.smoothstep(1.25, 0.95, z) + 0.10 * arm
    grime = np.clip(grime * (0.6 + 0.8 * n2), 0, 1)
    # Peach fuzz: the sides of the face, the jaw, the upper lip, the forearms. Not the lips, lids or nose tip.
    fuzz = np.clip(0.9 * gxz(0.062, 1.485, 0.022, 0.03) + 0.6 * gxz(0.0, 1.482, 0.02, 0.006) + 0.5 * gxz(0.045, 1.44, 0.03, 0.012)
                   + 0.5 * arm * (z < 1.20) + 0.3 * neck, 0, 1) * (1 - lip) * (1 - scalp)
    thin = np.clip(ear + gxz(0.0, 1.500, 0.014, 0.010) + 0.6 * lip, 0, 1)
    mole = np.zeros(len(c))
    for p in ((0.047, -0.107, 1.483), (-0.022, -0.085, 1.413), (-0.062, -0.07, 1.468), (0.15, -0.03, 1.375),
              (-0.115, -0.075, 1.30), (0.028, -0.125, 1.557)):
        mole = np.maximum(mole, L.gauss(c, p, 0.0011))
    scar = seg((0.0345, 1.566), (0.0425, 1.5405), 0.0008)
    cut = seg((-0.052, 1.5075), (-0.039, 1.5030), 0.0007)
    for name, v in (("m_red", red), ("m_yellow", yellow), ("m_blue", blue), ("m_oily", oily), ("m_lip", lip),
                    ("m_brow", brow * (1 - scar)), ("m_scalp", scalp), ("m_freckle", freckle), ("m_grime", grime),
                    ("m_thin", thin), ("m_mole", mole), ("m_scar", scar), ("m_cut", cut), ("m_pore", pore),
                    ("m_forehead", forehead), ("m_undereye", undereye), ("m_crow", crow), ("m_fold", fold),
                    ("m_neckline", neckline), ("m_philtrum", philtrum), ("m_lipline", lipline), ("m_vein", vein),
                    ("m_knuckle", knuckle), ("m_hand", hand), ("m_fuzz", fuzz), ("m_elbow", elbow)):
        L.set_float_attr(mesh, name, np.clip(v, 0, 1))


def paint(g):
    """The painted skin as sockets: colour, roughness, two bump heights, subsurface amount, oil film and fuzz."""
    names = ("red", "yellow", "blue", "oily", "lip", "brow", "scalp", "freckle", "grime", "thin", "mole", "scar",
             "cut", "pore", "forehead", "undereye", "crow", "fold", "neckline", "philtrum", "lipline", "vein",
             "knuckle", "hand", "fuzz", "elbow")
    a = {k: g.attr("m_" + k) for k in names}
    xs, ys, zs = g.xyz()
    ax = g.math("ABSOLUTE", xs)

    def lines(stretch, lo=0.90, hi=0.985, detail=2.0):
        """Thin wavy lines: the mid-level contours of a noise stretched across them."""
        return g.ramp(g.ridge(g.noise(1.0, detail, 0.5, stretch=stretch)), lo, hi)

    # Colour: a base that drifts warm and cool, then the zones.
    blotch = g.noise(55, 3, 0.55)
    mottle = g.noise(210, 3, 0.6)
    fine = g.noise(650, 2, 0.6)
    col = g.mixc((0.365, 0.196, 0.128), (0.42, 0.20, 0.14), g.ramp(blotch, 0.3, 0.7))
    col = g.mixc(col, (0.40, 0.25, 0.15), g.ramp(g.noise(30, 2), 0.35, 0.75, 0, 0.5))
    col = g.mixc(col, (0.44, 0.17, 0.13), g.ramp(mottle, 0.52, 0.80, 0, 0.22))     # small red mottling
    col = g.mixc(col, (0.38, 0.25, 0.15), g.ramp(mottle, 0.48, 0.20, 0, 0.16))     # and its sallow counterpart
    col = g.mixc(col, (0.44, 0.28, 0.15), g.mul(a["yellow"], 0.22))
    col = g.mixc(col, (0.47, 0.115, 0.095), g.mul(a["red"], g.ramp(blotch, 0.2, 0.8, 0.36, 0.62)))
    # Broken capillaries on the cheeks and the nose's wings: a fine red net inside the red zone.
    cap = g.ramp(g.voronoi(900, "DISTANCE_TO_EDGE", 1.0, 0), 0.0, 0.05, 1, 0)
    face_red = g.mul(a["red"], g.sub(1.0, g.sat(g.add(a["hand"], a["elbow"]))))
    col = g.mixc(col, (0.42, 0.07, 0.07), g.mul(g.mul(cap, face_red), g.ramp(g.noise(120, 2), 0.45, 0.7, 0, 0.30)))
    col = g.mixc(col, (0.20, 0.105, 0.11), g.mul(a["blue"], 0.42))
    # Veins under thin skin at the wrist and the back of the hand: a soft blue-green net.
    warp = g.node("ShaderNodeVectorMath", operation="ADD")
    g.link(g.coord(), warp.inputs[0])
    g.link(g.mul(g.noise(40, 2, 0.5, colour=True), 0.02), warp.inputs[1])
    vd = g.voronoi(62, "DISTANCE_TO_EDGE", 1.0, 0, vec=warp.outputs[0])
    vein = g.mul(g.ramp(vd, 0.0, 0.085, 1, 0), g.ramp(g.noise(24, 2), 0.42, 0.62))
    vein = g.mul(vein, a["vein"])
    col = g.mixc(col, (0.24, 0.25, 0.25), g.mul(vein, 0.30))
    # Freckles: voronoi cells, a random share of them a dot.
    fd = g.voronoi(620, "F1", 1.0, 0)
    fr = g.sep(g.voronoi(620, "F1", 1.0, 1))[0]
    dots = g.mul(g.ramp(fd, 0.16, 0.34, 1, 0), g.ramp(fr, 0.52, 0.60))
    dots = g.mul(dots, g.ramp(g.noise(90, 2), 0.35, 0.6))
    col = g.mixc(col, (0.20, 0.09, 0.05), g.mul(g.mul(dots, a["freckle"]), 0.6))
    col = g.mixc(col, (0.07, 0.035, 0.025), g.ramp(a["mole"], 0.3, 0.7, 0, 0.92))
    # Lips: vertical lines, a darker line where they meet, a paler dry centre on the lower lip.
    liplines = g.noise(1.0, 3, 0.6, stretch=(2600, 260, 160))
    lipfine = g.noise(1.0, 2, 0.6, stretch=(5200, 500, 300))
    lipcol = g.mixc((0.37, 0.115, 0.10), (0.25, 0.065, 0.065), g.ramp(liplines, 0.35, 0.7))
    lipcol = g.mixc(lipcol, (0.42, 0.17, 0.14), g.ramp(g.noise(160, 2), 0.5, 0.8, 0, 0.35))
    lipcol = g.mixc(lipcol, (0.17, 0.045, 0.05), g.mul(a["lipline"], 0.75))
    col = g.mixc(col, lipcol, g.mul(a["lip"], 0.9))
    # Scars: an old pale one through the brow, a fresh scab on the cheek.
    col = g.mixc(col, (0.50, 0.30, 0.25), g.mul(a["scar"], 0.7))
    col = g.mixc(col, (0.20, 0.035, 0.03), g.ramp(a["cut"], 0.35, 0.8, 0, 0.92))
    col = g.mixc(col, (0.50, 0.13, 0.11), g.mul(g.ramp(a["cut"], 0.02, 0.4), 0.35))
    # Value breakup at pore scale.
    col = g.mixc(col, (0.20, 0.10, 0.07), g.ramp(fine, 0.5, 0.85, 0, 0.16))

    # Lines. Each is a zone on the vertices times a pattern with the line's direction.
    #   forehead: level; under the eye: level and finer; crow's feet: rays from the eye's outer corner.
    l_forehead = g.mul(lines((14 / S, 14 / S, 330 / S)), a["forehead"])
    l_under = g.mul(lines((90 / S, 90 / S, 900 / S), 0.86, 0.98), a["undereye"])
    ang = g.math("ARCTAN2", g.sub(zs, 1.5335 * S), g.sub(ax, 0.0475 * S))
    rays = g.node("ShaderNodeCombineXYZ")
    g.link(g.mul(ang, 5.2), rays.inputs[0])
    g.link(g.mul(g.dist((0, 0, 0)), 3.0), rays.inputs[1])
    l_crow = g.mul(g.ramp(g.ridge(g.noise(1.0, 2, 0.5, vec=rays.outputs[0])), 0.86, 0.98), a["crow"])
    # The skin's own net of creases, coarser and deeper on the knuckles, the elbows and the backs of the hands.
    creases = g.voronoi(1500, "DISTANCE_TO_EDGE", 1.0, 0)
    coarse = g.voronoi(620, "DISTANCE_TO_EDGE", 1.0, 0)
    l_joint = g.mul(lines((2400, 2400, 2400), 0.80, 0.97), g.sat(g.add(a["knuckle"], g.mul(a["elbow"], 0.8))))
    soft = g.sat(g.add(g.add(a["fold"], a["neckline"]), g.mul(a["philtrum"], 0.5)))
    grooves = g.sat(g.add(g.add(g.mul(l_forehead, 0.55), g.mul(l_under, 0.7)), g.add(g.mul(l_crow, 0.8), g.mul(l_joint, 0.9))))
    col = g.mixc(col, (0.20, 0.085, 0.07), g.sat(g.add(g.mul(grooves, 0.22), g.mul(soft, 0.13))))

    # Brow and scalp: the painted layer under the hair cards, in the hair's own colour and fading in strokes.
    strokes = g.noise(1.0, 2, 0.5, stretch=(900, 300, 3200))
    browhair = g.mul(a["brow"], g.ramp(strokes, 0.30, 0.62, 0.55, 1.0))
    col = g.mixc(col, (0.022, 0.015, 0.011), g.sat(g.mul(browhair, 1.1)))
    hairs = g.noise(1.0, 2, 0.6, stretch=(1700, 420, 420))
    scalp = g.ramp(g.add(a["scalp"], g.mul(g.sub(hairs, 0.5), 0.55)), 0.30, 0.72)
    root = tuple(float(v) for v in L.HAIR_RGB * 0.55)
    lit = tuple(float(v) for v in L.HAIR_RGB * 1.05)
    col = g.mixc(col, g.mixc(root, lit, g.ramp(hairs, 0.35, 0.75)), scalp)
    # Grime: dirt that sits in patches and thins to a film at the edges.
    dirt_n = g.noise(38, 5, 0.6)
    dirt = g.mul(a["grime"], g.ramp(dirt_n, 0.35, 0.75))
    dirt = g.sat(g.add(dirt, g.mul(a["grime"], 0.18)))
    streak = g.ramp(g.noise(1.0, 3, 0.6, stretch=(420, 420, 40)), 0.45, 0.75)
    dirt = g.sat(g.mul(dirt, g.mixf(1.0, 0.45, streak)))
    col = g.mixc(col, (0.085, 0.058, 0.040), g.mul(dirt, 0.5))

    # Roughness. Dry skin is matt (0.62 to 0.74, never even); the oil of the forehead, nose and chin brings it to
    # 0.46 at most; lips are the smoothest thing on the face at 0.40; dirt and hair are rougher than skin.
    rough = g.ramp(blotch, 0.25, 0.75, 0.62, 0.70)
    rough = g.add(rough, g.ramp(mottle, 0.3, 0.7, -0.03, 0.03))
    rough = g.add(rough, g.ramp(fine, 0.35, 0.8, -0.035, 0.035))
    rough = g.mixf(rough, 0.46, g.mul(a["oily"], g.ramp(g.noise(140, 3, 0.6), 0.25, 0.75, 0.55, 1.0)))
    rough = g.add(rough, g.ramp(creases, 0.0, 0.12, 0.08, 0.0))
    rough = g.add(rough, g.mul(g.sat(g.add(a["knuckle"], a["elbow"])), 0.08))
    rough = g.mixf(rough, g.ramp(lipfine, 0.3, 0.7, 0.36, 0.50), a["lip"])
    rough = g.mixf(rough, 0.82, g.mul(dirt, 0.8))
    rough = g.mixf(rough, 0.60, scalp)
    # The oil film (Godot's clearcoat, Cycles' coat): only the forehead, the nose, the chin and the lips, faint.
    film = g.mul(a["oily"], g.ramp(g.noise(45, 4, 0.6), 0.25, 0.75, 0.25, 0.7))
    film = g.sat(g.add(film, g.mul(a["lip"], 0.55)))
    film = g.mul(film, g.sub(1.0, g.mul(dirt, 0.8)))

    # Bump. Pores: small everywhere, large and open on the nose and inner cheeks. Then the crease net, then lines.
    pores_s = g.ramp(g.voronoi(1900, "F1", 1.0, 0), 0.0, 0.42)
    pores_l = g.ramp(g.voronoi(1150, "F1", 0.9, 0), 0.0, 0.34)
    pores = g.mixf(pores_s, pores_l, a["pore"])
    net = g.mixf(g.ramp(creases, 0.0, 0.10), g.ramp(coarse, 0.0, 0.08), g.sat(g.add(a["hand"], a["elbow"])))
    skin_h = g.add(g.mul(net, 0.55), g.mul(pores, g.mixf(0.45, 0.95, a["pore"])))
    skin_h = g.mixf(skin_h, 0.5, g.sat(g.add(a["lip"], scalp)))
    lines_h = g.mul(a["lip"], g.add(g.ramp(liplines, 0.3, 0.7, 1.3, 0), g.ramp(lipfine, 0.35, 0.7, 0.5, 0)))
    lines_h = g.sub(lines_h, g.mul(a["lipline"], 1.2))
    lines_h = g.sub(lines_h, g.mul(grooves, 1.5))
    lines_h = g.sub(lines_h, g.mul(soft, 1.1))
    lines_h = g.add(lines_h, g.mul(vein, g.mul(a["hand"], 0.5)))
    lines_h = g.add(lines_h, g.mul(g.ramp(a["scar"], 0.2, 0.8), -0.7))
    lines_h = g.add(lines_h, g.mul(g.ramp(a["cut"], 0.3, 0.8), 0.9))
    lines_h = g.add(lines_h, g.mul(g.ramp(a["mole"], 0.3, 0.7), 0.8))
    lines_h = g.add(lines_h, g.mul(browhair, g.ramp(strokes, 0.3, 0.6, 0.0, 0.5)))
    lines_h = g.add(lines_h, g.mul(scalp, g.ramp(hairs, 0.3, 0.7, 0.0, 0.5)))
    lines_h = g.add(lines_h, g.mul(dirt, g.ramp(dirt_n, 0.4, 0.8, 0.0, 0.25)))
    sss = g.mixf(g.mixf(0.75, 1.0, a["thin"]), 0.25, g.sat(g.add(scalp, g.mul(dirt, 0.7))))
    fuzz = g.mul(a["fuzz"], g.sub(1.0, g.mul(dirt, 0.6)))
    return {"albedo": col, "rough": rough, "h_fine": skin_h, "h_lines": lines_h, "sss": sss, "film": film, "fuzz": fuzz}


def new_image(name, colour, deep=False):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=False, float_buffer=deep)
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


def detail_normal(size=512, cells=38):
    """A tiling micro-normal: pores (dots in a jittered grid) in a net of creases, from a Voronoi that wraps."""
    rng = np.random.default_rng(5)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells)), -1).reshape(-1, 2) + rng.uniform(0.1, 0.9, (cells * cells, 2))) / cells
    v, u = np.mgrid[0:size, 0:size] / size
    d1 = np.full((size, size), 9.0)
    d2 = np.full((size, size), 9.0)
    grid = pts.reshape(cells, cells, 2)
    cu, cv = np.floor(u * cells).astype(int), np.floor(v * cells).astype(int)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            p = grid[(cv + dy) % cells, (cu + dx) % cells]
            du = (p[..., 0] - u + 0.5) % 1.0 - 0.5
            dv = (p[..., 1] - v + 0.5) % 1.0 - 0.5
            d = np.hypot(du, dv) * cells
            d2 = np.where(d < d1, d1, np.minimum(d2, d))
            d1 = np.minimum(d1, d)
    height = 0.55 * L.smoothstep(0.0, 0.22, d2 - d1) - 0.45 * (1 - L.smoothstep(0.0, 0.26, d1))
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * size / 2
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * size / 2
    k = 0.006
    n = np.stack([-gx * k, -gy * k, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    img = bpy.data.images.new("out_detail", size, size, alpha=False)
    img.colorspace_settings.name = "Non-Color"
    px = np.ones((size, size, 4), dtype=np.float32)
    px[..., :3] = n * 0.5 + 0.5
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = f"{TEX}/skin_detail_normal.png"
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def main():
    L.open_stage(A.work, "s01")
    os.makedirs(TEX, exist_ok=True)
    sc = bpy.context.scene
    L.cycles_gpu(sc, 8)
    high, cage, mid = (bpy.data.objects[n] for n in ("high", "body_mr", "mid"))
    paint_masks(high)

    mats, targets, emit, sockets, bsdf, outs = {}, {}, {}, {}, {}, {}
    mid_targets = {}
    for i, s in enumerate(SETS):
        m, g = new_material("bake_" + s)
        p = paint(g)
        e = g.node("ShaderNodeEmission")
        b = g.node("ShaderNodeBsdfPrincipled")
        b1 = g.node("ShaderNodeBump")
        b1.inputs["Distance"].default_value = 0.00013
        g.link(p["h_fine"], b1.inputs["Height"])
        b2 = g.node("ShaderNodeBump")
        b2.inputs["Distance"].default_value = 0.00032
        g.link(p["h_lines"], b2.inputs["Height"])
        g.link(b1.outputs[0], b2.inputs["Normal"])
        g.link(b2.outputs[0], b.inputs["Normal"])
        out = g.node("ShaderNodeOutputMaterial")
        t = g.node("ShaderNodeTexImage")
        g.t.nodes.active = t
        mats[s], targets[s], emit[s], sockets[s], bsdf[s], outs[s] = m, t, e, p, b, out
        high.material_slots[i].material = m
        # The game mesh's own bake target: the normal map is baked onto it, from the painted surface.
        tm, tg = new_material("target_" + s)
        tp = tg.node("ShaderNodeBsdfPrincipled")
        to = tg.node("ShaderNodeOutputMaterial")
        tg.link(tp.outputs[0], to.inputs[0])
        mid_targets[s] = tg.node("ShaderNodeTexImage")
        tg.t.nodes.active = mid_targets[s]
        mid.material_slots[i].material = tm
    # Nothing but the surface being baked may cast or occlude: the cage and the whole-body copy lie on it.
    for o in bpy.data.objects:
        o.hide_render = o not in (high, mid)
    done = {}

    def bake(kind, name, colour=False, socket=None):
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
        L.select_only(high)
        mid.hide_render = True
        sc.cycles.samples = 64 if kind == "AO" else 8
        bpy.ops.object.bake(type=kind, margin=16, use_clear=True)
        mid.hide_render = False
        print("BAKED", name)

    def bake_normal():
        """Painted level-3 surface to the game mesh, in the game mesh's tangent space, 32-bit float."""
        for s in SETS:
            img = new_image(f"{s}_normal", False, deep=True)
            mid_targets[s].image = img
            done[(s, "normal")] = img
            t = mats[s].node_tree
            t.links.new(bsdf[s].outputs[0], outs[s].inputs[0])
        for o in bpy.context.view_layer.objects:
            if o is not None:
                o.select_set(False)
        high.select_set(True)
        mid.select_set(True)
        bpy.context.view_layer.objects.active = mid
        sc.cycles.samples = 16
        bpy.ops.object.bake(type="NORMAL", margin=16, use_clear=True, normal_space="TANGENT", use_selected_to_active=True,
                            cage_extrusion=0.0035, max_ray_distance=0.007)
        print("BAKED normal")

    bake_normal()
    bake("AO", "ao")
    for name, colour in (("albedo", True), ("rough", False), ("sss", False), ("film", False), ("fuzz", False)):
        bake("EMIT", name, colour=colour, socket=name)

    for s in SETS:
        px = {n: pixels(done[(s, n)]) for n in ("normal", "ao", "albedo", "rough", "sss", "film", "fuzz")}
        save_png(f"{s}_albedo", px["albedo"][..., :3], True)
        nrm = px["normal"][..., :3]
        L.write_png16(f"{TEX}/{s}_normal.png", nrm)
        dev = np.abs(nrm[..., :2] - 0.5)
        print("NORMAL", s, "mean tilt", round(float(dev.mean()), 4), "99.9th", round(float(np.percentile(dev, 99.9)), 3))
        orm = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
        orm[..., 0] = px["ao"][..., 0]
        orm[..., 1] = px["rough"][..., 0]
        save_png(f"{s}_orm", orm, False)
        mask = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
        mask[..., 0] = px["sss"][..., 0]
        mask[..., 1] = px["film"][..., 0]
        mask[..., 2] = px["fuzz"][..., 0]
        save_png(f"{s}_mask", mask, False)
        used = px["albedo"][..., :3].sum(-1) > 0.02
        r = px["rough"][..., 0][used]
        print("TEXSET", s, SIZE, "roughness 5/50/95 %", [round(float(v), 2) for v in np.percentile(r, (5, 50, 95))],
              "occlusion median", round(float(np.median(px["ao"][..., 0][used])), 2))
    detail_normal()
    for img in done.values():
        bpy.data.images.remove(img)

    # The bake sources are done: keep only what later stages read.
    for o in (high, cage):
        bpy.data.objects.remove(o)
    for o in bpy.data.objects:
        o.hide_render = o.name == "body_full"
    for i, s in enumerate(SETS):
        mid.material_slots[i].material = M.skin(f"skin_{s}", TEX, s)
    mid.name = mid.data.name = "skin"
    L.save_stage(A.work, "s02")


main()
