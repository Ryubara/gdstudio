"""Build the template's melee clips and export them as an animation library (kit #1254).

GDStudio's own clips, keyed from scratch on Quaternius's universal rig (the template's mannequins and the Universal
Animation Library share it): three blows of the fists (`Melee_Unarmed_Jab`, `Melee_Unarmed_Cross`,
`Melee_Unarmed_Hook`) and three of the pistol in the right hand (`Melee_Pistol_Whip`, `Melee_Pistol_Backhand`,
`Melee_Pistol_Jab`). Nothing is copied from another clip but the first and last poses, which are frame 0 of the
library's `Idle_Loop` (fists) and `Pistol_Idle_Loop` (pistol), so a blow leaves and rejoins the pose the game stands
in.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P <this file> -- [--out <folder>] [--render <folder>] [--only <clip>] [--trace]

How a clip is made. The game plays these on the upper body only (`spine_01` and every bone below it) over whatever
the legs do, so the pelvis and the legs are the joined pose on every frame and the whole blow is in the spine, the
collarbones and the arms. A clip is a table of keys on a few controls:

- the chest's turn (`Clip.chest`: yaw, pitch and roll in degrees, shared out over the three spine bones);
- each collarbone (`Clip.shoulder`: degrees forward and up, in the chest's own axes);
- the head, which keeps the joined pose's facing whatever the chest does (`Clip.head` adds to it);
- each wrist (`Clip.hand`): its place in the character's space, the way the elbow points, the way the palm faces,
  and the wrist's bend (`cock` toward the thumb, `flex` toward the palm). The hand lies along the forearm unless it
  is bent, so a wrist cannot be keyed further round than the bend says;
- the fingers (`Clip.fingers`): how far they are from the joined pose's toward the hand's closed pose, which is a
  fist (the fists of the prone clips, `FIST_CURL`) or, for the pistol's hand, the grip the game's `WeaponHold` puts
  on after the clip (`gameplay/weapon/hold/pistol_grip_pose.tres`, read here, never typed).

Smooth curves through the keys (`Channel`) give every frame, a two-bone solver turns the wrists into arm rotations,
and every bone is keyed on every frame.

The pistol rides `hand_r` as in the game: `assets/weapons/pistol/pistol_held.tscn` seats it and `WeaponHold` turns
the wrist under the grip after the clip (`turns` of the grip pose). The keys say how the hand looks in the game
(turned), the clip stores the hand without that turn, and every check and render puts the turn back on.

Positions are `(left, forward, up)` in metres from the character's root. Angles are degrees: yaw turns left, pitch
leans forward, roll leans to the left.
"""

import argparse
import hashlib
import json
import math
import re
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent.parent
GAME = ASSETS.parent
MANNEQUIN = ASSETS / "characters" / "mannequin" / "mannequin_female.glb"
MANNEQUIN_MALE = ASSETS / "characters" / "mannequin" / "mannequin_male.glb"
LIBRARY = ASSETS / "animation" / "universal" / "ual1.glb"
PISTOL = ASSETS / "weapons" / "pistol" / "pistol.glb"
PISTOL_HELD = ASSETS / "weapons" / "pistol" / "pistol_held.tscn"
GRIP_POSE = GAME / "gameplay" / "weapon" / "hold" / "pistol_grip_pose.tres"
## The library's rate: these clips play beside its clips (kit docs/tools/blender/animation.md#conventions).
FPS = 30
## The clips this file carries, and nothing else (kit docs/tools/blender/build-scripts.md#rebuilding).
FILE_CLIPS = [
    "Melee_Pistol_Backhand",
    "Melee_Pistol_Jab",
    "Melee_Pistol_Whip",
    "Melee_Unarmed_Cross",
    "Melee_Unarmed_Hook",
    "Melee_Unarmed_Jab",
]
## The poses the clips join (frame 0 of each).
IDLE = "Idle_Loop"
PISTOL_IDLE = "Pistol_Idle_Loop"

## How deep one body part may be inside another that no joint joins it to (mm), on either mannequin, on any frame.
OVERLAP_LIMIT = 5.0
## How deep the pistol may be inside the body, or the body inside the pistol (mm); the hand that holds it aside.
GUN_LIMIT = 5.0
## How far a main joint may be from the pose the clip joins, on its first and last frame (mm).
JOIN_LIMIT = 10.0
## The joints the join and the snap checks read.
MAIN_JOINTS = [
    "spine_01",
    "spine_02",
    "spine_03",
    "neck_01",
    "Head",
    "upperarm_l",
    "lowerarm_l",
    "hand_l",
    "upperarm_r",
    "lowerarm_r",
    "hand_r",
    "pelvis",
    "calf_l",
    "foot_l",
    "calf_r",
    "foot_r",
]
## No snap: the most a joint's velocity may change from one frame to the next (m/s, as a vector, so a turn back
## counts), by joint. A blow is fast on purpose: the fist goes from 0 to 8 m/s and back in a tenth of a second, so
## the wrists' limit is high; what the limit catches is an elbow that flips sides or a hand that jumps.
SNAP_LIMIT = {
    "hand": 6.5,
    "lowerarm": 6.0,
    "upperarm": 2.0,
    "Head": 1.0,
    "spine_03": 1.0,
}
## An arm is never straighter than this share of its length (a locked elbow pops), and the wrist never bent
## further from the forearm's line than this (degrees), as the game shows it.
ARM_LIMIT = 0.975
WRIST_LIMIT = 40.0
## A closed fist: every fingertip within this distance of the wrist joint (m): curled back onto the palm (0.09 on
## these hands). An open finger's tip is 0.20 from it, a half-closed one's 0.15.
FIST_TIP_LIMIT = 0.105
## The pistol clips join the library's two-handed pose, whose left hand is wrapped round the right one (26 mm
## inside it on the mesh, and in the grip): two hands that start inside each other cannot part without crossing.
## So while the game fades the clip in and out (its first `FADE_IN` and last `FADE_OUT` frames; the game holds the
## left hand on the pistol by its own solver until then), the left arm against the right hand, forearm and pistol
## is held to the joined pose's own depth and `JOINED_SLACK` more (mm), not to the limits above. Every other pair,
## and these on every other frame, are held to the limits.
FADE_IN = 2
FADE_OUT = 4
JOINED_SLACK = 5.0
## What the game asks of a blow (kit #1254): the striking point this far in front of the chest at contact (m), at
## this height (m, from the chest to the top of the head of someone standing in front), contact and length in
## these spans (s).
REACH = (0.55, 0.75)
HEIGHT = (1.25, 1.75)
TIMES = {
    "fists": {"contact": (0.15, 0.22), "length": (0.5, 0.6)},
    "pistol": {"contact": (0.22, 0.30), "length": (0.6, 0.75)},
}
## A blow is wound up by the arm, not by leaning away from it: up to contact, the chest's and the head's up axes
## are never tipped further back of the joined pose than this (degrees, in the character's own forward and back;
## the chest's roll counts once its yaw has turned it to the back), and the head joint is never further behind its
## joined place than this (mm). A maintainer's review of the pistol whip, kit #1315.
LEAN_BACK_LIMIT = 0.1
HEAD_BACK_LIMIT = 5.0
## The hit window is while the striking point is within this distance of where it is at contact (m).
WINDOW = 0.1

FINGERS = ["thumb", "index", "middle", "ring", "pinky"]
TRUNK = ["spine_01", "spine_02", "spine_03"]
## The chest's turn is shared out over the three spine bones, most at the top.
TRUNK_SHARE = (0.25, 0.35, 0.40)
## The fist of the prone clips (`../prone/build_prone_clips.py`, kit #1020: measured there on both mannequins):
## degrees each finger joint bends from the knuckle to the tip, and the way each thumb bone points on the left
## hand in the rest pose's axes (mirrored for the right), which lays the thumb across the index and middle fingers.
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
## glTF's axes (Y up) to Blender's (Z up), and back. A bone's matrix in Blender is its node's in glTF in these
## axes, so a rotation Godot gives in a bone's parent's space is the same numbers here.
TO_Z_UP = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
TO_Y_UP = TO_Z_UP.inverted()
## Where the pistol strikes, in the `Pistol` node's own space (m; -X is the muzzle's way, +Y up the grip, -Z its
## right side): the middle of the grip's foot, and the slide's right flat a third of the way back from the muzzle.
GUN_POINTS = {
    "butt": Vector((0.016, -0.052, 0.0)),
    "slide": Vector((-0.150, 0.120, -0.020)),
}


# ---------------------------------------------------------------------------------------------------------------
# Small maths
# ---------------------------------------------------------------------------------------------------------------
def P(left, forward, up):
    """A point in (left, forward, up) as a Blender vector (the rig faces -Y, its left is +X)."""
    return Vector((left, -forward, up))


def lfu(vector):
    """A Blender vector as [left, forward, up], rounded for a report."""
    return [round(vector.x, 4), round(-vector.y, 4), round(vector.z, 4)]


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


def placed(point, turn):
    """A 4x4 from a place and a 3x3 turn."""
    out = turn.to_4x4()
    out.translation = point
    return out


class Channel:
    """Keys on one control and their smooth curve: a cubic through the keys that is flat at a hold and at a peak
    (the vault build's, `../vault/build_vault.py`)."""

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
# The pistol as the game holds it
# ---------------------------------------------------------------------------------------------------------------
def godot_quat(text):
    x, y, z, w = (float(v) for v in text.split(","))
    return Quaternion((w, x, y, z))


def read_hold():
    """The pistol's seat on `hand_r` (a 4x4 in the bone's space), the wrist's turn `WeaponHold` adds after the
    clip, and the right hand's finger rotations on the grip (each in its parent's space), from the game's files."""
    text = PISTOL_HELD.read_text(encoding="utf-8")
    found = re.search(r'\[node name="Pistol"[^\[]*?transform = Transform3D\(([^)]*)\)', text, re.S)
    v = [float(x) for x in found.group(1).split(",")]
    seat = Matrix((v[0:3] + [v[9]], v[3:6] + [v[10]], v[6:9] + [v[11]], [0, 0, 0, 1]))
    text = GRIP_POSE.read_text(encoding="utf-8")
    rotations, turns = text.split("turns = ")
    quat = r'&"(\w+)": Quaternion\(([^)]*)\)'
    fingers = {name: godot_quat(value) for name, value in re.findall(quat, rotations)}
    turn = {name: godot_quat(value) for name, value in re.findall(quat, turns)}["hand_r"]
    return seat, turn, fingers


class Gun:
    """The pistol's mesh (in the axes Blender imports it in), for the checks and the renders."""

    def __init__(self, seat):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(PISTOL))
        self.objects = [o for o in bpy.data.objects if o not in before]
        self.root = next(o for o in self.objects if o.parent is None)
        self.seat = seat @ TO_Y_UP
        bpy.context.view_layer.update()
        verts, tris = [], []
        for obj in self.objects:
            if obj.type != "MESH":
                continue
            start = len(verts)
            verts += [(obj.matrix_world @ v.co)[:] for v in obj.data.vertices]
            obj.data.calc_loop_triangles()
            tris += [[start + i for i in t.vertices] for t in obj.data.loop_triangles]
        self.verts = np.array(verts)
        tri = np.array(tris)
        edges = np.unique(
            np.sort(np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]]), axis=1),
            axis=0,
        )
        self.samples = np.concatenate([self.verts, self.verts[tri].mean(axis=1), self.verts[edges].mean(axis=1)])
        self.tree = BVHTree.FromPolygons(verts, tris)
        self.low, self.high = self.verts.min(axis=0), self.verts.max(axis=0)
        self.root.rotation_mode = "QUATERNION"

    def matrix(self, hand):
        """The pistol's world matrix from the world matrix of `hand_r` as the game shows it (the wrist turned)."""
        return hand @ self.seat

    def point(self, hand, name):
        return hand @ self.seat @ TO_Z_UP @ GUN_POINTS[name]

    def against(self, body, coords, matrix, skip=("hand_r",)):
        """The pistol against a body's skin now: `(deepest mm, part, nearest mm to the head or the trunk)`. Both
        ways: the pistol's samples inside a part (rays, as `limb_overlap.py` tells inside from outside) and the
        part's vertices inside the pistol. The hand that holds it (`skip`) is not measured."""
        m = np.array(matrix)
        points = self.samples @ m[:3, :3].T + m[:3, 3]
        low, high = points.min(axis=0), points.max(axis=0)
        inverse = np.array(matrix.inverted())
        deepest, where, nearest = 0.0, None, 9.0
        rays = [
            Vector(v)
            for v in (
                (1, 0, 0),
                (-1, 0, 0),
                (0, 1, 0),
                (0, -1, 0),
                (0, 0, 1),
                (0, 0, -1),
            )
        ]
        for part, info in body.parts.items():
            if part in skip:
                continue
            own = coords[info["verts"]]
            trunk = part in ("head", "chest", "pelvis")
            reach = 0.25 if trunk else 0.0
            if (own.min(axis=0) > high + reach).any() or (own.max(axis=0) < low - reach).any():
                continue
            skin = BVHTree.FromPolygons(own.tolist(), info["local"])
            middles = [own[cap].mean(axis=0).tolist() for cap in info["caps"]]
            solid = BVHTree.FromPolygons(own.tolist() + middles, info["closed"])
            for point in points.tolist():
                location, normal, _index, distance = skin.find_nearest(point)
                if location is None:
                    continue
                outside = (Vector(point) - location).dot(normal) >= 0.0
                if not outside:
                    backs = 0
                    for way in rays:
                        _hit, facing, _face, far = solid.ray_cast(point, way)
                        backs += far is not None and way.dot(facing) > 0.0
                    outside = backs < len(rays) - 1
                if outside:
                    if trunk:
                        nearest = min(nearest, distance)
                elif distance > deepest:
                    deepest, where = distance, part
                    nearest = 0.0 if trunk else nearest
            local = own @ inverse[:3, :3].T + inverse[:3, 3]
            for point in local[((local >= self.low) & (local <= self.high)).all(axis=1)].tolist():
                location, normal, _index, distance = self.tree.find_nearest(point)
                if location is None or distance <= deepest or (Vector(point) - location).dot(normal) >= 0.0:
                    continue
                backs = 0
                for way in rays:
                    _hit, facing, _face, far = self.tree.ray_cast(point, way)
                    backs += far is not None and way.dot(facing) > 0.0
                if backs == len(rays):
                    deepest, where = distance, part
        return round(deepest * 1000.0, 1), where, round(nearest * 1000.0, 1)


# ---------------------------------------------------------------------------------------------------------------
# The rig
# ---------------------------------------------------------------------------------------------------------------
class Rig:
    """The mannequin's armature, its rest pose, poses read from the library's clips, and the hands' closed poses."""

    def __init__(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        # Blender puts a key at its seconds times the scene's rate: the rate is set before any import.
        bpy.context.scene.render.fps = FPS
        bpy.ops.import_scene.gltf(filepath=str(MANNEQUIN))
        self.arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
        self.mesh = max(
            (o for o in bpy.data.objects if o.type == "MESH" and o.parent == self.arm),
            key=lambda o: len(o.data.vertices),
        )
        self.extras = [o for o in bpy.data.objects if o not in (self.arm, self.mesh)]
        mine = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(LIBRARY))
        self.library_objects = [o for o in bpy.data.objects if o not in mine]
        self.library_arm = next(o for o in self.library_objects if o.type == "ARMATURE")
        for track in self.library_arm.animation_data.nla_tracks:
            track.mute = True
        self.library_actions = list(bpy.data.actions)
        import limb_overlap

        male = limb_overlap.load_body(MANNEQUIN_MALE, "male")
        self.bodies = [limb_overlap.Body(self.arm, self.mesh, "female"), male]
        self.order = [b.name for b in self.arm.data.bones]  # parents before children
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in self.arm.data.bones}
        self.rest = {b.name: b.matrix_local.copy() for b in self.arm.data.bones}
        self.rest_rel = {
            n: (self.rest[self.parent[n]].inverted() @ self.rest[n]) if self.parent[n] else self.rest[n].copy()
            for n in self.order
        }
        self.rest_rot = {n: self.rest[n].to_3x3() for n in self.order}
        seat, self.grip_turn, grip = read_hold()
        self.gun = Gun(seat)
        # The closed poses of each hand, as each finger bone's own rotation (what Blender keys).
        self.fist, self.grip = {}, {}
        for side, sign in (("l", 1.0), ("r", -1.0)):
            for finger, bends in FIST_CURL.items():
                for joint, bend in zip((1, 2, 3), bends):
                    name = f"{finger}_0{joint}_{side}"
                    # a finger joint bends toward the palm about its own hinge, which the right hand's bones mirror
                    way = math.copysign(1.0, self.rest_rot[name][1][0]) * sign
                    self.fist[name] = Quaternion((1, 0, 0), math.radians(way * bend))
            above = self.rest_rot[f"hand_{side}"]
            for joint, aim in zip((1, 2, 3), FIST_THUMB):
                name = f"thumb_0{joint}_{side}"
                rest = self.rest_rot[name]
                want = Vector((sign * aim[0], aim[1], aim[2])).normalized()
                turn = rest.col[1].rotation_difference(want).to_matrix()
                local = above.transposed() @ turn @ rest
                self.fist[name] = (self.rest_rel[name].to_3x3().inverted() @ local).to_quaternion()
                above = turn @ rest
        for name, quat in grip.items():
            self.grip[name] = (self.rest_rel[name].to_3x3().inverted() @ quat.to_matrix()).to_quaternion()

    def finger_bones(self, side):
        return [f"{f}_0{i}_{side}" for f in FINGERS for i in (1, 2, 3)]

    def library_pose(self, clip, frame):
        """The armature-space matrix of every bone of this rig in a library clip's pose (the clip's local
        rotations on this rig's own bone lengths, which is what Godot plays)."""
        action = bpy.data.actions[clip]
        data = self.library_arm.animation_data
        data.action = action
        data.action_slot = action.slots[0]
        bpy.context.scene.frame_set(int(frame))
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

    def hand_turn(self, side, fore, palm, cock=0.0, flex=0.0):
        """A hand's armature-space turn: lying along `fore` (the forearm's way) with the palm facing as near
        `palm` as that allows, then bent at the wrist `cock` degrees toward the thumb and `flex` toward the palm."""
        a = fore.normalized()
        b = (palm - a * palm.dot(a)).normalized()
        thumb = a.cross(b) * (1.0 if side == "r" else -1.0)
        c, f = math.radians(cock), math.radians(flex)
        a = a * math.cos(c) + thumb * math.sin(c)
        a, b = a * math.cos(f) + b * math.sin(f), b * math.cos(f) - a * math.sin(f)
        along = Vector((1, 0, 0)) if side == "l" else Vector((-1, 0, 0))
        return frame_of(a, b) @ frame_of(along, Vector((0, 0, -1))).transposed() @ self.rest_rot[f"hand_{side}"]

    def palm_of(self, side, turn):
        """The way a hand's palm faces and its fingers point, from its armature-space turn."""
        back = turn @ self.rest_rot[f"hand_{side}"].inverted()
        along = Vector((1, 0, 0)) if side == "l" else Vector((-1, 0, 0))
        return back @ Vector((0, 0, -1)), back @ along


# The arms: the bone that swings, the bone that bends, the end, and the hinge axis in the rest pose (the bend
# plane's normal, `upper x lower`, as an armature-space direction).
ARMS = {
    "l": ("upperarm_l", "lowerarm_l", "hand_l", Vector((0, 0, -1))),
    "r": ("upperarm_r", "lowerarm_r", "hand_r", Vector((0, 0, 1))),
}


class Clip:
    """One clip: the pose it joins, its keys, and what strikes."""

    def __init__(self, rig, name, frames, joins, contact, side, weapon, point):
        self.rig = rig
        self.name = name
        self.frames = frames
        self.joins = joins
        self.contact = contact
        self.side = side  # the hand that strikes
        self.weapon = weapon  # "fists" or "pistol"
        self.point = point  # "knuckles", or a name of GUN_POINTS
        self.what = ""
        self.channels = {}
        self.base = rig.library_pose(joins, 0)
        self.base_rel = {
            n: (self.base[rig.parent[n]].inverted() @ self.base[n]) if rig.parent[n] else self.base[n].copy()
            for n in rig.order
        }
        self.closed = {"l": rig.fist, "r": rig.grip if weapon == "pistol" else rig.fist}
        self.open = {n: rig.basis(n, self.base) for side in "lr" for n in rig.finger_bones(side)}
        # The clip leaves the joined pose at once (the game fades it in) and comes to rest on it: the pose is
        # keyed again two frames after the end, so every curve arrives flat.
        for frame in (0, frames, frames + 2):
            self.rest(frame)
        shut = 1.0  # the fists are closed, and the grip held, on every frame
        for frame in (0, frames):
            self.fingers(frame, "r", shut)
            self.fingers(frame, "l", shut if weapon == "fists" else 0.0)

    def key(self, channel, frame, value):
        self.channels.setdefault(channel, Channel()).key(frame, value)

    def rest(self, frame):
        """Key every control on the joined pose."""
        rig, base = self.rig, self.base
        for name in TRUNK + ["Head", "clavicle_l", "clavicle_r"]:
            self.key(name, frame, Vector((0.0, 0.0, 0.0)))
        for side, (upper, _lower, end, _axis) in ARMS.items():
            root, mid, tip = (base[b].translation for b in (upper, f"lowerarm_{side}", end))
            reach = (tip - root).normalized()
            bend = mid - root
            palm, _fingers = rig.palm_of(side, base[end].to_3x3())
            self.key(f"hand_{side}_pos", frame, tip.copy())
            self.key(
                f"hand_{side}_pole",
                frame,
                (bend - reach * bend.dot(reach)).normalized(),
            )
            self.key(f"hand_{side}_palm", frame, palm)
            self.key(f"hand_{side}_wrist", frame, Vector((0.0, 0.0)))
            self.key(f"hand_{side}_aim", frame, 0.0)

    def chest(self, frame, yaw=0.0, pitch=0.0, roll=0.0):
        """The chest's turn from the joined pose, shared out over the spine."""
        for name, share in zip(TRUNK, TRUNK_SHARE):
            self.key(name, frame, Vector((yaw, pitch, roll)) * share)

    def head(self, frame, yaw=0.0, pitch=0.0, roll=0.0):
        """The head's turn from the joined pose's facing (it does not follow the chest)."""
        self.key("Head", frame, Vector((yaw, pitch, roll)))

    def shoulder(self, frame, side, forward=0.0, up=0.0):
        """A collarbone: degrees its shoulder is pushed forward and lifted, in the chest's axes."""
        sign = 1.0 if side == "r" else -1.0
        self.key(f"clavicle_{side}", frame, Vector((sign * forward, 0.0, sign * up)))

    def hand(self, frame, side, at, elbow, palm, cock=0.0, flex=0.0):
        """A wrist: where it is, the way its elbow points, the way its palm faces and the wrist's bend."""
        self.key(f"hand_{side}_pos", frame, P(*at))
        self.key(f"hand_{side}_pole", frame, P(*elbow).normalized())
        self.key(f"hand_{side}_palm", frame, P(*palm).normalized())
        self.key(f"hand_{side}_wrist", frame, Vector((cock, flex)))
        self.key(f"hand_{side}_aim", frame, 1.0)

    def trunk(self, frame, mats):
        """Solve the spine at a frame into `mats`; returns the chest's turn from the joined pose."""
        for name in TRUNK:
            carried = mats[self.rig.parent[name]] @ self.base_rel[name]
            mats[name] = placed(
                carried.translation,
                R(*self.channels[name].at(frame)) @ carried.to_3x3(),
            )
        return mats["spine_03"].to_3x3() @ self.base["spine_03"].to_3x3().inverted()

    def collarbone(self, frame, side, mats, chest):
        """Solve a collarbone at a frame into `mats`; returns its shoulder joint's place."""
        name = f"clavicle_{side}"
        carried = mats["spine_03"] @ self.base_rel[name]
        turn = chest @ R(*self.channels[name].at(frame)) @ chest.inverted()
        mats[name] = placed(carried.translation, turn @ carried.to_3x3())
        return (mats[name] @ self.rig.rest_rel[f"upperarm_{side}"]).translation

    def from_shoulder(self, frame, side, inward, forward, up):
        """A place given from a shoulder joint in the chest's axes at that frame, as `(left, forward, up)` from
        the root: key the chest and the collarbone first. `inward` is toward the body's middle."""
        mats = {name: self.base[name].copy() for name in ("pelvis", "root")}
        chest = self.trunk(frame, mats)
        root = self.collarbone(frame, side, mats, chest)
        point = root + chest @ P(inward if side == "r" else -inward, forward, up)
        return (point.x, -point.y, point.z)

    def fingers(self, frame, side, closed):
        """How far a hand's fingers are from the joined pose's (0) toward its closed pose (1)."""
        self.key(f"curl_{side}", frame, closed)

    def solve(self, frame, shown=False):
        """Armature-space matrices of every bone at a frame. `shown` adds what the game adds after the clip: the
        wrist's turn under the pistol's grip."""
        rig, base, rel = self.rig, self.base, self.base_rel
        at = {name: channel.at(frame) for name, channel in self.channels.items()}
        mats = {name: base[name].copy() for name in rig.order}
        chest = self.trunk(frame, mats)
        for name, hold in (("neck_01", 0.5), ("Head", 1.0)):
            carried = mats[rig.parent[name]] @ rel[name]
            turn = R(*at["Head"]) if name == "Head" else Matrix.Identity(3)
            want = (turn @ base[name].to_3x3()).to_quaternion()
            quat = carried.to_quaternion().slerp(aligned(want, carried.to_quaternion()), hold)
            mats[name] = placed(carried.translation, quat.to_matrix())
        for side, (upper, lower, end, axis) in ARMS.items():
            root = self.collarbone(frame, side, mats, chest)
            target = at[f"hand_{side}_pos"]
            to_mid, to_end = (
                rig.rest_rel[lower].translation,
                rig.rest_rel[end].translation,
            )
            first, second = to_mid.length, to_end.length
            line = target - root
            distance = min(line.length, (first + second) * 0.9995)
            line.normalize()
            pole = at[f"hand_{side}_pole"]
            out = (pole - line * pole.dot(line)).normalized()
            along = (first * first - second * second + distance * distance) / (2.0 * distance)
            height = math.sqrt(max(first * first - along * along, 0.0))
            mid = root + line * along + out * height
            tip = root + line * distance
            normal = out.cross(line).normalized()
            turn_upper = (
                frame_of(mid - root, normal) @ frame_of(to_mid, rig.rest_rot[upper].inverted() @ axis).transposed()
            )
            turn_lower = (
                frame_of(tip - mid, normal) @ frame_of(to_end, rig.rest_rot[lower].inverted() @ axis).transposed()
            )
            mats[upper] = placed(root, turn_upper)
            mats[lower] = placed(mid, turn_lower)
            cock, flex = at[f"hand_{side}_wrist"]
            aimed = rig.hand_turn(side, tip - mid, at[f"hand_{side}_palm"], cock, flex)
            holds = self.weapon == "pistol" and side == "r"
            if holds:  # the keys say how the hand looks in the game; the clip stores it without the game's turn
                aimed = aimed @ rig.grip_turn.to_matrix().inverted()
            joined = rel[end].to_quaternion()
            local = (turn_lower.inverted() @ aimed).to_quaternion()
            weight = max(0.0, min(1.0, at[f"hand_{side}_aim"]))
            turn = turn_lower @ joined.slerp(aligned(local, joined), weight).to_matrix()
            if holds and shown:
                turn = turn @ rig.grip_turn.to_matrix()
            mats[end] = placed(tip, turn)
            curl = max(0.0, min(1.0, at[f"curl_{side}"]))
            for name in rig.finger_bones(side):
                quat = self.open[name].slerp(aligned(self.closed[side][name], self.open[name]), curl)
                mats[name] = mats[rig.parent[name]] @ rig.rest_rel[name] @ quat.to_matrix().to_4x4()
            for name in rig.order:
                if name.endswith(f"_leaf_{side}") and not name.startswith("ball"):
                    mats[name] = mats[rig.parent[name]] @ rig.rest_rel[name]
        return mats

    def strike(self, hand, knuckle):
        """The striking point, from the world matrix of the striking hand as the game shows it."""
        if self.point == "knuckles":
            return knuckle.copy()
        return self.rig.gun.point(hand, self.point)


# ---------------------------------------------------------------------------------------------------------------
# The clips
# ---------------------------------------------------------------------------------------------------------------
# A blow's keys, in order: the wind-up (short: a blow that is seen coming is slow to play), the snap to contact,
# a short follow-through and the way back. The research behind each is in README.md.
DOWN = (0.0, 0.0, -1.0)
## A fist on guard, from its own shoulder in the chest's axes (toward the body's middle, forward, up; m), and the
## way its elbow points. It turns with the chest, so it cannot end up in it. Each side has its own numbers, as a
## person's guard does (kit docs/tools/blender/own-animation.md#feel, no mirror poses): the rear (right) fist sits
## close under the jaw with the elbow near the ribs; the lead (left) fist is held further out and lower, the
## elbow a little away from the body.
GUARD = {
    "r": {"up": (0.0, 0.26, 0.04), "low": (-0.01, 0.23, -0.18), "elbow": (-0.5, -0.55, -1.0), "palm": (1.0, 0.3, -0.1)},
    "l": {
        "up": (-0.03, 0.30, -0.02),
        "low": (-0.05, 0.27, -0.24),
        "elbow": (0.75, -0.35, -1.0),
        "palm": (-1.0, 0.0, -0.3),
    },
}


def guard(c, side, frames, low, up=None):
    """Key a hand's guard: up on each of `frames` (at `up`, or the side's own place), lower at `low`. The frames
    are never the striking hand's: the two fists do not rise, hold or drop together."""
    mine = GUARD[side]
    for frame, place in [(frame, up or mine["up"]) for frame in frames] + [(low, mine["low"])]:
        c.hand(frame, side, at=c.from_shoulder(frame, side, *place), elbow=mine["elbow"], palm=mine["palm"])


def unarmed_jab(rig):
    """A straight blow of the lead (left) hand: the fist rises from the hip toward the chin and goes straight
    out, the left shoulder follows it, the right fist comes up to guard the jaw."""
    c = Clip(rig, "Melee_Unarmed_Jab", 16, IDLE, 5, "l", "fists", "knuckles")
    c.what = "the lead (left) fist straight out and straight back, the right fist up at the jaw"
    c.chest(2, yaw=3, pitch=1, roll=1)
    c.chest(5, yaw=-10, pitch=5, roll=-3)
    c.chest(7, yaw=-7, pitch=4, roll=-2)
    c.chest(11, yaw=-2, pitch=1)
    c.shoulder(2, "l", forward=0, up=5)
    c.shoulder(5, "l", forward=9, up=8)
    c.shoulder(10, "l", forward=3, up=3)
    c.shoulder(5, "r", forward=-5, up=-2)
    c.shoulder(10, "r", forward=-1, up=1)
    c.head(5, yaw=-3, pitch=5, roll=3)
    c.hand(2, "l", at=(0.27, 0.12, 1.12), elbow=(0.5, -0.7, -1.0), palm=(-1.0, 0.0, -0.3))
    c.hand(5, "l", at=(0.07, 0.535, 1.47), elbow=(0.7, 0.0, -1.0), palm=DOWN)
    c.hand(6, "l", at=(0.08, 0.50, 1.47), elbow=(0.7, 0.0, -1.0), palm=DOWN)
    c.hand(10, "l", at=(0.22, 0.27, 1.30), elbow=(0.5, -0.4, -1.0), palm=(-1.0, 0.0, -0.3))
    guard(c, "r", (5, 9), 13)
    return c


def unarmed_cross(rig):
    """A straight blow of the rear (right) hand: the chest winds a little to the right, then turns hard to the
    left and throws the right shoulder and fist through; the left fist comes back to the jaw."""
    c = Clip(rig, "Melee_Unarmed_Cross", 18, IDLE, 6, "r", "fists", "knuckles")
    c.what = "the rear (right) fist straight through behind a hard turn of the chest, the left fist up at the jaw"
    c.chest(2, yaw=-8, pitch=1)
    c.chest(6, yaw=38, pitch=8, roll=3)
    c.chest(8, yaw=42, pitch=9, roll=3)
    c.chest(13, yaw=8, pitch=2)
    c.shoulder(3, "r", forward=-4, up=6)
    c.shoulder(6, "r", forward=16, up=8)
    c.shoulder(12, "r", forward=3, up=3)
    c.shoulder(6, "l", forward=-8, up=5)
    c.shoulder(8, "l", forward=-9, up=5)
    c.shoulder(13, "l", forward=-2, up=1)
    c.head(6, yaw=4, pitch=6, roll=-4)
    c.head(8, yaw=5, pitch=6, roll=-4)
    c.hand(3, "r", at=(-0.28, -0.01, 1.16), elbow=(-0.5, -0.8, -1.0), palm=(1.0, 0.0, -0.3))
    c.hand(6, "r", at=(-0.03, 0.535, 1.46), elbow=(-0.7, 0.0, -1.0), palm=DOWN)
    c.hand(8, "r", at=(0.0, 0.50, 1.44), elbow=(-0.7, 0.0, -1.0), palm=DOWN)
    c.hand(12, "r", at=(-0.25, 0.15, 1.15), elbow=(-0.5, -0.6, -1.0), palm=(1.0, 0.0, -0.3))
    # the lead fist comes back high to the chin as the rear one goes: above the rising fist, never level with it
    guard(c, "l", (4, 9, 12), 16, up=(0.0, 0.27, 0.09))
    return c


def unarmed_hook(rig):
    """A hook of the lead (left) hand: the elbow lifts to the shoulder's height beside the body, and the chest's
    turn to the right carries the bent arm round in a level arc across the front."""
    c = Clip(rig, "Melee_Unarmed_Hook", 18, IDLE, 6, "l", "fists", "knuckles")
    c.what = "the lead (left) fist round in a level arc, the arm bent and carried by the chest's turn"
    c.chest(3, yaw=14, pitch=2)
    c.chest(6, yaw=-34, pitch=5, roll=-3)
    c.chest(8, yaw=-46, pitch=6, roll=-3)
    c.chest(13, yaw=-8, pitch=2)
    c.shoulder(3, "l", forward=-4, up=8)
    c.shoulder(6, "l", forward=14, up=10)
    c.shoulder(12, "l", forward=3, up=3)
    c.shoulder(6, "r", forward=-6, up=-3)
    c.shoulder(8, "r", forward=-7, up=-3)
    c.shoulder(13, "r", forward=-1, up=0)
    c.head(6, yaw=-4, pitch=5, roll=4)
    c.head(8, yaw=-6, pitch=5, roll=4)
    c.hand(3, "l", at=(0.36, 0.16, 1.30), elbow=(1.0, -0.6, -0.3), palm=DOWN)
    c.hand(6, "l", at=(0.02, 0.53, 1.48), elbow=(1.0, 0.2, -0.1), palm=DOWN)
    c.hand(8, "l", at=(-0.17, 0.42, 1.46), elbow=(1.0, 0.6, -0.15), palm=DOWN)
    c.hand(13, "l", at=(0.27, 0.17, 1.14), elbow=(0.6, -0.5, -1.0), palm=(-1.0, 0.0, -0.3))
    c.hand(2, "r", at=c.from_shoulder(2, "r", -0.08, 0.20, -0.30), elbow=(-0.6, -0.5, -1.0), palm=(1.0, 0.2, -0.1))
    guard(c, "r", (4, 5, 6, 7, 8, 10, 12), 16)
    return c


def left_off(c, out, back):
    """The pistol clips join a two-handed pose: the left hand leaves the pistol sideways by `out` and comes back
    to it sideways from `back`, never through the right hand or the grip."""
    aside = c.base["hand_l"].translation + P(0.10, -0.03, -0.04)
    c.key("hand_l_pos", out, aside)
    c.key("hand_l_pos", back, aside)


def pistol_whip(rig):
    """A hammer blow with the pistol's butt: the pistol goes up beside the head, muzzle up, and comes down and
    forward with the butt leading; the left hand stays up in front as a guard and is drawn in as the blow lands."""
    c = Clip(rig, "Melee_Pistol_Whip", 22, PISTOL_IDLE, 8, "r", "pistol", "butt")
    c.what = "the pistol up beside the head and down and forward, the butt leading; the left hand guards"
    # the wind-up is the arm's: the chest only turns a little under it and never leans back (kit #1315)
    c.chest(4, yaw=-10, pitch=4, roll=-2)
    c.chest(8, yaw=22, pitch=10, roll=3)
    c.chest(10, yaw=26, pitch=12, roll=3)
    c.chest(16, yaw=5, pitch=2)
    c.shoulder(4, "r", forward=-6, up=14)
    c.shoulder(8, "r", forward=14, up=6)
    c.shoulder(15, "r", forward=2, up=2)
    c.shoulder(4, "l", forward=7, up=3)
    c.shoulder(8, "l", forward=-7, up=-2)
    c.shoulder(15, "l", forward=-1, up=0)
    c.head(4, yaw=3, pitch=2, roll=3)
    c.head(8, yaw=3, pitch=5, roll=-3)
    c.hand(
        4,
        "r",
        at=(-0.38, -0.05, 1.70),
        elbow=(-1.0, -0.3, -0.5),
        palm=(1.0, 0.0, 0.0),
        cock=15,
    )
    c.hand(
        8,
        "r",
        at=(-0.10, 0.44, 1.52),
        elbow=(-0.8, -0.2, -1.0),
        palm=(1.0, 0.0, 0.0),
        cock=25,
    )
    c.hand(
        10,
        "r",
        at=(-0.06, 0.44, 1.36),
        elbow=(-0.8, -0.2, -1.0),
        palm=(1.0, 0.0, 0.0),
        cock=20,
    )
    c.hand(
        16,
        "r",
        at=(-0.22, 0.28, 1.20),
        elbow=(-0.6, -0.6, -1.0),
        palm=(1.0, 0.0, 0.0),
        cock=5,
    )
    left_off(c, 2, 20)
    c.hand(5, "l", at=(0.16, 0.32, 1.30), elbow=(0.6, -0.3, -1.0), palm=(-0.3, 1.0, 0.0))
    c.hand(8, "l", at=(0.22, 0.16, 1.24), elbow=(0.6, -0.8, -0.8), palm=(-1.0, 0.0, -0.2))
    c.hand(10, "l", at=(0.23, 0.14, 1.22), elbow=(0.6, -0.8, -0.8), palm=(-1.0, 0.0, -0.2))
    c.hand(16, "l", at=(0.17, 0.21, 1.31), elbow=(0.7, -0.6, -0.8), palm=(-1.0, 0.0, -0.2))
    for frame, closed in ((5, 0.5), (8, 0.8), (10, 0.8), (16, 0.4)):
        c.fingers(frame, "l", closed)
    return c


def pistol_backhand(rig):
    """A backhand with the pistol: the hand is carried across to the left shoulder as the chest winds left, then
    swings out level to the right, the back of the hand and the pistol's flat leading."""
    c = Clip(rig, "Melee_Pistol_Backhand", 21, PISTOL_IDLE, 8, "r", "pistol", "slide")
    c.what = "the pistol across to the left shoulder and out level to the right, the slide's flat leading"
    c.chest(5, yaw=26, pitch=3, roll=4)
    c.chest(8, yaw=8, pitch=5, roll=-2)
    c.chest(11, yaw=-6, pitch=5, roll=-4)
    c.chest(16, yaw=-2, pitch=1)
    c.shoulder(5, "r", forward=14, up=6)
    c.shoulder(8, "r", forward=12, up=6)
    c.shoulder(15, "r", forward=2, up=2)
    c.shoulder(5, "l", forward=-9, up=-3)
    c.shoulder(8, "l", forward=-5, up=-2)
    c.shoulder(15, "l", forward=-1, up=0)
    c.head(5, yaw=5, pitch=2, roll=3)
    c.head(8, yaw=-3, pitch=4, roll=-3)
    c.hand(
        5,
        "r",
        at=(0.16, 0.24, 1.44),
        elbow=(-0.2, 1.0, -0.6),
        palm=(0.3, -1.0, 0.0),
        cock=10,
    )
    c.hand(
        8,
        "r",
        at=(-0.12, 0.43, 1.44),
        elbow=(-1.0, -0.2, -0.6),
        palm=(1.0, 0.0, 0.0),
        cock=20,
    )
    c.hand(
        11,
        "r",
        at=(-0.36, 0.30, 1.42),
        elbow=(-1.0, -0.6, -0.6),
        palm=(1.0, 0.3, 0.0),
        cock=10,
    )
    c.hand(
        16,
        "r",
        at=(-0.26, 0.26, 1.18),
        elbow=(-0.6, -0.6, -1.0),
        palm=(1.0, 0.0, 0.0),
        cock=5,
    )
    left_off(c, 2, 19)
    c.hand(5, "l", at=(0.30, 0.04, 1.06), elbow=(0.6, -1.0, -0.4), palm=(-1.0, 0.0, 0.0))
    c.hand(8, "l", at=(0.27, 0.14, 1.14), elbow=(0.6, -0.8, -0.8), palm=(-1.0, 0.0, 0.0))
    c.hand(10, "l", at=(0.26, 0.16, 1.16), elbow=(0.6, -0.8, -0.8), palm=(-1.0, 0.0, 0.0))
    c.hand(16, "l", at=(0.27, 0.12, 1.08), elbow=(0.5, -0.9, -0.7), palm=(-1.0, 0.0, -0.2))
    for frame, closed in ((5, 0.5), (8, 0.8), (10, 0.8), (16, 0.4)):
        c.fingers(frame, "l", closed)
    return c


def pistol_jab(rig):
    """A short jab with the pistol's butt: the pistol is drawn back to the ribs, muzzle up, and driven forward
    and up from the elbow with the butt leading; the left hand guards."""
    c = Clip(rig, "Melee_Pistol_Jab", 19, PISTOL_IDLE, 7, "r", "pistol", "butt")
    c.what = "the pistol back to the ribs and driven forward and up, the butt leading; the left hand guards"
    c.chest(3, yaw=-14, pitch=1.5, roll=-3)
    c.chest(7, yaw=28, pitch=8, roll=4)
    c.chest(9, yaw=30, pitch=8, roll=4)
    c.chest(14, yaw=5, pitch=2)
    c.shoulder(3, "r", forward=-6, up=4)
    c.shoulder(7, "r", forward=14, up=6)
    c.shoulder(13, "r", forward=2, up=2)
    c.shoulder(3, "l", forward=5, up=4)
    c.shoulder(7, "l", forward=-6, up=5)
    c.shoulder(13, "l", forward=-1, up=1)
    c.head(7, yaw=4, pitch=5, roll=-3)
    c.hand(
        3,
        "r",
        at=(-0.27, 0.08, 1.20),
        elbow=(-0.6, -1.0, -0.6),
        palm=(1.0, 0.0, 0.0),
        cock=20,
    )
    c.hand(
        7,
        "r",
        at=(-0.08, 0.47, 1.40),
        elbow=(-0.6, -0.2, -1.0),
        palm=(1.0, 0.0, 0.0),
        cock=28,
    )
    c.hand(
        9,
        "r",
        at=(-0.08, 0.44, 1.39),
        elbow=(-0.6, -0.2, -1.0),
        palm=(1.0, 0.0, 0.0),
        cock=25,
    )
    c.hand(
        14,
        "r",
        at=(-0.24, 0.28, 1.18),
        elbow=(-0.6, -0.6, -1.0),
        palm=(1.0, 0.0, 0.0),
        cock=5,
    )
    left_off(c, 2, 17)
    c.hand(4, "l", at=(0.18, 0.30, 1.28), elbow=(0.6, -0.3, -1.0), palm=(-0.3, 1.0, 0.0))
    c.hand(7, "l", at=(0.21, 0.18, 1.30), elbow=(0.6, -0.7, -0.8), palm=(-1.0, 0.2, 0.0))
    c.hand(9, "l", at=(0.21, 0.17, 1.30), elbow=(0.6, -0.7, -0.8), palm=(-1.0, 0.2, 0.0))
    c.hand(14, "l", at=(0.16, 0.25, 1.33), elbow=(0.7, -0.5, -0.9), palm=(-1.0, 0.0, -0.2))
    for frame, closed in ((4, 0.5), (7, 0.8), (9, 0.8), (14, 0.4)):
        c.fingers(frame, "l", closed)
    return c


CLIPS = {
    "Melee_Unarmed_Jab": unarmed_jab,
    "Melee_Unarmed_Cross": unarmed_cross,
    "Melee_Unarmed_Hook": unarmed_hook,
    "Melee_Pistol_Whip": pistol_whip,
    "Melee_Pistol_Backhand": pistol_backhand,
    "Melee_Pistol_Jab": pistol_jab,
}


# ---------------------------------------------------------------------------------------------------------------
# Baking, checks, export
# ---------------------------------------------------------------------------------------------------------------
def bake(rig, clip, shown=False):
    """Key the clip onto the armature, one key a frame on every bone. `shown` bakes it as the game shows it (the
    wrist turned under the grip), for the checks and the renders; the exported clip is the plain one."""
    arm = rig.arm
    action = bpy.data.actions.new(clip.name + ("_shown" if shown else ""))
    arm.animation_data_create()
    arm.animation_data.action = action
    last = {}
    for frame in range(clip.frames + 1):
        mats = clip.solve(frame, shown)
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
    return action


def play(rig, action):
    data = rig.arm.animation_data
    data.action = action
    data.action_slot = action.slots[0]


def joints_of(arm, names):
    return {name: (arm.matrix_world @ arm.pose.bones[name].matrix).translation.copy() for name in names}


def crossing(values, frame, step, limit):
    """Walking from `frame` by `step` while `values` stay under `limit`: the time (in frames) the limit is
    crossed, between two frames, or the clip's end."""
    at = frame
    while 0 <= at + step < len(values) and values[at + step] <= limit:
        at += step
    nxt = at + step
    if not 0 <= nxt < len(values):
        return float(at)
    share = (limit - values[at]) / (values[nxt] - values[at])
    return at + step * share


def check(rig, clip, action, shown):
    """Fail on what a blow can get wrong, on the baked keys: limbs or the pistol in the body, a pose that does
    not join, a snap, an open fist, a locked elbow, a wrist bent too far, a blow that does not reach."""
    problems, report = [], {}
    scene = bpy.context.scene
    arm = rig.arm
    female, male = rig.bodies
    gun = rig.gun if clip.weapon == "pistol" else None
    frames = range(clip.frames + 1)
    hand, knuckle = f"hand_{clip.side}", f"middle_01_{clip.side}"

    # The exported keys against the pose they join.
    play(rig, action)
    watched = MAIN_JOINTS
    join = {}
    for frame, label in ((0, "first"), (clip.frames, "last")):
        scene.frame_set(frame)
        now = joints_of(arm, watched)
        worst = max(watched, key=lambda n: (now[n] - clip.base[n].translation).length)
        join[label] = [
            round((now[worst] - clip.base[worst].translation).length * 1000.0, 2),
            worst,
        ]
        if join[label][0] > JOIN_LIMIT:
            problems.append(f"the {label} pose is {join[label][0]} mm from {clip.joins} at {worst}")
    report["join_mm"] = join

    # As the game shows it, on every frame, on both mannequins' skinned meshes.
    import limb_overlap

    play(rig, shown)
    places = {body.name: [] for body in rig.bodies}
    strikes = {body.name: [] for body in rig.bodies}
    chests = {}
    crossed = {body.name: {} for body in rig.bodies}  # pair: depth on each frame (mm)
    gun_near = {body.name: [9999.0, None] for body in rig.bodies}
    straight, wrist_bend, tips = [0.0, None, None], [0.0, None, None], [0.0, None, None]
    lean = {"chest_deg": [0.0, None], "head_deg": [0.0, None], "head_back_mm": [0.0, None]}
    for frame in frames:
        scene.frame_set(frame)
        if frame <= clip.contact:  # the wind-up: how far the trunk and the head are back of the joined pose
            pose = {n: arm.matrix_world @ arm.pose.bones[n].matrix for n in ("spine_03", "Head")}
            for key, name in (("chest_deg", "spine_03"), ("head_deg", "Head")):
                up = pose[name].to_3x3() @ clip.base[name].to_3x3().inverted() @ Vector((0.0, 0.0, 1.0))
                back = math.degrees(math.atan2(up.y, up.z))
                if back > lean[key][0]:
                    lean[key] = [round(back, 2), frame]
            behind = (pose["Head"].translation.y - clip.base["Head"].translation.y) * 1000.0
            if behind > lean["head_back_mm"][0]:
                lean["head_back_mm"] = [round(behind, 1), frame]
        for body in rig.bodies:
            body.pose_from(arm)
            bones = body.arm.pose.bones
            world = body.arm.matrix_world
            now = joints_of(body.arm, watched)
            places[body.name].append(now)
            strikes[body.name].append(clip.strike(world @ bones[hand].matrix, world @ bones[knuckle].head))
            chests.setdefault(body.name, now["spine_03"].copy())
            for side in "lr":
                upper, lower, end = (world @ bones[f"{b}_{side}"].head for b in ("upperarm", "lowerarm", "hand"))
                share = (end - upper).length / ((lower - upper).length + (end - lower).length)
                if share > straight[0] and abs(frame - clip.contact) <= 3:
                    straight = [round(share, 3), frame, side]
                _palm, fingers = rig.palm_of(side, (world @ bones[f"hand_{side}"].matrix).to_3x3())
                bend = math.degrees(fingers.angle(end - lower))
                if bend > wrist_bend[0] and 0 < frame < clip.frames:
                    wrist_bend = [round(bend, 1), frame, side]
                if clip.weapon == "fists":
                    for finger in FINGERS[1:]:
                        tip = world @ bones[f"{finger}_04_leaf_{side}"].head
                        away = (tip - end).length
                        if away > tips[0]:
                            tips = [
                                round(away, 4),
                                frame,
                                f"{finger}_{side} ({body.name})",
                            ]
            pairs = {f"{a} in {b}": depth * 1000.0 for (a, b), (depth, _place) in body.overlaps().items()}
            if gun:
                deep, part, near = gun.against(body, body.skinned(), gun.matrix(world @ bones["hand_r"].matrix))
                if deep > 0.0:
                    pairs[f"pistol in {part}"] = deep
                if near < gun_near[body.name][0]:
                    gun_near[body.name] = [near, frame]
            for pair, depth in pairs.items():
                crossed[body.name].setdefault(pair, [0.0] * (clip.frames + 1))[frame] = round(depth, 1)
    if straight[0] > ARM_LIMIT:
        problems.append(
            f"the {straight[2]} arm is at {straight[0]} of its length at frame {straight[1]} (a locked elbow in the "
            f"blow; the limit is {ARM_LIMIT})"
        )
    report["straightest_arm"] = straight
    report["wind_up_lean_back"] = lean
    for key, part, limit, unit in (
        ("chest_deg", "chest leans", LEAN_BACK_LIMIT, "degrees"),
        ("head_deg", "head tips", LEAN_BACK_LIMIT, "degrees"),
        ("head_back_mm", "head moves", HEAD_BACK_LIMIT, "mm"),
    ):
        if lean[key][0] > limit:
            problems.append(
                f"the {part} {lean[key][0]} {unit} back of {clip.joins} at frame {lean[key][1]}, before contact "
                f"(the limit is {limit}: the arm winds a blow up, the trunk does not lean away)"
            )
    report["wrist_bend_deg"] = wrist_bend
    if wrist_bend[0] > WRIST_LIMIT:
        problems.append(f"the {wrist_bend[2]} wrist is bent {wrist_bend[0]} degrees at frame {wrist_bend[1]}")
    if clip.weapon == "fists":
        report["fist_open_mm"] = [round(tips[0] * 1000.0, 1), tips[1], tips[2]]
        if tips[0] > FIST_TIP_LIMIT:
            problems.append(f"a fist is open: {tips[2]} is {tips[0] * 1000:.0f} mm from its wrist at frame {tips[1]}")
    # Limbs in limbs and the pistol in the body. A pair the joined pose itself crosses is held to that pose's
    # depth while its hand is still near its joined place, and to the limit everywhere else.
    report["overlap_mm"], report["gun_in_body_mm"], report["joined_pose_mm"] = (
        {},
        {},
        {},
    )
    left, right = ("hand_l", "lowerarm_l"), ("hand_r", "lowerarm_r", "pistol")
    for body in rig.bodies:
        worst = {False: [0.0, None, None], True: [0.0, None, None]}
        joined = {pair: max(d[0], d[-1]) for pair, d in crossed[body.name].items() if max(d[0], d[-1]) > 0.0}
        deepest = max(joined.values(), default=0.0)
        faded = [0.0, None, None]
        for pair, depths in crossed[body.name].items():
            of_gun = pair.startswith("pistol")
            limit = GUN_LIMIT if of_gun else OVERLAP_LIMIT
            hands = any(n in pair for n in left) and any(n in pair for n in right)
            for frame, depth in enumerate(depths):
                if hands and deepest > limit and (frame <= FADE_IN or frame >= clip.frames - FADE_OUT):
                    if depth > faded[0]:
                        faded = [depth, frame, pair]
                    if depth <= deepest + JOINED_SLACK:
                        continue  # the joined pose's own crossing, while the game fades the clip
                if depth > worst[of_gun][0]:
                    worst[of_gun] = [depth, frame, pair]
                if depth > limit:
                    problems.append(f"{body.name}: {pair} by {depth} mm at frame {frame} (the limit is {limit} mm)")
        if gun:
            joined["deepest_while_fading"] = faded
        report["overlap_mm"][body.name] = worst[False]
        report["joined_pose_mm"][body.name] = joined
        if gun:
            report["gun_in_body_mm"][body.name] = worst[True]
        print(f"OVERLAP {clip.name} {body.name}: {json.dumps(crossed[body.name])}")
    if gun:
        report["gun_nearest_head_or_trunk_mm"] = gun_near
    else:
        del report["gun_in_body_mm"]
    del limb_overlap

    # No snap: how much each joint's velocity changes from one frame to the next (the female's, the keyed body).
    snap = {}
    track = places["female"]
    for name in watched:
        limit = next((v for k, v in SNAP_LIMIT.items() if name.startswith(k)), None)
        if limit is None:
            continue
        speeds = [(track[f][name] - track[f - 1][name]) * FPS for f in range(1, clip.frames + 1)] + [Vector()]
        changes = [(speeds[i] - speeds[i - 1]).length for i in range(1, len(speeds))]
        worst = max(range(len(changes)), key=lambda i: changes[i])
        snap[name] = [
            round(changes[worst], 2),
            worst + 1,
            round(max(s.length for s in speeds), 2),
        ]
        if changes[worst] > limit:
            problems.append(
                f"{name} snaps: its velocity changes {changes[worst]:.1f} m/s at frame {worst + 1} (limit {limit})"
            )
    report["snap_m_s"] = {name: value[:2] for name, value in snap.items()}
    report["start_speed_m_s"] = round(((track[1][hand] - track[0][hand]) * FPS).length, 2)

    # The blow: where the striking point is at contact, how fast it comes, and the window.
    blow = {}
    for body in rig.bodies:
        path = strikes[body.name]
        chest = chests[body.name]
        ahead = [-(p.y - chest.y) for p in path]
        from_contact = [(p - path[clip.contact]).length for p in path]
        speeds = [0.0] + [(path[f] - path[f - 1]).length * FPS for f in range(1, clip.frames + 1)]
        fastest = max(range(len(speeds)), key=lambda f: speeds[f])
        blow[body.name] = {
            "reach": round(ahead[clip.contact], 3),
            "furthest": round(max(ahead), 3),
            "furthest_at": round(max(frames, key=lambda f: ahead[f]) / FPS, 4),
            "point": lfu(path[clip.contact]),
            "fastest_m_s": round(speeds[fastest], 2),
            "fastest_at": round(fastest / FPS, 4),
            "into_contact_m_s": round(max(speeds[clip.contact - 2 : clip.contact + 1]), 2),
            "after_contact_m_s": round(max(speeds[clip.contact + 1 :]), 2),
            "hit_start": round(crossing(from_contact, clip.contact, -1, WINDOW) / FPS, 4),
            "hit_end": round(crossing(from_contact, clip.contact, 1, WINDOW) / FPS, 4),
        }
    report["blow"] = blow
    mine = blow["female"]
    for body, entry in blow.items():
        if not REACH[0] <= entry["reach"] <= REACH[1]:
            problems.append(
                f"{body}: the striking point is {entry['reach']} m in front of the chest at contact, not in {REACH}"
            )
    if not HEIGHT[0] <= mine["point"][2] <= HEIGHT[1]:
        problems.append(f"the striking point is {mine['point'][2]} m up at contact, not in {HEIGHT}")
    if mine["after_contact_m_s"] > mine["into_contact_m_s"]:
        problems.append(
            f"the striking point is faster after contact ({mine['after_contact_m_s']} m/s) than into it "
            f"({mine['into_contact_m_s']} m/s)"
        )
    spans = TIMES[clip.weapon]
    for label, value in (
        ("contact", clip.contact / FPS),
        ("length", clip.frames / FPS),
    ):
        if not spans[label][0] - 1e-6 <= value <= spans[label][1] + 1e-6:
            problems.append(f"its {label} is {value:.3f} s, not in {spans[label]}")

    return problems, report


def self_test(rig):
    """The pistol check reads the game's hold as clear and a pistol pushed into the head as deep inside it."""
    clip = Clip(rig, "SelfTest", 2, PISTOL_IDLE, 1, "r", "pistol", "butt")
    mats = clip.solve(0, shown=True)
    rig.arm.animation_data_create()
    rig.arm.animation_data.action = None
    for name in rig.order:
        bone = rig.arm.pose.bones[name]
        bone.rotation_mode = "QUATERNION"
        bone.rotation_quaternion = rig.basis(name, mats)
        if name == "pelvis":
            bone.location = (rig.rest_rel[name].inverted() @ (mats["root"].inverted() @ mats["pelvis"])).translation
    bpy.context.view_layer.update()
    out = {}
    for body in rig.bodies:
        body.pose_from(rig.arm)
        world = body.arm.matrix_world
        coords = body.skinned()
        held = rig.gun.matrix(world @ body.arm.pose.bones["hand_r"].matrix)
        # the joined pose's left hand lies on the pistol (the game's own solver holds it there): set aside here
        clear = rig.gun.against(body, coords, held, skip=("hand_r", "hand_l", "lowerarm_l"))
        # the hand that holds it, measured for once: the seat and the grip read here are the game's
        grip = rig.gun.against(body, coords, held, skip=[p for p in body.parts if p != "hand_r"])
        head = world @ body.arm.pose.bones["Head"].matrix
        inside = placed(head.translation + Vector((0.0, 0.0, 0.08)), held.to_3x3())
        deep = rig.gun.against(body, coords, inside)
        out[body.name] = {
            "carried": clear[0],
            "hand_on_grip": grip[0],
            "in_the_head": deep[0],
        }
        print(f"SELFTEST pistol {body.name}: {out[body.name]}")
        assert clear[0] <= GUN_LIMIT, f"{body.name}: the pistol as carried reads {clear} mm in the body"
        assert grip[0] <= 10.0, f"{body.name}: the hand is {grip[0]} mm in the grip: the seat was read wrongly"
        assert deep[0] > 15.0 and deep[1] == "head", f"{body.name}: a pistol in the head reads {deep}"
    for name, point in GUN_POINTS.items():
        _place, _normal, _index, off = rig.gun.tree.find_nearest(TO_Z_UP @ point)
        out[f"{name}_off_the_pistol"] = round(off * 1000.0, 1)
        print(f"SELFTEST pistol point {name}: {off * 1000:.1f} mm from the pistol's surface")
        assert off < 0.006, f"the striking point {name} is {off * 1000:.1f} mm off the pistol"
    for bone in rig.arm.pose.bones:
        bone.rotation_quaternion = Quaternion()
        bone.location = Vector()
    return out


def sidecar(clips, path):
    out = {
        "fps": FPS,
        "units": (
            "metres and seconds from the clip's start; places are [left, forward, up] from the character's root; "
            "reach is how far the striking point is in front of the chest (the spine_03 joint) at contact"
        ),
        # The file the numbers below were measured on: a test fails when melee.glb is not this file any more.
        "measured": {
            "file": path.name,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "overlap_limit_mm": OVERLAP_LIMIT,
            "gun_limit_mm": GUN_LIMIT,
            "join_limit_mm": JOIN_LIMIT,
            "snap_limit_m_s": SNAP_LIMIT,
            "hit_window_m": WINDOW,
        },
        "gun_points": {name: [round(x, 4) for x in point] for name, point in GUN_POINTS.items()},
        "clips": {},
    }
    for clip in clips:
        blow = clip.report["blow"]["female"]
        out["clips"][clip.name] = {
            "length": round(clip.frames / FPS, 4),
            "frames": clip.frames,
            "loop": False,
            "weapon": clip.weapon,
            "joins": clip.joins,
            "what": clip.what,
            "contact": round(clip.contact / FPS, 4),
            "hit_start": blow["hit_start"],
            "hit_end": blow["hit_end"],
            "striking_bone": f"hand_{clip.side}",
            "striking_point": (
                "the middle finger's knuckle (the middle_01 bone's joint)"
                if clip.point == "knuckles"
                else f"the pistol's {clip.point} (gun_points, in the Pistol node's space)"
            ),
            "reach": blow["reach"],
            "point_at_contact": blow["point"],
            "into_contact_m_s": blow["into_contact_m_s"],
            "male": {key: clip.report["blow"]["male"][key] for key in ("reach", "point", "hit_start", "hit_end")},
            "checks": {key: value for key, value in clip.report.items() if key != "blow"},
        }
    return out


def export(rig, actions, out):
    """Write the armature and its clips, with a one-triangle skin so Godot makes a Skeleton3D of every bone."""
    arm = rig.arm
    male = rig.bodies[1]
    for obj in rig.library_objects + male.objects + rig.gun.objects + rig.extras + [rig.mesh]:
        bpy.data.objects.remove(obj, do_unlink=True)
    keep = set(actions)
    for action in list(bpy.data.actions):
        if action not in keep:
            bpy.data.actions.remove(action)
    mesh = bpy.data.meshes.new("MeleeRig")
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0, 0.01)], [], [(0, 1, 2)])
    proxy = bpy.data.objects.new("MeleeRig", mesh)
    bpy.context.scene.collection.objects.link(proxy)
    proxy.parent = arm
    proxy.vertex_groups.new(name="root").add([0, 1, 2], 1.0, "REPLACE")
    proxy.modifiers.new("Armature", "ARMATURE").object = arm
    arm.animation_data.action = None
    for action in sorted(actions, key=lambda a: a.name):
        track = arm.animation_data.nla_tracks.new()
        track.name = action.name
        strip = track.strips.new(action.name, 0, action)
        strip.action_slot = action.slots[0]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (arm, proxy):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = out / "melee.glb"
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
        out[animation["name"]] = {
            "length": round(end, 4),
            "channels": len(animation["channels"]),
            "translation": moved,
        }
    return out


def played_back(rig, clips, path):
    """Import the exported file and compare what it plays with what was solved: the furthest any main joint is
    from its solved place (mm) on the first, the contact and the last frame of every clip."""
    before = set(bpy.data.objects)
    known = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(path))
    arm = next(o for o in bpy.data.objects if o not in before and o.type == "ARMATURE")
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    actions = {a.name.split(".")[0]: a for a in bpy.data.actions if a not in known}
    worst = 0.0
    for clip in clips:
        action = actions[clip.name]
        assert [round(f) for f in action.frame_range] == [0, clip.frames], (
            clip.name,
            action.frame_range[:],
        )
        arm.animation_data.action = action
        arm.animation_data.action_slot = action.slots[0]
        for frame in (0, clip.contact, clip.frames):
            bpy.context.scene.frame_set(frame)
            mats = clip.solve(frame)
            now = joints_of(arm, MAIN_JOINTS + [f"middle_03_{s}" for s in "lr"])
            worst = max([worst] + [(now[n] - mats[n].translation).length for n in now])
    return round(worst * 1000.0, 3)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(HERE))
    parser.add_argument("--render", default="")
    parser.add_argument("--only", default="")
    parser.add_argument("--no-fail", action="store_true")
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    rig = Rig()
    hold = self_test(rig)
    names = [args.only] if args.only else FILE_CLIPS
    clips = [CLIPS[name](rig) for name in names]
    actions, shown, failed = [], [], False
    for clip in clips:
        action = bake(rig, clip)
        seen = bake(rig, clip, shown=True) if clip.weapon == "pistol" else action
        problems, clip.report = check(rig, clip, action, seen)
        print(f"CLIP {clip.name}: {clip.frames} frames, {json.dumps(clip.report)}")
        if args.trace:
            trace(rig, clip)
        for problem in problems:
            failed = True
            print(f"PROBLEM {clip.name}: {problem}")
        actions.append(action)
        shown.append(seen)
    if args.render:
        import render_melee

        render_melee.render(rig, clips, shown, Path(args.render))
    if failed and not args.no_fail:
        sys.exit("the clips fail their checks; nothing was exported")
    if args.only or failed:
        return
    path = export(rig, actions, out)
    strip(path)
    found = read_back(path)
    assert sorted(found) == sorted(FILE_CLIPS), f"the file carries {sorted(found)}, not {FILE_CLIPS}"
    for clip in clips:
        assert abs(found[clip.name]["length"] - clip.frames / FPS) < 1e-3, (
            clip.name,
            found[clip.name],
        )
        assert found[clip.name]["translation"] == ["pelvis"], found[clip.name]["translation"]
        assert found[clip.name]["channels"] == len(rig.order) + 1, found[clip.name]["channels"]
    off = played_back(rig, clips, path)
    assert off < 0.5, f"the exported file plays {off} mm from the solved poses"
    report = sidecar(clips, path)
    report["measured"]["played_back_mm"] = off
    report["measured"]["pistol_hold_mm"] = hold
    text = json.dumps(report, indent=2) + "\n"
    (out / "melee_clips.json").write_text(text, encoding="utf-8", newline="\n")
    print("EXPORTED", path, f"played back within {off} mm", json.dumps(found)[:300])


def trace(rig, clip):
    """One line a frame: the chest's yaw, each wrist and elbow angle, the striking point (`--trace`)."""
    for frame in range(clip.frames + 1):
        mats = clip.solve(frame, shown=True)
        chest = mats["spine_03"].to_3x3() @ clip.base["spine_03"].to_3x3().inverted()
        ahead = chest @ Vector((0, -1, 0))
        yaw = math.degrees(math.atan2(ahead.x, -ahead.y))
        strike = clip.strike(mats[f"hand_{clip.side}"], mats[f"middle_01_{clip.side}"].translation)
        line = f"TRACE {clip.name} {frame:2d} chest {yaw:+5.1f} | strike {lfu(strike)}"
        for side in "lr":
            a, b, c = (mats[f"{n}_{side}"].translation for n in ("upperarm", "lowerarm", "hand"))
            share = (c - a).length / ((b - a).length + (c - b).length)
            line += f" | {side} shoulder {lfu(a)} wrist {lfu(c)} elbow {math.degrees((a - b).angle(c - b)):3.0f}"
            line += f" {share:.2f}"
        print(line)


if __name__ == "__main__":
    sys.path[:0] = [str(HERE), str(HERE.parent)]
    try:
        main()
    except Exception:  # Blender exits 0 after a script's exception: a failed assert must fail the build
        import traceback

        traceback.print_exc()
        sys.exit(1)
