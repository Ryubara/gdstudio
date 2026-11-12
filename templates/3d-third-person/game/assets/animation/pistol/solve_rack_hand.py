"""Solves where the left hand grips the pistol's slide for the rack clip (kit #1081), one body at a time.

    <godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
    uv run --no-project --with numpy --with scipy python assets/animation/pistol/solve_rack_hand.py
        <abs>/rig.json <abs>/rack_hand.json --body=female|male [--search] [--place=dx,dy,dz,rx,ry,rz]

Each body has its own grip, as each has its own hold (kit #1187): the prototype bodies' hands are a person's size
and differ (0.181 m and 0.195 m from wrist to fingertip), so a place and finger curls solved on one hand leave the
other's palm off the slide and its fingertips inside it. The result file holds one entry a body; a run replaces
its body's and keeps the other.

An overhand rack: the left hand comes over the top of the slide from the gun's left, palm down, just in front of
the rear sight, the four fingers down the slide's right side and the thumb down its left, pointing back at the
shooter. This works out the hand bone's place in the pistol's space and every finger bone's rotation, measured
on the body's skinned hand against the pistol's closed pieces and the right hand as the game's hold has it on
that body (`tools/hold/hold_files.py`: the hold scene's own files for the female, `pistol_fit_male.tres` for the
male; the trigger finger along the frame). It reads the hold and never changes it: the rig, the skinning and the
distance grid are the hold tools' (`tools/hold/hold_rig.py`, `hold_hand.py`, `hold_field.py`), the dump is
`tools/hold/dump_hold_rig.gd`'s.

It then walks the gripping hand back along the slide's travel (+X) and measures it against what stays (the
frame, the hammer, the right hand), and writes the hand opened (for the reach and the release) beside the grip.
`build_pistol_rack.py` keys the clip from the file this writes. With no option it solves the fingers at `PLACE`
(four minutes the first time, most of it the two distance grids it keeps beside the dump); `--search` searches
the place again from there (ten minutes).
"""

import itertools
import json
import struct
import sys
import time
from pathlib import Path

import numpy as np

GAME = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(GAME / "tools" / "hold"))

import hold_field  # noqa: E402
import hold_files  # noqa: E402
import hold_rig as R  # noqa: E402
from hold_hand import FINGERS, LIMITS, Hand  # noqa: E402

BASE_POSE = "ual1/Pistol_Aim_Neutral@0.16"
TARGET = -0.0008  # how far into the surface the skin is pressed, metres (the hold's own)
TOL = 0.0012  # how deep the solver lets skin go (the test allows 2 mm)
# The pistol in Godot: the muzzle along -X, up +Y, its left +Z. The slide's box runs from x -0.202 to 0.008,
# y 0.088 to 0.133 and z -0.02 to 0.02; the rear sight stands on its last 12 mm.
SLIDE_TOP = 0.133
SLIDE_BOTTOM = 0.088
SLIDE_HALF = 0.02
SLIDE_REAR = 0.008
REAR_SIGHT_FRONT = -0.012
# The serrations on the slide's two sides, along the barrel (the model's build: three bars at the rear): the
# index finger closes on the right side's and the thumb on the left side's.
SERRATIONS = (-0.030, -0.006)
# The slide's travel (the model's README: Deadnight moves it 0.05 m at a shot).
TRAVEL = 0.045
# The shares of the travel at which the gripping hand is measured against what stays behind (the hammer and
# the right hand's thumb are where the slide's rear and the hand on it arrive).
PULL_STEPS = (0.1, 0.2, 0.35, 0.5, 0.65, 0.8, 0.9, 1.0)
# The hand bone's place on the closed slide, as a move from `start_place()`: metres along the pistol's axes,
# then degrees about them (about the middle of the slide's top under the palm). One a body, each found by
# `--search`.
PLACES = {
    "female": [-0.014, -0.016, 0.008, 16.0, -18.0, -10.0],
    "male": [-0.007, -0.016, 0.012, 24.0, -18.0, -2.0],
}
PIVOT = np.array([-0.05, SLIDE_TOP, 0.0])
GRID_LOW = [-0.24, -0.09, -0.075]
GRID_HIGH = [0.08, 0.17, 0.075]
HAND_LOW = [-0.17, -0.09, -0.12]
HAND_HIGH = [0.10, 0.16, 0.09]
# The opened hand (over the slide before it closes, and as it lets go). The hand comes down on the slide from
# `OVER_MOVE` above its place (the pistol's space, metres; the clip's build reads it from this solver's file)
# with its fingers opened, and closes them where it lies: each finger is opened to the pose nearest its grip
# whose two outer parts are `OPEN_CLEAR` off every surface at the hand's place, at least `WAY_CLEAR` off on the
# way down, and never deeper than `TOL` while it closes.
OVER_MOVE = [0.0, 0.045, 0.03]
OPEN_CLEAR = 0.01
WAY_CLEAR = 0.001
WAY_STEPS = (0.15, 0.3, 0.45, 0.6, 0.8, 1.0)
CLOSE_STEPS = (0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875)
# The arm behind the hand, as the clip's build has it while the hand grips (`build_pistol_rack.py` prints the
# wrist's bend and fails over 45 degrees): the line of the left forearm in the pistol's space, elbow to wrist,
# and how far up the barrel the wrist may be. A search that knew nothing of the arm put the wrist 11 cm up the
# barrel with the fingers reaching back to the serrations: the wrist bent 43 degrees and the male's arm stopped
# 8 to 10 mm short of the place.
FOREARM = np.array([-0.31, 0.68, -0.67]) / np.linalg.norm([-0.31, 0.68, -0.67])
WRIST_FRONT = -0.09
X, Y, Z = np.eye(3)


def relu(x):
    return np.maximum(x, 0.0)


def glb_triangles(path, under):
    """The triangles of every mesh under the node `under` of a glb, in the root node's space: (N, 3, 3)."""
    data = Path(path).read_bytes()
    length = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20 : 20 + length])
    binary = data[20 + length + 8 :]

    def accessor(index):
        acc = doc["accessors"][index]
        view = doc["bufferViews"][acc["bufferView"]]
        kind = {5126: "<f4", 5123: "<u2", 5125: "<u4", 5121: "<u1"}[acc["componentType"]]
        width = {"SCALAR": 1, "VEC3": 3}[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        flat = np.frombuffer(binary, kind, acc["count"] * width, start)
        return flat.reshape(-1, width) if width > 1 else flat

    def local(node):
        m = np.eye(4)
        if "matrix" in node:
            return np.array(node["matrix"], float).reshape(4, 4).T
        if "rotation" in node:
            m[:3, :3] = R.quat_to_mat(node["rotation"])
        if "scale" in node:
            m[:3, :3] = m[:3, :3] * np.array(node["scale"], float)
        if "translation" in node:
            m[:3, 3] = node["translation"]
        return m

    out = []

    def walk(index, above, inside):
        node = doc["nodes"][index]
        here = above @ local(node)
        inside = inside or node.get("name") == under
        if inside and "mesh" in node:
            for primitive in doc["meshes"][node["mesh"]]["primitives"]:
                points = accessor(primitive["attributes"]["POSITION"]).astype(float)
                points = points @ here[:3, :3].T + here[:3, 3]
                out.append(points[accessor(primitive["indices"]).astype(int)].reshape(-1, 3, 3))
        for child in node.get("children", []):
            walk(child, here, inside)

    for root in doc["scenes"][doc.get("scene", 0)]["nodes"]:
        # The root node is the pistol itself (Godot makes it the scene's root): its children are in its space.
        for child in doc["nodes"][root].get("children", []):
            walk(child, np.eye(4), False)
    return np.concatenate(out)


class Scene:
    """One body's hands, the right one on the pistol as the game's hold has it on that body."""

    def __init__(self, rig, pistol, cache, hold, slide_tris):
        self.rig = rig
        self.gun_tris = np.array(pistol["triangles"]).reshape(-1, 3, 3)
        self.gun = hold_field.PiecesField(self.gun_tris, GRID_LOW, GRID_HIGH, 0.001, cache + ".gun.npz")
        # What stays where it is while the slide runs back: the frame, the hammer, the sights of the frame.
        slide_keys = {tuple(np.round(t.mean(axis=0) * 1e5).astype(int)) for t in slide_tris}
        stays = [t for t in self.gun_tris if tuple(np.round(t.mean(axis=0) * 1e5).astype(int)) not in slide_keys]
        print(f"the slide is {len(self.gun_tris) - len(stays)} of the pistol's {len(self.gun_tris)} triangles", flush=True)
        self.stays = hold_field.PiecesField(np.array(stays), GRID_LOW, GRID_HIGH, 0.001, cache + ".stays.npz")
        self.seat = hold["seat"]
        grip = hold["grip"]["rotations"]
        turn = hold["grip"]["turns"]["hand_r"]
        local = rig.poses[BASE_POSE].copy()
        hand_r = rig.index["hand_r"]
        local[hand_r][:3, :3] = local[hand_r][:3, :3] @ R.quat_to_mat(turn)
        for name, q in grip.items():
            local[rig.index[name]][:3, :3] = R.quat_to_mat(q)
        self.glob = rig.fk(local)
        self.gun_global = self.glob[hand_r] @ self.seat
        under = rig.under("hand_r")
        ids = np.where(np.isin(rig.main, under))[0]
        remap = -np.ones(len(rig.verts), int)
        remap[ids] = np.arange(len(ids))
        tris = remap[rig.tris[np.isin(rig.tris, ids).all(axis=1)]]
        points = self.to_gun(rig.skin(self.glob, ids))
        self.other = []
        for index in range(rig.model.max() + 1):
            mine = rig.model[ids][tris[:, 0]] == index
            self.other.append(hold_field.PiecesField(points[tris[mine]], HAND_LOW, HAND_HIGH, 0.0015, rays=(0, 1, 2)))
        self.left = Hand(rig, "l", rig.poses[BASE_POSE])

    def to_gun(self, points):
        g = self.gun_global
        return (points - g[:3, 3]) @ g[:3, :3]

    def field(self, points, which=None):
        """The distance from the left hand's points to the pistol and the right hand of the same mannequin."""
        at = self.to_gun(points)
        d = self.gun(at)
        ids = self.left.ids if which is None else self.left.ids[which]
        model = self.rig.model[ids]
        for index, other in enumerate(self.other):
            mine = model == index
            d[..., mine] = np.minimum(d[..., mine], other(at[..., mine, :]))
        return d

    def pulled(self, points, which=None):
        """The distance from the left hand's points, carried back with the slide to each of `PULL_STEPS`, to
        what stays where it is (the frame, the hammer) and the right hand: the least over the steps."""
        at = self.to_gun(points)
        d = np.full(at.shape[:-1], np.inf)
        for step in PULL_STEPS:
            moved = at + np.array([step * TRAVEL, 0.0, 0.0])
            d = np.minimum(d, np.minimum(self.stays(moved), self.other[0](moved)))
        return d

    def put(self, in_gun):
        """Moves the left hand, as its fingers are, to a place given in the pistol's space."""
        hand = self.left
        hand.move = np.eye(4)
        hand._apply_all()
        hand.move = self.gun_global @ in_gun @ np.linalg.inv(hand.hand_global())
        hand._apply_all()


def start_place(rig):
    """The left hand bone over the slide before the search: its fingers (+Y) point across the top to the gun's
    right and a little up, its palm (+X) faces down onto the slide, its index side (+Z) is at the rear. The
    hand's own size places it: how far its knuckles are from the wrist and its index knuckle from its middle."""
    rest = rig.fk(rig.rest)
    in_hand = np.linalg.inv(rest[rig.index["hand_l"]])
    to_knuckles = float((in_hand @ rest[rig.index["middle_01_l"]])[1, 3])
    to_index = float((in_hand @ rest[rig.index["index_01_l"]])[2, 3])
    lean = np.radians(35.0)  # the wrist lower than the knuckles, the heel of the palm toward the slide's left side
    fingers = np.array([0.0, np.sin(lean), -np.cos(lean)])
    index_side = np.array([1.0, 0.0, 0.0])
    palm = np.cross(fingers, index_side)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2] = palm, fingers, index_side
    # The knuckles over the slide's top, the index knuckle just in front of the rear sight.
    knuckles = np.array([REAR_SIGHT_FRONT - 0.012 - to_index, SLIDE_TOP + 0.03, 0.004])
    m[:3, 3] = knuckles - to_knuckles * fingers
    return m


def placed(rig, params):
    turn = np.eye(4)
    turn[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    turn[:3, 3] = PIVOT - turn[:3, :3] @ PIVOT + np.array(params[:3])
    return turn @ start_place(rig)


def natural(a):
    """What a finger wrapped over the slide costs for not looking like a hand's (0.03 to 0.1 mm a degree)."""
    cost = 1e-4 * np.abs(a[:, 3] - 0.6 * a[:, 2]) + 1.5e-4 * np.abs(a[:, 0])
    return cost + 3e-5 * (np.abs(a[:, 1] - 45.0) + np.abs(a[:, 2] - 60.0) + np.abs(a[:, 3] - 35.0))


def finger_cost(scene, finger, angles):
    hand = scene.left
    pts = hand.finger_points(finger, angles)
    sd = scene.field(pts, hand.finger_verts[finger][:: hand.stride])
    base, mid, tip = hand.finger_parts(finger)
    lows = [sd[:, p].min(axis=1) for p in (base, mid, tip)]
    deep = relu(-sd.min(axis=1) - (TOL if hand.stride == 1 else TOL - 0.0004))
    cost = 100.0 * deep
    # The hand goes back with the slide: nothing of the finger may arrive in the hammer or the right hand.
    back = scene.pulled(pts, hand.finger_verts[finger][:: hand.stride])
    cost += 100.0 * relu(-back.min(axis=1) - (TOL if hand.stride == 1 else TOL - 0.0004))
    a = np.atleast_2d(angles)
    tip_at = scene.to_gun(pts[:, tip].mean(axis=1))
    mid_at = scene.to_gun(pts[:, mid].mean(axis=1))
    touch = [np.abs(low - TARGET) for low in lows]
    if finger == "thumb":
        # Down the slide's left side, pointing back at the shooter, over the right thumb and not on it.
        cost += touch[2] + 0.6 * touch[1]
        cost += relu(SLIDE_HALF - tip_at[:, 2]) + relu(SLIDE_BOTTOM + 0.008 - tip_at[:, 1])
        # Its pad on the side's face by the serrations, not over the top's edge and not past the slide's rear
        # (the thumb's root is at the rear, so its tip lies at or behind the serrations' last bar).
        cost += relu(tip_at[:, 1] - (SLIDE_TOP - 0.006)) + relu(tip_at[:, 0] - SLIDE_REAR + 0.006)
        cost += 0.2 * relu(SERRATIONS[0] - tip_at[:, 0])
        cost += 0.3 * relu(mid_at[:, 0] - tip_at[:, 0])
        cost += 2e-4 * relu(a[:, 5] - 45.0) + 3e-5 * np.abs(a[:, :3]).sum(axis=1)
        # Laid along the slide's side, not hooked onto it: its middle part on the side's face too (not under
        # the slide, on the frame or the right thumb), and its two joints nearly straight.
        cost += relu(SLIDE_HALF - mid_at[:, 2]) + relu(SLIDE_BOTTOM + 0.004 - mid_at[:, 1])
        cost += 1.5e-4 * (relu(a[:, 4] - 20.0) + relu(a[:, 5] - 20.0))
    else:
        # Over the top and down the right side, the pad on the side's face above the frame.
        cost += touch[2] + 0.6 * touch[1] + natural(a)
        cost += relu(tip_at[:, 2] + SLIDE_HALF) + relu(SLIDE_BOTTOM + 0.006 - tip_at[:, 1])
        cost += relu(tip_at[:, 1] - (SLIDE_TOP - 0.008))
        if finger == "index":
            # The index finger's pad on the middle of the serrations, so the middle finger's is at their front.
            cost += 0.5 * relu(np.abs(tip_at[:, 0] - np.mean(SERRATIONS)) - 0.004)
    return cost, {"base": lows[0], "mid": lows[1], "tip": lows[2], "deep": deep}


def start_grid(finger):
    if finger == "thumb":
        root = [-30.0, 0.0, 30.0]
        return np.array(list(itertools.product(root, root, root, [0.0], [0, 25, 50], [0, 30, 60])), float)
    return np.array(list(itertools.product([0.0], range(-10, 96, 15), range(0, 111, 15), range(0, 81, 20))), float)


def solve_finger(scene, finger, quick=False, start=None):
    limits = LIMITS.get(finger, LIMITS["finger"])
    grid = start_grid(finger)
    if start is not None:
        grid = np.concatenate([grid, np.atleast_2d(start)])
    cost, _ = finger_cost(scene, finger, grid)
    best, best_cost = grid[cost.argmin()], cost.min()
    dims = len(best)
    rng = np.random.default_rng(1)
    for scale in (8.0, 4.0, 2.0, 1.0) if quick else (8.0, 4.0, 2.0, 1.0, 0.5, 0.25):
        for _ in range(1 if quick else 3):
            steps = np.concatenate([np.eye(dims), -np.eye(dims), rng.integers(-1, 2, size=(60 if quick else 200, dims))])
            cands = np.clip(best + scale * steps, limits[:, 0], limits[:, 1])
            cost, _ = finger_cost(scene, finger, cands)
            if cost.min() < best_cost:
                best_cost, best = cost.min(), cands[cost.argmin()]
    return best, best_cost


def close(scene, quick=False):
    hand = scene.left
    total = 0.0
    for _ in range(1 if quick else 2):
        total = 0.0
        for finger in FINGERS:
            best, cost = solve_finger(scene, finger, quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
    palm = scene.field(hand.points(hand.part["palm"]), hand.part["palm"])
    back = scene.pulled(hand.points(hand.part["palm"]), hand.part["palm"])
    return total + 3.0 * abs(palm.min() - TARGET) + 100.0 * relu(-palm.min() - TOL) + 100.0 * relu(-back.min() - TOL)


def score(scene, params, quick=True):
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    in_gun = placed(scene.rig, params)
    scene.put(in_gun)
    return close(scene, quick) + arm_cost(in_gun)


def arm_cost(in_gun):
    """What a place costs the arm that has to hold the hand there: a wrist bent from the forearm's line, and a
    wrist too far up the barrel for the arm to reach."""
    bend = np.degrees(np.arccos(np.clip(in_gun[:3, 1] @ FOREARM, -1.0, 1.0)))
    return 4e-4 * relu(bend - 20.0) + 0.1 * relu(WRIST_FRONT - in_gun[0, 3])


def search(scene, start, rounds):
    best = np.array(start, float)
    clock = time.time()
    best_cost = score(scene, best)
    print("one score takes %.1f s" % (time.time() - clock), flush=True)
    print("place start", np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    for step_m, step_deg in rounds:
        improved = True
        while improved:
            improved = False
            for k in range(6):
                for sign in (-1.0, 1.0):
                    cand = best.copy()
                    cand[k] += sign * (step_m if k < 3 else step_deg)
                    cost = score(scene, cand)
                    if cost < best_cost - 1e-6:
                        best, best_cost, improved = cand, cost, True
            print("  step", step_m, step_deg, np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    return best


def table(scene, tag):
    """Each part's distance to the pistol and the right hand, in millimetres (negative: inside)."""
    hand = scene.left
    sd = scene.field(hand.points())
    row = {part: round(float(sd[idx].min()) * 1000.0, 2) for part, idx in hand.part.items()}
    print(tag, ", ".join(f"{part} {value:.1f}" for part, value in row.items()), flush=True)
    return row


def tips(scene):
    """Where each fingertip's skin is in the pistol's space, in millimetres: along the barrel (the serrations
    are from -30 to -6), up (the slide's side is from 88 to 133) and to the gun's left (its sides are at 20)."""
    hand = scene.left
    out = {}
    for finger in FINGERS:
        at = scene.to_gun(hand.points(hand.part[finger + "_tip"])).mean(axis=0) * 1000.0
        out[finger] = [round(float(v), 1) for v in at]
        print("  tip", finger, out[finger], flush=True)
    return out


def open_cost(scene, finger, angles, grip):
    """What each row of angles costs as the finger's opened pose, the hand at its place on the slide: how far it
    is from the grip, and what it lacks of clear (at the place, on the way down from over the slide, and while
    it closes from this pose to the grip)."""
    hand = scene.left
    which = hand.finger_verts[finger]
    a = np.atleast_2d(angles)
    pts = hand.finger_points(finger, a)
    sd = scene.field(pts, which)
    # The finger's first part lies over the slide's top with the palm, so it cannot lift: the two parts that
    # close on the side are what opens.
    _base, mid, tip = hand.finger_parts(finger)
    ends = np.concatenate([mid, tip])
    cost = 100.0 * relu(OPEN_CLEAR - sd[:, ends].min(axis=1)) + 100.0 * relu(-sd.min(axis=1) - (TOL - 0.0004))
    up = scene.gun_global[:3, :3] @ np.array(OVER_MOVE)
    for step in WAY_STEPS:
        cost += 100.0 * relu(WAY_CLEAR - scene.field(pts + step * up, which).min(axis=1))
    for step in CLOSE_STEPS:
        between = hand.finger_points(finger, grip + (a - grip) * step)
        cost += 100.0 * relu(-scene.field(between, which).min(axis=1) - (TOL - 0.0004))
    # A degree is worth 0.05 mm; a spread at a knuckle more (an opened hand keeps its fingers together).
    weights = np.full(a.shape[1], 5e-5)
    if finger != "thumb":
        weights[0] = 3e-4
    return cost + (np.abs(a - grip) * weights).sum(axis=1)


def opened(scene):
    """The gripping hand opened (see `OVER_MOVE`): each finger bone's rotation, and each finger's angles."""
    hand = scene.left
    grips = {finger: hand.angles[finger].copy() for finger in FINGERS}
    rng = np.random.default_rng(2)
    found = {}
    for finger in FINGERS:
        limits = LIMITS.get(finger, LIMITS["finger"])
        grip = grips[finger]
        dims = len(grip)
        # Start from the grip with every bend taken back by a share, then search round the best.
        starts = np.array([np.where(np.arange(dims) >= (3 if finger == "thumb" else 1), grip * share, grip) for share in np.linspace(0.0, 1.0, 11)])
        if finger == "thumb":
            # The thumb opens at its root: away from the palm, about each of the root's axes.
            roots = np.array(list(itertools.product((-30.0, -15.0, 0.0, 15.0, 30.0), repeat=3)))
            wide = np.repeat(starts, len(roots), axis=0)
            wide[:, :3] = np.clip(wide[:, :3] + np.tile(roots, (len(starts), 1)), limits[:3, 0], limits[:3, 1])
            starts = np.concatenate([starts, wide])
        cost = open_cost(scene, finger, starts, grip)
        best, best_cost = starts[cost.argmin()], cost.min()
        for scale in (8.0, 4.0, 2.0, 1.0, 0.5):
            for _ in range(3):
                steps = np.concatenate([np.eye(dims), -np.eye(dims), rng.integers(-1, 2, size=(200, dims))])
                cands = np.clip(best + scale * steps, limits[:, 0], limits[:, 1])
                cost = open_cost(scene, finger, cands, grip)
                if cost.min() < best_cost:
                    best_cost, best = cost.min(), cands[cost.argmin()]
        found[finger] = best
        ends = np.concatenate(hand.finger_parts(finger)[1:])
        clear = scene.field(hand.finger_points(finger, best), hand.finger_verts[finger])[0, ends].min() * 1000.0
        print("  open", finger, np.round(best, 1).tolist(), f"{clear:.1f} mm off at its place, cost {best_cost * 1000:.2f} mm", flush=True)
    for finger in FINGERS:
        hand.set(finger, found[finger])
    out = hand.quaternions()
    way = []
    up = scene.gun_global[:3, :3] @ np.array(OVER_MOVE)
    for step in (0.0, *WAY_STEPS):
        way.append(round(float(scene.field(hand.points() + step * up).min()) * 1000.0, 2))
    print("  the opened hand's nearest skin on the way down, from its place up, mm:", way, flush=True)
    for finger in FINGERS:
        hand.set(finger, grips[finger])
    return out, {finger: found[finger].tolist() for finger in FINGERS}, way


def pulled(scene, in_gun):
    """The gripping hand walked back along the slide's travel, against what stays where it is (the frame, the
    hammer, the right hand): the deepest skin at each step, in millimetres."""
    field = scene.stays
    hand = scene.left
    rows = []
    for step in np.linspace(0.0, TRAVEL, 10):
        moved = in_gun.copy()
        moved[0, 3] += step
        scene.put(moved)
        at = scene.to_gun(hand.points())
        d = np.minimum(field(at), scene.other[0](at))
        row = [round(step * 1000.0, 1), round(float(-d.min()) * 1000.0, 2)]
        rows.append(row)
        print("pulled %.1f mm: the skin is %.1f mm inside what stays (negative: off it)" % tuple(row), flush=True)
    scene.put(in_gun)
    return rows


def option(name, default):
    for argument in sys.argv:
        if argument.startswith(f"--{name}="):
            return argument.split("=", 1)[1]
    return default


def main():
    started = time.time()
    rigs, pistol = R.load(sys.argv[1])
    body = option("body", "")
    if body not in rigs:
        raise SystemExit(f"solve_rack_hand: give the body with --body=<one of {sorted(rigs)}>")
    slide_tris = glb_triangles(GAME / "assets" / "weapons" / "pistol" / "pistol.glb", "Slide")
    scene = Scene(rigs[body], pistol, sys.argv[1], hold_files.read(GAME, body), slide_tris)
    place = option("place", "")
    params = np.array([float(value) for value in place.split(",")] if place else PLACES[body])
    if "--search" in sys.argv:
        scene.left.stride = 3
        params = search(scene, params, [(0.008, 8.0), (0.004, 4.0), (0.002, 2.0), (0.001, 1.0)])
        scene.left.stride = 1
    in_gun = placed(scene.rig, params)
    total = score(scene, params, quick=False)
    contact = table(scene, "rack " + body)
    tips_at = tips(scene)
    for finger in FINGERS:
        print(" ", finger, np.round(scene.left.angles[finger], 1).tolist())
    print("place", np.round(params, 4).tolist(), "total %.2f mm" % (total * 1000), "in %.0f s" % (time.time() - started))
    open_pose, open_angles, open_way = opened(scene)
    solved = {
        "place_params": params.tolist(),
        "slide_hand": in_gun.tolist(),
        "rack": scene.left.quaternions(),
        "rack_open": open_pose,
        "open_angles": open_angles,
        "open_way_mm": open_way,
        "over_move": OVER_MOVE,
        "angles": {finger: scene.left.angles[finger].tolist() for finger in FINGERS},
        "travel": [TRAVEL, 0.0, 0.0],
        "contact_mm": contact,
        "tips_mm": tips_at,
        "pulled_mm": pulled(scene, in_gun),
    }
    path = Path(sys.argv[2])
    out = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    # A file from before each body had its own grip holds one grip at its top: it is replaced whole.
    out = {name: entry for name, entry in out.items() if name in rigs}
    out[body] = solved
    path.write_text(json.dumps(dict(sorted(out.items())), indent=1) + "\n", encoding="utf-8", newline="\n")
    print("wrote", body, "to", path)


if __name__ == "__main__":
    main()
