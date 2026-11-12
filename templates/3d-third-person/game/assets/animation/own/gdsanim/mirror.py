"""A clip for the other side.

A left-and-right pair is one authored clip and its mirror. Mirroring is done on each bone's turn from the rest in
the character's space, which is reflected left to right and given to the bone of the other side, so it does not
depend on the bones' own axes (a glTF rig's left and right bones need not have mirrored axes, only a mirrored
rest).
"""

import numpy as np

from .rig import Rig

_FLIP = np.diag([-1.0, 1.0, 1.0])


def other(name: str) -> str:
    """The bone of the other side (`hand_l` for `hand_r`); a bone of the middle is its own."""
    if name.endswith("_l"):
        return name[:-2] + "_r"
    if name.endswith("_r"):
        return name[:-2] + "_l"
    return name


def mirror_pose(rig: Rig, pose: dict) -> dict:
    """The pose reflected left to right."""
    root = rig.parent["pelvis"]
    world = {root: rig.rest_rot[root]}
    for name in rig.bones:
        if name != root:
            world[name] = world[rig.parent[name]] @ pose["local"][name]
    flipped = {root: rig.rest_rot[root]}
    for name in rig.bones:
        if name == root:
            continue
        turn = world[name] @ rig.rest_rot[name].T
        flipped[other(name)] = _FLIP @ turn @ _FLIP @ rig.rest_rot[other(name)]
    local = {name: flipped[rig.parent[name]].T @ flipped[name] for name in rig.bones if name != root}
    local[root] = pose["local"].get(root, rig.local_rot[root])
    out = {"local": local, "pelvis": _FLIP @ pose["pelvis"], "miss": {}}
    if "places" in pose:
        root_rot = rig.rest_rot[root]
        inner = root_rot.T @ _FLIP @ root_rot
        out["places"] = {other(name): inner @ place for name, place in pose["places"].items()}
    return out


def mirror_frames(rig: Rig, frames: list) -> list:
    return [mirror_pose(rig, pose) for pose in frames]


def shift_loop(frames: list, by: int) -> list:
    """A loop started `by` frames later (its last pose stays its first): a gait's other half."""
    cycle = frames[:-1]
    turned = cycle[by:] + cycle[:by]
    return turned + [turned[0]]


def mirror_sides(value):
    """Swap `l` and `r` in a clip's records (contact times per foot, a footstep's foot, the foot it starts on)."""
    swap = {"l": "r", "r": "l"}
    if isinstance(value, dict):
        return {swap.get(k, k): mirror_sides(v) if k != "foot" else swap.get(v, v) for k, v in value.items()}
    if isinstance(value, list):
        return [mirror_sides(v) for v in value]
    return value
