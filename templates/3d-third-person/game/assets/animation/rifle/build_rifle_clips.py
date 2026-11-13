"""Build the template's rifle clips and export them to glTF (kit #1082).

GDStudio's own animation, made from nothing on the prototype mannequin rig (`form_female.glb`, the player's body:
GDStudio's own, with the bone names and rest rotations of Quaternius's universal rig, CC0), because the Universal
Animation Library has pistol clips and no rifle clip. Six clips, at the library's 30 frames a second:

- `Rifle_Idle` (a loop): the low ready, the head up and looking ahead, a slow breath;
- `Rifle_Aim_Neutral`, `Rifle_Aim_Up` and `Rifle_Aim_Down` (loops of one length): the rifle at the shoulder with
  the view level and `AIM_PITCH` degrees up and down, the body leant into it, the right shoulder up behind the
  butt and the head the game gives an aimed rifle, canted to the stock with the right eye by the sights;
- `Rifle_Shoot`: a shot's recoil taken by the body, from `Rifle_Aim_Neutral`'s first pose and back to it;
- `Rifle_Reload`: the body through a magazine change and the charging handle, from `Rifle_Idle`'s first pose and
  back to it, the beats at the shares of the reload the game's hold moves the left hand by (the left arm's way to the
  handle and its pull are the hold's `ChargePull`, kit #1266).

Nothing is copied from another game's or pack's motion. The legs and the pelvis are the game's own standing idle
(`gds/Idle`) on its steadiest frame, held: the game plays these clips on the upper body only, over its own
locomotion, and holds the legs on that frame under a standing aim (`AimStance`). A clip keys each bone in its
parent, so the arms it keys are the hold's own over that pelvis.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_rifle_clips.py -- --out <rifle_clips.glb> [--data <rifle_clips.json>]
        [--report <numbers.json>] [--preview <folder>] [--only <clip> ...]

How the hands get on the rifle. In the game the rifle is not carried by a bone: `TwoHandHold`
(`gameplay/weapon/two_hand_hold.gd`) puts its butt in the shoulder's pocket from the chest bone's place, turns the
chest, reaches each arm to its place on the rifle and closes the fingers, after the clip, on whichever body plays
it, with the hands' places and finger poses solved on that body (the scene's own are the female's, the male's are
a `HoldFit`). This build works the same hold out in Python (`Hold`, from the numbers of the hold's own files, none
typed here), so the body is shaped round the rifle where the game will draw it, and the arms and fingers it keys
are the hold's own on the female body: the clip alone shows two hands on the rifle, and the game's hold has
nothing left to move on her (`tests/gameplay/test_rifle_clips.gd` holds the clip's own hands within millimetres of
the hold's). On the male body (longer arms, bigger hands, his own fit) the game's reach does the work, and this
build measures him posed that way; the search for the head's place keeps both bodies' heads off the stock.

It works in Godot's axes (the character faces +Z, its left is +X, up is +Y; a bone's pose in its parent is the
same in Blender and in Godot) and keys every bone's rotation on every frame. It fails before it exports when a
loop does not close, a clip does not start and end on the pose it joins, an arm cannot reach on either body, the
head is in the stock, or a part of the body goes more than
`OVERLAP_LIMIT` into another on either body (`../limb_overlap.py`; the twist bones are turned as the engine's
`MannequinTwist` turns them, so the skin measured is the skin drawn). It reports, and does not fail on, how deep
the neck's base and the chest are in the butt: that is the hold's pocket. The hands against the rifle are
measured in Godot (`tests/gameplay/test_rifle_clips.gd`, `tests/gameplay/test_rifle_hold.gd`).
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import limb_overlap  # noqa: E402

GAME = Path(__file__).resolve().parents[3]
FPS = 30
OVERLAP_LIMIT = 5.0  # millimetres a part of the body may be inside another (`../limb_overlap.py`)
# A clip may not put a limb deeper in another than the hold alone does on the idle pose, plus this.
OVERLAP_OVER_HOLD = 3.0
# The hold brings the left shoulder to the hand guard and the butt to the skin in turns: at most this many, until
# the butt moves less than this between two (metres).
PUSH_PASSES = 8
PUSH_SETTLED = 1e-4
REACH_LIMIT = 0.5  # millimetres an arm may stop short of its place on the rifle
ROLL_LIMIT = 6.5  # degrees the head may roll on the neck, and the neck on the chest, in an aim clip
ROLL_SOFT = 4.0  # the search leans the trunk to keep both under this
HEAD_LIMIT = 5.0  # millimetres the head's skin may be inside the rifle
AIM_PITCH = 45.0  # degrees of view the up and down clips are made for (`CharacterAnimation.aim_pitch_range`)
# The bodies the template's characters wear (`gameplay/character/character_bodies.gd`): the clips are keyed on the
# first, the player's, and measured on every one with the hold solved on it.
MODELS = "assets/characters/prototype"
# The pose the clips stand on: the game's standing idle (`CharacterClips.IDLE`), on its steadiest frame.
BASE_FILE = "assets/animation/own/locomotion.glb"
BASE_CLIP = "gds/Idle"
BODIES = ("form_female", "form_male")

# The clips' lengths, as their last frame (a loop's last frame is its first again).
IDLE_FRAMES = 90
AIM_FRAMES = 60
SHOOT_FRAMES = 12
RELOAD_FRAMES = 66  # 2.2 s, the rifle's `reload_time`: the game stretches the clip to whatever the weapon says

# Godot's axes to Blender's: (x, y, z) to (x, -z, y).
C = np.array([[1.0, 0, 0, 0], [0, 0, -1.0, 0], [0, 1.0, 0, 0], [0, 0, 0, 1.0]])
X, Y, Z = np.eye(3)

# ---- the body's numbers -------------------------------------------------------------------------------------------

# The right eye, from the rig's `socket_camera` (the middle of the head's height, on its front) in the
# character's rest space: metres left, up, forward. The bodies have a visor and no face; this is half the
# distance between a person's pupils to the right, and an eye's depth behind the brow.
EYE_FROM_SOCKET = np.array([-0.032, 0.0, -0.018])
# Where the eye belongs on the rifle, in the rifle's own space (the muzzle is -X, up +Y, its left +Z), and the
# way the sight line runs from there to the front sight: the `AimEye` marker of `rifle_held.tscn`, its origin and
# its -Z, which the game's head goes to as well (`WeaponDef.aim_eye`). Filled in from the scene.
SIGHT_EYE = np.zeros(3)
SIGHT_AHEAD = -X
# The stock in the rifle's space, for the head's place: its comb's top, its half width and where it starts.
STOCK_TOP = 0.167
RECEIVER_TOP = 0.18  # the receiver's tail and the charging handle, ahead of the comb
COMB_FRONT = 0.04  # where the comb starts behind them (the stock is collapsed 5 cm: `build_rifle.py`, `STOCK_IN`)
STOCK_SIDE = 0.031
STOCK_FRONT = -0.04
HEAD_CLEAR = 0.004  # the search keeps the female head this far off the stock
# The head's and the neck's skin of each body, as points from each bone in the character's rest space
# (filled in from the models): `{body: {bone: points}}`.
SKIN_POINTS = {}
# Which of a body's `head` part (the head's and the neck's skin, `../limb_overlap.py`) is the head's own: the
# skin from 3 cm over the head bone up. The rest is the neck down to its base at the shoulders, where the butt
# sits: it is measured with the chest.
HEAD_SKIN = {}
# How far the search may lean the trunk past where a clip starts it (forward, to the right), in degrees.
AIM_LIMITS = {
    "lean": (-12.0, 12.0),
    "side": (-6.0, 6.0),
}
# The collarbones in an aim: the right one up and forward behind the butt, the left one forward with the reach.
# Degrees (up, forward).
AIM_CLAVICLE_R = (9.0, 12.0)
AIM_CLAVICLE_L = (2.0, 9.0)
IDLE_CLAVICLE_R = (6.0, 12.0)
IDLE_CLAVICLE_L = (0.0, 5.0)
# The low ready: the trunk a little forward, the head level and a little down the rifle's way.
IDLE_LEAN = 6.0
IDLE_HUNCH = 12.0  # the chest bone alone, forward: rounded shoulders keep the right forearm off the ribs
AIM_LEAN = 8.0  # degrees the trunk leans into the rifle with the view level
AIM_HUNCH = 8.0
AIM_DOWN_LEAN = 14.0
AIM_DOWN_HUNCH = 10.0
AIM_DOWN_CLEAR = 0.014
AIM_DOWN_CLAVICLE_R = (16.0, 8.0)  # the right shoulder up: it lifts the forearm off the ribs
IDLE_LOOK = (-5.0, 0.0)  # degrees the head looks (up, to the left) at rest
# Breath, in degrees at its top: the two upper spine bones pitch back, the collarbones rise, the head stays.
IDLE_BREATH = 0.7
AIM_BREATH = 0.25
# The shot, at the top of the recoil: degrees the two upper spine bones rock back (each), the right collarbone is
# pushed (up, back), the head rides back with the stock (a negative nod). The gun's own kick is the hold's
# (`kick_distance`, `kick_degrees`), over `kick_recover_time` of real time; the clip plays `SHOOT_SPEED` times
# its own speed (`CharacterAnimation.shoot_speed`).
SHOOT_SPEED = 1.6
SHOT_SPINE = 1.1
SHOT_CLAVICLE = (1.5, 5.0)
# The recoil's share by frame: up in one frame, back by the fourth, a small sway forward, still from the ninth.
SHOT_KEYS = [(0, 0.0), (1, 1.0), (2, 0.72), (3, 0.36), (4, 0.08), (5, -0.14), (7, -0.06), (9, 0.0), (12, 0.0)]

# The reload's body, keyed at shares of the reload: (share, look down, look left, lean, roll left, left shoulder
# drop), in degrees. The eyes go down to the magazine well as the hand leaves the hand guard, follow the hand to
# the belt as the left shoulder drops with it, come back to the well for the new magazine, lift for the charging
# handle and are level again at the end. The seat of the magazine and the bolt running home are small jolts
# (`RELOAD_JOLTS`: share, degrees the chest pitches back for a frame or two).
RELOAD_KEYS = [
    (0.00, 0.0, 0.0, 0.0, 0.0, 0.0),
    (0.14, 20.0, 4.0, 3.0, 0.0, 0.0),
    (0.24, 22.0, 5.0, 3.5, 1.0, 1.0),
    (0.42, 26.0, 14.0, 4.5, 4.0, 5.0),
    (0.50, 25.0, 10.0, 4.0, 3.0, 3.0),
    (0.62, 20.0, 4.0, 3.0, 0.5, 0.0),
    (0.72, 12.0, 2.0, 2.0, 0.0, 0.0),
    (0.86, 5.0, 0.0, 1.0, 0.0, 0.0),
    (1.00, 0.0, 0.0, 0.0, 0.0, 0.0),
]
RELOAD_JOLTS = [(0.62, 0.9), (0.86, 1.2)]  # the seat, and the bolt let go (`ChargePull.release`, its sound)


# ---- small maths --------------------------------------------------------------------------------------------------


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def axis_angle(axis, degrees):
    a = math.radians(degrees)
    axis = np.asarray(axis, float) / np.linalg.norm(axis)
    x, y, z = axis
    k = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return np.eye(3) * math.cos(a) + math.sin(a) * k + (1 - math.cos(a)) * np.outer(axis, axis)


def quat_to_mat(q):  # x y z w, as Godot writes it
    return np.array(Quaternion((q[3], q[0], q[1], q[2])).to_matrix())


def slerp(a, b, t):
    """Between two rotation matrices, the short way."""
    qa = Matrix(a.tolist()).to_quaternion()
    qb = Matrix(b.tolist()).to_quaternion()
    return np.array(qa.slerp(qb, t).to_matrix())


def between(a, b, t):
    """Between two 4 x 4 places: the origin along the line, the rotation the short way."""
    out = np.eye(4)
    out[:3, :3] = slerp(a[:3, :3], b[:3, :3], t)
    out[:3, 3] = a[:3, 3] + (b[:3, 3] - a[:3, 3]) * t
    return out


def moved(place, move):
    out = place.copy()
    out[:3, 3] = out[:3, 3] + np.asarray(move, float)
    return out


def place_of(basis, origin):
    out = np.eye(4)
    out[:3, :3] = basis
    out[:3, 3] = origin
    return out


def spline(keys, at):
    """A smooth way through `keys` [(time, value)]: cubic, with a key's slope that of its neighbours and none at
    the ends."""
    times = [k[0] for k in keys]
    values = [np.asarray(k[1], float) for k in keys]
    if at <= times[0]:
        return values[0]
    if at >= times[-1]:
        return values[-1]
    i = max(k for k in range(len(keys) - 1) if times[k] <= at)

    def slope(k):
        if k == 0 or k == len(keys) - 1:
            return np.zeros_like(values[k])
        return (values[k + 1] - values[k - 1]) / (times[k + 1] - times[k - 1])

    span = times[i + 1] - times[i]
    t = (at - times[i]) / span
    h00, h10 = 2 * t**3 - 3 * t**2 + 1, t**3 - 2 * t**2 + t
    h01, h11 = -2 * t**3 + 3 * t**2, t**3 - t**2
    return h00 * values[i] + h10 * span * slope(i) + h01 * values[i + 1] + h11 * span * slope(i + 1)


def aimed(basis, source, target):
    """The basis turned the short way so that `source` points along `target`."""
    a = source / np.linalg.norm(source)
    b = target / np.linalg.norm(target)
    axis = np.cross(a, b)
    s = np.linalg.norm(axis)
    if s < 1e-9:
        return basis
    return axis_angle(axis / s, math.degrees(math.atan2(s, a @ b))) @ basis


def angle_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    return math.degrees(math.atan2(np.linalg.norm(np.cross(a, b)), a @ b))


# ---- the files of the hold ------------------------------------------------------------------------------------------


def transform_in(text, name):
    """The `<name> = Transform3D(...)` of a block of a scene or resource file as a 4 x 4 (the file writes the
    basis by rows, then the origin)."""
    numbers = [float(v) for v in re.search(name + r" = Transform3D\(([^)]*)\)", text).group(1).split(",")]
    out = np.eye(4)
    out[:3, :3] = np.array(numbers[:9]).reshape(3, 3)
    out[:3, 3] = numbers[9:]
    return out


def read_transform(path, node):
    """A node's `transform` in a scene file."""
    text = Path(path).read_text(encoding="utf-8")
    return transform_in(text.split(f'[node name="{node}"', 1)[1].split("[node", 1)[0], "transform")


def quaternions_in(text):
    """The `rotations` of a `HandPose` in a block of text: bone name to its rotation in its parent (3 x 3)."""
    body = re.search(r"rotations = Dictionary\[StringName, Quaternion\]\(\{(.*?)\}\)", text, re.S)
    found = re.findall(r'&"(\w+)": Quaternion\(([^)]*)\)', body.group(1) if body else "")
    return {name: quat_to_mat([float(v) for v in numbers.split(",")]) for name, numbers in found}


def read_quaternions(path):
    return quaternions_in(Path(path).read_text(encoding="utf-8"))


def read_fit(path):
    """A `HoldFit` file (`gameplay/weapon/hold/hold_fit.gd`): the body's file name, the hands' places and the
    five finger poses, which the file holds as sub-resources."""
    text = Path(path).read_text(encoding="utf-8")
    head, main = text.split("[resource]", 1)
    found = re.finditer(r'\[sub_resource [^\]]*id="(\w+)"\](.*?)(?=\n\[|\Z)', head, re.S)
    blocks = {m.group(1): m.group(2) for m in found}
    fingers = {}
    for name in ("grip", "trigger", "support", "open", "magazine", "charge"):
        found = re.search(name + r'_pose = SubResource\("(\w+)"\)', main)
        if found:
            fingers[name] = quaternions_in(blocks[found.group(1)])
    out = {
        "body": re.search(r'body = "([^"]*)"', main).group(1),
        "right": np.linalg.inv(transform_in(main, "seat")),
        "left": transform_in(main, "support_hand"),
        "on_magazine": transform_in(main, "magazine_hand"),
        "fingers": fingers,
    }
    if "charge_hand = " in main:
        out["on_handle"] = transform_in(main, "charge_hand")
    return out


def _value(text):
    text = text.strip()
    vector = re.match(r"Vector[23]\(([^)]*)\)", text)
    if vector:
        return np.array([float(v) for v in vector.group(1).split(",")])
    try:
        return float(text)
    except ValueError:
        return text


def script_numbers(script):
    """A script's exported and constant numbers by name, as it gives them."""
    out = {}
    for name, value in re.findall(r"^(?:@export\S*(?:\([^\n]*\))? var|const) (\w+)(?:: \w+)? :?= (.+)$", script, re.M):
        out[name] = _value(value)
    return out


def read_numbers(script, scene, node):
    """A script's exported and constant numbers by name, with what the scene's node sets over them."""
    out = {}
    for name, value in re.findall(r"^(?:@export\S*(?:\([^\n]*\))? var|const) (\w+)(?:: \w+)? :?= (.+)$", script, re.M):
        out[name] = _value(value)
    block = scene.split(f'[node name="{node}"', 1)[1].split("[node", 1)[0]
    for name, value in re.findall(r"^(\w+) = (.+)$", block, re.M):
        out[name] = _value(value)
    return out


# ---- the rig --------------------------------------------------------------------------------------------------------


class Rig:
    """A body's rest skeleton in Godot's axes: each bone's rest in its parent, parents first."""

    def __init__(self, arm, name=""):
        self.name = name
        assert np.allclose(np.array(arm.matrix_world), np.eye(4), atol=1e-6), "the armature is not at the origin"
        bones = sorted(arm.data.bones, key=lambda b: len(b.parent_recursive))
        self.names = [b.name for b in bones]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        rest = {b.name: np.linalg.inv(C) @ np.array(b.matrix_local) for b in bones}
        self.rest_world = rest
        self.rest = {n: (np.linalg.inv(rest[self.parent[n]]) @ rest[n]) if self.parent[n] else rest[n] for n in self.names}
        # The right eye from the head bone, in the character's rest space.
        self.eye = rest["socket_camera"][:3, 3] - rest["Head"][:3, 3] + EYE_FROM_SOCKET

    def chain(self, pose, upto):
        """The place of one bone in the character's space, worked out up its parents."""
        names, n = [], upto
        while n:
            names.append(n)
            n = self.parent[n]
        out = np.eye(4)
        for n in reversed(names):
            local = self.rest[n].copy()
            local[:3, :3] = pose["local"][n]
            if n == "pelvis":
                local[:3, 3] = pose["pelvis"]
            out = out @ local
        return out

    def turn(self, pose, bone, rotation):
        """Turns a bone, and all below it, by a rotation given in the character's space."""
        world = self.chain(pose, bone)[:3, :3]
        above = self.chain(pose, self.parent[bone])[:3, :3]
        pose["local"][bone] = above.T @ rotation @ world

    def face(self, pose, bone, rotation=None):
        """Stands a bone as its rest has it in the character's space (upright, facing the front), turned by
        `rotation` from there, whatever the bones above it do."""
        above = self.chain(pose, self.parent[bone])[:3, :3]
        world = self.rest_world[bone][:3, :3]
        pose["local"][bone] = above.T @ (world if rotation is None else rotation @ world)


def copy_pose(pose):
    return {"local": dict(pose["local"]), "pelvis": pose["pelvis"].copy()}


def keyed(rig, name):
    """Whether a clip keys this bone: not the root (the clips are in place), a `_leaf`, a twist bone, a socket or
    an `ik_` target (`docs/tools/blender/mannequin-rig.md`)."""
    if rig.parent[name] is None or "_leaf" in name or "twist" in name:
        return False
    return not name.startswith(("socket_", "ik_"))


def roll_about_y(turn):
    """The part of a rotation (3 x 3) that is a roll about the bone's own length, its Y axis: the swing-twist
    split of `MannequinTwist.twist_about_y`."""
    q = Matrix(turn.tolist()).to_quaternion()
    roll = Quaternion((q.w, 0.0, q.y, 0.0))
    if roll.magnitude < 1e-6:
        return np.eye(3)
    return np.array(roll.normalized().to_matrix())


def twist(rig, pose):
    """Turns the prototype rig's twist bones for the pose, as the engine's `MannequinTwist` does after every
    modifier: the upper arm's and the thigh's roll is taken back out at the shoulder and the hip, and the
    wrist end of the forearm takes the hand's roll. No clip keys them; the skin is measured and drawn with
    them."""
    for side in ("l", "r"):
        for limb in ("upperarm", "thigh"):
            bone, source = f"{limb}_twist_01_{side}", f"{limb}_{side}"
            if bone in rig.rest:
                roll = roll_about_y(rig.rest[source][:3, :3].T @ pose["local"][source])
                pose["local"][bone] = rig.rest[bone][:3, :3] @ roll.T
        bone, source = f"lowerarm_twist_01_{side}", f"hand_{side}"
        if bone in rig.rest:
            roll = roll_about_y(pose["local"][source] @ rig.rest[source][:3, :3].T)
            pose["local"][bone] = roll @ rig.rest[bone][:3, :3]


def whole(rig, pose):
    """The pose with every bone of the rig in it: a bone the pose does not name stands at its rest."""
    out = copy_pose(pose)
    for n in rig.names:
        out["local"].setdefault(n, rig.rest[n][:3, :3])
    return out


def reach(rig, pose, side, goal, elbow):
    """Brings the hand of `side` to `goal` (a place in the character's space) by turning the upper arm, the
    forearm and the hand: the two-bone reach of the game's `HoldArm`, from the pose's own arm. Returns how far
    the wrist stops short, in metres."""
    names = [f"upperarm_{side}", f"lowerarm_{side}", f"hand_{side}"]
    above = rig.chain(pose, rig.parent[names[0]])
    locals_ = []
    for n in names:
        local = rig.rest[n].copy()
        local[:3, :3] = pose["local"][n]
        locals_.append(local)
    upper = above @ locals_[0]
    fore = upper @ locals_[1]
    hand = fore @ locals_[2]
    upper_length = np.linalg.norm(fore[:3, 3] - upper[:3, 3])
    fore_length = np.linalg.norm(hand[:3, 3] - fore[:3, 3])
    to_goal = goal[:3, 3] - upper[:3, 3]
    distance = np.linalg.norm(to_goal)
    span = min(max(distance, abs(upper_length - fore_length) + 0.001), upper_length + fore_length - 0.001)
    along = to_goal / distance
    forward = (upper_length**2 - fore_length**2 + span**2) / (2.0 * span)
    out = math.sqrt(max(upper_length**2 - forward**2, 0.0))
    pole = np.asarray(elbow, float) - upper[:3, 3]
    pole = pole - along * (pole @ along)
    pole = pole / np.linalg.norm(pole)
    elbow_at = upper[:3, 3] + along * forward + pole * out
    wrist_at = upper[:3, 3] + along * span
    upper[:3, :3] = aimed(upper[:3, :3], fore[:3, 3] - upper[:3, 3], elbow_at - upper[:3, 3])
    fore = upper @ locals_[1]
    hand = fore @ locals_[2]
    fore[:3, :3] = aimed(fore[:3, :3], hand[:3, 3] - fore[:3, 3], wrist_at - fore[:3, 3])
    pose["local"][names[0]] = above[:3, :3].T @ upper[:3, :3]
    pose["local"][names[1]] = upper[:3, :3].T @ fore[:3, :3]
    pose["local"][names[2]] = fore[:3, :3].T @ goal[:3, :3]
    return abs(distance - span)


# ---- the game's hold, worked out here -------------------------------------------------------------------------------


class Hold:
    """`TwoHandHold` and `TwoHandStance` as the game runs them, from their own files: where the rifle is for a
    chest, how the chest turns, where each hand's bone goes and how the fingers lie. `state` is what the game
    tells the hold: `raised` (0 the low ready, 1 at the shoulder), `pitch` (degrees of view, up positive), `kick`
    (1 on the frame of a shot) and `reload` (the share of a reload, below 0 for none)."""

    def __init__(self, body_file=""):
        """`body_file`: the model's file name. A body that one of the hold's `fits` was solved on gets that
        fit's places and poses (`TwoHandHold._fit_body`); any other the scene's own."""
        weapon = GAME / "gameplay/weapon"
        # The torso's skin the butt meets is a class of its own (`TorsoSkin`): its constants are the hold's too.
        script = (weapon / "two_hand_hold.gd").read_text(encoding="utf-8")
        script += "\n" + (weapon / "hold/torso_skin.gd").read_text(encoding="utf-8")
        held = weapon / "rifle_held.tscn"
        self.n = read_numbers(script, held.read_text(encoding="utf-8"), "RifleHeld")
        self.rifle = read_transform(held, "Rifle")
        self.right = read_transform(held, "RightHandTarget")
        self.left = read_transform(held, "LeftHandTarget")
        self.on_magazine = read_transform(held, "MagazineHand")
        # The charging handle's pull (kit #1266): `ChargePull`'s numbers (the scene keeps its defaults) and where
        # the hand sits on the handle.
        self.charge = script_numbers((weapon / "hold/charge_pull.gd").read_text(encoding="utf-8"))
        self.on_handle = read_transform(held, "ChargeHand")
        global SIGHT_EYE, SIGHT_AHEAD
        sights = read_transform(held, "AimEye")
        SIGHT_EYE, SIGHT_AHEAD = sights[:3, 3], -sights[:3, 2]
        base = weapon / "two_hand_hold.tscn"
        self.poles = {"r": read_transform(base, "RightPole")[:3, 3], "l": read_transform(base, "LeftPole")[:3, 3]}
        if (held.read_text(encoding="utf-8")).count('[node name="RightPole"'):
            self.poles = {"r": read_transform(held, "RightPole")[:3, 3], "l": read_transform(held, "LeftPole")[:3, 3]}
        poses = weapon / "hold"
        self.fingers = {
            name: read_quaternions(poses / f"rifle_{name}_pose.tres")
            for name in ("grip", "trigger", "support", "open", "magazine", "charge")
        }
        self.fit = "the scene's own"
        for path in re.findall(r'path="res://([^"]*fit[^"]*\.tres)"', held.read_text(encoding="utf-8")):
            fit = read_fit(GAME / path)
            if fit["body"] == body_file:
                self.right, self.left, self.on_magazine = fit["right"], fit["left"], fit["on_magazine"]
                self.on_handle = fit.get("on_handle", self.on_handle)
                self.fingers, self.fit = {**self.fingers, **fit["fingers"]}, path
        self.spine = ["spine_01", "spine_02", "spine_03"]
        torso = re.search(r"torso_bones: Array\[StringName\] = \[(.*?)\]", script, re.S).group(1)
        self.torso = re.findall(r'&"(\w+)"', torso)
        self.clavicle = re.search(r'left_clavicle: StringName = &"(\w+)"', script).group(1)
        # The torso's skin is its own class since kit #1336 (`hold/torso_skin.gd`): its region is read there.
        skin_script = (weapon / "hold/torso_skin.gd").read_text(encoding="utf-8")
        region = re.search(r"_SKIN_REGION := AABB\((.*)\)", script + skin_script).group(1)
        region = [float(v) for v in re.findall(r"-?\d+\.?\d*", region.replace("Vector3", ""))]
        self.region = (np.array(region[:3]), np.array(region[:3]) + np.array(region[3:]))
        self.skin = {}  # the torso's skin the butt meets, by bone, each point in the bone's rest space

    def measure_chest(self, rig, mesh):
        """Keeps a thinned set of the torso's skin for the butt to meet, as `TwoHandHold._measure_chest` does:
        points over every triangle a corner of which follows one of `torso_bones` most, a `skin_spacing` apart,
        the frontmost in each cell of that size in front of the chest bone, each in its bone's rest space.
        `mesh` is the body's nearest level, on its rest pose. Returns how many points it kept."""
        spacing = max(self.n["skin_spacing"], 0.001)
        groups = [g.name for g in mesh.vertex_groups]
        to_godot = np.linalg.inv(C) @ np.array(mesh.matrix_world)
        rests, mains = [], []
        for v in mesh.data.vertices:
            rests.append((to_godot @ np.append(np.array(v.co), 1.0))[:3])
            mains.append(groups[max(v.groups, key=lambda g: g.weight).group] if v.groups else "")
        origin = rig.rest_world[self.spine[-1]][:3, 3]
        low, high = self.region
        cells = {}
        mesh.data.calc_loop_triangles()
        for triangle in mesh.data.loop_triangles:
            at = triangle.vertices[:]
            if not any(mains[i] in self.torso for i in at):
                continue
            a, b, c = (rests[i] for i in at)
            longest = max(np.linalg.norm(a - b), np.linalg.norm(b - c), np.linalg.norm(c - a))
            steps = min(max(math.ceil(longest / spacing), 1), 12)
            for u in range(steps + 1):
                for v in range(steps + 1 - u):
                    w = steps - u - v
                    bone = mains[at[0] if u >= v and u >= w else (at[1] if v >= w else at[2])]
                    if bone not in self.torso:
                        continue
                    rest = (a * u + b * v + c * w) / steps
                    ahead = rest - origin
                    if ahead[2] <= 0.0 or (ahead < low).any() or (ahead > high).any():
                        continue
                    cell = tuple(np.floor(ahead / spacing).astype(int))
                    if cell in cells and cells[cell][2] >= ahead[2]:
                        continue
                    cells[cell] = (bone, (np.linalg.inv(rig.rest_world[bone]) @ np.append(rest, 1.0))[:3], ahead[2])
        self.skin = {}
        for bone, point, _ahead in cells.values():
            self.skin.setdefault(bone, []).append(point)
        self.skin = {bone: np.array(points) for bone, points in self.skin.items()}
        return sum(len(points) for points in self.skin.values())

    def turned(self, pitch, yaw):
        """A turn of the gun from straight ahead: the muzzle `pitch` degrees down and `yaw` across."""
        return axis_angle(X, pitch) @ axis_angle(Y, yaw)

    def chest_yaw(self, rig, pose):
        posed = rig.chain(pose, self.spine[-1])[:3, :3]
        ahead = posed @ rig.rest_world[self.spine[-1]][:3, :3].T @ Z
        return math.degrees(math.atan2(ahead[0], ahead[2]))

    def turn_chest(self, rig, pose):
        """The stance's chest turn: the chest stands at `chest_turn` from the front whatever the pose had."""
        degrees = self.n["chest_turn"] - self.chest_yaw(rig, pose)
        for bone in self.spine:
            rig.turn(pose, bone, axis_angle(Y, degrees / len(self.spine)))

    def straighten(self, rig, pose, raised):
        """The stance's `_straighten_chest`: a chest that leans more than `aim_lean_limit` is raised toward it
        as the gun comes up, split evenly over the spine bones."""
        if raised <= 0.0:
            return
        top = self.spine[-1]
        up = rig.chain(pose, top)[:3, :3] @ rig.rest_world[top][:3, :3].T @ Y
        lean = angle_between(up, Y)
        if lean <= self.n["aim_lean_limit"]:
            return
        axis = np.cross(up, Y)
        if axis @ axis < 1e-10:
            return
        for bone in self.spine:
            rig.turn(pose, bone, axis_angle(axis, (lean - self.n["aim_lean_limit"]) * raised / len(self.spine)))

    def chest_frame(self, turned):
        """The frame the pockets are given in (`_chest_frame`): the chest's turn about the up axis, and
        `pocket_lean` of the rest of its turn from its rest."""
        q = Matrix(turned.tolist()).to_quaternion()
        about_up = Quaternion((q.w, 0.0, q.y, 0.0))
        about_up = about_up.normalized() if about_up.magnitude > 1e-4 else Quaternion()
        lean = q @ about_up.inverted()
        return np.array((Quaternion().slerp(lean, self.n["pocket_lean"]) @ about_up).to_matrix())

    def push_way(self, basis):
        """The way the butt goes from the pocket to the skin: along the barrel, its fall taken out by
        `push_level` while the muzzle is down (`TwoHandHold._push_way`, kit #1346)."""
        barrel = basis[:, 2] / np.linalg.norm(basis[:, 2])
        level = np.array((barrel[0], 0.0, barrel[2]))
        if self.n["push_level"] <= 0.0 or barrel[1] >= 0.0 or level @ level < 1e-6:
            return barrel
        level /= np.linalg.norm(level)
        angle = np.arccos(np.clip(barrel @ level, -1.0, 1.0))
        if angle < 1e-6:
            return barrel
        t = self.n["push_level"]
        return (np.sin((1.0 - t) * angle) * barrel + np.sin(t * angle) * level) / np.sin(angle)

    def butt_push(self, rig, pose, gun, way=None):
        """How far the gun goes from the pocket (`gun`: the pivot there), along its barrel or along `way`, so no
        point of the torso's skin is inside its stock (`TorsoSkin.push`)."""
        n = self.n
        margin = n["butt_margin"]
        wide, high = n["butt_pad"][0] * 0.5 + margin, n["butt_pad"][1] * 0.5 + margin
        push = 0.0
        to_gun = np.linalg.inv(gun)
        if way is not None:
            local = gun[:3, :3].T @ way
            if abs(local[1]) > 1e-4:
                return self.push_along(rig, pose, to_gun, wide, high, np.array((local[1], max(local[2], n["_LEAST_ALONG"]))))
        for bone, points in self.skin.items():
            at = ((to_gun @ rig.chain(pose, bone)) @ np.c_[points, np.ones(len(points))].T).T[:, :3]
            inside = (at[:, 2] > -margin) & (at[:, 2] < n["butt_depth"])
            inside &= (np.abs(at[:, 0]) < wide) & (np.abs(at[:, 1]) < high)
            if inside.any():
                push = max(push, float(at[inside, 2].max()) + margin)
        return push

    def push_along(self, rig, pose, to_gun, wide, high, move):
        """The push along `move` (up the gun, along its barrel): each point near the stock forbids the moves
        that leave it inside, one open run, and the push is the least move forward no run forbids
        (`TorsoSkin._push_along`)."""
        n = self.n
        move = move / np.linalg.norm(move)
        margin, depth, most = n["butt_margin"], n["butt_depth"], n["_PUSH_MOST"]
        rise = abs(move[0]) * most
        runs = []
        for bone, points in self.skin.items():
            at = ((to_gun @ rig.chain(pose, bone)) @ np.c_[points, np.ones(len(points))].T).T[:, :3]
            near = (at[:, 2] >= -margin) & (at[:, 2] <= depth + most) & (np.abs(at[:, 1]) <= high + rise)
            near &= np.abs(at[:, 0]) < wide
            for x, y, z in at[near].tolist():
                one, other = (y - high) / move[0], (y + high) / move[0]
                low = max((z - depth) / move[1], min(one, other))
                top = min((z + margin) / move[1], max(one, other))
                if top > max(low, 0.0):
                    runs.append((low, top))
        pushed = 0.0
        for low, top in sorted(runs):
            if low >= pushed:
                break
            pushed = max(pushed, top)
        return pushed

    def reach_shoulder(self, rig, pose, pivot):
        """Turns the left collarbone (by `reach_turn` at most) so the left shoulder comes toward the hand guard,
        as far as the arm needs to reach its place at `arm_stretch` (`_reach_shoulder`)."""
        n = self.n
        if n["reach_turn"] <= 0.0:
            return
        length = np.linalg.norm(rig.rest["lowerarm_l"][:3, 3]) + np.linalg.norm(rig.rest["hand_l"][:3, 3])
        length *= n["arm_stretch"]
        target = (pivot @ self.rifle @ np.append(self.left[:3, 3], 1.0))[:3]
        assert rig.parent["upperarm_l"] == self.clavicle, "a bone lies between the collarbone and the upper arm"
        root = rig.chain(pose, self.clavicle)
        from_ = root[:3, :3] @ rig.rest["upperarm_l"][:3, 3]
        if np.linalg.norm(root[:3, 3] + from_ - target) <= length:
            return
        toward = target - root[:3, 3]
        axis = np.cross(from_, toward)
        if axis @ axis < 1e-10:
            return
        whole_ = math.radians(angle_between(from_, toward))
        both = from_ @ from_ + toward @ toward
        twice = 2.0 * np.linalg.norm(from_) * np.linalg.norm(toward)
        high = min(math.radians(n["reach_turn"]), whole_)
        share = (both - length * length) / max(twice, 1e-9)
        if share < 1.0:
            high = min(high, max(whole_ - math.acos(max(share, -1.0)), 0.0))
        rig.turn(pose, self.clavicle, axis_angle(axis, math.degrees(high)))

    def charge_way(self, progress):
        """`ChargePull.to_magazine`: how far along the hold's own way to the magazine the hand counts as on the
        pull's way, or below 0 before it."""
        c, n = self.charge, self.n
        if progress < c["leave"][0]:
            return -1.0
        if progress < c["release"][1]:
            return 1.0
        home, rest = n["reload_return"]
        middle = c["release"][1] + (home - c["release"][1]) * c["home_beside"]
        if progress < middle:
            t = smoothstep(c["release"][1], middle, progress)
            return n["_WAY_ON"] + (n["_WAY_BESIDE"] - n["_WAY_ON"]) * t
        if progress < home:
            return n["_WAY_BESIDE"] + (n["_WAY_DOWN"] - n["_WAY_BESIDE"]) * smoothstep(middle, home, progress)
        return n["_WAY_DOWN"] * (1.0 - smoothstep(home, rest, progress))

    def charge_place(self, progress, beside, below):
        """`ChargePull.hand_place`: the left hand bone's place on the pull's way."""
        c, home = self.charge, self.n["reload_return"][0]
        handle = self.on_handle
        pulled = moved(handle, c["travel"] * smoothstep(c["pull"][0], c["pull"][1], progress))
        near = moved(handle, c["approach"])
        if progress < c["reach"][0]:
            return between(self.on_magazine, beside, smoothstep(c["leave"][0], c["leave"][1], progress))
        if progress < c["grip"][0]:
            return between(beside, near, smoothstep(c["reach"][0], c["reach"][1], progress))
        if progress < c["pull"][0]:
            return between(near, handle, smoothstep(c["grip"][0], c["grip"][1], progress))
        if progress < c["release"][0]:
            return pulled
        off = moved(pulled, c["let_go"])
        if progress < c["release"][1]:
            return between(pulled, off, smoothstep(c["release"][0], c["release"][1], progress))
        middle = c["release"][1] + (home - c["release"][1]) * c["home_beside"]
        if progress < middle:
            return between(off, beside, smoothstep(c["release"][1], middle, progress))
        return between(beside, below, smoothstep(middle, home, progress))

    def to_magazine(self, progress):
        if progress < 0.0:
            return 0.0
        way = self.charge_way(progress)
        if way >= 0.0:
            return way
        leave, back = self.n["reload_leave"], self.n["reload_return"]
        return smoothstep(leave[0], leave[1], progress) * (1.0 - smoothstep(back[0], back[1], progress))

    def left_place(self, state, pivot, chest):
        """The left hand bone's place in the rifle's scene space, and how far the magazine is out of the gun
        there (`_place_reload`)."""
        progress = state.get("reload", -1.0)
        if progress < 0.0:
            return self.left, np.zeros(3), True
        n = self.n
        to_magazine = self.to_magazine(progress)
        away = smoothstep(n["reload_out"][0], n["reload_out"][1], progress)
        away *= 1.0 - smoothstep(n["reload_in"][0], n["reload_in"][1], progress)
        below = moved(self.left, n["reload_clearance"])
        beside = moved(self.on_magazine, n["magazine_approach"])
        hand = moved(self.left, -Y * n["_LET_GO_DROP"] * smoothstep(0.0, n["_WAY_OPEN"] * 0.5, to_magazine))
        hand = between(hand, below, smoothstep(n["_WAY_OPEN"] * 0.5, n["_WAY_DOWN"], to_magazine))
        hand = between(hand, beside, smoothstep(n["_WAY_DOWN"], n["_WAY_BESIDE"], to_magazine))
        hand = between(hand, self.on_magazine, smoothstep(n["_WAY_BESIDE"], n["_WAY_ON"], to_magazine))
        if self.charge["leave"][0] <= progress < n["reload_return"][0]:
            hand = self.charge_place(progress, beside, below)
        out = -Y * n["magazine_well"] * min(away / n["_WELL_SHARE"], 1.0)
        to_belt = smoothstep(0.0, 1.0, (away - n["_WELL_SHARE"]) / (1.0 - n["_WELL_SHARE"]))
        gun = pivot @ self.rifle
        belt = (np.linalg.inv(gun) @ np.append(chest + n["reload_belt"], 1.0))[:3]
        out = out + (belt - (hand[:3, 3] + out)) * to_belt
        return moved(hand, out), out, away < 0.9

    def apply(self, rig, pose, state):
        """Runs the hold on a pose, as the game does after the clip: the chest turn, the rifle's place, both
        arms, the fingers. Returns what it worked out (`gun`: the rifle scene's place in the character's
        space; `short`: how far each wrist stopped short; `magazine`: the magazine's move and whether it
        shows)."""
        n = self.n
        self.turn_chest(rig, pose)
        raised = state.get("raised", 0.0)
        self.straighten(rig, pose, raised)
        kick = state.get("kick", 0.0)
        pitch = min(max(state.get("pitch", 0.0), -n["pitch_limit"]), n["pitch_limit"])
        chest_at = rig.chain(pose, self.spine[-1])
        chest = chest_at[:3, 3]
        frame = self.chest_frame(chest_at[:3, :3] @ rig.rest_world[self.spine[-1]][:3, :3].T)
        low = self.turned(n["low_pitch"], n["low_yaw"])
        aim = self.turned(-pitch - n["kick_degrees"] * kick, 0.0)
        basis = slerp(low, aim, raised)
        pocket = chest + frame @ (n["low_pocket"] + (n["aim_pocket"] - n["low_pocket"]) * raised)
        # The left shoulder comes toward the hand guard, then the butt comes to the skin as the shoulder left
        # it, until neither moves: the game goes through the two again whenever the push moved more than
        # `_PUSH_STEP`, from the push of the frame before, and so settles within that of this.
        clip_clavicle = pose["local"][self.clavicle]
        push, back = 0.0, n["kick_distance"] * kick
        way = self.push_way(basis)
        for _ in range(PUSH_PASSES):
            pose["local"][self.clavicle] = clip_clavicle
            self.reach_shoulder(rig, pose, place_of(basis, pocket + way * push - basis[:, 2] * back))
            before, push = push, self.butt_push(rig, pose, place_of(basis, pocket), way)
            if abs(push - before) <= PUSH_SETTLED:
                break
        pivot = place_of(basis, pocket + way * push - basis[:, 2] * back)
        pivot[:3, 3] -= basis[:, 2] * self.pull(rig, pose, pivot)
        left, magazine, shown = self.left_place(state, pivot, chest)
        gun = pivot @ self.rifle
        short = {
            "r": reach(rig, pose, "r", gun @ self.right, self.poles["r"]),
            "l": reach(rig, pose, "l", gun @ left, self.poles["l"]),
        }
        self.close(pose, state)
        held = {"gun": gun, "short": short, "magazine": magazine, "magazine_shown": shown, "pivot": pivot}
        held["push"] = push
        return held

    def pull(self, rig, pose, pivot):
        """How far the gun comes back along its barrel for the left arm to reach the hand guard (`_pull`)."""
        n = self.n
        length = np.linalg.norm(rig.rest["lowerarm_l"][:3, 3]) + np.linalg.norm(rig.rest["hand_l"][:3, 3])
        length *= n["arm_stretch"]
        shoulder = rig.chain(pose, "upperarm_l")[:3, 3]
        held_at = (pivot @ self.rifle @ np.append(self.left[:3, 3], 1.0))[:3]
        off = held_at - shoulder
        if np.linalg.norm(off) <= length:
            return 0.0
        back = -pivot[:3, 2]
        along = off @ back
        beside = off @ off - along * along
        reach_ = math.sqrt(max(length * length - beside, 0.0))
        return min(max(-along - reach_, 0.0), n["pull_limit"])

    def close(self, pose, state):
        """The fingers, as the two `HandPoseModifier`s leave them (`refresh`)."""
        n = self.n
        reload = state.get("reload", -1.0)
        on_trigger = state.get("raised", 0.0) if reload < 0.0 else 0.0
        for bone, rotation in self.fingers["grip"].items():
            if bone in self.fingers["trigger"] and on_trigger > 0.0:
                rotation = slerp(rotation, self.fingers["trigger"][bone], on_trigger)
            pose["local"][bone] = rotation
        to_magazine = self.to_magazine(reload)
        # The thumb goes to its place behind the magazine while the hand comes down off the hand guard.
        second = smoothstep(n["_WAY_THUMB"][0], n["_WAY_THUMB"][1], to_magazine)
        opened = smoothstep(0.0, n["_WAY_OPEN"], to_magazine) * (1.0 - smoothstep(n["_WAY_ON"], 1.0, to_magazine))
        together = to_magazine > n["_WAY_DOWN"]  # on the magazine the four fingers close as one
        # The charging handle's pull (`ChargePull.set_fingers`): off the magazine the fingers open as one, then
        # close on the latch (the `third` pose) and open again.
        c, hooked = self.charge, 0.0
        if c["leave"][0] <= reload < c["release"][1]:
            second, together = 1.0, True
            opened = smoothstep(c["leave"][0], c["leave"][1], reload)
            hooked = smoothstep(c["grip"][0], c["grip"][1], reload)
            hooked *= 1.0 - smoothstep(c["release"][0], c["release"][1], reload)
        for bone, rotation in self.fingers["support"].items():
            if second > 0.0 and bone in self.fingers["magazine"]:
                rotation = slerp(rotation, self.fingers["magazine"][bone], second)
            if opened > 0.0 and bone in self.fingers["open"]:
                # Off the hand guard the knuckles open over the first half, the rest of each finger over the
                # second (`HandPoseModifier.open_first`).
                share = opened
                if not together:
                    share = min(opened / 0.5, 1.0) if "_01_" in bone else max((opened - 0.5) / 0.5, 0.0)
                rotation = slerp(rotation, self.fingers["open"][bone], share)
            if hooked > 0.0 and bone in self.fingers["charge"]:
                rotation = slerp(rotation, self.fingers["charge"][bone], hooked)
            pose["local"][bone] = rotation


# ---- shaping the body -----------------------------------------------------------------------------------------------


def shape(rig, base, hold, state, body):
    """The pose for a frame. The legs and the pelvis are the base pose's. The trunk stands upright from the
    pelvis and is leant (`lean` forward, `side` to the right, degrees over the three spine bones; `breath` back
    over the upper two; `hunch` forward on the chest bone alone) and turned as the hold turns the chest; the collarbones are set from their rest
    (`clavicle_r`, `clavicle_l`: degrees up, forward); the neck and the head are stood upright facing the
    front and turned in the character's space (`neck`, `head`: degrees of pitch down, yaw to the left and roll
    to the right); then the hold is run (the rifle's place, the arms, the fingers). A body with `look` (the
    aim's pitch up, degrees) has the head the game gives an aiming character instead (`level_head`). Returns the
    pose and what the hold worked out."""
    pose = copy_pose(base)
    spine = hold.spine
    for i, bone in enumerate(spine):
        share = (i + 1) / len(spine)
        back = body.get("breath", 0.0) * i - (body.get("hunch", 0.0) if i == len(spine) - 1 else 0.0)
        rig.face(
            pose,
            bone,
            axis_angle(X, body.get("lean", 0.0) * share - back) @ axis_angle(Z, body.get("side", 0.0) * share),
        )
    hold.turn_chest(rig, pose)
    for side, sign in (("r", -1.0), ("l", 1.0)):
        up, forward = body.get(f"clavicle_{side}", (0.0, 0.0))
        # Up is a turn about the front-to-back axis (the right shoulder rises with a turn the other way than
        # the left), forward a turn about the up axis.
        pose["local"][f"clavicle_{side}"] = rig.rest[f"clavicle_{side}"][:3, :3]
        rig.turn(pose, f"clavicle_{side}", axis_angle(Y, -sign * forward) @ axis_angle(Z, -sign * up))
    for bone in ("neck_01", "Head"):
        pitch, yaw, roll = body.get("neck" if bone == "neck_01" else "head", (0.0, 0.0, 0.0))
        rig.face(pose, bone, axis_angle(Y, yaw) @ axis_angle(X, pitch) @ axis_angle(Z, roll))
    held = hold.apply(rig, pose, state)
    if "look" in body:
        sight_head(rig, pose, body["look"], held["gun"])
    return pose, held


def head_rule():
    """The aim layer's numbers for the head: the neck's share of the turn and the most it may turn, degrees."""
    script = (GAME / "gameplay/character/aim/aim_layer.gd").read_text(encoding="utf-8")
    found = dict(re.findall(r"^@export\S*(?:\([^\n]*\))? var (head_\w+) := ([\d.]+)$", script, re.M))
    return float(found["head_neck_share"]), float(found["head_max_turn"])


def level_head(rig, pose, pitch):
    """The neck and the head as the game's `AimHeadModifier` sets them while a character aims (kit #1334), which
    runs after the clip and the spine's turn: from where the chest leaves the head (the neck and the head at
    their rest turns on it) to looking along the aim, `pitch` degrees up, with no roll against the world's up;
    the neck takes its share of that turn and the head the rest, about the same axis."""
    share, most = head_rule()
    chest = rig.chain(pose, rig.parent["neck_01"])[:3, :3]
    neck_line = chest @ rig.rest["neck_01"][:3, :3]
    lined = neck_line @ rig.rest["Head"][:3, :3]
    p = math.radians(pitch)
    look = np.array([[1.0, 0.0, 0.0], [0.0, math.cos(p), math.sin(p)], [0.0, -math.sin(p), math.cos(p)]])
    wanted = look @ rig.rest_world["Head"][:3, :3]
    turn = Matrix((wanted @ lined.T).tolist()).to_quaternion()
    if turn.angle > math.radians(most) and turn.angle > 1e-4:
        turn = Quaternion().slerp(turn, math.radians(most) / turn.angle)
    neck_world = np.array(Quaternion().slerp(turn, share).to_matrix()) @ neck_line
    head_world = np.array(turn.to_matrix()) @ lined
    pose["local"]["neck_01"] = chest.T @ neck_world
    pose["local"]["Head"] = neck_world.T @ head_world


def head_rolls(rig, pose):
    """How far the head is rolled on the neck and the neck on the chest, in degrees, read as the game's test
    reads them (`tests/fixtures/head_pose_probe.gd`): the turn from the rest, in the parent's rest frame, as yaw,
    then pitch, then roll."""
    out = []
    for bone in ("Head", "neck_01"):
        above = rig.parent[bone]
        turned = (
            rig.rest_world[above][:3, :3]
            @ rig.chain(pose, above)[:3, :3].T
            @ rig.chain(pose, bone)[:3, :3]
            @ rig.rest_world[bone][:3, :3].T
        )
        out.append(math.degrees(math.atan2(turned[1, 0], turned[1, 1])))
    return out


def sight_rule():
    """The numbers of `AimHeadModifier`'s sight rule, from its script: the steps, and what the eye along the line,
    a nod, a turned face and a cant weigh, and the most the head turns from the level look, degrees."""
    script = (GAME / "gameplay/character/aim/aim_head_modifier.gd").read_text(encoding="utf-8")
    found = dict(re.findall(r"^(?:@export\S*(?:\([^\n]*\))? var|const) (_?\w+) := ([\d.]+)$", script, re.M))
    return {name.lower().lstrip("_"): float(found[name]) for name in found if "sight" in name.lower()}


def sight_head(rig, pose, pitch, gun):
    """The neck and the head as the game's `AimHeadModifier` sets them for a weapon aimed down its sights
    (`WeaponDef.AimHead.SIGHT`, the rifle's): from the level look along the aim (`level_head`), turned on so
    the right eye comes toward its place on the weapon (`AimEye`) for what a nod, a turned face and a cant
    cost. One turn, shared between the neck and the head as the level look's is; the same steps of least
    squares as the game's, with its numbers."""
    share, most = head_rule()
    rule = sight_rule()
    chest_at = rig.chain(pose, rig.parent["neck_01"])
    chest = chest_at[:3, :3]
    neck_line = chest @ rig.rest["neck_01"][:3, :3]
    neck_origin = (chest_at @ rig.rest["neck_01"])[:3, 3]
    lined = neck_line @ rig.rest["Head"][:3, :3]
    head_from_neck = rig.rest["Head"][:3, 3]
    p = math.radians(pitch)
    look = np.array([[1.0, 0.0, 0.0], [0.0, math.cos(p), math.sin(p)], [0.0, -math.sin(p), math.cos(p)]])
    rest_head = rig.rest_world["Head"][:3, :3]
    level = Matrix((look @ rest_head @ lined.T).tolist()).to_quaternion()
    eye_local = rest_head.T @ rig.eye
    place = (gun @ np.append(SIGHT_EYE, 1.0))[:3]
    line = gun[:3, :3] @ (SIGHT_AHEAD / np.linalg.norm(SIGHT_AHEAD))
    upward = Y - (Y @ line) * line
    upward /= np.linalg.norm(upward)
    side = np.cross(upward, line)

    def posed(r):
        angle = float(np.linalg.norm(r))
        extra = Quaternion(Vector(r / angle), angle) if angle > 1e-9 else Quaternion()
        turn = extra @ level
        if turn.angle > math.radians(most) and turn.angle > 1e-4:
            turn = Quaternion().slerp(turn, math.radians(most) / turn.angle)
        neck_world = np.array(Quaternion().slerp(turn, share).to_matrix()) @ neck_line
        head_world = np.array(turn.to_matrix()) @ lined
        return neck_world, head_world

    def residual(r):
        neck_world, head_world = posed(r)
        eye = neck_origin + neck_world @ head_from_neck + head_world @ eye_local
        off = eye - place
        along = off @ line
        turned = [(r @ side) * rule["sight_nod"], (r @ upward) * rule["sight_face"], (r @ line) * rule["sight_cant"]]
        return np.concatenate([off - along * line, [along * rule["sight_along"]], turned])

    r = np.zeros(3)
    for _ in range(int(rule["sight_passes"])):
        now = residual(r)
        jac = np.empty((len(now), 3))
        for i in range(3):
            step = r.copy()
            step[i] += rule["sight_step"]
            jac[:, i] = (residual(step) - now) / rule["sight_step"]
        r = r + np.linalg.solve(jac.T @ jac + 1e-9 * np.eye(3), -jac.T @ now)
        size = float(np.linalg.norm(r))
        if size > math.radians(rule["sight_tilt"]):
            r *= math.radians(rule["sight_tilt"]) / size
    neck_world, head_world = posed(r)
    pose["local"]["neck_01"] = chest.T @ neck_world
    pose["local"]["Head"] = neck_world.T @ head_world


def eye_of(rig, pose):
    head = rig.chain(pose, "Head")
    rest = rig.rest_world["Head"]
    return head[:3, 3] + head[:3, :3] @ rest[:3, :3].T @ rig.eye


def face_of(rig, pose):
    """The way the face looks, and the head's up."""
    head = rig.chain(pose, "Head")[:3, :3] @ rig.rest_world["Head"][:3, :3].T
    return head @ Z, head @ Y


def stock_depth(rig, pose, gun, clear):
    """How deep the head's and the neck's skin of a body is in the stock, in metres, with `clear` added: the
    stock is a box of its comb and butt in the rifle's space, open upward and to the left, where a cheek comes
    off it."""
    skin = []
    for bone, points in SKIN_POINTS[rig.name].items():
        at = rig.chain(pose, bone)
        skin.append(at[:3, 3] + points @ (at[:3, :3] @ rig.rest_world[bone][:3, :3].T).T)
    skin = np.concatenate(skin)
    skin = (np.linalg.inv(gun) @ np.c_[skin, np.ones(len(skin))].T).T[:, :3]
    top = np.where(skin[:, 0] < COMB_FRONT, RECEIVER_TOP, STOCK_TOP)
    inside = np.minimum(top - skin[:, 1], STOCK_SIDE - skin[:, 2])
    inside = np.where((skin[:, 0] > STOCK_FRONT) & (skin[:, 2] > -STOCK_SIDE), inside, 0.0)
    return max(float(inside.max()) + clear, 0.0)


def solve_aim(rig, base, hold, state, body, others=()):
    """Finds the trunk's lean for an aim. The head is not the clip's while a character aims: the game holds it
    level and along the aim (`level_head`), so the search only leans the trunk, forward and to the side, until
    that head and its neck are clear of the stock and neither is rolled far on the bone under it: a damped
    least-squares search over two angles, each held near nothing by its cost. `others` are the other bodies that
    play the clip, as (rig, hold): the same clip on each, under its own hold, keeps its head off the stock too."""
    names = ["lean", "side"]
    soft = np.array([10.0, 5.0])  # degrees each is cheap up to
    # What a body gives and no more (`AIM_LIMITS`): past it an angle costs steeply.
    low = np.array([AIM_LIMITS[n][0] for n in names])
    high = np.array([AIM_LIMITS[n][1] for n in names])
    centre = np.zeros(2)
    x = centre.copy()

    def build(v):
        shaped = dict(body, lean=body.get("lean", 0.0) + v[0], side=v[1], look=state.get("pitch", 0.0))
        return shape(rig, base, hold, state, shaped) + (shaped,)

    def residual(v):
        pose, held, _ = build(v)
        clear = body.get("clear", HEAD_CLEAR)
        deepest = [stock_depth(rig, pose, held["gun"], clear)]
        for other, others_hold in others:
            # The clip on the other body: the same turns in each bone's parent, then that body's hold.
            posed = whole(other, {"local": dict(pose["local"]), "pelvis": pose["pelvis"]})
            deepest.append(stock_depth(other, posed, others_hold.apply(other, posed, state)["gun"], clear))
        return np.concatenate(
            [
                np.array(deepest) * 1500.0,
                [eye_off(rig, pose, held)[0] * 0.05],  # the trunk leans the eye toward the line too
                (v - centre) / soft,
                np.maximum(v - centre - high, 0.0) * 4.0,
                np.maximum(low - (v - centre), 0.0) * 4.0,
            ]
        )

    damp = 1e-2
    cost = float(residual(x) @ residual(x))
    for _ in range(60):
        r = residual(x)
        jac = np.empty((len(r), len(x)))
        for i in range(len(x)):
            step = x.copy()
            step[i] += 0.05
            jac[:, i] = (residual(step) - r) / 0.05
        move = np.linalg.solve(jac.T @ jac + damp * np.eye(len(x)), -jac.T @ r)
        tried = float(residual(x + move) @ residual(x + move))
        if tried < cost:
            x, cost, damp = x + move, tried, max(damp * 0.5, 1e-5)
            if np.abs(move).max() < 1e-3:
                break
        else:
            damp *= 4.0
    pose, held, shaped = build(x)
    return shaped, dict(zip(names, np.round(x, 2).tolist()))


def eye_off(rig, pose, held):
    """How far the right eye is off the sight line, and how far behind the rear sight's place it is, in mm."""
    eye = (np.linalg.inv(held["gun"]) @ np.append(eye_of(rig, pose), 1.0))[:3]
    off = eye - SIGHT_EYE
    line = SIGHT_AHEAD / np.linalg.norm(SIGHT_AHEAD)
    along = off @ line
    return float(np.linalg.norm(off - along * line) * 1000.0), float(-along * 1000.0)


# ---- the clips ------------------------------------------------------------------------------------------------------


def breath(frame, frames):
    """A breath over a loop: in over 40 % of it, out over the rest, 0 at both ends."""
    t = (frame % frames) / frames
    return 0.5 - 0.5 * math.cos(math.pi * (t / 0.4 if t < 0.4 else 1.0 + (t - 0.4) / 0.6))


def with_breath(body, amount):
    out = dict(body, breath=amount)
    for side in ("r", "l"):
        up, forward = body.get(f"clavicle_{side}", (0.0, 0.0))
        out[f"clavicle_{side}"] = (up + amount * 1.2, forward)
    # The head is stood in the character's space, so it stays where it looks while the chest rises under it.
    pitch, yaw, roll = body.get("head", (0.0, 0.0, 0.0))
    out["head"] = (pitch, yaw, roll)
    return out


def make_clips(rig, base, hold, only, others=()):
    """Every clip as its frames: `{name: {"frames": [pose], "held": [what the hold worked out], "states": [...],
    "loop": bool, "solved": {...}}}`."""
    clips = {}
    idle_state = {"raised": 0.0}
    idle_body = {
        "lean": IDLE_LEAN,
        "hunch": IDLE_HUNCH,
        "clavicle_r": IDLE_CLAVICLE_R,
        "clavicle_l": IDLE_CLAVICLE_L,
        "neck": (-IDLE_LOOK[0] * 0.5, IDLE_LOOK[1] * 0.5, 0.0),
        "head": (-IDLE_LOOK[0], IDLE_LOOK[1], 0.0),
    }
    aim_bodies, solved = {}, {}
    for name, pitch in (("Rifle_Aim_Neutral", 0.0), ("Rifle_Aim_Up", AIM_PITCH), ("Rifle_Aim_Down", -AIM_PITCH)):
        start = {"clavicle_r": AIM_CLAVICLE_R, "clavicle_l": AIM_CLAVICLE_L, "lean": AIM_LEAN - pitch * 0.35, "hunch": AIM_HUNCH}
        if pitch < 0.0:
            # Looking down the trunk folds over the rifle: more of both keeps the right forearm off the ribs.
            start.update(lean=AIM_DOWN_LEAN, hunch=AIM_DOWN_HUNCH, clear=AIM_DOWN_CLEAR, clavicle_r=AIM_DOWN_CLAVICLE_R)
        aim_bodies[name], solved[name] = solve_aim(rig, base, hold, {"raised": 1.0, "pitch": pitch}, start, others)

    def add(name, frames, body_at, state_at, loop):
        if only and name not in only:
            return
        poses, helds, states = [], [], []
        for f in range(frames + 1):
            state = state_at(f)
            pose, held = shape(rig, base, hold, state, body_at(f))
            poses.append(pose)
            helds.append(held)
            states.append(state)
        clips[name] = {"frames": poses, "held": helds, "states": states, "loop": loop, "solved": solved.get(name)}

    add(
        "Rifle_Idle",
        IDLE_FRAMES,
        lambda f: with_breath(idle_body, IDLE_BREATH * breath(f, IDLE_FRAMES)),
        lambda f: idle_state,
        True,
    )
    for name, pitch in (("Rifle_Aim_Neutral", 0.0), ("Rifle_Aim_Up", AIM_PITCH), ("Rifle_Aim_Down", -AIM_PITCH)):
        add(
            name,
            AIM_FRAMES,
            lambda f, name=name: with_breath(aim_bodies[name], AIM_BREATH * breath(f, AIM_FRAMES)),
            lambda f, pitch=pitch: {"raised": 1.0, "pitch": pitch},
            True,
        )

    aim_body = aim_bodies["Rifle_Aim_Neutral"]
    kick_frames = hold.n["kick_recover_time"] * SHOOT_SPEED * FPS

    def shot_body(f):
        share = float(spline(SHOT_KEYS, f))
        out = dict(aim_body, breath=SHOT_SPINE * share)
        up, forward = aim_body["clavicle_r"]
        out["clavicle_r"] = (up + SHOT_CLAVICLE[0] * share, forward - SHOT_CLAVICLE[1] * share)
        return out

    add(
        "Rifle_Shoot",
        SHOOT_FRAMES,
        shot_body,
        # The game's kick is whole on the tick of the shot and gone `kick_recover_time` later; frame 0 is the
        # aim pose the clip starts from, so the kick is whole on frame 1.
        lambda f: {"raised": 1.0, "pitch": 0.0, "kick": 0.0 if f == 0 else max(1.0 - (f - 1) / kick_frames, 0.0)},
        False,
    )

    def reload_body(f):
        share = f / RELOAD_FRAMES
        down, left, lean, roll, drop = spline([(k[0], k[1:]) for k in RELOAD_KEYS], share)
        jolt = sum(amount * max(1.0 - abs(share - at) * RELOAD_FRAMES / 2.0, 0.0) for at, amount in RELOAD_JOLTS)
        out = dict(idle_body, lean=IDLE_LEAN + lean, side=-roll, breath=jolt)
        up, forward = idle_body["clavicle_l"]
        out["clavicle_l"] = (up - drop, forward)
        pitch, yaw, roll_ = idle_body["head"]
        neck = idle_body["neck"]
        out["neck"] = (neck[0] + down * 0.45, neck[1] + left * 0.5, 0.0)
        out["head"] = (pitch + down, yaw + left, roll_)
        return out

    add(
        "Rifle_Reload",
        RELOAD_FRAMES,
        reload_body,
        lambda f: {"raised": 0.0, "reload": -1.0 if f in (0, RELOAD_FRAMES) else f / RELOAD_FRAMES},
        False,
    )
    return clips


# ---- Blender: import, key, export, measure --------------------------------------------------------------------------


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="BLENDER")
    new = [o for o in bpy.data.objects if o not in before]
    return next((o for o in new if o.type == "ARMATURE"), None), new


def library_pose(path, clip):
    """A library clip's steadiest frame as each bone's rotation in its parent and the pelvis's place there, with
    the frame's time in seconds; the library is removed again. The steadiest frame is the one whose pelvis is
    nearest its mean place over the clip: the pose the game holds the legs on under a standing aim
    (`AimStance.steady_time`, which reads the clip the same way)."""
    arm, objects = import_glb(path)
    action = bpy.data.actions.get(clip) or bpy.data.actions[clip + "_Loop"]
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    scene = bpy.context.scene
    first, last = round(action.frame_range[0]), round(action.frame_range[1])
    places = []
    for f in range(first, last):  # the last frame of a loop is its first again
        scene.frame_set(f)
        places.append(np.array(arm.pose.bones["pelvis"].matrix.translation))
    places = np.array(places)
    steady = first + int(np.linalg.norm(places - places.mean(axis=0), axis=1).argmin())
    scene.frame_set(steady)
    bpy.context.view_layer.update()
    local, pelvis = {}, None
    for pb in arm.pose.bones:
        m = np.array((pb.parent.matrix.inverted() @ pb.matrix) if pb.parent else pb.matrix)
        if pb.parent is None:
            m = np.linalg.inv(C) @ m
        local[pb.name] = np.array(Matrix(m[:3, :3].tolist()).to_quaternion().to_matrix())
        if pb.name == "pelvis":
            pelvis = m[:3, 3].copy()
    for obj in objects:
        bpy.data.objects.remove(obj)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    return {"local": local, "pelvis": pelvis}, (steady - first) / FPS


def set_pose(arm, rig, pose):
    """Puts a pose on an armature (no keys), the twist bones turned for it."""
    pose = whole(rig, pose)
    twist(rig, pose)
    for pb in arm.pose.bones:
        n = pb.name
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Matrix((rig.rest[n][:3, :3].T @ pose["local"][n]).tolist()).to_quaternion()
        if n == "pelvis":
            pb.location = tuple(rig.rest[n][:3, :3].T @ (pose["pelvis"] - rig.rest[n][:3, 3]))
    bpy.context.view_layer.update()


def key_clip(arm, rig, name, frames):
    """Key a clip on the armature: the rotation of every bone a clip may key (`keyed`) on every frame, and the
    pelvis's place."""
    action = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = action
    last = {}
    for f, pose in enumerate(frames):
        for pb in arm.pose.bones:
            n = pb.name
            if not keyed(rig, n):
                continue
            q = Matrix((rig.rest[n][:3, :3].T @ pose["local"][n]).tolist()).to_quaternion()
            if n in last and q.dot(last[n]) < 0:
                q.negate()
            last[n] = q.copy()
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n == "pelvis":
                pb.location = tuple(rig.rest[n][:3, :3].T @ (pose["pelvis"] - rig.rest[n][:3, 3]))
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


def export(arm, path):
    """The armature and its clips as a glb: a one-triangle mesh skinned to the root stands in for the model, so
    the file has a skin (Godot makes its `Skeleton3D` from it) and no copy of the mannequin."""
    mesh = bpy.data.meshes.new("RifleClips")
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0, 0.01)], [], [(0, 1, 2)])
    proxy = bpy.data.objects.new("RifleClips", mesh)
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
    bpy.data.objects.remove(proxy)


class Gun:
    """The rifle's near level, to place where the hold has it and to measure skin against."""

    def __init__(self):
        _, self.objects = import_glb(GAME / "assets/weapons/rifle/rifle.glb")
        self.root = next(o for o in self.objects if o.name.startswith("Rifle") and o.type == "MESH")
        self.magazine = next(o for o in self.objects if o.name.startswith("Magazine"))
        self.magazine_rest = self.magazine.matrix_local.copy()
        mesh = self.root.data
        mesh.calc_loop_triangles()
        to_godot = np.linalg.inv(C)[:3, :3]
        verts = [(to_godot @ np.array(v.co)).tolist() for v in mesh.vertices]
        self.tree = BVHTree.FromPolygons(verts, [t.vertices[:] for t in mesh.loop_triangles])

    def place(self, held):
        self.root.matrix_world = Matrix((C @ held["gun"] @ np.linalg.inv(C)).tolist())
        move = C[:3, :3] @ held["magazine"]
        self.magazine.matrix_local = Matrix.Translation(move.tolist()) @ self.magazine_rest
        self.magazine.hide_render = not held["magazine_shown"]
        bpy.context.view_layer.update()

    def depth(self, points, held):
        """How deep the deepest of `points` (the character's space) is inside the rifle's main mesh, in metres:
        a point is inside when a ray every way along the rifle's axes meets it."""
        local = (np.linalg.inv(held["gun"]) @ np.c_[points, np.ones(len(points))].T).T[:, :3]
        low, high = np.array([-0.51, -0.07, -0.06]), np.array([0.31, 0.25, 0.06])
        deepest = 0.0
        for point in local[((local > low) & (local < high)).all(axis=1)].tolist():
            if all(self.tree.ray_cast(point, way)[0] is not None for way in limb_overlap.RAYS):
                deepest = max(deepest, self.tree.find_nearest(point)[3])
        return deepest


def part_points(body, part):
    """A body part's skinned vertices in the character's space."""
    coords = body.skinned()[body.parts[part]["verts"]]
    return (np.linalg.inv(C)[:3, :3] @ coords.T).T


def hold_alone(base, bodies, rigs, holds):
    """What the hold does to a body with no rifle clip under it, as the game showed it before these clips: how
    deep a limb is in another with the hold run on the idle pose, by body, at the low ready and at
    the shoulder with the view level, up and down. The hold brings the grip close to the chest (kit #1177), so
    its own depth is the floor a clip is held to."""
    out = {}
    states = {"low": {"raised": 0.0}, "level": {"raised": 1.0}, "up": {"raised": 1.0, "pitch": AIM_PITCH}}
    states["down"] = {"raised": 1.0, "pitch": -AIM_PITCH}
    for body in bodies:
        for tag, state in states.items():
            posed = copy_pose(base)
            holds[body.name].apply(rigs[body.name], posed, state)
            set_pose(body.arm, rigs[body.name], posed)
            depths = [depth for depth, _place in body.overlaps().values()]
            out[(body.name, tag)] = round(max(depths, default=0.0) * 1000.0, 1)
        # Through a reload the left hand goes the hold's own way past the right hand and the forearm.
        deepest = 0.0
        for f in range(1, RELOAD_FRAMES):
            posed = copy_pose(base)
            holds[body.name].apply(rigs[body.name], posed, {"raised": 0.0, "reload": f / RELOAD_FRAMES})
            set_pose(body.arm, rigs[body.name], posed)
            deepest = max([deepest] + [depth for depth, _place in body.overlaps().values()])
        out[(body.name, "reload")] = round(deepest * 1000.0, 1)
    return out


def state_tag(state):
    if state.get("reload", -1.0) >= 0.0:
        return "reload"
    if state.get("raised", 0.0) < 0.5:
        return "low"
    pitch = state.get("pitch", 0.0)
    return "level" if abs(pitch) < 1.0 else ("up" if pitch > 0.0 else "down")


def measure(clips, bodies, rigs, holds, gun, report, floor):
    """Every frame of every clip on every body, posed as the game draws it (the clip, then the hold on that
    body): limbs in limbs, the head and the chest in the rifle, the arms' reach, the eye on the sight line."""
    failures = []
    for name, clip in clips.items():
        entry = report["clips"].setdefault(name, {})
        for body in bodies:
            rig = rigs[body.name]
            worst = {"overlap_mm": 0.0, "head_in_rifle_mm": 0.0, "neck_in_rifle_mm": 0.0, "chest_in_rifle_mm": 0.0}
            worst["short_mm"] = 0.0
            where, eye_worst = {}, 0.0
            for f, (pose, state) in enumerate(zip(clip["frames"], clip["states"])):
                posed = copy_pose(pose)
                held = holds[body.name].apply(rig, posed, state)
                set_pose(body.arm, rig, posed)
                for (a, b), (depth, _place) in body.overlaps().items():
                    if depth * 1000.0 > worst["overlap_mm"]:
                        worst["overlap_mm"] = round(depth * 1000.0, 1)
                        where["overlap"] = f"{a} in {b} at frame {f}"
                head = part_points(body, "head")
                parts = {"head_in_rifle_mm": head[HEAD_SKIN[body.name]], "neck_in_rifle_mm": head[~HEAD_SKIN[body.name]]}
                parts["chest_in_rifle_mm"] = part_points(body, "chest")
                for key, points in parts.items():
                    mm = round(gun.depth(points, held) * 1000.0, 1)
                    if mm > worst[key]:
                        worst[key] = mm
                        where[key] = f"frame {f}"
                short = max(held["short"].values()) * 1000.0
                if short > worst["short_mm"]:
                    worst["short_mm"] = round(short, 2)
                    where["short"] = f"frame {f}"
                if "Aim" in name:
                    eye_worst = max(eye_worst, eye_off(rig, posed, held)[0])
            worst["where"] = where
            if "Aim" in name:
                worst["eye_off_mm"] = round(eye_worst, 1)
            entry[body.name] = worst
            line = f"  {name:18s} {body.name:17s} " + "  ".join(f"{k} {v}" for k, v in worst.items() if k != "where")
            print(line, where)
            alone = floor[(body.name, state_tag(clip["states"][1]))]
            worst["hold_alone_mm"] = alone
            if worst["overlap_mm"] > max(OVERLAP_LIMIT, alone + OVERLAP_OVER_HOLD):
                failures.append(f"{name} on {body.name}: {where['overlap']}, {worst['overlap_mm']} mm")
            if worst["head_in_rifle_mm"] > HEAD_LIMIT:
                failures.append(f"{name} on {body.name}: the head is {worst['head_in_rifle_mm']} mm in the rifle")
            if worst["short_mm"] > REACH_LIMIT:
                failures.append(f"{name} on {body.name}: an arm stops {worst['short_mm']} mm short")
    return failures


def pose_gap(a, b, bones=None):
    """The largest turn between two poses' bones, in degrees."""
    worst = 0.0
    for n in bones or a["local"]:
        apart = np.linalg.norm(a["local"][n] - b["local"][n]) / (2.0 * math.sqrt(2.0))
        worst = max(worst, math.degrees(2.0 * math.asin(min(apart, 1.0))))
    return worst


def render_previews(folder, clips, bodies, rigs, holds, gun):
    """Contact sheets to look at: a row a view (the right side, the front left, above, behind the right
    shoulder), a column a frame, one sheet a clip and body."""
    folder.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_shadows = False
    scene.render.resolution_x, scene.render.resolution_y = 420, 420
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("Sheet")
    scene.world = world
    camera = bpy.data.objects.new("SheetCamera", bpy.data.cameras.new("SheetCamera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.05
    target = np.array([0.0, 1.38, 0.2])
    views = {"right": (-2.5, 0.0, 0.0), "front_left": (1.6, 0.4, 2.0), "above": (0.0, 2.5, 0.01), "shoulder": (-0.7, 0.5, -2.2)}
    for body in bodies:
        body.mesh.color = (0.72, 0.74, 0.78, 1.0)
    gun.root.color = (0.25, 0.25, 0.27, 1.0)
    gun.magazine.color = (0.4, 0.3, 0.2, 1.0)
    for name, clip in clips.items():
        count = len(clip["frames"])
        picks = sorted({round(i * (count - 1) / 5) for i in range(6)})
        for body in bodies:
            for other in bodies:
                other.mesh.hide_render = other is not body
            rig = rigs[body.name]
            tiles = []
            for view, offset in views.items():
                row = []
                for f in picks:
                    posed = copy_pose(clip["frames"][f])
                    held = holds[body.name].apply(rig, posed, clip["states"][f])
                    set_pose(body.arm, rig, posed)
                    gun.place(held)
                    eye = C[:3, :3] @ (target + np.array(offset))
                    look = C[:3, :3] @ target
                    camera.location = eye.tolist()
                    camera.rotation_euler = (Vector(look.tolist()) - Vector(eye.tolist())).to_track_quat("-Z", "Y").to_euler()
                    path = folder / f"_tile_{view}_{f}.png"
                    scene.render.filepath = str(path)
                    bpy.ops.render.render(write_still=True)
                    image = bpy.data.images.load(str(path))
                    pixels = np.array(image.pixels[:]).reshape(image.size[1], image.size[0], 4)
                    bpy.data.images.remove(image)
                    path.unlink()
                    row.append(pixels)
                tiles.append(np.concatenate(row, axis=1))
            sheet = np.concatenate(tiles[::-1], axis=0)
            out = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0], alpha=True)
            out.pixels = sheet.ravel().tolist()
            out.filepath_raw = str(folder / f"{name}_{body.name}.png")
            out.file_format = "PNG"
            out.save()
            bpy.data.images.remove(out)
            print("sheet", folder / f"{name}_{body.name}.png", "frames", picks)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out")
    parser.add_argument("--data")
    parser.add_argument("--report")
    parser.add_argument("--preview")
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--no-checks", action="store_true")
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    base, base_time = library_pose(GAME / BASE_FILE, BASE_CLIP.split("/")[1])
    print(f"  the legs and the pelvis: {BASE_CLIP} at {base_time:.4f} s")
    bodies, rigs, holds = [], {}, {}
    for stem in BODIES:
        arm, objects = import_glb(GAME / MODELS / f"{stem}.glb")
        # The nearest level of detail: the mesh with the most vertices.
        mesh = max((o for o in objects if o.type == "MESH" and o.parent == arm), key=lambda o: len(o.data.vertices))
        for o in objects:
            if o.type == "MESH" and o is not mesh:
                bpy.data.objects.remove(o)
        body = limb_overlap.Body(arm, mesh, stem)
        bodies.append(body)
        rigs[stem] = Rig(arm, stem)
        holds[stem] = Hold(f"{stem}.glb")
        kept = holds[stem].measure_chest(rigs[stem], mesh)
        print(f"  {stem}: {kept} points of the torso's skin for the butt")
        print(f"  {stem}: the hold is {holds[stem].fit}")
    female = bodies[0]
    rig = rigs[female.name]
    hold = holds[female.name]
    gun = Gun()
    for body in bodies:
        own = rigs[body.name]
        set_pose(body.arm, own, {"local": {n: own.rest[n][:3, :3] for n in own.names}, "pelvis": own.rest["pelvis"][:3, 3]})
        points = part_points(body, "head")
        high = points[:, 1] > own.rest_world["Head"][1, 3] + 0.03
        HEAD_SKIN[body.name] = high
        SKIN_POINTS[body.name] = {
            bone: some[::2] - own.rest_world[bone][:3, 3] for bone, some in (("Head", points[high]), ("neck_01", points[~high]))
        }

    base = whole(rig, base)
    others = [(rigs[b.name], holds[b.name]) for b in bodies[1:]]
    clips = make_clips(rig, base, hold, args.only, others)
    report = {"fps": FPS, "clips": {}, "solved": {}}
    failures = []
    for name, clip in clips.items():
        frames = clip["frames"]
        entry = report["clips"].setdefault(name, {})
        entry["frames"] = len(frames) - 1
        entry["seconds"] = round((len(frames) - 1) / FPS, 4)
        if clip["solved"]:
            report["solved"][name] = clip["solved"]
            off, behind = eye_off(rig, frames[0], clip["held"][0])
            entry["eye_off_mm"], entry["eye_back_mm"] = round(off, 1), round(behind, 1)
            eye = (np.linalg.inv(clip["held"][0]["gun"]) @ np.append(eye_of(rig, frames[0]), 1.0))[:3] - SIGHT_EYE
            # Where the eye is from its place on the line, in the rifle's space: toward the butt, up, to the left.
            entry["eye_from_place_mm"] = np.round(eye * 1000.0, 1).tolist()
            entry["butt_push_mm"] = round(clip["held"][0]["push"] * 1000.0, 1)
            face, _ = face_of(rig, frames[0])
            line = clip["held"][0]["gun"][:3, :3] @ (SIGHT_AHEAD / np.linalg.norm(SIGHT_AHEAD))
            entry["face_off_line_deg"] = round(angle_between(face, line), 1)
            print(f"  {name}: solved {clip['solved']}, eye {off:.1f} mm off the line, face {entry['face_off_line_deg']} deg")
            print(f"    the eye from its place (back, up, left) {entry['eye_from_place_mm']} mm, the butt pushed {entry['butt_push_mm']} mm")
            rolls = [max(abs(r) for r in pair) for pair in zip(*(head_rolls(rig, pose) for pose in frames))]
            entry["head_roll_deg"], entry["neck_roll_deg"] = round(rolls[0], 1), round(rolls[1], 1)
            head_face, head_up = face_of(rig, frames[0])
            level_side = np.cross(Y, head_face)
            entry["head_cant_deg"] = round(90.0 - angle_between(head_up, level_side), 1)
            print(f"    the head rolled {rolls[0]:.1f} degrees on the neck, the neck {rolls[1]:.1f}; canted {entry['head_cant_deg']}")
        if clip["loop"]:
            gap = pose_gap(frames[0], frames[-1])
            entry["loop_gap_deg"] = round(gap, 4)
            if gap > 0.01:
                failures.append(f"{name}: the loop does not close ({gap:.3f} degrees)")
    joins = {"Rifle_Shoot": "Rifle_Aim_Neutral", "Rifle_Reload": "Rifle_Idle"}
    for name, joined in joins.items():
        if name in clips and joined in clips:
            for end in (0, -1):
                gap = pose_gap(clips[name]["frames"][end], clips[joined]["frames"][0])
                report["clips"][name][f"join_gap_deg_{'start' if end == 0 else 'end'}"] = round(gap, 4)
                if gap > 0.01:
                    failures.append(f"{name}: frame {end} is {gap:.3f} degrees off {joined}'s first pose")

    if not args.no_checks:
        floor = hold_alone(base, bodies, rigs, holds)
        report["hold_alone_mm"] = {f"{name} {tag}": mm for (name, tag), mm in floor.items()}
        print("  the hold alone, on the idle:", report["hold_alone_mm"])
        failures += measure(clips, bodies, rigs, holds, gun, report, floor)
    if args.preview:
        render_previews(Path(args.preview), clips, bodies, rigs, holds, gun)
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1), encoding="utf-8")
    if failures:
        print("FAILED:")
        for failure in failures:
            print("  " + failure)
        sys.exit(1)
    if args.data:
        data = {
            "fps": FPS,
            # The pose under the clips: the bones over `spine_01` are this clip's at this time.
            "base": {"clip": BASE_CLIP, "seconds": round(base_time, 4)},
            "clips": {
                name: {"frames": len(clip["frames"]) - 1, "seconds": round((len(clip["frames"]) - 1) / FPS, 4), "loop": clip["loop"]}
                for name, clip in clips.items()
            },
        }
        Path(args.data).write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    if args.out:
        for obj in list(gun.objects):
            bpy.data.objects.remove(obj)
        for body in bodies[1:]:
            for obj in [body.mesh, body.arm]:
                bpy.data.objects.remove(obj)
        bpy.data.objects.remove(female.mesh)
        for name, clip in clips.items():
            # Godot's importer makes a clip whose name ends in `_Loop` a loop and drops the ending.
            key_clip(female.arm, rig, name + ("_Loop" if clip["loop"] else ""), clip["frames"])
        export(female.arm, args.out)
        print("exported", args.out, [f"{n} {len(c['frames']) - 1}" for n, c in clips.items()])


if __name__ == "__main__":
    main()
