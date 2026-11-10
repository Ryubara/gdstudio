"""Contact sheets of the vault clips over their reference obstacle (used by `build_vault.py --render <folder>`).

For each clip: `<clip>_side.png` (from the character's left, every frame), `<clip>_right.png`, `<clip>_front.png`
and `<clip>_top.png` (every second frame), and `<clip>_path.png` (the whole vault in one picture, the body drawn
every second frame where the root is at that frame). The body moves forward at the clip's reference speed, so the
box stands still as it does in a game.

For a clip with an obstacle, also `<clip>_over.png`: the frames over the top (from the hand plant to five frames
after the release), larger, from the front (upper rows) and from the character's left (lower rows), which is where
legs that pass through each other show; and `<clip>_close_<frame>.png` for the frames in `CLOSE`, the legs from
the front and from the right.
"""

import math

import bpy
import numpy as np
from mathutils import Vector

TILE = (400, 480)
METRES_HIGH = 2.3
## The frames looked at close: where the first version of each clip had a leg deepest in the other leg or an arm.
CLOSE = {"Vault_Low": [7, 12], "Vault_High": [15, 20]}


def _material(name, colour):
    material = bpy.data.materials.new(name)
    material.diffuse_color = colour
    return material


def _box(clip, left_from, left_to, name, wire):
    low = Vector((left_from, -clip.box_depth, 0.0))
    high = Vector((left_to, 0.0, clip.box_height))
    corners = [(x, y, z) for x in (low.x, high.x) for y in (low.y, high.y) for z in (low.z, high.z)]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(corners, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.color = (0.85, 0.45, 0.15, 1.0)
    if wire:
        obj.modifiers.new("Wire", "WIREFRAME").thickness = 0.02
    return obj


def _floor():
    mesh = bpy.data.meshes.new("Floor")
    mesh.from_pydata([(-3, -6, 0), (3, -6, 0), (3, 6, 0), (-3, 6, 0)], [], [(0, 1, 2, 3)])
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


def _aim(camera, place, target, scale):
    camera.location = place
    direction = (Vector(target) - Vector(place)).normalized()
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = scale


def _shot(path, size):
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
    return pixels.reshape(size[1], size[0], 4)


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


def render(rig, clips, actions, out):
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
    for obj in rig.library_objects:
        obj.hide_render = True
    rig.mesh.color = (0.80, 0.82, 0.86, 1.0)
    camera = _camera()
    _floor()
    arm = rig.arm
    for clip, action in zip(clips, actions):
        arm.animation_data.action = action
        arm.animation_data.action_slot = action.slots[0]
        boxes = []
        if clip.box_height > 0.0:
            boxes = [
                _box(clip, -1.5, 1.5, "BoxWire", True),
                _box(clip, -1.5, -1.05, "BoxFarRight", False),
                _box(clip, 0.75, 1.5, "BoxFarLeft", False),
            ]

        def show(wire, right, left, boxes=boxes):
            for box, on in zip(boxes, (wire, right, left)):
                box.hide_render = not on

        views = {
            "side": (lambda y: ((6, y, 1.05), (0, y, 1.05)), 1, (True, True, False)),
            "right": (lambda y: ((-6, y, 1.05), (0, y, 1.05)), 2, (True, False, True)),
            "front": (lambda y: ((0, y - 6, 1.05), (0, y, 1.05)), 2, (True, False, False)),
            "top": (lambda y: ((0, y, 6), (0, y - 0.001, 0)), 2, (True, False, False)),
        }
        for view, (place, every, boxes_on) in views.items():
            show(*boxes_on)
            tiles = []
            for frame in range(0, clip.frames + 1, every):
                scene.frame_set(frame)
                arm.location.y = -clip.forward(frame)
                _aim(camera, *place(arm.location.y), METRES_HIGH)
                tiles.append(_shot(out / "tile.png", TILE))
            _sheet(tiles, 5, out / f"{clip.name}_{view}.png")

        if clip.box_height > 0.0:
            # Over the top, larger: the front above, the character's left below.
            show(True, False, False)
            first = clip.events["hand_plant"] - 1
            last = min(clip.frames, clip.events["hand_release"] + 5)
            rows = []
            for view in ("front", "side"):
                for frame in range(first, last + 1):
                    scene.frame_set(frame)
                    arm.location.y = -clip.forward(frame)
                    middle = clip.box_height + 0.15
                    y = arm.location.y
                    place = (0, y - 6, middle) if view == "front" else (6, y, middle)
                    _aim(camera, place, (0, y, middle), 2.1)
                    rows.append(_shot(out / "tile.png", (480, 480)))
                while len(rows) % 6:
                    rows.append(np.ones_like(rows[0]))
            _sheet(rows, 6, out / f"{clip.name}_over.png")
            for frame in CLOSE.get(clip.name, []):
                scene.frame_set(frame)
                arm.location.y = -clip.forward(frame)
                bpy.context.view_layer.update()
                hips = arm.matrix_world @ arm.pose.bones["pelvis"].head
                target = (hips.x - 0.25, hips.y - 0.15, hips.z - 0.05)
                tiles = []
                for offset in ((0, -6, 0.6), (-6, -1.5, 0.6)):
                    place = tuple(a + b for a, b in zip(target, offset))
                    _aim(camera, place, target, 1.25)
                    tiles.append(_shot(out / "tile.png", (640, 640)))
                _sheet(tiles, 2, out / f"{clip.name}_close_{frame:02d}.png")

        # The whole path in one picture: a copy of the skinned body where the root is, every second frame.
        show(True, True, False)
        copies = []
        graph = bpy.context.evaluated_depsgraph_get()
        frames = list(range(0, clip.frames + 1, 4))
        for i, frame in enumerate(frames):
            scene.frame_set(frame)
            arm.location.y = -clip.forward(frame)
            bpy.context.view_layer.update()
            graph = bpy.context.evaluated_depsgraph_get()
            mesh = bpy.data.meshes.new_from_object(rig.mesh.evaluated_get(graph))
            copy = bpy.data.objects.new(f"Ghost{frame}", mesh)
            copy.matrix_world = rig.mesh.matrix_world.copy()
            scene.collection.objects.link(copy)
            share = i / max(1, len(frames) - 1)
            copy.color = (0.25 + 0.7 * share, 0.55, 0.95 - 0.7 * share, 1.0)
            copies.append(copy)
        rig.mesh.hide_render = True
        middle = -(clip.forward(0) + clip.forward(clip.frames)) / 2.0
        span = clip.speed * clip.frames / 24.0 + 1.8
        _aim(camera, (6, middle, 1.0), (0, middle, 1.0), span)
        side = _shot(out / "tile.png", (int(span * 360), int(2.3 * 360)))
        _sheet([side], 1, out / f"{clip.name}_path.png")
        _aim(camera, (0, middle, 6), (0, middle - 0.001, 0), span)
        camera.rotation_euler = (0.0, 0.0, math.radians(-90))
        top = _shot(out / "tile.png", (int(span * 360), int(2.3 * 360)))
        _sheet([top], 1, out / f"{clip.name}_path_top.png")
        rig.mesh.hide_render = False
        for obj in copies + boxes:
            bpy.data.objects.remove(obj, do_unlink=True)
        arm.location.y = 0.0
