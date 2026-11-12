"""Clothes and straps cut from the body they sit on (kit docs: tools/blender/realistic-characters.md#clothes).

- `shell`: a garment from the faces of a source mesh, cut along the zero line of a field, pushed off the body and
  pulled taut so it bridges hollows the way cloth under tension does;
- `plane_ring` and `strap`: a belt or strap as a band lofted around the convex outline a plane cuts from the body;
- `box`: a bevelled box for hard gear.
"""

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, geometry

import rc_lib as L


def shell(name, src, coarse, field, offset, tension=12, folds=None, rim=0.002):
    """`coarse(c, part)` picks candidate faces by centre, `field(c)` is positive where cloth stays, `offset(c)` is
    the cloth's height over the source in metres, `folds(c)` extra height. Positions `c` are base metres."""
    bm = bmesh.new()
    bm.from_mesh(src.data)
    part_layer = bm.faces.layers.int.get("part")
    cen = np.array([f.calc_center_median()[:] for f in bm.faces]) / L.SCALE
    part = np.array([f[part_layer] if part_layer else -1 for f in bm.faces])
    keep = coarse(cen, part)
    bmesh.ops.delete(bm, geom=[f for f, k in zip(bm.faces, keep) if not k], context="FACES")
    # Cut along the field's zero line: split every crossing edge there, join the new vertices across faces.
    bm.verts.ensure_lookup_table()
    val = field(np.array([v.co[:] for v in bm.verts]) / L.SCALE)
    fv = {v: float(val[i]) for i, v in enumerate(bm.verts)}
    new = []
    for e in list(bm.edges):
        a, b = e.verts
        fa, fb = fv[a], fv[b]
        if fa * fb < 0 and abs(fa) > 1e-5 and abs(fb) > 1e-5:
            _, nv = bmesh.utils.edge_split(e, a, fa / (fa - fb))
            fv[nv] = 0.0
            new.append(nv)
    if new:
        bmesh.ops.connect_verts(bm, verts=new, check_degenerate=True)
    drop = [f for f in bm.faces if sum(fv.get(v, 0.0) for v in f.verts) / len(f.verts) < 0]
    bmesh.ops.delete(bm, geom=drop, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.normal_update()
    bm.verts.ensure_lookup_table()
    n = len(bm.verts)
    p0 = np.array([v.co[:] for v in bm.verts])
    nr = np.array([v.normal[:] for v in bm.verts])
    edge = np.array([(e.verts[0].index, e.verts[1].index) for e in bm.edges])
    border = np.zeros(n, dtype=bool)
    for e in bm.edges:
        if e.is_boundary:
            border[e.verts[0].index] = border[e.verts[1].index] = True
    off = offset(p0 / L.SCALE)
    if folds is not None:
        off = off + folds(p0 / L.SCALE) * (~border)
    p = p0 + nr * off[:, None]
    deg = np.bincount(edge.ravel(), minlength=n)[:, None]
    for _ in range(tension):
        acc = np.zeros_like(p)
        np.add.at(acc, edge[:, 0], p[edge[:, 1]])
        np.add.at(acc, edge[:, 1], p[edge[:, 0]])
        sm = acc / np.maximum(deg, 1)
        p = np.where(border[:, None], p, p + 0.6 * (sm - p))
        d = ((p - p0) * nr).sum(1)
        p += nr * np.clip(off - d, 0, None)[:, None]
    for v, q in zip(bm.verts, p):
        v.co = q
    if rim:
        # A turned-in edge, so the cloth has a thickness where it ends.
        bm.normal_update()
        inward = {tuple(round(x, 6) for x in v.co): v.normal.copy() for v in bm.verts if v.is_boundary}
        ext = bmesh.ops.extrude_edge_only(bm, edges=[e for e in bm.edges if e.is_boundary])
        for v in (g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)):
            v.co -= inward[tuple(round(x, 6) for x in v.co)] * rim
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    o = bpy.data.objects.new(name, mesh)
    L.link(o)
    return o


def plane_ring(sources, point, normal, count=48, grow=0.003, only=None):
    """The convex outline a plane cuts from `sources` (objects), as `count` points with their outward directions.
    `only(points)` may drop cut points (one leg, not the other)."""
    point, normal = Vector(point), Vector(normal).normalized()
    u = normal.orthogonal().normalized()
    v = normal.cross(u)
    pts = []
    for o in sources:
        co = L.co_get(o.data)
        e = np.empty(len(o.data.edges) * 2, dtype=np.int32)
        o.data.edges.foreach_get("vertices", e)
        e = e.reshape(-1, 2)
        d = (co - np.array(point)) @ np.array(normal)
        d0, d1 = d[e[:, 0]], d[e[:, 1]]
        cross = d0 * d1 < 0
        t = (d0[cross] / (d0[cross] - d1[cross]))[:, None]
        pts.append(co[e[cross, 0]] * (1 - t) + co[e[cross, 1]] * t)
    pts = np.concatenate(pts)
    if only is not None:
        pts = pts[only(pts)]
    rel = pts - np.array(point)
    p2 = np.stack([rel @ np.array(u), rel @ np.array(v)], 1)
    hull = [p2[i] for i in geometry.convex_hull_2d([tuple(q) for q in p2])]
    hull.append(hull[0])
    seg = [np.linalg.norm(hull[i + 1] - hull[i]) for i in range(len(hull) - 1)]
    total = sum(seg)
    ring, k, walked = [], 0, 0.0
    for i in range(count):
        s = total * i / count
        while walked + seg[k] < s:
            walked += seg[k]
            k += 1
        f = (s - walked) / seg[k]
        ring.append(hull[k] * (1 - f) + hull[k + 1] * f)
    ring = np.array(ring)
    centre = ring.mean(0)
    out = []
    for i in range(count):
        tan = ring[(i + 1) % count] - ring[i - 1]
        nrm = np.array([tan[1], -tan[0]])
        nrm /= np.linalg.norm(nrm) + 1e-9
        if nrm @ (ring[i] - centre) < 0:
            nrm = -nrm
        q = ring[i] + nrm * grow
        out.append((point + u * q[0] + v * q[1], (u * nrm[0] + v * nrm[1]).normalized()))
    return out, normal


def strap(name, ring, axis, width, thick, closed=True):
    """A band of rectangular section along `ring` ((point, outward) pairs), `width` wide along `axis`."""
    verts, faces = [], []
    axis = Vector(axis).normalized()
    for p, nrm in ring:
        for dn, da in ((0, -0.5), (0, 0.5), (1, 0.5), (1, -0.5)):
            verts.append(p + nrm * thick * dn + axis * width * da)
    m = len(ring)
    for i in range(m if closed else m - 1):
        a, b = 4 * i, 4 * ((i + 1) % m)
        for j in range(4):
            j2 = (j + 1) % 4
            faces.append((a + j, a + j2, b + j2, b + j))
    if not closed:
        faces += [(3, 2, 1, 0), tuple(4 * (m - 1) + j for j in range(4))]
    o = L.new_mesh_obj(name, verts, faces)
    fix_normals(o)
    return o


def fix_normals(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()


def box(name, centre, size, rot=None, bevel=0.003, segments=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=segments, affect="EDGES", profile=0.5)
    mat = Matrix.Translation(Vector(centre)) @ (rot.to_4x4() if rot is not None else Matrix.Identity(4))
    bmesh.ops.transform(bm, matrix=mat, verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    L.link(o)
    return o


def cylinder(name, centre, radius, depth, axis, segments=20, bevel=0.0015):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=depth)
    if bevel:
        rim = [e for e in bm.edges if len(e.link_faces) == 2 and any(len(f.verts) > 4 for f in e.link_faces)]
        bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=2, affect="EDGES", profile=0.5)
    rot = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector(centre)) @ rot, verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    L.link(o)
    return o


def join(name, objs):
    L.select_only(objs[0])
    for o in objs:
        o.select_set(True)
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = o.data.name = name
    return o


def ridges(c, freq, seed, sharp=1.0):
    """Fold-like ridges 0..1 from stretched noise: high frequency across the folds, low along them."""
    n = L.fbm3(c * np.array(freq), 3, seed)
    return (1 - np.abs(2 * n - 1)) ** sharp
