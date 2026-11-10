"""Build the template's vault clips and export them as an animation library (kit #1010).

GDStudio's own clips, keyed from scratch on Quaternius's universal rig (the template's mannequins and the Universal
Animation Library share it): `Vault_Low` (a one-handed speed vault), `Vault_High` (a two-handed side vault) and
`Vault_Land` (the landing step back into the sprint). Nothing is copied from another clip but the first and last
poses, which are the library's own `Sprint_Loop` so the clips join the run.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P <this file> -- [--out <folder>] [--render <folder>] [--only <clip>]

How a clip is made: every clip is a table of keys on a small set of controls (the pelvis, the spine, each wrist and
ankle with the way its elbow or knee points, the hands and feet, the fingers' curl), written in the **world** of a
reference obstacle: a box whose front face is at forward 0, so a planted hand or foot is two keys at one place. The
body's root moves forward at a constant speed (`speed`, from `start` metres before the front face) and is taken out
again, so the exported clip is in place like the library's. The solver below turns the controls into bone rotations
(two-bone IK about each limb's own hinge axis), and the build checks the skinned mesh on every frame against the
floor and the box before it exports.

Positions are `(left, forward, up)` in metres: left is the character's left, forward the way it runs, forward 0 the
obstacle's front face. Angles are `(yaw, pitch, roll)` in degrees: yaw turns left, pitch leans forward, roll leans
to the left.
"""

import argparse
import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent.parent
MANNEQUIN = ASSETS / "characters" / "mannequin" / "mannequin_female.glb"
LIBRARY = ASSETS / "animation" / "universal" / "ual1.glb"
FPS = 24
## The clips this file carries, and nothing else (kit docs/tools/blender/build-scripts.md#rebuilding).
FILE_CLIPS = ["Vault_Low", "Vault_High", "Vault_Land"]
## The obstacle is this wide in the checks: a wall, so the legs have to clear its top, not pass beside it.
BOX_HALF_WIDTH = 1.5
## How deep the skin may go into the floor or the box (m), and how far a planted palm may be off the top.
FLOOR_LIMIT = 0.012
BOX_LIMIT = 0.012
PALM_LIMIT = 0.015
## How far a planted wrist or ankle may move in the world while it is planted (m).
PLANT_LIMIT = 0.005
## The wrist bone rides this far above a surface the palm lies on.
PALM = 0.036
## A planted arm is never straighter than this share of its length.
ARM_REACH = 0.94

## The most a planted hand may move the body off its keyed path from one frame to the next (m).
PULL_STEP = 0.02


FINGERS = ["thumb", "index", "middle", "ring", "pinky"]
SPINE = ["spine_01", "spine_02", "spine_03", "neck_01", "Head", "clavicle_l", "clavicle_r"]


# ---------------------------------------------------------------------------------------------------------------
# Small maths
# ---------------------------------------------------------------------------------------------------------------
def P(left, forward, up):
    """A point in (left, forward, up) as a Blender vector (the rig faces -Y, its left is +X)."""
    return Vector((left, -forward, up))


def R(yaw=0.0, pitch=0.0, roll=0.0):
    """A turn in the rig's axes: yaw to the left, pitch forward, roll to the left (degrees)."""
    return (
        Matrix.Rotation(math.radians(yaw), 3, "Z")
        @ Matrix.Rotation(math.radians(pitch), 3, "X")
        @ Matrix.Rotation(math.radians(roll), 3, "Y")
    )


def frame_of(first, second):
    """An orthonormal 3x3 whose first column is `first` and whose second is as near `second` as that allows."""
    a = first.normalized()
    b = (second - a * second.dot(a)).normalized()
    return Matrix((a, b, a.cross(b))).transposed()


def aligned(quat, last):
    """`quat` with the sign that keeps it next to `last` (the same rotation; the short way round)."""
    if last is not None and quat.dot(last) < 0.0:
        return -quat
    return quat


class Channel:
    """Keys on one control and their smooth curve: a cubic through the keys that is flat at a hold and at a peak."""

    def __init__(self):
        self.keys = {}

    def key(self, frame, value):
        self.keys[float(frame)] = value

    def _prepared(self):
        frames = sorted(self.keys)
        values = [self.keys[f] for f in frames]
        if values and isinstance(values[0], Quaternion):
            fixed, last = [], None
            for value in values:
                last = aligned(value.normalized(), last)
                fixed.append(Vector(last))
            values = fixed
        elif values and not isinstance(values[0], Vector):
            values = [Vector((v, 0.0)) for v in values]
        tangents = []
        for i, value in enumerate(values):
            before = (value - values[i - 1]) / (frames[i] - frames[i - 1]) if i > 0 else None
            after = (values[i + 1] - value) / (frames[i + 1] - frames[i]) if i + 1 < len(values) else None
            if before is None or after is None:
                tangents.append((after if before is None else before) if len(values) > 1 else value * 0.0)
                continue
            if before.length < 1e-7 or after.length < 1e-7:
                tangents.append(value * 0.0)
                continue
            span = frames[i + 1] - frames[i - 1]
            tangent = (before * (frames[i + 1] - frames[i]) + after * (frames[i] - frames[i - 1])) / span
            if not self.is_quat():
                for axis in range(len(tangent)):
                    if before[axis] * after[axis] <= 0.0:
                        tangent[axis] = 0.0
                    else:
                        limit = 3.0 * min(abs(before[axis]), abs(after[axis]))
                        tangent[axis] = max(-limit, min(limit, tangent[axis]))
            tangents.append(tangent)
        return frames, values, tangents

    def is_quat(self):
        return bool(self.keys) and isinstance(next(iter(self.keys.values())), Quaternion)

    def is_scalar(self):
        return bool(self.keys) and not isinstance(next(iter(self.keys.values())), (Quaternion, Vector))

    def at(self, frame):
        frames, values, tangents = self._prepared()
        if frame <= frames[0]:
            out = values[0]
        elif frame >= frames[-1]:
            out = values[-1]
        else:
            i = max(k for k in range(len(frames)) if frames[k] <= frame)
            h = frames[i + 1] - frames[i]
            s = (frame - frames[i]) / h
            out = (
                values[i] * (2 * s**3 - 3 * s**2 + 1)
                + tangents[i] * h * (s**3 - 2 * s**2 + s)
                + values[i + 1] * (-2 * s**3 + 3 * s**2)
                + tangents[i + 1] * h * (s**3 - s**2)
            )
        if self.is_quat():
            return Quaternion(out).normalized()
        if self.is_scalar():
            return out[0]
        return out.copy()


# ---------------------------------------------------------------------------------------------------------------
# The rig
# ---------------------------------------------------------------------------------------------------------------
class Rig:
    """The mannequin's armature, its rest pose, and poses read from the library's clips."""

    def __init__(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = FPS
        bpy.ops.import_scene.gltf(filepath=str(MANNEQUIN))
        self.arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        self.mesh = next(o for o in bpy.data.objects if o.type == "MESH" and o.parent == self.arm)
        mine = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(LIBRARY))
        self.library_objects = [o for o in bpy.data.objects if o not in mine]
        self.library_arm = next(o for o in self.library_objects if o.type == "ARMATURE")
        for track in self.library_arm.animation_data.nla_tracks:
            track.mute = True
        self.library_actions = list(bpy.data.actions)
        self.order = [b.name for b in self.arm.data.bones]  # parents before children
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in self.arm.data.bones}
        self.rest = {b.name: b.matrix_local.copy() for b in self.arm.data.bones}
        self.rest_rel = {
            n: (self.rest[self.parent[n]].inverted() @ self.rest[n]) if self.parent[n] else self.rest[n].copy()
            for n in self.order
        }
        self.rest_rot = {n: self.rest[n].to_3x3() for n in self.order}
        # An open hand is the rest pose with the thumb lifted into the palm's plane (it rests pointing down).
        self.open = {}
        for side in "lr":
            rest = self.rest_rot[f"thumb_01_{side}"]
            self.open[f"thumb_01_{side}"] = (rest.inverted() @ R(0, -50, 0) @ rest).to_quaternion()

    def finger_bones(self, side):
        return [f"{f}_0{i}_{side}" for f in FINGERS for i in (1, 2, 3)]

    def library_pose(self, clip, frame):
        """The armature-space matrix of every bone of this rig in a library clip's pose (the clip's local
        rotations on this rig's own bone lengths, which is what Godot plays)."""
        action = bpy.data.actions[clip]
        data = self.library_arm.animation_data
        data.action = action
        data.action_slot = action.slots[0]
        length = action.frame_range[1]
        frame = frame % length
        bpy.context.scene.frame_set(int(frame), subframe=frame - int(frame))
        bones = self.library_arm.pose.bones
        out = {}
        for name in self.order:
            parent = self.parent[name]
            if parent is None:
                out[name] = self.rest[name].copy()
                continue
            rel = bones[parent].matrix.inverted() @ bones[name].matrix
            offset = rel.translation if name == "pelvis" else self.rest_rel[name].translation
            out[name] = out[parent] @ Matrix.LocRotScale(offset, rel.to_quaternion(), None)
        return out

    def basis(self, name, mats):
        """A bone's pose-space rotation (what Blender keys) from armature-space matrices."""
        parent = self.parent[name]
        rel = mats[parent].inverted() @ mats[name] if parent else mats[name]
        return (self.rest_rel[name].inverted() @ rel).to_quaternion()


# The limbs: the bone that swings, the bone that bends, the end, and the hinge axis in the rest pose (the bend
# plane's normal, `upper x lower`, as an armature-space direction).
LIMBS = {
    "hand_l": ("upperarm_l", "lowerarm_l", "hand_l", Vector((0, 0, -1))),
    "hand_r": ("upperarm_r", "lowerarm_r", "hand_r", Vector((0, 0, 1))),
    "foot_l": ("thigh_l", "calf_l", "foot_l", Vector((1, 0, 0))),
    "foot_r": ("thigh_r", "calf_r", "foot_r", Vector((1, 0, 0))),
}


class Clip:
    """One clip: its keys, its reference obstacle and the constant forward speed taken out of it."""

    def __init__(self, rig, name, frames, speed, start, box_height, box_depth):
        self.rig = rig
        self.name = name
        self.frames = frames
        self.speed = speed
        self.start = start
        self.box_height = box_height
        self.box_depth = box_depth
        self.channels = {}
        self.events = {}
        self.planted = []  # (limb, first frame, last frame)
        self.pulled = {}
        self.pullers = {}
        self.notes = {}

    def forward(self, frame):
        """How far forward the root is at a frame (0 is the obstacle's front face)."""
        return self.speed * frame / FPS - self.start

    def body(self, frame, left, forward, up):
        """A point given from the root's place at that frame (forward is ahead of the root)."""
        return P(left, self.forward(frame) + forward, up)

    def key(self, channel, frame, value):
        self.channels.setdefault(channel, Channel()).key(frame, value)

    def keys(self, channel, table):
        for frame, value in table.items():
            self.key(channel, frame, value)

    def to_world(self, frame, point):
        return point + Vector((0.0, -self.forward(frame), 0.0))

    def to_place(self, frame, point):
        return point + Vector((0.0, self.forward(frame), 0.0))

    def spine(self, name, yaw=0.0, pitch=0.0, roll=0.0):
        """A bend of a spine bone, given in the rig's axes, as the bone's own rotation."""
        rest = self.rig.rest_rot[name]
        return (rest.inverted() @ R(yaw, pitch, roll) @ rest).to_quaternion()

    def turned(self, name, yaw=0.0, pitch=0.0, roll=0.0):
        """A bone's armature-space rotation: its rest turned in the rig's axes (pelvis, feet)."""
        return (R(yaw, pitch, roll) @ self.rig.rest_rot[name]).to_quaternion()

    def palm(self, side, fingers, palm):
        """A hand's armature-space rotation from where its fingers point and where its palm faces."""
        rest = self.rig.rest_rot[f"hand_{side}"]
        along = Vector((1, 0, 0)) if side == "l" else Vector((-1, 0, 0))
        turn = frame_of(P(*fingers), P(*palm)) @ frame_of(along, Vector((0, 0, -1))).transposed()
        return (turn @ rest).to_quaternion()

    def pose_from(self, frame, clip, clip_frame, only=None, skip=()):
        """Key every control (or those in `only`) from a pose of a library clip."""
        rig = self.rig
        mats = rig.library_pose(clip, clip_frame)
        values = {
            "pelvis_pos": self.to_world(frame, mats["pelvis"].translation),
            "pelvis_rot": mats["pelvis"].to_quaternion(),
        }
        for name in SPINE:
            values[name] = rig.basis(name, mats)
        for limb, (upper, lower, end, _axis) in LIMBS.items():
            root, mid, tip = (mats[b].translation for b in (upper, lower, end))
            reach = (tip - root).normalized()
            bend = mid - root
            values[f"{limb}_pos"] = self.to_world(frame, tip)
            values[f"{limb}_pole"] = (bend - reach * bend.dot(reach)).normalized()
            values[f"{limb}_rot"] = mats[end].to_quaternion()
            values[f"{limb}_fk"] = rig.basis(end, mats)
        for side in "lr":
            values[f"ball_{side}"] = rig.basis(f"ball_{side}", mats)
            values[f"curl_{side}"] = 1.0
            values[f"hand_{side}_world"] = 0.0
        for channel, value in values.items():
            if (only is None or channel in only) and channel not in skip:
                self.key(channel, frame, value)
        return mats

    def solve(self, frame, fist, shift=None):
        """Armature-space matrices of every bone at a frame, with the pelvis moved by `shift`, and the pull the
        planted hands ask for: a hand held on the obstacle that the arm cannot reach pulls the pelvis, and the
        body with it, toward itself, so the contact wins over the body's keyed path (see `bake`)."""
        rig = self.rig
        at = {name: channel.at(frame) for name, channel in self.channels.items()}
        mats = {"root": rig.rest["root"].copy()}
        pelvis = self.to_place(frame, at["pelvis_pos"]) + (shift or Vector())
        mats["pelvis"] = Matrix.LocRotScale(pelvis, at["pelvis_rot"], None)
        pull = Vector()
        done = {"root", "pelvis"}
        reach_error = {}

        def forward_kinematics(name, quat):
            mats[name] = mats[rig.parent[name]] @ rig.rest_rel[name] @ quat.to_matrix().to_4x4()
            done.add(name)

        for name in SPINE:
            forward_kinematics(name, at[name])
        for limb, (upper, lower, end, axis) in LIMBS.items():
            root = (mats[rig.parent[upper]] @ rig.rest_rel[upper]).translation
            target = self.to_place(frame, at[f"{limb}_pos"])
            to_mid = rig.rest_rel[lower].translation
            to_end = rig.rest_rel[end].translation
            first, second = to_mid.length, to_end.length
            line = target - root
            distance = line.length
            reach_error[limb] = max(0.0, distance - (first + second) * 0.9995)
            if limb.startswith("hand") and distance > (first + second) * ARM_REACH:
                windows = [(a, b) for n, a, b in self.planted if n == limb]
                held = 1.0 if any(a <= frame <= b for a, b in windows) else 0.0
                if windows and frame < windows[0][0]:
                    held = max(0.0, min(1.0, at[f"{limb}_world"]))
                pull += line.normalized() * (distance - (first + second) * ARM_REACH) * held
                if shift is None and held > 0.0:
                    self.pullers.setdefault(frame, []).append(
                        f"{limb[-1]}{(distance - (first + second) * ARM_REACH) * held * 100:.0f}"
                    )
            distance = min(distance, (first + second) * 0.9995)
            line.normalize()
            pole = at[f"{limb}_pole"]
            side = (pole - line * pole.dot(line)).normalized()
            along = (first * first - second * second + distance * distance) / (2.0 * distance)
            height = math.sqrt(max(first * first - along * along, 0.0))
            mid = root + line * along + side * height
            tip = root + line * distance
            normal = side.cross(line).normalized()
            turn_upper = (
                frame_of(mid - root, normal) @ frame_of(to_mid, rig.rest_rot[upper].inverted() @ axis).transposed()
            )
            turn_lower = (
                frame_of(tip - mid, normal) @ frame_of(to_end, rig.rest_rot[lower].inverted() @ axis).transposed()
            )
            mats[upper] = Matrix.LocRotScale(root, turn_upper.to_quaternion(), None)
            mats[lower] = Matrix.LocRotScale(mid, turn_lower.to_quaternion(), None)
            free = (mats[lower] @ rig.rest_rel[end] @ at[f"{limb}_fk"].to_matrix().to_4x4()).to_quaternion()
            weight = at[f"{limb}_world"] if limb.startswith("hand") else 1.0
            held = aligned(at[f"{limb}_rot"], free)
            mats[end] = Matrix.LocRotScale(tip, free.slerp(held, max(0.0, min(1.0, weight))), None)
            done.update((upper, lower, end))
        for side in "lr":
            forward_kinematics(f"ball_{side}", at[f"ball_{side}"])
            curl = at[f"curl_{side}"]
            for name in rig.finger_bones(side):
                forward_kinematics(name, rig.open.get(name, Quaternion()).slerp(fist[name], curl))
        for name in rig.order:
            if name not in done:
                mats[name] = mats[rig.parent[name]] @ rig.rest_rel[name]
        return mats, reach_error, pull


# ---------------------------------------------------------------------------------------------------------------
# The clips
# ---------------------------------------------------------------------------------------------------------------
SPRINT = "Sprint_Loop"  # 16 frames at 24: the left foot lands at 0, the right at 8


def vault_low(rig):
    """A speed vault: off the left foot, the left hand on top, both legs swung over to the right, down on the
    right foot. The right hand never comes near the obstacle, so it can hold a pistol."""
    c = Clip(rig, "Vault_Low", frames=16, speed=4.0, start=1.3, box_height=0.8, box_depth=0.4)
    top = c.box_height
    # In and out of the sprint: its poses a little before and after give the curves the run's own speed.
    for frame in (-2, 0):
        c.pose_from(frame, SPRINT, frame)
    c.pose_from(2, SPRINT, 2, only={"pelvis_rot", "foot_r_pos", "foot_r_pole", "foot_r_rot", "ball_r"})
    for frame in (16, 18):
        c.pose_from(frame, SPRINT, frame - 8)

    c.keys(
        "pelvis_pos",
        {
            2: c.body(2, 0.0, -0.06, 0.82),
            4: c.body(4, -0.02, -0.04, 0.95),
            7: c.body(7, -0.07, -0.02, 1.08),
            9: c.body(9, -0.12, 0.0, 1.13),
            11: c.body(11, -0.09, -0.03, 1.08),
            13: c.body(13, -0.04, -0.05, 0.98),
        },
    )
    c.keys(
        "pelvis_rot",
        {
            4: c.turned("pelvis", 0, 18, 10),
            7: c.turned("pelvis", -5, 20, 40),
            9: c.turned("pelvis", -8, 20, 52),
            11: c.turned("pelvis", -5, 18, 40),
            13: c.turned("pelvis", 0, 14, 12),
        },
    )
    for name in ("spine_01", "spine_02", "spine_03"):
        c.keys(
            name,
            {
                4: c.spine(name, 2, 5, 1),
                7: c.spine(name, 4, 9, 2),
                9: c.spine(name, 5, 10, 3),
                11: c.spine(name, 3, 8, 1),
                13: c.spine(name, 0, 5, 0),
            },
        )
    c.keys(
        "neck_01",
        {5: c.spine("neck_01", -2, -10, -10), 9: c.spine("neck_01", -4, -16, -22), 13: c.spine("neck_01", 0, -6, -4)},
    )
    c.keys("Head", {5: c.spine("Head", -3, -12, -10), 9: c.spine("Head", -6, -18, -24), 13: c.spine("Head", 0, -6, -4)})
    c.keys(
        "clavicle_l",
        {7: c.spine("clavicle_l", 0, 0, 10), 10: c.spine("clavicle_l", 0, 0, 12), 13: c.spine("clavicle_l")},
    )

    # The left hand: forward and down onto the top, 0.12 m in from the front edge, then back into the swing.
    plant = P(0.27, 0.12, top + PALM)
    c.keys(
        "hand_l_pos",
        {
            2: c.body(2, 0.36, 0.05, 1.02),
            4: c.body(4, 0.34, 0.30, 1.05),
            7: plant,
            9: plant,
            10: plant + P(0.03, 0.14, 0.17),
            12: c.body(12, 0.36, -0.22, 1.0),
            14: c.body(14, 0.34, 0.0, 0.92),
        },
    )
    c.planted.append(("hand_l", 7, 9))
    c.keys("hand_l_pole", {4: P(0.5, -1.0, 0.2), 7: P(0.6, -1.0, 0.3), 9: P(0.7, -0.4, 0.8), 13: P(0.5, -1.0, 0.2)})
    flat = c.palm("l", (0.3, 1.0, 0.0), (0.0, 0.0, -1.0))
    c.keys(
        "hand_l_rot",
        {
            0: flat,
            7: flat,
            9: c.palm("l", (0.45, 1.0, 0.0), (0.0, 0.0, -1.0)),
            10: c.palm("l", (0.4, 1.0, -0.5), (0.0, -0.5, -1.0)),
            16: flat,
        },
    )
    c.keys("hand_l_world", {4: 0.0, 7: 1.0, 10: 1.0, 12: 0.0})
    c.keys("curl_l", {4: 1.0, 6: 0.0, 9: 0.0, 13: 1.0})

    # The right arm swings up and out for balance, away from the obstacle.
    c.keys(
        "hand_r_pos",
        {
            4: c.body(4, -0.40, 0.20, 1.05),
            7: c.body(7, -0.50, 0.10, 1.20),
            9: c.body(9, -0.56, 0.05, 1.32),
            12: c.body(12, -0.48, 0.0, 1.25),
            14: c.body(14, -0.44, -0.10, 1.20),
        },
    )
    c.keys("hand_r_pole", {7: P(-0.6, -1.0, -0.3), 9: P(-0.5, -1.0, -0.4), 13: P(-0.6, -1.0, -0.2)})

    # The left leg pushes off, tucks and follows the right leg over.
    stance = c.channels["foot_l_pos"].at(0)
    c.keys(
        "foot_l_pos",
        {
            2: stance,
            3: stance + P(0.0, 0.03, 0.05),
            4: stance + P(0.0, 0.08, 0.17),
            6: c.body(6, 0.04, -0.50, 0.62),
            8: c.body(8, -0.28, -0.32, 0.98),
            10: c.body(10, -0.50, -0.14, 1.08),
            12: c.body(12, -0.36, -0.26, 1.04),
            13: c.body(13, -0.18, -0.40, 0.92),
            14: c.body(14, -0.02, -0.50, 0.72),
        },
    )
    c.planted.append(("foot_l", 0, 2))
    c.keys(
        "foot_l_rot",
        {
            2: c.turned("foot_l"),
            3: c.turned("foot_l", 0, 25, 0),
            4: c.turned("foot_l", 0, 55, 0),
            6: c.turned("foot_l", -10, 60, -10),
            10: c.turned("foot_l", -30, 40, -40),
            13: c.turned("foot_l", -10, 60, -15),
        },
    )
    c.keys("foot_l_pole", {4: P(0.0, 1.0, 0.0), 6: P(-0.2, 1.0, 0.3), 10: P(-0.5, 0.8, 0.9), 13: P(-0.2, 1.0, 0.3)})
    c.keys(
        "ball_l",
        {2: c.spine("ball_l"), 3: c.spine("ball_l", 0, -22, 0), 4: c.spine("ball_l", 0, -45, 0), 6: c.spine("ball_l")},
    )

    # The right leg leads: the knee drives up and out, the leg passes over the top and reaches down to land.
    c.keys(
        "foot_r_pos",
        {
            4: c.body(4, -0.18, 0.08, 0.58),
            6: c.body(6, -0.42, 0.34, 0.98),
            8: c.body(8, -0.62, 0.42, 1.08),
            10: c.body(10, -0.50, 0.48, 0.86),
            12: c.body(12, -0.28, 0.48, 0.56),
            14: c.body(14, -0.13, 0.42, 0.28),
        },
    )
    c.keys(
        "foot_r_rot",
        {
            4: c.turned("foot_r", -10, 20, 0),
            6: c.turned("foot_r", -30, 10, -30),
            8: c.turned("foot_r", -35, 10, -50),
            12: c.turned("foot_r", -10, 15, -15),
            14: c.turned("foot_r", 0, 5, 0),
        },
    )
    c.keys(
        "foot_r_pole",
        {
            4: P(-0.2, 1.0, 0.2),
            6: P(-0.5, 0.8, 0.6),
            8: P(-0.4, 0.6, 1.0),
            12: P(-0.3, 1.0, 0.2),
            14: P(-0.1, 1.0, 0.0),
        },
    )

    c.events = {"takeoff": 4, "hand_plant": 7, "over": 9, "hand_release": 9, "land": 16}
    c.notes = {
        "hand_place": {"left": 0.27, "forward": 0.12, "wrist_above_top": PALM},
        "hand": "left",
        "takeoff_foot": "left",
        "landing_foot": "right",
        "weapon": "the right hand keeps the sprint's fist",
    }
    return c


def vault_land(rig):
    """The landing step: down on the right foot, a deeper knee than a sprint step, and off into the sprint."""
    c = Clip(rig, "Vault_Land", frames=10, speed=4.0, start=0.0, box_height=0.0, box_depth=0.0)
    for frame in (-2, 0):
        c.pose_from(frame, SPRINT, frame + 8)
    for frame in (10, 12):
        c.pose_from(frame, SPRINT, frame - 10)
    stance = c.channels["foot_r_pos"].at(0)
    c.keys("foot_r_pos", {3: stance, 5: stance + P(0.0, 0.07, 0.10), 8: c.body(8, -0.09, -0.55, 0.42)})
    c.planted.append(("foot_r", 0, 3))
    c.keys("foot_r_rot", {3: c.turned("foot_r"), 5: c.turned("foot_r", 0, 55, 0), 8: c.turned("foot_r", 0, 70, 0)})
    c.keys("ball_r", {3: c.spine("ball_r"), 5: c.spine("ball_r", 0, -40, 0), 7: c.spine("ball_r")})
    c.keys(
        "pelvis_pos",
        {
            2: c.body(2, -0.01, -0.07, 0.79),
            3: c.body(3, -0.01, -0.07, 0.78),
            6: c.body(6, 0.0, -0.07, 0.90),
            8: c.body(8, 0.01, -0.07, 0.93),
        },
    )
    c.keys("pelvis_rot", {3: c.turned("pelvis", 0, 16, -2), 7: c.turned("pelvis", 0, 10, 0)})
    for name in ("spine_01", "spine_02", "spine_03"):
        c.keys(name, {3: c.spine(name, 0, 7, 0)})
    c.keys(
        "foot_l_pos", {3: c.body(3, 0.09, -0.05, 0.34), 6: c.body(6, 0.09, 0.42, 0.42), 8: c.body(8, 0.09, 0.50, 0.32)}
    )

    c.keys("foot_l_rot", {3: c.turned("foot_l", 0, 35, 0), 6: c.turned("foot_l", 0, -5, 0)})
    c.keys("hand_l_pos", {3: c.body(3, 0.36, 0.20, 0.92), 6: c.body(6, 0.40, -0.12, 1.08)})
    c.keys("hand_r_pos", {3: c.body(3, -0.40, -0.22, 0.98), 6: c.body(6, -0.33, 0.28, 0.98)})
    c.events = {"land": 0, "push_off": 5, "sprint": 10}
    c.notes = {"landing_foot": "right", "next": "Sprint at 0 s (the left foot lands)"}
    return c


def vault_high(rig):
    """A two-handed side vault: a short step, off the right foot with both hands on top, the hips up over the
    hands and both legs swung over to the right as the right hand lets go, down on the right foot."""
    c = Clip(rig, "Vault_High", frames=26, speed=3.0, start=1.86, box_height=1.2, box_depth=0.4)
    top = c.box_height
    for frame in (-2, 0):
        c.pose_from(frame, SPRINT, frame)
    c.pose_from(2, SPRINT, 2, only={"pelvis_rot", "foot_r_pos", "foot_r_pole", "foot_r_rot", "ball_r"})
    for frame in (26, 28):
        c.pose_from(frame, SPRINT, frame - 18)

    c.keys(
        "pelvis_pos",
        {
            2: c.body(2, 0.0, -0.06, 0.84),
            4: c.body(4, 0.0, -0.06, 0.90),
            6: c.body(6, 0.0, -0.06, 0.86),
            8: c.body(8, 0.0, -0.05, 0.80),
            10: c.body(10, 0.0, -0.04, 0.92),
            12: c.body(12, -0.03, -0.03, 1.20),
            14: c.body(14, -0.07, -0.02, 1.38),
            16: c.body(16, -0.10, 0.0, 1.44),
            18: c.body(18, -0.10, 0.0, 1.42),
            20: c.body(20, -0.07, -0.03, 1.28),
            22: c.body(22, -0.04, -0.05, 1.10),
            24: c.body(24, -0.02, -0.06, 0.95),
        },
    )
    c.keys(
        "pelvis_rot",
        {
            4: c.turned("pelvis", 0, 10, 0),
            8: c.turned("pelvis", 0, 22, 0),
            10: c.turned("pelvis", 0, 25, 5),
            12: c.turned("pelvis", -3, 34, 10),
            14: c.turned("pelvis", -10, 30, 36),
            16: c.turned("pelvis", -15, 12, 55),
            18: c.turned("pelvis", -12, 4, 42),
            20: c.turned("pelvis", -6, 8, 22),
            22: c.turned("pelvis", 0, 12, 8),
        },
    )
    for name in ("spine_01", "spine_02", "spine_03"):
        c.keys(
            name,
            {
                4: c.spine(name, 0, 4, 0),
                8: c.spine(name, 0, 8, 0),
                12: c.spine(name, 2, 12, 0),
                16: c.spine(name, 4, 5, 2),
                20: c.spine(name, 2, 4, 0),
                23: c.spine(name, 0, 4, 0),
            },
        )
    c.keys(
        "neck_01",
        {
            8: c.spine("neck_01", 0, -8, 0),
            12: c.spine("neck_01", 0, -14, -4),
            16: c.spine("neck_01", -4, -18, -20),
            22: c.spine("neck_01", 0, -8, -4),
        },
    )
    c.keys(
        "Head",
        {
            8: c.spine("Head", 0, -8, 0),
            12: c.spine("Head", 0, -14, -4),
            16: c.spine("Head", -6, -18, -22),
            22: c.spine("Head", 0, -8, -4),
        },
    )

    # Both hands go onto the top, 0.10 m in from the front edge; the right lets go first to let the legs by.
    plant_l = P(0.24, 0.10, top + PALM)
    plant_r = P(-0.24, 0.10, top + PALM)
    c.keys(
        "hand_l_pos",
        {
            4: c.body(4, 0.36, 0.05, 1.0),
            8: c.body(8, 0.30, 0.32, 1.25),
            10: plant_l + P(0.0, -0.12, 0.10),
            11: plant_l,
            16: plant_l,
            17: plant_l + P(0.04, 0.14, 0.20),
            18: plant_l + P(0.08, 0.30, 0.27),
            20: c.body(20, 0.36, -0.15, 1.25),
            24: c.body(24, 0.34, 0.05, 1.0),
        },
    )
    c.keys(
        "hand_r_pos",
        {
            4: c.body(4, -0.36, 0.15, 0.98),
            8: c.body(8, -0.30, 0.32, 1.25),
            10: plant_r + P(0.0, -0.12, 0.10),
            11: plant_r,
            13: plant_r,
            15: c.body(15, -0.42, 0.12, 1.50),
            17: c.body(17, -0.55, 0.0, 1.75),
            20: c.body(20, -0.55, -0.05, 1.60),
            23: c.body(23, -0.45, -0.08, 1.25),
        },
    )
    c.planted += [("hand_l", 11, 16), ("hand_r", 11, 13)]
    c.keys("hand_l_pole", {8: P(0.4, -1.0, -0.8), 11: P(0.6, -1.0, 0.1), 16: P(0.7, -0.4, 0.8), 22: P(0.5, -1.0, 0.2)})
    c.keys(
        "hand_r_pole",
        {
            8: P(-0.4, -1.0, -0.8),
            11: P(-0.6, -1.0, 0.1),
            13: P(-0.8, -0.8, 0.4),
            18: P(-0.6, -1.0, -0.3),
            23: P(-0.6, -1.0, -0.2),
        },
    )
    flat_l = c.palm("l", (0.2, 1.0, 0.0), (0.0, 0.0, -1.0))
    flat_r = c.palm("r", (-0.2, 1.0, 0.0), (0.0, 0.0, -1.0))
    c.keys(
        "hand_l_rot",
        {
            0: flat_l,
            11: flat_l,
            16: c.palm("l", (0.45, 1.0, 0.0), (0.0, 0.0, -1.0)),
            17: c.palm("l", (0.4, 1.0, -0.5), (0.0, -0.5, -1.0)),
            26: flat_l,
        },
    )
    c.keys(
        "hand_r_rot",
        {0: flat_r, 11: flat_r, 13: flat_r, 14: c.palm("r", (-0.3, 1.0, 0.3), (0.0, 0.2, -1.0)), 26: flat_r},
    )
    c.keys("hand_l_world", {8: 0.0, 11: 1.0, 18: 1.0, 20: 0.0})
    c.keys("hand_r_world", {8: 0.0, 11: 1.0, 13: 1.0, 15: 0.0})

    c.keys("curl_l", {8: 1.0, 10: 0.0, 16: 0.0, 20: 1.0})
    c.keys("curl_r", {8: 1.0, 10: 0.0, 13: 0.0, 17: 1.0})

    # The left foot finishes its sprint step, swings through and tucks; the right foot takes off close to the wall.
    stance = c.channels["foot_l_pos"].at(0)
    c.keys(
        "foot_l_pos",
        {
            3: stance,
            4: stance + P(0.0, 0.04, 0.07),
            5: stance + P(0.0, 0.10, 0.20),
            7: c.body(7, 0.09, -0.45, 0.45),
            9: c.body(9, 0.10, -0.12, 0.30),
            11: c.body(11, 0.08, 0.08, 0.42),
            13: c.body(13, -0.02, -0.30, 0.85),
            15: c.body(15, -0.30, -0.12, 1.40),
            17: c.body(17, -0.50, 0.0, 1.52),
            19: c.body(19, -0.45, 0.05, 1.42),
            21: c.body(21, -0.25, -0.15, 1.10),
            23: c.body(23, -0.05, -0.38, 0.78),
        },
    )
    c.keys(
        "foot_l_rot",
        {
            3: c.turned("foot_l"),
            4: c.turned("foot_l", 0, 30, 0),
            5: c.turned("foot_l", 0, 60, 0),
            9: c.turned("foot_l", 0, 30, 0),
            13: c.turned("foot_l", -10, 40, -10),
            17: c.turned("foot_l", -30, 40, -40),
            22: c.turned("foot_l", -10, 60, -15),
        },
    )
    c.keys(
        "foot_l_pole",
        {
            5: P(0.0, 1.0, 0.0),
            11: P(0.0, 1.0, 0.2),
            13: P(-0.8, 0.4, 0.5),
            15: P(-0.6, 0.6, 0.6),
            17: P(-0.5, 0.8, 0.9),
            22: P(-0.2, 1.0, 0.3),
        },
    )
    c.keys(
        "ball_l",
        {3: c.spine("ball_l"), 4: c.spine("ball_l", 0, -25, 0), 5: c.spine("ball_l", 0, -45, 0), 7: c.spine("ball_l")},
    )
    takeoff = P(-0.09, c.forward(6) + 0.30, 0.104)
    c.keys(
        "foot_r_pos",
        {
            4: c.body(4, -0.09, 0.05, 0.32),
            6: takeoff,
            9: takeoff,
            10: takeoff + P(0.0, 0.03, 0.06),
            11: takeoff + P(0.0, 0.07, 0.16),
            12: takeoff + P(-0.04, 0.14, 0.36),
            14: c.body(14, -0.40, -0.05, 1.20),
            15: c.body(15, -0.54, 0.10, 1.42),
            17: c.body(17, -0.68, 0.25, 1.52),
            19: c.body(19, -0.55, 0.40, 1.25),
            21: c.body(21, -0.35, 0.45, 0.90),
            23: c.body(23, -0.18, 0.42, 0.50),
        },
    )
    c.planted += [("foot_l", 0, 3), ("foot_r", 6, 9)]
    c.keys(
        "foot_r_rot",
        {
            4: c.turned("foot_r", 0, -10, 0),
            6: c.turned("foot_r"),
            9: c.turned("foot_r"),
            10: c.turned("foot_r", 0, 25, 0),
            11: c.turned("foot_r", 0, 45, 0),
            12: c.turned("foot_r", 0, 60, 0),
            15: c.turned("foot_r", -30, 20, -30),
            17: c.turned("foot_r", -35, 10, -50),
            21: c.turned("foot_r", -10, 15, -15),
            24: c.turned("foot_r", 0, 5, 0),
        },
    )
    c.keys(
        "foot_r_pole",
        {
            6: P(0.0, 1.0, 0.0),
            12: P(-0.2, 1.0, 0.2),
            15: P(-0.5, 0.8, 0.6),
            17: P(-0.4, 0.6, 1.0),
            21: P(-0.3, 1.0, 0.2),
            24: P(-0.1, 1.0, 0.0),
        },
    )
    c.keys(
        "ball_r",
        {
            4: c.spine("ball_r"),
            9: c.spine("ball_r"),
            10: c.spine("ball_r", 0, -22, 0),
            11: c.spine("ball_r", 0, -40, 0),
            12: c.spine("ball_r", 0, -45, 0),
            14: c.spine("ball_r"),
        },
    )

    c.events = {"takeoff": 11, "hand_plant": 11, "right_hand_release": 13, "over": 16, "hand_release": 16, "land": 26}
    c.notes = {
        "hand_place": {"left": 0.24, "forward": 0.10, "wrist_above_top": PALM},
        "hand": "both, the left stays longer",
        "takeoff_foot": "right",
        "landing_foot": "right",
        "weapon": "none: both hands are open on the obstacle",
    }
    return c


CLIPS = {"Vault_Low": vault_low, "Vault_High": vault_high, "Vault_Land": vault_land}


# ---------------------------------------------------------------------------------------------------------------
# Baking, checks, export
# ---------------------------------------------------------------------------------------------------------------
def bake(rig, clip, fist):
    """Key the clip onto the armature, one key a frame on every bone, and return what the solver could not reach."""
    arm = rig.arm
    action = bpy.data.actions.new(clip.name)
    arm.animation_data_create()
    arm.animation_data.action = action
    last = {}
    worst = {}
    # What the planted hands ask of the body on each frame, smoothed over time so the body is not jerked; the
    # arm, kept a little bent, takes up the difference.
    pulls = [clip.solve(frame, fist)[2] for frame in range(-2, clip.frames + 3)]
    for _ in range(2):
        padded = [Vector()] + pulls + [Vector()]
        pulls = [padded[i] * 0.25 + padded[i + 1] * 0.5 + padded[i + 2] * 0.25 for i in range(len(pulls))]
    clip.pulls = pulls[2:-2]
    clip.pulled = {frame: round(pull.length, 4) for frame, pull in enumerate(clip.pulls)}
    for frame in range(clip.frames + 1):
        mats, reach_error, _pull = clip.solve(frame, fist, clip.pulls[frame])
        for limb, error in reach_error.items():
            for name, first, final in clip.planted:
                if name == limb and first <= frame <= final:
                    worst[limb] = max(worst.get(limb, 0.0), error)
                    if error > 0.002:
                        print(f"REACH {clip.name} {limb} frame {frame}: {error * 1000:.0f} mm short")
        for name in rig.order:
            bone = arm.pose.bones[name]
            bone.rotation_mode = "QUATERNION"
            quat = aligned(rig.basis(name, mats), last.get(name))
            last[name] = quat
            bone.rotation_quaternion = quat
            bone.keyframe_insert("rotation_quaternion", frame=frame)
            if name == "pelvis":
                rel = mats["root"].inverted() @ mats["pelvis"]
                bone.location = (rig.rest_rel[name].inverted() @ rel).translation
                bone.keyframe_insert("location", frame=frame)
    arm.animation_data.action_slot = action.slots[0]
    return action, worst


def skinned(rig, frame):
    bpy.context.scene.frame_set(frame)
    graph = bpy.context.evaluated_depsgraph_get()
    obj = rig.mesh.evaluated_get(graph)
    mesh = obj.to_mesh()
    world = obj.matrix_world
    points = [world @ v.co for v in mesh.vertices]
    groups = [[obj.vertex_groups[g.group].name for g in v.groups if g.weight > 0.3] for v in mesh.vertices]
    obj.to_mesh_clear()
    return points, groups


def check(rig, clip, action, worst):
    """Fail on what a vault can get wrong: skin under the floor or in the box, a planted hand or foot that moves."""
    arm = rig.arm
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    problems = []
    report = {"lowest": 9.0, "deepest_in_box": 0.0}
    for frame in range(1, clip.frames + 1):
        step = (clip.pulls[frame] - clip.pulls[frame - 1]).length
        if step > PULL_STEP:
            problems.append(f"frame {frame}: the planted hand jerks the body {step * 1000:.0f} mm")
    for limb, error in worst.items():
        if error > 0.002:
            problems.append(f"{limb} cannot reach its planted place by {error * 1000:.0f} mm")
    palm_gap = []
    held = {}
    for frame in range(clip.frames + 1):
        points, groups = skinned(rig, frame)
        for limb, first, final in clip.planted:
            if first <= frame <= final:
                place = clip.to_world(frame, arm.pose.bones[limb].head.copy())
                held.setdefault((limb, first), []).append(place)

        ahead = clip.forward(frame)
        lowest = min(p.z for p in points)
        report["lowest"] = min(report["lowest"], lowest)
        if lowest < -FLOOR_LIMIT:
            problems.append(f"frame {frame}: {-lowest * 1000:.0f} mm under the floor")
        if clip.box_height > 0.0:
            deepest, where = 0.0, ""
            for point, names in zip(points, groups):
                forward = -point.y + ahead
                if 0.0 < forward < clip.box_depth and abs(point.x) < BOX_HALF_WIDTH and point.z < clip.box_height:
                    depth = min(clip.box_height - point.z, forward, clip.box_depth - forward)
                    if depth > deepest:
                        deepest, where = depth, ",".join(names)
            report["deepest_in_box"] = max(report["deepest_in_box"], deepest)
            if deepest > BOX_LIMIT:
                problems.append(f"frame {frame}: {deepest * 1000:.0f} mm into the box ({where})")
            for limb, first, final in clip.planted:
                if limb.startswith("hand") and first <= frame <= final:
                    hand = [p.z for p, names in zip(points, groups) if any(n.startswith(limb) for n in names)]
                    palm_gap.append(min(hand) - clip.box_height)
    for (limb, first), places in held.items():
        drift = max((place - places[0]).length for place in places)
        report[f"{limb}_drift_mm"] = round(max(report.get(f"{limb}_drift_mm", 0.0), drift * 1000), 1)
        if drift > PLANT_LIMIT:
            problems.append(f"{limb} planted at frame {first} moves {drift * 1000:.0f} mm")
    if palm_gap:
        report["palm_gap_mm"] = [round(min(palm_gap) * 1000, 1), round(max(palm_gap) * 1000, 1)]
        if max(abs(g) for g in palm_gap) > PALM_LIMIT:
            problems.append(f"the planted palm is {report['palm_gap_mm']} mm from the top")
    report["lowest"] = round(report["lowest"], 4)
    report["deepest_in_box"] = round(report["deepest_in_box"], 4)
    return problems, report


def sidecar(clips):
    out = {"fps": FPS, "units": "metres and seconds; forward 0 is the obstacle's front face", "clips": {}}
    for clip in clips:
        entry = {
            "length": round(clip.frames / FPS, 4),
            "frames": clip.frames,
            "loop": False,
            "speed": clip.speed,
            "travel": round(clip.speed * clip.frames / FPS, 4),
            "events": {name: round(frame / FPS, 4) for name, frame in clip.events.items()},
        }
        entry.update(clip.notes)
        if clip.box_height > 0.0:
            entry["obstacle"] = {"height": clip.box_height, "depth": clip.box_depth}
            entry["root_start"] = -clip.start
            entry["root_at"] = {name: round(clip.forward(frame), 4) for name, frame in clip.events.items()}
            entry["contacts"] = clip.contacts
        out["clips"][clip.name] = entry
    return out


def export(rig, actions, out):
    """Write the armature and its clips, with a one-triangle skin so Godot makes a Skeleton3D of every bone."""
    arm = rig.arm
    for obj in rig.library_objects + [rig.mesh]:
        bpy.data.objects.remove(obj, do_unlink=True)
    for action in rig.library_actions:
        bpy.data.actions.remove(action)
    mesh = bpy.data.meshes.new("VaultRig")
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0, 0.01)], [], [(0, 1, 2)])
    proxy = bpy.data.objects.new("VaultRig", mesh)
    bpy.context.scene.collection.objects.link(proxy)
    proxy.parent = arm
    proxy.vertex_groups.new(name="root").add([0, 1, 2], 1.0, "REPLACE")
    proxy.modifiers.new("Armature", "ARMATURE").object = arm
    arm.animation_data.action = None
    for action in actions:
        track = arm.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.action_slot = action.slots[0]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (arm, proxy):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = out / "vault.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_skins=True,
        export_materials="NONE",
        export_yup=True,
    )
    return path


def strip(path):
    """Keep only what a clip should drive: every bone's rotation and the pelvis's place. The exporter also writes
    each bone's rest translation and scale, which would press this rig's bone lengths onto the other mannequin."""
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + length])
    rest = data[20 + length :]
    for animation in gltf["animations"]:
        channels, samplers = [], []
        for channel in animation["channels"]:
            target = channel["target"]
            name = gltf["nodes"][target["node"]]["name"]
            if target["path"] == "rotation" or (target["path"] == "translation" and name == "pelvis"):
                samplers.append(animation["samplers"][channel["sampler"]])
                channels.append({"sampler": len(samplers) - 1, "target": target})
        animation["channels"], animation["samplers"] = channels, samplers
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    body = struct.pack("<II", len(text), 0x4E4F534A) + text + rest
    path.write_bytes(data[:8] + struct.pack("<I", 12 + len(body)) + body)


def read_back(path):
    """The clip names, lengths and animated bones of the exported file."""
    data = path.read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + length])
    blob = data[20 + length + 8 :]
    out = {}
    for animation in gltf["animations"]:
        end = 0.0
        for sampler in animation["samplers"]:
            end = max(end, gltf["accessors"][sampler["input"]]["max"][0])
        moved = sorted(
            gltf["nodes"][ch["target"]["node"]]["name"]
            for ch in animation["channels"]
            if ch["target"]["path"] == "translation"
        )
        out[animation["name"]] = {"length": round(end, 4), "channels": len(animation["channels"]), "translation": moved}
    del blob
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(HERE))
    parser.add_argument("--render", default="")
    parser.add_argument("--only", default="")
    parser.add_argument("--no-fail", action="store_true")
    args = parser.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    rig = Rig()
    pose = rig.library_pose(SPRINT, 0)
    fist = {name: rig.basis(name, pose) for side in "lr" for name in rig.finger_bones(side)}
    names = [args.only] if args.only else FILE_CLIPS
    clips = [CLIPS[name](rig) for name in names]
    actions, failed = [], False
    for clip in clips:
        action, worst = bake(rig, clip, fist)
        problems, report = check(rig, clip, action, worst)
        clip.contacts = report
        print(f"CLIP {clip.name}: {clip.frames} frames, {report}")
        print(f"PULLED {clip.name}:", {f: v for f, v in clip.pulled.items() if v}, clip.pullers)
        for problem in problems:
            failed = True
            print(f"PROBLEM {clip.name}: {problem}")
        actions.append(action)
    if args.render:
        import render_vault

        render_vault.render(rig, clips, actions, Path(args.render))
    if failed and not args.no_fail:
        sys.exit("the clips fail their checks; nothing was exported")
    if args.only:
        return
    path = export(rig, actions, out)
    strip(path)
    found = read_back(path)
    assert sorted(found) == sorted(FILE_CLIPS), f"the file carries {sorted(found)}, not {FILE_CLIPS}"
    for clip in clips:
        assert abs(found[clip.name]["length"] - clip.frames / FPS) < 1e-3, (clip.name, found[clip.name])
        assert found[clip.name]["translation"] == ["pelvis"], found[clip.name]["translation"]
        assert found[clip.name]["channels"] == len(rig.order) + 1, found[clip.name]["channels"]
    (out / "vault_clips.json").write_text(json.dumps(sidecar(clips), indent=2) + "\n", encoding="utf-8")
    print("EXPORTED", path, json.dumps(found)[:400])


if __name__ == "__main__":
    sys.path.insert(0, str(HERE))
    main()
