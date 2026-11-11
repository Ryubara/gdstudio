"""Stage 8: export for Godot. Writes `heroine.glb` (the skinned meshes on the rig, material slots by name, no
embedded textures: Godot's materials are built by the test project from the texture sets), copies the texture
sets beside it with the two maps Godot wants packed its own way, and reads the file back to measure it.

    blender -b -P s08_export.py -- --work <dir> --out <godot asset folder>

Fails before it reports if the read-back file is over the triangle budget or lost bones.
"""

import json
import os
import shutil
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rc_lib as L  # noqa: E402

A = L.args()
BUDGET = 130_000  # triangles, hero character at close range (kit docs: realistic-characters.md#budgets)
GODOT_SIZE = {"head": 4096, "body": 2048, "outfit": 4096, "gear": 2048, "hair": 2048, "eye": 1024}


def resized(src, dst, size):
    img = bpy.data.images.load(src, check_existing=False)
    if img.size[0] > size:
        img.scale(size, size)
    img.filepath_raw = dst
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def coat_map(src, dst, size):
    """Godot's clearcoat texture: strength in red, glossiness in green. Ours: the sweat film from the mask's green."""
    img = bpy.data.images.load(src, check_existing=False)
    if img.size[0] > size:
        img.scale(size, size)
    n = img.size[0]
    px = np.empty(n * n * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    out = np.ones_like(px)
    out[:, 0] = px[:, 1]
    out[:, 1] = 0.86
    out[:, 2] = 0.0
    img.pixels.foreach_set(out.ravel())
    img.filepath_raw = dst
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def main():
    L.open_stage(A.work, "s07")
    out = A.out.replace("\\", "/").rstrip("/")
    os.makedirs(out, exist_ok=True)
    rig = bpy.data.objects["rig"]
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == rig and o.name != "body_full"]
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    built = {}
    for o in meshes + [rig]:
        o.hide_set(False)
        o.select_set(True)
        if o.type == "MESH":
            built[o.name] = L.tri_count(o)
    bpy.context.view_layer.objects.active = rig
    path = f"{out}/heroine.glb"
    if os.path.exists(path):
        os.remove(path)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False,
                              export_materials="PLACEHOLDER", export_animations=False, export_skins=True,
                              export_def_bones=False, export_leaf_bone=False, export_tangents=True,
                              export_vertex_color="ACTIVE", export_all_vertex_colors=True, export_normals=True)
    tex = f"{A.work}/tex"
    for name in sorted(os.listdir(tex)):
        if not name.endswith(".png"):
            continue
        key = name.split("_")[0]
        size = GODOT_SIZE.get(key, 4096)
        if name.endswith("_mask.png") and key in ("head", "body"):
            coat_map(f"{tex}/{name}", f"{out}/{key}_coat.png", size)
        resized(f"{tex}/{name}", f"{out}/{name}", size)
    shutil.copy(f"{A.work}/rig.json", f"{out}/rig.json")

    # Read the file back: what Godot gets, not the scene that was built.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    back = {}
    for o in bpy.data.objects:
        if o.type == "MESH" and any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers):
            back[o.name] = L.tri_count(o)
    total = sum(back.values())
    print("EXPORT file MB", round(os.path.getsize(path) / 1e6, 1), "bones", len(arm.data.bones), "triangles", total, "budget", BUDGET)
    for name in sorted(back):
        print("EXPORT mesh", name, back[name], "built", built.get(name))
    assert total == sum(built.values()), "the file read back does not have the triangles that were built"
    assert total <= BUDGET, f"{total} triangles is over the budget of {BUDGET}"
    assert len(arm.data.bones) == 84, f"{len(arm.data.bones)} bones in the file"
    with open(f"{out}/measure.json", "w") as f:
        json.dump({"triangles": total, "meshes": back, "bones": len(arm.data.bones)}, f, indent=1)
    print("EXPORTED", path)


main()
