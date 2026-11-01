"""Clean a Quaternius character file and export it as a Godot-ready glTF with all its clips.

    blender -b --factory-startup -P sandbox/rig-sharing/blender/clean_export.py -- <in.glb> <out.glb>

What it does, in order (each step is a finding of the spike, see docs/blender/rig-sharing.md):

1. Import with `bone_heuristic="TEMPERANCE"` (the default moves bone-attached meshes).
2. Delete held items (meshes parented to a hand bone: the 14 kit weapons) and strays (unparented meshes: the 80-tri
   Icosphere), and the `*_end` leaf-bone empties the importer makes (they would become nodes in Godot).
3. Unparent the armature from the `RootNode` empty and delete it, so the armature is the scene root.
4. Apply the armature's 100x object scale, and scale every bone location key by the same factor: applying scale
   rescales the rest pose but not the keys, and the clips would then move the hips by 1/100 of what they should.
5. Pose bones cleared (not pose_position REST: it freezes every exported clip), no active action; drop duplicate clips (the zombie file holds each clip twice, `CharacterArmature|Walk`
   and `Walk`); name every clip without the `CharacterArmature|` prefix.
6. Rename meshes that share a bone's name (Godot would rename the bone).
7. Export glTF binary, one animation per NLA track, no leaf bones, Y up.
"""

import re
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import riglib


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    src, out = Path(argv[0]), Path(argv[1])
    objs = riglib.import_glb(src)
    arm = riglib.armature_of(objs)
    body, held, stray = riglib.split_parts(objs)
    report = {"held": len(held), "held_tris": sum(riglib.tris(o) for o in held), "stray": [o.name for o in stray]}

    # 2. Held items, strays, leaf empties.
    for o in held + stray:
        bpy.data.objects.remove(o)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY" and o.name.endswith("_end")]:
        bpy.data.objects.remove(o)

    # 3. Armature becomes the root.
    root = arm.parent
    mw = arm.matrix_world.copy()
    arm.parent = None
    arm.matrix_world = mw
    if root is not None and root.type == "EMPTY":
        bpy.data.objects.remove(root)

    # 4. Apply the object scale; scale location keys to match.
    factor = arm.scale[0]
    assert all(abs(s - factor) < 1e-4 for s in arm.scale), f"non-uniform armature scale {tuple(arm.scale)}"
    # transform_apply moves meshes parented to a bone (the Soldier's helmet and pads floated far above him):
    # remember their world matrices and put them back after.
    # Pin them at rest (the import leaves a clip active, and the export writes the rest pose).
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    pinned = {c: c.matrix_world.copy() for c in arm.children if c.parent_type == "BONE"}
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True, properties=False)
    bpy.context.view_layer.update()
    for c, mw_c in pinned.items():
        c.matrix_world = mw_c
    arm.data.pose_position = "POSE"
    # The meshes are children of the armature; their own transforms keep them where they were.
    for c in arm.children:
        if c.type == "MESH":
            bpy.ops.object.select_all(action="DESELECT")
            c.select_set(True)
            bpy.context.view_layer.objects.active = c
            if c.parent_type != "BONE":
                bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 5. Clips: dedupe and rename; scale location keys.
    seen = {}
    for a in list(bpy.data.actions):
        name = re.sub(r"^.*\|", "", a.name)
        if name in seen:
            bpy.data.actions.remove(a)
        else:
            seen[name] = a
    for a in seen.values():  # rename only once the duplicates are gone, or Blender makes "Walk.001"
        a.name = "tmp_" + a.name
    for name, a in seen.items():
        a.name = name
    for a in seen.values():
        a.use_fake_user = True
        for fc in riglib.fcurves(a):
            if fc.data_path.endswith(".location"):
                for k in fc.keyframe_points:
                    k.co[1] *= factor
                    k.handle_left[1] *= factor
                    k.handle_right[1] *= factor
    # One NLA track per clip (the importer's tracks point at the duplicates we removed), exported with NLA_TRACKS.
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for name, a in seen.items():
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, int(a.frame_range[0]), a)
        if hasattr(strip, "action_slot") and a.slots:
            strip.action_slot = a.slots[0]
    # Never set arm.data.pose_position = "REST" before exporting: the exporter samples the clips through the pose,
    # and every clip comes out as the rest pose (150 channels, none moving). Clearing the pose bones is enough.
    arm.data.pose_position = "POSE"
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)

    # A mesh named like a bone (the Soldier's "Body" and "Head") makes Godot's importer rename the bone to "Body_2":
    # the clips of that file then target Body_2 and stop driving any other character's Body. Rename the mesh.
    bones = {b.name for b in arm.data.bones}
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        if o.name in bones:
            o.name = o.data.name = o.name + "_Mesh"
    report.update(
        scale_applied=factor,
        bones=len(arm.data.bones),
        clips=sorted(seen),
        meshes={o.name: riglib.tris(o) for o in meshes},
        tris=sum(riglib.tris(o) for o in meshes),
    )

    # 6. Export.
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_def_bones=False,
        export_leaf_bone=False,
        export_reset_pose_bones=True,
        export_optimize_animation_size=False,
    )
    print("RIG-SHARING", src.name, "->", out.name, report)


main()
