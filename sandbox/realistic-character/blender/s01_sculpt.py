"""Stage 1: the body. Takes Blender Studio's CC0 realistic female base mesh (a multires sculpt), reshapes its cage
into our own heroine (face landmarks, build, height), drops the skin the clothes hide, packs the UVs into a head
set and a body set, and saves:

- `body_mr`: the cage with its Multires modifier (the normal bake reads levels 1 and 3 from it);
- `mid`: level 1 applied, the game mesh's skin; `high`: level 3 applied, the surface the textures are painted on;
- `body_full`: level 1 of the whole body, which the clothes are cut from.
"""

import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import kdtree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_lib as L  # noqa: E402

A = L.args()
BASE_OBJ = "GEO-body_female_realistic"

# Landmarks measured on the base (metres, before the height scale; the character faces -Y, +X is her left).
EYE = (0.0329, -0.121, 1.5344)


def frontmost(tree_xz, co, x, z):
    """The surface point in front of the face at (x, z): the lowest y among the vertices nearest in x and z."""
    hits = tree_xz.find_n((x, z, 0.0), 3)
    i = min((h[1] for h in hits), key=lambda k: co[k][1])
    c = co[i].copy()
    c[0], c[2] = x, z
    return c


def deform(co, ref):
    """Reshape positions `co`; `ref` is the mid mesh's positions, used to find the surface under a landmark."""
    kd = kdtree.KDTree(len(ref))
    for i, c in enumerate(ref):
        if c[2] > 1.38 and c[1] < 0.0:
            kd.insert((c[0], c[2], 0.0), i)
    kd.balance()
    out = co.copy()

    def push(x, z, vec, sigma, mirror=True, sign_x=True):
        for sx in (1, -1) if mirror and x != 0 else (1,):
            c = frontmost(kd, ref, sx * x, z)
            w = L.gauss(co, c, sigma)[:, None]
            v = np.array(vec, dtype=np.float64)
            if sign_x:
                v[0] *= sx
            out[:] += w * v

    mm = 0.001
    # Jaw and chin: a squarer jaw angle and a firmer, slightly longer chin.
    push(0.0, 1.432, (0, -2.0 * mm, -2.2 * mm), 0.016)
    push(0.060, 1.462, (0.9 * mm, 0, -0.8 * mm), 0.022)
    # Cheekbones: higher and wider; a little hollow under them.
    push(0.056, 1.516, (1.8 * mm, -1.6 * mm, 1.0 * mm), 0.017)
    push(0.045, 1.482, (-1.0 * mm, 1.0 * mm, 0), 0.014)
    # Nose: a small dorsal hump, the tip turned up, narrower wings.
    push(0.0, 1.522, (0, -1.3 * mm, 0), 0.008)
    push(0.0, 1.502, (0, -0.6 * mm, 1.6 * mm), 0.010)
    push(0.0165, 1.496, (-1.6 * mm, 0.3 * mm, 0), 0.007)
    # Mouth: wider, a fuller lower lip, a sharper bow.
    push(0.0255, 1.466, (1.6 * mm, 0.4 * mm, 0), 0.008)
    push(0.0, 1.461, (0, -1.1 * mm, -0.5 * mm), 0.008)
    push(0.006, 1.4745, (0, -0.4 * mm, 0.8 * mm), 0.004)
    # Brows: a straighter, lower inner brow and a lifted tail.
    push(0.046, 1.549, (0, -0.5 * mm, 1.4 * mm), 0.012)
    push(0.016, 1.546, (0, -0.8 * mm, -0.9 * mm), 0.010)
    # Eyelids: open the eye a little (upper lid up, lower lid down), kept on the eyeball's sphere below.
    for sx in (1, -1):
        e = np.array([sx * EYE[0], EYE[1], EYE[2]])
        d = co - e
        near = np.exp(-((d[:, 0] / 0.011) ** 2 + (d[:, 1] / 0.012) ** 2) / 2) * (d[:, 1] < 0.004)
        up = near * np.exp(-(((d[:, 2] - 0.0045) / 0.0035) ** 2) / 2) * (-0.7 * mm)
        dn = near * np.exp(-(((d[:, 2] + 0.0050) / 0.0030) ** 2) / 2) * (0.3 * mm)
        out[:, 2] += up - dn
    # Ears closer to the head.
    for sx in (1, -1):
        w = L.gauss(co, (sx * 0.094, 0.022, 1.52), 0.016)[:, None]
        out[:] += w * np.array([-sx * 3.0 * mm, -1.0 * mm, 0])
    # The asymmetry every real face has.
    push(0.0, 1.502, (0.5 * mm, 0, 0), 0.012, mirror=False)
    push(0.0255, 1.466, (0, 0, 0.5 * mm), 0.010, mirror=False)
    push(-0.046, 1.549, (0, 0, 0.6 * mm), 0.012, mirror=False)

    # Build: an athletic frame. Deltoids, trapezius and a firmer neck; forearms a touch fuller.
    def bulge(c, sigma, amount):
        for sx in (1, -1):
            cc = np.array([sx * c[0], c[1], c[2]])
            w = L.gauss(co, cc, sigma)
            d = co - cc
            d /= np.linalg.norm(d, axis=1)[:, None] + 1e-9
            out[:] += (w * amount)[:, None] * d

    bulge((0.185, 0.01, 1.385), 0.045, 4.0 * mm)
    bulge((0.085, 0.03, 1.43), 0.040, 2.5 * mm)
    bulge((0.30, 0.01, 1.20), 0.05, 2.0 * mm)
    return out * L.SCALE


PARTS = {"head": 0, "mouth": 1, "torso": 2, "arm": 3, "hand": 4, "leg": 5, "foot": 6}
TILE_PART = {(0, 0): 0, (0, 2): 0, (1, 0): 1, (1, 2): 1, (0, 1): 2, (0, 3): 2, (1, 1): 2, (1, 3): 2, (2, 1): 2,
             (2, 3): 2, (3, 0): 3, (3, 2): 3, (2, 0): 4, (2, 2): 4, (5, 0): 5, (5, 2): 5, (6, 0): 5, (6, 2): 5,
             (7, 0): 5, (7, 2): 5, (8, 0): 5, (8, 2): 5, (4, 0): 6, (4, 2): 6}
TOP_SKIN_Z = 1.25  # torso skin is kept above this height; the tank top hides the rest


def tag_parts(mesh):
    """Name every face's body part from the UDIM tile the base mesh put it on."""
    uv = mesh.uv_layers[0].data
    part = []
    for p in mesh.polygons:
        u = sum(uv[i].uv[0] for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv[1] for i in p.loop_indices) / p.loop_total
        t = (int(u), int(v))
        part.append(TILE_PART[t])
    a = mesh.attributes.new("part", "INT", "FACE")
    a.data.foreach_set("value", part)
    return part


def pack_uvs(obj):
    """One island scale per set, then pack each material's faces into its own 0..1 square."""
    L.select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    for slot in range(len(obj.material_slots)):
        bpy.ops.mesh.select_all(action="DESELECT")
        obj.active_material_index = slot
        bpy.ops.object.material_slot_select()
        bpy.ops.uv.average_islands_scale()
        bpy.ops.uv.pack_islands(rotate=True, margin=0.006, udim_source="CLOSEST_UDIM", shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    # The packer lands each set on the UDIM tile nearest to where its islands were: bring it home to 0..1.
    mesh = obj.data
    uv = np.empty(len(mesh.loops) * 2, dtype=np.float32)
    mesh.uv_layers[0].data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    slot = np.empty(len(mesh.polygons), dtype=np.int32)
    mesh.polygons.foreach_get("material_index", slot)
    loop_slot = np.repeat(slot, [p.loop_total for p in mesh.polygons])
    for k in range(len(obj.material_slots)):
        sel = loop_slot == k
        uv[sel] -= np.floor(uv[sel].mean(0))
        assert uv[sel].min() >= 0 and uv[sel].max() <= 1, "a UV set is not inside 0..1"
    mesh.uv_layers[0].data.foreach_set("uv", uv.ravel())


def level_copy(src, name, level):
    o = src.copy()
    o.data = src.data.copy()
    o.name = o.data.name = name
    L.link(o)
    L.select_only(o)
    o.modifiers[0].levels = level
    bpy.ops.object.modifier_apply(modifier=o.modifiers[0].name)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def main():
    L.reset()
    with bpy.data.libraries.load(A.base) as (src, dst):
        dst.objects = [n for n in src.objects if n == BASE_OBJ]
    base = dst.objects[0]
    L.link(base)
    base.location = (0, 0, 0)
    base.name = base.data.name = "body_mr"
    mesh = base.data
    part = np.array(tag_parts(mesh))
    co = L.co_get(mesh)
    L.co_set(mesh, deform(co, co))
    full = level_copy(base, "body_full", 1)
    full.hide_render = True

    # Drop the skin under the top, the trousers and the boots, cage face by cage face.
    co = L.co_get(mesh)
    hidden = []
    for p in mesh.polygons:
        k = part[p.index]
        if k in (5, 6) or (k == 2 and max(co[v][2] for v in p.vertices) < TOP_SKIN_Z):
            hidden.append(p.index)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in hidden], context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.clear()
    for n in ("skin_head", "skin_body"):
        mesh.materials.append(bpy.data.materials.new(n))
    pv = np.empty(len(mesh.polygons), dtype=np.int32)
    mesh.attributes["part"].data.foreach_get("value", pv)
    mesh.polygons.foreach_set("material_index", (pv > 1).astype(np.int32))
    pack_uvs(base)

    for name, level in (("mid", 1), ("high", 3)):
        o = level_copy(base, name, level)
        zs = L.co_get(o.data)[:, 2]
        print("BODY", name, "verts", len(o.data.vertices), "tris", L.tri_count(o), "top", round(zs.max(), 4))
    zs = L.co_get(full.data)[:, 2]
    print("BODY full tris", L.tri_count(full), "height", round(zs.max() - zs.min(), 4))
    eye = np.array(EYE) * L.SCALE
    bpy.context.scene["eye_center"] = [float(v) for v in eye]
    bpy.context.scene["eye_radius"] = 0.012 * L.SCALE
    L.save_stage(A.work, "s01")


main()
