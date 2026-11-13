"""Render the review sheet's pictures in Blender (kit #1154). Run by `review_sheet.py`, not by hand:

    blender -b --factory-startup -P review_render.py -- <jobs.json>

`jobs.json` is `{"size": [w, h], "top_size": [w, h], "bodies": [{"glb": <a body's glb with the clips in it>,
"shots": [{"clip", "frame", "view", "out", "shift", "root"}]}]}`. A shot is one clip at one frame from one side: `side` (the
character faces right), `left` (its other side), `front`, `back`, `top` (the character faces up the picture) or
`quarter`. Each is drawn with no
perspective over a floor of 0.25 m squares that is moved back by `shift` metres, so a foot that slides is seen
sliding over its square, with back faces culled as the game draws them. A clip that turns (kit #1157) gives each
shot a `root` instead, `[x, z, yaw]` in glTF's axes (metres to the character's first left and ahead, degrees to its
left): the character is put there on a floor that stays still, and the camera looks from where it would at the
clip's first frame, following the character's place, so the turn is seen as the body makes it.
"""

import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

## Metres of height a side or front picture shows, and of width a top picture shows.
TALL = 2.05
WIDE = 1.15
SQUARE = 0.25


def floor() -> bpy.types.Object:
    """A floor of `SQUARE` squares: a two by two image, repeated."""
    image = bpy.data.images.new("squares", 2, 2)
    light, dark = (0.50, 0.52, 0.55, 1.0), (0.38, 0.40, 0.43, 1.0)
    image.pixels = list(light + dark + dark + light)
    material = bpy.data.materials.new("floor")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    texture.interpolation = "Closest"
    shader = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    material.node_tree.links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    nodes.active = texture
    half = 6.0
    mesh = bpy.data.meshes.new("floor")
    mesh.from_pydata([(-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0)], [], [(0, 1, 2, 3)])
    layer = mesh.uv_layers.new()
    repeat = half / SQUARE
    for loop, uv in zip(layer.data, ((0, 0), (repeat, 0), (repeat, repeat), (0, repeat)), strict=False):
        loop.uv = uv
    mesh.materials.append(material)
    obj = bpy.data.objects.new("floor", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def camera() -> bpy.types.Object:
    data = bpy.data.cameras.new("view")
    data.type = "ORTHO"
    obj = bpy.data.objects.new("view", data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.scene.camera = obj
    return obj


def aim(cam: bpy.types.Object, view: str, size: tuple, at: Vector = None) -> None:
    """Blender's axes: the character faces -Y, its left is +X, up is +Z. `at` moves the camera with a character
    that is not at the origin."""
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = size
    at = at if at is not None else Vector((0.0, 0.0, 0.0))
    middle = Vector((0.0, 0.0, TALL / 2.0 - 0.06))
    if view == "side":
        cam.location, up = middle + Vector((-6.0, 0.0, 0.0)), Vector((0, 0, 1))
        cam.data.ortho_scale = TALL * max(1.0, size[0] / size[1])
    elif view == "left":
        cam.location, up = middle + Vector((6.0, 0.0, 0.0)), Vector((0, 0, 1))
        cam.data.ortho_scale = TALL * max(1.0, size[0] / size[1])
    elif view == "back":
        cam.location, up = middle + Vector((0.0, 6.0, 0.0)), Vector((0, 0, 1))
        cam.data.ortho_scale = TALL * max(1.0, size[0] / size[1])
    elif view == "front":
        cam.location, up = middle + Vector((0.0, -6.0, 0.0)), Vector((0, 0, 1))
        cam.data.ortho_scale = TALL * max(1.0, size[0] / size[1])
    elif view == "quarter":
        cam.location, up = middle + Vector((-3.2, -5.0, 1.2)), Vector((0, 0, 1))
        cam.data.ortho_scale = TALL * 1.08 * max(1.0, size[0] / size[1])
    else:
        middle = Vector((0.0, 0.0, 0.0))
        cam.location, up = Vector((0.0, 0.0, 8.0)), Vector((0, -1, 0))
        cam.data.ortho_scale = WIDE
    cam.location += at
    middle = middle + at
    look = (middle - cam.location).normalized()
    side = look.cross(up).normalized()
    over = side.cross(look)
    cam.rotation_euler = Matrix((side, over, -look)).transposed().to_euler()


def main() -> None:
    jobs = json.loads(Path(sys.argv[sys.argv.index("--") + 1]).read_text(encoding="utf-8"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30  # before any import: Blender reads a clip's seconds at the scene's rate
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world = bpy.data.worlds.new("sky")
    scene.world.color = (0.30, 0.33, 0.38)
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "TEXTURE"
    shading.show_backface_culling = True
    shading.show_shadows = True
    shading.shadow_intensity = 0.35
    shading.show_cavity = True
    scene.display.light_direction = (0.25, -0.35, 0.9)
    ground, cam = floor(), camera()
    for body in jobs["bodies"]:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=body["glb"])
        new = [o for o in bpy.data.objects if o not in before]
        arm = next(o for o in new if o.type == "ARMATURE")
        base = arm.matrix_world.copy()
        for track in arm.animation_data.nla_tracks:
            track.mute = True
        actions = {a.name.removesuffix("_Loop"): a for a in bpy.data.actions}
        for shot in body["shots"]:
            action = actions[shot["clip"]]
            arm.animation_data.action = action
            arm.animation_data.action_slot = action.slots[0]
            scene.frame_set(int(shot["frame"]))
            size = tuple(jobs["top_size"] if shot["view"] == "top" else jobs["size"])
            if "root" in shot:
                # glTF's x (left) is Blender's +X and its z (ahead) Blender's -Y; a turn to the left is about +Z.
                x, z, yaw = shot["root"]
                arm.matrix_world = Matrix.Translation((x, -z, 0.0)) @ Matrix.Rotation(math.radians(yaw), 4, "Z") @ base
                ground.location = (0.0, 0.0, 0.0)
                aim(cam, shot["view"], size, Vector((x, -z, 0.0)))
            else:
                arm.matrix_world = base
                # The floor moves back under a clip in place; it repeats every two squares.
                ground.location = (0.0, math.fmod(shot.get("shift", 0.0), 2.0 * SQUARE), 0.0)
                aim(cam, shot["view"], size)
            scene.render.filepath = shot["out"]
            bpy.ops.render.render(write_still=True)
        for obj in new:
            bpy.data.objects.remove(obj)
        for action in list(bpy.data.actions):
            bpy.data.actions.remove(action)
    print("RENDERED")


if __name__ == "__main__":
    main()
