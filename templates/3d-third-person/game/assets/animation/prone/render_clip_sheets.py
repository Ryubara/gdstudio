"""Render contact sheets of animation clips on a mannequin, the way Godot plays them (kit #1009).

Godot plays a library clip on any model of the Quaternius universal rig by writing the clip's local bone rotations
(and the pelvis and root positions) onto the model's own bones, so a clip authored on one mannequin reaches a slightly
different pose on the other. This script does the same in Blender: it imports the model and the clip file, copies each
frame's local rotations onto the model's armature and renders the model from the side, the front and the top, one
column per frame. Run it with the pinned Blender, headless, every path absolute:

    blender -b --factory-startup -P render_clip_sheets.py -- --model <mannequin.glb> --clips <clips.glb>
        --out <folder> [--clip <name> ...] [--frames 8] [--travel <name>=<metres per second> ...]
        [--views side,front,top,quarter] [--tile 480x300] [--scale 2.6] [--height 0.75] [--ahead 0] [--wrap 0]
        [--range 12-24]

`--travel` moves the model forward at that speed while the clip plays, over a floor of 0.25 m squares, so a hand or a
foot that is planted stays on its square. `--ahead` moves every camera that far toward the head and `--wrap` breaks
each view's row after that many frames, for a close-up of the arms over a whole cycle
(`--views top --scale 1.15 --ahead 0.62 --frames 14 --wrap 7 --tile 520x440`).
"""

import argparse
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

VIEWS = ("side", "front", "top", "quarter")
# Where each camera stands for a model at the origin, and how it is turned. The model faces -Y, so the side view
# looks at its right side with the head to the right, and the top view has the head to the right as well.
CAMERA_HOME = {
    "side": (-10.0, 0.0, 0.0),
    "front": (0.0, -10.0, 0.0),
    "top": (0.0, 0.0, 10.0),
    "quarter": (-6.0, -7.0, 5.5),
}
CAMERA_TURN = {
    "side": (math.radians(90), 0.0, math.radians(-90)),
    "front": (math.radians(90), 0.0, 0.0),
    "top": (0.0, 0.0, math.radians(-90)),
    "quarter": (math.radians(59.2), 0.0, math.radians(-40.6)),
}


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="BLENDER")
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    return arm, new


def rest_local(bone):
    if bone.parent:
        return bone.parent.matrix_local.inverted() @ bone.matrix_local
    return bone.matrix_local.copy()


def clip_frames(arm, action, count, span=None):
    """The local bone matrices of a clip at `count` evenly spaced frames, and its frame range (or `span`'s)."""
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    first, last = span or (round(v) for v in action.frame_range)
    frames = sorted(
        {round(first + (last - first) * i / max(count - 1, 1)) for i in range(count)}
    )
    out = []
    for frame in frames:
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        pose = {}
        for pb in arm.pose.bones:
            pose[pb.name] = (
                (pb.parent.matrix.inverted() @ pb.matrix)
                if pb.parent
                else pb.matrix.copy()
            )
        out.append((frame, pose))
    return out, (first, last)


def apply_pose(model, pose, moved=("root", "pelvis")):
    """Write a clip pose onto the model as Godot does: rotations from the clip, bone offsets from the model."""
    for pb in model.pose.bones:
        local = pose.get(pb.name)
        rest = rest_local(pb.bone)
        pb.rotation_mode = "QUATERNION"
        if local is None:
            pb.matrix_basis = Matrix.Identity(4)
            continue
        want = local.to_quaternion().to_matrix().to_4x4()
        want.translation = local.translation if pb.name in moved else rest.translation
        basis = rest.inverted() @ want
        pb.location = basis.translation
        pb.rotation_quaternion = basis.to_quaternion()
        pb.scale = (1, 1, 1)


def make_camera(name, scale):
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = scale
    cam = bpy.data.objects.new(name, data)
    cam.location = CAMERA_HOME[name]
    cam.rotation_euler = CAMERA_TURN[name]
    bpy.context.scene.collection.objects.link(cam)
    return cam


def make_floor(size=14.0, square=0.25):
    """A floor of two greys in `square` metre squares: one mesh, two materials."""
    n = int(size / square)
    verts, faces, mats = [], [], []
    for i in range(n):
        for j in range(n):
            x0, y0 = -size / 2 + i * square, -size / 2 + j * square
            base = len(verts)
            verts += [
                (x0, y0, 0),
                (x0 + square, y0, 0),
                (x0 + square, y0 + square, 0),
                (x0, y0 + square, 0),
            ]
            faces.append((base, base + 1, base + 2, base + 3))
            mats.append((i + j) % 2)
    mesh = bpy.data.meshes.new("Floor")
    mesh.from_pydata(verts, [], faces)
    for index, shade in enumerate((0.40, 0.50)):
        mat = bpy.data.materials.new(f"Floor{index}")
        mat.diffuse_color = (shade, shade, shade + 0.03, 1)
        mesh.materials.append(mat)
    for poly, index in zip(mesh.polygons, mats):
        poly.material_index = index
    floor = bpy.data.objects.new("Floor", mesh)
    bpy.context.scene.collection.objects.link(floor)
    return floor


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    world = bpy.data.worlds.new("World")
    world.color = (0.75, 0.77, 0.8)
    scene.world = world
    scene.view_settings.view_transform = "Standard"
    return scene


def render_tile(scene, cam, path):
    scene.camera = cam
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(str(path))
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(
        image.size[1], image.size[0], 4
    )
    bpy.data.images.remove(image)
    return pixels


def save_sheet(rows, path):
    """Rows of tiles, the first row on top (Blender's pixel rows run bottom up)."""
    sheet = np.concatenate([np.concatenate(row, axis=1) for row in rows[::-1]], axis=0)
    image = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
    image.pixels.foreach_set(sheet.ravel())
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--clips", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--clip", action="append")
    parser.add_argument("--frames", type=int, default=8)
    parser.add_argument("--travel", action="append", default=[])
    parser.add_argument("--scale", type=float, default=2.6)
    parser.add_argument("--suffix", default="")
    parser.add_argument("--views", default="side,front,top")
    parser.add_argument("--tile", default="480x300")
    parser.add_argument(
        "--height",
        type=float,
        default=0.75,
        help="the height the side and front views centre on",
    )
    parser.add_argument(
        "--ahead",
        type=float,
        default=0.0,
        help="metres the cameras move toward the head",
    )
    parser.add_argument("--range", help="first-last: the frames to spread over")
    parser.add_argument(
        "--wrap", type=int, default=0, help="frames in a row before a new one"
    )
    args = parser.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    travel = {k: float(v) for k, v in (item.split("=") for item in args.travel)}

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = setup_scene()
    scene.render.fps = (
        30  # the library's rate, so a frame of the clip is a frame of the scene
    )
    scene.render.resolution_x, scene.render.resolution_y = (
        int(v) for v in args.tile.split("x")
    )
    views = args.views.split(",")
    model, model_objects = import_glb(args.model)
    for obj in model_objects:
        if (
            obj.type == "MESH" and obj.parent is None
        ):  # the female file carries a stray icosphere
            bpy.data.objects.remove(obj)
    clips_arm, clip_objects = import_glb(args.clips)
    for obj in clip_objects:
        obj.hide_render = True
    fps = scene.render.fps
    make_floor()
    cams = {view: make_camera(view, args.scale) for view in views}
    lift = {
        "side": args.height,
        "front": args.height,
        "top": 0.0,
        "quarter": args.height,
    }
    names = args.clip or sorted(a.name for a in bpy.data.actions)
    for name in names:
        action = bpy.data.actions.get(name)
        if action is None:
            raise SystemExit(f"no clip {name} in {args.clips}")
        span = [int(v) for v in args.range.split("-")] if args.range else None
        frames, (first, last) = clip_frames(clips_arm, action, args.frames, span)
        rows = {view: [] for view in views}
        speed = travel.get(name, 0.0)
        for frame, pose in frames:
            apply_pose(model, pose)
            shift = -speed * (frame - first) / fps  # the model faces -Y
            model.location = (0, shift, 0)
            shift -= args.ahead
            for view, cam in cams.items():
                home = CAMERA_HOME[view]
                cam.location = (home[0], home[1] + shift, home[2] + lift[view])
            bpy.context.view_layer.update()
            for view in views:
                rows[view].append(
                    render_tile(scene, cams[view], out / f"_tile_{view}.png")
                )
        for view in views:
            (out / f"_tile_{view}.png").unlink(missing_ok=True)
        target = out / f"{name}{args.suffix}.png"
        wrap = args.wrap or len(frames)
        blank = np.ones_like(rows[views[0]][0])
        sheet = []
        for view in views:
            for start in range(0, len(frames), wrap):
                row = rows[view][start : start + wrap]
                sheet.append(row + [blank] * (wrap - len(row)))
        save_sheet(sheet, target)
        print(f"SHEET {name} frames {first}-{last} at {fps} fps -> {target}")


if __name__ == "__main__":
    main()
