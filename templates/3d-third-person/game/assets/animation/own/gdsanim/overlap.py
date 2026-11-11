"""The overlap pass: parts that hang from other parts take their motion late.

A solved clip moves as one piece: the forearm turns on the frame the upper arm does. This pass runs each named bone
through a damped spring from the part it hangs from. On every frame the bone's target is where its solved pose puts
it on its parent as the parent really is (after the parent's own pass); the bone follows the target with a `lag`
(frames it trails a steady motion) and an `overshoot` (the share of a sudden change it swings past by). Bones are
done parents first, so the lag adds up along a chain: chest, neck, head; upper arm, forearm, hand.

A loop is run round its cycle until the spring's state at the seam stops changing, so the last pose is the first
and nothing kicks at the seam. A clip that plays once starts at rest on its first pose.

Limbs whose ends are planted (a foot on the floor, a hand on a ledge) are left out by the description: the pass
would pull them off their place.
"""

import math

import numpy as np

from . import FPS, maths
from .rig import Rig

## Spring steps a frame: enough that the stiffest spring a style can ask for (a lag of half a frame) is stable.
SUBSTEPS = 8
## The most rounds a loop is run for its seam to close, and the change at the seam that counts as closed (radians).
ROUNDS = 40
CLOSED = 1e-10


def spring_numbers(lag: float, overshoot: float) -> tuple:
    """The stiffness and damping (per second squared, per second) of a spring that trails a steady motion by
    `lag` frames and swings `overshoot` (0 to under 1) past a sudden change."""
    if overshoot <= 0.0:
        zeta = 1.0
    else:
        log = math.log(overshoot)
        zeta = -log / math.sqrt(math.pi**2 + log**2)
    omega = 2.0 * zeta / max(lag / FPS, 1e-6)
    return omega * omega, 2.0 * zeta * omega


def _follow(targets: list, lag: float, overshoot: float, loop: bool) -> list:
    """A bone's world rotations following its targets through the spring, one per frame."""
    if lag <= 0.0:
        return list(targets)
    stiffness, damping = spring_numbers(lag, overshoot)
    dt = 1.0 / (FPS * SUBSTEPS)
    count = len(targets) - 1 if loop else len(targets)
    rot, speed = targets[0].copy(), np.zeros(3)
    out = [None] * len(targets)
    for round_no in range(ROUNDS if loop else 1):
        start_rot, start_speed = rot.copy(), speed.copy()
        for f in range(count):
            out[f] = rot.copy()
            a = targets[f]
            b = targets[f + 1] if f + 1 < len(targets) else targets[f]
            step = maths.rotation_vector(a.T @ b)
            for sub in range(SUBSTEPS):
                goal = a @ maths.from_rotation_vector(step * ((sub + 1) / SUBSTEPS))
                error = maths.rotation_vector(goal @ rot.T)
                speed = speed + dt * (stiffness * error - damping * speed)
                rot = maths.from_rotation_vector(speed * dt) @ rot
        if not loop:
            break
        moved = np.linalg.norm(maths.rotation_vector(rot @ start_rot.T)) + np.linalg.norm(speed - start_speed) * dt
        if round_no > 0 and moved < CLOSED:
            break
    if loop:
        out[-1] = out[0].copy()
    return out


def apply(rig: Rig, frames: list, chains: dict, loop: bool) -> None:
    """Run the pass on a clip's poses in place. `chains` maps a bone to `(lag, overshoot)`; any bone not named
    keeps its solved rotation in its parent."""
    if not chains:
        return
    count = len(frames)
    root = rig.parent["pelvis"]
    actual = {root: [rig.rest_rot[root]] * count}
    for name in rig.bones:
        if name == root:
            continue
        parent = actual[rig.parent[name]]
        targets = [parent[f] @ frames[f]["local"][name] for f in range(count)]
        if name in chains:
            lag, overshoot = chains[name]
            actual[name] = _follow(targets, lag, overshoot, loop)
            for f in range(count):
                frames[f]["local"][name] = parent[f].T @ actual[name][f]
        else:
            actual[name] = targets


def chains_from(numbers: dict, bones: dict) -> dict:
    """The chains of a description from a style's overlap numbers (`Style.overlap`). `bones` maps a bone to the
    style's part name, or to `(part, share)` when several bones share a part's lag (the three spine bones each
    take a third of the chest's): `{"spine_03": ("chest", 1 / 3), "lowerarm_l": "forearm"}`. The style gives each
    part `[lag, overshoot]`."""
    out = {}
    for bone, part in bones.items():
        part, share = part if isinstance(part, tuple) else (part, 1.0)
        if part in numbers and numbers[part][0] > 0.0:
            out[bone] = (float(numbers[part][0]) * share, float(numbers[part][1]))
    return out


def follow(values: list, lag: float, overshoot: float, loop: bool) -> list:
    """A number a frame run through the same spring (a weight shift that settles, a curl that trails)."""
    if lag <= 0.0:
        return list(values)
    stiffness, damping = spring_numbers(lag, overshoot)
    dt = 1.0 / (FPS * SUBSTEPS)
    count = len(values) - 1 if loop else len(values)
    at, speed = float(values[0]), 0.0
    out = [0.0] * len(values)
    for round_no in range(ROUNDS if loop else 1):
        start = (at, speed)
        for f in range(count):
            out[f] = at
            a = values[f]
            b = values[f + 1] if f + 1 < len(values) else values[f]
            for sub in range(SUBSTEPS):
                goal = a + (b - a) * (sub + 1) / SUBSTEPS
                speed += dt * (stiffness * (goal - at) - damping * speed)
                at += speed * dt
        if not loop or (round_no > 0 and abs(at - start[0]) + abs(speed - start[1]) * dt < CLOSED):
            break
    if loop:
        out[-1] = out[0]
    return out
