"""Stage 8: export for Godot. Writes `heroine.glb` (the skinned meshes on the rig, material slots by name, no
embedded textures: Godot's materials are built by the test project from the texture sets), copies the texture
sets beside it at the sizes Godot gets (the skin's normal maps keep 16 bits a channel), and reads the file back
to measure it. Both hairstyles are in the file; the budget counts one.

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


def resized16(src, dst, size):
    """A normal map keeps its 16 bits a channel: Blender reads the file as float, a 2 by 2 mean halves it."""
    img = bpy.data.images.load(src, check_existing=False)
    n = img.size[0]
    px = np.empty(n * n * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(n, n, 4)[..., :3]
    while n > size:
        px = px.reshape(n // 2, 2, n // 2, 2, 3).mean((1, 3))
        n //= 2
    L.write_png16(dst, px)
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
        if name.endswith("_normal.png") and key in ("head", "body"):
            resized16(f"{tex}/{name}", f"{out}/{name}", size)
        else:
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
    # She wears one hairstyle at a time: the budget counts the heavier one.
    hair = {k: v for k, v in back.items() if k.startswith("hair_")}
    worn = sum(v for k, v in back.items() if k not in hair) + max(hair.values())
    total = sum(back.values())
    print("EXPORT file MB", round(os.path.getsize(path) / 1e6, 1), "bones", len(arm.data.bones), "triangles in the file", total,
          "worn at once", worn, "budget", BUDGET)
    for name in sorted(back):
        print("EXPORT mesh", name, back[name], "built", built.get(name))
    assert total == sum(built.values()), "the file read back does not have the triangles that were built"
    assert worn <= BUDGET, f"{worn} triangles is over the budget of {BUDGET}"
    assert len(arm.data.bones) == 84, f"{len(arm.data.bones)} bones in the file"
    with open(f"{out}/measure.json", "w") as f:
        json.dump({"triangles": worn, "triangles_in_file": total, "meshes": back, "bones": len(arm.data.bones)}, f, indent=1)
    print("EXPORTED", path)


main()
