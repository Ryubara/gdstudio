"""Render the prototype mannequins (kit #1149) for review: turntables, wireframes, the rig and poses.

Run it with the pinned Blender, headless, every path absolute:

    blender -b --factory-startup -P render_mannequins.py -- --model <a.glb> [--model <b.glb> ...] --out <png>
        [--views front,side,back,quarter] [--lod 0] [--mode solid|wire|rig] [--pose rest|relaxed|reach]
        [--clip <library.glb> --action <name> --frame <n>] [--zoom <part>] [--px 520]

One row a model, one column a view, all at one scale on a ground line, so bodies are compared like for like.
`--pose relaxed` lowers the arms and bends the elbows and knees a little, by bone rotations (the twist bones are
turned as the engine's `MannequinTwist` turns them); `--clip` poses the body from a frame of a clip file instead, the
way Godot plays it: each bone's rotation in its parent and the pelvis's place times the body's `motion_scale`.
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

VIEWS = {"front": 0.0, "quarter": 35.0, "side": 90.0, "back": 180.0, "rear": 215.0}
ZOOMS = {
    "hand": ("hand_l", 0.28),
    "shoulder": ("upperarm_l", 0.55),
    "foot": ("foot_l", 0.4),
    "head": ("Head", 0.5),
    "upper": ("spine_03", 1.1),
}


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    meshes = sorted((o for o in new if o.type == "MESH"), key=lambda o: o.name)
    return rig, meshes, new


def twist_about(quaternion, axis):
    """The part of a rotation that turns about `axis` (swing-twist)."""
    projected = Vector((quaternion.x, quaternion.y, quaternion.z)).project(axis)
    twist = Quaternion((quaternion.w, projected.x, projected.y, projected.z))
    if twist.magnitude < 1e-9:
        return Quaternion()
    twist.normalize()
    return twist


def drive_twist(rig):
    """Turn the twist bones as `mannequin_twist.gd` does."""
    y = Vector((0, 1, 0))
    for side in "lr":
        for limb in ("upperarm", "thigh"):
            twist = rig.pose.bones.get(f"{limb}_twist_01_{side}")
            if twist is not None:
                twist.rotation_mode = "QUATERNION"
                twist.rotation_quaternion = twist_about(pose_rotation(rig.pose.bones[f"{limb}_{side}"]), y).inverted()
        twist = rig.pose.bones.get(f"lowerarm_twist_01_{side}")
        if twist is not None:
            hand = rig.pose.bones[f"hand_{side}"]
            # The hand's turn, seen in the forearm's axes (the hand rests turned in the forearm).
            rest = hand.bone.matrix_local.to_quaternion()
            parent = hand.parent.bone.matrix_local.to_quaternion()
            local = parent.inverted() @ rest
            turn = local @ pose_rotation(hand) @ local.inverted()
            twist.rotation_mode = "QUATERNION"
            twist.rotation_quaternion = twist_about(turn, y)


def pose_rotation(bone):
    if bone.rotation_mode == "QUATERNION":
        return bone.rotation_quaternion.copy()
    return bone.rotation_euler.to_quaternion()


def turn_world(rig, name, axis, degrees):
    """Turn a bone about an axis of the armature's space (Blender's: +Z up, -Y front), keeping its place."""
    bone = rig.pose.bones[name]
    bpy.context.view_layer.update()
    matrix = bone.matrix.copy()
    turned = Matrix.Rotation(math.radians(degrees), 4, axis) @ matrix
    turned.translation = matrix.translation
    bone.matrix = turned
    bpy.context.view_layer.update()


def pose(rig, name):
    for bone in rig.pose.bones:
        bone.rotation_mode = "QUATERNION"
    if name == "relaxed":
        for side, sign in (("l", 1), ("r", -1)):
            turn_world(rig, f"upperarm_{side}", "Y", 62 * sign)
            turn_world(rig, f"lowerarm_{side}", "X", 22)
            turn_world(rig, f"thigh_{side}", "Y", -4 * sign)
    elif name == "reach":
        # Arms forward and rolled, a knee up: the pose that shows a bad shoulder, a wrung forearm and a hip.
        for side, sign in (("l", 1), ("r", -1)):
            turn_world(rig, f"upperarm_{side}", "Z", -80 * sign)
            turn_world(rig, f"upperarm_{side}", "Y", 0)
            turn_world(rig, f"lowerarm_{side}", "Z", -35 * sign)
            hand = rig.pose.bones[f"hand_{side}"]
            hand.rotation_quaternion = Quaternion((0, 1, 0), math.radians(-80 * sign)) @ hand.rotation_quaternion
        turn_world(rig, "thigh_l", "X", 70)
        turn_world(rig, "calf_l", "X", -80)
    drive_twist(rig)
    bpy.context.view_layer.update()


def pose_from_clip(rig, clip_rig, action, frame):
    """Copy a frame of a clip onto the body: rotations as they are, the pelvis's place times the motion scale."""
    scale = rig.get("motion_scale", 1.0)
    clip_rig.animation_data_create()
    clip_rig.animation_data.action = action
    if hasattr(clip_rig.animation_data, "action_slot") and action.slots:
        clip_rig.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    for source in clip_rig.pose.bones:
        target = rig.pose.bones.get(source.name)
        if target is None:
            continue
        target.rotation_mode = "QUATERNION"
        target.rotation_quaternion = pose_rotation(source)
        target.location = source.location * scale
    drive_twist(rig)
    bpy.context.view_layer.update()


def bone_sticks(rig, offset):
    """The skeleton as geometry, since a render does not draw bones: a stick a bone and a cross a socket."""
    verts, faces, colours = [], [], []

    def box(a, b, width, colour):
        direction = (b - a).normalized() if (b - a).length > 1e-6 else Vector((0, 0, 1))
        side = direction.orthogonal().normalized() * width
        other = direction.cross(side)
        base = len(verts)
        for end in (a, b):
            for s, o in ((1, 1), (-1, 1), (-1, -1), (1, -1)):
                verts.append(end + side * s + other * o)
        for quad in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            faces.append(tuple(base + i for i in quad))
            colours.append(colour)

    for bone in rig.pose.bones:
        head, name = bone.head, bone.name
        if name.startswith("socket_"):
            for axis, colour in ((bone.x_axis, 0), (bone.y_axis, 1), (bone.z_axis, 2)):
                box(head, head + axis * 0.07, 0.004, colour)
        elif name.startswith("ik_"):
            box(head - Vector((0.03, 0, 0)), head + Vector((0.03, 0, 0)), 0.006, 3)
            box(head - Vector((0, 0.03, 0)), head + Vector((0, 0.03, 0)), 0.006, 3)
        elif "twist" in name:
            box(head, head + bone.y_axis * 0.06, 0.009, 4)
        else:
            tail = bone.children[0].head if bone.children and not bone.children[0].name.startswith(("socket", "ik", "thigh", "clav")) and "twist" not in bone.children[0].name else bone.tail
            if name in ("pelvis", "spine_03", "hand_l", "hand_r", "root"):
                tail = bone.tail
            box(head, tail, 0.0035 if "0" in name and "spine" not in name and "neck" not in name else 0.006, 5)
    mesh = bpy.data.meshes.new("sticks")
    mesh.from_pydata([v + offset for v in verts], [], faces)
    palette = [(0.9, 0.1, 0.1, 1), (0.1, 0.75, 0.1, 1), (0.15, 0.3, 1.0, 1), (1.0, 0.1, 0.9, 1), (1.0, 0.75, 0.0, 1), (0.05, 0.05, 0.05, 1)]
    for i, colour in enumerate(palette):
        material = bpy.data.materials.new(f"stick{i}")
        material.diffuse_color = colour
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.material_index = colours[polygon.index]
    obj = bpy.data.objects.new("sticks", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", action="append", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--views", default="front,quarter,side,back")
    parser.add_argument("--lod", type=int, default=0)
    parser.add_argument("--mode", default="solid", choices=("solid", "wire", "rig"))
    parser.add_argument("--pose", default="rest")
    parser.add_argument("--clip", type=Path)
    parser.add_argument("--action")
    parser.add_argument("--frame", type=int, default=0)
    parser.add_argument("--zoom")
    parser.add_argument("--px", type=int, default=520)
    parser.add_argument("--height", type=float, default=1.95)
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    views = args.views.split(",")
    clip_rig = action = None
    if args.clip:
        clip_rig, _meshes, new = load(args.clip)
        action = bpy.data.actions[args.action]
        for obj in new:
            obj.hide_render = True

    step = 1.9 if not args.zoom else 3.0
    row_step = args.height + 0.12
    shown = []
    for row, path in enumerate(args.model):
        for column, view in enumerate(views):
            rig, meshes, _new = load(path)
            for i, mesh in enumerate(meshes):
                mesh.hide_render = i != args.lod
            if clip_rig is not None:
                pose_from_clip(rig, clip_rig, action, args.frame)
            elif args.pose != "rest":
                pose(rig, args.pose)
            body = meshes[args.lod]
            spot = Vector((column * step, 0, -row * row_step))
            pivot = Vector((0, 0, 0))
            if args.zoom:
                pivot = rig.pose.bones[ZOOMS[args.zoom][0]].head.copy()
            rig.rotation_mode = "XYZ"
            rig.rotation_euler = (0, 0, math.radians(VIEWS[view]))
            bpy.context.view_layer.update()
            rig.location = spot - (rig.matrix_world.to_3x3() @ pivot if args.zoom else Vector((0, 0, 0)))
            if args.mode == "wire":
                wire = body.modifiers.new("wire", "WIREFRAME")
                wire.thickness = 0.0022 if not args.zoom else 0.0008
                wire.use_replace = False
                wire.material_offset = 1
                dark = bpy.data.materials.new("wire")
                dark.diffuse_color = (0.02, 0.02, 0.02, 1)
                body.data.materials.append(dark)
            if args.mode == "rig":
                bpy.context.view_layer.update()
                sticks = bone_sticks(rig, Vector((0, 0, 0)))
                sticks.matrix_world = rig.matrix_world
                sticks.show_in_front = True
                body.color = (1, 1, 1, 0.25)
            shown.append(body)

    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE" if args.mode != "rig" else "MATERIAL"
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    shading.show_shadows = False
    shading.show_specular_highlight = False
    shading.show_object_outline = True
    if args.mode == "rig":
        shading.show_xray = True
        shading.xray_alpha = 0.35
    scene.display.render_aa = "8"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("world")
    scene.world = world
    scene.render.film_transparent = False
    world.color = (0.62, 0.64, 0.67)

    columns, rows = len(views), len(args.model)
    camera_data = bpy.data.cameras.new("camera")
    camera_data.type = "ORTHO"
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    if args.zoom:
        span = ZOOMS[args.zoom][1]
        width, height = step * (columns - 1) + span, row_step * (rows - 1) + span
        middle = Vector((step * (columns - 1) / 2, -10, -row_step * (rows - 1) / 2))
        cell = span
    else:
        width, height = step * columns, row_step * rows
        middle = Vector((step * (columns - 1) / 2, -10, args.height / 2 - 0.04 - row_step * (rows - 1) / 2))
        cell = step
    camera.location = middle
    camera.rotation_euler = (math.radians(90), 0, 0)
    camera_data.ortho_scale = max(width, height * 1.0) if width >= height else height
    scene.render.resolution_x = int(args.px * width / cell)
    scene.render.resolution_y = int(args.px * height / cell)
    camera_data.ortho_scale = max(width, height)
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(args.out)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", args.out)


main()
