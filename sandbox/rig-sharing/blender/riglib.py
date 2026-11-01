"""Helpers for the rig-sharing spike scripts (a trimmed copy of Deadnight's tools/blender/kitlib.py).

Not run on its own. The scripts that use it put this folder on sys.path first.
"""

import bpy

# Meshes parented to a hand bone are held items (each kit character file carries all 14 kit weapons in its hands).
HAND_BONE_PREFIXES = ("LowerArm", "Hand", "Wrist", "Palm", "Index", "Middle", "Ring", "Pinky", "Thumb")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    """Import into an empty scene; return the new objects.

    `bone_heuristic="TEMPERANCE"`: with the default the bone-attached meshes (helmets, pads, weapons) land in the
    wrong place.
    """
    reset()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="TEMPERANCE")
    return [o for o in bpy.data.objects if o not in before]


def armature_of(objs):
    return next((o for o in objs if o.type == "ARMATURE"), None)


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def fcurves(action):
    """F-curves of an action on Blender 4.4+ (layered actions: layers > strips > channelbags) and older."""
    if hasattr(action, "layers") and action.layers:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    yield from bag.fcurves
    else:
        yield from getattr(action, "fcurves", [])


def split_parts(objs):
    """Split meshes into body, held items (parented to a hand bone) and strays (unparented, e.g. the Icosphere)."""
    arm = armature_of(objs)
    body, held, stray = [], [], []
    for o in objs:
        if o.type != "MESH":
            continue
        if o.parent is None:
            stray.append(o)
        elif o.parent_type == "BONE" and o.parent_bone.startswith(HAND_BONE_PREFIXES):
            held.append(o)
        else:
            body.append(o)
    return body, held, stray
