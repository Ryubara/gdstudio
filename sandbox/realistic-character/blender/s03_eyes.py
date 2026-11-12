"""Stage 3: the eyes. Each eye is four meshes, the way current game eyes are layered:

- `eye_*`: the sclera with a recessed, slightly concave iris and a pupil well (one painted texture);
- `cornea_*`: a clear shell over the front with the corneal bulge, which refracts the iris and carries the wet glint;
- `eyeocc_*`: a black shell whose vertex alpha darkens the eye where the lids meet it (ambient occlusion that
  follows the lids, not the eyeball);
- `tear_*`: the wet line where the lower lid meets the eye.

The lid contour (where the eyeball goes under the lids, measured by rays against the skin) is kept on the scene
for the lashes.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_lib as L  # noqa: E402
import rc_materials as M  # noqa: E402

A = L.args()
TEX = f"{A.work}/tex"
IRIS = 0.0061  # iris radius, metres
PUPIL = 0.0021
SEG = 32
CONTOUR = 64


def revolve(name, profile, centre, flip=False):
    """A surface of revolution about the eye's forward axis. `profile` is (radius, forward) from the front pole
    to the back; the UVs are the front view, so a texture drawn as a disc lands on the iris."""
    verts, uvs, faces = [], [], []
    r_eye = bpy.context.scene["eye_radius"]
    rings = []
    for rho, f in profile:
        if rho < 1e-7:
            rings.append([len(verts)])
            verts.append((0.0, -f, 0.0))
            uvs.append((0.5, 0.5))
            continue
        ring = []
        for k in range(SEG):
            a = 2 * math.pi * k / SEG
            ring.append(len(verts))
            verts.append((rho * math.cos(a), -f, rho * math.sin(a)))
            uvs.append((0.5 + rho * math.cos(a) / (2.1 * r_eye), 0.5 + rho * math.sin(a) / (2.1 * r_eye)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(SEG):
            k2 = (k + 1) % SEG
            if len(a) == 1:
                faces.append((a[0], b[k2], b[k]))
            elif len(b) == 1:
                faces.append((a[k], a[k2], b[0]))
            else:
                faces.append((a[k], a[k2], b[k2], b[k]))
    if flip:
        faces = [f[::-1] for f in faces]
    o = L.new_mesh_obj(name, [Vector(v) + Vector(centre) for v in verts], faces)
    uv = o.data.uv_layers.new(name="UVMap")
    for loop in o.data.loops:
        uv.data[loop.index].uv = uvs[loop.vertex_index]
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def bulge(theta, r_eye):
    """How far the cornea stands out of the eyeball's sphere at polar angle theta."""
    t_c = math.asin(IRIS / r_eye) * 1.12
    return 0.0015 * (0.5 + 0.5 * math.cos(math.pi * theta / t_c)) if theta < t_c else 0.0


def lid_contour(tree, centre, r_eye):
    """For CONTOUR directions around the forward axis, the polar angle at which the eyeball goes under a lid."""
    out = []
    c = Vector(centre)
    for k in range(CONTOUR):
        phi = 2 * math.pi * k / CONTOUR
        found = math.radians(60)
        for step in range(1, 120):
            th = math.radians(0.5 * step)
            d = Vector((math.sin(th) * math.cos(phi), -math.cos(th), math.sin(th) * math.sin(phi)))
            hit = tree.ray_cast(c + d * (r_eye * 0.97), d, 0.004)
            if hit[0] is not None:
                found = th
                break
        out.append(found)
    return out


def at(centre, r, th, phi):
    return Vector(centre) + r * Vector((math.sin(th) * math.cos(phi), -math.cos(th), math.sin(th) * math.sin(phi)))


def srgb(a):
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.clip(a, 0, None) ** (1 / 2.4) - 0.055)


def eye_texture(r_eye, size=2048):
    """The sclera and iris painted by rule: radial fibres, a collarette, a dark limbal ring, veins at the rim."""
    v, u = np.mgrid[0:size, 0:size].astype(np.float64) / (size - 1)
    x = (u - 0.5) * 2.1 * r_eye
    z = (v - 0.5) * 2.1 * r_eye
    rho = np.hypot(x, z)
    ang = np.arctan2(z, x)
    r = (rho / IRIS).ravel()
    ca, sa = np.cos(ang).ravel(), np.sin(ang).ravel()
    fib = L.fbm3(np.stack([ca * 22, sa * 22, r * 1.6], 1), 4, 3)
    fib2 = L.fbm3(np.stack([ca * 70, sa * 70, r * 2.0], 1), 3, 9)
    wob = L.fbm3(np.stack([ca * 5, sa * 5, r * 0], 1), 2, 21)
    coll = 0.44 + 0.10 * (wob - 0.5)
    inner = np.array([0.20, 0.085, 0.02])
    outer = np.array([0.040, 0.040, 0.020])
    t = L.smoothstep(coll - 0.07, coll + 0.10, r)[:, None]
    col = inner * (1 - t) + outer * t
    col *= (L.smoothstep(0.25, 0.75, fib) * 1.7 + 0.25)[:, None] * (0.6 + 0.8 * fib2)[:, None]
    col += (np.exp(-(((r - coll) / 0.05) ** 2)) * 0.10)[:, None] * np.array([1.0, 0.7, 0.3])
    col *= (1 - 0.85 * L.smoothstep(0.80, 1.0, r))[:, None]
    col *= L.smoothstep(PUPIL / IRIS - 0.02, PUPIL / IRIS + 0.04, r)[:, None]
    # Sclera: off-white, pinker and veined towards the rim.
    p3 = np.stack([x.ravel() * 420, z.ravel() * 420, np.zeros(x.size)], 1)
    ridged = 1 - np.abs(2 * L.fbm3(p3, 4, 31) - 1)
    ridged2 = 1 - np.abs(2 * L.fbm3(p3 * 2.3, 3, 57) - 1)
    rim = L.smoothstep(0.0062, 0.0115, rho.ravel())
    veins = np.clip(L.smoothstep(0.90, 0.985, ridged) + 0.6 * L.smoothstep(0.92, 0.99, ridged2), 0, 1) * (0.15 + 0.85 * rim)
    scl = np.array([0.60, 0.56, 0.52]) * (1 - 0.25 * rim)[:, None] + np.array([0.10, -0.03, -0.04]) * rim[:, None]
    scl = scl * (1 - 0.55 * veins)[:, None] + np.array([0.42, 0.06, 0.05]) * (0.55 * veins)[:, None]
    edge = L.smoothstep(0.97, 1.03, r)[:, None]
    rgb = col * (1 - edge) + scl * edge
    img = bpy.data.images.new("eye_albedo", size, size, alpha=False)
    px = np.ones((size * size, 4), dtype=np.float32)
    px[:, :3] = srgb(np.clip(rgb, 0, 1))
    img.pixels.foreach_set(px.ravel())
    img.filepath_raw = f"{TEX}/eye_albedo.png"
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def build_eye(side, centre, tree, mats):
    sc = bpy.context.scene
    r = sc["eye_radius"]
    th_l = math.asin(IRIS / r)
    f_l = r * math.cos(th_l)
    # Eyeball: pupil well, concave iris, sclera to the back pole.
    prof = [(0.0, f_l - 0.0016), (PUPIL * 0.98, f_l - 0.0015), (PUPIL, f_l - 0.0009)]
    for i in range(1, 6):
        rho = PUPIL + (IRIS - PUPIL) * i / 5
        prof.append((rho, f_l - 0.0009 * (1 - (rho / IRIS) ** 2)))
    for i in range(1, 19):
        th = th_l + (math.pi - th_l) * i / 18
        prof.append((r * math.sin(th) if i < 18 else 0.0, r * math.cos(th)))
    ball = revolve(f"eye_{side}", prof, centre)
    ball.data.materials.append(mats["eye"])

    def shell(name, extra, th_max, n):
        p = [(0.0, r + extra + bulge(0, r))]
        for i in range(1, n + 1):
            th = th_max * i / n
            rr = r + extra + bulge(th, r)
            p.append((rr * math.sin(th), rr * math.cos(th)))
        return revolve(f"{name}_{side}", p, centre)

    cornea = shell("cornea", 0.00004, math.radians(72), 18)
    cornea.data.materials.append(mats["cornea"])
    contour = lid_contour(tree, centre, r)
    occ = shell("eyeocc", 0.00022, math.radians(66), 16)
    occ.data.materials.append(mats["occ"])
    col = occ.data.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
    for v in occ.data.vertices:
        d = (v.co - Vector(centre)).normalized()
        th = math.acos(max(-1, min(1, -d.y)))
        phi = math.atan2(d.z, d.x) % (2 * math.pi)
        k = phi / (2 * math.pi) * CONTOUR
        k0 = int(k) % CONTOUR
        thc = contour[k0] + (contour[(k0 + 1) % CONTOUR] - contour[k0]) * (k - int(k))
        t = th / max(thc, 1e-4)
        a = 0.88 * float(L.smoothstep(0.50, 1.0, np.array([t]))[0]) ** 1.4
        a += 0.22 * float(L.smoothstep(0.15, 1.0, np.array([t]))[0]) * max(math.sin(phi), 0.0)
        col.data[v.index].color = (0, 0, 0, min(a, 0.95))
    # Tear line: a thin wet tube along the lower lid's contact line.
    pts = [(k, contour[k]) for k in range(CONTOUR) if math.sin(2 * math.pi * k / CONTOUR) < -0.12]
    verts, faces = [], []
    for i, (k, thc) in enumerate(pts):
        phi = 2 * math.pi * k / CONTOUR
        base = at(centre, r + 0.0001, thc - 0.012, phi)
        n = (base - Vector(centre)).normalized()
        tang = (at(centre, r, thc, phi + 0.05) - at(centre, r, thc, phi - 0.05)).normalized()
        b = n.cross(tang)
        for j in range(4):
            a = math.pi / 2 * j
            verts.append(base + 0.00038 * (math.cos(a) * n + math.sin(a) * b))
        if i:
            for j in range(4):
                j2 = (j + 1) % 4
                faces.append((4 * (i - 1) + j, 4 * (i - 1) + j2, 4 * i + j2, 4 * i + j))
    tear = L.new_mesh_obj(f"tear_{side}", verts, faces)
    for p in tear.data.polygons:
        p.use_smooth = True
    tear.data.materials.append(mats["tear"])
    for o in (cornea, occ, tear):
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        cen = sum((f.calc_center_median() for f in bm.faces), Vector()) / len(bm.faces)
        if sum((f.normal.dot(f.calc_center_median() - (Vector(centre) if o is not tear else cen)) for f in bm.faces)) < 0:
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(o.data)
        bm.free()
    sc[f"lid_contour_{side}"] = contour
    tris = sum(L.tri_count(o) for o in (ball, cornea, occ, tear))
    print("EYE", side, "tris", tris, "opening deg", round(math.degrees(min(contour)), 1), round(math.degrees(max(contour)), 1))


def main():
    L.open_stage(A.work, "s02")
    sc = bpy.context.scene
    skin = bpy.data.objects["skin"]
    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(skin, dg)
    eye_texture(sc["eye_radius"])
    mats = {"eye": M.eye(TEX), "cornea": M.clear_shell("cornea", 1.376), "occ": M.occlusion(),
            "tear": M.clear_shell("tearline", 1.34)}
    c = sc["eye_center"]
    build_eye("L", (c[0], c[1], c[2]), tree, mats)
    build_eye("R", (-c[0], c[1], c[2]), tree, mats)
    L.save_stage(A.work, "s03")


main()
