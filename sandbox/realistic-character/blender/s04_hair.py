"""Stage 4: hair as cards. Draws a strand atlas (eight strips, from dense clumps to flyaways and lashes), then
lays textured cards over the scalp along a flow field: a short cut swept back and to her right from a part on
her left, clipped around the ears, short at the nape. Brows and lashes are small cards from the same atlas.

A card is a strip of quads that follows the head at a small height and lifts towards its tip; its normals are
the scalp's, so the cut shades as one volume and not as a pile of flat cards.
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
HAIR_RGB = np.array([0.060, 0.036, 0.021])
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
    spec = [(105, 1.5, 5, 3, 0.80), (90, 1.4, 4, 5, 0.72), (75, 1.6, 3, 7, 0.65), (50, 1.4, 4, 6, 0.6),
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
            tone = HAIR_RGB * min(rng.lognormal(0, 0.4), 2.2) * (np.array([1.7, 1.45, 1.2]) if rng.random() < 0.06 else 1.0)
            grad = (0.75 + 0.6 * t[live])[:, None, None]
            rgb[rr, cc] = rgb[rr, cc] * (1 - cov[..., None]) + tone * grad * cov[..., None]
            occ[rr, cc] = occ[rr, cc] * (1 - cov) + shade * cov
            nx[rr, cc] = nx[rr, cc] * (1 - cov) + np.clip((cc - x[live][:, None]) / np.maximum(half[live][:, None], 0.6), -1, 1) * cov
            alpha[rr, cc] = alpha[rr, cc] + cov * (1 - alpha[rr, cc])
    albedo = np.concatenate([srgb(np.clip(rgb, 0, 1)), np.clip(alpha, 0, 1)[..., None]], 2)
    save("hair_albedo", albedo, True, alpha=True)
    n = np.stack([nx * 0.7, np.zeros_like(nx), np.sqrt(np.clip(1 - (nx * 0.7) ** 2, 0, 1))], 2)
    save("hair_normal", n * 0.5 + 0.5, False)
    orm = np.stack([occ, np.full_like(occ, 0.40) + 0.1 * (1 - occ), np.zeros_like(occ)], 2)
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


def sample_scalp(skin, count):
    """Random points on the scalp, by area, with the smooth normal there."""
    mesh = skin.data
    mesh.calc_loop_triangles()
    co = L.co_get(mesh)
    nr = L.normals_get(mesh)
    tri = np.array([t.vertices[:] for t in mesh.loop_triangles])
    cen = co[tri].mean(1)
    head = cen[:, 2] > 1.44 * S
    wgt = np.zeros(len(tri))
    wgt[head] = L.scalp_mask(cen[head] / S)
    e1, e2 = co[tri[:, 1]] - co[tri[:, 0]], co[tri[:, 2]] - co[tri[:, 0]]
    area = np.linalg.norm(np.cross(e1, e2), axis=1) / 2
    p = wgt * area
    idx = RNG.choice(len(tri), count, p=p / p.sum())
    b = RNG.dirichlet((1, 1, 1), count)
    pts = (co[tri[idx]] * b[:, :, None]).sum(1)
    nrm = (nr[tri[idx]] * b[:, :, None]).sum(1)
    nrm /= np.linalg.norm(nrm, axis=1)[:, None]
    return pts, nrm, (wgt * area).sum()


def flow(p, n):
    """The direction hair grows at a scalp point: back and to her right on top, down on the sides and back."""
    top = float(L.smoothstep(0.30, 0.75, np.array([n.z]))[0])
    part = 0.032 * S
    if p.x < part:
        sweep = Vector((-0.50, 0.86, -0.05))
    else:
        sweep = Vector((0.85, 0.35, -0.35))
    front = float(L.smoothstep(-0.03 * S, -0.09 * S, np.array([p.y]))[0])
    sweep = sweep + Vector((0, 0.3, 0.25)) * front
    side = Vector((0.0, 0.30, -1.0))
    return (sweep * top + side * (1 - top)).normalized(), top


def hair_cards(skin, tree, count):
    cards = Cards()
    pts, nrms, area = sample_scalp(skin, count)
    ear_top = 1.558 * S
    for p, n in zip(pts, nrms):
        p, n = Vector(p), Vector(n)
        g, top = flow(p, n)
        length = (0.050 + 0.055 * top) * RNG.uniform(0.75, 1.15)
        nape = float(L.smoothstep(1.56 * S, 1.50 * S, np.array([p.z]))[0]) * (p.y > 0.02)
        length *= 1 - 0.45 * nape
        if p.y < 0.035 * S and top < 0.5 and p.z < ear_top + 0.07:
            length = min(length, max(0.012, (p.z - (ear_top - 0.004)) * 1.05))
        nseg = 5
        h0 = RNG.uniform(0.0012, 0.0055)
        front = float(L.smoothstep(-0.04 * S, -0.10 * S, np.array([p.y]))[0]) * top
        lift = RNG.uniform(0.002, 0.007) + 0.008 * top * RNG.random() + 0.014 * front
        length *= 1 + 0.25 * front
        dev = Matrix.Rotation(RNG.normal(0, 0.16), 3, n)
        line, ln = [p + n * h0], [n]
        q, qn = p, n
        for i in range(1, nseg + 1):
            t = i / nseg
            g, _ = flow(q, qn)
            d = dev @ g
            d = d - qn * d.dot(qn)
            if d.length < 1e-5:
                break
            q2 = q + d.normalized() * (length / nseg)
            loc, fn, _, _ = tree.find_nearest(q2)
            q = loc
            qn = (qn * 0.5 + fn * 0.5).normalized()
            line.append(q + qn * (h0 + lift * t**1.4))
            ln.append(qn)
        if len(line) < 3:
            continue
        r = RNG.random()
        strip = int(RNG.integers(0, 3)) if r < 0.62 else int(RNG.integers(3, 5)) if r < 0.9 else 5
        width = RNG.uniform(0.011, 0.019) * (0.8 + 0.4 * top)
        cards.add(line, ln, width, width * RNG.uniform(0.55, 0.9), strip, tilt=RNG.normal(0, 0.22))
    # Flyaways: a few thin wisps that leave the shape, most at the front and the crown.
    pts, nrms, _ = sample_scalp(skin, count // 30)
    for p, n in zip(pts, nrms):
        p, n = Vector(p), Vector(n)
        g, top = flow(p, n)
        length = RNG.uniform(0.03, 0.06)
        d = (g - n * g.dot(n)).normalized()
        d = Matrix.Rotation(RNG.normal(0, 0.35), 3, n) @ d
        line, ln = [], []
        out = RNG.uniform(0.08, 0.30)
        for i in range(5):
            t = i / 4
            line.append(p + n * (0.003 + out * length * t**1.6) + d * length * t + Vector((0, 0, -0.012 * t * t)))
            ln.append(n)
        cards.add(line, ln, 0.010, 0.008, 6, tilt=RNG.normal(0, 0.5))
    return cards, area


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
    tree = BVHTree.FromObject(skin, bpy.context.evaluated_depsgraph_get())
    mat = M.hair(TEX)
    cards, area = hair_cards(skin, tree, 1500)
    cards.build("hair", mat)
    print("SCALP area m2", round(area, 4))
    small = Cards()
    brow_cards(tree, small)
    lash_cards(tree, small)
    small.build("brows_lashes", mat)
    bpy.context.scene.cycles.transparent_max_bounces = 64
    L.save_stage(A.work, "s04")


main()
