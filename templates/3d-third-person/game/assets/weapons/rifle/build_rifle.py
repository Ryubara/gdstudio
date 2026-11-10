"""Build the template's assault rifle and its far level, and export both to glTF (kit #886).

GDStudio's own model: Deadnight's M4A1-type carbine (`tools/blender/weapon_specs/m4a1.py` with `build_weapons.py` and
`weaponlib.py` in the Deadnight repository, Deadnight #795, MIT), copied here whole so the template can rebuild it
without Deadnight. A generic carbine with a carry handle and no maker's marks, drawn at the real 0.80 m with
cross-sections about 1.5 to 2 times real (the chunky read of the Toon Shooter kit, as the template's pistol). What
changed from Deadnight's build:

- the origin is the grip (the centre of the handle where the middle finger wraps), as the template's pistol;
- no ammunition model (the template's reload has no left-hand prop yet);
- the build fails before it exports on the budgets, the material count, the nodes, the sockets and the muzzle's place,
  and on a far level whose sockets are not where the near level's are.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P <this file> -- [--out <folder>] [--scale 1.0]

Axes are the kit's weapon axes (kit `docs/tools/blender/weapons.md#axes-origin-and-the-hold`): 1 unit = 1 m, up +Z,
the muzzle along -X, thin across Y; in Godot the muzzle is -X, up +Y and the gun's left +Z. Each file holds:

- `Rifle`: the receivers, barrel, hand guard, carry handle, grip and stock (the root, origin at the grip);
- `Magazine`: drops down out of the well, origin at the well's mouth; `Bolt`: the charging handle, runs back along
  +X, origin at its root;
- `Muzzle`: the flash hider's open end, -Z out of the barrel in Godot; `Eject`: the ejection port on the right;
- `Grip`: the right hand's handle at the origin, +Y up the handle in Godot and -Z along the barrel;
  `Trigger`: the trigger's front face, -Z the press (backward);
- `Support`: the left hand's handle, under the hand guard's rear: +Y toward the muzzle in Godot, -Z the way the
  left hand's fingers point (round the guard to the gun's right, and up);
- `Butt`: the butt pad's rear face, where the stock meets the shoulder (the weapon's own axes).

`rifle.glb` is the near level (held and close up), `rifle_far.glb` the far level (the same parts with no chamfers,
half the sides on round parts and the small detail parts left out), with every node and socket at the same place.
"""

import argparse
import itertools
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

NAME = "rifle"
BUDGETS = {"near": 1500, "far": 500}  # kit docs/tools/blender/optimisation.md#budgets: a held or world weapon
BEVEL = 0.017
ROUGHNESS = 0.415
METALLIC = 0.4

# Deadnight's weapon palette (the Toon Shooter kit's weapon colours, sRGB), one 8 px swatch each in a 4 x 4 grid; the
# same cells as the template's pistol, so both read one palette.
PALETTE = {
    "Grey": "#818491",
    "DarkGrey": "#414141",
    "Black": "#252525",
    "Wood": "#95703d",
    "Grey2": "#5f5f5f",
    "Red": "#8c3735",
    "DarkWood": "#6b4f2c",
    "Green": "#496321",
    "Yellow": "#d1ab46",
    "Blue": "#34609e",
    "Glow": "#7fe3ff",
    "Frost": "#c6dce4",
    "Tan": "#9c8562",
}
GRID = 4
SWATCH_PX = 8


def hex_rgb(h):
    return tuple(int(h[i : i + 2], 16) / 255 for i in (1, 3, 5))


def swatch_uv(colour):
    """UV of the centre of a palette swatch (row 0 at the top of the image)."""
    i = list(PALETTE).index(colour)
    return Vector(((i % GRID + 0.5) / GRID, 1 - (i // GRID + 0.5) / GRID))


def palette_image():
    """The palette atlas as a packed Blender image (the glb embeds it; Godot extracts it beside the glb)."""
    size = GRID * SWATCH_PX
    img = bpy.data.images.new("weapons_palette", size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for i, h in enumerate(PALETTE.values()):
        r, g, b = hex_rgb(h)
        col, row = i % GRID, i // GRID
        for y in range(SWATCH_PX):
            for x in range(SWATCH_PX):
                py = size - 1 - (row * SWATCH_PX + y)  # Blender's pixel rows start at the bottom
                k = (py * size + col * SWATCH_PX + x) * 4
                px[k : k + 4] = [r, g, b, 1.0]
    img.pixels = px
    img.pack()
    return img


def atlas_material(img):
    """The one weapon material: the palette, nearest-filtered, roughness 0.415, metallic 0.4, backface culling."""
    m = bpy.data.materials.new("Weapons")
    m.use_backface_culling = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = ROUGHNESS
    bsdf.inputs["Metallic"].default_value = METALLIC
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.nodes.active = tex
    return m


class Builder:
    """Collects the parts of one model as separate closed objects, then joins them into one mesh (Deadnight's
    `weaponlib.Builder`, the primitives the carbine uses). `lod="far"` drops chamfers and `detail` parts and halves
    the sides of round parts."""

    def __init__(self, name, lod, material, chunk=(1.0, 1.0, 1.0)):
        self.name, self.material, self.chunk = name, material, chunk
        self.near = lod == "near"
        self.parts = []

    def _finish(self, bm, colour, bevel, detail):
        if detail and not self.near:
            bm.free()
            return None
        bmesh.ops.scale(bm, vec=self.chunk, verts=bm.verts)
        me = bpy.data.meshes.new(f"{self.name}_part")
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(o)
        if bevel and self.near:
            mod = o.modifiers.new("chamfer", "BEVEL")
            mod.width = bevel
            mod.segments = 1
            mod.limit_method = "ANGLE"
            mod.angle_limit = math.radians(40)
            mod.use_clamp_overlap = True
            dg = bpy.context.evaluated_depsgraph_get()
            new = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
            o.modifiers.clear()
            o.data = new
        uv = o.data.uv_layers.new(name="UVMap")
        s = swatch_uv(colour)
        for loop in uv.data:
            loop.uv = s
        self.parts.append(o)
        return o

    def box(self, center, size, colour, bevel=BEVEL, rot=None, detail=False):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        m = Matrix.Translation(center)
        if rot:
            m = m @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
        m = m @ Matrix.Diagonal((*size, 1))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        return self._finish(bm, colour, bevel, detail)

    def cyl(self, p0, p1, radius, colour, segs=12, bevel=BEVEL, detail=False):
        if not self.near:
            segs = max(6, segs // 2)
        p0, p1 = Vector(p0), Vector(p1)
        axis = p1 - p0
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius, depth=axis.length)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=bm.verts)
        return self._finish(bm, colour, bevel, detail)

    def prism(self, profile, y0, y1, colour, bevel=BEVEL, detail=False):
        """A side profile [(x, z), ...] (counter-clockwise seen from -Y) extruded from y0 to y1."""
        bm = bmesh.new()
        vs = [bm.verts.new((x, y0, z)) for x, z in profile]
        face = bm.faces.new(vs)
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, y1 - y0, 0), verts=moved)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self._finish(bm, colour, bevel, detail)

    def bar(self, points, width, thick, colour, y=0.0, bevel=0.0, detail=False):
        """A bent bar through side-view points [(x, z), ...]: one box per segment, overlapping at the joints."""
        for (x0, z0), (x1, z1) in itertools.pairwise(points):
            d = Vector((x1 - x0, 0, z1 - z0))
            ang = math.atan2(d.z, d.x)
            self.box(
                ((x0 + x1) / 2, y, (z0 + z1) / 2),
                (d.length + thick * 0.9, width, thick),
                colour,
                bevel=bevel,
                rot=(0, -ang, 0),
                detail=detail,
            )

    def join(self, name):
        me = bpy.data.meshes.new(name)
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        bm = bmesh.new()
        for p in self.parts:
            bm.from_mesh(p.data)
        bm.to_mesh(me)
        bm.free()
        for p in self.parts:
            bpy.data.objects.remove(p)
        me.materials.append(self.material)
        for poly in me.polygons:
            poly.use_smooth = False
        return o


# ---- Deadnight's M4A1 (weapon_specs/m4a1.py, Deadnight #795), in drawing units ------------------------------------

BORE = 0.045
D, K, T = "DarkGrey", "Black", "Tan"


def body(b):
    """Everything that stays put in the reload."""
    # Barrel and the birdcage flash hider with its slots.
    b.cyl((-0.13, 0, BORE), (-0.42, 0, BORE), 0.016, D, segs=10, bevel=0)
    b.cyl((-0.42, 0, BORE), (-0.47, 0, BORE), 0.02, D, segs=10, bevel=0)
    b.cyl((-0.47, 0, BORE), (-0.473, 0, BORE), 0.011, K, segs=8, bevel=0, detail=True)  # bore
    for a in (45, 135, 225, 315):
        r = math.radians(a)
        b.box(
            (-0.447, 0.0185 * math.cos(r), BORE + 0.0185 * math.sin(r)),
            (0.03, 0.006, 0.006),
            K,
            bevel=0,
            rot=(r, 0, 0),
            detail=True,
        )  # the slots
    # The triangle front sight (signature): a collar on the barrel, a frame tapering up to its ears, the post.
    b.box((-0.333, 0, BORE), (0.034, 0.04, 0.044), K, bevel=0)
    b.prism([(-0.358, 0.05), (-0.31, 0.05), (-0.322, 0.122), (-0.346, 0.122)], -0.011, 0.011, K, bevel=0.003)
    b.box((-0.334, 0, 0.128), (0.026, 0.026, 0.014), K, bevel=0)  # the ears
    b.box((-0.334, 0, 0.13), (0.006, 0.006, 0.02), D, bevel=0, detail=True)  # the post
    b.box((-0.345, 0, 0.012), (0.012, 0.012, 0.03), K, bevel=0, detail=True)  # sling swivel
    # The round ribbed Tan hand guard, a Black cap at its front and the delta ring at its rear.
    b.cyl((-0.13, 0, BORE), (-0.31, 0, BORE), 0.04, T, segs=12, bevel=0.008)
    b.cyl((-0.31, 0, BORE), (-0.322, 0, BORE), 0.034, K, segs=12, bevel=0)  # front cap
    b.cyl((-0.11, 0, BORE), (-0.135, 0, BORE), 0.046, K, segs=12, bevel=0)  # delta ring
    for x in (-0.17, -0.22, -0.27):
        b.cyl((x - 0.004, 0, BORE), (x + 0.004, 0, BORE), 0.042, T, segs=12, bevel=0, detail=True)  # ribs
    # The upper receiver, Black, a big flat side; the dust cover and the forward assist on the right.
    b.box((-0.03, 0, 0.058), (0.2, 0.064, 0.064), K, bevel=0.012)  # x -0.13..0.07, z 0.026..0.09
    b.box((-0.03, 0.0335, 0.05), (0.07, 0.004, 0.024), D, bevel=0, detail=True)  # dust cover
    b.cyl((0.04, 0.03, 0.068), (0.06, 0.042, 0.068), 0.011, D, segs=8, bevel=0, detail=True)  # forward assist
    # The carry handle over it (signature), its rear sight block at the back.
    b.box((-0.03, 0, 0.13), (0.15, 0.03, 0.022), K, bevel=0.006)  # top bar x -0.105..0.045
    b.box((-0.095, 0, 0.105), (0.024, 0.03, 0.04), K, bevel=0)  # front leg
    b.box((0.035, 0, 0.115), (0.04, 0.034, 0.06), K, bevel=0)  # rear block
    b.box((0.04, 0, 0.152), (0.024, 0.028, 0.016), D, bevel=0)  # the rear sight's aperture
    b.box((0.04, 0, 0.152), (0.026, 0.008, 0.008), K, bevel=0, detail=True)  # its hole
    b.cyl((0.035, -0.024, 0.118), (0.035, 0.024, 0.118), 0.012, D, segs=8, bevel=0, detail=True)  # windage knob
    # The lower receiver: the trigger group, the magazine well (flared at its mouth), the buffer tube's root.
    b.box((-0.02, 0, 0.0035), (0.16, 0.06, 0.047), K, bevel=0.008)  # x -0.10..0.06, z -0.02..0.027
    b.box((-0.085, 0, -0.04), (0.08, 0.05, 0.05), K, bevel=0)  # the well, x -0.125..-0.045
    b.box((-0.06, 0.027, -0.03), (0.016, 0.006, 0.016), D, bevel=0, detail=True)  # magazine release, on the well
    for y in (-0.031, 0.031):
        b.box((0.035, y, 0.008), (0.02, 0.004, 0.012), D, bevel=0, detail=True)  # selector
    # Pistol grip (Tan), guard and trigger.
    b.prism(
        [(-0.006, -0.02), (0.04, -0.02), (0.075, -0.13), (0.072, -0.145), (0.034, -0.145), (0.005, -0.06)],
        -0.024,
        0.024,
        T,
        bevel=0.008,
    )
    b.bar([(-0.036, -0.018), (-0.038, -0.07), (-0.018, -0.087), (0.006, -0.081), (0.012, -0.04)], 0.018, 0.012, K)
    b.bar([(-0.01, -0.02), (-0.014, -0.044), (-0.006, -0.056)], 0.01, 0.01, D)
    # The buffer tube and the Tan stock on it: a flat top, the bottom dropping to the butt; a Black pad. The bottom's
    # front stays high (z 0.02 at x 0.22), clear of the wrist of a shouldered hold.
    b.cyl((0.06, 0, 0.055), (0.25, 0, 0.055), 0.022, K, segs=10, bevel=0)
    b.prism([(0.15, 0.035), (0.22, 0.02), (0.322, -0.06), (0.33, 0.08), (0.15, 0.08)], -0.028, 0.028, T, bevel=0.01)
    b.box((0.336, 0, 0.01), (0.014, 0.062, 0.145), K, bevel=0.004)  # butt pad


def magazine(b):
    """The straight magazine, Tan like the furniture, a slight forward curve at its foot and a Black floor plate. The
    reload's part: out down along its own axis from the well."""
    b.bar([(-0.085, -0.02), (-0.087, -0.11), (-0.099, -0.19)], 0.034, 0.07, T, bevel=0.006)
    b.box((-0.101, 0, -0.2), (0.078, 0.04, 0.012), K, bevel=0, rot=(0, -0.14, 0))  # floor plate


def bolt(b):
    """The charging handle under the carry handle's rear: a T, slides back (+X) 0.06."""
    b.box((0.08, 0, 0.083), (0.03, 0.016, 0.012), D, bevel=0)
    b.box((0.094, 0, 0.083), (0.012, 0.05, 0.014), K, bevel=0)  # the latch bar


NODES = {
    "Magazine": (magazine, (-0.085, 0.0, -0.03)),  # the well's mouth: it drops down out of the well
    "Bolt": (bolt, (0.07, 0.0, 0.083)),  # the handle's root at the receiver's rear
}
MUZZLE = (-0.47, 0.0, BORE)
EJECT = (-0.03, 0.036, 0.05)  # the dust cover
GRIP = ((0.036, 0.0, -0.085), (-0.28, 0.0, 0.96), (-1.0, 0.0, 0.0))  # origin, up the handle, front (the fingers)
TRIGGER = (-0.018, 0.0, -0.038)
SUPPORT = ((-0.25, 0.0, 0.03), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.6))  # the hand guard's rear, held from below
BUTT = (0.343, 0.0, 0.01)  # the butt pad's rear face: where the stock meets the shoulder


# ---- the template's files ----------------------------------------------------------------------------------------


def empty(parent, name, at, rot=None, size=0.03):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = size
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.matrix_basis = Matrix.Translation(at) @ (rot or Matrix.Identity(4))
    return e


def frame(up, front):
    """A rotation whose local +Z is `up` and local +Y is `front` (made square to up)."""
    z = Vector(up).normalized()
    y = Vector(front)
    y = (y - z * y.dot(z)).normalized()
    return Matrix((y.cross(z), y, z)).transposed().to_4x4()


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def build(lod, scale, mat):
    origin = Vector(GRIP[0])  # every point moves by -origin, then scales: the grip is the origin
    place = Matrix.Diagonal((scale, scale, scale, 1)) @ Matrix.Translation(-origin)

    b = Builder(NAME, lod, mat)
    body(b)
    root = b.join("Rifle")
    root.data.transform(place)
    nodes = []
    for node, (part, pivot) in NODES.items():
        nb = Builder(node, lod, mat)
        part(nb)
        o = nb.join(node)
        at = place @ Vector(pivot)
        o.data.transform(Matrix.Translation(-at) @ place)
        o.parent = root
        o.location = at
        nodes.append(o)
    turn = Matrix.Rotation(math.pi / 2, 4, "Z")  # an empty's +Y (Godot -Z) along -X, out of the barrel
    sockets = [
        empty(root, "Muzzle", place @ Vector(MUZZLE), turn),
        empty(root, "Eject", place @ Vector(EJECT)),
        empty(root, "Grip", Vector(), frame(GRIP[1], GRIP[2])),
        empty(root, "Trigger", place @ Vector(TRIGGER), frame((0, 0, 1), (1, 0, 0))),
        empty(root, "Support", place @ Vector(SUPPORT[0]), frame(SUPPORT[1], SUPPORT[2])),
        empty(root, "Butt", place @ Vector(BUTT)),
    ]
    return root, nodes, sockets


def check(lod, root, nodes, sockets):
    """Fail before the export on what this model can get wrong."""
    bpy.context.view_layer.update()  # the nodes' matrix_world follows their new parent and location only after this
    count = tris(root) + sum(tris(o) for o in nodes)
    errors = []
    if count > BUDGETS[lod]:
        errors.append(f"{count} triangles, over the {lod} budget of {BUDGETS[lod]}")
    mats = {m.name for o in (root, *nodes) for m in o.data.materials}
    if mats != {"Weapons"}:
        errors.append(f"materials {sorted(mats)}, not the one palette material")
    if sorted(o.name for o in nodes) != sorted(NODES):
        errors.append(f"nodes {[o.name for o in nodes]}, not {list(NODES)}")
    pts = [root.matrix_world @ v.co for v in root.data.vertices]
    for o in nodes:
        pts += [o.matrix_world @ v.co for v in o.data.vertices]
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    at = {s.name: s.location for s in sockets}
    if abs(at["Muzzle"].x - mn.x) > 0.01 or abs(at["Muzzle"].y) > 1e-6:
        errors.append(f"Muzzle at x {at['Muzzle'].x:.4f}, not within 1 cm of the front face {mn.x:.4f}")
    if at["Grip"].length > 1e-6:
        errors.append("Grip is not at the origin")
    if not at["Support"].x < at["Trigger"].x < 0.0:
        errors.append("Support is not ahead of the trigger, or the trigger not ahead of the grip")
    mag = next(o for o in nodes if o.name == "Magazine")
    if not (at["Support"].x < mag.location.x < 0.0 and mag.location.z < at["Muzzle"].z):
        errors.append("Magazine's pivot is not between the grip and the support, under the bore")
    if abs(at["Butt"].x - mx.x) > 0.01:
        errors.append(f"Butt at x {at['Butt'].x:.4f}, not within 1 cm of the rear face {mx.x:.4f}")
    if not (mn.x < 0 < mx.x and mn.z < 0 < mx.z):
        errors.append("the origin is outside the model")
    if errors:
        raise SystemExit(f"rifle build ({lod}) failed: " + "; ".join(errors))
    return count, mn, mx, {k: v.copy() for k, v in at.items()} | {o.name: o.location.copy() for o in nodes}


def export(root, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in (root, *root.children):
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )


def clear(root):
    for o in (*root.children, root):
        bpy.data.objects.remove(o)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--scale", type=float, default=1.0, help="uniform size after the drawing (1 = real length)")
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    mat = atlas_material(palette_image())
    args.out.mkdir(parents=True, exist_ok=True)
    places = {}
    for lod in ("near", "far"):
        root, nodes, sockets = build(lod, args.scale, mat)
        count, mn, mx, at = check(lod, root, nodes, sockets)
        places[lod] = at
        path = args.out / (f"{NAME}.glb" if lod == "near" else f"{NAME}_far.glb")
        export(root, path)
        size = [round(mx[i] - mn[i], 4) for i in range(3)]
        rounded = {k: [round(c, 4) for c in v] for k, v in at.items()}
        print(f"RIFLE {lod}: {count} tris, size {size} (x y z, m), min {[round(c, 4) for c in mn]}, nodes {rounded}")
        print(f"RIFLE file {path}")
        clear(root)
    moved = [k for k in places["near"] if (places["near"][k] - places["far"][k]).length > 1e-6]
    if moved:
        raise SystemExit(f"rifle build failed: the far level moved {moved}")


main()
