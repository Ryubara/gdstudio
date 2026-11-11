"""The centre of mass, and the pelvis solved from it.

Weight reads when the centre of mass does what a body's does: it stays over the feet while standing, moves onto a
foot before the other is lifted, follows a free fall's arc in the air, and the body leans by its acceleration. A
description says where the centre of mass should be and `settle` moves the pelvis until it is there, so weight is an
input, like the footfalls.
"""

import math

import numpy as np

from .maths import FPS
from .rig import SIDES, Rig
from .solve import Solver

## Gravity, m/s2.
G = 9.81


def centre_of_mass(rig: Rig, pose: dict) -> np.ndarray:
    """The centre of mass of one pose on a rig."""
    rotation, translation = rig.arrays([pose])
    return rig.centre_of_mass(rig.world(rotation, translation))[0]


def settle(solver: Solver, spec: dict, over: tuple, stretch: float | None = None, rounds: int = 5) -> dict:
    """Solve `spec` with the pelvis moved level until the centre of mass is over the floor point `over` (x, z).
    With `stretch` the pelvis is also raised or lowered until the straighter leg is that share of its full
    length (hip to ankle over thigh plus calf), so the leg that carries the weight is as straight as the
    description says wherever the weight goes; without it the pelvis keeps the description's height. When `over`
    is a point in space (x, y, z) the pelvis is moved until the centre of mass is at it, height too: a gait gives
    the centre of mass's whole path (a free fall between a run's contacts). Returns the pose;
    `spec["pelvis"]["place"]` is left as solved."""
    rig = solver.rig
    place = np.array(spec["pelvis"]["place"], dtype=float)
    pose = None
    for _ in range(rounds):
        spec["pelvis"]["place"] = place
        pose = solver.solve(spec)
        com = centre_of_mass(rig, pose)
        if len(over) == 3:
            miss = np.asarray(over, dtype=float) - com
        else:
            miss = np.array([over[0] - com[0], 0.0, over[1] - com[2]])
        if stretch is not None and len(over) == 2:
            miss[1] = _stretch_miss(rig, spec, pose, stretch)
        if np.linalg.norm(miss) < 1e-5:
            break
        place = place + miss
    return pose


def _stretch_miss(rig: Rig, spec: dict, pose: dict, stretch: float) -> float:
    """How far the pelvis must rise for the straighter leg to be `stretch` of its length (a smooth maximum of
    the two legs, so the height has no corner where they swap)."""
    turn = rig.rest_rot[rig.parent["pelvis"]] @ pose["local"]["pelvis"] @ rig.rest_rot["pelvis"].T
    rises = []
    for s, _ in SIDES:
        hip = pose["pelvis"] + turn @ (rig.rest_pos["thigh_" + s] - rig.rest_pos["pelvis"])
        to = np.asarray(spec["leg"][s]["ankle"], dtype=float) - hip
        want = stretch * (rig.length["thigh_" + s] + rig.length["calf_" + s])
        level = math.hypot(to[0], to[2])
        rises.append(math.sqrt(max(want * want - level * level, 1e-9)) + to[1])
    # The lower of the two rises is the straighter leg's; a soft minimum of them.
    sharp = 400.0
    low = min(rises)
    return low - math.log(sum(math.exp(-sharp * (r - low)) for r in rises)) / sharp


def support_point(rig: Rig, legs: dict, share_left: float, ahead: float = 0.45) -> tuple:
    """The floor point `share_left` of the way from the right foot to the left, `ahead` of the way from each
    heel to its toe: where the centre of mass is when the left foot carries that share of the weight."""
    points = {}
    for s, _ in SIDES:
        sole = rig.sole[s]
        ankle = np.asarray(legs[s]["ankle"], dtype=float)
        heel = ankle + (sole["heel"] - sole["ankle"])
        toe = ankle + (sole["toe"] - sole["ankle"])
        points[s] = heel + ahead * (toe - heel)
    at = points["r"] + share_left * (points["l"] - points["r"])
    return float(at[0]), float(at[2])


def lean_for(acceleration: float) -> float:
    """Degrees a body leans into an acceleration (m/s2) to stay over its feet: `atan(a / g)`."""
    return math.degrees(math.atan2(acceleration, G))


def free_fall(height: float, rise_speed: float, frames: int) -> np.ndarray:
    """The height of a centre of mass in free fall on each of `frames` frames from `height` at `rise_speed`."""
    t = np.arange(frames) / FPS
    return height + rise_speed * t - 0.5 * G * t * t


def support_polygon(rig: Rig, world: np.ndarray, sides: tuple, frame_no: int) -> np.ndarray:
    """The floor points (x, z) under the soles of the planted feet on a frame: each sole's heel and toe, spread
    to the sole's width."""
    out = []
    for s in sides:
        points = rig.sole_points(world[frame_no : frame_no + 1], s)
        half = 0.035
        for key in ("heel", "ball", "toe"):
            p = points[key][0]
            out.append((p[0] - half, p[2]))
            out.append((p[0] + half, p[2]))
    return np.array(out)


def inside_margin(polygon: np.ndarray, point: tuple) -> float:
    """How far a point is inside the convex hull of floor points (m; negative is outside)."""
    hull = _hull(polygon)
    best = math.inf
    for i in range(len(hull)):
        a, b = hull[i], hull[(i + 1) % len(hull)]
        edge = b - a
        normal = np.array([-edge[1], edge[0]]) / max(np.linalg.norm(edge), 1e-12)
        best = min(best, float(np.dot(np.asarray(point) - a, normal)))
    return best


def _hull(points: np.ndarray) -> np.ndarray:
    """The convex hull, counter-clockwise (Andrew's monotone chain)."""
    pts = sorted(set(map(tuple, np.round(points, 9))))
    if len(pts) <= 2:
        return np.array(pts)

    def turn(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and turn(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and turn(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return np.array(lower[:-1] + upper[:-1])
