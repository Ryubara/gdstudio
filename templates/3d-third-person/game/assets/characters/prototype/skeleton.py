"""The prototype mannequin skeleton (kit #1149): bone names, parents and rest pose. Pure numpy, no Blender.

The contract is the kit page `docs/tools/blender/mannequin-rig.md`. 82 bones: the Universal Animation Library's 65
(Quaternius, CC0), with their names, parents and rest rotations to the bit, so every library clip plays with no
conversion, plus 17 leaves of our own (twist bones, sockets, IK targets). A body (`bodies.py`) gives only the places
of the joints: clips store rotations, so bodies of any proportions share them.

Axes here are the exported file's and Godot's: +Y up, +Z the character's front, +X its left, metres.
"""

import numpy as np

## The library rig's hips height (m): clips key the pelvis's place for this body. A body's `motion_scale` is its own
## pelvis rest height over this.
REFERENCE_HIPS = 0.916607

## (name, parent, rest rotation in the parent as a glTF quaternion x y z w, the reference body's rest translation in
## the parent). Read from the library's rig; the translations are the reference the bodies are measured against.
LIBRARY_BONES = [
    ('root', None, (-0.7071068, 0, 0, 0.7071068), (0, 0, 0)),
    ('pelvis', 'root', (0.7904685, 0, 0, 0.6125028), (0, 0.0501, 0.9167)),
    ('spine_01', 'pelvis', (-0.0647026, 0, 0, 0.9979046), (0, 0.138176, -0.0)),
    ('spine_02', 'spine_01', (-0.0772798, 0, 0, 0.9970095), (0, 0.124035, 0.0)),
    ('spine_03', 'spine_02', (-0.0002686, 0, 0, 1), (0, 0.141272, 0.0)),
    ('neck_01', 'spine_03', (0.1109859, 0, 0, 0.993822), (0, 0.172891, -0.0)),
    ('Head', 'neck_01', (-0.0786742, 0, 0, 0.9969004), (0, 0.082587, -0.0)),
    ('clavicle_l', 'spine_03', (-0.6040206, -0.345103, -0.3567177, 0.6235508), (0.0188, 0.140554, 0.080895)),
    ('upperarm_l', 'clavicle_l', (0.1802696, 0.68385, -0.1798364, 0.6837477), (-0.030072, 0.218582, -0.016968)),
    ('lowerarm_l', 'upperarm_l', (0.0171823, -2.04e-05, 4e-07, 0.9998524), (0.0, 0.27444, -0.0)),
    ('hand_l', 'lowerarm_l', (-0.0086197, -4e-07, 0.0, 0.9999629), (0.0, 0.272641, -0.0)),
    ('index_01_l', 'hand_l', (-0.0, 0.7071096, -0.0, 0.707104), (0.002, 0.1199, 0.0309)),
    ('index_02_l', 'index_01_l', (-0.0, -0.0, -0.0, 1), (-0.0, 0.0407, 0.0)),
    ('index_03_l', 'index_02_l', (0.0, 0.0, -0.0, 1), (0.0, 0.0348, 0.0)),
    ('index_04_leaf_l', 'index_03_l', (0.0, 1, 0.0, 3.7e-06), (0.0, 0.0301, 0.0)),
    ('middle_01_l', 'hand_l', (-0.0167025, 0.7069123, -0.0167026, 0.7069067), (-0.0004, 0.1216, 0.0052)),
    ('middle_02_l', 'middle_01_l', (-0.0, -0.0, 0.0015136, 0.9999989), (0.0, 0.042347, 0.0)),
    ('middle_03_l', 'middle_02_l', (0.0, -0.0, -0.0011297, 0.9999993), (-0.0, 0.033933, 0.0)),
    ('middle_04_leaf_l', 'middle_03_l', (0.0, 1, -0.0, 3.7e-06), (-0.0, 0.034437, 0.0)),
    ('pinky_01_l', 'hand_l', (-0.023706, 0.7067121, -0.0237062, 0.7067065), (0.0016, 0.1077, -0.0408)),
    ('pinky_02_l', 'pinky_01_l', (0.0, -0.0, -0.0008343, 0.9999996), (0.0, 0.040291, -0.0)),
    ('pinky_03_l', 'pinky_02_l', (-0.0, 0.0, 0.0006095, 0.9999998), (-0.0, 0.027665, 0.0)),
    ('pinky_04_leaf_l', 'pinky_03_l', (0.0, 1, 0.0, 3.7e-06), (-0.0, 0.028164, 0.0)),
    ('ring_01_l', 'hand_l', (-0.0125887, 0.7069975, -0.0125888, 0.706992), (-0.0001, 0.1191, -0.0171)),
    ('ring_02_l', 'ring_01_l', (-0.0, -0.0, 1.22e-05, 1), (-0.0, 0.039325, -0.0)),
    ('ring_03_l', 'ring_02_l', (0.0, -0.0, -0.0010671, 0.9999994), (-0.0, 0.03092, -0.0)),
    ('ring_04_leaf_l', 'ring_03_l', (0.0, 1, 0.0, 3.7e-06), (0.0, 0.031823, -0.0)),
    ('thumb_01_l', 'hand_l', (0.247413, 0.9457945, 0.2034412, 0.0535841), (0.0228, 0.0273, 0.0336)),
    ('thumb_02_l', 'thumb_01_l', (-0.0001357, -7.41e-05, 4.79e-05, 1), (0.0, 0.04303, 0.0)),
    ('thumb_03_l', 'thumb_02_l', (0.0002479, 8.09e-05, -0.0005353, 0.9999998), (-0.0, 0.049078, -0.0)),
    ('thumb_04_leaf_l', 'thumb_03_l', (0.0, 0.5061779, 3e-07, 0.8624291), (-0.0, 0.040862, -0.0)),
    ('clavicle_r', 'spine_03', (-0.6040206, 0.345103, 0.3567177, 0.6235508), (-0.0188, 0.140554, 0.080895)),
    ('upperarm_r', 'clavicle_r', (0.1802696, -0.68385, 0.1798364, 0.6837477), (0.030072, 0.218582, -0.016968)),
    ('lowerarm_r', 'upperarm_r', (0.0171823, 2.04e-05, -4e-07, 0.9998524), (-0.0, 0.27444, -0.0)),
    ('hand_r', 'lowerarm_r', (-0.0086197, 5e-07, -0.0, 0.9999629), (-0.0, 0.27264, 0.0)),
    ('index_01_r', 'hand_r', (-0.0, -0.7071096, 0.0, 0.7071039), (-0.002, 0.1199, 0.0309)),
    ('index_02_r', 'index_01_r', (-0.0, -0.0, 0.0, 1), (-0.0, 0.0407, -0.0)),
    ('index_03_r', 'index_02_r', (-0.0, -0.0, -0.0, 1), (-0.0, 0.0348, -0.0)),
    ('index_04_leaf_r', 'index_03_r', (0.0, -1, 0.0, 3.7e-06), (-0.0, 0.0301, 0.0)),
    ('middle_01_r', 'hand_r', (-0.0167025, -0.7069123, 0.0167026, 0.7069067), (0.0004, 0.1216, 0.0052)),
    ('middle_02_r', 'middle_01_r', (-0.0, -0.0, -0.0015136, 0.9999989), (0.0, 0.042347, -0.0)),
    ('middle_03_r', 'middle_02_r', (0.0, 0.0, 0.0011297, 0.9999993), (0.0, 0.033933, 0.0)),
    ('middle_04_leaf_r', 'middle_03_r', (0.0, -1, -0.0, 3.7e-06), (0.0, 0.034437, 0.0)),
    ('pinky_01_r', 'hand_r', (-0.023706, -0.7067121, 0.0237062, 0.7067065), (-0.0016, 0.1077, -0.0408)),
    ('pinky_02_r', 'pinky_01_r', (0.0, -0.0, 0.0008343, 0.9999996), (0.0, 0.040291, -0.0)),
    ('pinky_03_r', 'pinky_02_r', (-0.0, -0.0, -0.0006095, 0.9999998), (0.0, 0.027665, -0.0)),
    ('pinky_04_leaf_r', 'pinky_03_r', (0.0, -1, -0.0, 3.7e-06), (0.0, 0.028164, -0.0)),
    ('ring_01_r', 'hand_r', (-0.0125887, -0.7069975, 0.0125888, 0.706992), (0.0001, 0.1191, -0.0171)),
    ('ring_02_r', 'ring_01_r', (0.0, -0.0, -1.22e-05, 1), (-0.0, 0.039325, -0.0)),
    ('ring_03_r', 'ring_02_r', (0.0, 0.0, 0.0010671, 0.9999994), (0.0, 0.03092, -0.0)),
    ('ring_04_leaf_r', 'ring_03_r', (0.0, -1, -0.0, 3.7e-06), (-0.0, 0.031823, 0.0)),
    ('thumb_01_r', 'hand_r', (0.2474131, -0.9457945, -0.2034411, 0.0535841), (-0.0228, 0.0273, 0.0336)),
    ('thumb_02_r', 'thumb_01_r', (-0.0001357, 7.4e-05, -4.79e-05, 1), (-0.0, 0.04303, -0.0)),
    ('thumb_03_r', 'thumb_02_r', (0.0002479, -8.1e-05, 0.0005353, 0.9999999), (-0.0, 0.049078, 0.0)),
    ('thumb_04_leaf_r', 'thumb_03_r', (0.0, -0.5061778, -3e-07, 0.8624291), (-0.0, 0.040862, 0.0)),
    ('thigh_l', 'pelvis', (0.9924845, 0, 0, 0.1223706), (0.089, 0.027771, 0.046024)),
    ('calf_l', 'thigh_l', (0.0365859, -0.0001312, -4.8e-06, 0.9993305), (0.0, 0.40031, -0.0)),
    ('foot_l', 'calf_l', (-0.5290717, -0.0003281, 0.0003435, 0.848577), (-0.0, 0.42948, 0.0)),
    ('ball_l', 'foot_l', (0.0001371, -0.9643068, 0.2647871, 0.0004994), (0.0, 0.173301, -0.0)),
    ('ball_leaf_l', 'ball_l', (-0.0, -0.0, -0.0, 1), (0.0, 0.0789, -0.0)),
    ('thigh_r', 'pelvis', (0.9924845, 0, 0, 0.1223706), (-0.089, 0.027771, 0.046024)),
    ('calf_r', 'thigh_r', (0.0365859, -0.0001312, -4.8e-06, 0.9993305), (-0.0, 0.40031, -0.0)),
    ('foot_r', 'calf_r', (-0.5290717, -0.0003281, 0.0003435, 0.848577), (0.0, 0.42948, 0.0)),
    ('ball_r', 'foot_r', (0.0001371, -0.9643068, 0.2647871, 0.0004994), (-0.0, 0.173301, -0.0)),
    ('ball_leaf_r', 'ball_r', (-0.0, -0.0, -0.0, 1), (-0.0, 0.0789, -0.0)),
]

## The leaves this rig adds: (name, parent, kind).
TWIST_BONES = [(f"{limb}_twist_01_{side}", f"{limb}_{side}") for side in "lr" for limb in ("upperarm", "lowerarm", "thigh")]
SOCKETS = [
    ("socket_hand_r", "hand_r"),
    ("socket_hand_l", "hand_l"),
    ("socket_back", "spine_03"),
    ("socket_hip_l", "pelvis"),
    ("socket_hip_r", "pelvis"),
    ("socket_head", "Head"),
    ("socket_camera", "Head"),
]
IK_TARGETS = [("ik_foot_l", "root", "foot_l"), ("ik_foot_r", "root", "foot_r"), ("ik_hand_l", "root", "hand_l"), ("ik_hand_r", "root", "hand_r")]

FINGERS = ("thumb", "index", "middle", "ring", "pinky")


def quat_matrix(q):
    """The 3x3 rotation of a glTF quaternion (x, y, z, w)."""
    x, y, z, w = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def library_rest():
    """The reference body: {bone: (place, 3x3 orientation)} in the model's space, and {bone: parent}."""
    rest, parents = {}, {}
    for name, parent, rot, loc in LIBRARY_BONES:
        local = quat_matrix(rot)
        if parent is None:
            rest[name] = (np.array(loc, float), local)
        else:
            place, basis = rest[parent]
            rest[name] = (place + basis @ np.array(loc, float), basis @ local)
        parents[name] = parent
    return rest, parents


def build_rest(joints, hand_scale, sockets):
    """A body's whole rest: {bone: (place, orientation)} and {bone: parent}, in hierarchy order.

    `joints` places the left side's and the middle's main joints ({bone: (x, y, z)}; a right bone mirrors its left).
    Finger and toe-leaf bones keep the reference hand's layout, scaled by `hand_scale` about the hand bone (and the
    toe leaf by the foot's length). `sockets` places the seven sockets in the model's space.
    """
    library, parents = library_rest()
    rest = {}
    for name, parent, _rot, _loc in LIBRARY_BONES:
        basis = library[name][1]
        key = name[:-2] + "_l" if name.endswith("_r") else name
        if key in joints:
            place = np.array(joints[key], float)
            if name.endswith("_r"):
                place[0] = -place[0]
        elif name.split("_")[0] in FINGERS:
            hand = "hand_" + name[-1]
            place = rest[hand][0] + (library[name][0] - library[hand][0]) * hand_scale
        else:
            raise KeyError(f"the body gives no place for {name}")
        rest[name] = (place, basis)
    for name, parent in TWIST_BONES:
        limb = parent[:-2]
        child = {"upperarm": "lowerarm", "lowerarm": "hand", "thigh": "calf"}[limb] + parent[-2:]
        # The forearm's twist bone sits at the wrist; the others at their limb's own joint.
        place = rest[child][0] if limb == "lowerarm" else rest[parent][0]
        rest[name] = (place.copy(), rest[parent][1])
        parents[name] = parent
    model = np.eye(3)
    for name, parent in SOCKETS:
        place = np.array(sockets[name], float)
        if name == "socket_hand_r":
            # -X along the fingers, +Y toward the thumb's side: the kit's weapon axes (muzzle -X, top +Y).
            basis = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float)
        elif name == "socket_hand_l":
            basis = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
        else:
            basis = model
        rest[name] = (place, basis)
        parents[name] = parent
    for name, parent, twin in IK_TARGETS:
        rest[name] = (rest[twin][0].copy(), rest[twin][1])
        parents[name] = parent
    return rest, parents


def deform_bones():
    """The bones that carry skin: the library's without the root and the leaves, and the twist bones."""
    return [n for n, _p, _r, _l in LIBRARY_BONES if n != "root" and "leaf" not in n] + [n for n, _p in TWIST_BONES]
