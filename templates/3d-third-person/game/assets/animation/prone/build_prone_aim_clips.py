"""Build the template's prone aim clips for one body and export them to glTF (kit #1111).

GDStudio's own animation, made from nothing, because neither the Universal Animation Library nor the prone clips of
kit #1009 hold a weapon lying down. Three poses of a body that lies on its belly behind the pistol and aims it with
both hands, by how far it looks up or down: flat on the ground, both arms stretched ahead, the hands resting just
over the floor, the head low behind the sights. Each clip is a slow breath that leaves the pistol still.

One file a body, solved on that body's own skeleton and skin with that body's own hold: `prone_aim.glb` on
`form_female` (the body the character scene wears) and `prone_aim_male.glb` on `form_male` (`BODIES` holds what
differs). Two bodies with different arms and hands cannot share the file: the first set, solved on the Quaternius
female, put the prototype bodies' left hand 8 to 27 mm off the pistol and the magazine 8 to 26 mm under the floor.

The hands are placed from the hold the game uses, never from a typed number: `tools/hold/dump_aim_seat.gd` writes,
for each body, the pistol's seat on `hand_r`, the left hand's `SupportHand` marker, the wrist turn of the grip pose
and the finger rotations of the grip, trigger and support poses. This script puts the right hand's bone where that
seat carries the pistol along the aim and the left hand's bone on the marker (the game's `HoldArm` then finds the
left hand where the clip already has it), keys the hold's fingers, and measures the skin as the game shows it: the
wrist turn on, the fingers closed, the twist bones turned as `MannequinTwist` turns them.

The pelvis and the legs are the first pose of the prone idle the body plays in the game, read from that file
(`--idle`): the game lays these clips over the prone idle and the crawl from `spine_01` up, so the chest is solved
on the pelvis the game will give it. When the prone idle of a body changes, build its aim clips again.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute, once a body:

    blender -b --factory-startup -P build_prone_aim_clips.py -- --body female --model <form_female.glb>
        --hold <aim_seat.json> --idle <prone.glb> --out <prone_aim.glb> [--report <numbers.json>]
    blender -b --factory-startup -P build_prone_aim_clips.py -- --body male --model <form_male.glb>
        --hold <aim_seat.json> --idle <prone.glb> --out <prone_aim_male.glb> [--report <numbers.json>]

Blender exits 0 when a script raises, so read the output for `EXPORTED` and check the file's time.

It shares the solver, the keying and the export of `build_prone_clips.py` (same folder), and fails before it exports
when a loop does not close, a target is missed, the pistol is off its line, the rig's rests differ from Godot's, the
left arm is too near straight in a clip or in the blend between two, a hand, a finger bone, an arm or the pistol is
under the floor, the two sides mirror each other, or a part of the body goes more than 5 mm into another (the two
hands on each other and on the pistol are measured in the game: `tests/gameplay/test_prone_aim_hold.gd`).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Quaternion

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_prone_clips as base  # noqa: E402

FPS = base.FPS
FRAMES = 90  # one breath, the prone idle's length
IDLE_CLIP = "Prone_Idle_Loop"
# The clips and the look each is made for, in degrees (up is positive). The game blends them by the look.
CLIPS = {
    "Prone_Aim_Down_Loop": -25.0,
    "Prone_Aim_Neutral_Loop": 0.0,
    "Prone_Aim_Up_Loop": 20.0,
}
LOWER_BODY = ("root", "pelvis", "thigh", "calf", "foot", "ball")
HAND_PARTS = ("hand", "index", "middle", "ring", "pinky", "thumb")
CLEAR = {"foot": 0.006, "muzzle": 0.04}  # metres the grip's foot and the muzzle stay over the floor
HAND_CLEAR = 0.002  # metres the hands' skin stays over the floor
CHEST_SINK = 0.003  # metres the chest's skin presses into the floor
HEAD_FOLLOW = (0.2, 0.45)  # the share of the look the neck and the head follow
ARM_REST = 0.001  # metres an arm's skin stays over the floor: an elbow that would go under is raised to rest on it
ARM_FLOOR = -1.0  # millimetres an arm's skin may be under the floor
LINE_LIMIT = 0.3  # degrees the barrel may be off the look, and millimetres/10 a hand may be off its place
REACH_LIMIT = 0.985  # how far of its length the left arm may be stretched, in a clip and between two
MIRROR_LIMIT = {"elbow": 0.03, "shoulder": 0.008}  # metres a left joint is from the right one's reflection, at least
OVERLAP_LIMIT = base.OVERLAP_LIMIT

# What each body's pose is made of. No pose is the same on both sides: every side has its own numbers, written out,
# never one number with a flipped sign. The right arm is the firing arm and the straighter one; the left shoulder is
# pushed ahead and the chest turned after it, as a two-handed hold turns the support side toward the target, so the
# support hand reaches round the front of the grip with its elbow bent lower and wider.
BODIES = {
    "female": {
        "hold": "form_female",
        "extend": 0.93,  # how far the right arm is stretched toward the pistol (1 is locked straight)
        "grip_right": 0.012,  # metres the grip is to the right of the body's middle: in front of the right eye
        "grip_up": {20.0: 0.125},  # the grip over the floor for a look that lifts the pistol off it
        # each trunk bone's pitch from standing (90 lies face down), its yaw (negative brings the left shoulder
        # ahead) and its roll; the spine then gives until the chest rests
        "trunk": {
            "spine_01": (86.0, -1.0, 0.5),
            "spine_02": (79.0, -2.5, 1.0),
            "spine_03": (71.0, -5.0, 1.5),
            "neck_01": (54.0, -1.0, 3.0),
            "Head": (30.0, 6.0, 8.0),  # turned and tipped to the left, the right eye behind the sights
        },
        # degrees each collarbone lifts toward the head and pushes toward the chest
        "clav": {"l": (25.0, 1.0), "r": (19.0, -1.0)},
        # where each elbow points: ahead (negative is back), out to its side, up
        "pole": {"l": (-0.10, 0.80, -0.75), "r": (-0.25, 0.55, -1.0)},
        "bone_floor": 0.008,  # metres the lowest hand or finger bone is over the floor (the Godot test's limit)
    },
    "male": {
        "hold": "form_male",
        "extend": 0.93,
        "grip_right": 0.014,
        "grip_up": {20.0: 0.13},
        "trunk": {
            "spine_01": (86.0, -1.0, 0.5),
            "spine_02": (79.0, -2.0, 1.0),
            "spine_03": (71.0, -4.5, 1.5),
            "neck_01": (54.0, -1.0, 2.5),
            "Head": (30.0, 5.0, 7.0),
        },
        "clav": {"l": (24.0, 1.5), "r": (18.0, -1.0)},
        "pole": {"l": (-0.08, 0.85, -0.70), "r": (-0.22, 0.40, -1.0)},
        "bone_floor": 0.004,
    },
}

# Godot's axes (x left, y up, z ahead) to Blender's (x left, y back, z up).
TO_BLENDER = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])
# The twist bones of the prototype rig as the game's `MannequinTwist` drives them: the twist bone, the bone whose
# roll it reads, and whether it takes that roll back out (true) or copies it (false).
TWISTS = [
    (f"{twist}_twist_01_{side}", f"{source}_{side}", counter)
    for side in ("l", "r")
    for twist, source, counter in (("upperarm", "upperarm", True), ("thigh", "thigh", True), ("lowerarm", "hand", False))
]


def xf(numbers):
    """A transform written as twelve numbers (the basis' columns, then the origin) as a 4x4 matrix."""
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = (
        numbers[0:3],
        numbers[3:6],
        numbers[6:9],
        numbers[9:12],
    )
    return m


def quat_matrix(q):
    """A quaternion as Godot writes it (x, y, z, w) as a 3x3 matrix."""
    x, y, z, w = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def roll_about_y(q):
    """The part of a turn that is a roll about the bone's length (the swing-twist split of `MannequinTwist`)."""
    roll = Quaternion((q.w, 0.0, q.y, 0.0))
    if roll.magnitude < 1e-6:
        return Quaternion()
    return roll.normalized()


class Hold:
    """A body's hold of the pistol as the game has it (`dump_aim_seat.gd`), and where it puts the two hand bones."""

    def __init__(self, path, model):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        body = data["models"][model]
        self.seat = xf(body["seat"])
        self.support = xf(body["support"])
        self.muzzle = xf(data["muzzle"])
        self.foot = xf(data["foot"])
        self.turn = quat_matrix(body["turn"])
        self.rest = {"r": xf(body["hand_r"])[:3, :3], "l": xf(body["hand_l"])[:3, :3]}
        self.rests = {bone: quat_matrix(q) for bone, q in body["rests"].items()}
        # The fingers as the game holds them while it aims: the grip with the index finger on the trigger, and
        # the support hand's.
        self.fingers = {}
        for pose in ("grip", "trigger", "support"):
            self.fingers.update({bone: quat_matrix(q) for bone, q in body["poses"][pose].items()})

    def pistol(self, grip, look):
        """The pistol's transform in Godot's model space with its grip at `grip` (Blender's axes), aimed `look`
        degrees up from straight ahead. The pistol's own axes: the muzzle along -X, up +Y, its left +Z."""
        a = math.radians(look)
        ahead = np.array([0.0, math.sin(a), math.cos(a)])
        left = np.array([1.0, 0.0, 0.0])
        m = np.eye(4)
        m[:3, 0], m[:3, 1], m[:3, 2] = -ahead, np.cross(ahead, left), left
        m[:3, 3] = TO_BLENDER.T @ np.asarray(grip, dtype=float)
        return m

    def hands(self, grip, look):
        """For each side, the hand bone's place and its world turn from the rest, in Blender's axes: the right hand
        where the seat carries the pistol (less the wrist turn the game's grip pose adds after the clip), the left
        hand on the support marker."""
        pistol = self.pistol(grip, look)
        right = pistol @ np.linalg.inv(self.seat)
        left = pistol @ self.support
        out = {}
        for s, posed, undo in (("r", right, self.turn.T), ("l", left, np.eye(3))):
            turn = posed[:3, :3] @ undo @ self.rest[s].T
            out[s] = (TO_BLENDER @ posed[:3, 3], TO_BLENDER @ turn @ TO_BLENDER.T)
        return out

    def carried(self, rig, world):
        """The pistol as a pose carries it (its transform in Godot's model space), from the right hand's bone."""
        hand = world["hand_r"]
        turn = TO_BLENDER.T @ (hand[:3, :3] @ rig.rest_rot["hand_r"].T) @ TO_BLENDER
        posed = np.eye(4)
        posed[:3, :3] = turn @ self.rest["r"] @ self.turn
        posed[:3, 3] = TO_BLENDER.T @ hand[:3, 3]
        return posed @ self.seat

    def measure(self, rig, world, look):
        """What a solved pose does to the pistol: degrees the barrel is off the look, metres the left hand's bone
        is off the support marker, and where the muzzle, the grip's foot and the marker are (Blender's axes)."""
        pistol = self.carried(rig, world)
        a = math.radians(look)
        barrel = -pistol[:3, 0]
        off = math.degrees(math.acos(min(1.0, float(barrel @ np.array([0.0, math.sin(a), math.cos(a)])))))
        marker = TO_BLENDER @ (pistol @ self.support)[:3, 3]
        muzzle = TO_BLENDER @ (pistol @ self.muzzle)[:3, 3]
        foot = TO_BLENDER @ (pistol @ self.foot)[:3, 3]
        return off, float(np.linalg.norm(marker - world["hand_l"][:3, 3])), muzzle, foot, marker


class AimSolver(base.Solver):
    """The prone solver with hands that take their turn from the weapon, not from the forearm, fingers that take
    the hold's poses, and twist bones turned as the game turns them."""

    def __init__(self, rig, hold):
        super().__init__(rig)
        self.hold = hold

    def _arm(self, world, spec, s, sign):
        super()._arm(world, spec, s, sign)
        turn = spec["arm"][s].get("hand_turn")
        if turn is not None:
            world["hand_" + s][:3, :3] = turn @ self.rig.rest_rot["hand_" + s]

    def solve(self, spec):
        pose = super().solve(spec)
        for bone, turn in self.hold.fingers.items():
            pose["local"][bone] = turn
        return pose

    def twists(self, local):
        """Each twist bone's turn in its parent for a pose, as `MannequinTwist` sets it after the clip."""
        rig = self.rig
        out = {}
        for twist, source, counter in TWISTS:
            if twist not in rig.local_rot:
                continue
            rest = base.to_quat(rig.local_rot[source])
            pose = base.to_quat(local[source])
            own = base.to_quat(rig.local_rot[twist])
            if counter:
                turned = own @ roll_about_y(rest.inverted() @ pose).inverted()
            else:
                turned = roll_about_y(pose @ rest.inverted()) @ own
            out[twist] = np.array(turned.to_matrix())
        return out


def shown(rig, hold, pose):
    """World matrices of a pose as the game shows it: the clip, then the wrist turn of the grip pose on `hand_r`
    (the twist bones are in the pose already, turned from the clip's own hand, as the game's modifiers run)."""
    local = dict(pose["local"])
    local["hand_r"] = local["hand_r"] @ hold.turn
    return rig.world(local, pose["pelvis"])


def trunk_spec(body, lower, look, phase, give):
    """The lying body without its arms: the pelvis of the prone idle, the trunk's arch flattened by `give` degrees
    so the chest rests, a slow breath, and the head following the look."""
    breath = math.sin(2 * math.pi * phase)
    late = math.sin(2 * math.pi * (phase - 0.12))
    spec = base.prone_base(0.0)
    spec["pelvis_pos"] = lower["pelvis"].copy()
    spec["comply"] = False
    for key in ("curl", "thumb_flat", "fist"):
        spec.pop(key)
    numbers = body["trunk"]
    trunk = spec["trunk"]
    trunk["pelvis"] = lower["pelvis_turn"]
    for name, share, swell in (("spine_01", 1 / 3, 0.3), ("spine_02", 2 / 3, 0.6), ("spine_03", 1.0, 0.8)):
        pitch, yaw, roll = numbers[name]
        trunk[name] = (pitch + share * give - swell * breath, yaw, roll)
    pitch, yaw, roll = numbers["neck_01"]
    trunk["neck_01"] = (pitch - HEAD_FOLLOW[0] * look - 0.5 * late, yaw, roll)
    pitch, yaw, roll = numbers["Head"]
    trunk["Head"] = (pitch - HEAD_FOLLOW[1] * look - 0.6 * late, yaw, roll)
    spec["clav"] = {
        "l": (body["clav"]["l"][0] + 0.6 * breath, body["clav"]["l"][1]),
        "r": (body["clav"]["r"][0] + 0.4 * late, body["clav"]["r"][1]),
    }
    return spec


def grip_up(body, hold, look):
    """The grip's height that rests the pistol as low as the floor lets it (the grip's foot and the muzzle keep
    `CLEAR`), or the height typed for a look that lifts it."""
    if look in body["grip_up"]:
        return body["grip_up"][look]
    pistol = hold.pistol(base.vec(0.0, 0.0, 0.0), look)
    low = [
        CLEAR[part] - (TO_BLENDER @ (pistol @ point)[:3, 3])[2]
        for part, point in (("foot", hold.foot), ("muzzle", hold.muzzle))
    ]
    return max(low)


def grip_place(rig, body, hold, shoulders, look, up):
    """Where the pistol's grip is, `up` over the floor and `grip_right` to the right of the body's middle (in
    front of the right eye), so that the right wrist is `extend` of the arm's length from its shoulder: one
    unknown (how far ahead), bisected. Returns the place and how far the left arm is stretched (1 is straight)."""

    def reach(ahead, s):
        hands = hold.hands(base.vec(ahead, -body["grip_right"], up), look)
        return np.linalg.norm(hands[s][0] - shoulders[s]) / (rig.len["upperarm_" + s] + rig.len["lowerarm_" + s])

    near, far = -shoulders["r"][1], -shoulders["r"][1] + 1.0
    for _ in range(50):
        middle = (near + far) / 2
        if reach(middle, "r") < body["extend"]:
            near = middle
        else:
            far = middle
    return base.vec(near, -body["grip_right"], up), float(reach(near, "l"))


def aim_spec(rig, solver, body, hold, lower, look, phase, give, grip=None, lift=0.0, raised=None):
    """The targets of one frame: the trunk, and both arms stretched to the hands on the pistol. The pistol is
    placed from the shoulders once (`grip` none) and stays there through the breath; `raised` is how far each
    elbow's pole is turned up from the body's own, so the arm rests on the floor and not in it."""
    spec = trunk_spec(body, lower, look, phase, give)
    reach = 0.0  # how far the left arm is stretched
    if grip is None:
        trunk = solver._trunk(spec, np.zeros(2))
        shoulders = {s: trunk["upperarm_" + s][:3, 3].copy() for s, _ in base.SIDES}
        grip, reach = grip_place(rig, body, hold, shoulders, look, grip_up(body, hold, look) + lift)
    hands = hold.hands(grip, look)
    for s, sign in base.SIDES:
        place, turn = hands[s]
        ahead, out, up = body["pole"][s]
        spec["arm"][s] = {
            "wrist": place,
            "pole": base.vec(ahead, sign * out, up + (raised or {}).get(s, 0.0)),
            "palm": turn @ np.array([0.0, 0.0, -1.0]),
            "hand_turn": turn,
        }
        spec["leg"][s] = lower["leg"]
    spec["grip"] = grip
    spec["left_reach"] = reach
    return spec


def solve_pose(rig, solver, lower, spec):
    """A frame's pose: solved from the spine up, the prone idle's below, the twist bones turned for it."""
    pose = solver.solve(spec)
    for n in pose["local"]:
        if n in lower["local"] and (n.rstrip("_lr").rstrip("_") in LOWER_BODY or n.startswith("ball_leaf")):
            pose["local"][n] = lower["local"][n]
    pose["pelvis"] = lower["pelvis"].copy()
    pose["local"].update(solver.twists(pose["local"]))
    return pose


def chest_give(rig, solver, body, hold, lower):
    """Degrees the spine flattens so that the chest's skin rests on the floor (pressed `CHEST_SINK` into it)."""

    def low(give):
        pose = solve_pose(rig, solver, lower, aim_spec(rig, solver, body, hold, lower, 0.0, 0.0, give))
        skinned = rig.skin(shown(rig, hold, pose))
        return rig.lowest(skinned, ("spine_02", "spine_03", "clavicle")) + CHEST_SINK

    under, over = 30.0, -20.0  # the chest in the floor, and off it
    for _ in range(30):
        middle = (under + over) / 2
        if low(middle) < 0.0:
            under = middle
        else:
            over = middle
    return (under + over) / 2


def hand_bones_low(rig, world):
    """The lowest origin of a hand's or a finger's bone, in metres over the floor, with the bone."""
    low, lowest = 1.0, ""
    for n in rig.names:
        cursor = n
        while cursor is not None and not cursor.startswith("hand_"):
            cursor = rig.parent[cursor]
        if cursor is not None and world[n][2, 3] < low:
            low, lowest = float(world[n][2, 3]), n
    return low, lowest


def build_clip(rig, solver, body, hold, lower, look, give):
    frames = []
    # The hands rest just over the floor with the pistol: lifted until their skin, the fingers closed as the hold
    # closes them, is `HAND_CLEAR` over it and no hand bone is under the Godot test's limit.
    lift = 0.0
    for _ in range(8):
        grip = aim_spec(rig, solver, body, hold, lower, look, 0.0, give, None, lift)
        world = shown(rig, hold, solve_pose(rig, solver, lower, grip))
        low = rig.lowest(rig.skin(world), HAND_PARTS) - HAND_CLEAR
        low = min(low, hand_bones_low(rig, world)[0] - body["bone_floor"] - 0.001)
        if low >= -1e-4:
            break
        lift -= low

    def arm_low(s, raised):
        spec = aim_spec(rig, solver, body, hold, lower, look, 0.0, give, grip["grip"], 0.0, raised)
        skinned = rig.skin(shown(rig, hold, solve_pose(rig, solver, lower, spec)))
        return min(rig.lowest(skinned, (f"{part}_{s}", f"{part}_twist_01_{s}")) for part in ("upperarm", "lowerarm"))

    # An elbow whose arm would lie in the floor is turned up until the arm's skin rests on it.
    raised = {"l": 0.0, "r": 0.0}
    for s in ("l", "r", "l", "r"):
        if arm_low(s, dict(raised, **{s: 0.0})) >= ARM_REST:
            raised[s] = 0.0
            continue
        under, over = 0.0, 3.0
        for _ in range(24):
            middle = (under + over) / 2
            if arm_low(s, dict(raised, **{s: middle})) < ARM_REST:
                under = middle
            else:
                over = middle
        raised[s] = over
    for f in range(FRAMES):
        spec = aim_spec(rig, solver, body, hold, lower, look, f / FRAMES, give, grip["grip"], 0.0, raised)
        pose = solve_pose(rig, solver, lower, spec)
        pose["left_reach"] = grip["left_reach"]
        pose["raised"] = dict(raised)
        frames.append(pose)
    return frames + [frames[0]]


def bend(rig, world, s):
    """Degrees the wrist is bent: the hand's turn from the forearm, less the turn it has at rest."""
    rest = rig.rest_rot["lowerarm_" + s].T @ rig.rest_rot["hand_" + s]
    now = world["lowerarm_" + s][:3, :3].T @ world["hand_" + s][:3, :3]
    return math.degrees(base.to_quat(rest.T @ now).angle)


def pose_numbers(rig, hold, pose, look):
    world = shown(rig, hold, pose)
    skinned = rig.skin(world)
    off, apart, muzzle, foot, _ = hold.measure(rig, rig.world(pose["local"], pose["pelvis"]), look)
    bone_low, bone = hand_bones_low(rig, world)
    out = {
        "barrel_off_degrees": round(off, 4),
        "left_hand_off_mm": round(apart * 1000.0, 3),
        "muzzle_up": round(float(muzzle[2]), 4),
        "foot_up": round(float(foot[2]), 4),
        "muzzle_ahead": round(float(-muzzle[1]), 3),
        "head_top": round(float(skinned[np.char.startswith(rig.owner, "Head"), 2].max()), 3),
        "head_ahead": round(float(-world["Head"][1, 3]), 3),
        "head_up": round(float(world["Head"][2, 3]), 3),
        "lowest_hand_bone_mm": round(bone_low * 1000.0, 1),
        "lowest_hand_bone": bone,
    }
    for s, _ in base.SIDES:
        out["shoulder_" + s] = [round(float(v), 3) for v in world["upperarm_" + s][:3, 3]]
        out["elbow_" + s] = [round(float(v), 3) for v in world["lowerarm_" + s][:3, 3]]
        out["wrist_" + s] = [round(float(v), 3) for v in world["hand_" + s][:3, 3]]
        out["wrist_bend_" + s] = round(bend(rig, world, s), 1)
        reach = np.linalg.norm(world["hand_" + s][:3, 3] - world["upperarm_" + s][:3, 3])
        out["arm_stretch_" + s] = round(float(reach / (rig.len["upperarm_" + s] + rig.len["lowerarm_" + s])), 4)
        for part in ("upperarm", "lowerarm"):
            out[f"lowest_{part}_{s}_mm"] = round(rig.lowest(skinned, (f"{part}_{s}", f"{part}_twist_01_{s}")) * 1e3, 1)
        mask = np.zeros(len(rig.owner), dtype=bool)
        for part in HAND_PARTS:
            mask |= np.char.startswith(rig.owner, part) & np.char.endswith(rig.owner, "_" + s)
        out[f"lowest_hand_{s}_mm"] = round(float(skinned[mask, 2].min()) * 1e3, 1)
    for part in ("spine", "clavicle", "neck", "Head"):
        out[f"lowest_{part}_mm"] = round(rig.lowest(skinned, (part,)) * 1e3, 1)
    # How far each left joint is from the right one's reflection in the body's middle: no mirror pose.
    for joint, bone in (("shoulder", "upperarm"), ("elbow", "lowerarm"), ("wrist", "hand")):
        right = world[bone + "_r"][:3, 3] * np.array([-1.0, 1.0, 1.0])
        out[f"{joint}_from_mirror_mm"] = round(float(np.linalg.norm(world[bone + "_l"][:3, 3] - right)) * 1e3, 1)
    return out


def between(rig, hold, a, b, share):
    """The pose the game plays between two clips' first frames: every bone's rotation blended."""
    local = {n: base.slerp(a["local"][n], b["local"][n], share) for n in a["local"]}
    return {"local": local, "pelvis": a["pelvis"]}


def blend_numbers(rig, hold, clips):
    """Between two neighbouring clips the game blends bone rotations, not hand places: how far the left arm must
    stretch to its marker there, how far the hand the clips give is from it, and how low the pistol gets."""
    order = sorted(CLIPS, key=CLIPS.get)
    out = {"left_stretch": 0.0, "left_hand_off_mm": 0.0, "pistol_low_mm": 1e3, "at_look": 0.0}
    for low, high in zip(order[:-1], order[1:]):
        for step in range(1, 8):
            share = step / 8
            pose = between(rig, hold, clips[low][0], clips[high][0], share)
            world = rig.world(pose["local"], pose["pelvis"])
            look = CLIPS[low] + share * (CLIPS[high] - CLIPS[low])
            _, apart, muzzle, foot, marker = hold.measure(rig, world, look)
            stretch = float(
                np.linalg.norm(marker - world["upperarm_l"][:3, 3]) / (rig.len["upperarm_l"] + rig.len["lowerarm_l"])
            )
            if stretch > out["left_stretch"]:
                out.update(left_stretch=round(stretch, 4), at_look=round(look, 2))
            out["left_hand_off_mm"] = max(out["left_hand_off_mm"], round(apart * 1e3, 2))
            out["pistol_low_mm"] = min(out["pistol_low_mm"], round(float(min(muzzle[2], foot[2])) * 1e3, 1))
    return out


def read_lower(rig, path):
    """The first pose of the prone idle the body plays, as the game plays it on this body: the file's local
    rotations on this rig's bones, and the pelvis's place."""
    pose = base.library_pose(path, IDLE_CLIP, 0)
    local = {n: (pose["local"][n] if n in pose["local"] else rig.local_rot[n]) for n in rig.names}
    world = rig.world(local, pose["pelvis"])
    return {
        "local": {n: m for n, m in pose["local"].items() if n in rig.local_rot},
        "pelvis": np.array(pose["pelvis"], dtype=float),
        "pelvis_turn": world["pelvis"][:3, :3] @ rig.rest_rot["pelvis"].T,
        # any reachable ankle: the legs are replaced by the idle's
        "leg": {"ankle": world["pelvis"][:3, 3] + base.vec(-0.6, 0.0, 0.0), "pole": base.vec(0.0, 0.0, -1.0)},
    }


def check_rests(rig, hold):
    """Degrees the rig's rests in Blender are off Godot's: the hold's finger rotations and the twist rule are
    written in Godot's bone axes, so the two must agree."""
    worst, bone = 0.0, ""
    for n in rig.names:
        if n == "root" or n not in hold.rests:
            continue
        off = math.degrees(base.to_quat(rig.local_rot[n].T @ hold.rests[n]).angle)
        if off > worst:
            worst, bone = off, n
    return worst, bone


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--body", required=True, choices=sorted(BODIES))
    parser.add_argument("--model", required=True)
    parser.add_argument("--hold", required=True)
    parser.add_argument("--idle", required=True, help="the prone library the body plays in the game")
    parser.add_argument("--out", required=True)
    parser.add_argument("--report")
    parser.add_argument("--keep-blend", help="save the scene with the body and the clips, to render it")
    parser.add_argument("--preview", action="store_true", help="export even when a check fails, to look at it")
    args = parser.parse_args(argv)
    body = BODIES[args.body]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    arm, objects = base.import_glb(args.model)
    # The mesh drawn up close: a prototype body's farther levels of detail lie inside it.
    meshes = [o for o in objects if o.type == "MESH" and o.parent == arm]
    mesh = max(meshes, key=lambda o: len(o.data.vertices))
    for obj in objects:
        if obj.type == "MESH" and obj is not mesh:
            bpy.data.objects.remove(obj)
    rig = base.Rig(arm, mesh)
    hold = Hold(args.hold, body["hold"])
    solver = AimSolver(rig, hold)
    lower = read_lower(rig, args.idle)

    failures = []
    rest_off, rest_bone = check_rests(rig, hold)
    if rest_off > 0.05:
        failures.append(f"the rig's rest of {rest_bone} is {rest_off:.3f} degrees off Godot's")
    give = chest_give(rig, solver, body, hold, lower)
    report = {
        "body": args.body,
        "fps": FPS,
        "clips": {},
        "chest_give_degrees": round(give, 3),
        "rests_off_degrees": round(rest_off, 4),
    }
    clips = {}
    for name, look in CLIPS.items():
        clips[name] = build_clip(rig, solver, body, hold, lower, look, give)
    for name, frames in clips.items():
        look = CLIPS[name]
        numbers = base.clip_numbers(rig, name, frames)
        numbers["look"] = look
        numbers["seam_degrees"] = round(base.seam(frames), 5)
        pose = numbers["pose"] = pose_numbers(rig, hold, frames[0], look)
        numbers["left_arm_stretch"] = round(frames[0]["left_reach"], 4)
        numbers["elbows_raised"] = {s: round(v, 3) for s, v in frames[0]["raised"].items()}
        if frames[0]["left_reach"] > REACH_LIMIT:
            failures.append(f"{name}: the left arm is at {frames[0]['left_reach']:.3f} of its length")
        worst_line, worst_hand, stray = 0.0, 0.0, 0.0
        first = rig.world(frames[0]["local"], frames[0]["pelvis"])
        for each in frames:
            world = rig.world(each["local"], each["pelvis"])
            off, apart, _, _, _ = hold.measure(rig, world, look)
            worst_line, worst_hand = max(worst_line, off), max(worst_hand, apart)
            for bone in ("hand_l", "hand_r"):
                stray = max(stray, float(np.linalg.norm(world[bone][:3, 3] - first[bone][:3, 3])))
        numbers["barrel_off_degrees"] = round(worst_line, 4)
        numbers["left_hand_off_mm"] = round(worst_hand * 1000.0, 3)
        numbers["arms_stray_mm"] = round(stray * 1000.0, 3)
        report["clips"][name] = numbers
        if numbers["solver_miss"] > 0.001:
            failures.append(f"{name}: a target is missed by {numbers['solver_miss']:.4f} m")
        if numbers["seam_degrees"] > 0.01:
            failures.append(f"{name}: the loop does not close")
        if worst_line > LINE_LIMIT or worst_hand * 1000.0 > LINE_LIMIT * 10:
            failures.append(
                f"{name}: the barrel is {worst_line:.3f} degrees off the look, the left hand"
                f" {worst_hand * 1000:.2f} mm off its marker"
            )
        if stray > 0.0005:
            failures.append(f"{name}: a wrist moves {stray * 1000:.2f} mm in the breath")
        for part in ("muzzle_up", "foot_up"):
            if pose[part] < 0.003:
                failures.append(f"{name}: the pistol's {part[:-3]} is {pose[part]} m over the floor")
        if pose["lowest_hand_bone_mm"] < body["bone_floor"] * 1e3:
            failures.append(f"{name}: {pose['lowest_hand_bone']} is {pose['lowest_hand_bone_mm']} mm over the floor")
        for s, _ in base.SIDES:
            if pose[f"lowest_hand_{s}_mm"] < 0.0:
                failures.append(f"{name}: the {s} hand's skin is {-pose[f'lowest_hand_{s}_mm']} mm under the floor")
            for part in ("upperarm", "lowerarm"):
                if pose[f"lowest_{part}_{s}_mm"] < ARM_FLOOR:
                    failures.append(f"{name}: {part}_{s} is {-pose[f'lowest_{part}_{s}_mm']} mm under the floor")
        for joint, least in MIRROR_LIMIT.items():
            if pose[f"{joint}_from_mirror_mm"] < least * 1e3:
                failures.append(
                    f"{name}: the left {joint} is {pose[f'{joint}_from_mirror_mm']} mm from the right one's"
                    f" reflection (a mirror pose; at least {least * 1e3:.0f})"
                )
    report["between_clips"] = blend_numbers(rig, hold, clips)
    if report["between_clips"]["left_stretch"] > REACH_LIMIT:
        failures.append(f"between two clips the left arm is at {report['between_clips']['left_stretch']} of its length")
    if report["between_clips"]["pistol_low_mm"] < 0.0:
        failures.append(f"between two clips the pistol is {-report['between_clips']['pistol_low_mm']} mm under the floor")

    actions = {name: base.key_clip(arm, rig, name, frames) for name, frames in clips.items()}
    for name, frames in clips.items():
        off = base.check_against_blender(arm, mesh, rig, actions[name], frames, FRAMES // 3)
        report["clips"][name]["skinning_against_blender"] = round(off, 6)
        if off > 0.001:
            failures.append(f"{name}: the script's skinning is {off:.4f} m off Blender's")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import limb_overlap

    measured_body = limb_overlap.Body(arm, mesh, args.body)
    report["overlap_mm"] = {}
    for name, frames in clips.items():
        entry = limb_overlap.measure(arm, actions[name], range(0, len(frames), 15), [measured_body])[args.body]
        # The two hands hold the pistol together: the game's hold closes them and its test measures them.
        hands = {k: v[0] for k, v in entry["pairs"].items() if "hand_l" in k and "hand_r" in k}
        pairs = {k: v[0] for k, v in entry["pairs"].items() if k not in hands and v[0] > 0.0}
        deepest = max(pairs.values(), default=0.0)
        report["overlap_mm"][name] = {"deepest": deepest, "pairs": pairs, "hands": hands}
        if deepest > OVERLAP_LIMIT:
            failures.append(f"{name}: {pairs} (the limit is {OVERLAP_LIMIT} mm)")
    arm.animation_data.action = None
    print("REPORT", json.dumps(report, indent=1))
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    if args.keep_blend:
        bpy.ops.wm.save_as_mainfile(filepath=args.keep_blend)
    if failures:
        print("BUILD FAILED\n  " + "\n  ".join(failures))
        if not args.preview:
            raise SystemExit(1)
    bpy.data.objects.remove(mesh)
    base.export(arm, args.out)
    print("EXPORTED", args.out)


if __name__ == "__main__":
    main()
