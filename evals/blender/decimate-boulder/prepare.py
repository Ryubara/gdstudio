"""Input of the decimate-boulder eval: boulder_high.glb, a sculpted-looking boulder of 20,480 triangles."""

import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1 :]
out = Path(argv[argv.index("--dir") + 1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=6, radius=1.0)
noise.seed_set(774)
for v in bm.verts:
    d = v.co.normalized()
    bump = 0.22 * noise.fractal(d * 1.6, 0.6, 2.0, 4) + 0.05 * noise.noise(d * 7.0)
    v.co = d * (1.0 + bump)
    v.co.x *= 0.8
    v.co.y *= 0.6
    v.co.z *= 0.55
    v.co.z = max(v.co.z, -0.3)  # a flat bottom it sits on
low = min(v.co.z for v in bm.verts)
for v in bm.verts:
    v.co.z -= low
mesh = bpy.data.meshes.new("boulder_high")
bm.to_mesh(mesh)
bm.free()
for poly in mesh.polygons:
    poly.use_smooth = True  # a sculpt is smooth-shaded: glTF keeps its vertices shared
mat = bpy.data.materials.new("rock")
mat.diffuse_color = (0.42, 0.4, 0.37, 1.0)
mesh.materials.append(mat)
obj = bpy.data.objects.new("boulder_high", mesh)
bpy.context.scene.collection.objects.link(obj)
bpy.ops.export_scene.gltf(filepath=str(out / "boulder_high.glb"), export_format="GLB")
