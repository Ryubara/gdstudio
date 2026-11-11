"""Stage 4: hair as cards, in two styles a woman wears today. Draws a strand atlas (eight strips, from dense
locks to flyaways and lashes), then builds:

- `hair_ponytail`: the hair drawn back over the scalp to a tie high on the back of the head, a tail that arcs out
  and falls to the shoulder blades, short hairs along the hairline and two loose strands at the temples;
- `hair_long`: long hair worn down from a part on her left, swept off the face, over the ears and the shoulders
  to the chest.

One is shown at a time (the export and the renders pick). Brows and lashes are small cards from the same atlas.

A card is a strip of quads along a path: over the scalp towards the tie, or falling under gravity and pushed off
the body. Its normals are the surface's under it (or point away from the lock's middle), so a style shades as one
volume and not as a pile of flat cards. The scalp under the cards is painted in the hair's colour by stage 2 and
fades over a centimetre, so the hairline is soft and no gap shows a cap.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_lib as L  # noqa: E402
import rc_materials as M  # noqa: E402

A = L.args()
TEX = f"{A.work}/tex"
STRIPS = 8
TIE_V = 0.05  # the tie's solid patch is the lowest 5 % of the last strip
HAIR_RGB = L.HAIR_RGB
RNG = np.random.default_rng(11)
S = L.SCALE


def srgb(a):
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.clip(a, 0, None) ** (1 / 2.4) - 0.055)


def save(name, px, colour, alpha=False):
    size = px.shape[0]
    img = bpy.data.images.new("out_" + name, size, size, alpha=alpha)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    if px.shape[2] == 3:
        px = np.concatenate([px, np.ones((size, size, 1), dtype=px.dtype)], 2)
    img.pixels.foreach_set(px.astype(np.float32).ravel())
    img.filepath_raw = f"{TEX}/{name}.png"
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def hair_atlas(size):
    """Strands drawn root (top) to tip (bottom), far strands first: colour and coverage, a normal across each
    strand, and depth as occlusion."""
    w = size // STRIPS
    rng = np.random.default_rng(7)
    rgb = np.tile(HAIR_RGB, (size, size, 1)).astype(np.float64)
    alpha = np.zeros((size, size))
    nx = np.zeros((size, size))
    occ = np.ones((size, size))
    rows = np.arange(size)
    t = 1 - rows / (size - 1)
    off = np.arange(-4, 5)
    px = size / 2048
    #        strands, half width (px), clumps, wave, shortest
    spec = [(120, 1.5, 5, 3, 0.92), (100, 1.4, 4, 5, 0.86), (80, 1.6, 3, 7, 0.74), (50, 1.4, 4, 6, 0.6),
            (38, 1.5, 3, 9, 0.5), (20, 1.4, 3, 10, 0.5), (7, 1.2, 2, 16, 0.6), (7, 2.6, 0, 3, 0.55)]
    for k, (count, hw, clumps, wave, shortest) in enumerate(spec):
        x_lo, x_hi = k * w + 6 * px, (k + 1) * w - 6 * px
        centres = rng.uniform(x_lo + 0.15 * w, x_hi - 0.15 * w, max(clumps, 1))
        depth = np.sort(rng.uniform(0, 1, count))
        for i in range(count):
            x0 = rng.uniform(x_lo + 4 * px, x_hi - 4 * px)
            xc = centres[rng.integers(len(centres))] + rng.normal(0, 0.03 * w)
            pull = rng.uniform(0.35, 0.9) if clumps else 0.0
            ph, fr = rng.uniform(0, 6.28), rng.uniform(0.6, 1.8)
            x = x0 + (xc - x0) * pull * t**1.4 + wave * px * np.sin(ph + fr * 6.28 * t) * t
            x += rng.normal(0, 1) * 10 * px * t**2
            length = rng.uniform(shortest, 1.0)
            if k == 7:
                x = x0 + rng.normal(0, 6 * px) * t + 10 * px * t**2 * rng.choice([-1, 1])
                half = hw * px * np.clip((length - t) / length, 0, 1) ** 0.8 * rng.uniform(0.7, 1.1)
            else:
                half = hw * px * rng.uniform(0.6, 1.1) * np.clip((length - t) / 0.3, 0, 1) ** 0.7
            x = np.clip(x, x_lo, x_hi)
            live = half > 0.02
            rr = rows[live][:, None]
            cc = np.floor(x[live])[:, None].astype(np.int64) + off[None, :]
            cov = np.clip(half[live][:, None] + 0.5 - np.abs(cc - x[live][:, None]), 0, 1)
            cov *= L.smoothstep(0.0, 0.035, t[live])[:, None]
            cc = np.clip(cc, 0, size - 1)
            shade = 0.45 + 0.55 * depth[i]
            # One strand in seven is lightened by the sun: the colour's own highlights, apart from the shader's.
            light = rng.random() < 0.14
            tone = (L.HAIR_LIGHT * rng.uniform(0.7, 1.15) if light else HAIR_RGB * min(rng.lognormal(0, 0.3), 1.9))
            grad = (0.80 + 0.22 * t[live])[:, None, None]
            rgb[rr, cc] = rgb[rr, cc] * (1 - cov[..., None]) + tone * grad * cov[..., None]
            occ[rr, cc] = occ[rr, cc] * (1 - cov) + shade * cov
            nx[rr, cc] = nx[rr, cc] * (1 - cov) + np.clip((cc - x[live][:, None]) / np.maximum(half[live][:, None], 0.6), -1, 1) * cov
            alpha[rr, cc] = alpha[rr, cc] + cov * (1 - alpha[rr, cc])
    # A solid patch for the hair tie, in the corner under the lash strip (no card reaches that low).
    tie = (slice(0, int(TIE_V * size)), slice(7 * w, size))
    rgb[tie], alpha[tie], occ[tie], nx[tie] = np.array([0.012, 0.012, 0.014]), 1.0, 1.0, 0.0
    albedo = np.concatenate([srgb(np.clip(rgb, 0, 1)), np.clip(alpha, 0, 1)[..., None]], 2)
    save("hair_albedo", albedo, True, alpha=True)
    n = np.stack([nx * 0.7, np.zeros_like(nx), np.sqrt(np.clip(1 - (nx * 0.7) ** 2, 0, 1))], 2)
    save("hair_normal", n * 0.5 + 0.5, False)
    orm = np.stack([occ, np.full_like(occ, 0.52) + 0.15 * (1 - occ), np.zeros_like(occ)], 2)
    save("hair_orm", orm, False)
    print("ATLAS hair", size)


class Cards:
    def __init__(self):
        self.v, self.f, self.uv, self.n = [], [], [], []

    def add(self, pts, nrms, w_root, w_tip, strip, tilt=0.0, v0=1.0, v1=0.0):
        base = len(self.v)
        u0, u1 = (strip + 0.06) / STRIPS, (strip + 0.94) / STRIPS
        if RNG.random() < 0.5:
            u0, u1 = u1, u0
        m = len(pts)
        for i, (p, n) in enumerate(zip(pts, nrms)):
            d = (pts[min(i + 1, m - 1)] - pts[max(i - 1, 0)]).normalized()
            across = n.cross(d)
            if across.length < 1e-6:
                across = Vector((1, 0, 0))
            across = (Matrix.Rotation(tilt, 3, d) @ across.normalized())
            t = i / (m - 1)
            hw = 0.5 * (w_root + (w_tip - w_root) * t)
            self.v += [p - across * hw, p + across * hw]
            nn = (n + 0.25 * d.cross(across)).normalized() if n.length else n
            self.n += [nn, nn]
            vv = v0 + (v1 - v0) * t
            self.uv += [(u0, vv), (u1, vv)]
            if i:
                a = base + 2 * (i - 1)
                self.f.append((a, a + 1, a + 3, a + 2))

    def band(self, centre, axis, radius, thick, major=14, minor=6):
        """The hair tie: a small torus about `axis`, textured from the atlas's solid patch."""
        base = len(self.v)
        axis = axis.normalized()
        u = axis.orthogonal().normalized()
        w = axis.cross(u)
        for i in range(major):
            a = 2 * math.pi * i / major
            ring = u * math.cos(a) + w * math.sin(a)
            for j in range(minor):
                b = 2 * math.pi * j / minor
                n = ring * math.cos(b) + axis * math.sin(b)
                self.v.append(centre + ring * radius + n * thick)
                self.n.append(n)
                self.uv.append(((7.5 + 0.2 * i / major) / STRIPS, TIE_V * 0.5))
        for i in range(major):
            for j in range(minor):
                a, b = base + i * minor + j, base + i * minor + (j + 1) % minor
                c, d = base + ((i + 1) % major) * minor + (j + 1) % minor, base + ((i + 1) % major) * minor + j
                self.f.append((a, b, c, d))

    def build(self, name, mat):
        o = L.new_mesh_obj(name, self.v, self.f)
        uv = o.data.uv_layers.new(name="UVMap")
        for loop in o.data.loops:
            uv.data[loop.index].uv = self.uv[loop.vertex_index]
        for p in o.data.polygons:
            p.use_smooth = True
        o.data.normals_split_custom_set_from_vertices([tuple(n) for n in self.n])
        o.data.materials.append(mat)
        print("CARDS", name, "cards", len(self.f) and len(self.v) // 2, "tris", L.tri_count(o))
        return o


def sample_scalp(skin, count, weight=None):
    """Random points on the scalp, by area (times `weight(centres in base metres)`), with the smooth normal there."""
    mesh = skin.data
    mesh.calc_loop_triangles()
    co = L.co_get(mesh)
    nr = L.normals_get(mesh)
    tri = np.array([t.vertices[:] for t in mesh.loop_triangles])
    cen = co[tri].mean(1)
    head = cen[:, 2] > 1.44 * S
    wgt = np.zeros(len(tri))
    wgt[head] = L.scalp_mask(cen[head] / S)
    if weight is not None:
        wgt[head] *= weight(cen[head] / S)
    e1, e2 = co[tri[:, 1]] - co[tri[:, 0]], co[tri[:, 2]] - co[tri[:, 0]]
    area = np.linalg.norm(np.cross(e1, e2), axis=1) / 2
    p = wgt * area
    idx = RNG.choice(len(tri), count, p=p / p.sum())
    b = RNG.dirichlet((1, 1, 1), count)
    pts = (co[tri[idx]] * b[:, :, None]).sum(1)
    nrm = (nr[tri[idx]] * b[:, :, None]).sum(1)
    nrm /= np.linalg.norm(nrm, axis=1)[:, None]
    return [Vector(q) for q in pts], [Vector(q) for q in nrm]


def hairline(c):
    """1 on the scalp's rim, 0 inside: where the short hairs of a hairline grow (base metres)."""
    m = L.scalp_mask(c, soft=0.006)
    return np.clip(1 - np.abs(m - 0.45) / 0.4, 0, 1)


def fall(body, p, d, steps, step, clearance, field, stop_z=-1.0, stick_z=9.0):
    """A lock's path: from `p` heading `d`, each step turned towards `field(p, i)` (which carries gravity) and
    pushed out to `clearance` off the body (above `stick_z` it is held at that distance, as hair lies on a skull). Returns the points and, for each, the body's normal near it."""
    pts, nrms = [p.copy()], [None]
    for i in range(steps):
        d = (d * 0.5 + field(p, i).normalized() * 0.5).normalized()
        p = p + d * step
        loc, nrm, _, _ = body.find_nearest(p)
        gap = clearance * min(1.0, (i + 1) / 5)  # a lock leaves the scalp gradually, or its root stands up
        if (p - loc).dot(nrm) < gap or p.z > stick_z:
            p = loc + nrm * gap  # off the body; and above `stick_z` hair lies on the head, it does not fly
        pts.append(p.copy())
        nrms.append(nrm.copy() if (p - loc).length < 0.05 else None)
        if p.z < stop_z:
            break
    nrms[0] = nrms[1]
    return pts, nrms


def ponytail(skin, tree, body):
    cards = Cards()
    # The tie: high on the back of the head, a finger's width off the scalp.
    centre = Vector((0.0, -0.01, 1.56)) * S
    hit, hn, _, _ = tree.ray_cast(centre, Vector((0.0, 0.93, 0.36)).normalized(), 0.3)
    tie = hit + hn * 0.014
    out = (hn + Vector((0, 0.25, 0.25))).normalized()
    print("HAIR ponytail tie at", [round(v, 3) for v in tie])

    def drawn_back(p, n, strip, width, h0, volume, v1=0.12):
        """A card from a root over the scalp to the tie, lifted a little in the middle for volume."""
        line, ln = [p + n * h0], [n]
        q, qn = p, n
        total = (tie - p).length
        for _ in range(40):
            to = tie - q
            if to.length < 0.028:
                break
            d = to - qn * to.dot(qn)
            if d.length < 1e-5:
                break
            loc, fn, _, _ = tree.find_nearest(q + d.normalized() * 0.011)
            q, qn = loc, (qn * 0.5 + fn * 0.5).normalized()
            t = 1 - (tie - q).length / max(total, 1e-4)
            line.append(q + qn * (h0 + volume * math.sin(math.pi * min(max(t, 0), 1)) ** 0.8))
            ln.append(qn)
        if len(line) < 3:
            return
        line += [tie - out * 0.004 + (line[-1] - tie) * 0.25, tie + out * 0.004]
        ln += [ln[-1], ln[-1]]
        cards.add(line, ln, width, width * 0.4, strip, tilt=RNG.normal(0, 0.12), v0=1.0, v1=v1)

    # The body of the hair, in layers: lower cards first, each layer a little higher off the scalp.
    pts, nrms = sample_scalp(skin, 560)
    rim = hairline(np.array([q[:] for q in pts]) / S)
    for k, (p, n) in enumerate(zip(pts, nrms)):
        layer = k / len(pts)
        strip = int(RNG.integers(0, 3)) if RNG.random() < 0.7 else int(RNG.integers(3, 5))
        width = RNG.uniform(0.016, 0.026)
        if rim[k] > 0.2:
            # Rooted on the rim: a thinner card of fewer strands, so the hairline is not a wall.
            strip, width = int(RNG.integers(3, 6)), width * 0.65
        drawn_back(p, n, strip, width, 0.0010 + 0.0035 * layer, RNG.uniform(0.001, 0.006) * (0.4 + layer))
    # The rim: more, narrower cards rooted on the hairline itself, so its edge is many strands and not one line.
    pts, nrms = sample_scalp(skin, 260, hairline)
    for p, n in zip(pts, nrms):
        drawn_back(p, n, int(RNG.integers(2, 6)), RNG.uniform(0.010, 0.017), RNG.uniform(0.0008, 0.0030), RNG.uniform(0.001, 0.004))
    # Short hairs that did not make it into the tie, along the forehead and the temples.
    pts, nrms = sample_scalp(skin, 110, lambda c: hairline(c) * (c[:, 1] < 0.02))
    for p, n in zip(pts, nrms):
        to = tie - p
        d = (to - n * to.dot(n)).normalized()
        d = Matrix.Rotation(RNG.normal(0, 0.6), 3, n) @ d
        length = RNG.uniform(0.012, 0.030)
        line = [p + n * 0.0006 + d * length * t + n * (0.006 * t**1.5) for t in (0.0, 0.35, 0.7, 1.0)]
        cards.add(line, [n] * 4, 0.011, 0.009, int(RNG.integers(5, 7)), tilt=RNG.normal(0, 0.4), v0=1.0, v1=0.45)

    # The tail: arcs out of the tie and falls; its cards fan around one centre line.
    def tail_field(p, i):
        return Vector((0.0, 0.10, -1.0))

    start = out * 0.6 + Vector((0, 0.5, 0.35))
    mid, _ = fall(body, tie + out * 0.006, start.normalized(), 17, 0.02, 0.016, tail_field)
    u = start.normalized().orthogonal().normalized()
    w = start.normalized().cross(u)
    for k in range(95):
        ang, rad = RNG.uniform(0, 2 * math.pi), 0.011 * math.sqrt(RNG.random())
        off = (u * math.cos(ang) + w * math.sin(ang)) * rad
        d0 = (start.normalized() + off * 9).normalized()
        steps = int(RNG.uniform(12, 17.99))
        line, _ = fall(body, tie + out * 0.006 + off, d0, steps, 0.02, 0.008 + rad, tail_field)
        ln = []
        for i, q in enumerate(line):
            r = q - mid[min(i, len(mid) - 1)]
            ln.append(r.normalized() if r.length > 0.002 else (off.normalized() if off.length else out))
        spread = [q + ln[i] * (0.012 * (i / len(line)) ** 1.2) for i, q in enumerate(line)]
        strip = int(RNG.integers(0, 3)) if k < 70 else int(RNG.integers(3, 6))
        cards.add(spread, ln, RNG.uniform(0.018, 0.028), RNG.uniform(0.010, 0.016), strip, tilt=RNG.normal(0, 0.3))
    cards.band(tie + out * 0.004, out, 0.0115, 0.0034, 18, 8)

    # Two loose strands at each temple, falling in front of the ear.
    for sx in (1, -1):
        for k in range(2):
            root = Vector((sx * RNG.uniform(0.060, 0.070), RNG.uniform(-0.088, -0.070), RNG.uniform(1.578, 1.590))) * S
            p, n, _, _ = tree.find_nearest(root)

            def strand(q, i, sx=sx):
                return Vector((sx * 0.10 * math.sin(i * 0.7), -0.10 + 0.05 * math.cos(i * 0.6), -1.0))

            line, ln = fall(body, p + n * 0.002, Vector((sx * 0.5, -0.2, -0.6)).normalized(), int(RNG.uniform(5, 8)),
                            0.013, 0.005 + 0.002 * k, strand)
            ln = [(q if q is not None else Vector((sx, -0.3, 0))).normalized() for q in ln]
            cards.add(line, ln, 0.008, 0.004, 4 if k else 3, tilt=RNG.normal(0, 0.3))
    return cards


def long_hair(skin, tree, body):
    cards = Cards()
    part = 0.022  # the part, on her left (base metres)
    ear_z = 1.535

    def field_for(side, phase, front):
        def field(p, i):
            b = p / S
            if b.z > ear_z + 0.02:
                # On the skull: away from the part and down, and back off the forehead.
                g = Vector((side * (0.9 if front else 0.75), 0.50 if front else 0.22, -0.30 if front else -0.60))
            else:
                g = Vector((0.16 * math.sin(phase + i * 0.55), 0.06 + 0.12 * math.cos(phase * 1.3 + i * 0.5), -1.0))
            if b.y < -0.040 and abs(b.x) < 0.086 and b.z < 1.60:
                g = Vector((side * 1.0, 0.35, -0.25))  # never across the face
            return g
        return field

    pts, nrms = sample_scalp(skin, 430)
    extra, en = sample_scalp(skin, 70, lambda c: np.exp(-(((c[:, 0] - part) / 0.012) ** 2)) * (c[:, 2] > 1.58))
    for k, (p, n) in enumerate(zip(pts + extra, nrms + en)):
        b = p / S
        side = 1.0 if b.x > part else -1.0
        front = b.y < -0.045
        phase = 6.28 * float(L.fbm3(np.array([[b.x * 14, b.y * 14, b.z * 14]]), 2, 3)[0]) * 2
        layer = RNG.random()
        clearance = 0.002 + 0.011 * layer
        d0 = Vector((side * 0.7, 0.3, -0.4))
        d0 = (d0 - n * d0.dot(n)).normalized()
        tip_z = RNG.uniform(1.235, 1.33) * S
        line, ln = fall(body, p + n * 0.0015, d0, 30, 0.024, clearance, field_for(side, phase, front), stop_z=tip_z,
                        stick_z=(ear_z - 0.03) * S)
        if len(line) < 4:
            continue
        axis_pts = [Vector((0.0, 0.01 * S, q.z)) for q in line]
        ln = [(m if m is not None else (q - a)).normalized() for m, q, a in zip(ln, line, axis_pts)]
        strip = int(RNG.integers(0, 3)) if layer < 0.75 else int(RNG.integers(3, 6))
        width = RNG.uniform(0.022, 0.034)
        if hairline(np.array([b[:]]))[0] > 0.2:
            strip, width = int(RNG.integers(3, 6)), width * 0.65
        cards.add(line, ln, width * 0.8, width * RNG.uniform(0.6, 0.9), strip, tilt=RNG.normal(0, 0.25))
    # The hairline's short hairs.
    pts, nrms = sample_scalp(skin, 90, lambda c: hairline(c) * (c[:, 1] < 0.02))
    for p, n in zip(pts, nrms):
        side = 1.0 if p.x / S > part else -1.0
        d = Vector((side * 0.7, 0.5, -0.3))
        d = Matrix.Rotation(RNG.normal(0, 0.5), 3, n) @ (d - n * d.dot(n)).normalized()
        length = RNG.uniform(0.014, 0.034)
        line = [p + n * 0.0006 + d * length * t + n * (0.006 * t**1.5) for t in (0.0, 0.35, 0.7, 1.0)]
        cards.add(line, [n] * 4, 0.011, 0.009, int(RNG.integers(5, 7)), tilt=RNG.normal(0, 0.4), v0=1.0, v1=0.45)
    return cards


def brow_cards(tree, cards):
    for sx in (1, -1):
        made = 0
        while made < 85:
            x = RNG.uniform(0.008, 0.057)
            z = RNG.uniform(1.538, 1.557)
            c = np.array([[sx * x, -0.1, z]])
            m, bx = L.brow_field(c)
            if m[0] < 0.25 or (sx > 0 and 0.0335 < x < 0.0440 and abs((x - 0.0345) / 0.008 * -0.0255 + 1.566 - z) < 0.0016):
                continue
            hit = tree.ray_cast(Vector((sx * x * S, -0.4, z * S)), Vector((0, 1, 0)), 0.6)
            if hit[0] is None:
                continue
            p, n = hit[0], hit[1]
            b = float(bx[0])
            ang = math.radians(78 - 95 * b + RNG.normal(0, 9)) if b < 0.75 else math.radians(-12 - 25 * (b - 0.75) / 0.25 + RNG.normal(0, 8))
            d = Vector((sx * math.cos(ang), 0, math.sin(ang)))
            d = (d - n * d.dot(n)).normalized()
            length = RNG.uniform(0.006, 0.0095) * (1 - 0.35 * b)
            line = [p + n * 0.0002, p + n * 0.0009 + d * length * 0.5, p + n * 0.0011 + d * length]
            cards.add(line, [n, n, n], 0.0042, 0.0034, 7, tilt=RNG.normal(0, 0.15), v0=1.0, v1=0.35)
            made += 1


def lash_cards(tree, cards):
    sc = bpy.context.scene
    r = sc["eye_radius"]
    c0 = sc["eye_center"]
    fwd = Vector((0, -1, 0))
    for side, sx in (("L", 1), ("R", -1)):
        contour = list(sc[f"lid_contour_{side}"])
        centre = Vector((sx * c0[0], c0[1], c0[2]))
        n = len(contour)
        for k in range(0, n):
            phi = 2 * math.pi * k / n
            up = math.sin(phi)
            if abs(up) < 0.18:
                continue
            upper = up > 0
            if not upper and k % 2:
                continue
            th = contour[k]
            th += math.radians(2.5)
            root = centre + (r + 0.0011) * Vector((math.sin(th) * math.cos(phi), -math.cos(th), math.sin(th) * math.sin(phi)))
            hit = tree.ray_cast(root + fwd * 0.03, -fwd, 0.04)
            if hit[0] is not None:
                root = hit[0] + fwd * 0.0002
            radial = Vector((math.cos(phi), 0, math.sin(phi)))
            mid = abs(up) ** 0.6
            if upper:
                length = (0.0055 + 0.0040 * mid) * RNG.uniform(0.85, 1.1)
                p1 = root + length * 0.5 * (fwd * 0.85 + radial * 0.15 + Vector((0, 0, -0.10)))
                p2 = p1 + length * 0.5 * (fwd * 0.62 + radial * 0.2 + Vector((0, 0, 0.62))).normalized()
            else:
                length = (0.0028 + 0.0020 * mid) * RNG.uniform(0.85, 1.1)
                p1 = root + length * 0.5 * (fwd * 0.8 + radial * 0.5)
                p2 = p1 + length * 0.5 * (fwd * 0.6 + radial * 0.5 + Vector((0, 0, -0.5))).normalized()
            nrm = Vector((0, -0.6, 0.8 if upper else -0.8)).normalized()
            wide = 0.0034 if upper else 0.0026
            cards.add([root, p1, p2], [nrm, nrm, nrm], wide, wide * 1.2, 7, tilt=RNG.normal(0, 0.1), v0=1.0, v1=0.25)


def main():
    L.open_stage(A.work, "s03")
    hair_atlas(1024 if A.quick else 2048)
    skin = bpy.data.objects["skin"]
    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(skin, dg)
    body = BVHTree.FromObject(bpy.data.objects["body_full"], dg)
    mat = M.hair(TEX)
    ponytail(skin, tree, body).build("hair_ponytail", mat)
    long_hair(skin, tree, body).build("hair_long", mat)
    small = Cards()
    brow_cards(tree, small)
    lash_cards(tree, small)
    small.build("brows_lashes", mat)
    bpy.context.scene.cycles.transparent_max_bounces = 64
    L.save_stage(A.work, "s04")


main()
