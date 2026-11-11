"""Build the template's rifle clips and export them to glTF (kit #1082).

GDStudio's own animation, made from nothing on the Quaternius universal rig (the female mannequin's skeleton, CC0),
because the Universal Animation Library has pistol clips and no rifle clip. Six clips, at the library's 30 frames a
second:

- `Rifle_Idle` (a loop): the low ready, the head up and looking ahead, a slow breath;
- `Rifle_Aim_Neutral`, `Rifle_Aim_Up` and `Rifle_Aim_Down` (loops of one length): the rifle at the shoulder with
  the view level and `AIM_PITCH` degrees up and down, the body leant into it, the right shoulder up behind the
  butt and the head down on the stock with the right eye on the sight line;
- `Rifle_Shoot`: a shot's recoil taken by the body, from `Rifle_Aim_Neutral`'s first pose and back to it;
- `Rifle_Reload`: the body through a magazine change and the charging handle, from `Rifle_Idle`'s first pose and
  back to it, the beats at the shares of the reload the game's hold moves the left hand by.

Nothing is copied from another game's or pack's motion. The legs and the pelvis are the library's `Idle` first
pose, held: the game plays these clips on the upper body only, over its own locomotion.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_rifle_clips.py -- --out <rifle_clips.glb> [--data <rifle_clips.json>]
        [--report <numbers.json>] [--preview <folder>] [--only <clip> ...]

How the hands get on the rifle. In the game the rifle is not carried by a bone: `TwoHandHold`
(`gameplay/weapon/two_hand_hold.gd`) puts its butt in the shoulder's pocket from the chest bone's place, turns the
chest, reaches each arm to its place on the rifle and closes the fingers, after the clip, on whichever mannequin
plays it. This build works the same hold out in Python (`Hold`, from the numbers of the hold's own files, none
typed here), so the body is shaped round the rifle where the game will draw it, and the arms and fingers it keys
are the hold's own on the female mannequin: the clip alone shows two hands on the rifle, and the game's hold has
nothing left to move on her (`tests/gameplay/test_rifle_clips.gd` holds the clip's own hands within millimetres of
the hold's). On the male mannequin (arms 5 cm longer) the game's reach does the work, and this build measures him
posed that way.

It works in Godot's axes (the character faces +Z, its left is +X, up is +Y; a bone's pose in its parent is the
same in Blender and in Godot) and keys every bone's rotation on every frame. It fails before it exports when a
loop does not close, a clip does not start and end on the pose it joins, an arm cannot reach on either mannequin,
the eye is off the sight line in an aim clip, the head is in the stock, or a part of the body goes more than
`OVERLAP_LIMIT` into another on either mannequin (`../limb_overlap.py`). The hands against the rifle are measured
in Godot (`tests/gameplay/test_rifle_clips.gd`, `tests/gameplay/test_rifle_hold.gd`).
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
# A clip may not put a limb deeper in another than the hold alone does on the library's idle pose, plus this.
OVERLAP_OVER_HOLD = 3.0
REACH_LIMIT = 0.5  # millimetres an arm may stop short of its place on the rifle
EYE_LIMIT = 80.0  # millimetres the right eye may be off the sight line in an aim clip
HEAD_LIMIT = 5.0  # millimetres the head's skin may be inside the rifle
AIM_PITCH = 45.0  # degrees of view the up and down clips are made for (`CharacterAnimation.aim_pitch_range`)

# The clips' lengths, as their last frame (a loop's last frame is its first again).
IDLE_FRAMES = 90
AIM_FRAMES = 60
SHOOT_FRAMES = 12
RELOAD_FRAMES = 66  # 2.2 s, the rifle's `reload_time`: the game stretches the clip to whatever the weapon says

# Godot's axes to Blender's: (x, y, z) to (x, -z, y).
C = np.array([[1.0, 0, 0, 0], [0, 0, -1.0, 0], [0, 1.0, 0, 0], [0, 0, 0, 1.0]])
X, Y, Z = np.eye(3)

# ---- the body's numbers -------------------------------------------------------------------------------------------

# The right eye and the right cheekbone in the head bone's rest space of the character (metres from the head
# bone: left, up, forward). The mannequin has no face; these are a head's proportions on its 25 cm head.
EYE = np.array([-0.032, 0.125, 0.095])
# Where the eye belongs on the rifle, in the rifle's own space (the muzzle is -X, up +Y, its left +Z): on the line
# over the carry handle's sight and the front sight post, this far behind the rear sight.
SIGHT_EYE = np.array([0.085, 0.232, 0.0])
SIGHT_AHEAD = np.array([-1.0, -0.02, 0.0])  # the way the line runs to the front sight
# The stock in the rifle's space, for the head's place: its comb's top, its half width and where it starts.
STOCK_TOP = 0.167
RECEIVER_TOP = 0.18  # the receiver's tail and the charging handle, ahead of the comb
STOCK_SIDE = 0.031
STOCK_FRONT = -0.04
HEAD_CLEAR = 0.004  # the search keeps the female head this far off the stock
# The head's and the neck's skin on both mannequins, as points from each bone in the character's rest space
# (filled in from the models).
SKIN_POINTS = {}
# How far the search may lean the trunk past where a clip starts it (forward, to the right), and turn the neck and
# the head from the view's own pitch (down, to the left, a roll to the right), in degrees: what a body gives.
AIM_LIMITS = {
    "lean": (-2.0, 12.0),
    "side": (-4.0, 2.0),
    "np": (-8.0, 24.0),
    "ny": (-20.0, 20.0),
    "nr": (-4.0, 10.0),
    "hp": (-12.0, 12.0),
    "hy": (-20.0, 20.0),
    "hr": (-4.0, 12.0),
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
SHOT_HEAD = -0.8
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
RELOAD_JOLTS = [(0.62, 0.9), (0.88, 1.2)]


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


def read_transform(path, node):
    """A node's `transform` in a scene file as a 4 x 4 (the file writes the basis by rows, then the origin)."""
    text = Path(path).read_text(encoding="utf-8")
    block = text.split(f'[node name="{node}"', 1)[1].split("[node", 1)[0]
    numbers = [float(v) for v in re.search(r"transform = Transform3D\(([^)]*)\)", block).group(1).split(",")]
    out = np.eye(4)
    out[:3, :3] = np.array(numbers[:9]).reshape(3, 3)
    out[:3, 3] = numbers[9:]
    return out


def read_quaternions(path):
    """The `rotations` of a `HandPose` file: bone name to its rotation in its parent (3 x 3)."""
    text = Path(path).read_text(encoding="utf-8")
    body = re.search(r"rotations = Dictionary\[StringName, Quaternion\]\(\{(.*?)\}\)", text, re.S)
    found = re.findall(r'&"(\w+)": Quaternion\(([^)]*)\)', body.group(1) if body else "")
    return {name: quat_to_mat([float(v) for v in numbers.split(",")]) for name, numbers in found}


def _value(text):
    text = text.strip()
    vector = re.match(r"Vector[23]\(([^)]*)\)", text)
    if vector:
        return np.array([float(v) for v in vector.group(1).split(",")])
    try:
        return float(text)
    except ValueError:
        return text


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
    """A mannequin's rest skeleton in Godot's axes: each bone's rest in its parent, parents first."""

    def __init__(self, arm):
        assert np.allclose(np.array(arm.matrix_world), np.eye(4), atol=1e-6), "the armature is not at the origin"
        bones = sorted(arm.data.bones, key=lambda b: len(b.parent_recursive))
        self.names = [b.name for b in bones]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        rest = {b.name: np.linalg.inv(C) @ np.array(b.matrix_local) for b in bones}
        self.rest_world = rest
        self.rest = {n: (np.linalg.inv(rest[self.parent[n]]) @ rest[n]) if self.parent[n] else rest[n] for n in self.names}

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

    def __init__(self):
        weapon = GAME / "gameplay/weapon"
        script = (weapon / "two_hand_hold.gd").read_text(encoding="utf-8")
        held = weapon / "rifle_held.tscn"
        self.n = read_numbers(script, held.read_text(encoding="utf-8"), "RifleHeld")
        self.rifle = read_transform(held, "Rifle")
        self.right = read_transform(held, "RightHandTarget")
        self.left = read_transform(held, "LeftHandTarget")
        self.on_magazine = read_transform(held, "MagazineHand")
        base = weapon / "two_hand_hold.tscn"
        self.poles = {"r": read_transform(base, "RightPole")[:3, 3], "l": read_transform(base, "LeftPole")[:3, 3]}
        if (held.read_text(encoding="utf-8")).count('[node name="RightPole"'):
            self.poles = {"r": read_transform(held, "RightPole")[:3, 3], "l": read_transform(held, "LeftPole")[:3, 3]}
        poses = weapon / "hold"
        self.fingers = {
            name: read_quaternions(poses / f"rifle_{name}_pose.tres")
            for name in ("grip", "trigger", "support", "open", "magazine")
        }
        self.spine = ["spine_01", "spine_02", "spine_03"]

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

    def to_magazine(self, progress):
        if progress < 0.0:
            return 0.0
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
        kick = state.get("kick", 0.0)
        pitch = min(max(state.get("pitch", 0.0), -n["pitch_limit"]), n["pitch_limit"])
        chest = rig.chain(pose, self.spine[-1])[:3, 3]
        low = self.turned(n["low_pitch"], n["low_yaw"])
        aim = self.turned(-pitch - n["kick_degrees"] * kick, 0.0)
        basis = slerp(low, aim, raised)
        pocket = n["low_pocket"] + (n["aim_pocket"] - n["low_pocket"]) * raised
        pivot = place_of(basis, chest + pocket - basis[:, 2] * n["kick_distance"] * kick)
        pivot[:3, 3] -= basis[:, 2] * self.pull(rig, pose, pivot)
        left, magazine, shown = self.left_place(state, pivot, chest)
        gun = pivot @ self.rifle
        short = {
            "r": reach(rig, pose, "r", gun @ self.right, self.poles["r"]),
            "l": reach(rig, pose, "l", gun @ left, self.poles["l"]),
        }
        self.close(pose, state)
        return {"gun": gun, "short": short, "magazine": magazine, "magazine_shown": shown, "pivot": pivot}

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
        second = smoothstep(n["_WAY_DOWN"], n["_WAY_BESIDE"], to_magazine)
        opened = smoothstep(0.0, n["_WAY_OPEN"], to_magazine) * (1.0 - smoothstep(n["_WAY_ON"], 1.0, to_magazine))
        for bone, rotation in self.fingers["support"].items():
            if second > 0.0 and bone in self.fingers["magazine"]:
                rotation = slerp(rotation, self.fingers["magazine"][bone], second)
            if opened > 0.0 and bone in self.fingers["open"]:
                # The knuckles open over the first half, the rest of each finger over the second.
                share = min(opened / 0.5, 1.0) if "_01_" in bone else max((opened - 0.5) / 0.5, 0.0)
                rotation = slerp(rotation, self.fingers["open"][bone], share)
            pose["local"][bone] = rotation


# ---- shaping the body -----------------------------------------------------------------------------------------------


def shape(rig, base, hold, state, body):
    """The pose for a frame. The legs and the pelvis are the base pose's. The trunk stands upright from the
    pelvis and is leant (`lean` forward, `side` to the right, degrees over the three spine bones; `breath` back
    over the upper two; `hunch` forward on the chest bone alone) and turned as the hold turns the chest; the collarbones are set from their rest
    (`clavicle_r`, `clavicle_l`: degrees up, forward); the neck and the head are stood upright facing the
    front and turned in the character's space (`neck`, `head`: degrees of pitch down, yaw to the left and roll
    to the right); then the hold is run (the rifle's place, the arms, the fingers). Returns the pose and what
    the hold worked out."""
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
    return pose, held


def eye_of(rig, pose):
    head = rig.chain(pose, "Head")
    rest = rig.rest_world["Head"]
    return head[:3, 3] + head[:3, :3] @ rest[:3, :3].T @ EYE


def face_of(rig, pose):
    """The way the face looks, and the head's up."""
    head = rig.chain(pose, "Head")[:3, :3] @ rig.rest_world["Head"][:3, :3].T
    return head @ Z, head @ Y


def solve_aim(rig, base, hold, state, body):
    """Finds the lean, the neck and the head that put the right eye on the sight line with the face along it:
    a damped least-squares search over eight angles, each held near nothing by its cost (a neck gives more than
    a spine)."""
    names = ["lean", "side", "np", "ny", "nr", "hp", "hy", "hr"]
    soft = np.array([10.0, 5.0, 14.0, 15.0, 8.0, 14.0, 15.0, 8.0])  # degrees each is cheap up to
    # What a body gives and no more (`AIM_LIMITS`): past it an angle costs steeply.
    low = np.array([AIM_LIMITS[n][0] for n in names])
    high = np.array([AIM_LIMITS[n][1] for n in names])
    view = -state.get("pitch", 0.0)  # the neck and the head are counted from the view's own pitch
    centre = np.array([0, 0, view * 0.4, 0, 0, view, 0, 0])
    x = centre + np.array([6.0, 2.0, 12.0, 0.0, 3.0, 0.0, 0.0, 4.0])

    def build(v):
        shaped = dict(body, lean=body.get("lean", 0.0) + v[0], side=v[1], neck=tuple(v[2:5]), head=tuple(v[5:8]))
        return shape(rig, base, hold, state, shaped) + (shaped,)

    def residual(v):
        pose, held, _ = build(v)
        gun = held["gun"]
        eye = (np.linalg.inv(gun) @ np.append(eye_of(rig, pose), 1.0))[:3]
        off = eye - SIGHT_EYE
        line = SIGHT_AHEAD / np.linalg.norm(SIGHT_AHEAD)
        face, up = face_of(rig, pose)
        # The head's skin against the stock: a box of the stock's comb and butt in the rifle's space, open
        # upward and to the left, where a cheek comes off it.
        skin = []
        for bone, points in SKIN_POINTS.items():
            at = rig.chain(pose, bone)
            skin.append(at[:3, 3] + points @ (at[:3, :3] @ rig.rest_world[bone][:3, :3].T).T)
        skin = np.concatenate(skin)
        skin = (np.linalg.inv(gun) @ np.c_[skin, np.ones(len(skin))].T).T[:, :3]
        top = np.where(skin[:, 0] < 0.09, RECEIVER_TOP, STOCK_TOP)
        inside = np.minimum(top - skin[:, 1], STOCK_SIDE - skin[:, 2])
        inside = np.where((skin[:, 0] > STOCK_FRONT) & (skin[:, 2] > -STOCK_SIDE), inside, 0.0)
        deepest = max(float(inside.max()) + body.get("clear", HEAD_CLEAR), 0.0)
        ahead = gun[:3, :3] @ line
        gun_up = gun[:3, :3] @ Y
        return np.concatenate(
            [
                # A millimetre to the side of the line or under it costs as much as 4 degrees of a soft angle;
                # over it a third of that (a cheek on the comb holds the eye up); along it a tenth.
                [off[2] * 400.0, off[1] * (130.0 if off[1] > 0.0 else 400.0), off[0] * 40.0],
                [deepest * 1500.0],
                np.cross(face, ahead) * 12.0,  # the face along the line
                [max(angle_between(up, gun_up) - 12.0, 0.0) * 0.2],  # the head may roll onto the stock
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


def make_clips(rig, base, hold, only):
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
        start = {"clavicle_r": AIM_CLAVICLE_R, "clavicle_l": AIM_CLAVICLE_L, "lean": -pitch * 0.35, "hunch": AIM_HUNCH}
        if pitch < 0.0:
            # Looking down the trunk folds over the rifle: more of both keeps the right forearm off the ribs.
            start.update(lean=AIM_DOWN_LEAN, hunch=AIM_DOWN_HUNCH, clear=AIM_DOWN_CLEAR, clavicle_r=AIM_DOWN_CLAVICLE_R)
        aim_bodies[name], solved[name] = solve_aim(rig, base, hold, {"raised": 1.0, "pitch": pitch}, start)

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
        pitch, yaw, roll = aim_body["head"]
        out["head"] = (pitch + SHOT_HEAD * share, yaw, roll)
        neck = aim_body["neck"]
        out["neck"] = (neck[0] + SHOT_HEAD * 0.4 * share, neck[1], neck[2])
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
    """A library clip's first frame as each bone's rotation in its parent and the pelvis's place there; the
    library is removed again."""
    arm, objects = import_glb(path)
    action = bpy.data.actions.get(clip) or bpy.data.actions[clip + "_Loop"]
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    bpy.context.scene.frame_set(round(action.frame_range[0]))
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
    return {"local": local, "pelvis": pelvis}


def set_pose(arm, rig, pose):
    """Puts a pose on an armature (no keys)."""
    for pb in arm.pose.bones:
        n = pb.name
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Matrix((rig.rest[n][:3, :3].T @ pose["local"][n]).tolist()).to_quaternion()
        if n == "pelvis":
            pb.location = tuple(rig.rest[n][:3, :3].T @ (pose["pelvis"] - rig.rest[n][:3, 3]))
    bpy.context.view_layer.update()


def key_clip(arm, rig, name, frames):
    """Key a clip on the armature: every bone's rotation on every frame, and the pelvis's place."""
    action = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = action
    last = {}
    for f, pose in enumerate(frames):
        for pb in arm.pose.bones:
            n = pb.name
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


def hold_alone(base, bodies, rigs, hold):
    """What the hold does to a body with no rifle clip under it, as the game showed it before these clips: how
    deep a limb is in another with the hold run on the library's `Idle` pose, by body, at the low ready and at
    the shoulder with the view level, up and down. The hold brings the grip close to the chest (kit #1177), so
    its own depth is the floor a clip is held to."""
    out = {}
    states = {"low": {"raised": 0.0}, "level": {"raised": 1.0}, "up": {"raised": 1.0, "pitch": AIM_PITCH}}
    states["down"] = {"raised": 1.0, "pitch": -AIM_PITCH}
    for body in bodies:
        for tag, state in states.items():
            posed = copy_pose(base)
            hold.apply(rigs[body.name], posed, state)
            set_pose(body.arm, rigs[body.name], posed)
            depths = [depth for depth, _place in body.overlaps().values()]
            out[(body.name, tag)] = round(max(depths, default=0.0) * 1000.0, 1)
    return out


def state_tag(state):
    if state.get("raised", 0.0) < 0.5:
        return "low"
    pitch = state.get("pitch", 0.0)
    return "level" if abs(pitch) < 1.0 else ("up" if pitch > 0.0 else "down")


def measure(clips, bodies, rigs, hold, gun, report, floor):
    """Every frame of every clip on every body, posed as the game draws it (the clip, then the hold on that
    body): limbs in limbs, the head and the chest in the rifle, the arms' reach, the eye on the sight line."""
    failures = []
    for name, clip in clips.items():
        entry = report["clips"].setdefault(name, {})
        for body in bodies:
            rig = rigs[body.name]
            worst = {"overlap_mm": 0.0, "head_in_rifle_mm": 0.0, "chest_in_rifle_mm": 0.0, "short_mm": 0.0}
            where, eye_worst = {}, 0.0
            for f, (pose, state) in enumerate(zip(clip["frames"], clip["states"])):
                posed = copy_pose(pose)
                held = hold.apply(rig, posed, state)
                set_pose(body.arm, rig, posed)
                for (a, b), (depth, _place) in body.overlaps().items():
                    if depth * 1000.0 > worst["overlap_mm"]:
                        worst["overlap_mm"] = round(depth * 1000.0, 1)
                        where["overlap"] = f"{a} in {b} at frame {f}"
                for part, key in (("head", "head_in_rifle_mm"), ("chest", "chest_in_rifle_mm")):
                    mm = round(gun.depth(part_points(body, part), held) * 1000.0, 1)
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


def render_previews(folder, clips, bodies, rigs, hold, gun):
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
                    held = hold.apply(rig, posed, clip["states"][f])
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
    base = library_pose(GAME / "assets/animation/universal/ual1.glb", "Idle")
    models = GAME / "assets/characters/mannequin"
    bodies, rigs = [], {}
    for who in ("female", "male"):
        arm, objects = import_glb(models / f"mannequin_{who}.glb")
        mesh = max((o for o in objects if o.type == "MESH" and o.parent == arm), key=lambda o: len(o.data.vertices))
        for o in objects:
            if o.type == "MESH" and o is not mesh:
                bpy.data.objects.remove(o)
        body = limb_overlap.Body(arm, mesh, f"mannequin_{who}")
        bodies.append(body)
        rigs[body.name] = Rig(arm)
    female = bodies[0]
    rig = rigs[female.name]
    hold = Hold()
    gun = Gun()
    for body in bodies:
        own = rigs[body.name]
        set_pose(body.arm, own, {"local": {n: own.rest[n][:3, :3] for n in own.names}, "pelvis": own.rest["pelvis"][:3, 3]})
        points = part_points(body, "head")
        high = points[:, 1] > own.rest_world["Head"][1, 3] + 0.03
        for bone, some in (("Head", points[high]), ("neck_01", points[~high])):
            some = some[::2] - own.rest_world[bone][:3, 3]
            SKIN_POINTS[bone] = np.concatenate([SKIN_POINTS[bone], some]) if bone in SKIN_POINTS else some

    clips = make_clips(rig, base, hold, args.only)
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
            face, _ = face_of(rig, frames[0])
            line = clip["held"][0]["gun"][:3, :3] @ (SIGHT_AHEAD / np.linalg.norm(SIGHT_AHEAD))
            entry["face_off_line_deg"] = round(angle_between(face, line), 1)
            print(f"  {name}: solved {clip['solved']}, eye {off:.1f} mm off the line, face {entry['face_off_line_deg']} deg")
            if off > EYE_LIMIT:
                failures.append(f"{name}: the eye is {off:.1f} mm off the sight line")
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
        floor = hold_alone(base, bodies, rigs, hold)
        report["hold_alone_mm"] = {f"{name} {tag}": mm for (name, tag), mm in floor.items()}
        print("  the hold alone, on the library's Idle:", report["hold_alone_mm"])
        failures += measure(clips, bodies, rigs, hold, gun, report, floor)
    if args.preview:
        render_previews(Path(args.preview), clips, bodies, rigs, hold, gun)
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
