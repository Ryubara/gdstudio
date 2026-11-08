"""Build the template's pistol and export it to glTF (kit #834).

GDStudio's own model: Deadnight's service pistol (`tools/blender/weapon_specs/service_pistol.py` with
`build_weapons.py` and `weaponlib.py` in the Deadnight repository, MIT), copied here whole so the template can rebuild
it without Deadnight. A generic 1911-type pistol with no maker's marks, drawn at the real 0.21 m with cross-sections
about 1.5 to 2 times real (the chunky read of the Toon Shooter kit). What changed from Deadnight's build:

- the origin is the grip (the centre of the handle where the middle finger wraps), not the frame behind the trigger;
- one file, no far level and no ammunition model (Godot's importer makes the mesh's levels of detail);
- the build fails before it exports on the budget, the material count, the nodes and the muzzle's place.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P <this file> -- [--out <folder>] [--scale 1.0] [--chunk 1 1 1]

Axes are the kit's weapon axes (kit `docs/tools/blender/weapons.md#axes-origin-and-the-hold`): 1 unit = 1 m, up +Z,
the muzzle along -X, thin across Y; in Godot the muzzle is -X, up +Y and the gun's left +Z. The file holds:

- `Pistol`: the frame, grip and hammer (the root, origin at the grip);
- `Slide`: runs back along +X at the shot, origin at its rear; `Magazine`: drops along the grip, origin at its foot;
- `Muzzle`: the barrel's open end, -Z out of the barrel in Godot; `Eject`: the ejection port on the right;
- `Grip`: the right hand's handle at the origin, +Y up the handle in Godot and -Z along the barrel;
  `Trigger`: the trigger's front face, -Z the press (backward).
"""

import argparse
import itertools
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

NAME = "pistol"
BUDGET = 1500  # kit docs/tools/blender/optimisation.md#budgets: a held or world weapon
BEVEL = 0.017
ROUGHNESS = 0.415
METALLIC = 0.4

# Deadnight's weapon palette (the Toon Shooter kit's weapon colours, sRGB), one 8 px swatch each in a 4 x 4 grid.
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
    `weaponlib.Builder`, the near level's primitives that the pistol uses)."""

    def __init__(self, name, material, chunk):
        self.name, self.material, self.chunk = name, material, chunk
        self.parts = []

    def _finish(self, bm, colour, bevel):
        bmesh.ops.scale(bm, vec=self.chunk, verts=bm.verts)
        me = bpy.data.meshes.new(f"{self.name}_part")
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(o)
        if bevel:
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

    # `detail` marks a small part that Deadnight's far level leaves out; this build makes the near level only.

    def box(self, center, size, colour, bevel=BEVEL, rot=None, detail=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        m = Matrix.Translation(center)
        if rot:
            m = m @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X")
        m = m @ Matrix.Diagonal((*size, 1))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        return self._finish(bm, colour, bevel)

    def cyl(self, p0, p1, radius, colour, segs=12, bevel=BEVEL, detail=None):
        p0, p1 = Vector(p0), Vector(p1)
        axis = p1 - p0
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=radius, radius2=radius, depth=axis.length)
        rot = Vector((0, 0, 1)).rotation_difference(axis.normalized()).to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation((p0 + p1) / 2) @ rot, verts=bm.verts)
        return self._finish(bm, colour, bevel)

    def prism(self, profile, y0, y1, colour, bevel=BEVEL, detail=None):
        """A side profile [(x, z), ...] (counter-clockwise seen from -Y) extruded from y0 to y1."""
        bm = bmesh.new()
        vs = [bm.verts.new((x, y0, z)) for x, z in profile]
        face = bm.faces.new(vs)
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        moved = [g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, y1 - y0, 0), verts=moved)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return self._finish(bm, colour, bevel)

    def bar(self, points, width, thick, colour, y=0.0, bevel=0.0, detail=None):
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


# ---- Deadnight's service pistol (weapon_specs/service_pistol.py, Deadnight #797), in drawing units -------------------

BORE = 0.045  # the barrel's axis height
D, K, G, W, Y = "DarkGrey", "Black", "Grey", "Wood", "Yellow"


def body(b):
    """The frame, the grip and everything else that stays when the slide runs back and the magazine drops."""
    b.box((-0.085, 0, 0.021), (0.13, 0.034, 0.02), D, bevel=0.005)  # dust cover
    b.box((0.0, 0, 0.016), (0.09, 0.036, 0.034), D, bevel=0.005)  # frame over the trigger and the grip's top
    b.box((-0.025, 0.019, 0.021), (0.03, 0.006, 0.01), K, bevel=0, detail=True)  # slide stop lever (right)
    b.cyl((-0.06, -0.02, 0.021), (-0.06, 0.02, 0.021), 0.005, K, segs=6, bevel=0, detail=True)  # its pin
    # Grip: the DarkGrey frame raked back 18 degrees, Wood panels proud on both sides.
    b.prism([(-0.012, 0.004), (0.04, 0.004), (0.074, -0.1), (0.022, -0.1)], -0.017, 0.017, D, bevel=0.005)
    b.prism([(-0.004, -0.008), (0.034, -0.008), (0.062, -0.09), (0.024, -0.09)], -0.021, 0.021, W, bevel=0.004)
    for y in (-0.022, 0.022):
        for x, z in ((0.012, -0.02), (0.04, -0.08)):
            b.cyl((x, y * 0.98, z), (x, y * 1.12, z), 0.005, K, segs=4, bevel=0, detail=True)  # grip screws
    # The grip safety's tang over the web of the hand and the round hammer spur above it.
    b.bar([(0.03, 0.02), (0.058, 0.03), (0.068, 0.026)], 0.03, 0.012, D)
    b.cyl((0.052, -0.008, 0.07), (0.052, 0.008, 0.07), 0.013, K, segs=10, bevel=0)  # hammer spur
    b.bar([(0.038, 0.05), (0.05, 0.068)], 0.014, 0.012, K)  # hammer neck
    # Trigger guard (round, deep enough for a chunky finger) and the trigger.
    b.bar([(-0.058, 0.01), (-0.06, -0.022), (-0.044, -0.04), (-0.014, -0.04), (0.0, -0.016)], 0.014, 0.008, D)
    b.bar([(-0.026, 0.004), (-0.028, -0.014), (-0.022, -0.026)], 0.009, 0.008, K)


def slide(b):
    """The long Black slide with the sights, the ejection port on the right, the rear serrations and the bushing."""
    b.box((-0.065, 0, 0.0525), (0.21, 0.04, 0.045), K, bevel=0.006)
    b.cyl((-0.17, 0, BORE), (-0.173, 0, BORE), 0.013, D, segs=10, bevel=0)  # barrel bushing
    b.cyl((-0.173, 0, BORE), (-0.175, 0, BORE), 0.008, K, segs=8, bevel=0, detail=True)  # the bore
    b.box((-0.155, 0, 0.08), (0.012, 0.008, 0.01), K, bevel=0)  # front sight
    b.box((0.026, 0, 0.08), (0.012, 0.03, 0.012), K, bevel=0)  # rear sight
    b.box((-0.06, 0.0205, 0.064), (0.044, 0.004, 0.016), G, bevel=0, detail=True)  # ejection port
    for i in range(3):
        x = 0.004 + 0.01 * i
        for y in (-0.0205, 0.0205):
            b.box((x, y, 0.052), (0.004, 0.003, 0.032), D, bevel=0, detail=True)  # rear serrations


def magazine(b):
    """The magazine in the grip, raked with it: hidden but for the floor plate; drops out along the grip."""
    b.prism([(0.0, -0.002), (0.028, -0.002), (0.058, -0.096), (0.03, -0.096)], -0.013, 0.013, D, bevel=0.003)
    b.box((0.048, 0, -0.104), (0.05, 0.03, 0.012), K, bevel=0)  # floor plate
    b.cyl((0.0, 0, 0.0), (0.02, 0, 0.0), 0.007, Y, segs=6, bevel=0, detail=True)  # the top round


NODES = {
    "Slide": (slide, (0.04, 0.0, 0.0525)),  # the slide's rear: it runs back along +X
    "Magazine": (magazine, (0.035, 0.0, -0.10)),  # the magazine well's foot: it drops along the grip
}
MUZZLE = (-0.17, 0.0, BORE)  # the slide's front face on the bore (the bushing stands 3-5 mm proud)
EJECT = (-0.06, 0.02, 0.065)
GRIP = ((0.032, 0.0, -0.058), (-0.31, 0.0, 0.95), (-1.0, 0.0, 0.0))  # origin, up the handle, front (the fingers)
TRIGGER = (-0.03, 0.0, -0.012)


# ---- the template's file -----------------------------------------------------------------------------------------


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


def build(scale, chunk):
    img = palette_image()
    mat = atlas_material(img)
    k = Vector(chunk)
    origin = Vector(GRIP[0]) * k  # every point moves by -origin, then scales: the grip is the origin
    place = Matrix.Diagonal((scale, scale, scale, 1)) @ Matrix.Translation(-origin)

    b = Builder(NAME, mat, chunk)
    body(b)
    root = b.join("Pistol")
    root.data.transform(place)
    nodes = []
    for node, (part, pivot) in NODES.items():
        nb = Builder(node, mat, chunk)
        part(nb)
        o = nb.join(node)
        at = place @ (Vector(pivot) * k)
        o.data.transform(Matrix.Translation(-at) @ place)
        o.parent = root
        o.location = at
        nodes.append(o)
    turn = Matrix.Rotation(math.pi / 2, 4, "Z")  # an empty's +Y (Godot -Z) along -X, out of the barrel
    sockets = [
        empty(root, "Muzzle", place @ (Vector(MUZZLE) * k), turn),
        empty(root, "Eject", place @ (Vector(EJECT) * k)),
        empty(root, "Grip", Vector(), frame(Vector(GRIP[1]) * k, Vector(GRIP[2]) * k)),
        empty(root, "Trigger", place @ (Vector(TRIGGER) * k), frame((0, 0, 1), (1, 0, 0))),
    ]
    return root, nodes, sockets


def check(root, nodes, sockets):
    """Fail before the export on what this model can get wrong."""
    bpy.context.view_layer.update()  # the nodes' matrix_world follows their new parent and location only after this
    count = tris(root) + sum(tris(o) for o in nodes)
    errors = []
    if count > BUDGET:
        errors.append(f"{count} triangles, over the budget of {BUDGET}")
    mats = {m.name for o in (root, *nodes) for m in o.data.materials}
    if mats != {"Weapons"}:
        errors.append(f"materials {sorted(mats)}, not the one palette material")
    pts = [root.matrix_world @ v.co for v in root.data.vertices]
    for o in nodes:
        pts += [o.matrix_world @ v.co for v in o.data.vertices]
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    muzzle = next(s for s in sockets if s.name == "Muzzle").location
    if abs(muzzle.x - mn.x) > 0.01 or abs(muzzle.y) > 1e-6:
        errors.append(f"Muzzle at x {muzzle.x:.4f}, not within 1 cm of the front face {mn.x:.4f}")
    grip = next(s for s in sockets if s.name == "Grip")
    if grip.location.length > 1e-6:
        errors.append("Grip is not at the origin")
    if not (mn.x < 0 < mx.x and mn.z < 0 < mx.z):
        errors.append("the origin is outside the model")
    if errors:
        raise SystemExit("pistol build failed: " + "; ".join(errors))
    return count, mn, mx


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


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--scale", type=float, default=1.0, help="uniform size after the drawing (1 = real length)")
    ap.add_argument(
        "--chunk", type=float, nargs=3, default=(1.0, 1.0, 1.0), help="the drawing's x y z, before chamfers"
    )
    ap.add_argument("--name", default=NAME, help="the file's name, without .glb")
    args = ap.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    root, nodes, sockets = build(args.scale, tuple(args.chunk))
    count, mn, mx = check(root, nodes, sockets)
    args.out.mkdir(parents=True, exist_ok=True)
    name = args.name
    path = args.out / f"{name}.glb"
    export(root, path)
    size = [round(mx[i] - mn[i], 4) for i in range(3)]
    at = {s.name: [round(c, 4) for c in s.location] for s in sockets}
    at.update({o.name: [round(c, 4) for c in o.location] for o in nodes})
    print(f"PISTOL {name}: {count} tris, size {size} (x y z, m), min {[round(c, 4) for c in mn]}, nodes {at}")
    print(f"PISTOL file {path}")


main()
