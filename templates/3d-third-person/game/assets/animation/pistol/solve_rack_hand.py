"""Solves where the left hand grips the pistol's slide for the rack clip (kit #1081), on both mannequins at once.

    <godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
    uv run --no-project --with numpy --with scipy python assets/animation/pistol/solve_rack_hand.py
        <abs>/rig.json <abs>/rack_hand.json [--search] [--place=dx,dy,dz,rx,ry,rz]

An overhand rack: the left hand comes over the top of the slide from the gun's left, palm down, just in front of
the rear sight, the four fingers down the slide's right side and the thumb down its left, pointing back at the
shooter. This works out the hand bone's place in the pistol's space and every finger bone's rotation, measured
on both mannequins' skinned hands against the pistol's closed pieces and the right hand as the game's hold has
it (`pistol_held.tscn`, `pistol_grip_pose.tres`; the trigger finger along the frame). It reads the hold and never
changes it: the rig, the skinning and the distance grid are the hold tools' (`tools/hold/hold_rig.py`,
`hold_hand.py`, `hold_field.py`), the dump is `tools/hold/dump_hold_rig.gd`'s.

It then walks the gripping hand back along the slide's travel (+X) and measures it against what stays (the
frame, the hammer, the right hand), and writes the hand opened (for the reach and the release) beside the grip.
`build_pistol_rack.py` keys the clip from the file this writes. With no option it solves the fingers at `PLACE`
(a minute); `--search` searches the place again from there (ten minutes).
"""

import itertools
import json
import re
import struct
import sys
import time
from pathlib import Path

import numpy as np

GAME = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(GAME / "tools" / "hold"))

import hold_field  # noqa: E402
import hold_rig as R  # noqa: E402
from hold_hand import FINGERS, LIMITS, Hand  # noqa: E402

BASE_POSE = "ual1/Pistol_Aim_Neutral@0.16"
TARGET = -0.0008  # where the nearer mannequin's skin sits off the surface, metres (the hold's own)
TOL = 0.0012  # how deep the solver lets skin go (the test allows 2 mm)
# The pistol in Godot: the muzzle along -X, up +Y, its left +Z. The slide's box runs from x -0.202 to 0.008,
# y 0.088 to 0.133 and z -0.02 to 0.02; the rear sight stands on its last 12 mm.
SLIDE_TOP = 0.133
SLIDE_BOTTOM = 0.088
SLIDE_HALF = 0.02
REAR_SIGHT_FRONT = -0.012
# The slide's travel (the model's README: Deadnight moves it 0.05 m at a shot).
TRAVEL = 0.045
# The hand bone's place on the closed slide, as a move from `start_place()`: metres along the pistol's axes,
# then degrees about them (about the middle of the slide's top under the palm).
PLACE = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
PIVOT = np.array([-0.05, SLIDE_TOP, 0.0])
GRID_LOW = [-0.24, -0.09, -0.075]
GRID_HIGH = [0.08, 0.17, 0.075]
HAND_LOW = [-0.17, -0.09, -0.12]
HAND_HIGH = [0.10, 0.16, 0.09]
OPEN_SHARE = 0.45  # the opened hand: each finger bone this share of the way from its rest to its grip
X, Y, Z = np.eye(3)


def relu(x):
    return np.maximum(x, 0.0)


def read_quaternions(path, block):
    """The `block` dictionary (`rotations` or `turns`) of a `HandPose` file: bone name to (x, y, z, w)."""
    text = Path(path).read_text(encoding="utf-8")
    body = re.search(block + r" = Dictionary\[StringName, Quaternion\]\(\{(.*?)\}\)", text, re.S)
    found = re.findall(r'&"(\w+)": Quaternion\(([^)]*)\)', body.group(1) if body else "")
    return {name: np.array([float(v) for v in numbers.split(",")]) for name, numbers in found}


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
    """Both mannequins' hands (one merged rig), the right one on the pistol as the game's hold has it."""

    def __init__(self, rig, pistol, cache):
        self.rig = rig
        self.gun_tris = np.array(pistol["triangles"]).reshape(-1, 3, 3)
        self.gun = hold_field.PiecesField(self.gun_tris, GRID_LOW, GRID_HIGH, 0.001, cache)
        self.seat = R.xf(pistol["seat"])
        hold = GAME / "gameplay" / "weapon" / "hold"
        grip = read_quaternions(hold / "pistol_grip_pose.tres", "rotations")
        turn = read_quaternions(hold / "pistol_grip_pose.tres", "turns")["hand_r"]
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

    def put(self, in_gun):
        """Moves the left hand, as its fingers are, to a place given in the pistol's space."""
        hand = self.left
        hand.move = np.eye(4)
        hand._apply_all()
        hand.move = self.gun_global @ in_gun @ np.linalg.inv(hand.hand_global())
        hand._apply_all()


def start_place():
    """The left hand bone over the slide before the search: its fingers (+Y) point across the top to the gun's
    right and a little up, its palm (+X) faces down onto the slide, its index side (+Z) is at the rear."""
    lean = np.radians(35.0)  # the wrist lower than the knuckles, the heel of the palm toward the slide's left side
    fingers = np.array([0.0, np.sin(lean), -np.cos(lean)])
    index_side = np.array([1.0, 0.0, 0.0])
    palm = np.cross(fingers, index_side)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2] = palm, fingers, index_side
    # The knuckles (0.12 m along the fingers from the wrist) over the slide's top, the index knuckle just in
    # front of the rear sight (0.031 toward the index side of the bone).
    knuckles = np.array([REAR_SIGHT_FRONT - 0.012 - 0.031, SLIDE_TOP + 0.03, 0.004])
    m[:3, 3] = knuckles - 0.12 * fingers
    return m


def placed(params):
    turn = np.eye(4)
    turn[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    turn[:3, 3] = PIVOT - turn[:3, :3] @ PIVOT + np.array(params[:3])
    return turn @ start_place()


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
    a = np.atleast_2d(angles)
    tip_at = scene.to_gun(pts[:, tip].mean(axis=1))
    mid_at = scene.to_gun(pts[:, mid].mean(axis=1))
    touch = [np.abs(low - TARGET) for low in lows]
    if finger == "thumb":
        # Down the slide's left side, pointing back at the shooter, over the right thumb and not on it.
        cost += touch[2] + 0.6 * touch[1]
        cost += relu(SLIDE_HALF - tip_at[:, 2]) + relu(SLIDE_BOTTOM + 0.008 - tip_at[:, 1])
        cost += 0.3 * relu(mid_at[:, 0] - tip_at[:, 0])
        cost += 2e-4 * relu(a[:, 5] - 45.0) + 3e-5 * np.abs(a[:, :3]).sum(axis=1)
    else:
        # Over the top and down the right side, the pad on the side's face above the frame.
        cost += touch[2] + 0.6 * touch[1] + natural(a)
        cost += relu(tip_at[:, 2] + SLIDE_HALF) + relu(SLIDE_BOTTOM + 0.006 - tip_at[:, 1])
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
    return total + abs(palm.min() - TARGET) + 100.0 * relu(-palm.min() - TOL)


def score(scene, params, quick=True):
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    scene.put(placed(params))
    return close(scene, quick)


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
    """Each part's distance to the pistol and the right hand, per mannequin, in millimetres."""
    hand = scene.left
    sd = scene.field(hand.points())
    model = scene.rig.model[hand.ids]
    out = {}
    for which, name in enumerate(("female", "male")):
        row = {part: round(float(sd[idx[model[idx] == which]].min()) * 1000.0, 2) for part, idx in hand.part.items()}
        out[name] = row
        print(tag, name, ", ".join(f"{part} {value:.1f}" for part, value in row.items()), flush=True)
    return out


def opened(scene):
    """The gripping hand opened: every finger bone `OPEN_SHARE` of the way from its rest to its grip."""
    rig, out = scene.rig, {}
    for name, quaternion in scene.left.quaternions().items():
        end = np.array(quaternion, float)
        start = np.array(R.mat_to_quat(rig.rest[rig.index[name]][:3, :3]), float)
        if start @ end < 0.0:
            end = -end
        angle = np.arccos(np.clip(start @ end, -1.0, 1.0))
        if angle > 1e-6:
            end = (np.sin((1.0 - OPEN_SHARE) * angle) * start + np.sin(OPEN_SHARE * angle) * end) / np.sin(angle)
        out[name] = end.tolist()
    return out


def pulled(scene, in_gun, slide_tris, cache):
    """The gripping hand walked back along the slide's travel, against what stays where it is (the frame, the
    hammer, the right hand): the deepest skin at each step, per mannequin, in millimetres."""
    slide_keys = {tuple(np.round(t.mean(axis=0) * 1e5).astype(int)) for t in slide_tris}
    stays = np.array([t for t in scene.gun_tris if tuple(np.round(t.mean(axis=0) * 1e5).astype(int)) not in slide_keys])
    print(f"the slide is {len(scene.gun_tris) - len(stays)} of the pistol's {len(scene.gun_tris)} triangles")
    field = hold_field.PiecesField(stays, GRID_LOW, GRID_HIGH, 0.001, cache)
    hand = scene.left
    model = scene.rig.model[hand.ids]
    rows = []
    for step in np.linspace(0.0, TRAVEL, 10):
        moved = in_gun.copy()
        moved[0, 3] += step
        scene.put(moved)
        at = scene.to_gun(hand.points())
        row = [round(step * 1000.0, 1)]
        for which in range(2):
            mine = model == which
            d = np.minimum(field(at[mine]), scene.other[which](at[mine]))
            row.append(round(float(-d.min()) * 1000.0, 2))
        rows.append(row)
        print("pulled %.1f mm: the female's skin is %.1f mm inside what stays, the male's %.1f (negative: off it)" % tuple(row), flush=True)
    scene.put(in_gun)
    return rows


def option(name, default):
    for argument in sys.argv:
        if argument.startswith(f"--{name}="):
            return [float(value) for value in argument.split("=", 1)[1].split(",")]
    return default


def main():
    started = time.time()
    rigs, pistol = R.load(sys.argv[1])
    scene = Scene(R.merged(rigs["female"], rigs["male"]), pistol, sys.argv[1] + ".gun.npz")
    slide_tris = glb_triangles(GAME / "assets" / "weapons" / "pistol" / "pistol.glb", "Slide")
    params = np.array(option("place", PLACE))
    if "--search" in sys.argv:
        scene.left.stride = 3
        params = search(scene, params, [(0.008, 8.0), (0.004, 4.0), (0.002, 2.0), (0.001, 1.0)])
        scene.left.stride = 1
    in_gun = placed(params)
    total = score(scene, params, quick=False)
    contact = table(scene, "rack")
    for finger in FINGERS:
        print(" ", finger, np.round(scene.left.angles[finger], 1).tolist())
    print("place", np.round(params, 4).tolist(), "total %.2f mm" % (total * 1000), "in %.0f s" % (time.time() - started))
    out = {
        "place_params": params.tolist(),
        "slide_hand": in_gun.tolist(),
        "rack": scene.left.quaternions(),
        "rack_open": opened(scene),
        "angles": {finger: scene.left.angles[finger].tolist() for finger in FINGERS},
        "travel": [TRAVEL, 0.0, 0.0],
        "contact_mm": contact,
        "pulled_mm": pulled(scene, in_gun, slide_tris, sys.argv[1] + ".stays.npz"),
    }
    Path(sys.argv[2]).write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("wrote", sys.argv[2])


if __name__ == "__main__":
    main()
