"""Build the template's pistol slide-rack clip and export it to glTF (kit #1081).

GDStudio's own animation, made from nothing on the rig the template's bodies share (the prototype `form_female`
body's skeleton: the Universal Animation Library's 65 bones, whose names are Quaternius's, CC0, and the
prototype rig's 17 leaves, which the clip leaves alone), because the library's `Pistol_Reload` has no rack of
the slide. An overhand rack: the right
hand brings the pistol a little in and cants it, the left hand comes over the top of the slide just in front of the
rear sight, grips it, pulls it back while the right hand pushes the frame forward, lets go at the rear (the slide
runs home on its own), follows through toward the chest and comes back to the support grip. Nothing is copied
from another game's or pack's motion; the only pose read from the library is the last frame of `Pistol_Reload`
(the same as its first), where the clip starts and ends.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_pistol_rack.py -- --out <pistol_rack.glb> [--data <rack_clip.json>]
        [--hand <rack_hand.json>] [--report <numbers.json>] [--preview]

It reads, from the game it lives in: the two bodies the template's characters wear (`form_female.glb`,
`form_male.glb`), `ual1.glb`, each body's hold (`tools/hold/hold_files.py`: the pistol's seat on `hand_r`, the
wrist's turn, the `SupportHand` marker and the hold's hand poses) and each body's left hand on the slide, its
place and its fingers (`rack_hand.json`, written by `solve_rack_hand.py`, one entry a body). It works in Godot's axes (the character faces +Z,
its left is +X, up is +Y; a bone's pose in its parent is the same in Blender and in Godot) and keys every bone's
rotation on every frame at 30 frames a second, the library's rate.

The hands as the game draws them: the hold turns the right wrist and closes the right fingers after the clip, so
the clip keys the right hand as the library has it and the pistol's place is worked out with the hold's turn. The
left hand is keyed onto the slide on the female body, with her fingers; on a body with other arms and hands
(the male's) the same rotations miss, so the game reaches the left hand to the body's own place and closes the
body's own fingers, which this build writes to `--data` for each body (`SlideRack`: the hand bone's way over the
slide in the pistol's space, the fingers closed on it and opened over it, the slide's travel, the clip's shares),
as it reaches the `SupportHand` marker. The build poses both bodies that way and fails before it exports when
the clip does not start and end on the library's pose, an arm cannot reach, the wrist bends too far, or a part of
the body goes more than 5 mm into another on either body (`../limb_overlap.py`). The hands against the pistol
are measured in Godot (`tests/gameplay/test_pistol_rack.gd`).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion

GAME = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(GAME / "tools" / "hold"))

import hold_files  # noqa: E402

FPS = 30
CLIP = "Pistol_Rack"
JOIN_CLIP = "Pistol_Reload"
FRAMES = 28  # the clip's last frame: 0.933 s
OVERLAP_LIMIT = 5.0  # millimetres a part of the body may be inside another (`../limb_overlap.py`)
WRIST_LIMIT = 45.0  # degrees the left wrist may bend from the forearm's line while it grips
# On its way between the support grip and the slide the hand holds nothing, so it is turned toward the forearm's
# line by whatever its wrist would bend past this (degrees): the keys give the hand its turn at each end of the
# way, and held between them it bent the wrist 81 degrees beside the gun.
WAY_WRIST = 40.0

# The beats, in frames. The clip's own left hand goes from the library's place to its support grip (`AT_SUPPORT`,
# where the hold has the hand anyway) and opens there; between `LEAVE` the hold lets the hand go to the clip's arm.
# It is over the slide at `OVER`, closes on it between `GRIP`, pulls between `PULL`, lets go between `RELEASE`
# (the slide runs home in `SLAM`), follows through to `FOLLOW`, is at the support grip again from `RETURNED`, and
# between `BACK` the hold takes it.
AT_SUPPORT = 1.25
LEAVE = (1.0, 2.5)
# The beats the game reads fall on whole frames: its reach follows the hand's place frame by frame.
OVER = 7.0
GRIP = (7.0, 9.0)
# The hand is down on the slide at `CLOSE_AT`, straight from over it, its fingers opened, and only then closes
# them: closing while it still came down, the thumb's tip went 5 mm through the slide's left edge.
CLOSE_AT = 8.0
PULL = (10.0, 13.0)
RELEASE = (13.0, 15.0)
SLAM = 1.0
FOLLOW = 17.0
RETURNED = 25.5
BACK = (25.5, 27.0)
# The hold's own plan for the left hand (`SupportHandPlan`, the game's): how far the hand is on the weapon is the
# rack's `support_weight`. From 1 down to `WAY_FROM` the hold opens the fingers (the first `UNHOOK` of the way)
# and takes the hand out along `WeaponHold.support_way`; down to `ARM_UNTIL` the hand waits at the way's far end
# while the right thumb leaves the left thumb's root for the frame (kit #1084); below it the hold's arm gives the
# hand to the clip's. So the clip's own hand is at the way's far end, not at the support grip, on the frames the
# hold lets it go and takes it: at the grip it lay under the thumb as it came down (5.8 mm in the game on the
# female at frame 2.5, 6.7 mm at frame 25).
ARM_UNTIL = 0.3
WAY_FROM = 0.6
UNHOOK = 0.45

# Godot's axes to Blender's: (x, y, z) to (x, -z, y).
C = np.array([[1.0, 0, 0, 0], [0, 0, -1.0, 0], [0, 1.0, 0, 0], [0, 0, 0, 1.0]])
X, Y, Z = np.eye(3)

# The pistol's way through the clip, as moves from where the library's pose holds it: metres in the character's
# space (left, up, forward), then degrees about the pistol's own axes (roll about the barrel, the top toward the
# gun's left; pitch, the muzzle down; yaw, the muzzle to the character's left). The pistol comes in and down in
# front of the right shoulder and cants, is pushed forward against the pull, nods as the slide runs home, settles
# and goes back. How far in, how far canted and how far turned are what the left wrist needs on the body the clip
# is keyed on (the forearm has to lie along the hand that lies across the slide): on `form_female` 11.5 cm in,
# canted 28 degrees and turned 10 bent the wrist 53 to 57 degrees; 16 cm, 36 and 15 bend it 35. The turn stays
# at 15: the muzzle is kept downrange.
GUN_KEYS = [
    # frame, (left, up, forward), (roll, pitch, yaw), stop
    (0.0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), True),
    (7.5, (-0.03, -0.005, -0.160), (-36.0, 0.0, 15.0), False),
    (10.0, (-0.03, -0.006, -0.165), (-36.0, 0.0, 15.0), True),
    (13.0, (-0.03, -0.004, -0.133), (-36.0, -1.0, 15.0), False),
    (15.0, (-0.03, -0.008, -0.125), (-35.0, 3.0, 15.0), False),
    (18.0, (-0.028, -0.005, -0.140), (-28.0, 0.0, 12.0), False),
    (28.0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), True),
]
# The left hand's way to the slide and back, as moves of its place on the slide in the pistol's own space (the
# muzzle is -X, up +Y, the gun's left +Z): over the slide, opened (the solver's `OVER_MOVE`, which opened the
# fingers to clear the slide on the straight way down from there); after the release, off the slide's rear
# toward the chest.
FOLLOW_MOVE = (0.075, 0.03, 0.035)
# The hand's way between the support grip and the slide goes round the gun's left side, as a hand does: off the
# support grip with its fingers as they let go, along the line the hold solved clear for that body's opened
# hand (`WeaponHold.support_way`, 6 cm; the fingers lie round the front of the grip and under the trigger guard,
# and lifted straight up they go through the guard and the right hand's fingers) and `CLEAR_FAR` times as far,
# turned as it held; then to the left of the slide and above it, turned as it will grip (`SWING_MOVE`, from its
# place over the slide), then over the top.
CLEAR_FAR = 1.5
CLEAR_AT = 4.0
SWING_MOVE = (0.0, 0.03, 0.07)
SWING_IN_AT = 5.0
SWING_BACK_AT = 21.0
CLEAR_BACK_AT = 23.5
# Where the left elbow points, in the character's space: as the hold has it while the hand is on its support grip
# (`WeaponHold.support_elbow`), and out to the side while the hand is on the slide, the forearm across the chest.
# (The right elbow keeps the library's place.)
SUPPORT_ELBOW = (0.6, 0.6, 0.2)
LEFT_ELBOW = (0.75, 1.2, 0.05)
# The chest and the head follow the hands: degrees the upper spine and the head pitch forward at the grip.
SPINE_PITCH = 2.5
HEAD_PITCH = 7.0
BODY_KEYS = [(0.0, 0.0), (8.0, 1.0), (16.0, 1.0), (28.0, 0.0)]


# ---- small maths ------------------------------------------------------------------------------------------------


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def frame_at(span, share):
    """The frame between `span`'s two at which a smoothstep over it is `share`."""
    low, high = 0.0, 1.0
    for _ in range(40):
        mid = (low + high) / 2.0
        low, high = (mid, high) if mid * mid * (3.0 - 2.0 * mid) < share else (low, mid)
    return span[0] + (span[1] - span[0]) * low


def hold_plan(on):
    """`SupportHandPlan` for a hand `on` the weapon by 0 to 1: how far the hold's arm has it, how far out along
    its way it is and how far its fingers are opened."""
    way = 1.0 - min(max((on - WAY_FROM) / (1.0 - WAY_FROM), 0.0), 1.0)
    return min(max(on / ARM_UNTIL, 0.0), 1.0), smoothstep(UNHOOK, 1.0, way), smoothstep(0.0, UNHOOK, way)


def axis_angle(axis, degrees):
    a = math.radians(degrees)
    axis = np.asarray(axis, float) / np.linalg.norm(axis)
    x, y, z = axis
    k = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    return np.eye(3) * math.cos(a) + math.sin(a) * k + (1 - math.cos(a)) * np.outer(axis, axis)


def quat_to_mat(q):  # x y z w, as Godot writes it
    return np.array(Quaternion((q[3], q[0], q[1], q[2])).to_matrix())


def mat_to_quat(m):  # w x y z, as Blender keys it
    q = Matrix(np.asarray(m)[:3, :3].tolist()).to_quaternion()
    return np.array([q.w, q.x, q.y, q.z])


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


def spline(keys, frame):
    """A smooth way through `keys` [(frame, vector, stop)]: cubic, with the slope at a key that of its neighbours
    (none at a key that stops, and none at the ends)."""
    times = [k[0] for k in keys]
    values = [np.asarray(k[1], float) for k in keys]
    if frame <= times[0]:
        return values[0]
    if frame >= times[-1]:
        return values[-1]
    i = max(k for k in range(len(keys) - 1) if times[k] <= frame)

    def slope(k):
        if keys[k][2] or k == 0 or k == len(keys) - 1:
            return np.zeros_like(values[k])
        return (values[k + 1] - values[k - 1]) / (times[k + 1] - times[k - 1])

    span = times[i + 1] - times[i]
    t = (frame - times[i]) / span
    h00, h10 = 2 * t**3 - 3 * t**2 + 1, t**3 - 2 * t**2 + t
    h01, h11 = -2 * t**3 + 3 * t**2, t**3 - t**2
    return h00 * values[i] + h10 * span * slope(i) + h01 * values[i + 1] + h11 * span * slope(i + 1)


def place_spline(keys, frame):
    """A smooth way through places [(frame, 4 x 4, stop)]: the origins on `spline`, the rotations as quaternions
    on it too (kept on one side, then made unit)."""
    origins = [(k[0], k[1][:3, 3], k[2]) for k in keys]
    quats, last = [], None
    for k in keys:
        q = mat_to_quat(k[1])
        if last is not None and q @ last < 0.0:
            q = -q
        last = q
        quats.append((k[0], q, k[2]))
    q = spline(quats, frame)
    q = q / np.linalg.norm(q)
    out = np.eye(4)
    out[:3, :3] = np.array(Quaternion(q.tolist()).to_matrix())
    out[:3, 3] = spline(origins, frame)
    return out


# ---- the rig ----------------------------------------------------------------------------------------------------


class Rig:
    """The mannequin's rest skeleton in Godot's axes: each bone's rest in its parent, parents first."""

    def __init__(self, arm):
        assert np.allclose(np.array(arm.matrix_world), np.eye(4), atol=1e-6), "the armature is not at the origin"
        bones = sorted(arm.data.bones, key=lambda b: len(b.parent_recursive))
        self.names = [b.name for b in bones]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        rest = {b.name: np.linalg.inv(C) @ np.array(b.matrix_local) for b in bones}
        self.rest = {n: (np.linalg.inv(rest[self.parent[n]]) @ rest[n]) if self.parent[n] else rest[n] for n in self.names}

    def world(self, pose):
        """Every bone's place in the character's space for a pose {"local": {bone: 3 x 3}, "pelvis": place}."""
        out = {}
        for n in self.names:
            local = self.rest[n].copy()
            local[:3, :3] = pose["local"][n]
            if n == "pelvis":
                local[:3, 3] = pose["pelvis"]
            out[n] = out[self.parent[n]] @ local if self.parent[n] else local
        return out

    def chain(self, pose, upto):
        """The place of one bone, worked out up its parents only."""
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


def aimed(basis, source, target):
    """The basis turned the short way so that `source` points along `target`."""
    a = source / np.linalg.norm(source)
    b = target / np.linalg.norm(target)
    axis = np.cross(a, b)
    s = np.linalg.norm(axis)
    if s < 1e-9:
        return basis
    return axis_angle(axis / s, math.degrees(math.atan2(s, a @ b))) @ basis


# ---- the clip ---------------------------------------------------------------------------------------------------


class Rack:
    """What the clip is made from, for one body: the pose it joins, that body's hold (the seat, the wrist's turn,
    the support grip, the hand poses) and its left hand's place and fingers on the slide. The clip is keyed from
    the female's; the male's gives his hand's way and fingers, which the game puts on over the clip."""

    def __init__(self, rig, join, hold, solved):
        self.rig, self.join = rig, join
        self.seat = hold["seat"]
        self.turn = np.eye(4)
        self.turn[:3, :3] = quat_to_mat(hold["grip"]["turns"]["hand_r"])
        self.slide_hand = np.array(solved["slide_hand"])
        self.travel = np.array(solved["travel"])
        self.grip = {n: quat_to_mat(q) for n, q in solved["rack"].items()}
        self.open = {n: quat_to_mat(q) for n, q in solved["rack_open"].items()}
        world = rig.world(join)
        # The hand bone to the pistol: the hold's turn of the wrist, then the seat.
        self.to_gun = self.turn @ self.seat
        self.gun0 = world["hand_r"] @ self.to_gun
        self.left0 = np.linalg.inv(self.gun0) @ world["hand_l"]
        self.support = hold["support_hand"]
        self.way_off = hold["support_way"]
        self.right_grip = {n: quat_to_mat(q) for n, q in hold["grip"]["rotations"].items()}
        self.support_grip = {n: quat_to_mat(q) for n, q in hold["support"]["rotations"].items()}
        self.let_go = {n: quat_to_mat(q) for n, q in hold["open"]["rotations"].items()}
        self.solved = solved
        # Where the library's pose has the elbows: a reach with its own elbow as the pole gives the pose back.
        self.elbow0 = {}
        for side in ("l", "r"):
            shoulder, elbow, wrist = (world[f"{bone}_{side}"][:3, 3] for bone in ("upperarm", "lowerarm", "hand"))
            along = (wrist - shoulder) / np.linalg.norm(wrist - shoulder)
            foot = shoulder + along * ((elbow - shoulder) @ along)
            self.elbow0[side] = elbow + (elbow - foot) * 2.0
        self.elbow0["l"] = tuple(self.elbow0["l"])
        self.left_keys_in, self.left_keys_out = self._left_keys()
        self.ease = {}

    def gun(self, frame):
        """The pistol's place in the character's space on a frame."""
        keys = [(k[0], np.array(k[1] + k[2]), k[3]) for k in GUN_KEYS]
        left, up, forward, roll, pitch, yaw = spline(keys, frame)
        turn = np.eye(4)
        # The pistol's axes: the barrel is its X (the muzzle at -X), up its Y, its left its Z.
        turn[:3, :3] = axis_angle(Y, yaw) @ axis_angle(Z, pitch) @ axis_angle(X, roll)
        out = self.gun0 @ turn
        out[:3, 3] = self.gun0[:3, 3] + np.array([left, up, forward])
        return out

    def pull(self, frame):
        """How far back the gripping hand has the slide, 0 to 1."""
        return smoothstep(PULL[0], PULL[1], frame)

    def on_slide(self, frame):
        place = self.slide_hand.copy()
        place[:3, 3] = place[:3, 3] + self.travel * self.pull(frame)
        return place

    def _left_keys(self):
        """The left hand's places in the pistol's space on its way in and on its way back, and its elbow's."""
        over = moved(self.slide_hand, self.solved["over_move"])
        follow = moved(self.slide_hand, self.travel + np.array(FOLLOW_MOVE))
        swing_in = moved(over, SWING_MOVE)
        # Back the way it came: the way off the support grip is clear of the right hand, a shorter one is not.
        swing_back = swing_in
        clear = moved(self.support, self.way_off * CLEAR_FAR)
        # The way's far end, where the hold has the hand as it lets it go and as it takes it again.
        far = moved(self.support, self.way_off)
        let_go_at = frame_at(LEAVE, 1.0 - ARM_UNTIL)
        taken_at = frame_at(BACK, ARM_UNTIL)
        way_in = [
            (0.0, self.left0, True),
            (AT_SUPPORT, self.support, True),
            (let_go_at, far, True),
            (LEAVE[1], far, True),
            (CLEAR_AT, clear, False),
            (SWING_IN_AT, swing_in, False),
            (OVER, over, True),
            (CLOSE_AT, self.slide_hand, True),
        ]
        pulled = self.slide_hand.copy()
        pulled[:3, 3] = pulled[:3, 3] + self.travel
        way_out = [
            (PULL[1], pulled, True),
            (FOLLOW, follow, False),
            (SWING_BACK_AT, swing_back, False),
            (CLEAR_BACK_AT, clear, False),
            (RETURNED, far, True),
            (taken_at, far, True),
            (BACK[1], self.support, True),
            (float(FRAMES), self.left0, True),
        ]
        self.elbow_keys = [
            (0.0, self.elbow0["l"], True),
            (AT_SUPPORT, SUPPORT_ELBOW, True),
            (LEAVE[1], SUPPORT_ELBOW, True),
            (SWING_IN_AT, LEFT_ELBOW, True),
            (SWING_BACK_AT, LEFT_ELBOW, True),
            (RETURNED, SUPPORT_ELBOW, True),
            (BACK[1], SUPPORT_ELBOW, True),
            (float(FRAMES), self.elbow0["l"], True),
        ]
        return way_in, way_out

    def left(self, frame):
        """The left hand bone's place in the pistol's space on a frame."""
        if frame <= GRIP[1]:
            return place_spline(self.left_keys_in, frame)
        if frame <= PULL[1]:
            return self.on_slide(frame)
        return place_spline(self.left_keys_out, frame)

    def way_weight(self, frame):
        """How free the hand's turn is, 0 to 1: all of it between the support grip and the slide, none where
        the hand holds either."""
        # Not before the hand is at the far end of its clear line off the support grip: turned nearer the gun,
        # its fingers went 5.6 mm into the right hand.
        to_slide = smoothstep(CLEAR_AT, SWING_IN_AT, frame) * (1.0 - smoothstep(OVER, CLOSE_AT, frame))
        back = smoothstep(RELEASE[0], FOLLOW, frame) * (1.0 - smoothstep(SWING_BACK_AT, CLEAR_BACK_AT, frame))
        return max(to_slide, back)

    def place(self, frame):
        """The left hand bone's place in the pistol's space on a whole frame, as the clip has it: `left()` with
        the hand turned toward the forearm on the way (`WAY_WRIST`; the turns are found while the clip's body
        is posed, on the body it is keyed on, and every body takes them)."""
        out = self.left(frame).copy()
        turn = self.ease.get(round(frame))
        if turn is not None:
            out[:3, :3] = turn @ out[:3, :3]
        return out

    def fingers(self, frame, name):
        """A left finger bone's rotation in its parent on a frame: the library's, opened at the support grip (the
        hold's own opened hand), opened over the slide, closed on it, opened again as the slide is let go, and
        back the same way."""
        own, let_go, opened, grip = self.join["local"][name], self.let_go[name], self.open[name], self.grip[name]
        keys = [
            (0.0, own),
            (AT_SUPPORT, let_go),
            (LEAVE[1], let_go),
            (CLEAR_AT, let_go),
            (OVER, opened),
            (CLOSE_AT, opened),
            (GRIP[1], grip),
            (RELEASE[0], grip),
            (RELEASE[1], opened),
            (FOLLOW, opened),
            (CLEAR_BACK_AT, let_go),
            (RETURNED, let_go),
            (BACK[1], let_go),
            (float(FRAMES), own),
        ]
        for (start, a), (end, b) in zip(keys, keys[1:]):
            if frame <= end:
                return slerp(a, b, smoothstep(start, end, frame))
        return own

    def support_weight(self, frame):
        """How far the hold has the left hand on its support grip (`SupportHand`): at the clip's ends."""
        return max(1.0 - smoothstep(LEAVE[0], LEAVE[1], frame), smoothstep(BACK[0], BACK[1], frame))

    def hand_weight(self, frame):
        """How far the game's reach has the left hand on its way over the slide (the rest is the clip's own
        arm): all of it from the frame the hand is over the slide to the end of its follow-through."""
        return smoothstep(SWING_IN_AT, OVER, frame) * (1.0 - smoothstep(FOLLOW, SWING_BACK_AT, frame))

    def pose(self, frame):
        """The whole body on a frame, and what was measured while solving it."""
        rig = self.rig
        pose = {"local": dict(self.join["local"]), "pelvis": self.join["pelvis"]}
        lean = spline([(f, [v], True) for f, v in BODY_KEYS], frame)[0]
        world = rig.world(pose)
        for name, degrees in (("spine_02", SPINE_PITCH), ("spine_03", SPINE_PITCH), ("Head", HEAD_PITCH)):
            # Forward about the character's left (+X): the turn is put on in the character's space.
            above = rig.chain(pose, rig.parent[name])[:3, :3]
            pose["local"][name] = above.T @ axis_angle(X, degrees * lean) @ above @ pose["local"][name]
        gun = self.gun(frame)
        short_r = reach(rig, pose, "r", gun @ np.linalg.inv(self.to_gun), self.elbow0["r"])
        left = gun @ self.left(frame)
        elbow = spline(self.elbow_keys, frame)
        short_l = reach(rig, pose, "l", left, elbow)
        loose = self.way_weight(frame)
        if loose > 0.0:
            # The wrist's place gives the arm; the hand's turn is free on the way, so it follows the forearm.
            world = rig.world(pose)
            fore = world["hand_l"][:3, 3] - world["lowerarm_l"][:3, 3]
            fore = fore / np.linalg.norm(fore)
            along = world["hand_l"][:3, 1]
            bend = math.degrees(math.acos(min(max(fore @ along, -1.0), 1.0)))
            excess = loose * max(bend - WAY_WRIST, 0.0)
            if excess > 0.0:
                turn = axis_angle(np.cross(along, fore), excess)
                # The same turn in the pistol's space, for the hand's way the game reaches it along.
                self.ease[round(frame)] = gun[:3, :3].T @ turn @ gun[:3, :3]
                left = gun @ self.place(frame)
                reach(rig, pose, "l", left, elbow)
        for name in self.grip:
            pose["local"][name] = self.fingers(frame, name)
        world = rig.world(pose)
        fore = world["hand_l"][:3, 3] - world["lowerarm_l"][:3, 3]
        fore = fore / np.linalg.norm(fore)
        pose["numbers"] = {
            "short_r": short_r,
            "short_l": short_l,
            "wrist_l": math.degrees(math.acos(min(max(fore @ world["hand_l"][:3, 1], -1.0), 1.0))),
            "gun": gun,
            "left_in_gun": self.place(frame),
        }
        return pose


# ---- Blender ----------------------------------------------------------------------------------------------------


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="BLENDER")
    new = [o for o in bpy.data.objects if o not in before]
    return next(o for o in new if o.type == "ARMATURE"), new


def library_pose(path, clip, last=True):
    """A library clip's last (or first) frame as each bone's rotation in its parent and the pelvis's place there,
    then the library is removed. Godot plays a clip this way on a model's own bone lengths."""
    arm, objects = import_glb(path)
    action = bpy.data.actions[clip]
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    first, end = (round(f) for f in action.frame_range)
    bpy.context.scene.frame_set(end if last else first)
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
    return {"local": local, "pelvis": pelvis, "frames": end - first}


def key_clip(arm, rig, name, frames, bones):
    """Key a clip on the armature: the rotation of every bone of `bones` on every frame, and the pelvis's place."""
    action = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = action
    last = {}
    for f, pose in enumerate(frames):
        for pb in arm.pose.bones:
            n = pb.name
            if n not in bones:
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
    """The armature and its clip as a glb: a one-triangle mesh skinned to the root stands in for the model, so the
    file has a skin (Godot makes its `Skeleton3D` from it) and no copy of the mannequin."""
    mesh = bpy.data.meshes.new("PistolClips")
    mesh.from_pydata([(0, 0, 0), (0.01, 0, 0), (0, 0, 0.01)], [], [(0, 1, 2)])
    proxy = bpy.data.objects.new("PistolClips", mesh)
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


def local_of(body, name):
    """A bone's rotation in its parent as the body is posed now (its rest there times what the pose adds)."""
    return np.array(body.rest_rel[name] @ body.arm.pose.bones[name].matrix_basis)[:3, :3]


def turn_to(body, name, rotation, weight=1.0):
    """Turns a bone to a rotation in its parent, by `weight` of the way from where the pose has it."""
    rest = np.array(body.rest_rel[name])
    step = rest.copy()
    step[:3, :3] = slerp(local_of(body, name), rotation, weight) if weight < 1.0 else rotation
    body.arm.pose.bones[name].matrix_basis = Matrix((np.linalg.inv(rest) @ step).tolist())


def body_reach(body, goal, elbow, weight):
    """The game's `HoldArm` on a measured body: brings the left hand to `goal` (a place in the character's
    space) by `weight`. Returns how far the hand was from it, in metres."""
    bones = body.arm.pose.bones
    names = ["upperarm_l", "lowerarm_l", "hand_l"]
    bpy.context.view_layer.update()
    above = np.linalg.inv(C) @ np.array(bones["clavicle_l"].matrix)
    rest = {n: np.array(body.rest_rel[n]) for n in names}

    class Arm:
        """The three bones of the arm as a rig of their own, hanging from the collarbone."""

        parent = {names[0]: "clavicle_l", names[1]: names[0], names[2]: names[1]}

        def chain(self, pose, upto):
            out = above.copy()
            for n in names if upto != "clavicle_l" else []:
                step = rest[n].copy()
                step[:3, :3] = pose["local"][n]
                out = out @ step
                if n == upto:
                    break
            return out

    arm = Arm()
    arm.rest = rest
    pose = {"local": {n: local_of(body, n) for n in names}}
    off = float(np.linalg.norm(arm.chain(pose, "hand_l")[:3, 3] - goal[:3, 3]))
    if weight > 0.0:
        reached = {"local": dict(pose["local"])}
        reach(arm, reached, "l", goal, elbow)
        for n in names:
            turn_to(body, n, reached["local"][n], weight)
    bpy.context.view_layer.update()
    return off


def held(body, rack, frame):
    """Poses a measured body as the game draws it on a frame of the clip, from the body's own `rack`: the hold's
    right hand (the wrist's turn, the fingers on the grip), the left hand on its support grip at the clip's ends
    (the hold's reach to `SupportHand` and its fingers), the body's own fingers for the rack wherever the hand
    is off that grip, and the left hand reached to its place on the slide by as much as the game holds it
    there. Returns how far the clip's own left hand was from the slide's place, in metres."""
    bones = body.arm.pose.bones
    bones["hand_r"].matrix_basis = bones["hand_r"].matrix_basis @ Matrix(rack.turn.tolist())
    for name, rotation in rack.right_grip.items():
        turn_to(body, name, rotation)
    bpy.context.view_layer.update()
    gun = np.linalg.inv(C) @ np.array(bones["hand_r"].matrix) @ rack.seat
    on_support = rack.support_weight(frame)
    off = body_reach(body, gun @ rack.place(frame), LEFT_ELBOW, 0.0)
    # The hold's plan: its arm has the hand on the grip or out along its way, the fingers opened on the way.
    arm, way, opened = hold_plan(on_support)
    if arm > 0.0:
        body_reach(body, gun @ moved(rack.support, rack.way_off * way), SUPPORT_ELBOW, arm)
        for name, rotation in rack.support_grip.items():
            turn_to(body, name, slerp(rotation, rack.let_go[name], opened) if name in rack.let_go else rotation, arm)
    if on_support < 1.0:
        # The rack's own fingers come after the hold's, by what the hold does not have the hand on its grip.
        for name in rack.grip:
            turn_to(body, name, rack.fingers(frame, name), 1.0 - on_support)
    body_reach(body, gun @ rack.place(frame), LEFT_ELBOW, rack.hand_weight(frame))
    return off


def pose_gap(a, b):
    """The largest turn between two poses' bones, in degrees, and how far their pelvises are apart."""
    worst = 0.0
    for n in b["local"]:
        # By the distance between the two matrices: an arc cosine near 1 turns rounding into a twentieth of a degree.
        apart = np.linalg.norm(a["local"][n] - b["local"][n]) / (2.0 * math.sqrt(2.0))
        worst = max(worst, math.degrees(2.0 * math.asin(min(apart, 1.0))))
    return worst, float(np.linalg.norm(a["pelvis"] - b["pelvis"]))


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    here = Path(__file__).resolve().parent
    bodies = GAME / "assets" / "characters" / "prototype"
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=str(bodies / "form_female.glb"), help="the body the clip is keyed on")
    parser.add_argument("--male", default=str(bodies / "form_male.glb"))
    parser.add_argument("--library", default=str(GAME / "assets" / "animation" / "universal" / "ual1.glb"))
    parser.add_argument("--hand", default=str(here / "rack_hand.json"))
    parser.add_argument("--out", required=True)
    parser.add_argument("--data", help="write what the game's reach needs (the SlideRack resource's numbers)")
    parser.add_argument("--report")
    parser.add_argument("--preview", action="store_true", help="export even when a check fails, to look at it")
    parser.add_argument("--arms-only", action="store_true", help="skip the limb check and the export (tuning)")
    parser.add_argument("--check", action="store_true", help="compare with the files on disk, write nothing")
    args = parser.parse_args(argv)
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # clip_check.py
    sys.dont_write_bytecode = True  # Blender ignores PYTHONDONTWRITEBYTECODE
    import clip_check

    checking = clip_check.Check(args.check)
    args.out = checking.file(args.out)
    args.data = checking.file(args.data)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    join = library_pose(args.library, JOIN_CLIP)
    first = library_pose(args.library, JOIN_CLIP, last=False)
    arm, objects = import_glb(args.model)
    for obj in objects:
        if obj is not arm:
            bpy.data.objects.remove(obj)
    rig = Rig(arm)
    # The clip keys the library's bones; a bone the library does not have (the prototype rig's leaves: twist
    # bones, sockets, IK targets) stays at its rest and gets no key.
    library_bones = set(join["local"])
    for pose in (join, first):
        for name in rig.names:
            pose["local"].setdefault(name, rig.rest[name][:3, :3])
    solved = json.loads(Path(args.hand).read_text(encoding="utf-8"))
    racks = {name: Rack(rig, join, hold_files.read(GAME, name), solved[name]) for name in ("female", "male")}
    rack = racks["female"]
    frames = [rack.pose(float(f)) for f in range(FRAMES + 1)]
    for each in racks.values():
        each.ease = rack.ease

    failures = []
    report = {"fps": FPS, "frames": FRAMES, "seconds": round(FRAMES / FPS, 4), "per_frame": []}
    for f, pose in enumerate(frames):
        numbers = pose["numbers"]
        report["per_frame"].append(
            {
                "frame": f,
                "right_short_mm": round(numbers["short_r"] * 1000.0, 2),
                "left_short_mm": round(numbers["short_l"] * 1000.0, 2),
                "left_wrist_degrees": round(numbers["wrist_l"], 1),
                "pull": round(rack.pull(f), 3),
                "hand_weight": round(rack.hand_weight(f), 3),
            }
        )
        if max(numbers["short_r"], numbers["short_l"]) > 0.0005:
            failures.append(f"frame {f}: an arm stops short of its hand's place")
        if GRIP[1] <= f <= PULL[1] and numbers["wrist_l"] > WRIST_LIMIT:
            failures.append(f"frame {f}: the left wrist bends {numbers['wrist_l']:.0f} degrees")
    joins = {
        "starts on the reload's last frame": pose_gap(frames[0], join),
        "ends on the reload's last frame": pose_gap(frames[-1], join),
        "the reload's last frame is its first": pose_gap(join, first),
    }
    report["joins"] = {k: [round(v[0], 4), round(v[1], 5)] for k, v in joins.items()}
    worst = sorted(
        (
            (pose_gap({"local": frames[0]["local"], "pelvis": join["pelvis"]}, {"local": {n: join["local"][n]}, "pelvis": join["pelvis"]})[0], n)
            for n in library_bones
        ),
        reverse=True,
    )[:4]
    print("JOIN worst bones", worst)
    for what, (turn, apart) in joins.items():
        if turn > 0.05 or apart > 0.0005:
            failures.append(f"{what}: off by {turn:.3f} degrees and {apart:.4f} m")

    if args.arms_only:
        print("ARMS", json.dumps(report["per_frame"]))
        print("ARMS failures:", "; ".join(failures) or "none")
        return
    action = key_clip(arm, rig, CLIP, frames, library_bones)

    # Limbs through each other, on both mannequins' skinned meshes as the game draws them, on every frame.
    sys.path.insert(0, str(here.parent))
    import limb_overlap

    bodies = [limb_overlap.load_body(args.model, "female"), limb_overlap.load_body(args.male, "male")]
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    report["overlap_mm"] = {
        body.name: {"deepest": 0.0, "frame": None, "pair": None, "pairs": {}, "support_grip": 0.0, "frames": []}
        for body in bodies
    }
    report["clip_hand_off_mm"] = {body.name: [] for body in bodies}
    for f in range(FRAMES + 1):
        bpy.context.scene.frame_set(f)
        for body in bodies:
            body.pose_from(arm)
            off = held(body, racks[body.name], float(f))
            report["clip_hand_off_mm"][body.name].append(round(off * 1000.0, 1))
            entry = report["overlap_mm"][body.name]
            entry["frames"].append(0.0)
            for (a, b), (depth, _place) in body.overlaps().items():
                mm = round(depth * 1000.0, 1)
                pair = f"{a} in {b}"
                if rack.support_weight(float(f)) >= 1.0 and {a, b} == {"hand_l", "hand_r"}:
                    # The hold has the left hand on its support grip, over the right hand's fingers: the two
                    # hands touch there by the hold's own solve, which its test measures (2 mm, `HandContact`;
                    # this check reads touching hands several millimetres deeper). It is the hold's number,
                    # reported and not judged here; every frame on which the rack moves the hand is.
                    entry["support_grip"] = max(entry["support_grip"], mm)
                    continue
                entry["frames"][-1] = max(entry["frames"][-1], mm)
                if mm > entry["pairs"].get(pair, [0.0])[0]:
                    entry["pairs"][pair] = [mm, f]
                if mm > entry["deepest"]:
                    entry.update(deepest=mm, frame=f, pair=pair)
    arm.animation_data.action = None
    for body in bodies:
        entry = report["overlap_mm"][body.name]
        print(
            f"OVERLAP {CLIP} {body.name}: {entry['deepest']} mm at frame {entry['frame']} ({entry['pair']});"
            f" the hold's support grip at the clip's ends reads {entry['support_grip']} mm"
        )
        if entry["deepest"] > OVERLAP_LIMIT:
            failures.append(
                f"on the {body.name}: {entry['pair']} by {entry['deepest']} mm at frame {entry['frame']}"
                f" (the limit is {OVERLAP_LIMIT} mm); all: {entry['pairs']}"
            )
        if max(report["clip_hand_off_mm"]["female"][round(GRIP[1]) : round(PULL[1]) + 1]) > 0.5:
            failures.append("the clip's own left hand is off the slide on the female body")
        for obj in body.objects:
            bpy.data.objects.remove(obj)

    first_place, last_place = math.floor(SWING_IN_AT), math.ceil(SWING_BACK_AT)
    data = {
        "clip": f"pistol/{CLIP}",
        "length": FRAMES / FPS,
        "travel": rack.travel.tolist(),
        "elbow": list(LEFT_ELBOW),
        "places_from": first_place / FRAMES,
        "places_to": last_place / FRAMES,
        "reach": [SWING_IN_AT / FRAMES, OVER / FRAMES],
        "away": [FOLLOW / FRAMES, SWING_BACK_AT / FRAMES],
        "leave": [LEAVE[0] / FRAMES, LEAVE[1] / FRAMES],
        "fingers_over": [CLEAR_AT / FRAMES, OVER / FRAMES],
        "grip": [GRIP[0] / FRAMES, GRIP[1] / FRAMES],
        "fingers_close": CLOSE_AT / FRAMES,
        "pull": [PULL[0] / FRAMES, PULL[1] / FRAMES],
        "release": [RELEASE[0] / FRAMES, RELEASE[1] / FRAMES],
        "slam": SLAM / FRAMES,
        "fingers_away": [FOLLOW / FRAMES, CLEAR_BACK_AT / FRAMES],
        "back": [BACK[0] / FRAMES, BACK[1] / FRAMES],
        # What differs from body to body: the hand's place on the slide, its way there and back, its fingers.
        "bodies": {
            name: {
                "hand": each.slide_hand.tolist(),
                "places": [each.place(float(f)).tolist() for f in range(first_place, last_place + 1)],
                "grip": each.solved["rack"],
                "open": each.solved["rack_open"],
            }
            for name, each in racks.items()
        },
    }
    report["data"] = data
    print("REPORT", json.dumps(report, indent=1))
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8", newline="\n")
    if failures:
        print("BUILD FAILED\n  " + "\n  ".join(failures))
        if not args.preview:
            raise SystemExit(1)
    if args.data:
        Path(args.data).write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8", newline="\n")
    export(arm, args.out)
    print("EXPORTED", args.out)
    checking.finish()


if __name__ == "__main__":
    main()
