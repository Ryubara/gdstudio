"""Stage 5: clothes and gear, our own design: a washed tank top over a dark sports top, canvas trousers with thigh
pockets worn over lace-up boots, a leather belt, a drop-leg holster with a sidearm on the right thigh, a sling
strap with a hip pouch, a bandage wrap on the right forearm and a field watch on the left wrist.

Cloth is cut from the body's own faces (rc_cloth.shell); belts and straps are lofted around the outline a plane
cuts from the body (rc_cloth.plane_ring). Two meshes come out, `outfit` and `gear`, each with one UV set; their
faces keep a material per look until stage 6 has baked them.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector, geometry

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_cloth as C  # noqa: E402
import rc_lib as L  # noqa: E402

A = L.args()
S = L.SCALE
RIGID = [0]


def mat(o, name):
    m = bpy.data.materials.get("bk_" + name) or bpy.data.materials.new("bk_" + name)
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def hard(o, name):
    for p in o.data.polygons:
        p.use_smooth = True
    o.data.set_sharp_from_angle(angle=math.radians(38))
    # A hard piece follows one bone: stage 7 reads this to give all of it the same weights.
    RIGID[0] += 1
    L.set_float_attr(o.data, "rigid", np.full(len(o.data.vertices), RIGID[0]))
    return mat(o, name)


def top_field(c, grow=0.0):
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ax = np.abs(x)
    wf = L.smoothstep(0.03, -0.03, y)
    rx, rz, zc = 0.070 - grow, 0.052 + 0.058 * wf - grow, 1.415
    f_neck = (np.sqrt((x / rx) ** 2 + ((z - zc) / rz) ** 2) - 1) * 0.06
    # A deep armhole: its edge stays on the trunk. A shallower one (0.115 by 0.10) ran its lower edge through the
    # fold in front of the armpit, where it ended in a point.
    f_arm = (np.sqrt(((ax - 0.235) / (0.127 - grow)) ** 2 + ((z - 1.345) / (0.127 - grow)) ** 2) - 1) * 0.1
    return np.minimum(np.minimum(f_neck, f_arm), z - 0.93)


def gz(c, z0, s):
    return np.exp(-(((c[:, 2] - z0) / s) ** 2) / 2)


def clothes(full):
    def torso(cen, part):
        body = ((part == 2) & (cen[:, 2] < 1.47)) | ((part == 0) & (cen[:, 2] < 1.42))
        # The shoulder's cap belongs to the arm's tile: without its faces the armhole's edge followed the tile's
        # stair-stepped seam instead of the cut line (a ragged armhole).
        body |= (part == 3) & (cen[:, 2] > 1.27) & (np.abs(cen[:, 0]) < 0.25)
        return body & (cen[:, 2] > 0.90) & (np.abs(cen[:, 0]) < 0.25)

    top = C.shell("top", full, torso, top_field, lambda c: np.full(len(c), 0.0040), tension=30,
                  folds=lambda c: 0.0050 * C.ridges(c, (7, 7, 42), 3, 1.5) * L.smoothstep(1.16, 1.03, c[:, 2])
                  + 0.0030 * C.ridges(c, (30, 12, 22), 4, 2.0) * gz(c, 1.13, 0.05))
    mat(top, "top")
    bra = C.shell("bra", full, lambda cen, part: torso(cen, part) & (cen[:, 2] > 1.10),
                  lambda c: np.minimum(top_field(c, 0.008), c[:, 2] - 1.15), lambda c: np.full(len(c), 0.0012),
                  tension=4, rim=0.0015)
    mat(bra, "bra")

    def legs(cen, part):
        return ((part == 5) | ((part == 2) & (cen[:, 2] < 1.0))) & (cen[:, 2] > 0.06)

    def tr_folds(c):
        f = 0.011 * C.ridges(c, (7, 7, 40), 5, 1.6) * gz(c, 0.475, 0.07)
        f += 0.014 * C.ridges(c, (6, 6, 46), 7, 1.4) * L.smoothstep(0.30, 0.12, c[:, 2])
        f += 0.008 * C.ridges(c, (26, 10, 30), 9, 1.8) * gz(c, 0.83, 0.05)
        f += 0.006 * C.ridges(c, (10, 10, 22), 15, 2.0) * gz(c, 0.65, 0.09)
        return f + 0.003 * L.fbm3(c * 18, 2, 12)

    trousers = C.shell("trousers", full, legs, lambda c: np.minimum(0.975 - c[:, 2], c[:, 2] - 0.085),
                       lambda c: 0.009 + 0.012 * L.smoothstep(0.55, 0.15, c[:, 2])
                       + 0.012 * gz(c, 0.80, 0.045) * np.exp(-((c[:, 0] / 0.07) ** 2)), tension=18, folds=tr_folds)
    mat(trousers, "trousers")
    parts = [top, bra, trousers]
    for sx in (1, -1):
        def region(c, zlo=0.595, sx=sx):
            return np.minimum(np.minimum(0.735 - c[:, 2], c[:, 2] - zlo), np.minimum(0.058 - np.abs(c[:, 1] - 0.005), sx * c[:, 0] - 0.118))

        def near(cen, part, sx=sx):
            return (sx * cen[:, 0] > 0.09) & (cen[:, 2] > 0.55) & (cen[:, 2] < 0.78)

        pocket = C.shell(f"pocket{sx}", trousers, near, region, lambda c: np.full(len(c), 0.0045), tension=3, rim=0.004)
        flap = C.shell(f"flap{sx}", trousers, near, lambda c: region(c, 0.685), lambda c: np.full(len(c), 0.0075), tension=3, rim=0.003)
        parts += [mat(pocket, "trousers"), mat(flap, "trousers")]
    return top, trousers, parts


def boot(full, vp, sx):
    """A boot lofted over the foot: convex sections across the foot's axis, a rounded toe and heel, a lug sole."""
    co = L.co_get(full.data)
    side = sx * co[:, 0] > 0
    foot = co[side & (vp == 6)]
    leg = co[side & (vp == 5) & (co[:, 2] < 0.20)]
    pts = np.concatenate([foot, leg])
    toe, heel = foot[foot[:, 1].argmin()], foot[foot[:, 1].argmax()]
    axis = np.array([toe[0] - heel[0], toe[1] - heel[1], 0.0])
    length = np.linalg.norm(axis)
    axis /= length
    lat = np.array([-axis[1], axis[0], 0.0])
    s = (pts - heel) @ axis
    u = (pts - heel) @ lat
    clip = 0.165
    m, nsec = 20, 17
    rings = []
    for i in range(nsec):
        si = 0.006 + (length - 0.012) * i / (nsec - 1)
        sel = (np.abs(s - si) < length / nsec * 0.75) & (pts[:, 2] < clip)
        p2 = np.stack([u[sel], pts[sel, 2]], 1)
        hull = [p2[k] for k in geometry.convex_hull_2d([tuple(q) for q in p2])]
        cen = np.mean(hull, 0)
        ring = []
        for k in range(m):
            a = 2 * math.pi * k / m
            d = np.array([math.cos(a), math.sin(a)])
            best = 0.0
            for j in range(len(hull)):
                p, q = hull[j] - cen, hull[(j + 1) % len(hull)] - cen
                e = q - p
                den = d[0] * e[1] - d[1] * e[0]
                if abs(den) < 1e-12:
                    continue
                t = (p[0] * e[1] - p[1] * e[0]) / den
                w = (p[0] * d[1] - p[1] * d[0]) / den
                if t > 0 and -1e-6 <= w <= 1 + 1e-6:
                    best = max(best, t)
            q2 = cen + d * (best + 0.0065)
            zz = max(q2[1] * (1.0 + 0.25 * L.smoothstep(0.55, 0.9, np.array([si / length]))[0]), 0.010)
            ring.append(heel + axis * si + lat * q2[0] + np.array([0, 0, zz - heel[2]]))
        rings.append(ring)
    verts = [p for r in rings for p in r]
    faces = []
    for i in range(nsec - 1):
        for k in range(m):
            k2 = (k + 1) % m
            faces.append((i * m + k, i * m + k2, (i + 1) * m + k2, (i + 1) * m + k))
    for i, out in ((0, -0.010), (nsec - 1, 0.008)):
        c = np.mean(rings[i], 0) + axis * out
        c[2] = min(c[2], 0.05) if i else c[2]
        verts.append(c)
        for k in range(m):
            faces.append((i * m + k, i * m + (k + 1) % m, len(verts) - 1))
    upper = L.new_mesh_obj(f"boot{sx}", verts, faces)
    C.fix_normals(upper)
    L.select_only(upper)
    sub = upper.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    bpy.ops.object.modifier_apply(modifier="sub")
    for p in upper.data.polygons:
        p.use_smooth = True
    mat(upper, "boot")
    # Sole: the foot's outline on the ground, grown and extruded, with a heel step.
    g2 = np.stack([(foot - heel) @ axis, (foot - heel) @ lat], 1)
    hull = np.array([g2[k] for k in geometry.convex_hull_2d([tuple(q) for q in g2])])
    cen = hull.mean(0)
    sv, sf = [], []
    n = len(hull)
    for zc, grow in ((0.0, 0.006), (0.006, 0.009), (0.020, 0.009), (0.024, 0.006)):
        for h in hull:
            d = h - cen
            q = h + d / np.linalg.norm(d) * grow
            lift = 0.0 if zc > 0.01 or q[0] < length * 0.38 else 0.0
            sv.append(heel + axis * q[0] + lat * q[1] + np.array([0, 0, zc + lift]) - np.array([0, 0, heel[2]]))
    for r in range(3):
        for k in range(n):
            k2 = (k + 1) % n
            sf.append((r * n + k, r * n + k2, (r + 1) * n + k2, (r + 1) * n + k))
    sf.append(tuple(range(n))[::-1])
    sf.append(tuple(3 * n + k for k in range(n)))
    sole = L.new_mesh_obj(f"sole{sx}", sv, sf)
    C.fix_normals(sole)
    hard(sole, "sole")
    # Laces: crossed over the instep.
    laces = []
    top_l, top_r = m // 4 - 2, m // 4 + 2
    for i in range(7, 13):
        for a, b in ((top_l, top_r), (top_r, top_l)):
            p, q = Vector(rings[i][a]), Vector(rings[i + 1][b])
            mid = (p + q) / 2 + Vector((0, 0, 0.0035))
            d = q - p
            rot = Vector((1, 0, 0)).rotation_difference(d.normalized()).to_matrix()
            laces.append(hard(C.box(f"lace{sx}", mid, (d.length * 1.05, 0.0032, 0.0028), rot, bevel=0.0009, segments=1), "lace"))
    return [upper, sole] + laces


def frame_from(n, a):
    """A rotation whose columns are n (out of the body), n x a, and a."""
    n, a = Vector(n).normalized(), Vector(a).normalized()
    t = a.cross(n).normalized()
    n = t.cross(a).normalized()
    return Matrix((n, t, a)).transposed(), n, t, a


def gear(full, top, trousers):
    out = []
    # Belt and buckle.
    ring, axis = C.plane_ring([trousers, top], (0, 0, 0.957 * S), (0, 0, 1), 56, 0.0025)
    out.append(mat(C.strap("belt", ring, axis, 0.038, 0.0042), "belt"))
    p, n = min(ring, key=lambda r: r[0].y)
    rot, n, t, a = frame_from(n, (0, 0, 1))
    for off, size in (((0.007, 0, 0.022), (0.006, 0.056, 0.006)), ((0.007, 0, -0.022), (0.006, 0.056, 0.006)),
                      ((0.007, 0.026, 0), (0.006, 0.006, 0.05)), ((0.007, -0.026, 0), (0.006, 0.006, 0.05)),
                      ((0.009, 0.004, 0), (0.004, 0.05, 0.005))):
        out.append(hard(C.box("buckle", p + n * off[0] + t * off[1] + a * off[2], size, rot, bevel=0.0012), "metal"))
    belt_side = min(ring, key=lambda r: r[0].x)

    # Drop-leg holster on the right thigh: two thigh straps, a plate, the holster and the sidearm in it.
    hip, knee = Vector((-0.095, 0.0, 0.90)) * S, Vector((-0.105, -0.005, 0.49)) * S
    leg = (knee - hip).normalized()
    outer = []
    for k, zz in enumerate((0.725, 0.615)):
        pt = hip + leg * ((0.90 - zz) * S / -leg.z)
        r, ax = C.plane_ring([trousers], pt, leg, 40, 0.003, only=lambda q: q[:, 0] < -0.012)
        out.append(mat(C.strap(f"thigh_strap{k}", r, ax, 0.032, 0.003), "webbing"))
        outer.append(min(r, key=lambda e: e[0].x))
    o1, o2 = outer
    rot, n, t, a = frame_from((o1[1] + o2[1]) / 2, o1[0] - o2[0])
    mid = (o1[0] + o2[0]) / 2
    for name, off, size, look, tilt in (
            ("plate", (0.005, 0, 0), (0.008, 0.088, 0.185), "polymer", 0),
            ("holster", (0.026, 0.004, -0.012), (0.036, 0.060, 0.150), "polymer", 0),
            ("holster_lip", (0.026, 0.004, 0.058), (0.040, 0.064, 0.016), "polymer", 0),
            ("slide", (0.026, 0.002, 0.082), (0.026, 0.050, 0.034), "gunmetal", 0),
            ("grip", (0.026, 0.040, 0.118), (0.027, 0.036, 0.085), "grip", -0.30),
            ("sight", (0.026, -0.016, 0.101), (0.006, 0.008, 0.005), "gunmetal", 0)):
        r2 = rot @ Matrix.Rotation(tilt, 3, "X") if tilt else rot
        out.append(hard(C.box(name, mid + n * off[0] + t * off[1] + a * off[2], size, r2, bevel=0.0028), look))
    drop = [(belt_side[0], belt_side[1]), ((belt_side[0] + o1[0]) / 2 + n * 0.004, n), (o1[0] + a * 0.05 + n * 0.008, n)]
    out.append(mat(C.strap("drop_strap", drop, t, 0.034, 0.003, closed=False), "webbing"))

    # Sling across the chest, from the left shoulder to the right hip, with a pouch.
    pa, pb, pc = Vector((0.100, 0.0, 1.405)) * S, Vector((-0.15, -0.09, 0.99)) * S, Vector((-0.15, 0.08, 0.99)) * S
    ring, axis = C.plane_ring([top, trousers, full], pa, (pb - pa).cross(pc - pa), 64, 0.0035,
                              only=lambda q: (q[:, 2] > 0.95 * S) & (np.abs(q[:, 0]) < 0.20 * S))
    out.append(mat(C.strap("sling", ring, axis, 0.034, 0.003), "webbing"))
    p, n = min(ring, key=lambda r: r[0].x + 0.5 * r[0].z)
    rot, n, t, a = frame_from(n, (0, 0, 1))
    out.append(hard(C.box("pouch", p + n * 0.030 - a * 0.02, (0.050, 0.115, 0.145), rot, bevel=0.008, segments=3), "pouch"))
    out.append(hard(C.box("pouch_flap", p + n * 0.032 + a * 0.032, (0.056, 0.120, 0.058), rot, bevel=0.006, segments=2), "pouch"))
    out.append(hard(C.box("pouch_clip", p + n * 0.060 + a * 0.012, (0.006, 0.030, 0.020), rot, bevel=0.0015), "polymer"))
    p, n = min(ring, key=lambda r: r[0].y + abs(r[0].x - 0.02))
    rot, n, t, a = frame_from(n, axis.cross(n))
    out.append(hard(C.box("slider", p + n * 0.004, (0.004, 0.040, 0.018), rot, bevel=0.0012), "polymer"))

    # Bandage wrap on the right forearm, field watch on the left wrist.
    co = L.co_get(full.data)
    for sx, what in ((-1, "wrap"), (1, "watch")):
        arm = co[(sx * co[:, 0] > 0.14 * S) & (co[:, 2] < 1.30 * S) & (co[:, 2] > 0.93 * S)]
        o = arm.mean(0)
        w, v = np.linalg.eigh(np.cov((arm - o).T))
        ax = v[:, -1] * (-1 if v[2, -1] > 0 else 1)
        tt = (arm - o) @ ax
        t0, t1 = tt.min(), tt.max()
        if what == "wrap":
            def field(c, o=o, ax=ax, t0=t0, t1=t1):
                pr = (c * S - o) @ ax
                return np.minimum(pr - (t0 + 0.60 * (t1 - t0)), (t0 + 0.975 * (t1 - t0)) - pr)

            wrap = C.shell("wrap", full, lambda cen, part: (cen[:, 0] < -0.14) & (cen[:, 2] < 1.30) & (cen[:, 2] > 0.90),
                           field, lambda c: np.full(len(c), 0.0017), tension=2, rim=0.0013)
            out.append(mat(wrap, "wrap"))
        else:
            # Above the wrist as measured (the arm's tile ends 8 cm short of it: the first watch sat mid-forearm).
            hf = L.hand_frame(co, *L.vertex_parts(full.data), sx)
            pt, ax = Vector(hf["wrist"] - hf["a"] * 0.030), hf["a"]
            r, _ = C.plane_ring([full], pt, Vector(ax), 28, 0.0012,
                                only=lambda q, pt=pt: np.linalg.norm(q - np.array(pt), axis=1) < 0.06)
            out.append(mat(C.strap("watch_band", r, Vector(ax), 0.020, 0.0024), "webbing"))
            p, n = max(r, key=lambda e: e[0].x)
            out.append(hard(C.cylinder("watch_case", p + n * 0.006, 0.0185, 0.0105, n), "metal"))
            out.append(hard(C.cylinder("watch_glass", p + n * 0.0116, 0.0155, 0.0012, n, bevel=0.0), "glass"))
    return out


def unwrap(o):
    L.select_only(o)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.002, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")


def main():
    L.open_stage(A.work, "s04")
    full = bpy.data.objects["body_full"]
    part = np.empty(len(full.data.polygons), dtype=np.int32)
    full.data.attributes["part"].data.foreach_get("value", part)
    vp = np.zeros(len(full.data.vertices), dtype=np.int32)
    for p in full.data.polygons:
        for v in p.vertices:
            vp[v] = part[p.index]
    top, trousers, parts = clothes(full)
    g = gear(full, top, trousers)
    for sx in (1, -1):
        parts += boot(full, vp, sx)
    outfit = C.join("outfit", parts)
    gearo = C.join("gear", g)
    for o in (outfit, gearo):
        unwrap(o)
        print("OUTFIT", o.name, "tris", L.tri_count(o), "materials", len(o.material_slots))
    L.save_stage(A.work, "s05")


main()
