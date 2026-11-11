"""Build the template's prone and crawl clips and export them to glTF (kit #1009).

GDStudio's own animation, made from nothing on the Quaternius universal rig (the female mannequin's skeleton, CC0),
because the Universal Animation Library has no prone or crawl clip. Every frame is solved by this script from a few
targets (where the pelvis lies, how the spine arches, where an elbow, a hand and a foot rest on the ground) and keyed
on the armature in Blender; nothing is copied from another game's or pack's motion. The only pose read from
another file is frame 0 of `Crouch_Idle_Loop`, where the two transitions have to start and end: GDStudio's own
crouch idle (`../own/locomotion.glb`, kit #1160), given as `--library`.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_prone_clips.py -- --model <mannequin_female.glb> --male <mannequin_male.glb>
        --library <own/locomotion.glb> --out <prone.glb> [--report <numbers.json>]

Axes: Blender's, 1 unit = 1 m, up +Z, the mannequin faces -Y (Godot's +Z) with its left at +X. The clips are in place
(the game moves the body) at 30 frames a second, the library's rate. The build fails before it exports when a loop
does not close, a planted elbow, hand or foot slides, the body sinks into the floor or rises over the prone height, a
transition does not start or end on the pose it joins, or a limb goes more than 5 mm into another part of the body on
either mannequin (`../limb_overlap.py`, the check every clip build of the template shares; `--male` names the other
mannequin).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

FPS = 30
CLIPS = (
    "Prone_Idle_Loop",
    "Crawl_Fwd_Loop",
    "Crouch_To_Prone",
    "Prone_To_Crouch",
)  # the frozen list of the file
TRUNK = ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head")
SIDES = (("l", 1.0), ("r", -1.0))

# Prone: where the body lies in the character's space. The origin is under the middle of the lying body, so a capsule
# laid along the facing covers it evenly.
PELVIS_FWD = 0.01  # the pelvis joint behind the origin
ELBOW_H = (
    0.041  # the elbow joint over the floor when the forearm rests on its outer edge
)
WRIST_H = 0.045  # the wrist joint over the floor when the hand lies flat
FIST_H = 0.0655  # the wrist joint over the floor when the fist rests on its outer edge, rolled with the forearm
ANKLE_H = 0.040  # the ankle joint over the floor when the foot lies on it
KNEE_H = 0.058  # the knee joint over the floor when the knee rests on it
TOE_H = 0.012  # the tip of the toe bone over the floor when the toes rest on it
SQUASH = (
    0.006  # how far the belly may sink into the floor (a body flattens where it lies)
)

# The forearms: how a person lies and crawls on them (the README's research). The elbows rest outside the shoulders
# and the forearms point inward, so the hands lie near the body's centre line in front of the head; the wrist turns
# the hand part of the way back toward straight ahead.
IDLE_FOREARM_IN = 29.5  # degrees a lying forearm points inward of straight ahead
IDLE_ELBOW_OUT = 0.095  # metres a lying elbow rests outside its shoulder
IDLE_STAGGER = (
    0.025  # metres the right elbow lies ahead of the middle and the left behind it
)
FOREARM_IN = 40.0  # degrees a planted forearm points inward in the crawl
FOREARM_SWING = 14.0  # degrees it points inward at the top of its swing, so the hand passes outside the other
FOREARM_ROLL = 45.0  # degrees a resting forearm is rolled onto its outer edge: the palm faces down and inward
# The fist a resting hand is closed into: degrees each finger joint bends from the knuckle to the tip, and the way
# each thumb bone points on the left hand in the rest pose's axes (mirrored for the right), which lays the thumb
# across the outside of the index and middle fingers.
# The numbers are the middle between the two mannequins (`fist_numbers`): the male's fingers are longer, so a
# fist closed on the female's palm puts his fingertips 6.7 mm into his and leaves his thumb 7 mm off his fingers.
FIST_CURL = {
    "index": (75.0, 88.0, 25.0),
    "middle": (75.0, 88.0, 20.0),
    "ring": (75.0, 88.0, 25.0),
    "pinky": (75.0, 98.0, 25.0),
}
FIST_THUMB = (
    (0.660, -0.472, -0.585),
    (0.0436, 0.0085, -0.0228),
    (0.0120, 0.0400, 0.0065),
)
FINGERS = ("index", "middle", "ring", "pinky")
AXES = [
    Vector(v)
    for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
]

# Crawl: one cycle is two pulls, the right elbow with the left foot and then the others.
CRAWL_FRAMES = 28
CRAWL_CLAV_PUSH = 11.0  # degrees the collarbones push the shoulders toward the floor, which holds the chest off it
CRAWL_ELBOW_UP = (
    0.0  # metres a crawling elbow rides higher than a lying one (the chest leans on it)
)
CRAWL_DUTY = 0.52  # the part of the cycle an elbow is planted
CRAWL_STRIDE = 0.30  # metres a planted elbow travels under the body
LEG_DUTY = 0.30  # the part of the cycle a foot is planted and pushes; then the leg drags straight
LEG_EASE = 0.025  # metres the foot gives as it stops pushing
LEG_DRAW = 0.70  # the phase the knee starts to draw up again

IDLE_FRAMES = 90
TO_PRONE_FRAMES = 27
TO_CROUCH_FRAMES = 30
HAND_FLOOR_LIMIT = 5.0  # millimetres a hand may be under the floor on either mannequin (skin pressed on it)
FIST_LIMIT_IN = 3.0  # millimetres a finger piece may be inside the palm or another finger in the fist
FIST_LIMIT_OFF = 5.0  # millimetres the thumb may be off the fingers it lies across
OVERLAP_LIMIT = 5.0  # millimetres a part of the body may be inside another (`../limb_overlap.py`, both mannequins)
# Coming up, where each hand and elbow wait beside the place they have in the crouch (forward, out to their own side
# and up, in metres) while the knee comes forward under them.
HAND_WAIT = {
    "l": ((0.0, 0.22, 0.10), (-0.05, 0.24, 0.10)),
    "r": ((0.0, 0.18, 0.08), (-0.04, 0.20, 0.08)),
}
HAND_WAIT_FRAMES = {
    "l": (13, 19, 26),
    "r": (14, 19, 25),
}  # the hand leaves the floor, waits, takes its place
STEP_LIFT = 0.13  # metres the right ankle is lifted half way between the crouch and the lying place
HAND_LIFT = 0.038  # metres a hand lifts off the floor while it closes
ROLL_FRAMES = (
    12,
    19,
)  # going down, the frames between which the forearms roll and the hands close
OPEN_FRAMES = (
    3,
    7,
)  # coming up, the frames between which the fists open and the palms turn down
KNEE_OPEN = 0.45  # how far the front knee opens to the side going down (added to its unit direction)


# ---- small maths ------------------------------------------------------------------------------------------------


def vec(fwd, left, up):
    """A point given as forward, left and up of the character, in Blender's axes."""
    return np.array([left, -fwd, up], dtype=float)


def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=float)


def rot_z(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=float)


def axis_angle(axis, a):
    return np.array(Matrix.Rotation(a, 3, tuple(unit(np.asarray(axis, dtype=float)))))


def frame(aim, side):
    """An orthonormal basis whose first axis is `aim` and whose second is `side` made square to it."""
    a = unit(aim)
    s = unit(side - a * np.dot(a, side))
    return np.column_stack([a, s, np.cross(a, s)])


def aim_turn(aim0, side0, aim, side):
    """The world rotation that takes the rest directions (aim0, side0) to (aim, side)."""
    return frame(aim, side) @ frame(aim0, side0).T


def trunk_turn(pitch, yaw=0.0, roll=0.0):
    """A trunk bone's turn from the standing rest, in degrees: roll about the spine, pitch forward (90 lies face
    down), then yaw about the vertical (positive turns the head to the character's left)."""
    return (
        rot_z(math.radians(yaw))
        @ rot_x(math.radians(pitch))
        @ rot_z(math.radians(roll))
    )


def to_quat(m):
    return Matrix(m.tolist()).to_quaternion()


def slerp(a, b, w):
    if w <= 0.0:
        return a
    if w >= 1.0:
        return b
    return np.array(to_quat(a).slerp(to_quat(b), w).to_matrix())


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def hermite(p0, p1, m0, m1, t):
    t2, t3 = t * t, t * t * t
    return (
        (2 * t3 - 3 * t2 + 1) * p0
        + (t3 - 2 * t2 + t) * m0
        + (-2 * t3 + 3 * t2) * p1
        + (t3 - t2) * m1
    )


def keyed(keys, frame_no):
    """A value keyed at frames, read at `frame_no` on a monotone cubic through the keys (no overshoot, and flat
    between two equal keys, so a planted target stays where it is)."""
    xs = [k[0] for k in keys]
    ys = [np.atleast_1d(np.asarray(k[1], dtype=float)) for k in keys]
    if frame_no <= xs[0]:
        return ys[0] if len(ys[0]) > 1 else float(ys[0][0])
    if frame_no >= xs[-1]:
        return ys[-1] if len(ys[-1]) > 1 else float(ys[-1][0])
    n = len(xs)
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [d[0]] + [
        np.where(
            d[i - 1] * d[i] > 0, 2 * d[i - 1] * d[i] / (d[i - 1] + d[i] + 1e-30), 0.0
        )
        for i in range(1, n - 1)
    ]
    m.append(d[-1])
    m[0] = np.zeros_like(m[0])
    m[-1] = np.zeros_like(m[-1])
    i = max(j for j in range(n - 1) if xs[j] <= frame_no)
    h = xs[i + 1] - xs[i]
    out = hermite(ys[i], ys[i + 1], m[i] * h, m[i + 1] * h, (frame_no - xs[i]) / h)
    return out if len(out) > 1 else float(out[0])


def keyed_turn(keys, frame_no):
    """A rotation keyed at frames as 3x3 matrices, read through `keyed` on its quaternion."""
    quats, last = [], None
    for f, m in keys:
        q = np.array(to_quat(m))
        if last is not None and np.dot(q, last) < 0:
            q = -q
        quats.append((f, q))
        last = q
    q = keyed(quats, frame_no)
    return np.array(Quaternion(tuple(q)).normalized().to_matrix())


# ---- the rig ----------------------------------------------------------------------------------------------------


class Rig:
    """The mannequin's rest skeleton and skin as arrays, so a pose is solved and measured without touching Blender."""

    def __init__(self, arm, mesh):
        assert np.allclose(np.array(arm.matrix_world), np.eye(4), atol=1e-6), (
            "the armature is not at the origin"
        )
        bones = list(arm.data.bones)
        depth = {b.name: len(b.parent_recursive) for b in bones}
        bones.sort(key=lambda b: depth[b.name])
        self.names = [b.name for b in bones]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.rest = {b.name: np.array(b.matrix_local) for b in bones}
        self.rest_rot = {n: m[:3, :3] for n, m in self.rest.items()}
        self.rest_pos = {n: m[:3, 3] for n, m in self.rest.items()}
        self.local = {}
        for n in self.names:
            p = self.parent[n]
            self.local[n] = (
                np.linalg.inv(self.rest[p]) @ self.rest[n] if p else self.rest[n]
            )
        self.local_rot = {n: m[:3, :3] for n, m in self.local.items()}
        self.local_pos = {n: m[:3, 3] for n, m in self.local.items()}
        self.len = {}
        for s, _ in SIDES:
            self.len["upperarm_" + s] = np.linalg.norm(
                self.rest_pos["lowerarm_" + s] - self.rest_pos["upperarm_" + s]
            )
            self.len["lowerarm_" + s] = np.linalg.norm(
                self.rest_pos["hand_" + s] - self.rest_pos["lowerarm_" + s]
            )
            self.len["thigh_" + s] = np.linalg.norm(
                self.rest_pos["calf_" + s] - self.rest_pos["thigh_" + s]
            )
            self.len["calf_" + s] = np.linalg.norm(
                self.rest_pos["foot_" + s] - self.rest_pos["calf_" + s]
            )
        world = np.array(mesh.matrix_world)
        co = np.array([v.co[:] for v in mesh.data.vertices])
        self.verts = co @ world[:3, :3].T + world[:3, 3]
        index = {n: i for i, n in enumerate(self.names)}
        group = {g.index: index[g.name] for g in mesh.vertex_groups if g.name in index}
        self.weights = np.zeros((len(co), len(self.names)))
        for v in mesh.data.vertices:
            for g in v.groups:
                if g.group in group:
                    self.weights[v.index, group[g.group]] = g.weight
        self.weights /= self.weights.sum(axis=1, keepdims=True)
        self.owner = np.array(self.names)[self.weights.argmax(axis=1)]
        mesh.data.calc_loop_triangles()
        self.tris = np.array([t.vertices[:] for t in mesh.data.loop_triangles])
        self.rest_inv = np.stack([np.linalg.inv(self.rest[n]) for n in self.names])

    def world(self, local_rot, pelvis_pos):
        """World matrices of a pose given as local rotations and the pelvis's place."""
        out = {}
        for n in self.names:
            p = self.parent[n]
            m = np.eye(4)
            if p is None:
                m[:3, :3] = local_rot[n]
                m[:3, 3] = self.local_pos[n]
            else:
                m[:3, :3] = out[p][:3, :3] @ local_rot[n]
                m[:3, 3] = (
                    pelvis_pos
                    if n == "pelvis"
                    else out[p][:3, :3] @ self.local_pos[n] + out[p][:3, 3]
                )
            out[n] = m
        return out

    def skin(self, world):
        """The mesh's vertices in a pose (linear blend skinning, as Blender and Godot do it)."""
        mats = np.stack([world[n] for n in self.names]) @ self.rest_inv
        homo = np.concatenate([self.verts, np.ones((len(self.verts), 1))], axis=1)
        moved = np.einsum("bij,vj->vbi", mats[:, :3, :], homo)
        return np.einsum("vb,vbi->vi", self.weights, moved)

    def lowest(self, skinned, prefixes):
        mask = np.zeros(len(self.owner), dtype=bool)
        for prefix in prefixes:
            mask |= np.char.startswith(self.owner, prefix)
        return float(skinned[mask, 2].min())


# ---- the solver -------------------------------------------------------------------------------------------------


class Solver:
    """Solves one pose from targets. `spec` keys:

    - `pelvis_pos`: the pelvis joint in the character's space;
    - `trunk`: for each bone of `TRUNK`, its turn from the standing rest as (pitch, yaw, roll) in degrees or as a
      3x3 matrix;
    - `comply`: when true, the three spine bones pitch and roll by the amount that puts each shoulder exactly one
      upper arm away from its elbow target (the chest rides on the planted elbows);
    - `clav`: for each side, how far the collarbone lifts toward the head and pushes toward the chest, in degrees;
    - `arm`: for each side, `elbow` and `wrist` targets (the elbow leads, for a forearm on the floor) or `wrist` and
      `pole` (two-bone IK, for a hand that carries weight), with `palm` (the way the palm faces) and `fingers`;
    - `leg`: for each side, the `ankle` target, `pole` (the way the knee points), `pole_at` (a point it points at)
      or `knee_out` with `knee_z`, `flex` (degrees the foot points away from the shin's square: 0 stands on the
      sole, 80 lays the instep down) and `foot_world` (a world turn the foot keeps, with its weight);
    - `curl`: degrees every finger joint bends.
    """

    def __init__(self, rig):
        self.rig = rig
        self.warm = np.zeros(2)
        self.miss = {}
        # the fist's thumb, as each thumb bone's turn from its parent
        self.fist_thumb = {}
        for s, sign in SIDES:
            parent = rig.rest_rot["hand_" + s]
            for joint, aim in zip(("01", "02", "03"), FIST_THUMB):
                name = f"thumb_{joint}_{s}"
                rest = rig.rest_rot[name]
                want = unit(np.array([sign * aim[0], aim[1], aim[2]]))
                turn = np.array(
                    Vector(rest[:, 1]).rotation_difference(Vector(want)).to_matrix()
                )
                self.fist_thumb[name] = parent.T @ turn @ rest
                parent = turn @ rest

    def _place(self, world, name, rot):
        rig = self.rig
        p = rig.parent[name]
        m = np.eye(4)
        m[:3, :3] = rot
        m[:3, 3] = world[p][:3, :3] @ rig.local_pos[name] + world[p][:3, 3]
        world[name] = m

    def _trunk_turn(self, spec, name, give):
        value = spec["trunk"][name]
        if isinstance(value, np.ndarray):
            return value
        pitch, yaw, roll = value
        share = {"spine_01": 1 / 3, "spine_02": 2 / 3, "spine_03": 1.0}.get(name, 0.0)
        return trunk_turn(pitch + share * give[0], yaw, roll + share * give[1])

    def _trunk(self, spec, give):
        rig = self.rig
        world = {"root": rig.rest["root"].copy()}
        turns = {}
        for name in TRUNK:
            turns[name] = self._trunk_turn(spec, name, give)
            self._place(world, name, turns[name] @ rig.rest_rot[name])
            if name == "pelvis":
                world[name][:3, 3] = spec["pelvis_pos"]
        for s, sign in SIDES:
            lift, push = (
                math.radians(v) for v in spec.get("clav", {}).get(s, (0.0, 0.0))
            )
            turn = axis_angle((0, -sign, 0), lift) @ axis_angle((0, 0, -sign), push)
            self._place(
                world,
                "clavicle_" + s,
                turns["spine_03"] @ turn @ rig.rest_rot["clavicle_" + s],
            )
            self._place(
                world, "upperarm_" + s, world["clavicle_" + s][:3, :3]
            )  # the place only; turned below
        return world

    def _shoulder_miss(self, spec, give):
        world = self._trunk(spec, give)
        out = []
        for s, _ in SIDES:
            arm = spec["arm"][s]
            reach = np.linalg.norm(arm["elbow"] - world["upperarm_" + s][:3, 3])
            out.append(reach - self.rig.len["upperarm_" + s])
        return np.array(out)

    def _comply(self, spec):
        give = self.warm.copy()
        for _ in range(12):
            miss = self._shoulder_miss(spec, give)
            if np.abs(miss).max() < 1e-6:
                break
            jac = np.zeros((2, 2))
            for k in range(2):
                step = np.zeros(2)
                step[k] = 0.05
                jac[:, k] = (self._shoulder_miss(spec, give + step) - miss) / 0.05
            delta = np.linalg.solve(jac + 1e-9 * np.eye(2), -miss)
            give = give + np.clip(delta, -6.0, 6.0)
        self.warm = give
        return give

    def _arm(self, world, spec, s, sign):
        rig = self.rig
        arm = spec["arm"][s]
        upper, lower, hand = "upperarm_" + s, "lowerarm_" + s, "hand_" + s
        shoulder = world[upper][:3, 3]
        len_u, len_f = rig.len[upper], rig.len[lower]
        if "elbow" in arm:
            aim_u = unit(arm["elbow"] - shoulder)
            self.miss["elbow_" + s] = abs(
                np.linalg.norm(arm["elbow"] - shoulder) - len_u
            )
            elbow = shoulder + len_u * aim_u
            aim_f = unit(arm["wrist"] - elbow)
            hinge = unit(np.cross(aim_u, aim_f))
        else:
            to = arm["wrist"] - shoulder
            dist = min(np.linalg.norm(to), (len_u + len_f) * 0.999)
            self.miss["wrist_" + s] = max(np.linalg.norm(to) - dist, 0.0)
            along = unit(to)
            a = (len_u**2 - len_f**2 + dist**2) / (2 * dist)
            toward = arm["pole_at"] - shoulder if "pole_at" in arm else arm["pole"]
            pole = unit(toward - along * np.dot(along, toward))
            elbow = shoulder + a * along + math.sqrt(max(len_u**2 - a**2, 0.0)) * pole
            aim_u = unit(elbow - shoulder)
            aim_f = unit(shoulder + dist * along - elbow)
            hinge = unit(np.cross(pole, along))
        rest_u = unit(rig.rest_pos[lower] - rig.rest_pos[upper])
        rest_f = unit(rig.rest_pos[hand] - rig.rest_pos[lower])
        rest_g = unit(rig.rest_pos["middle_01_" + s] - rig.rest_pos[hand])
        rest_hinge = unit(np.cross(rest_u, (0.0, -1.0, 0.0)))
        palm0 = np.array([0.0, 0.0, -1.0])
        palm = unit(arm.get("palm", np.array([0.0, 0.0, -1.0])))
        fingers = arm.get("fingers")
        fingers = (
            unit(aim_f - palm * np.dot(aim_f, palm))
            if fingers is None
            else unit(fingers)
        )
        self._place(
            world,
            upper,
            aim_turn(rest_u, rest_hinge, aim_u, hinge) @ rig.rest_rot[upper],
        )
        self._place(
            world, lower, aim_turn(rest_f, palm0, aim_f, palm) @ rig.rest_rot[lower]
        )
        self._place(
            world, hand, aim_turn(rest_g, palm0, fingers, palm) @ rig.rest_rot[hand]
        )

    def _leg(self, world, spec, s, sign):
        rig = self.rig
        leg = spec["leg"][s]
        thigh, calf, foot = "thigh_" + s, "calf_" + s, "foot_" + s
        self._place(world, thigh, world["pelvis"][:3, :3])
        hip = world[thigh][:3, 3]
        len_t, len_c = rig.len[thigh], rig.len[calf]
        to = leg["ankle"] - hip
        dist = min(np.linalg.norm(to), (len_t + len_c) * 0.999)
        self.miss["ankle_" + s] = max(np.linalg.norm(to) - dist, 0.0)
        along = unit(to)
        a = (len_t**2 - len_c**2 + dist**2) / (2 * dist)
        bend = math.sqrt(max(len_t**2 - a**2, 0.0))
        if "pole_at" in leg:
            pole = unit(
                leg["pole_at"] - hip - along * np.dot(along, leg["pole_at"] - hip)
            )
        elif "pole" in leg:
            pole = unit(leg["pole"] - along * np.dot(along, leg["pole"]))
        else:
            out = unit(leg["knee_out"] - along * np.dot(along, leg["knee_out"]))
            down = np.cross(along, out)
            down = down if down[2] < 0 else -down
            want = (leg["knee_z"] - hip[2] - a * along[2]) / (
                max(bend, 1e-6) * min(down[2], -1e-6)
            )
            drop = float(np.clip(want, -0.9, 0.9)) * smooth(
                (bend - 0.02) / 0.10
            ) + 0.5 * (1.0 - smooth((bend - 0.02) / 0.10))
            pole = unit(out * math.sqrt(max(1.0 - drop * drop, 0.0)) + down * drop)
        knee = hip + a * along + bend * pole
        aim_t = unit(knee - hip)
        aim_c = unit(hip + dist * along - knee)
        hinge = unit(np.cross(pole, along))
        rest_t = unit(rig.rest_pos[calf] - rig.rest_pos[thigh])
        rest_c = unit(rig.rest_pos[foot] - rig.rest_pos[calf])
        hinge0 = np.array([1.0, 0.0, 0.0])
        self._place(
            world, thigh, aim_turn(rest_t, hinge0, aim_t, hinge) @ rig.rest_rot[thigh]
        )
        self._place(
            world, calf, aim_turn(rest_c, hinge0, aim_c, hinge) @ rig.rest_rot[calf]
        )
        cap = unit(
            np.cross(aim_c, hinge)
        )  # the way the kneecap faces, square to the shin
        flex = math.radians(leg.get("flex", 0.0))
        toe = math.cos(flex) * cap + math.sin(flex) * aim_c
        sole = -math.sin(flex) * cap + math.cos(flex) * aim_c
        if "foot_roll" in leg:
            roll = axis_angle(toe, math.radians(leg["foot_roll"]))
            sole = roll @ sole
        turned = (
            aim_turn(np.array([0.0, -1.0, 0.0]), np.array([0.0, 0.0, -1.0]), toe, sole)
            @ rig.rest_rot[foot]
        )
        if (
            "foot_world" in leg
        ):  # a foot that stands on the floor keeps its own turn while the shin moves
            held, weight = leg["foot_world"]
            turned = slerp(turned, held, weight)
        self._place(world, foot, turned)
        self._toes(world, s)

    def _toes(self, world, s):
        """Bend the toes up where they would go into the floor (a foot on its toes, or lying on them)."""
        rig = self.rig
        foot, ball, leaf = "foot_" + s, "ball_" + s, "ball_leaf_" + s
        self._place(world, ball, world[foot][:3, :3] @ rig.local_rot[ball])
        joint = world[ball][:3, 3]
        rest = world[ball][:3, :3] @ rig.local_pos[leaf]
        axis = world[foot][:3, :3] @ rig.rest_rot[foot].T @ np.array([1.0, 0.0, 0.0])
        floor = TOE_H - joint[2]
        if rest[2] >= floor:
            return
        best = None
        for step in range(1, 361):
            for angle in (math.radians(step * 0.25), -math.radians(step * 0.25)):
                if (axis_angle(axis, angle) @ rest)[2] >= floor:
                    best = angle
                    break
            if best is not None:
                break
        if best is None:
            return
        self._place(world, ball, axis_angle(axis, best) @ world[ball][:3, :3])

    def solve(self, spec):
        """The pose as local rotations for every bone, and the pelvis's place."""
        rig = self.rig
        self.miss = {}
        give = self._comply(spec) if spec.get("comply") else np.zeros(2)
        world = self._trunk(spec, give)
        for s, sign in SIDES:
            self._arm(world, spec, s, sign)
            self._leg(world, spec, s, sign)
        curl = spec.get("curl", {})
        fist = spec.get("fist", {})
        local = {}
        for n in rig.names:
            p = rig.parent[n]
            if n in world:
                local[n] = (
                    world[p][:3, :3].T @ world[n][:3, :3] if p else world[n][:3, :3]
                )
                continue
            rot = rig.local_rot[n]
            side = n[-1]
            closed = fist.get(side, 0.0)
            finger, _, joint = n[:-2].partition("_")
            if finger in FINGERS and joint in ("01", "02", "03"):
                # a finger joint bends toward the palm about its own hinge, which the right hand's bones mirror
                bend = curl.get(side, 0.0)
                bend += closed * (FIST_CURL[finger][int(joint) - 1] - bend)
                way = math.copysign(1.0, rig.rest_rot[n][1, 0]) * (
                    1.0 if side == "l" else -1.0
                )
                rot = rot @ rot_x(math.radians(way * bend))
            elif finger == "thumb" and joint in ("02", "03"):
                rot = slerp(
                    rot @ rot_x(math.radians(curl.get(side, 0.0) * 0.5)),
                    self.fist_thumb[n],
                    closed,
                )
            elif finger == "thumb" and joint == "01":
                # the rest thumb points 47 degrees under the palm: lay it out beside the palm for a hand on the floor
                lay = rot_x(
                    math.radians(-37.0 * spec.get("thumb_flat", {}).get(side, 0.0))
                )
                rot = slerp(
                    rig.rest_rot["hand_" + side].T @ lay @ rig.rest_rot[n],
                    self.fist_thumb[n],
                    closed,
                )
            local[n] = rot
            self._place(world, n, world[p][:3, :3] @ rot)
        return {
            "local": local,
            "pelvis": np.array(spec["pelvis_pos"], dtype=float),
            "miss": dict(self.miss),
            "give": give,
        }


def blend(a, b, w):
    """Two poses mixed bone by bone in local space."""
    if w <= 0.0:
        return a
    if w >= 1.0:
        return b
    return {
        "local": {n: slerp(a["local"][n], b["local"][n], w) for n in a["local"]},
        "pelvis": a["pelvis"] * (1 - w) + b["pelvis"] * w,
        "miss": {},
    }


# ---- the clips --------------------------------------------------------------------------------------------------


def prone_base(pelvis_up):
    """The targets of the lying body both loops start from: propped on the elbows, legs straight behind."""
    spec = {
        "pelvis_pos": vec(PELVIS_FWD, 0.0, pelvis_up),
        "trunk": {
            "pelvis": (89.0, 0.0, 0.0),
            "spine_01": (85.0, 0.0, 0.0),
            "spine_02": (76.0, 0.0, 0.0),
            "spine_03": (66.0, 0.0, 0.0),
            "neck_01": (46.0, 0.0, 0.0),
            "Head": (24.0, 0.0, 0.0),
        },
        "comply": True,
        "clav": {"l": (8.0, 4.0), "r": (8.0, 4.0)},
        "arm": {},
        "leg": {},
        "curl": {"l": 2.0, "r": 2.0},
        "thumb_flat": {"l": 1.0, "r": 1.0},
        "fist": {"l": 1.0, "r": 1.0},
    }
    return spec


def idle_spec(rig, phase, pelvis_up, anchor):
    """Prone idle: one slow breath over the loop, the head drifting a little, elbows and hands where they lie."""
    breath = math.sin(2 * math.pi * phase)
    late = math.sin(2 * math.pi * (phase - 0.12))
    look = math.sin(2 * math.pi * phase + 1.1)
    spec = prone_base(pelvis_up)
    trunk = spec["trunk"]
    trunk["spine_01"] = (85.0 - 0.5 * breath, 0.0, 0.0)
    trunk["spine_02"] = (76.0 - 1.0 * breath, 0.6 * look, 0.0)
    trunk["spine_03"] = (66.0 - 1.4 * breath, 1.0 * look, 0.0)
    trunk["neck_01"] = (46.0 - 1.2 * late, 2.0 * look, 0.0)
    trunk["Head"] = (17.0 - 1.6 * late, 4.0 * look, 0.6 * look)
    for s, sign in SIDES:
        spec["clav"][s] = (8.0 + 1.5 * breath, 4.0 + 1.2 * breath)
        elbow = vec(
            anchor["shoulder_fwd"] + 0.035 - sign * IDLE_STAGGER,
            sign * (anchor["shoulder_left"] + IDLE_ELBOW_OUT),
            ELBOW_H,
        )
        reach = math.radians(IDLE_FOREARM_IN)
        flat = math.sqrt(rig.len["lowerarm_" + s] ** 2 - (ELBOW_H - FIST_H) ** 2)
        wrist = elbow + vec(
            flat * math.cos(reach), -sign * flat * math.sin(reach), FIST_H - ELBOW_H
        )
        spec["arm"][s] = forearm_on_floor(elbow, wrist, sign, IDLE_FOREARM_IN)
        spec["leg"][s] = lying_leg(rig, sign, anchor)
    return spec


def forearm_on_floor(elbow, wrist, sign, inward, roll=FOREARM_ROLL):
    """An arm resting on its forearm, which points `inward` degrees toward the body's centre line and is rolled
    `roll` degrees onto its outer edge (the little finger's side down, the thumb's side up), so the palm faces
    down and in toward the other arm. The hand lies in line with the forearm: a straight wrist carries weight
    longest."""
    reach, turn = math.radians(inward), math.radians(roll)
    medial = vec(-math.sin(reach), -sign * math.cos(reach), 0.0)
    return {
        "elbow": elbow,
        "wrist": wrist,
        "palm": math.cos(turn) * vec(0.0, 0.0, -1.0) + math.sin(turn) * medial,
    }


def lying_leg(rig, sign, anchor, spread=0.13):
    """A straight leg lying behind the body, the instep on the floor and the toes a little out."""
    reach = (rig.len["thigh_l"] + rig.len["calf_l"]) * 0.992
    drop = anchor["hip_up"] - ANKLE_H
    side = spread - anchor["hip_left"]
    back = math.sqrt(reach**2 - drop**2 - side**2)
    return {
        "ankle": vec(anchor["hip_fwd"] - back, sign * spread, ANKLE_H),
        "pole": vec(0.0, sign * 0.45, -1.0),
        "flex": 62.0,
    }


def crawl_spec(rig, phase, pelvis_up, anchor):
    """Low crawl: the right elbow and the left foot plant together and the body is pulled over them, then the
    left elbow and the right foot. At phase 0 the right elbow has just planted at its reach and the left knee is
    drawn up."""
    turn = 2 * math.pi * phase
    c, s2 = math.cos(turn), math.sin(turn)
    spec = prone_base(pelvis_up)
    spec["pelvis_pos"] = vec(
        PELVIS_FWD + 0.008 * math.sin(2 * turn - 0.6), -0.012 * c, pelvis_up
    )
    trunk = spec["trunk"]
    trunk["pelvis"] = (89.0, -6.0 * c, 5.0 * c)
    trunk["spine_01"] = (86.0, -3.0 * c, 3.0 * c)
    trunk["spine_02"] = (80.0, 2.0 * c, 0.0)
    trunk["spine_03"] = (72.0, 7.0 * c, 0.0)
    trunk["neck_01"] = (50.0, 2.5 * c, 0.0)
    trunk["Head"] = (24.0 + 1.5 * math.cos(2 * turn), -1.5 * c, 1.5 * s2)
    travel = CRAWL_STRIDE
    for s, sign in SIDES:
        # the right arm and the left leg lead the cycle; the other pair is half a cycle behind
        arm_phase = (phase + (0.0 if s == "r" else 0.5)) % 1.0
        leg_phase = (phase + (0.0 if s == "l" else 0.5)) % 1.0
        fwd, lift, _ = stroke(arm_phase, travel)
        swing = (
            lift**0.45
        )  # the forearm opens out sooner than it rises, clear of its own shoulder
        elbow = vec(
            anchor["shoulder_fwd"] + 0.17 - travel + fwd,
            sign * (anchor["shoulder_left"] + 0.085 + 0.03 * swing),
            ELBOW_H + CRAWL_ELBOW_UP + 0.05 * lift,
        )
        inward = FOREARM_IN - (FOREARM_IN - FOREARM_SWING) * swing
        reach = math.radians(inward)
        rise = FIST_H - ELBOW_H - CRAWL_ELBOW_UP + 0.035 * lift
        flat = math.sqrt(rig.len["lowerarm_" + s] ** 2 - rise**2)
        wrist = elbow + vec(
            flat * math.cos(reach), -sign * flat * math.sin(reach), rise
        )
        spec["arm"][s] = forearm_on_floor(elbow, wrist, sign, inward)
        spec["clav"][s] = (10.0 + 8.0 * (fwd / travel - 0.5), CRAWL_CLAV_PUSH)
        spec["fist"][s] = (
            1.0 - 0.12 * lift
        )  # the fist loosens a little while it is carried

        fwd, lift, push = leg_stroke(leg_phase)
        straight = lying_leg(rig, sign, anchor, spread=0.19)
        ankle = straight["ankle"] + vec(
            fwd, sign * 0.03 * lift, 0.012 + 0.012 * lift + 0.05 * push
        )
        spec["leg"][s] = {
            "ankle": ankle,
            "knee_out": vec(0.0, sign, 0.0),
            "knee_z": KNEE_H + 0.01 * lift,
            "flex": 62.0 - 30.0 * push,
        }
    return spec


def stroke(phase, travel):
    """One planted point's way through a cycle: how far ahead of its rearmost place it is, how lifted (0 to 1) and
    whether it is planted. Planted, it goes back at one speed; lifted, it returns leaving and landing at that
    speed, so nothing snaps."""
    duty = CRAWL_DUTY
    if phase < duty:
        return travel * (1.0 - phase / duty), 0.0, True
    t = (phase - duty) / (1.0 - duty)
    slope = -travel / duty * (1.0 - duty)
    return hermite(0.0, travel, slope, slope, t), math.sin(math.pi * t) ** 2, False


def leg_stroke(phase):
    """A foot's way through a cycle: how far ahead of its place behind the body it is, how lifted, and how hard
    it pushes (0 to 1). It plants with the knee drawn up and pushes back at the body's speed, gives a little as
    it stops, drags straight behind the body, then draws up again."""
    speed = CRAWL_STRIDE / CRAWL_DUTY  # metres a unit of phase
    reach = speed * LEG_DUTY + LEG_EASE
    stop = LEG_DUTY + 2.0 * LEG_EASE / speed
    if phase < LEG_DUTY:
        return reach - speed * phase, 0.0, 1.0
    if phase < stop:
        t = (phase - LEG_DUTY) / (stop - LEG_DUTY)
        return LEG_EASE * (1.0 - t) ** 2, 0.0, 1.0 - smooth(t)
    if phase < LEG_DRAW:
        return 0.0, 0.0, 0.0
    t = (phase - LEG_DRAW) / (1.0 - LEG_DRAW)
    return (
        hermite(0.0, reach, 0.0, -speed * (1.0 - LEG_DRAW), t),
        math.sin(math.pi * t) ** 2,
        smooth((t - 0.55) / 0.45),
    )


def settle(
    rig, solver, make, anchor, groups=("pelvis", "spine_01", "spine_02", "thigh")
):
    """Solve a lying pose with the belly resting on the floor: the pelvis's height is moved until the lowest vertex
    of the belly and thighs sinks `SQUASH` into it."""
    up = anchor["pelvis_up"]
    pose = None
    for _ in range(4):
        pose = solver.solve(make(up))
        low = rig.lowest(rig.skin(rig.world(pose["local"], pose["pelvis"])), groups)
        if abs(low + SQUASH) < 2e-4:
            break
        up -= low + SQUASH
    pose["pelvis_up"] = up
    return pose


def measure_anchor(rig, solver):
    """Where the shoulders and hips are in the prone base pose: the clips place elbows and feet from them."""
    anchor = {
        "pelvis_up": 0.11,
        "shoulder_fwd": 0.3,
        "shoulder_left": 0.15,
        "hip_fwd": PELVIS_FWD,
        "hip_left": 0.09,
        "hip_up": 0.1,
    }
    for _ in range(3):
        pose = settle(
            rig,
            solver,
            lambda up, anchor=anchor: idle_spec(rig, 0.0, up, anchor),
            anchor,
        )
        world = rig.world(pose["local"], pose["pelvis"])
        shoulder, hip = world["upperarm_l"][:3, 3], world["thigh_l"][:3, 3]
        other = world["upperarm_r"][:3, 3]
        anchor = {
            "pelvis_up": pose["pelvis_up"],
            "shoulder_fwd": -(shoulder[1] + other[1]) / 2,
            "shoulder_left": shoulder[0],
            "hip_fwd": -hip[1],
            "hip_left": hip[0],
            "hip_up": hip[2],
        }
    return anchor


def build_idle(rig, solver, anchor):
    frames = []
    for f in range(IDLE_FRAMES):
        frames.append(
            settle(
                rig,
                solver,
                lambda up, f=f: idle_spec(rig, f / IDLE_FRAMES, up, anchor),
                anchor,
            )
        )
    return frames + [frames[0]]


def build_crawl(rig, solver, anchor):
    frames = []
    solver.warm = np.zeros(2)
    for f in (
        list(range(CRAWL_FRAMES)) * 2
    ):  # twice round, so the solver's warm start is the loop's own
        frames.append(
            settle(
                rig,
                solver,
                lambda up, f=f: crawl_spec(rig, f / CRAWL_FRAMES, up, anchor),
                anchor,
            )
        )
    frames = frames[CRAWL_FRAMES:]
    return frames + [frames[0]]


ARM_BONES = (
    "clavicle",
    "upperarm",
    "lowerarm",
    "hand",
    "index",
    "middle",
    "ring",
    "pinky",
    "thumb",
)
LEG_BONES = ("thigh", "calf", "foot", "ball")


def mix_limbs(solved, base, arm_w, leg_w):
    """A solved pose with its arms and legs mixed toward a base pose's, in local space."""
    local = dict(solved["local"])
    for n in local:
        if n.startswith(ARM_BONES) and arm_w < 1.0:
            local[n] = slerp(base["local"][n], solved["local"][n], arm_w)
        elif n.startswith(LEG_BONES) and leg_w < 1.0:
            local[n] = slerp(base["local"][n], solved["local"][n], leg_w)
    return {"local": local, "pelvis": solved["pelvis"], "miss": solved["miss"]}


def transition(rig, solver, count, keys, limbs_from, anchor_pose):
    """A clip solved from keyed targets. `keys` holds, by frame: the pelvis's place, each trunk bone's turn, each
    wrist, elbow hint, ankle, the way each knee points, the feet's flex and held world turn, and three weights: `arm_w` and
    `leg_w` (1 uses the solved limb, 0 the limb of `limbs_from`) and `anchor_w` (1 is `anchor_pose` whole)."""
    frames = []
    for f in range(count + 1):
        spec = {
            "pelvis_pos": keyed(keys["pelvis"], f),
            "trunk": {n: keyed_turn(keys["trunk"][n], f) for n in TRUNK},
            "clav": {s: tuple(keyed(keys["clav"], f)) for s, _ in SIDES},
            "arm": {},
            "leg": {},
            "curl": {s: keyed(keys["curl"], f) for s, _ in SIDES},
            "thumb_flat": {s: keyed(keys["thumb_flat"], f) for s, _ in SIDES},
            "fist": {s: keyed(keys["fist"], f) for s, _ in SIDES},
        }
        for s, _ in SIDES:
            spec["arm"][s] = {
                "wrist": keyed(keys["wrist"][s], f),
                "pole_at": keyed(keys["elbow"][s], f),
                "palm": keyed(keys["palm"][s], f),
                "fingers": keyed(keys["fingers"][s], f),
            }
            spec["leg"][s] = {
                "ankle": keyed(keys["ankle"][s], f),
                "pole": keyed(keys["knee"][s], f),
                "flex": keyed(keys["flex"][s], f),
                "foot_world": (
                    keys["foot_world"][s][0],
                    keyed(keys["foot_world"][s][1], f),
                ),
            }
        arm_w, leg_w = keyed(keys["arm_w"], f), keyed(keys["leg_w"], f)
        pose = mix_limbs(solver.solve(spec), limbs_from, arm_w, leg_w)
        # a target counts as missed only while its limb is the solved one
        pose["miss"] = {
            k: v
            for k, v in pose["miss"].items()
            if (arm_w if k.startswith("wrist") else leg_w) >= 1.0
        }
        frames.append(
            blend(pose, anchor_pose, keyed(keys["anchor_w"], f))
            | {"before_anchor": pose}
        )
    return frames


def pose_points(rig, pose):
    """What the transitions read from a pose they join: joint places, trunk turns and the feet's world turns."""
    world = rig.world(pose["local"], pose["pelvis"])
    out = {
        "world": world,
        "pelvis": pose["pelvis"].copy(),
        "trunk": {n: world[n][:3, :3] @ rig.rest_rot[n].T for n in TRUNK},
    }
    for s, _ in SIDES:
        out["shoulder_" + s] = world["upperarm_" + s][:3, 3].copy()
        out["wrist_" + s] = world["hand_" + s][:3, 3].copy()
        out["elbow_" + s] = world["lowerarm_" + s][:3, 3].copy()
        out["hip_" + s] = world["thigh_" + s][:3, 3].copy()
        out["ankle_" + s] = world["foot_" + s][:3, 3].copy()
        out["knee_" + s] = world["calf_" + s][:3, 3].copy()
        out["foot_" + s] = world["foot_" + s][:3, :3].copy()
        out["fingers_" + s] = unit(
            world["middle_01_" + s][:3, 3] - world["hand_" + s][:3, 3]
        )
        out["palm_" + s] = (
            world["hand_" + s][:3, :3]
            @ rig.rest_rot["hand_" + s].T
            @ np.array([0.0, 0.0, -1.0])
        )
    return out


def build_transitions(rig, solver, anchor, crouch, clips):
    """Crouch to prone and back. Down: the hands reach for the floor ahead, the chest follows them down while the
    feet go back one after the other, and the body settles on its forearms. Up: the hands come back beside the
    chest and push, the knees draw under the body one after the other, and the chest rises into the crouch."""
    idle = clips["Prone_Idle_Loop"][0]
    c, p = pose_points(rig, crouch), pose_points(rig, idle)
    down = np.array([0.0, 0.0, -1.0])
    lying_knee = {s: vec(0.0, sign * 1.0, -0.35) for s, sign in SIDES}
    crouch_knee = {s: unit(c["knee_" + s] - c["hip_" + s]) for s, _ in SIDES}
    under_knee = {
        s: unit(vec(0.3, sign * 1.0, -0.25)) for s, sign in SIDES
    }  # a bent knee goes out to the side
    r0, l0 = c["ankle_r"], c["ankle_l"]

    # ---- crouch to prone: the left foot is the front one in the crouch, the right is back on its toes
    n = TO_PRONE_FRAMES
    dive = {
        "pelvis": (62, 0, 0),
        "spine_01": (74, 0, 0),
        "spine_02": (88, 0, 0),
        "spine_03": (102, 0, 0),
        "neck_01": (80, 0, 0),
        "Head": (52, 0, 0),
    }
    land = {
        "pelvis": (86, 0, 0),
        "spine_01": (86, 0, 0),
        "spine_02": (80, 0, 0),
        "spine_03": (73, 0, 0),
        "neck_01": (52, 0, 0),
        "Head": (30, 0, 0),
    }
    keys = {
        "pelvis": [
            (0, c["pelvis"]),
            (9, vec(0.08, 0.0, 0.39)),
            (15, vec(0.03, 0.0, 0.33)),
            (20, vec(0.0, 0.0, 0.215)),
            (24, p["pelvis"]),
            (n, p["pelvis"]),
        ],
        "trunk": {
            b: [
                (0, c["trunk"][b]),
                (9, trunk_turn(*dive[b])),
                (18, trunk_turn(*land[b])),
                (24, p["trunk"][b]),
                (n, p["trunk"][b]),
            ]
            for b in TRUNK
        },
        "clav": [(0, (8.0, 4.0)), (n, (8.0, 4.0))],
        "curl": [(0, 12.0), (9, 2.0), (n, 2.0)],
        "thumb_flat": [(0, 0.0), (9, 1.0), (n, 1.0)],
        # the open hands catch the body; as the elbows come down the forearms roll and the hands close
        "fist": [
            (0, 0.0),
            (ROLL_FRAMES[0] + 1, 0.0),
            (ROLL_FRAMES[1] - 1, 1.0),
            (n, 1.0),
        ],
        "wrist": {},
        "elbow": {},
        "palm": {},
        "fingers": {},
        "ankle": {},
        "knee": {},
        "flex": {},
        "foot_world": {},
        "arm_w": [(0, 0.0), (4, 1.0), (n, 1.0)],
        "leg_w": [(0, 0.0), (2, 1.0), (n, 1.0)],
        "anchor_w": [(0, 0.0), (21, 0.0), (n, 1.0)],
    }
    for s, sign in SIDES:
        above = p["wrist_" + s] + vec(-0.24, sign * 0.20, 0.22)
        flat_hand = p["wrist_" + s] * np.array([1.0, 1.0, 0.0]) + vec(0.0, 0.0, WRIST_H)
        keys["wrist"][s] = [
            (0, c["wrist_" + s]),
            (
                3,
                c["wrist_" + s] + vec(0.16, sign * 0.03, 0.14),
            ),  # up and ahead, over the knee
            (5, above),
            (9, flat_hand),
            (ROLL_FRAMES[0], flat_hand),
            # the hand lifts off the floor to close: a fist is taller than a flat hand
            (ROLL_FRAMES[0] + 3, p["wrist_" + s] + vec(0.0, 0.0, HAND_LIFT)),
            (ROLL_FRAMES[1], p["wrist_" + s]),
            (n, p["wrist_" + s]),
        ]
        keys["elbow"][s] = [
            (0, c["elbow_" + s]),
            (
                4,
                c["elbow_" + s] + vec(-0.04, sign * 0.22, 0.14),
            ),  # out, clear of the knee
            (9, p["elbow_" + s] + vec(-0.1, sign * 0.1, 0.25)),
            (19, p["elbow_" + s]),
            (n, p["elbow_" + s]),
        ]
        keys["palm"][s] = [
            (0, c["palm_" + s]),
            (8, down),
            (ROLL_FRAMES[0], down),
            (ROLL_FRAMES[1] - 2, p["palm_" + s]),
            (n, p["palm_" + s]),
        ]
        # the flat hands land pointing nearly straight ahead, clear of each other, and turn in as they close
        landing = vec(
            math.cos(math.radians(13.0)), -sign * math.sin(math.radians(13.0)), 0.0
        )
        keys["fingers"][s] = [
            (0, c["fingers_" + s]),
            (8, landing),
            (ROLL_FRAMES[0] + 2, landing),
            (ROLL_FRAMES[1], p["fingers_" + s]),
            (n, p["fingers_" + s]),
        ]
    # the right foot slides back on its toes; the left steps back after the hands have landed
    keys["ankle"]["r"] = [
        (0, r0),
        (3, r0),
        # the crouch stands with its feet side by side (kit #1160): the foot is carried back, not slid
        (8, (r0 + p["ankle_r"]) / 2 + vec(0.0, 0.0, STEP_LIFT)),
        (14, p["ankle_r"] + vec(0.07, 0.0, 0.10)),
        (19, p["ankle_r"] + vec(0.03, 0.0, 0.07)),
        (24, p["ankle_r"]),
        (n, p["ankle_r"]),
    ]
    keys["ankle"]["l"] = [
        (0, l0),
        (7, l0),
        (9, l0 + vec(0.0, 0.0, 0.03)),
        (13, (l0 + p["ankle_l"]) / 2 + vec(0.0, 0.03, 0.20)),
        (17, p["ankle_l"] + vec(0.05, 0.0, 0.10)),
        (20, p["ankle_l"] + vec(0.03, 0.0, 0.07)),
        (25, p["ankle_l"]),
        (n, p["ankle_l"]),
    ]
    # the front (left) knee opens to the side as the chest comes down, so the chest passes beside it
    open_knee = unit(crouch_knee["l"] + vec(0.0, KNEE_OPEN, 0.0))
    for s, sign in SIDES:
        keys["knee"][s] = [
            (0, crouch_knee[s]),
            (8, crouch_knee[s]),
            (14, under_knee[s]),
            (20, lying_knee[s]),
            (n, lying_knee[s]),
        ]
        if s == "l":
            keys["knee"][s][1:2] = [
                (2, crouch_knee[s]),
                (6, open_knee),
                (11, open_knee),
            ]
        keys["foot_world"][s] = (
            c["foot_" + s],
            [
                (0, 1.0),
                (4 if s == "r" else 9, 1.0),
                (10 if s == "r" else 13, 0.0),
                (n, 0.0),
            ],
        )
    keys["flex"]["r"] = [(0, 20.0), (14, 22.0), (19, 30.0), (24, 62.0), (n, 62.0)]
    keys["flex"]["l"] = [
        (0, 0.0),
        (13, 30.0),
        (17, 22.0),
        (20, 30.0),
        (25, 62.0),
        (n, 62.0),
    ]
    to_prone = transition(rig, solver, n, keys, crouch, idle)

    # ---- prone to crouch
    n = TO_CROUCH_FRAMES
    push = {
        "pelvis": (66, 0, 0),
        "spine_01": (76, 0, 0),
        "spine_02": (86, 0, 0),
        "spine_03": (92, 0, 0),
        "neck_01": (70, 0, 0),
        "Head": (44, 0, 0),
    }
    keys = {
        "pelvis": [
            (0, p["pelvis"]),
            (5, p["pelvis"] + vec(0.0, 0.0, 0.01)),
            (10, vec(-0.03, 0.0, 0.31)),
            (15, vec(-0.12, 0.01, 0.42)),
            (21, c["pelvis"] + vec(0.03, 0.0, 0.035)),
            (25, c["pelvis"]),
            (n, c["pelvis"]),
        ],
        "trunk": {
            b: [
                (0, p["trunk"][b]),
                (5, trunk_turn(*land[b])),
                (14, trunk_turn(*push[b])),
                (25, c["trunk"][b]),
                (n, c["trunk"][b]),
            ]
            for b in TRUNK
        },
        "clav": [(0, (8.0, 4.0)), (n, (8.0, 4.0))],
        "curl": [(0, 2.0), (14, 2.0), (22, 12.0), (n, 12.0)],
        "thumb_flat": [(0, 1.0), (14, 1.0), (22, 0.0), (n, 0.0)],
        # the fists open as the hands come back beside the chest: the push is on flat palms
        "fist": [(0, 1.0), (OPEN_FRAMES[0], 1.0), (OPEN_FRAMES[1], 0.0), (n, 0.0)],
        "wrist": {},
        "elbow": {},
        "palm": {},
        "fingers": {},
        "ankle": {},
        "knee": {},
        "flex": {},
        "foot_world": {},
        "arm_w": [(0, 1.0), (15, 1.0), (27, 0.0), (n, 0.0)],
        "leg_w": [(0, 1.0), (26, 1.0), (n, 0.0)],
        "anchor_w": [(0, 1.0), (4, 0.0), (n, 0.0)],
    }
    for s, sign in SIDES:
        under = vec(-p["shoulder_" + s][1] - 0.06, sign * 0.23, WRIST_H)
        leave, wait, arrive = HAND_WAIT_FRAMES[s]
        keys["wrist"][s] = [
            (0, p["wrist_" + s]),
            (1, p["wrist_" + s]),
            (4, (p["wrist_" + s] + under) / 2 + vec(0, 0, 0.06)),
            (8, under),
            (leave, under),
            (
                wait,
                c["wrist_" + s] + vec(*HAND_WAIT[s][0]) * np.array([sign, 1.0, 1.0]),
            ),
            (arrive, c["wrist_" + s]),
            (n, c["wrist_" + s]),
        ]
        keys["elbow"][s] = [
            (0, p["elbow_" + s]),
            (8, under + vec(-0.25, sign * 0.12, 0.2)),
            (15, under + vec(-0.25, sign * 0.12, 0.3)),
            (
                wait,
                c["elbow_" + s] + vec(*HAND_WAIT[s][1]) * np.array([sign, 1.0, 1.0]),
            ),
            (arrive, c["elbow_" + s]),
            (n, c["elbow_" + s]),
        ]
        keys["palm"][s] = [
            (0, p["palm_" + s]),
            (OPEN_FRAMES[0], p["palm_" + s]),
            (OPEN_FRAMES[1], down),
            (15, down),
            (22, c["palm_" + s]),
            (n, c["palm_" + s]),
        ]
        ahead = vec(1.0, -sign * 0.25, 0.0)
        keys["fingers"][s] = [
            (0, p["fingers_" + s]),
            (8, ahead),
            (15, ahead),
            (22, c["fingers_" + s]),
            (n, c["fingers_" + s]),
        ]
    # the right knee bends under the body on its toes first; the left foot then steps up to the front
    keys["ankle"]["r"] = [
        (0, p["ankle_r"]),
        (4, p["ankle_r"] + vec(0.0, 0.0, 0.07)),
        (8, p["ankle_r"] + vec(0.0, 0.0, 0.10)),
        (13, (r0 + p["ankle_r"]) / 2 + vec(0.0, 0.0, STEP_LIFT)),
        (17, r0),
        (n, r0),
    ]
    keys["ankle"]["l"] = [
        (0, p["ankle_l"]),
        (5, p["ankle_l"] + vec(0.0, 0.0, 0.07)),
        (11, p["ankle_l"] + vec(0.0, 0.0, 0.10)),
        (17, (l0 + p["ankle_l"]) / 2 + vec(0.05, 0.05, 0.16)),
        (22, l0 + vec(0.0, 0.0, 0.02)),
        (24, l0),
        (n, l0),
    ]
    for s, sign in SIDES:
        keys["knee"][s] = [
            (0, lying_knee[s]),
            (6, lying_knee[s]),
            (13, under_knee[s]),
            (24, crouch_knee[s]),
            (n, crouch_knee[s]),
        ]
        keys["foot_world"][s] = (
            c["foot_" + s],
            [
                (0, 0.0),
                (10 if s == "r" else 18, 0.0),
                (17 if s == "r" else 23, 1.0),
                (n, 1.0),
            ],
        )
    keys["flex"]["r"] = [(0, 62.0), (4, 30.0), (8, 22.0), (17, 20.0), (n, 20.0)]
    keys["flex"]["l"] = [
        (0, 62.0),
        (5, 30.0),
        (11, 22.0),
        (17, 30.0),
        (22, 0.0),
        (n, 0.0),
    ]
    to_crouch = transition(rig, solver, n, keys, crouch, idle)
    return {"Crouch_To_Prone": to_prone, "Prone_To_Crouch": to_crouch}


# ---- Blender ----------------------------------------------------------------------------------------------------


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="BLENDER")
    new = [o for o in bpy.data.objects if o not in before]
    return next(o for o in new if o.type == "ARMATURE"), new


def library_pose(path, clip, frame_no=0):
    """One frame of a library clip as local rotations and the pelvis's place, then the library is removed."""
    arm, objects = import_glb(path)
    action = bpy.data.actions[clip]
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    bpy.context.scene.frame_set(frame_no)
    bpy.context.view_layer.update()
    local, pelvis = {}, None
    for pb in arm.pose.bones:
        m = (pb.parent.matrix.inverted() @ pb.matrix) if pb.parent else pb.matrix
        local[pb.name] = np.array(m.to_quaternion().to_matrix())
        if pb.name == "pelvis":
            pelvis = np.array(pb.matrix.translation)
    for obj in objects:
        bpy.data.objects.remove(obj)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    return {"local": local, "pelvis": pelvis, "miss": {}}


def key_clip(arm, rig, name, frames):
    """Key a clip on the armature: every bone's rotation on every frame, and the pelvis's place."""
    action = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = action
    last = {}
    for f, pose in enumerate(frames):
        for pb in arm.pose.bones:
            n = pb.name
            basis = rig.local_rot[n].T @ pose["local"][n]
            q = to_quat(basis)
            if n in last and q.dot(last[n]) < 0:
                q.negate()
            last[n] = q.copy()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n == "pelvis":
                parent = rig.rest[rig.parent[n]]
                local_pos = parent[:3, :3].T @ (pose["pelvis"] - parent[:3, 3])
                pb.location = tuple(rig.local_rot[n].T @ (local_pos - rig.local_pos[n]))
                pb.keyframe_insert("location", frame=f)
    action.use_fake_user = True
    slot = arm.animation_data.action_slot
    arm.animation_data.action = None
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, action)
    strip.action_slot = slot
    strip.name = name
    track.mute = True
    return action


def check_against_blender(arm, mesh, rig, action, frames, frame_no):
    """The script's own skinning against Blender's, on one frame of a keyed clip."""
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    bpy.context.scene.frame_set(frame_no)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    shaped = mesh.evaluated_get(deps)
    world = np.array(shaped.matrix_world)
    co = (
        np.array([v.co[:] for v in shaped.data.vertices]) @ world[:3, :3].T
        + world[:3, 3]
    )
    pose = frames[frame_no]
    mine = rig.skin(rig.world(pose["local"], pose["pelvis"]))
    arm.animation_data.action = None
    return float(np.abs(co - mine).max())


def export(arm, path):
    """The armature and its clips as a glb: a one-triangle mesh skinned to the root stands in for the model, so the
    file has a skin (Godot makes its `Skeleton3D` from it) and no copy of the mannequin."""
    mesh = bpy.data.meshes.new("ProneClips")
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0, 0.01)], [], [(0, 1, 2)])
    proxy = bpy.data.objects.new("ProneClips", mesh)
    bpy.context.scene.collection.objects.link(proxy)
    proxy.parent = arm
    proxy.vertex_groups.new(name="root").add([0, 1, 2], 1.0, "REPLACE")
    proxy.modifiers.new("Armature", "ARMATURE").object = arm
    for track in arm.animation_data.nla_tracks:
        track.mute = False
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    proxy.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_optimize_animation_keep_anim_armature=True,
        export_reset_pose_bones=True,
        export_def_bones=False,
        export_materials="NONE",
        export_skins=True,
        export_yup=True,
    )


# ---- checks -----------------------------------------------------------------------------------------------------


def clip_numbers(rig, name, frames):
    """What a clip measures: the lowest and highest vertex, the body's reach ahead and behind, its width, the
    highest point of the back and thighs, and the solver's worst miss."""
    low, high, ahead, behind, miss = [], [], [], [], 0.0
    wide, back = 0.0, 0.0
    trunk = np.isin(
        rig.owner, ("pelvis", "spine_01", "spine_02", "spine_03", "thigh_l", "thigh_r")
    )
    for pose in frames:
        skinned = rig.skin(rig.world(pose["local"], pose["pelvis"]))
        wide = max(wide, float(skinned[:, 0].max() - skinned[:, 0].min()))
        back = max(back, float(skinned[trunk, 2].max()))
        low.append(float(skinned[:, 2].min()))
        high.append(float(skinned[:, 2].max()))
        ahead.append(float(-skinned[:, 1].min()))
        behind.append(float(skinned[:, 1].max()))
        miss = max([miss] + list(pose.get("miss", {}).values()))
    return {
        "frames": len(frames) - 1,
        "seconds": round((len(frames) - 1) / FPS, 4),
        "lowest": round(min(low), 4),
        "highest": round(max(high), 4),
        "ahead": round(max(ahead), 3),
        "behind": round(max(behind), 3),
        "widest": round(wide, 3),
        "back_highest": round(back, 3),
        "solver_miss": round(miss, 5),
    }


def seam(frames):
    """The largest turn between a loop's first and last pose, in degrees."""
    worst = 0.0
    for n in frames[0]["local"]:
        q = to_quat(frames[0]["local"][n]).rotation_difference(
            to_quat(frames[-1]["local"][n])
        )
        worst = max(worst, math.degrees(q.angle))
    return worst


def pose_gap(a, b):
    """The largest turn between two poses, in degrees, and how far their pelvises are apart."""
    worst = 0.0
    for n in a["local"]:
        worst = max(
            worst,
            math.degrees(
                to_quat(a["local"][n]).rotation_difference(to_quat(b["local"][n])).angle
            ),
        )
    return worst, float(np.linalg.norm(a["pelvis"] - b["pelvis"]))


def stray(rig, frames, bone, first, last):
    """How far a joint strays from its mean place over a run of frames it should stay planted in."""
    places = []
    for f in range(first, last + 1):
        places.append(rig.world(frames[f]["local"], frames[f]["pelvis"])[bone][:3, 3])
    places = np.array(places)
    return round(float(np.linalg.norm(places - places.mean(axis=0), axis=1).max()), 5)


def planted_slide(rig, frames, travel):
    """How far each planted joint strays from its place on the ground while the body travels: for every side, the
    elbow, the wrist and the ankle through their planted part of the crawl, in metres, and the knee's slide (the
    knee rolls as the leg straightens, so it is reported, not held)."""
    out = {}
    count = len(frames) - 1
    speed = travel / (CRAWL_DUTY * count / FPS)
    for s, _ in SIDES:
        for joint, lead, duty in (
            ("lowerarm_", "r", CRAWL_DUTY),
            ("hand_", "r", CRAWL_DUTY),
            ("foot_", "l", LEG_DUTY),
            ("calf_", "l", LEG_DUTY),
        ):
            places = []
            for f in range(count):
                phase = (f / count + (0.0 if s == lead else 0.5)) % 1.0
                if phase >= duty - 1e-9:
                    continue
                world = rig.world(frames[f]["local"], frames[f]["pelvis"])
                p = world[joint + s][:3, 3].copy()
                p[1] -= speed * (phase * count / FPS)  # the body moves along -Y
                places.append(p)
            places = np.array(places)
            out[joint + s] = round(
                float(np.linalg.norm(places - places.mean(axis=0), axis=1).max()), 5
            )
    return out, speed


def fist_numbers(rig, pose):
    """How the closed hands of a pose fit together, in millimetres, on the mesh's own pieces (the mannequin's hand
    is a palm and a capsule a finger bone): the deepest any finger piece is inside the palm or a piece of another
    finger, the gap between the thumb's last piece and the index and middle fingers it lies across, and each
    fingertip's gap to the palm. A point is inside a piece when the nearest skin of that piece faces away from
    it and rays from it meet the back of the piece's faces."""
    from mathutils.bvhtree import BVHTree

    skinned = rig.skin(rig.world(pose["local"], pose["pelvis"]))
    piece = np.array([rig.owner[t[0]] for t in rig.tris])
    out = {}
    for s, _ in SIDES:
        names = ["hand_" + s] + [
            f"{finger}_{joint}_{s}"
            for finger in FINGERS + ("thumb",)
            for joint in ("01", "02", "03")
        ]
        trees, points = {}, {}
        for name in names:
            tris = rig.tris[piece == name]
            used = np.unique(tris)
            trees[name] = BVHTree.FromPolygons(
                skinned[used].tolist(), np.searchsorted(used, tris).tolist()
            )
            points[name] = skinned[np.flatnonzero(rig.owner == name)]

        def reach(inner, outer, trees=trees, points=points):
            """(depth inside, gap outside) of `inner`'s vertices against `outer`'s skin, in metres."""
            deep, gap = 0.0, 9.0
            for point in points[inner].tolist():
                place, normal, _, distance = trees[outer].find_nearest(point)
                inside = (Vector(point) - place).dot(normal) < 0.0
                if inside:
                    # from inside, a ray any way first meets the back of a face (five of six: the palm is open
                    # at the wrist)
                    backs = 0
                    for way in AXES:
                        _, facing, _, far = trees[outer].ray_cast(point, way)
                        backs += far is not None and way.dot(facing) > 0.0
                    inside = backs >= 5
                if inside:
                    deep = max(deep, distance)
                    gap = 0.0
                else:
                    gap = min(gap, distance)
            return deep, gap

        deepest, pair, pairs = 0.0, None, {}
        for a in names[1:]:
            for b in names:
                same = a.split("_")[0] == b.split("_")[0]
                # not measured: a finger against itself, a knuckle against the palm it grows from, and two
                # knuckles side by side (the model's own are 3.7 mm into each other with the hand open)
                if (
                    a == b
                    or same
                    or ("_01_" in a and (b.startswith("hand") or "_01_" in b))
                ):
                    continue
                deep = reach(a, b)[0]
                if deep > 0.0:
                    pairs[f"{a} in {b}"] = round(deep * 1000.0, 1)
                if deep > deepest:
                    deepest, pair = deep, f"{a} in {b}"
        out[s] = {
            "deepest": round(deepest * 1000.0, 1),
            "pair": pair,
            "pairs": pairs,
            "thumb_gap": round(
                min(
                    reach(f"thumb_03_{s}", f"{f}_02_{s}")[1]
                    for f in ("index", "middle")
                )
                * 1000.0,
                1,
            ),
            "tip_to_palm": {
                f: round(reach(f"{f}_03_{s}", "hand_" + s)[1] * 1000.0, 1)
                for f in FINGERS
            },
        }
    return out


def floor_numbers(arm, actions, clips, bodies, failures):
    """How low each mannequin's hands (with their fingers) and forearms get in each clip, in millimetres over the
    floor, with the frame. A hand deeper than `HAND_FLOOR_LIMIT` on the first body, the one the clips are solved on,
    fails the build; the other's numbers are reported (his longer upper arms put his elbows lower)."""
    scene = bpy.context.scene
    out = {}
    for name, frames in clips.items():
        arm.animation_data.action = actions[name]
        arm.animation_data.action_slot = actions[name].slots[0]
        out[name] = {body.name: {} for body in bodies}
        for f in range(len(frames)):
            scene.frame_set(f)
            for body in bodies:
                body.pose_from(arm)
                coords = body.skinned()
                for part in ("hand", "lowerarm"):
                    for s, _ in SIDES:
                        low = round(
                            float(coords[body.parts[f"{part}_{s}"]["verts"], 2].min())
                            * 1000.0,
                            1,
                        )
                        entry = out[name][body.name].setdefault(
                            f"{part}_{s}", {"lowest": low, "frame": f, "frames": []}
                        )
                        entry["frames"].append(low)
                        if low < entry["lowest"]:
                            entry.update(lowest=low, frame=f)
        for body in bodies:
            for part, entry in out[name][body.name].items():
                if (
                    body is bodies[0]
                    and part.startswith("hand")
                    and entry["lowest"] < -HAND_FLOOR_LIMIT
                ):
                    failures.append(
                        f"{name} on the {body.name}: {part} goes {-entry['lowest']} mm under the floor at"
                        f" frame {entry['frame']} (the limit is {HAND_FLOOR_LIMIT} mm)"
                    )
    arm.animation_data.action = None
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--male", required=True)
    parser.add_argument("--library", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--report")
    parser.add_argument(
        "--preview",
        action="store_true",
        help="export even when a check fails, to look at it",
    )
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    crouch = library_pose(args.library, "Crouch_Idle_Loop")
    arm, objects = import_glb(args.model)
    mesh = next(o for o in objects if o.type == "MESH" and o.parent == arm)
    for obj in objects:
        if obj.type == "MESH" and obj.parent is None:
            bpy.data.objects.remove(obj)
    rig = Rig(arm, mesh)
    solver = Solver(rig)
    anchor = measure_anchor(rig, solver)
    print("ANCHOR", {k: round(float(v), 4) for k, v in anchor.items()})

    clips = {}
    clips["Prone_Idle_Loop"] = build_idle(rig, solver, anchor)
    clips["Crawl_Fwd_Loop"] = build_crawl(rig, solver, anchor)
    from_transitions = globals().get("build_transitions")
    if from_transitions:
        clips.update(from_transitions(rig, solver, anchor, crouch, clips))

    report = {"fps": FPS, "clips": {}}
    failures = []
    for name, frames in clips.items():
        numbers = clip_numbers(rig, name, frames)
        report["clips"][name] = numbers
        if numbers["lowest"] < -0.02:
            failures.append(
                f"{name}: the mesh goes {-numbers['lowest']:.3f} m under the floor"
            )
        if numbers["solver_miss"] > 0.002:
            failures.append(
                f"{name}: a target is missed by {numbers['solver_miss']:.4f} m"
            )
    for name in ("Prone_Idle_Loop", "Crawl_Fwd_Loop"):
        report["clips"][name]["seam_degrees"] = round(seam(clips[name]), 5)
        if seam(clips[name]) > 0.01:
            failures.append(f"{name}: the loop does not close")
    slide, speed = planted_slide(rig, clips["Crawl_Fwd_Loop"], CRAWL_STRIDE)
    report["clips"]["Crawl_Fwd_Loop"].update(
        {
            "speed": round(speed, 4),
            "stride": CRAWL_STRIDE,
            "cycle_travel": round(speed * CRAWL_FRAMES / FPS, 4),
            "slide": slide,
        }
    )
    for joint, value in slide.items():
        if not joint.startswith("calf_") and value > 0.003:
            failures.append(
                f"Crawl_Fwd_Loop: {joint} slides {value:.4f} m while planted"
            )
    if from_transitions:
        idle0 = clips["Prone_Idle_Loop"][0]
        joins = {
            "Crouch_To_Prone starts on the crouch": pose_gap(
                clips["Crouch_To_Prone"][0], crouch
            ),
            "Crouch_To_Prone ends on the prone idle": pose_gap(
                clips["Crouch_To_Prone"][-1], idle0
            ),
            "Prone_To_Crouch starts on the prone idle": pose_gap(
                clips["Prone_To_Crouch"][0], idle0
            ),
            "Prone_To_Crouch ends on the crouch": pose_gap(
                clips["Prone_To_Crouch"][-1], crouch
            ),
        }
        report["joins"] = {
            k: [round(v[0], 4), round(v[1], 5)] for k, v in joins.items()
        }
        for what, (turn, apart) in joins.items():
            if turn > 0.05 or apart > 0.0005:
                failures.append(f"{what}: off by {turn:.3f} degrees and {apart:.4f} m")
        down, up = clips["Crouch_To_Prone"], clips["Prone_To_Crouch"]
        planted = {
            "Crouch_To_Prone hand_l 10-12": stray(
                rig, down, "hand_l", 10, ROLL_FRAMES[0]
            ),
            "Crouch_To_Prone hand_r 10-12": stray(
                rig, down, "hand_r", 10, ROLL_FRAMES[0]
            ),
            "Crouch_To_Prone hand_l 19-27": stray(
                rig, down, "hand_l", ROLL_FRAMES[1], TO_PRONE_FRAMES
            ),
            "Crouch_To_Prone hand_r 19-27": stray(
                rig, down, "hand_r", ROLL_FRAMES[1], TO_PRONE_FRAMES
            ),
            "Crouch_To_Prone foot_l 0-7": stray(rig, down, "foot_l", 0, 7),
            "Prone_To_Crouch hand_l 8-13": stray(
                rig, up, "hand_l", 8, HAND_WAIT_FRAMES["l"][0]
            ),
            "Prone_To_Crouch hand_r 8-14": stray(
                rig, up, "hand_r", 8, HAND_WAIT_FRAMES["r"][0]
            ),
            "Prone_To_Crouch foot_r 18-30": stray(
                rig, up, "foot_r", 18, TO_CROUCH_FRAMES
            ),
            "Prone_To_Crouch foot_l 25-30": stray(
                rig, up, "foot_l", 25, TO_CROUCH_FRAMES
            ),
        }
        report["planted"] = planted
        for what, value in planted.items():
            if value > 0.006:
                failures.append(f"{what}: strays {value:.4f} m while planted")
    groups = {}
    for name, frames in clips.items():
        per = {}
        for pose in frames:
            skinned = rig.skin(rig.world(pose["local"], pose["pelvis"]))
            for group in (
                "pelvis",
                "spine",
                "neck",
                "Head",
                "clavicle",
                "upperarm",
                "lowerarm",
                "hand",
                "thigh",
                "calf",
                "foot",
                "ball",
            ):
                extra = (
                    ("index", "middle", "ring", "pinky", "thumb")
                    if group == "hand"
                    else ()
                )
                low = rig.lowest(skinned, (group,) + extra)
                per[group] = round(min(per.get(group, 9.0), low), 4)
        groups[name] = per
    report["lowest_by_part"] = groups
    # The fist on both mannequins: the clip's rotations on each one's own hand, as Godot plays them.
    other_arm, other_objects = import_glb(args.male)
    other_mesh = max(
        (o for o in other_objects if o.type == "MESH" and o.parent == other_arm),
        key=lambda o: len(o.data.vertices),
    )
    fist_rigs = {"female": rig, "male": Rig(other_arm, other_mesh)}
    for obj in other_objects:
        bpy.data.objects.remove(obj)
    report["fist_mm"] = {}
    for body, body_rig in fist_rigs.items():
        report["fist_mm"][body] = fist_numbers(body_rig, clips["Prone_Idle_Loop"][0])
        for side, entry in report["fist_mm"][body].items():
            if entry["deepest"] > FIST_LIMIT_IN:
                failures.append(
                    f"the {body}'s {side} fist: {entry['pair']} by {entry['deepest']} mm (the limit is"
                    f" {FIST_LIMIT_IN} mm)"
                )
            if entry["thumb_gap"] > FIST_LIMIT_OFF:
                failures.append(
                    f"the {body}'s {side} fist: the thumb is {entry['thumb_gap']} mm off the fingers (the"
                    f" limit is {FIST_LIMIT_OFF} mm)"
                )
    actions = {name: key_clip(arm, rig, name, frames) for name, frames in clips.items()}
    for name, frames in clips.items():
        off = check_against_blender(
            arm, mesh, rig, actions[name], frames, (len(frames) - 1) // 3
        )
        report["clips"][name]["skinning_against_blender"] = round(off, 6)
        if off > 0.001:
            failures.append(
                f"{name}: the script's skinning is {off:.4f} m off Blender's"
            )
    # Limbs through each other, on both mannequins' skinned meshes, on every frame of the keyed clips.
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import limb_overlap

    male = limb_overlap.load_body(args.male, "male")
    bodies = [limb_overlap.Body(arm, mesh, "female"), male]
    report["overlap_mm"] = {}
    report["floor_mm"] = floor_numbers(arm, actions, clips, bodies, failures)
    for name, frames in clips.items():
        measured = limb_overlap.measure(arm, actions[name], range(len(frames)), bodies)
        report["overlap_mm"][name] = {}
        for body, entry in measured.items():
            report["overlap_mm"][name][body] = {
                "deepest": entry["deepest_mm"],
                "frame": entry["frame"],
                "pair": entry["pair"],
                "pairs": entry["pairs"],
            }
            if entry["deepest_mm"] > OVERLAP_LIMIT:
                failures.append(
                    f"{name} on the {body}: {entry['pair']} by {entry['deepest_mm']} mm at frame"
                    f" {entry['frame']} (the limit is {OVERLAP_LIMIT} mm); all: {entry['pairs']}"
                )
    arm.animation_data.action = None
    for obj in male.objects:
        bpy.data.objects.remove(obj)
    print("REPORT", json.dumps(report, indent=1))
    if args.report:
        Path(args.report).write_text(
            json.dumps(report, indent=1) + "\n", encoding="utf-8"
        )
    if sorted(clips) != sorted(CLIPS) and from_transitions:
        failures.append(f"the clip list is {sorted(clips)}, not {sorted(CLIPS)}")
    if failures:
        print("BUILD FAILED\n  " + "\n  ".join(failures))
        if not args.preview:
            raise SystemExit(1)
    bpy.data.objects.remove(mesh)
    export(arm, args.out)
    print("EXPORTED", args.out)


if __name__ == "__main__":
    main()
