"""Build the template's vault clips and export them as an animation library (kit #1010).

GDStudio's own clips, keyed from scratch on Quaternius's universal rig (the template's mannequins and the Universal
Animation Library share it): `Vault_Low` (a one-handed speed vault), `Vault_High` (a two-handed side vault) and
`Vault_Land` (the landing step back into the sprint). Nothing is copied from another clip but the first and last
poses, which are the library's own `Sprint_Loop` so the clips join the run.

The same keys are solved once for each body that plays them, into a file a body (`BODIES`, gdstudio #1294): a planted
hand is on its place only on the arms it was solved for.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute, the default body first (the
others are held to its numbers); `--python-exit-code 1` because Blender exits 0 when a script raises:

    blender -b --factory-startup --python-exit-code 1 -P <this file> -- [--body <name>] [--out <folder>]
        [--render <folder>] [--only <clip>] [--trace] [--no-fail]

How a clip is made: every clip is a table of keys on a small set of controls (the pelvis, the spine, each wrist and
ankle with the way its elbow or knee points, the hands and feet, the fingers' curl), written in the **world** of a
reference obstacle: a box whose front face is at forward 0, so a planted hand or foot is two keys at one place. The
body's root moves forward at a constant speed (`speed`, from `start` metres before the front face) and is taken out
again, so the exported clip is in place like the library's. The solver below turns the controls into bone rotations
(two-bone IK about each limb's own hinge axis), and the build checks the skinned mesh on every frame against the
floor and the box before it exports.

From a vault's jump on, the pelvis is not keyed by hand. The clip says where the body's centre of mass is on every
frame (`Clip.drive`): on the arc of a free fall while nothing touches it, and on a curve between two heights and
speeds while a hand carries it. The build keys each clip a few times, measuring how far the centre of mass is above
the pelvis in every pose, until the pelvis sits under it. `check_motion` then fails on a move a body cannot make.

Positions are `(left, forward, up)` in metres: left is the character's left, forward the way it runs, forward 0 the
obstacle's front face. Angles are `(yaw, pitch, roll)` in degrees: yaw turns left, pitch leans forward, roll leans
to the left.
"""

import argparse
import json
import math
import os
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent.parent
## The bodies a clip file is solved on (`--body`), one file a body: a planted hand is on its place only on the arms
## it was solved for, and the legs go over clear of each other only on the thighs they were keyed around (gdstudio
## #1294). `file` is the body, `out` the clip file and `sidecar` its numbers; the rest is what differs from body to
## body, each measured on that body with `--trace`:
## `palm` how far the wrist bone rides above a surface the palm lies on; `strike` the height of the centre of mass in
## the sprint's foot strike (both vaults end there, `Vault_Land` starts there), `low_takeoff` the same on the frame
## the speed vault leaves the ground, `high_crouch` the same in the low point of the side vault's last step (frame
## 9), where its jump starts. The `low_*` and `high_*` numbers are the keys of `Vault_Low` and `Vault_High` that a
## body's arms and thighs move; each is explained where the clip reads it, and a body that names none gets the keys
## as they were made on the Quaternius female (her file is the same bytes as before the bodies were split).
## `VAULT_TUNE` in the environment (a JSON object) overrides numbers of the chosen body for one run, to try them.
BODIES = {
    "form_female": {
        "file": ASSETS / "characters" / "prototype" / "form_female.glb",
        "out": "vault.glb",
        "sidecar": "vault_clips.json",
        "palm": 0.022,
        "strike": 0.950,
        "low_takeoff": 1.065,
        "high_crouch": 0.915,
        "high_lift": 0.02,
        "high_spread": (0.075, 0.03),
        "high_knees": (0.15, 0.2),
        "high_edge": 1.5,
        "high_late": 1.3,
        "high_l14_foot": (-0.02, -0.30, -0.40),
        "high_l14_pole": (-1.0, 0.4, 0.25),
        "high_l16_foot": (-0.36, -0.27, -0.10),
        "low_l7_pole": (-0.75, 0.6, -0.6),
    },
    "form_male": {
        "file": ASSETS / "characters" / "prototype" / "form_male.glb",
        "out": "vault_male.glb",
        "sidecar": "vault_male_clips.json",
        "palm": 0.028,
        "strike": 0.962,
        "low_takeoff": 1.078,
        "high_crouch": 0.925,
        "high_lift": 0.01,
        "high_shrug": 10.0,
        "high_spread": (0.10, 0.035),
        "high_knees": (0.15, 0.2),
        "high_knee_16": 0.6,
        "high_late": 1.3,
        "high_roll": 3.0,
        "high_l14_foot": (-0.02, -0.30, -0.40),
        "high_l14_pole": (-1.0, 0.4, 0.28),
        "high_l16_foot": (-0.36, -0.27, -0.10),
        "low_l7_pole": (-0.75, 0.6, -0.6),
        "low_lift": 0.03,
        "low_tilt": 0.15,
        "low_shrug": 10.0,
        "low_free": (0.05, 0.0, 0.03),
    },
    "quaternius_female": {
        "file": ASSETS / "characters" / "mannequin" / "mannequin_female.glb",
        "out": "vault_quaternius.glb",
        "sidecar": "vault_quaternius_clips.json",
        "palm": 0.036,
        "strike": 0.964,
        "low_takeoff": 1.073,
        "high_crouch": 0.925,
    },
}
## The body whose file every other body's is held to: the same lengths, speeds, contact times and hand places, so
## the vault code has one set of numbers.
DEFAULT_BODY = "form_female"
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
## A planted arm is never straighter than this share of its length.
ARM_REACH = 0.94

## A game draws the clip between its keys (60 frames a second and more, where the clip has 24): the build measures
## this many times a frame (240 a second), with the keys joined by straight lines as a player joins them. Between
## the keys no leg joint's middle may be deeper in the box than this (m), on either mannequin, and the skin keeps
## `BOX_LIMIT`: two keys that are both clear of the box say nothing of the path between them.
BETWEEN = 10
JOINT_LIMIT = 0.005
LEG_JOINTS = ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]
## A planted hand or foot is held by a chain of joints, and joints joined by straight lines do not hold its end
## still: between two keys the palm presses into the top and the sole into the floor, under the contact where it
## does not show. The skin of a hand from the frame before its plant to the frame after its release, and the
## lowest skin over the floor, get these limits between the keys (m; the clips read 16.3 mm and 20.8 mm).
PRESS_LIMIT = 0.02
FLOOR_PRESS_LIMIT = 0.025
HAND_PARTS = ("hand", "thumb", "index", "middle", "ring", "pinky")

## The most a planted hand may move the body off its keyed path from one frame to the next (m).
PULL_STEP = 0.02
## How deep one body part may be inside another that no joint joins it to (mm), on either mannequin, on any frame:
## skin on skin and no more (`limb_overlap.py` measures it; the library's own clips never cross the legs at all).
OVERLAP_LIMIT = 5.0


## An arm that has let go, or is free while the other carries the body, follows the body: its wrist stays under
## this height over its own shoulder (m), moves no faster than this in the world and against its shoulder (m/s),
## and its speed changes by no more than this from one frame to the next (m/s): no fling, no snap.
FREE_OVER_SHOULDER = 0.05
FREE_SPEED = 7.0
FREE_SPEED_AGAINST_SHOULDER = 4.5
FREE_SPEED_CHANGE = 4.0

## Gravity (m/s^2): a body in the air, touching nothing, falls on this arc and no other.
# The legs over the obstacle (`legs_of`), while the hips are over its top: the knees and the ankles no farther apart
# than this many widths of the hip joints (legs astride the hands read as a squat on the box; they go over together,
# to one side), no knee folded tighter than this, and no knee, ankle or toe bone under the top.
LEGS_KNEE_SPREAD = 2.0
LEGS_ANKLE_SPREAD = 2.6
LEGS_FOLD = 40.0
# From the takeoff until the legs come down: an ankle's speed against the hips changes by no more than this in one
# frame (m/s; a leg that stops and starts again, or turns back), and from the front face on neither ankle rests
# against the hips (under this speed, m/s) for two frames running: a held pose in the air.
LEGS_SPEED_CHANGE = 6.0
LEGS_HELD = 1.0
GRAVITY = 9.81
## How far the body's centre may be off the arc of a free fall on any frame in the air (m).
ARC_LIMIT = 0.015
## The body's mass by part, each a share of the whole at a point between two bones (the share of the way from the
## first to the second): rounded from the usual tables of body segments (Dempster; de Leva 1996). The centre of
## mass is what gravity moves, so the checks of the fall measure it, not the pelvis: legs that reach down and arms
## that swing move the pelvis the other way.
MASS = [
    ("Head", "Head", 0.0, 0.08),
    ("pelvis", "neck_01", 0.5, 0.50),
    ("upperarm_l", "lowerarm_l", 0.44, 0.028),
    ("upperarm_r", "lowerarm_r", 0.44, 0.028),
    ("lowerarm_l", "hand_l", 0.43, 0.016),
    ("lowerarm_r", "hand_r", 0.43, 0.016),
    ("hand_l", "hand_l", 0.0, 0.006),
    ("hand_r", "hand_r", 0.0, 0.006),
    ("thigh_l", "calf_l", 0.43, 0.10),
    ("thigh_r", "calf_r", 0.43, 0.10),
    ("calf_l", "foot_l", 0.43, 0.0465),
    ("calf_r", "foot_r", 0.43, 0.0465),
    ("foot_l", "ball_l", 0.5, 0.0145),
    ("foot_r", "ball_r", 0.5, 0.0145),
]


def centre_of_mass(mats):
    """The body's centre of mass from armature-space bone matrices (`MASS`)."""
    total, mass = Vector(), 0.0
    for first, second, share, part in MASS:
        a, b = mats[first].translation, mats[second].translation
        total += (a + (b - a) * share) * part
        mass += part
    return total / mass


def angle_at(mats, first, middle, last):
    """The angle of a joint in degrees (180 is straight), from three bones' places."""
    a = mats[first].translation - mats[middle].translation
    b = mats[last].translation - mats[middle].translation
    return math.degrees(a.angle(b))


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


def fall(height, speed, seconds):
    """Where a body in the air is after `seconds`: it left `height` going up at `speed`, and only gravity acts."""
    return height + speed * seconds - 0.5 * GRAVITY * seconds * seconds


def carried(start, start_speed, end, end_speed, length, seconds):
    """A height between two given heights and speeds, `seconds` into `length`: the body while a hand or a foot
    carries it (a cubic, so the speed dips when the end is nearer than the two speeds would take it: the limb
    takes the load, gives, and then pushes)."""
    s = seconds / length
    return (
        start * (2 * s**3 - 3 * s**2 + 1)
        + start_speed * length * (s**3 - 2 * s**2 + s)
        + end * (-2 * s**3 + 3 * s**2)
        + end_speed * length * (s**3 - s**2)
    )


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

    def __init__(self, name):
        self.name = name
        self.body = BODIES[name]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = FPS
        bpy.ops.import_scene.gltf(filepath=str(self.body["file"]))
        self.arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        # The nearest level of detail of a prototype body (the farther ones lie inside it).
        self.mesh = max(
            (o for o in bpy.data.objects if o.type == "MESH" and o.parent == self.arm),
            key=lambda o: len(o.data.vertices),
        )
        mine = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(LIBRARY))
        self.library_objects = [o for o in bpy.data.objects if o not in mine]
        self.library_arm = next(o for o in self.library_objects if o.type == "ARMATURE")
        for track in self.library_arm.animation_data.nla_tracks:
            track.mute = True
        self.library_actions = list(bpy.data.actions)
        # The body as the overlap check measures it: the file is this body's own.
        import limb_overlap

        self.bodies = [limb_overlap.Body(self.arm, self.mesh, name)]
        self.order = [b.name for b in self.arm.data.bones]  # parents before children
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in self.arm.data.bones}
        self.rest = {b.name: b.matrix_local.copy() for b in self.arm.data.bones}
        self.rest_rel = {
            n: (self.rest[self.parent[n]].inverted() @ self.rest[n]) if self.parent[n] else self.rest[n].copy()
            for n in self.order
        }
        self.rest_rot = {n: self.rest[n].to_3x3() for n in self.order}
        # The bones a clip keys: the library's own. A body may have more (the prototype bodies' twist and IK
        # bones), which no clip drives and another body does not have.
        theirs = {b.name for b in self.library_arm.data.bones}
        self.keyed = [n for n in self.order if n in theirs]
        # The twist bones of a prototype body, which no clip keys and the game turns (`limb_overlap.twist_bones`).
        self.twists = limb_overlap.twist_bones(self.rest_rel)
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
            if name not in bones:
                out[name] = out[parent] @ self.rest_rel[name]
                continue
            rel = bones[parent].matrix.inverted() @ bones[name].matrix
            offset = rel.translation if name == "pelvis" else self.rest_rel[name].translation
            out[name] = out[parent] @ Matrix.LocRotScale(offset, rel.to_quaternion(), None)
        return out

    def twist(self, mats):
        """Put the twist bones where the game's modifier turns them for the pose in `mats`, so the skin the
        checks measure is the skin a player sees: the shoulder's and the hip's take the limb's roll about its own
        length back out, the wrist's takes the hand's roll."""
        import limb_overlap

        for twist, source, axis, counter in self.twists:
            parent = self.parent[source]
            rel = (mats[parent].inverted() @ mats[source]).to_quaternion()
            roll = limb_overlap.twist_roll(self.rest_rel, source, rel, axis, counter)
            base = mats[source] if counter else mats[parent]
            rest = self.rest_rel[twist]
            mats[twist] = (
                base @ Matrix.Translation(rest.translation) @ roll.to_matrix().to_4x4() @ rest.to_3x3().to_4x4()
            )

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

    def __init__(self, rig, name, frames, speed, start, box_height, box_depth, offsets=None):
        self.rig = rig
        # How far the body's centre of mass is above the keyed pelvis on each frame, measured on the last pass
        # (`settle`): `drive` keys the pelvis from where the centre of mass has to be.
        self.offsets = offsets or {}
        self.flights = []  # (first frame, last frame) with nothing touching: the centre of mass falls freely
        self.push = None  # (limb, first frame, last frame): the arm that carries the body over
        self.reach = None  # (limb, the frame it lands): the leg that reaches for the ground
        self.centre = {}  # frame: the height the centre of mass was asked to be at
        self.mats = {}
        self.absorb = None  # (limb, first frame, last frame): the leg that gives under the landing
        self.released = []  # (limb, first frame, last frame): an arm nothing holds, from its last planted frame
        self.motion = {}
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
        self.trace = {}

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

    def drive(self, path, centre):
        """Key the pelvis on every frame of `centre` (frame: the height of the body's centre of mass) so the
        centre of mass is there: gravity and the limbs that carry the body decide its height, the pose decides
        how far under it the pelvis is. `path` is sparse keys of the pelvis's `(left, forward)` from the root."""
        across = Channel()
        for frame, (left, forward) in path.items():
            across.key(frame, Vector((left, forward)))
        for frame, height in centre.items():
            left, forward = across.at(frame)
            self.centre[frame] = height
            self.key("pelvis_pos", frame, self.body(frame, left, forward, height - self.offsets.get(frame, 0.10)))

    def under(self, frame, left, forward, down):
        """A point given from the pelvis bone in the world's axes: `down` is toward the floor however the hips
        are turned (a foot that reaches for the ground)."""
        return self.channels["pelvis_pos"].at(frame) + P(left, forward, -down)

    def settle(self, fist):
        """Solve every frame: the planted hands' pull on the body, smoothed over time so the body is not jerked
        (the arm, kept a little bent, takes up the difference), then every bone's matrix and what the checks
        read from it. Returns the centre of mass's height over the keyed pelvis, for the next pass of `drive`."""
        self.pullers = {}
        pulls = [self.solve(frame, fist)[2] for frame in range(-2, self.frames + 3)]
        for _ in range(2):
            padded = [Vector()] + pulls + [Vector()]
            pulls = [padded[i] * 0.25 + padded[i + 1] * 0.5 + padded[i + 2] * 0.25 for i in range(len(pulls))]
        self.pulls = pulls[2:-2]
        self.pulled = {frame: round(pull.length, 4) for frame, pull in enumerate(self.pulls)}
        offsets = {}
        for frame in range(self.frames + 1):
            mats, reach_error, _pull = self.solve(frame, fist, self.pulls[frame])
            self.mats[frame] = (mats, reach_error)
            self.trace[frame] = measure_pose(self.rig, mats)
            offsets[frame] = self.trace[frame]["com"].z - self.channels["pelvis_pos"].at(frame).z
        return offsets

    def shoulder(self, frame, side, left=0.0, forward=0.0, up=0.0):
        """A point given from a shoulder joint in the world's axes, from the keys of the pelvis, the spine and
        the collarbone at that frame (key those first): `up` is how far over the shoulder a hand is, whatever
        the body's lean, so a free arm's height is written down and not a result of the hips' roll."""
        at = Matrix.LocRotScale(self.channels["pelvis_pos"].at(frame), self.channels["pelvis_rot"].at(frame), None)
        chain = ["spine_01", "spine_02", "spine_03", f"clavicle_{side}"]
        for name in chain:
            at = at @ self.rig.rest_rel[name] @ self.channels[name].at(frame).to_matrix().to_4x4()
        return (at @ self.rig.rest_rel[f"upperarm_{side}"]).translation + P(left, forward, up)

    def spine(self, name, yaw=0.0, pitch=0.0, roll=0.0):
        """A bend of a spine bone, given in the rig's axes, as the bone's own rotation."""
        rest = self.rig.rest_rot[name]
        return (rest.inverted() @ R(yaw, pitch, roll) @ rest).to_quaternion()

    def turned(self, name, yaw=0.0, pitch=0.0, roll=0.0):
        """A bone's armature-space rotation: its rest turned in the rig's axes (pelvis, feet)."""
        return (R(yaw, pitch, roll) @ self.rig.rest_rot[name]).to_quaternion()

    def hips_turn(self, frame):
        """The pelvis's turn from its rest at a frame, from its keys (key the pelvis before anything given in
        the hips' axes)."""
        return self.channels["pelvis_rot"].at(frame).to_matrix() @ self.rig.rest_rot["pelvis"].inverted()

    def hips(self, frame, left, forward, up):
        """A point given from the pelvis bone in the hips' own axes at that frame: `left` is the body's left
        however the body is rolled. A foot keyed with `left` above 0 and the other below it cannot cross."""
        return self.channels["pelvis_pos"].at(frame) + self.hips_turn(frame) @ P(left, forward, up)

    def hips_way(self, frame, left, forward, up):
        """A direction given in the hips' axes at that frame (where a knee or an elbow points)."""
        return self.hips_turn(frame) @ P(left, forward, up)

    def hips_turned(self, frame, name, yaw=0.0, pitch=0.0, roll=0.0):
        """A bone's armature-space rotation: its rest turned in the hips' axes at that frame (a foot in the air)."""
        return (self.hips_turn(frame) @ R(yaw, pitch, roll) @ self.rig.rest_rot[name]).to_quaternion()

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
        rig.twist(mats)
        return mats, reach_error, pull


# ---------------------------------------------------------------------------------------------------------------
# The clips
# ---------------------------------------------------------------------------------------------------------------
SPRINT = "Sprint_Loop"  # 16 frames at 24: the left foot lands at 0, the right at 8
## The speed the body is falling at when `Vault_Land` starts (m/s): between the two vaults' (2.7 and 3.7).
LAND_SPEED = 3.3


def vault_low(rig, offsets=None):
    """A speed vault: off the left foot, the left hand on top, both legs swung over to the right, down on the
    right foot. The left arm carries the body over: it takes the weight as the shoulder comes over the hand (the
    elbow gives), then pushes, and the push is what lifts the body off the top and gives it its time in the air.
    The right hand never comes near the obstacle, so it can hold a pistol."""
    c = Clip(rig, "Vault_Low", frames=19, speed=4.0, start=1.3, box_height=0.8, box_depth=0.4, offsets=offsets)
    own = rig.body
    top = c.box_height
    last = c.frames
    # In and out of the sprint: its poses a little before and after give the curves the run's own speed.
    for frame in (-2, 0):
        c.pose_from(frame, SPRINT, frame)
    c.pose_from(2, SPRINT, 2, only={"pelvis_rot", "foot_r_pos", "foot_r_pole", "foot_r_rot", "ball_r"})
    for frame in (last, last + 2):
        c.pose_from(frame, SPRINT, frame - last + 8)

    c.keys("pelvis_pos", {2: c.body(2, 0.0, -0.06, 0.82), 4: c.body(4, -0.02, -0.04, 0.95)})
    # From the takeoff on, the pelvis is keyed from the body's centre of mass (`drive`). In the air it is on the
    # arc of a free fall. While the hand is on the top the arm carries it: the rise slows as the arm takes the
    # weight and gives, then the push sends the body off the top faster than it came on, and that speed is all
    # the time in the air it gets.
    takeoff, plant, release = 4, 6, 10
    off_foot = (own["low_takeoff"], 1.657)
    on_hand = (fall(*off_foot, (plant - takeoff) / FPS), off_foot[1] - GRAVITY * (plant - takeoff) / FPS)
    air = (last - release) / FPS
    off_hand = (1.32, (own["strike"] - 1.32 + 0.5 * GRAVITY * air * air) / air)
    centre = {}
    for frame in range(takeoff + 1, last):
        if frame <= plant:
            centre[frame] = fall(*off_foot, (frame - takeoff) / FPS)
        elif frame <= release:
            centre[frame] = carried(*on_hand, *off_hand, (release - plant) / FPS, (frame - plant) / FPS)
        else:
            centre[frame] = fall(*off_hand, (frame - release) / FPS)
    end = c.to_place(last, c.channels["pelvis_pos"].at(last))
    c.drive(
        {
            4: (-0.02, -0.04),
            6: (-0.06, 0.0),
            9: (-0.12, -0.02),
            12: (-0.10, -0.02),
            16: (-0.04, -0.05),
            last: (end.x, -end.y),
        },
        centre,
    )
    c.flights = [(takeoff, plant), (release, last)]
    c.push = ("hand_l", plant, release)
    c.reach = ("foot_r", last)
    c.released = [("hand_r", takeoff, last)]
    c.arc = {"off_foot": off_foot, "on_hand": on_hand, "off_hand": off_hand, "land": own["strike"]}

    # The body lies over to the left as it passes the hand and comes upright again on the way down.
    c.keys(
        "pelvis_rot",
        {
            4: c.turned("pelvis", 0, 18, 10),
            6: c.turned("pelvis", -4, 20, 48),
            8: c.turned("pelvis", -8, 18, 60),
            10: c.turned("pelvis", -8, 10, 56),
            12: c.turned("pelvis", -5, 12, 38),
            15: c.turned("pelvis", -2, 12, 14),
            17: c.turned("pelvis", 0, 13, 4),
        },
    )
    # The chest turns toward the planted hand as the body goes by, so the hand can stay and leave last.
    for name in ("spine_01", "spine_02", "spine_03"):
        c.keys(
            name,
            {
                4: c.spine(name, 2, 5, 1),
                6: c.spine(name, 0, 11, 4),
                8: c.spine(name, 8, 8, 7),
                10: c.spine(name, 11, 3, 5),
                12: c.spine(name, 5, 5, 2),
                15: c.spine(name, 0, 5, 0),
            },
        )
    c.keys(
        "neck_01",
        {5: c.spine("neck_01", -2, -10, -10), 8: c.spine("neck_01", -4, -16, -22), 14: c.spine("neck_01", 0, -6, -4)},
    )
    c.keys("Head", {5: c.spine("Head", -3, -12, -10), 8: c.spine("Head", -6, -18, -24), 14: c.spine("Head", 0, -6, -4)})
    # The shoulder sinks toward the hand while the arm carries the body (the collarbone drops 20 degrees), and comes
    # back with the push.
    c.keys(
        "clavicle_l",
        {
            5: c.spine("clavicle_l"),
            6: c.spine("clavicle_l", 0, 0, 8),
            8: c.spine("clavicle_l", 0, 0, 20),
            10: c.spine("clavicle_l", 0, 0, 4 - own.get("low_shrug", 0.0)),
            13: c.spine("clavicle_l"),
        },
    )

    # The left hand: forward and down onto the top, 0.12 m in from the front edge. The wrist stays while the body
    # passes over it; then the heel of the hand lifts and the fingers leave last; then the arm trails behind and
    # low before it swings forward for the landing.
    plant_at = P(0.27, 0.12, top + own["palm"])
    c.keys(
        "hand_l_pos",
        {
            2: c.body(2, 0.36, 0.05, 1.02),
            4: c.body(4, 0.34, 0.30, 1.05),
            6: plant_at,
            9: plant_at,
            # `low_lift` and `low_tilt`: longer fingers tip less as the heel of the hand lifts, or they go into the top.
            10: plant_at + P(0.01, 0.03, own.get("low_lift", 0.035)),
            12: c.body(12, 0.40, -0.42, 1.12),
            14: c.body(14, 0.42, -0.30, 1.10),
            17: c.body(17, 0.38, 0.02, 0.98),
        },
    )
    c.planted.append(("hand_l", plant, release - 1))
    c.keys(
        "hand_l_pole",
        {
            4: P(0.5, -1.0, 0.2),
            6: P(0.6, -1.0, 0.3),
            8: P(0.9, -0.6, 0.4),
            10: P(0.7, -0.4, 0.8),
            14: P(0.5, -1.0, 0.2),
        },
    )
    low_tilt = own.get("low_tilt", 0.45)
    flat = c.palm("l", (0.3, 1.0, 0.0), (0.0, 0.0, -1.0))
    c.keys(
        "hand_l_rot",
        {
            0: flat,
            6: flat,
            9: c.palm("l", (0.45, 1.0, 0.0), (0.0, 0.0, -1.0)),
            10: c.palm("l", (0.4, 1.0, -low_tilt), (0.0, -low_tilt, -1.0)),
            11: c.palm("l", (0.4, 1.0, -0.6), (0.0, -0.6, -1.0)),
            last: flat,
        },
    )
    c.keys("hand_l_world", {4: 0.0, 6: 1.0, 11: 1.0, 13: 0.0})
    c.keys("curl_l", {4: 1.0, 5: 0.0, 11: 0.0, 15: 1.0})

    # The right arm is free and follows the body: keyed from its own shoulder (`shoulder`), it lies back along the
    # upper side of the rolled body with the wrist no higher than the shoulder while the left arm carries the body
    # (a point up from the rolled hips put it 0.37 m over the shoulder, above the head, in two frames), then down
    # and back as the body comes upright, into the sprint's swing.
    # A longer free arm lies further out from the hip (`low_free`: further right, forward, up).
    free = own.get("low_free", (0.0, 0.0, 0.0))
    c.keys(
        "hand_r_pos",
        {
            4: c.body(4, -0.40, 0.06, 1.20),
            6: c.shoulder(6, "r", -0.33 - free[0], -0.30 + free[1], -0.06 + free[2]),
            8: c.shoulder(8, "r", -0.34 - free[0], -0.30 + free[1], 0.0 + free[2]),
            10: c.shoulder(10, "r", -0.36 - free[0], -0.26 + free[1], -0.04 + free[2]),
            12: c.shoulder(12, "r", -0.40, -0.20, -0.10),
            14: c.shoulder(14, "r", -0.40, -0.16, -0.18),
            16: c.shoulder(16, "r", -0.24, -0.22, -0.36),
        },
    )
    c.keys(
        "hand_r_pole",
        {6: P(-0.4, -1.0, 0.4), 10: P(-0.4, -1.0, 0.4), 15: P(-0.6, -1.0, -0.2)},
    )

    # The legs go over stacked, as in a real speed vault: the body is rolled to the left, so the right leg is the
    # upper one and the left leg the lower, each on its own side of the hips (`hips`: left above 0 for the left
    # foot, below 0 for the right), knees a hip's width apart. They never cross.
    # The left leg pushes off, trails, tucks under the right leg with its knee forward, and stays behind on the
    # way down as the trailing leg of the landing stride. On frame 7 its knee is out beside the rolled body (the
    # thigh in line with the trunk, the shin folded back) and already over the top, a frame before it passes the
    # front edge: with the ankle behind the hip and the knee pointed forward, the knee hung straight down under
    # the top there and whipped forward through the edge between frames 7 and 8 (gdstudio #1221).
    stance = c.channels["foot_l_pos"].at(0)
    c.keys(
        "foot_l_pos",
        {
            2: stance,
            3: stance + P(0.0, 0.03, 0.05),
            4: stance + P(0.0, 0.08, 0.17),
            6: c.body(6, 0.08, -0.44, 0.78),
            7: c.body(7, -0.21, -0.15, top + 0.34),
            8: c.hips(8, 0.20, 0.10, -0.16),
            10: c.hips(10, 0.20, 0.14, -0.18),
            12: c.hips(12, 0.17, 0.08, -0.24),
            14: c.hips(14, 0.14, -0.08, -0.32),
            16: c.hips(16, 0.13, -0.24, -0.36),
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
            8: c.hips_turned(8, "foot_l", -25, 5, 0),
            10: c.hips_turned(10, "foot_l", -25, 5, 0),
            15: c.hips_turned(15, "foot_l", 0, 50, 0),
        },
    )
    c.keys(
        "foot_l_pole",
        {
            4: P(0.0, 1.0, 0.0),
            6: c.hips_way(6, 0.15, 1.0, 0.2),
            # Lower on thicker thighs, clear of the upper leg's thigh (5.0 mm into it on the prototype male).
            7: P(*own.get("low_l7_pole", (-0.75, 0.6, -0.4))),
            8: c.hips_way(8, 0.15, 1.0, 0.25),
            10: c.hips_way(10, 0.15, 1.0, 0.25),
            15: c.hips_way(15, 0.2, 1.0, 0.1),
        },
    )
    c.keys(
        "ball_l",
        {2: c.spine("ball_l"), 3: c.spine("ball_l", 0, -22, 0), 4: c.spine("ball_l", 0, -45, 0), 6: c.spine("ball_l")},
    )

    # The right leg leads like a hurdler's: the knee drives up and the leg reaches over the top. Past the far
    # edge it opens and reaches down for the ground, a little more each frame, the toes first: it is nearly
    # straight a frame before the foot lands, and the knee is already giving as it does (`Vault_Land` goes on).
    c.keys(
        "foot_r_pos",
        {
            4: c.body(4, -0.18, 0.08, 0.58),
            6: c.hips(6, -0.30, 0.40, -0.13),
            8: c.hips(8, -0.24, 0.55, -0.06),
            10: c.hips(10, -0.20, 0.56, -0.16),
            12: c.hips(12, -0.16, 0.52, -0.30),
            14: c.under(14, -0.14, 0.44, 0.44),
            16: c.under(16, -0.12, 0.38, 0.60),
            17: c.under(17, -0.11, 0.34, 0.68),
            18: c.under(18, -0.10, 0.31, 0.73),
        },
    )
    # The lead foot is lifted and held back a little on frame 5, toes up (`foot_r_rot`), so the toes are over the
    # top when they pass the front edge between frames 5 and 6 (they cut it by 40 mm; gdstudio #1221).
    c.key("foot_r_pos", 5, c.channels["foot_r_pos"].at(5) + P(0.0, -0.03, 0.06))
    c.keys(
        "foot_r_rot",
        {
            4: c.turned("foot_r", -10, 20, 0),
            5: c.hips_turned(5, "foot_r", 0, -15, 0),
            6: c.hips_turned(6, "foot_r", 0, -5, 0),
            8: c.hips_turned(8, "foot_r", 0, 10, 0),
            12: c.hips_turned(12, "foot_r", 0, 10, 0),
            15: c.turned("foot_r", 0, 16, 0),
            18: c.turned("foot_r", 0, 14, 0),
        },
    )
    c.keys(
        "foot_r_pole",
        {
            4: P(-0.2, 1.0, 0.2),
            6: c.hips_way(6, -0.3, 0.8, 0.8),
            8: c.hips_way(8, -0.3, 0.6, 1.0),
            10: c.hips_way(10, -0.25, 0.8, 0.8),
            12: c.hips_way(12, -0.15, 1.0, 0.3),
            15: P(-0.1, 1.0, 0.0),
        },
    )

    c.events = {
        "takeoff": takeoff,
        "hand_plant": plant,
        "over": 9,
        "hand_release": release - 1,
        "push_off": release,
        "land": last,
    }
    c.notes = {
        "hand_place": {"left": 0.27, "forward": 0.12, "wrist_above_top": own["palm"]},
        "hand": "left",
        "takeoff_foot": "left",
        "landing_foot": "right",
        "weapon": "the right hand keeps the sprint's fist",
    }
    return c


def vault_land(rig, offsets=None):
    """The landing step: the right foot is down and the body is still falling. The knee and the hip give under
    it (the hips drop 0.14 m in three frames, the chest comes forward), then the leg drives off into the sprint."""
    c = Clip(rig, "Vault_Land", frames=10, speed=4.0, start=0.0, box_height=0.0, box_depth=0.0, offsets=offsets)
    for frame in (-2, 0):
        c.pose_from(frame, SPRINT, frame + 8)
    for frame in (10, 12):
        c.pose_from(frame, SPRINT, frame - 10)
    stance = c.channels["foot_r_pos"].at(0)
    c.keys("foot_r_pos", {3: stance, 5: stance + P(0.0, 0.07, 0.10), 8: c.body(8, -0.09, -0.55, 0.42)})
    c.planted.append(("foot_r", 0, 3))
    c.keys("foot_r_rot", {3: c.turned("foot_r"), 5: c.turned("foot_r", 0, 55, 0), 8: c.turned("foot_r", 0, 70, 0)})
    c.keys("ball_r", {3: c.spine("ball_r"), 5: c.spine("ball_r", 0, -40, 0), 7: c.spine("ball_r")})
    # The body arrives falling (the vaults end at 2.7 and 3.7 m/s down; this clip starts at 3.3): the hips go on
    # down, fast at first and slower as the leg takes the weight, to their lowest on the third frame.
    strike = c.to_place(0, c.channels["pelvis_pos"].at(0))
    del c.channels["pelvis_pos"].keys[-2.0]
    c.keys(
        "pelvis_pos",
        {
            -1: c.body(-1, strike.x, -strike.y, strike.z + LAND_SPEED / FPS),
            1: c.body(1, -0.01, -0.07, strike.z - 0.067),
            2: c.body(2, -0.01, -0.07, strike.z - 0.115),
            3: c.body(3, -0.01, -0.07, strike.z - 0.137),
            4: c.body(4, -0.005, -0.07, strike.z - 0.125),
            6: c.body(6, 0.0, -0.07, 0.875),
            8: c.body(8, 0.01, -0.07, 0.925),
        },
    )
    c.keys(
        "pelvis_rot",
        {2: c.turned("pelvis", 0, 20, -2), 4: c.turned("pelvis", 0, 18, -1), 7: c.turned("pelvis", 0, 10, 0)},
    )
    for name in ("spine_01", "spine_02", "spine_03"):
        c.keys(name, {3: c.spine(name, 0, 8, 0)})
    c.keys(
        "foot_l_pos", {3: c.body(3, 0.09, -0.05, 0.34), 6: c.body(6, 0.09, 0.42, 0.42), 8: c.body(8, 0.09, 0.50, 0.32)}
    )

    c.keys("foot_l_rot", {3: c.turned("foot_l", 0, 35, 0), 6: c.turned("foot_l", 0, -5, 0)})
    c.keys("hand_l_pos", {3: c.body(3, 0.36, 0.20, 0.88), 6: c.body(6, 0.40, -0.12, 1.08)})
    c.keys("hand_r_pos", {3: c.body(3, -0.40, -0.22, 0.94), 6: c.body(6, -0.33, 0.28, 0.98)})
    c.absorb = ("foot_r", 0, 3)
    c.events = {"land": 0, "lowest": 3, "push_off": 5, "sprint": 10}
    c.notes = {"landing_foot": "right", "next": "Sprint at 0 s (the left foot lands)"}
    return c


def vault_high(rig, offsets=None):
    """A two-handed side vault: a short step, off the right foot with both hands on top, the hips up over the
    hands and rolled onto the left arm, both legs over together on the right, parallel to the obstacle, as the
    right hand lets go, down on the right foot. The arms take
    a third of the body's weight from the moment the foot leaves: the elbows are bent under it at the plant and
    straighten as the hips rise over the hands, the left arm locks as the body passes over it and pushes off
    last, and the body is still rising when it leaves the hand."""
    c = Clip(rig, "Vault_High", frames=30, speed=3.0, start=1.86, box_height=1.2, box_depth=0.4, offsets=offsets)
    own = rig.body
    top = c.box_height
    last = c.frames
    for frame in (-2, 0):
        c.pose_from(frame, SPRINT, frame)
    c.pose_from(2, SPRINT, 2, only={"pelvis_rot", "foot_r_pos", "foot_r_pole", "foot_r_rot", "ball_r"})
    for frame in (last, last + 2):
        c.pose_from(frame, SPRINT, frame - last + 8)

    c.keys(
        "pelvis_pos",
        {
            2: c.body(2, 0.0, -0.06, 0.84),
            4: c.body(4, 0.0, -0.06, 0.90),
            6: c.body(6, 0.0, -0.06, 0.86),
            8: c.body(8, 0.0, -0.05, 0.80),
            9: c.body(9, 0.0, -0.045, 0.835),
        },
    )
    # From the push of the right foot on, the pelvis is keyed from the body's centre of mass (`drive`): the leg
    # throws it up, the arms carry part of it while a hand is on the top, and from the left hand's push it is on
    # the arc of a free fall, over the far edge still rising, to the height of the sprint's foot strike.
    crouch, takeoff, release = 9, 11, 17
    in_crouch = (own["high_crouch"], 1.2)
    off_foot = (1.12, 3.0)
    air = (last - release) / FPS
    support = (release - takeoff) / FPS
    # The speed off the hand that lands the body on the last frame, with the arms' share of the weight even.
    speed = (own["strike"] + 0.5 * GRAVITY * air * air - off_foot[0] - 0.5 * off_foot[1] * support) / (air + 0.5 * support)
    off_hand = (off_foot[0] + 0.5 * (off_foot[1] + speed) * support, speed)
    centre = {}
    for frame in range(crouch + 1, last):
        if frame <= takeoff:
            centre[frame] = carried(*in_crouch, *off_foot, (takeoff - crouch) / FPS, (frame - crouch) / FPS)
        elif frame <= release:
            centre[frame] = carried(*off_foot, *off_hand, support, (frame - takeoff) / FPS)
        else:
            centre[frame] = fall(*off_hand, (frame - release) / FPS)
    end = c.to_place(last, c.channels["pelvis_pos"].at(last))
    c.drive(
        {
            9: (0.0, -0.045),
            10: (0.0, -0.04),
            12: (-0.03, -0.03),
            14: (-0.07, -0.02),
            16: (-0.07, 0.0),
            18: (-0.07, 0.0),
            22: (-0.08, -0.02),
            26: (-0.04, -0.05),
            last: (end.x, -end.y),
        },
        centre,
    )
    c.flights = [(release, last)]
    c.push = ("hand_l", takeoff, release)
    c.reach = ("foot_r", last)
    c.released = [("hand_r", 12, last)]
    c.legs = (takeoff, 23)
    c.arc = {"off_foot": off_foot, "off_hand": off_hand, "land": own["strike"]}

    # Thicker thighs: the hips roll onto the arm a little sooner (`high_roll`, degrees more on frame 14), so the
    # lower thigh does not swing across under the upper one at the front edge.
    early = own.get("high_roll", 0.0)
    c.keys(
        "pelvis_rot",
        {
            4: c.turned("pelvis", 0, 10, 0),
            8: c.turned("pelvis", 0, 22, 0),
            10: c.turned("pelvis", 0, 25, 5),
            12: c.turned("pelvis", -3, 34, 10),
            13: c.turned("pelvis", -6, 32, 26 + early * 0.6),
            14: c.turned("pelvis", -10, 27, 44 + early),
            15: c.turned("pelvis", -12, 20, 58 + early * 0.6),
            16: c.turned("pelvis", -14, 14, 68),
            17: c.turned("pelvis", -14, 10, 72),
            18: c.turned("pelvis", -13, 8, 70),
            19: c.turned("pelvis", -11, 7, 62),
            20: c.turned("pelvis", -9, 6, 50),
            22: c.turned("pelvis", -6, 8, 30),
            24: c.turned("pelvis", -4, 10, 16),
            27: c.turned("pelvis", 0, 12, 5),
        },
    )
    # The chest turns toward the left hand as the body goes by it, so that hand can stay and leave last.
    for name in ("spine_01", "spine_02", "spine_03"):
        c.keys(
            name,
            {
                4: c.spine(name, 0, 4, 0),
                8: c.spine(name, 0, 8, 0),
                12: c.spine(name, 2, 12, 0),
                16: c.spine(name, 6, 5, 0),
                17: c.spine(name, 8, 4, -2),
                20: c.spine(name, 3, 4, 1),
                25: c.spine(name, 0, 4, 0),
            },
        )
    c.keys(
        "neck_01",
        {
            8: c.spine("neck_01", 0, -8, 0),
            12: c.spine("neck_01", 0, -14, -4),
            16: c.spine("neck_01", -4, -18, -20),
            25: c.spine("neck_01", 0, -8, -4),
        },
    )
    c.keys(
        "Head",
        {
            8: c.spine("Head", 0, -8, 0),
            12: c.spine("Head", 0, -14, -4),
            16: c.spine("Head", -6, -18, -22),
            25: c.spine("Head", 0, -8, -4),
        },
    )

    # Both hands go onto the top, 0.10 m in from the front edge; the right lets go first to let the legs by. The
    # left wrist stays until the body is over it; then the heel of the hand lifts and the fingers leave last.
    # The right hand lets go while its elbow is still bent (an arm at full stretch is torn off the top by the
    # rising shoulder): from rest it gains speed evenly over four frames on a path in the world, ahead of the
    # right knee that swings over, until it travels with the body; then it rides out to the right a little under
    # the shoulder (`shoulder`), a balance arm, and comes down into the sprint's swing with the landing.
    plant_l = P(0.24, 0.10, top + own["palm"])
    plant_r = P(-0.24, 0.10, top + own["palm"])
    c.keys(
        "hand_l_pos",
        {
            4: c.body(4, 0.36, 0.05, 1.0),
            8: c.body(8, 0.30, 0.32, 1.25),
            10: plant_l + P(0.0, -0.12, 0.10),
            11: plant_l,
            16: plant_l,
            # A longer arm is still bent when the body has passed, so its wrist lifts less on the frame it pushes
            # off (`high_lift`) and the arm is straight there (141 degrees on the prototype female otherwise).
            17: plant_l + P(0.01, 0.03, own.get("high_lift", 0.05)),
            19: c.body(19, 0.40, -0.40, 1.52),
            23: c.body(23, 0.42, -0.30, 1.45),
            27: c.body(27, 0.38, 0.0, 1.08),
        },
    )
    c.keys(
        "hand_r_pos",
        {
            4: c.body(4, -0.36, 0.15, 0.98),
            8: c.body(8, -0.30, 0.32, 1.25),
            10: plant_r + P(0.0, -0.12, 0.10),
            11: plant_r,
            12: plant_r,
            13: P(-0.25, 0.17, 1.32),
            14: P(-0.27, 0.31, 1.45),
            15: P(-0.29, 0.45, 1.62),
            16: P(-0.28, 0.54, 1.81),
            17: c.shoulder(17, "r", -0.43, 0.16, -0.02),
            18: c.shoulder(18, "r", -0.42, 0.14, -0.05),
            20: c.shoulder(20, "r", -0.40, 0.12, -0.09),
            23: c.shoulder(23, "r", -0.38, 0.08, -0.16),
            26: c.shoulder(26, "r", -0.34, -0.04, -0.28),
            28: c.shoulder(28, "r", -0.24, -0.18, -0.37),
        },
    )
    c.planted += [("hand_l", 11, 16), ("hand_r", 11, 12)]
    c.keys(
        "hand_l_pole",
        {
            8: P(0.4, -1.0, -0.8),
            11: P(0.6, -1.0, 0.1),
            14: P(1.0, -0.6, 0.3),
            15: P(1.0, -0.2, 0.5),
            16: P(0.7, -0.4, 0.8),
            25: P(0.5, -1.0, 0.2),
        },
    )
    c.keys(
        "hand_r_pole",
        {
            8: P(-0.4, -1.0, -0.8),
            11: P(-0.6, -1.0, 0.1),
            12: P(-0.8, -0.8, 0.4),
            15: P(-0.8, -0.6, 0.5),
            16: P(-0.8, -0.5, 0.6),
            18: P(-0.5, -1.0, 0.2),
            23: P(-0.3, -1.0, -0.3),
            27: P(-0.6, -1.0, -0.2),
        },
    )
    # The heel of the left hand lifts about the fingers: the hand tips by what the wrist has risen.
    tilt = 0.3 * own.get("high_lift", 0.05) / 0.05
    flat_l = c.palm("l", (0.2, 1.0, 0.0), (0.0, 0.0, -1.0))
    flat_r = c.palm("r", (-0.2, 1.0, 0.0), (0.0, 0.0, -1.0))
    c.keys(
        "hand_l_rot",
        {
            0: flat_l,
            11: flat_l,
            16: c.palm("l", (0.45, 1.0, 0.0), (0.0, 0.0, -1.0)),
            17: c.palm("l", (0.4, 1.0, -tilt), (0.0, -tilt, -1.0)),
            18: c.palm("l", (0.4, 1.0, -0.6), (0.0, -0.6, -1.0)),
            last: flat_l,
        },
    )
    c.keys(
        "hand_r_rot",
        {0: flat_r, 11: flat_r, 12: flat_r, 13: c.palm("r", (-0.3, 1.0, 0.3), (0.0, 0.2, -1.0)), last: flat_r},
    )
    c.keys("hand_l_world", {8: 0.0, 11: 1.0, 18: 1.0, 20: 0.0})
    c.keys("hand_r_world", {8: 0.0, 11: 1.0, 13: 1.0, 16: 0.0})
    # A body with longer arms pushes the shoulder up off the hand as the arm straightens (the collarbone lifts).
    shrug = own.get("high_shrug", 0.0)
    if shrug:
        c.keys(
            "clavicle_l",
            {
                13: c.channels["clavicle_l"].at(13),
                16: c.spine("clavicle_l", 0, 0, -shrug * 0.8),
                17: c.spine("clavicle_l", 0, 0, -shrug),
                21: c.channels["clavicle_l"].at(21),
            },
        )

    c.keys("curl_l", {8: 1.0, 10: 0.0, 18: 0.0, 22: 1.0})
    c.keys("curl_r", {8: 1.0, 10: 0.0, 12: 0.0, 18: 1.0})

    def side(frame, left, forward, up):
        """A foot from the pelvis in the world's axes, while the body lies on its side over the top."""
        return c.under(frame, left, forward, -up)

    # The legs go over together, to the right, parallel to the obstacle (a side vault): the hips roll onto the left
    # arm (72 degrees at the push) and both legs trail behind and beside them, the knees a hip width apart and bent
    # about a right angle, the right leg on top; past the far edge they swing forward and down as the body comes
    # upright. Both feet are on one smooth path each from the pelvis in the world's axes (`side`): keyed in the
    # hips' own axes, the roll and the forward lean threw them 0.4 m in a frame. Before the fourth review the right
    # leg went over ahead like a hurdler's and the left stayed folded behind the hands, astride them: a squat on
    # the box (`LEGS_*`).
    # The left foot finishes its sprint step and swings through; its knee turns out to the right at the edge, the
    # hips being too low there to lift it over forward (0.12 m over the top, 0.26 m before the face).
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
            12: side(12, 0.07, -0.02, -0.62),
            13: side(13, 0.02, -0.16, -0.54),
            # On thicker thighs the lower foot is further back and down at the front edge, and its knee a little
            # higher (`high_l14_pole`): the thigh lies less across under the upper one (11 mm into it otherwise).
            14: side(14, *own.get("high_l14_foot", (-0.08, -0.28, -0.36))),
            15: side(15, -0.20, -0.32, -0.15),
            # ... and carries on a little further a frame later, so the ankle keeps one speed (`LEGS_SPEED_CHANGE`).
            16: side(16, *own.get("high_l16_foot", (-0.33, -0.28, -0.12))),
            17: side(17, -0.43, -0.21, -0.05),
            18: side(18, -0.48, -0.13, -0.02),
            19: side(19, -0.46, -0.05, -0.05),
            20: side(20, -0.38, -0.02, -0.16),
            21: side(21, -0.27, -0.05, -0.27),
            22: side(22, -0.15, -0.09, -0.36),
            24: c.hips(24, 0.14, -0.10, -0.38),
            27: c.hips(27, 0.13, -0.24, -0.38),
        },
    )
    c.keys(
        "foot_l_rot",
        {
            3: c.turned("foot_l"),
            4: c.turned("foot_l", 0, 30, 0),
            5: c.turned("foot_l", 0, 60, 0),
            9: c.turned("foot_l", 0, 30, 0),
            13: c.hips_turned(13, "foot_l", 0, 40, 0),
            15: c.hips_turned(15, "foot_l", 0, -10, 0),
            17: c.hips_turned(17, "foot_l", 0, 45, 0),
            20: c.hips_turned(20, "foot_l", 0, 45, 0),
            26: c.hips_turned(26, "foot_l", 0, 50, 0),
        },
    )
    c.keys(
        "foot_l_pole",
        {
            5: P(0.0, 1.0, 0.0),
            11: P(0.0, 1.0, 0.2),
            13: P(-0.5, 1.0, 0.0),
            14: P(*own.get("high_l14_pole", (-1.0, 0.4, 0.0))),
            15: P(-0.3, 1.0, 0.0),
            16: P(-0.3, 1.0, 0.15),
            20: P(-0.3, 1.0, 0.15),
            23: c.hips_way(23, 0.15, 1.0, 0.2),
            26: c.hips_way(26, 0.2, 1.0, 0.1),
        },
    )
    c.keys(
        "ball_l",
        {3: c.spine("ball_l"), 4: c.spine("ball_l", 0, -25, 0), 5: c.spine("ball_l", 0, -45, 0), 7: c.spine("ball_l")},
    )
    # The right leg pushes off and trails: it rises beside the left one, crosses the front edge two frames after
    # the hips and lies on top; past the far edge it opens and reaches down for the ground, a little more each
    # frame, the toes first (as in `Vault_Low`).
    foot = P(-0.09, c.forward(6) + 0.30, 0.104)
    c.keys(
        "foot_r_pos",
        {
            4: c.body(4, -0.09, 0.05, 0.32),
            6: foot,
            9: foot,
            10: foot + P(0.0, 0.03, 0.06),
            11: foot + P(0.0, 0.07, 0.20),
            12: foot + P(-0.04, 0.14, 0.44),
            13: c.body(13, -0.30, -0.33, 0.80),
            14: c.body(14, -0.47, -0.39, 1.07),
            15: c.body(15, -0.62, -0.39, top + 0.15),
            16: side(16, -0.61, -0.32, 0.0),
            17: side(17, -0.62, -0.25, 0.05),
            18: side(18, -0.62, -0.14, 0.06),
            19: side(19, -0.60, 0.02, -0.04),
            20: side(20, -0.56, 0.14, -0.14),
            21: side(21, -0.48, 0.26, -0.26),
            22: side(22, -0.38, 0.36, -0.36),
            24: c.under(24, -0.15, 0.46, 0.42),
            26: c.under(26, -0.13, 0.40, 0.56),
            28: c.under(28, -0.11, 0.34, 0.68),
            29: c.under(29, -0.10, 0.31, 0.73),
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
            15: c.hips_turned(15, "foot_r", 0, 0, 0),
            17: c.hips_turned(17, "foot_r", 0, 45, 0),
            19: c.hips_turned(19, "foot_r", 0, 45, 0),
            22: c.hips_turned(22, "foot_r", 0, 30, 0),
            25: c.turned("foot_r", 0, 16, 0),
            29: c.turned("foot_r", 0, 14, 0),
        },
    )
    c.keys(
        "foot_r_pole",
        {
            6: P(0.0, 1.0, 0.0),
            12: P(-0.2, 1.0, 0.2),
            14: P(-1.0, 0.6, 0.5),
            15: P(-0.7, 0.8, 0.6),
            16: P(-0.3, 1.0, 0.5),
            20: P(-0.3, 1.0, 0.3),
            22: P(-0.2, 1.0, 0.1),
            25: P(-0.1, 1.0, 0.0),
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

    # Thicker thighs lie further apart: each foot is moved out to its own side of the hips by the body's own
    # amount while the legs are over the top (gdstudio #1294: keyed for the Quaternius female's thighs, the legs
    # went 28 mm into each other on the prototype female and 16 mm on the male).
    out_l, out_r = own.get("high_spread", (0.0, 0.0))
    if out_l or out_r:
        share = {13: 0.4, 14: 0.8, 15: 1.0, 16: 1.0, 17: 1.0, 18: 1.0, 19: 1.0, 20: 1.0, 21: 0.8, 22: 0.4}
        # At the front edge the lower leg cannot go down (the top is under its knee), so the upper one goes up:
        # the lower foot waits, and the upper foot is lifted by `high_edge` times its share there.
        wait = {13: 0.0, 14: 0.0, 15: 0.4}
        # Past the far edge the lower leg has room under it and goes further out (`high_late` times its share).
        late = own.get("high_late", 1.0)
        wait.update({19: late, 20: late, 21: 0.8 * late})
        edge = own.get("high_edge", 1.0)
        lift = {13: 0.5 * edge, 14: edge, 15: 0.5 * (1.0 + edge)}
        moved = {
            frame: (
                c.channels["foot_l_pos"].at(frame) + c.hips_way(frame, out_l * wait.get(frame, part), 0.0, 0.0),
                c.channels["foot_r_pos"].at(frame) + c.hips_way(frame, -out_r * lift.get(frame, part), 0.0, 0.0),
            )
            for frame, part in share.items()
        }
        for frame, (left, right) in moved.items():
            c.key("foot_l_pos", frame, left)
            c.key("foot_r_pos", frame, right)
    # And each knee points further out to its own side.
    knee_l, knee_r = own.get("high_knees", (0.0, 0.0))
    if knee_l or knee_r:
        for limb, out in (("foot_l_pole", knee_l), ("foot_r_pole", -knee_r)):
            poles = {frame: c.channels[limb].at(frame).normalized() for frame in range(14, 22)}
            for frame, pole in poles.items():
                # Less at the front edge, where the hips are still low over the top.
                # The lower knee waits until it is past the front edge, where the hips are still low over the top.
                if out > 0.0:
                    part = {14: 0.0, 15: 0.3, 16: own.get("high_knee_16", 1.0)}.get(frame, 1.0)
                else:
                    part = {14: edge, 15: 0.5 * (1.0 + edge)}.get(frame, 1.0)
                c.key(limb, frame, pole + c.hips_way(frame, out * part, 0.0, 0.0))

    c.events = {
        "takeoff": takeoff,
        "hand_plant": 11,
        "right_hand_release": 12,
        "over": 16,
        "hand_release": release - 1,
        "push_off": release,
        "land": last,
    }
    c.notes = {
        "hand_place": {"left": 0.24, "forward": 0.10, "wrist_above_top": own["palm"]},
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
def measure_pose(rig, mats):
    """What the checks of the load, the push and the fall read from one solved pose (metres, degrees; in place)."""
    out = {"com": centre_of_mass(mats), "pelvis": mats["pelvis"].translation.copy()}
    out["head"] = mats["Head"].translation.copy()
    for side in "lr":
        shoulder, wrist = mats[f"upperarm_{side}"].translation, mats[f"hand_{side}"].translation
        length = rig.rest_rel[f"lowerarm_{side}"].translation.length + rig.rest_rel[f"hand_{side}"].translation.length
        out[f"shoulder_{side}"] = shoulder.copy()
        out[f"wrist_{side}"] = wrist.copy()
        out[f"arm_{side}"] = (wrist - shoulder).length / length
        out[f"elbow_{side}"] = angle_at(mats, f"upperarm_{side}", f"lowerarm_{side}", f"hand_{side}")
        out[f"knee_{side}"] = angle_at(mats, f"thigh_{side}", f"calf_{side}", f"foot_{side}")
        out[f"foot_{side}"] = mats[f"foot_{side}"].translation.copy()
        out[f"toe_{side}"] = mats[f"ball_{side}"].translation.copy()
        out[f"calf_{side}"] = mats[f"calf_{side}"].translation.copy()
        out[f"thigh_{side}"] = mats[f"thigh_{side}"].translation.copy()
    return out


def print_trace(clip):
    """One line a frame: where the body's centre and the pelvis are, the arms and the knees (`--trace`)."""
    print(
        f"TRACE {clip.name}: frame root | com up fwd vz | pelvis up | shoulder_l up fwd(world) | arm_l elbow_l | "
        "arm_r elbow_r | knee_l knee_r | foot_l up foot_r up"
    )
    for frame in range(clip.frames + 1):
        t = clip.trace[frame]
        before = clip.trace[max(frame - 1, 0)]["com"].z
        after = clip.trace[min(frame + 1, clip.frames)]["com"].z
        span = (min(frame + 1, clip.frames) - max(frame - 1, 0)) / FPS
        print(
            f"TRACE {clip.name} {frame:2d} {clip.forward(frame):+.3f} | {t['com'].z:.3f} {-t['com'].y:+.3f} "
            f"{(after - before) / span:+.2f} | {t['pelvis'].z:.3f} | {t['shoulder_l'].z:.3f} "
            f"{-t['shoulder_l'].y + clip.forward(frame):+.3f} | {t['arm_l']:.2f} {t['elbow_l']:3.0f} | "
            f"{t['arm_r']:.2f} {t['elbow_r']:3.0f} | {t['knee_l']:3.0f} {t['knee_r']:3.0f} | "
            f"{t['foot_l'].z:.2f} {t['foot_r'].z:.2f}"
        )


def bake(rig, clip):
    """Key the clip onto the armature, one key a frame on every bone, and return what the solver could not reach."""
    arm = rig.arm
    action = bpy.data.actions.new(clip.name)
    arm.animation_data_create()
    arm.animation_data.action = action
    last = {}
    worst = {}
    for frame in range(clip.frames + 1):
        mats, reach_error = clip.mats[frame]
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
    # Keys are joined by straight lines, as Godot joins the exported keys: a pose read between two frames
    # (`check_between`) is then the pose a game draws there. The export samples whole frames and is the same.
    for curve in curves_of(action):
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"
    return action, worst


def curves_of(action):
    return [c for layer in action.layers for strip in layer.strips for bag in strip.channelbags for c in bag.fcurves]


def skinned(rig, frame):
    whole = math.floor(frame)
    bpy.context.scene.frame_set(whole, subframe=frame - whole)
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
    # Limbs through each other, on the skinned mesh of the body the file is for, on every frame.
    import limb_overlap

    report["overlap_mm"] = {}
    measured = limb_overlap.measure(arm, action, range(clip.frames + 1), rig.bodies)
    for body, entry in measured.items():
        report["overlap_mm"][body] = {
            "deepest": entry["deepest_mm"],
            "frame": entry["frame"],
            "pair": entry["pair"],
            "by_class": {kind: value[0] for kind, value in sorted(entry["by_class"].items())},
        }
        print(f"OVERLAP {clip.name} {body}: per frame {entry['frames']} {entry['by_class']} {entry['pairs']}")
        if entry["frame"] is not None:
            at = clip.trace[entry["frame"]]
            print(
                f"OVERLAP {clip.name} {body}: deepest at {entry['place']}, hip joints "
                f"{[round(v, 3) for v in at['thigh_l']]} {[round(v, 3) for v in at['thigh_r']]}, knees "
                f"{[round(v, 3) for v in at['calf_l']]} {[round(v, 3) for v in at['calf_r']]}"
            )
        if entry["deepest_mm"] > OVERLAP_LIMIT:
            problems.append(
                f"{body}: {entry['pair']} by {entry['deepest_mm']} mm at frame {entry['frame']} "
                f"(the limit is {OVERLAP_LIMIT} mm)"
            )
    clip.overlap = measured
    between, report["between_keys"] = check_between(rig, clip, action)
    moving, motion = check_motion(clip)
    clip.motion = motion
    return problems + between + moving, report


def in_box(clip, point, ahead):
    """How deep a point of the body (in place, the root `ahead` of the front face) is inside the obstacle: under
    its top and past both faces, 0 when it is outside."""
    forward = -point.y + ahead
    if not (0.0 < forward < clip.box_depth and abs(point.x) < BOX_HALF_WIDTH and point.z < clip.box_height):
        return 0.0
    return min(clip.box_height - point.z, forward, clip.box_depth - forward)


def check_between(rig, clip, action):
    """Fail on what the body does between two keys: `BETWEEN` times a frame, with the keys joined as a player
    joins them and the root moved as the game moves it, each leg joint of both mannequins against the box, and
    the keyed mannequin's skin against the box and the floor. Each worst reading comes with its time in seconds."""
    arm = rig.arm
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    curves = curves_of(action)
    assert curves and all(k.interpolation == "LINEAR" for c in curves for k in c.keyframe_points), (
        f"{clip.name}: the baked keys are not joined by straight lines, so a pose between frames is not a game's"
    )
    scene = bpy.context.scene
    problems = []
    report = {"samples_a_second": FPS * BETWEEN, "joint_limit_mm": JOINT_LIMIT * 1000.0}
    joints = {body.name: [0.0, None, None] for body in rig.bodies}
    skin, pressed, lowest = [0.0, None, None], [0.0, None, None], [9.0, None]
    holding = {
        limb[-1]: [(first - 1, final + 1) for name, first, final in clip.planted if name == limb]
        for limb in ("hand_l", "hand_r")
    }
    rows = []  # one a sample, for `--trace`: frame, lowest skin, deepest skin in the box, deepest joint in the box
    for step in range(clip.frames * BETWEEN + 1):
        frame = step / BETWEEN
        seconds = round(frame / FPS, 4)
        ahead = clip.forward(frame)
        points, groups = skinned(rig, frame)
        low = min(p.z for p in points)
        if low < lowest[0]:
            lowest = [low, seconds]
        row = [frame, low, 0.0, "", 0.0, "", {}]
        rows.append(row)
        for name in ("thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r", "ball_r"):
            place = arm.pose.bones[name].head
            row[6][name] = (-place.y + ahead, place.z - clip.box_height)
        if clip.box_height <= 0.0:
            continue
        for point, names in zip(points, groups):
            depth = in_box(clip, point, ahead)
            if depth <= 0.0:
                continue
            if depth > row[2]:
                row[2:4] = depth, ",".join(names)
            # A planted hand's own skin is the contact; everything else has no business in the box.
            held = names and all(
                n.startswith(HAND_PARTS) and any(a <= frame <= b for a, b in holding[n[-1]]) for n in names
            )
            worst = pressed if held else skin
            if depth > worst[0]:
                worst[:] = depth, ",".join(names), seconds
        for body in rig.bodies:
            body.pose_from(arm)
            for name in LEG_JOINTS:
                place = body.arm.matrix_world @ body.arm.pose.bones[name].head
                depth = in_box(clip, place, ahead)
                if depth > row[4]:
                    row[4:6] = depth, f"{body.name} {name}"
                if depth > joints[body.name][0]:
                    joints[body.name] = [depth, name, seconds]
    clip.between = rows
    report["lowest"] = [round(lowest[0], 4), lowest[1]]
    if lowest[0] < -FLOOR_PRESS_LIMIT:
        problems.append(f"between the keys, at {lowest[1]} s: {-lowest[0] * 1000:.0f} mm under the floor")
    if clip.box_height > 0.0:
        report["skin_in_box_mm"] = [round(skin[0] * 1000, 1), skin[1], skin[2]]
        report["planted_hand_in_box_mm"] = [round(pressed[0] * 1000, 1), pressed[1], pressed[2]]
        if skin[0] > BOX_LIMIT:
            problems.append(f"between the keys, at {skin[2]} s: {skin[0] * 1000:.0f} mm into the box ({skin[1]})")
        if pressed[0] > PRESS_LIMIT:
            problems.append(
                f"between the keys, at {pressed[2]} s: the planted hand presses {pressed[0] * 1000:.0f} mm into the "
                f"box ({pressed[1]})"
            )
        report["joint_in_box_mm"] = {}
        for name, (depth, bone, seconds) in joints.items():
            report["joint_in_box_mm"][name] = [round(depth * 1000, 1), bone, seconds]
            if depth > JOINT_LIMIT:
                problems.append(
                    f"between the keys, at {seconds} s: {name}'s {bone} is {depth * 1000:.0f} mm inside the box "
                    f"(the limit is {JOINT_LIMIT * 1000:.0f} mm)"
                )
    return problems, report


def release_of(clip, limb, first, final):
    """What an arm that nothing holds does from `first` (the last frame its hand is planted, or the takeoff) to
    `final`: how high the wrist gets over its own shoulder and over the head bone, how fast it moves in the world
    (the body's own travel included) and against the shoulder, and the most its speed changes in one frame."""
    side = limb[-1]
    trace = clip.trace
    frames = list(range(first, final + 1))
    over = [trace[f][f"wrist_{side}"].z - trace[f][f"shoulder_{side}"].z for f in frames]
    world = [clip.to_world(f, trace[f][f"wrist_{side}"]) for f in frames]
    local = [trace[f][f"wrist_{side}"] - trace[f][f"shoulder_{side}"] for f in frames]
    steps = [(b - a) * FPS for a, b in zip(world, world[1:])]
    against = [(b - a).length * FPS for a, b in zip(local, local[1:])]
    changes = [(b - a).length for a, b in zip(steps, steps[1:])]
    head = [trace[f][f"wrist_{side}"].z - trace[f]["head"].z for f in frames]
    return {
        "frames": [first, final],
        "wrist_over_shoulder": [round(v, 3) for v in over],
        "peak_over_shoulder": round(max(over), 3),
        "peak_over_head_bone": round(max(head), 3),
        "speed": [round(v.length, 2) for v in steps],
        "peak_speed": round(max(v.length for v in steps), 2),
        "speed_up": [round(v.z, 2) for v in steps],
        "peak_speed_up": round(max(v.z for v in steps), 2),
        "speed_against_shoulder": [round(v, 2) for v in against],
        "peak_speed_against_shoulder": round(max(against), 2),
        "speed_change_a_frame": [round(v, 2) for v in changes],
        "peak_speed_change_a_frame": round(max(changes), 2),
    }


def legs_of(clip, first, final):
    """What the legs do from `first` to `final`, a list a frame: the hips' height over the top, how far the knees
    are apart against the hip joints' own width, each ankle and knee in the world (forward of the front face, up
    from the top), each ankle's speed against the hips and how far its path turns from one frame to the next."""
    trace, top = clip.trace, clip.box_height
    frames = list(range(first, final + 1))
    out = {"frames": [first, final]}
    out["hips_over_top"] = [round(trace[f]["pelvis"].z - top, 3) for f in frames]
    out["hips_forward"] = [round(clip.to_world(f, trace[f]["pelvis"]).y * -1.0, 3) for f in frames]
    width = (trace[first]["thigh_l"] - trace[first]["thigh_r"]).length
    out["knee_spread"] = [round((trace[f]["calf_l"] - trace[f]["calf_r"]).length / width, 2) for f in frames]
    out["ankle_spread"] = [round((trace[f]["foot_l"] - trace[f]["foot_r"]).length / width, 2) for f in frames]
    for side in "lr":
        for part, name in (("foot", "ankle"), ("calf", "knee"), ("toe", "toe")):
            world = [clip.to_world(f, trace[f][f"{part}_{side}"]) for f in frames]
            out[f"{name}_{side}_forward"] = [round(-v.y, 3) for v in world]
            out[f"{name}_{side}_over_top"] = [round(v.z - top, 3) for v in world]
        out[f"knee_{side}_deg"] = [round(trace[f][f"knee_{side}"]) for f in frames]
        local = [trace[f][f"foot_{side}"] - trace[f]["pelvis"] for f in frames]
        out[f"ankle_{side}_from_hips"] = [f"{v.x:+.2f} {-v.y:+.2f} {v.z:+.2f}" for v in local]
        steps = [(b - a) * FPS for a, b in zip(local, local[1:])]
        out[f"ankle_{side}_speed"] = [round(v.length, 2) for v in steps]
        out[f"ankle_{side}_speed_change"] = [round((b - a).length, 2) for a, b in zip(steps, steps[1:])]
        out[f"ankle_{side}_turn_deg"] = [
            round(math.degrees(a.angle(b))) if a.length > 0.5 and b.length > 0.5 else 0 for a, b in zip(steps, steps[1:])
        ]
    return out


def check_motion(clip):
    """Fail on what the body cannot do: leave the arc of a free fall while nothing touches it, cross on an arm
    that never takes its weight or never pushes, land on a leg that does not reach, or land without giving."""
    problems, report = [], {}
    trace = clip.trace
    speed_at = {}  # frame: the body's speed upward where a stretch in the air starts or ends
    for index, (first, final) in enumerate(clip.flights):
        # The best free fall through the frames in the air: gravity is given, the height and speed at the start
        # are fitted.
        times = [(frame - first) / FPS for frame in range(first, final + 1)]
        lifted = [trace[frame]["com"].z + 0.5 * GRAVITY * t * t for frame, t in zip(range(first, final + 1), times)]
        count = len(times)
        mean_t, mean_z = sum(times) / count, sum(lifted) / count
        spread = sum((t - mean_t) ** 2 for t in times)
        speed = sum((t - mean_t) * (z - mean_z) for t, z in zip(times, lifted)) / spread
        height = mean_z - speed * mean_t
        off = max(abs(height + speed * t - z) for t, z in zip(times, lifted))
        seconds = times[-1]
        top = speed / GRAVITY if speed > 0.0 else 0.0
        entry = {
            "frames": [first, final],
            "seconds": round(seconds, 4),
            "speed_up_at_start": round(speed, 2),
            "rise_to_top": round(0.5 * speed * top, 3) if top < seconds else None,
            "seconds_to_top": round(top, 3) if top < seconds else None,
            "fall_from_top": round(0.5 * GRAVITY * (seconds - top) ** 2, 3) if top < seconds else None,
            "speed_down_at_end": round(GRAVITY * seconds - speed, 2),
            "off_the_arc_mm": round(off * 1000, 1),
        }
        report[f"air_{index + 1}"] = entry
        speed_at[first] = speed
        speed_at[final] = speed - GRAVITY * seconds
        print(f"ARC {clip.name} frames {first}-{final}: {entry}")
        if off > ARC_LIMIT:
            problems.append(
                f"frames {first}-{final}: the body is {off * 1000:.0f} mm off the arc of a free fall "
                f"(the limit is {ARC_LIMIT * 1000:.0f} mm)"
            )
    if clip.push:
        limb, first, final = clip.push
        side = limb[-1]
        elbows = [round(trace[frame][f"elbow_{side}"]) for frame in range(first, final + 1)]
        arms = [round(trace[frame][f"arm_{side}"], 2) for frame in range(first, final + 1)]
        deepest = min(range(len(elbows)), key=elbows.__getitem__)

        def rate(frame):
            return (trace[frame + 1]["com"].z - trace[frame - 1]["com"].z) * FPS / 2.0

        # The share of the body's weight the arm carries on average: what gravity would have taken off the
        # body's upward speed over the contact, and did not.
        seconds = (final - first) / FPS
        on, off = speed_at.get(first, rate(first)), speed_at.get(final, rate(final))
        carried_share = 1.0 + (off - on) / (GRAVITY * seconds)
        shoulder = [
            round(trace[frame][f"shoulder_{side}"].z - trace[frame][f"wrist_{side}"].z, 3)
            for frame in range(first, final + 1)
        ]
        entry = {
            "frames": [first, final],
            "elbow_deg": elbows,
            "arm_length_share": arms,
            "shoulder_over_wrist": shoulder,
            "weight_carried": round(carried_share, 2),
            "speed_up_on": round(on, 2),
            "speed_up_off": round(off, 2),
        }
        report["push"] = entry
        print(f"PUSH {clip.name}: {entry}")
        # The arm takes the weight: the elbow gives after the plant, or the hand lands with the arm already
        # folded under the body (a high obstacle, the shoulders barely over the hands).
        if elbows[deepest] > 100 and (elbows[0] - elbows[deepest] < 15 or deepest == 0):
            problems.append(f"the planted arm never gives under the body (elbow {elbows})")
        if elbows[-1] < 165 or elbows[-1] - elbows[deepest] < 30:
            problems.append(f"the planted arm does not push off straight (elbow {elbows})")
        if carried_share < 0.25:
            problems.append(f"the planted arm carries only {carried_share:.2f} of the body's weight")
    if getattr(clip, "legs", None):
        entry = legs_of(clip, *clip.legs)
        report["legs"] = entry
        for key, values in entry.items():
            if not key.endswith("_from_hips"):
                print(f"LEGS {clip.name} {key}: {values}")
        first = clip.legs[0]
        over = [i for i, v in enumerate(entry["hips_forward"]) if 0.0 <= v <= clip.box_depth]
        entry["frames_over_the_top"] = [first + over[0], first + over[-1]] if over else []
        for key, limit, what in (
            ("knee_spread", LEGS_KNEE_SPREAD, "the knees are"),
            ("ankle_spread", LEGS_ANKLE_SPREAD, "the ankles are"),
        ):
            worst = max((entry[key][i] for i in over), default=0.0)
            entry[f"peak_{key}_over_the_top"] = worst
            if worst > limit:
                problems.append(f"{what} {worst} hip widths apart over the top (the limit is {limit})")
        fold = min((entry[f"knee_{side}_deg"][i] for i in over for side in "lr"), default=180)
        entry["tightest_knee_over_the_top"] = fold
        if fold < LEGS_FOLD:
            problems.append(f"a knee is folded to {fold} degrees over the top (the limit is {LEGS_FOLD:.0f})")
        low = min(
            (entry[f"{part}_{side}_over_top"][i] for i in over for side in "lr" for part in ("knee", "ankle", "toe")),
            default=1.0,
        )
        entry["lowest_leg_bone_over_the_top"] = low
        if low < 0.0:
            problems.append(f"a leg bone is {-low:.3f} m under the top while the hips are over it")
        for side in "lr":
            snap = max(entry[f"ankle_{side}_speed_change"])
            entry[f"peak_ankle_{side}_speed_change"] = snap
            if snap > LEGS_SPEED_CHANGE:
                problems.append(f"the {side} leg snaps: {snap} m/s of speed change in one frame (the limit is {LEGS_SPEED_CHANGE})")
            speeds = entry[f"ankle_{side}_speed"][over[0] :] if over else []
            held = sum(1 for a, b in zip(speeds, speeds[1:]) if a < LEGS_HELD and b < LEGS_HELD)
            entry[f"ankle_{side}_frames_held"] = held
            if held:
                problems.append(f"the {side} leg is held still against the hips for {held + 1} frames in the air")
        for key in [k for k in entry if k.endswith("_from_hips")]:
            del entry[key]
    for limb, first, final in clip.released:
        entry = release_of(clip, limb, first, final)
        report[f"release_{limb[-1]}"] = entry
        print(f"RELEASE {clip.name} {limb}: {entry}")
        for key, limit, what in (
            ("peak_over_shoulder", FREE_OVER_SHOULDER, "m over its shoulder"),
            ("peak_speed", FREE_SPEED, "m/s in the world"),
            ("peak_speed_against_shoulder", FREE_SPEED_AGAINST_SHOULDER, "m/s against its shoulder"),
            ("peak_speed_change_a_frame", FREE_SPEED_CHANGE, "m/s of speed change in one frame"),
        ):
            if entry[key] > limit:
                problems.append(f"the free {limb} is flung: {entry[key]} {what} (the limit is {limit})")
    if clip.reach:
        limb, land = clip.reach
        side = limb[-1]
        knees = [round(trace[frame][f"knee_{side}"]) for frame in range(land - 6, land + 1)]
        feet = [round(trace[frame][f"foot_{side}"].z, 3) for frame in range(land - 6, land + 1)]
        report["reach"] = {"frames": [land - 6, land], "knee_deg": knees, "foot_up": feet}
        print(f"LEG {clip.name}: {report['reach']}")
        steps = [b - a for a, b in zip(knees, knees[1:])]
        if min(steps) < 0:
            problems.append(f"the landing leg folds again on its way down (knee {knees})")
        if max(steps) > 30:
            problems.append(f"the landing leg snaps open (knee {knees})")
        if knees[-2] < 135:
            problems.append(f"the landing leg does not reach for the ground (knee {knees})")
        if any(b >= a for a, b in zip(feet, feet[1:])):
            problems.append(f"the landing foot does not come down on every frame ({feet})")
    if getattr(clip, "absorb", None):
        limb, first, final = clip.absorb
        side = limb[-1]
        knees = [round(trace[frame][f"knee_{side}"]) for frame in range(first, final + 1)]
        hips = [round(trace[frame]["pelvis"].z, 3) for frame in range(first, final + 1)]
        report["absorb"] = {
            "frames": [first, final],
            "knee_deg": knees,
            "pelvis_up": hips,
            "drop": round(hips[0] - hips[-1], 3),
        }
        print(f"LEG {clip.name}: {report['absorb']}")
        if any(b > a for a, b in zip(knees, knees[1:])) or any(b >= a for a, b in zip(hips, hips[1:])):
            problems.append(f"the landing leg does not give on every frame (knee {knees}, hips {hips})")
        if hips[0] - hips[-1] < 0.08:
            problems.append(f"the hips drop only {(hips[0] - hips[-1]) * 1000:.0f} mm in the landing")
    return problems, report


SAME = ("length", "frames", "speed", "travel", "events", "root_start", "root_at", "obstacle")


def held_to_default(found, default):
    """What a body's numbers differ in from the default body's, where the vault code needs one set: each clip's
    length, speed, contact times and root places, and where the hands land (`SAME`; the wrist's height over the
    top is the body's own, its palm being as thick as it is)."""
    out = []
    for name, entry in found["clips"].items():
        theirs = default["clips"].get(name, {})
        for key in SAME:
            if entry.get(key) != theirs.get(key):
                out.append(f"{name}: {key} is {entry.get(key)}, the default body's {theirs.get(key)}")
        for key in ("left", "forward"):
            mine, other = entry.get("hand_place", {}).get(key), theirs.get("hand_place", {}).get(key)
            if mine != other:
                out.append(f"{name}: the hand lands {key} {mine}, the default body's {other}")
    return out


def sidecar(rig, clips, path):
    import hashlib

    out = {
        "fps": FPS,
        # The body the clips were solved on and are played by.
        "body": rig.name,
        "model": rig.body["file"].name,
        "units": "metres and seconds; forward 0 is the obstacle's front face",
        # The file the numbers below were measured on: a test fails when vault.glb is not this file any more.
        "measured": {
            "file": path.name,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "overlap_limit_mm": OVERLAP_LIMIT,
            **__import__("measure_hash").made_by([rig.body["file"]]),
        },
        "clips": {},
    }
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
        if clip.motion:
            entry["motion"] = clip.motion
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
    path = out / rig.body["out"]
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


def strip(path, keyed):
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
            if name not in keyed:
                continue
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
    parser.add_argument("--body", default=DEFAULT_BODY, choices=sorted(BODIES))
    parser.add_argument("--render", default="")
    parser.add_argument("--only", default="")
    parser.add_argument("--no-fail", action="store_true")
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--check", action="store_true", help="compare with the files on disk, write nothing")
    args = parser.parse_args(argv)
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # clip_check.py
    sys.dont_write_bytecode = True  # Blender ignores PYTHONDONTWRITEBYTECODE
    import clip_check

    checking = clip_check.Check(args.check)
    args.out = checking.folder(args.out)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    BODIES[args.body].update(json.loads(os.environ.get("VAULT_TUNE", "{}")))
    rig = Rig(args.body)
    pose = rig.library_pose(SPRINT, 0)
    fist = {name: rig.basis(name, pose) for side in "lr" for name in rig.finger_bones(side)}
    names = [args.only] if args.only else FILE_CLIPS
    # Each clip is keyed a few times: a pass measures how far the centre of mass is above the pelvis in every
    # pose, and the next keys the pelvis from where the centre of mass has to be (`Clip.drive`).
    clips = []
    for name in names:
        offsets, moved = {}, 0.0
        for _ in range(8):
            clip = CLIPS[name](rig, offsets)
            found = clip.settle(fist)
            moved = max((abs(found[f] - offsets.get(f, 0.10)) for f in clip.centre), default=0.0)
            offsets = found
            if moved < 0.0002:
                break
        print(f"DRIVEN {name}: the centre of mass is within {moved * 1000:.2f} mm of where it was asked to be")
        assert moved < 0.002, f"{name}: the pelvis does not settle under the centre of mass ({moved * 1000:.1f} mm)"
        clips.append(clip)
    actions, failed = [], False
    for clip in clips:
        action, worst = bake(rig, clip)
        problems, report = check(rig, clip, action, worst)
        clip.contacts = report
        print(f"CLIP {clip.name}: {clip.frames} frames, {report}")
        print(f"PULLED {clip.name}:", {f: v for f, v in clip.pulled.items() if v}, clip.pullers)
        if args.trace:
            print_trace(clip)
            for frame, low, deep, where, joint, which, legs in clip.between:
                if low < -0.004 or deep > 0.004 or joint > 0.0:
                    print(
                        f"BETWEEN {clip.name} {frame:5.1f} ({frame / FPS:.4f} s): lowest {low * 1000:+.1f} mm | skin "
                        f"in the box {deep * 1000:.1f} mm {where} | joint in the box {joint * 1000:.1f} mm {which}"
                    )
                # Each leg joint near the box: forward of the front face and up from the top (m).
                if clip.box_height > 0.0 and -0.5 < clip.forward(frame) < clip.box_depth + 0.3:
                    places = " | ".join(f"{name} {at[0]:+.2f} {at[1]:+.2f}" for name, at in legs.items())
                    print(f"LEGS {clip.name} {frame:5.1f}: {places}")
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
    strip(path, set(rig.keyed))
    found = read_back(path)
    assert sorted(found) == sorted(FILE_CLIPS), f"the file carries {sorted(found)}, not {FILE_CLIPS}"
    for clip in clips:
        assert abs(found[clip.name]["length"] - clip.frames / FPS) < 1e-3, (clip.name, found[clip.name])
        assert found[clip.name]["translation"] == ["pelvis"], found[clip.name]["translation"]
        assert found[clip.name]["channels"] == len(rig.keyed) + 1, found[clip.name]["channels"]
    numbers = sidecar(rig, clips, path)
    if args.body != DEFAULT_BODY:
        default = json.loads((HERE / BODIES[DEFAULT_BODY]["sidecar"]).read_text(encoding="utf-8"))
        differs = held_to_default(numbers, default)
        for line in differs:
            print(f"PROBLEM {line}")
        if differs and not args.no_fail:
            sys.exit(f"{args.body}'s clips differ from {DEFAULT_BODY}'s in what the vault code reads")
    text = json.dumps(numbers, indent=2) + "\n"
    (out / rig.body["sidecar"]).write_text(text, encoding="utf-8", newline="\n")
    print("EXPORTED", path, json.dumps(found)[:400])
    checking.finish()


if __name__ == "__main__":
    sys.path[:0] = [str(HERE), str(HERE.parent)]
    main()
