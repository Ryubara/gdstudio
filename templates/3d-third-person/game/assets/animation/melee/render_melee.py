"""Review sheets of the melee clips (used by `build_melee.py -- --render <folder>`).

For each clip and each mannequin (`female`, `male`), with the pistol in the hand for the pistol clips:

- `<clip>_<body>_side.png`, `_front.png`, `_top.png`: every frame, from the striking hand's side, from the front
  and from above (the character faces up the picture);
- `<clip>_<body>_review.png`: eight frames (the start, the wind-up, the three frames into contact, the
  follow-through, the way back, the end) in three rows: side, front, top;
- `<clip>_<body>_close.png`: the upper body close, from three frames before contact to two after, from the
  striking side, from the front quarter and from the front.

Every tile carries its frame number in the top left corner.
"""

import math

import bpy
import numpy as np
from mathutils import Vector

TILE = (330, 440)
METRES_HIGH = 2.15
DIGITS = {
    "0": "111101101101111",
    "1": "010110010010111",
    "2": "111001111100111",
    "3": "111001111001111",
    "4": "101101111001001",
    "5": "111100111001111",
    "6": "111100111101111",
    "7": "111001001001001",
    "8": "111101111101111",
    "9": "111101111001111",
}


def _floor():
    mesh = bpy.data.meshes.new("Floor")
    mesh.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new("Floor", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.color = (0.32, 0.34, 0.38, 1.0)
    return obj


def _camera():
    data = bpy.data.cameras.new("Sheet")
    data.type = "ORTHO"
    obj = bpy.data.objects.new("Sheet", data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.scene.camera = obj
    return obj


def _aim(camera, place, target, scale, from_above=False):
    camera.location = place
    direction = (Vector(target) - Vector(place)).normalized()
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    if from_above:  # the character faces -Y: turn the picture so that is up
        camera.rotation_euler = (0.0, 0.0, math.radians(180.0))
    camera.data.ortho_scale = scale


def _shot(path, size, label):
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(str(path))
    pixels = np.empty(size[0] * size[1] * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    path.unlink()
    tile = pixels.reshape(size[1], size[0], 4)
    scale = 4
    for i, char in enumerate(str(label)):
        for n, bit in enumerate(DIGITS[char]):
            if bit == "1":
                row, column = divmod(n, 3)
                top = size[1] - 8 - (row + 1) * scale
                left = 8 + i * 4 * scale + column * scale
                tile[top : top + scale, left : left + scale] = (0.05, 0.05, 0.05, 1.0)
    return tile


def _sheet(tiles, columns, path):
    rows = math.ceil(len(tiles) / columns)
    height, width = tiles[0].shape[:2]
    sheet = np.ones((rows * height, columns * width, 4), dtype=np.float32)
    for i, tile in enumerate(tiles):
        row, column = divmod(i, columns)
        top = (rows - 1 - row) * height
        sheet[top : top + height, column * width : (column + 1) * width] = tile
    image = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
    image.pixels.foreach_set(sheet.ravel())
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def render(rig, clips, actions, out, bodies=("female", "male"), every_frame=True):
    """`actions` are the clips as the game shows them (`build_melee.bake(..., shown=True)`)."""
    out.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.film_transparent = False
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_shadows = False
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = True
    scene.world = bpy.data.worlds.new("Sheet")
    scene.world.color = (0.75, 0.78, 0.82)
    scene.view_settings.view_transform = "Standard"
    female, male = rig.bodies
    for obj in rig.library_objects + rig.extras + [o for o in male.objects if o is not male.mesh]:
        obj.hide_render = True
    female.mesh.color = (0.80, 0.82, 0.86, 1.0)
    male.mesh.color = (0.72, 0.80, 0.90, 1.0)
    gun = rig.gun
    for obj in gun.objects:
        obj.color = (0.16, 0.16, 0.18, 1.0)
    camera = _camera()
    _floor()
    arm = rig.arm
    for clip, action in zip(clips, actions):
        arm.animation_data.action = action
        arm.animation_data.action_slot = action.slots[0]
        for obj in gun.objects:
            obj.hide_render = clip.weapon != "pistol"
        side = 6.0 if clip.side == "l" else -6.0
        views = {
            "side": (((side, -0.25, 1.05), (0.0, -0.25, 1.05)), False),
            "front": (((0.0, -6.0, 1.05), (0.0, 0.0, 1.05)), False),
            "top": (((0.0, -0.25, 6.0), (0.0, -0.25, 0.0)), True),
        }
        close = {
            "side": ((side, -0.3, 1.38), (0.0, -0.3, 1.38)),
            "quarter": ((side * 0.6, -4.5, 1.9), (0.0, -0.25, 1.38)),
            "front": ((0.0, -6.0, 1.38), (0.0, 0.0, 1.38)),
        }
        k = clip.contact
        review = [
            0,
            max(1, k - 4),
            k - 2,
            k - 1,
            k,
            k + 2,
            (k + 2 + clip.frames) // 2,
            clip.frames,
        ]
        near = [k - 3, k - 2, k - 1, k, k + 1, k + 2]
        for body in rig.bodies:
            if body.name not in bodies:
                continue
            female.mesh.hide_render = body is not female
            male.mesh.hide_render = body is not male

            def pose(frame, body=body, clip=clip):
                scene.frame_set(frame)
                rig.pose_body(body, clip.weapon == "pistol")
                hand = body.arm.matrix_world @ body.arm.pose.bones["hand_r"].matrix
                gun.root.matrix_world = gun.matrix(hand, rig.holds[body.name])
                bpy.context.view_layer.update()

            rows = []
            for view, ((place, target), above) in views.items():
                tiles = {}
                for frame in range(clip.frames + 1) if every_frame else review:
                    pose(frame)
                    _aim(camera, place, target, METRES_HIGH, above)
                    tiles[frame] = _shot(out / "tile.png", TILE, frame)
                if every_frame:
                    _sheet(
                        list(tiles.values()),
                        8,
                        out / f"{clip.name}_{body.name}_{view}.png",
                    )
                rows += [tiles[frame] for frame in review]
            _sheet(rows, len(review), out / f"{clip.name}_{body.name}_review.png")
            tiles = []
            for place, target in close.values():
                for frame in near:
                    pose(frame)
                    _aim(camera, place, target, 1.25)
                    tiles.append(_shot(out / "tile.png", (440, 440), frame))
            _sheet(tiles, len(near), out / f"{clip.name}_{body.name}_close.png")
    scene.frame_set(0)
