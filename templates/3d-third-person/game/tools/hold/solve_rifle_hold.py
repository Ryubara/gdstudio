"""Solves how the mannequin's hands hold the rifle (kit #889), from the dump `dump_hold_rig.gd` writes.

    <godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
    uv run --no-project --with numpy --with scipy python tools/hold/solve_rifle_hold.py <abs>/rig.json \
        <abs>/rifle_female.json --body=female
    <godot> --headless --path game -s res://tools/hold/write_hold.gd -- <abs>/rifle_female.json rifle female

The rifle has no clip: both arms reach by IK for a place of the hand bone given in the rifle's own space, so the
solver works there with the rifle at the origin. It finds three places and the fingers of each, on one body's skin
(`--body=female` or `--body=male`, the template's two bodies, kit #1187: their hands differ in size, so each gets a
hold of its own; `write_hold.gd` puts the default body's in the rifle's scene and pose files and another body's in
a `HoldFit`, `rifle_fit_<body>.tres`; `--body=both` measures two bodies whose skeletons match from the hands down
at once), with the grid, limits and finger search of `solve_pistol_hold.py`:

- the right hand on the pistol grip: the palm on the grip's right panel, the web high under the receiver, three
  fingers round the grip's front, the thumb round its left side, the index finger straight along the receiver
  over the trigger guard (`grip`) and on the trigger (`trigger`);
- the left hand under the hand guard at `Support`: the palm under it, the fingers up its right side and the thumb
  up its left (`support`), and the same hand opened (`open`);
- the left hand round the magazine for the reload (`magazine`): the palm on its left face, the fingers round
  its front, the thumb behind it.

A place also costs what it bends the wrist: the forearm's line is worked out from where the shoulder is in the
rifle's space at the shoulder and at the low ready (`SHOULDERS`, read from the game), and a wrist bent more than
`WRIST_FREE` degrees costs. With no option it solves the fingers at the three places the template ships (`MOVES`,
about 10 minutes). `--right=`, `--left=` and `--magazine=` give other places (a move from the start below: metres
along the rifle's axes, then degrees about them), `--only=<name>` solves one hand and keeps the others as the
output file has them, `--fast` solves once with the
quick finger search (half a minute a hand, to look at a place), `--search` or `--search-<name>` searches the
place from there (a coordinate search, an hour a hand), and `--draw=<file.png>` draws the hands on the rifle from
both sides, the top and the front. The places were found by looking: a place is tried with `--fast --draw`, then
in the game's close-ups (`tools/capture/rifle_hands.tscn`), and kept when both read as a hand that holds.
"""

import json
import sys
import time

import hold_field
import hold_rig as R
import numpy as np
from hold_hand import FINGERS, LIMITS, Hand
from solve_pistol_hold import body_option, model_names, natural, option, relu, start_grid

BASE_POSE = "ual1/Pistol_Aim_Neutral@0.16"
TARGET = -0.0008  # where the nearer skin of the two mannequins should sit off the surface, metres
TOL = 0.0012  # how deep the solver lets skin go (the test allows 2 mm)
# Where the nearer palm sits off the surface. Measuring two bodies at once (`--body=both`), the Quaternius pair's
# palms on the grip differed by 5.4 mm (the female's the hollower), so the male's was pressed 1.4 mm in and the
# female's was then 4 mm off: both within the test's 2 mm in and 5 mm off. One body's palm sits at TARGET.
PALM_TARGET = {"right": TARGET, "left": TARGET, "magazine": TARGET}
PALM_TARGET_BOTH = -0.0014
PALM_TOL = 0.0018
X, Y, Z = np.eye(3)
# The rifle: muzzle along -X, up +Y, its left side +Z. The distance grid covers where a hand can be.
GRID_LOW = [-0.42, -0.24, -0.11]
GRID_HIGH = [0.22, 0.26, 0.11]
GRID_STEP = 0.0015
# Where the middle of the trigger finger's last bone sits when its pad is on the trigger, from `Trigger`.
TRIGGER_OFF = np.array([-0.005, -0.004, 0.0])
# The index finger off the trigger lies straight along the rifle's right side, outside the trigger guard and no
# lower than this, its tip on the magazine well's wall.
REGISTER_Y = 0.02
# How far over to the near (left) side of the rifle's middle the thumb behind the magazine stays.
THUMB_BACK_Z = 0.0
# How far the middle of the straight index finger's last bone lies from the trigger along the receiver (the test
# wants the nearest skin 20 mm off; `--register-clear=` tries another).
REGISTER_TRIGGER_CLEAR = option("register-clear", [0.034])[0]
# How high the thumb's root sits on the grip (the web under the receiver's tail).
WEB_Y = 0.03
# The palm's middle in the hand bone's space (+Y along the fingers, +Z toward the thumb's side).
PALM = np.array([0.0, 0.07, 0.0])
# A palm vertex is seated by when the forearm carries less than this share of its weight.
FOREARM_SHARE = 0.03
# Degrees a wrist bends for nothing, and what a degree more costs, in metres.
WRIST_FREE = 20.0
WRIST_COST = 3e-4
# Each arm's shoulder joint in the rifle's space and where its elbow points, at the shoulder and at the low
# ready: the body's `shoulders` in the dump (`dump_hold_rig.gd` poses the rifle's hold in the idle clip; the
# shoulder, and the way from the middle of the shoulder and the hand to the elbow). Set by `main`.
SHOULDERS = {}
# Where each search starts: the hand bone's axes in the rifle (columns: across the palm, along the fingers,
# toward the thumb's side), where the palm's middle is, and the way the hand is pushed onto the surface.
STARTS = {
    # The palm (-X of the right hand) faces the grip's right panel; the thumb's side is up the grip.
    "right": ([[0, 0, -1], [-0.96, -0.28, 0], [-0.28, 0.96, 0]], [0.0, -0.005, -0.05], Z),
    # The palm (+X of the left hand) faces up under the hand guard; the fingers cross under it, forward.
    "left": ([[0, 1, 0], [-0.6, 0, -0.8], [-0.8, 0, 0.6]], [-0.246, 0.05, 0.0], Y),
    # The palm faces the magazine's left face; the fingers go round its front, the thumb's side is up.
    "magazine": ([[0, 0, -1], [-1, 0, 0], [0, 1, 0]], [-0.115, -0.07, 0.06], -Z),
}
# The moves from the starts that the template ships (metres along the rifle's axes, then degrees about them).
# The right hand sits 4 cm back and 2 cm up from the start (its index knuckle level with the trigger), turned 20 degrees about the rifle's up axis so the
# palm bears on the grip's right rear and the web is behind it.
MOVES = {
    "right": [0.04, 0.02, 0.0, 0.0, -20.0, 0.0],
    "left": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    "magazine": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
}
ROUNDS = [(0.008, 4.0), (0.004, 2.0), (0.002, 1.0)]
# How far the opened left hand's fingers are from their place under the hand guard to their rest (straight).
OPEN_SHARE = 0.8
# The grid is exact within this far of the rifle's surface; farther off a coarse grid's value stands.
BAND = 0.03
COARSE_STEP = 0.006


class BandField(hold_field.PiecesField):
    """The rifle's distance grid. The rifle is three times the pistol's length, and a nearest-sample query costs
    about 90 microseconds a point on its million samples, so only the grid points within `BAND` of the surface
    (by a coarse grid built first) get the exact distance; a hand never measures from farther off."""

    def __init__(self, tris, low, high, step, cache):
        self.low, self.step = np.array(low, float), step
        shape = np.ceil((np.array(high) - self.low) / step).astype(int) + 1
        try:
            saved = np.load(cache)
            if saved["grid"].shape == tuple(shape) and saved["count"] == len(tris):
                self.grid = saved["grid"]
                return
        except OSError:
            pass
        rough = hold_field.PiecesField(tris, low, high, COARSE_STEP)
        axes = [self.low[k] + step * np.arange(shape[k]) for k in range(3)]
        samples, sample_tri = hold_field.sample_triangles(tris, step)
        tree = hold_field.cKDTree(samples)
        dist = np.empty(shape, np.float32)
        for start in range(0, shape[0], 16):
            slab = np.stack(np.meshgrid(axes[0][start : start + 16], axes[1], axes[2], indexing="ij"), axis=-1)
            value = np.abs(rough(slab))
            near = value < BAND
            value[near] = hold_field.exact_distance(slab[near], tris, tree, sample_tri)
            dist[start : start + 16] = value
        depth = np.zeros(shape)
        piece = hold_field.pieces(tris)
        for p in range(piece.max() + 1):
            self._fill_piece(tris[piece == p], shape, depth, (2,))
        self.grid = np.where(depth > 0, -depth, dist).astype(np.float32)
        np.savez_compressed(cache, grid=self.grid, count=len(tris))


class Placed:
    """One hand put on the rifle: its place in the rifle's space and its fingers."""

    def __init__(self, rig, side, gun, sockets, name):
        self.rig, self.side, self.gun, self.sockets, self.name = rig, side, gun, sockets, name
        self.hand = Hand(rig, side, rig.poses[BASE_POSE])
        axes, palm_at, self.push = STARTS[name]
        basis = np.array(axes, float).T
        basis /= np.linalg.norm(basis, axis=0)
        self.base = np.eye(4)
        self.base[:3, :3] = basis
        self.base[:3, 3] = np.array(palm_at) - basis @ PALM
        self.pivot = np.array(palm_at, float)
        self.in_gun = self.base
        upper = np.linalg.norm(rig.rest[rig.index["lowerarm_" + side]][:3, 3])
        fore = np.linalg.norm(rig.rest[rig.index["hand_" + side]][:3, 3])
        self.arm = (upper, fore)
        # The palm's skin as the game's test counts it (the hand bone carries half its weight or more) that the
        # forearm does not move. The skin at the heel of the palm is shared with the
        # forearm, which the game's IK turns at the wrist (40 to 50 degrees on the grip) as no pose here has it:
        # a hand seated by that skin stood 5 to 7 mm off the grip in the game.
        hand = self.hand
        fore = rig.index["lowerarm_" + side]
        shared = (rig.vweights[hand.ids] * (rig.vbones[hand.ids] == fore)).sum(axis=1)
        mine = (rig.main[hand.ids] == hand.hand) & (rig.share[hand.ids] >= 0.5)
        self.palm = np.where(mine & (shared < FOREARM_SHARE))[0]

    def put(self, in_gun):
        hand = self.hand
        hand.move = np.eye(4)
        hand._apply_all()
        hand.move = in_gun @ np.linalg.inv(hand.hand_global())
        hand._apply_all()
        self.in_gun = in_gun

    def field(self, points):
        return self.gun(points)

    def place(self, params):
        """Puts the hand at the start moved by `params` (the rifle's axes, turns about the palm's middle), then
        pushes it along `push` from 8 cm off until the palm's skin is TARGET off the surface."""
        turn = np.eye(4)
        turn[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
        turn[:3, 3] = self.pivot - turn[:3, :3] @ self.pivot + np.array(params[:3])
        start = turn @ self.base
        palm = self.palm

        def gap(way):
            at = start.copy()
            at[:3, 3] += self.push * way
            self.put(at)
            return self.field(self.hand.points(palm)).min() - PALM_TARGET[self.name]

        low = -0.08
        while low < 0.08 and gap(low + 0.002) > 0:
            low += 0.002
        high = low + 0.002
        for _ in range(12):
            mid = 0.5 * (low + high)
            if gap(mid) > 0:
                low = mid
            else:
                high = mid
        gap(low)

    def wrist(self):
        """The degrees the wrist bends from the forearm's line, at the shoulder and at the low ready."""
        upper, fore = self.arm
        at = self.in_gun[:3, 3]
        bends = []
        for shoulder, pole in SHOULDERS[self.side]:
            to = at - np.array(shoulder)
            reach = np.clip(np.linalg.norm(to), abs(upper - fore) + 1e-3, upper + fore - 1e-3)
            along = to / np.linalg.norm(to)
            forward = (upper * upper - fore * fore + reach * reach) / (2.0 * reach)
            out = np.sqrt(max(upper * upper - forward * forward, 0.0))
            side = np.array(pole) - along * (np.array(pole) @ along)
            elbow = np.array(shoulder) + along * forward + side / np.linalg.norm(side) * out
            line = (at - elbow) / np.linalg.norm(at - elbow)
            bends.append(np.degrees(np.arccos(np.clip(self.in_gun[:3, 1] @ line, -1.0, 1.0))))
        return bends

    def open_fingers(self):
        for finger in FINGERS:
            self.hand.angles[finger][:] = 0.0
        self.hand._apply_all()


def finger_cost(placed, finger, angles, mode):
    """The cost of each row of angles for one finger: (K,)."""
    hand = placed.hand
    pts = hand.finger_points(finger, angles)
    sd = placed.field(pts)
    base, mid, tip = hand.finger_parts(finger)
    lows = [sd[:, p].min(axis=1) for p in (base, mid, tip)]
    # A search that measures every third vertex keeps 0.4 mm in hand, so the full measure agrees.
    deep = relu(-sd.min(axis=1) - (TOL if hand.stride == 1 else TOL - 0.0004))
    cost = 100.0 * deep
    a = np.atleast_2d(angles)
    tip_at = pts[:, tip].mean(axis=1)
    mid_at = pts[:, mid].mean(axis=1)
    touch = [np.abs(low - TARGET) for low in lows]
    if mode == "wrap":
        cost += touch[2] + touch[1] + 0.5 * touch[0] + natural(a)
    elif mode == "trigger":
        want = placed.sockets["Trigger"][:3, 3] + TRIGGER_OFF
        cost += 0.7 * np.linalg.norm(tip_at - want, axis=1) + 0.5 * touch[2]
        cost += 1e-4 * np.abs(a[:, 3] - 0.65 * a[:, 2])
    elif mode == "register":
        # Straight along the receiver's right side, over the trigger guard.
        cost += touch[2] + touch[1] + 2e-4 * (a[:, 2] + a[:, 3])
        cost += relu(tip_at[:, 2] + 0.014) + relu(mid_at[:, 2] + 0.014)
        cost += relu(REGISTER_Y - tip_at[:, 1]) + 0.5 * relu(REGISTER_Y - 0.01 - mid_at[:, 1])
        # Off the trigger by the test's 20 mm at its nearest skin: a prototype body's shorter finger lay 15 to
        # 17 mm from it along the receiver (kit #1187), as the pistol's along the frame did.
        trigger = placed.sockets["Trigger"][:3, 3]
        cost += relu(REGISTER_TRIGGER_CLEAR - np.linalg.norm(tip_at - trigger, axis=1))
    elif mode == "thumb":
        # Round the far side (the rifle's left, +Z), lying forward, nearly straight.
        lie = tip_at - mid_at
        cost += 2.0 * touch[2] + 0.7 * touch[1] + 0.3 * touch[0]
        cost += relu(0.012 - tip_at[:, 2]) + relu(lie[:, 0] + 0.005)
        cost += 2e-4 * relu(a[:, 5] - 45.0)
    elif mode == "thumb_back":
        # Behind the magazine: on whatever it reaches, nearly straight, and on the near (left, +Z) half: a thumb
        # round the magazine's far side was dragged 12 mm through it as the hand left to the left (kit #1187).
        cost += touch[2] + 0.7 * touch[1] + 2e-4 * relu(a[:, 5] - 45.0)
        cost += relu(THUMB_BACK_Z - tip_at[:, 2]) + relu(THUMB_BACK_Z - mid_at[:, 2])
    return cost


def solve_finger(placed, finger, mode, quick=False, start=None):
    hand = placed.hand
    limits = LIMITS.get(finger, LIMITS["finger"])
    grid = start_grid(finger, "trigger" if mode in ("trigger", "register") else mode)
    if start is not None:
        grid = np.concatenate([grid, np.atleast_2d(start)])
    cost = finger_cost(placed, finger, grid, mode)
    best = grid[cost.argmin()]
    best_cost = cost.min()
    dims = len(best)
    rng = np.random.default_rng(1)
    for scale in (8.0, 4.0, 2.0, 1.0) if quick else (8.0, 4.0, 2.0, 1.0, 0.5, 0.25):
        for _ in range(1 if quick else 3):
            steps = np.concatenate(
                [np.eye(dims), -np.eye(dims), rng.integers(-1, 2, size=(60 if quick else 200, dims))]
            )
            cands = np.clip(best + scale * steps, limits[:, 0], limits[:, 1])
            cost = finger_cost(placed, finger, cands, mode)
            if cost.min() < best_cost:
                best_cost = cost.min()
                best = cands[cost.argmin()]
    hand.set(finger, best)
    return best_cost


def modes_of(name, trigger=True):
    if name == "right":
        return {"index": "trigger" if trigger else "register", "thumb": "thumb"}
    return {"thumb": "thumb" if name == "left" else "thumb_back"}


def close(placed, quick=False, trigger=True):
    """Closes the fingers where the hand is; returns the total cost and each finger's."""
    hand = placed.hand
    modes = modes_of(placed.name, trigger)
    table = {}
    for _ in range(1 if quick else 2):
        for finger in FINGERS:
            table[finger] = solve_finger(placed, finger, modes.get(finger, "wrap"), quick, hand.angles[finger])
    palm = placed.field(hand.points(placed.palm)).min()
    whole = placed.field(hand.points(hand.part["palm"])).min()
    table["palm"] = abs(palm - PALM_TARGET[placed.name]) + 100.0 * relu(-whole - PALM_TOL)
    return sum(table.values()), table


def score(placed, params, quick=True):
    """What the hand's place costs: the closed fingers, the palm, the wrist and what each place is for."""
    placed.open_fingers()
    placed.place(params)
    total, table = close(placed, quick)
    # The palm's skin near the knuckles follows the fingers: seated again under the closed fingers.
    placed.place(params)
    bends = placed.wrist()
    table["wrist"] = WRIST_COST * float(np.mean([relu(bend - WRIST_FREE) for bend in bends]))
    hand, rig = placed.hand, placed.rig
    palm_at = (placed.in_gun @ np.append(PALM, 1.0))[:3]
    if placed.name == "right":
        root = hand.glob[rig.index["thumb_01_r"]][:3, 3]
        web = placed.field(hand.points(hand.part["thumb_base"])).min()
        table["web"] = 0.2 * relu(WEB_Y - root[1]) + 0.5 * abs(web - TARGET)
    elif placed.name == "left":
        # Under the hand guard at `Support`, not wherever along it the fingers fit best.
        table["at"] = 0.3 * abs(palm_at[0] - placed.sockets["Support"][0, 3])
    else:
        # On the magazine's lower half, clear of the magazine well.
        table["at"] = 0.3 * relu(palm_at[1] + 0.05)
    return sum(table.values()), table


def search(placed, start):
    placed.hand.stride = 3
    best = np.array(start, float)
    best_cost, _ = score(placed, best)
    print(placed.name, "start", np.round(best, 4).tolist(), f"cost {best_cost * 1000:.2f} mm", flush=True)
    for step_m, step_deg in ROUNDS:
        improved = True
        while improved:
            improved = False
            for k in range(6):
                for sign in (-1.0, 1.0):
                    cand = best.copy()
                    cand[k] += sign * (step_m if k < 3 else step_deg)
                    if k >= 3 and abs(cand[k]) > 60.0:
                        continue
                    cost, _ = score(placed, cand)
                    if cost < best_cost - 1e-6:
                        best, best_cost, improved = cand, cost, True
            print("  step", step_m, step_deg, np.round(best, 4).tolist(), f"cost {best_cost * 1000:.2f} mm", flush=True)
    placed.hand.stride = 1
    return best


def finish(placed, params, fast=False):
    """The full solve at a place: seated and closed three times (`fast`: once, with the quick search, to look
    at a start); returns the last table."""
    placed.open_fingers()
    placed.hand.stride = 3 if fast else 1
    table = {}
    for _ in range(1 if fast else 3):
        placed.place(params)
        _, table = close(placed, quick=fast, trigger=False)
    # Seated once more under the closed fingers, so the palm is where the test will find it, and the fingers
    # closed once more where the hand now is.
    placed.place(params)
    placed.hand.stride = 1
    _, table = close(placed, quick=fast, trigger=False)
    return table


def opened(rig, support):
    """The left hand's four fingers opened from their pose under the hand guard: each bone `OPEN_SHARE` of the
    way from `support` back to its rest (bone name to quaternion), the hand that lets go and reaches. The thumb
    is not in it: opened toward its rest it went 15 mm into the hand guard, so it keeps the pose it is given."""
    out = {}
    for name, quaternion in support.items():
        if name.startswith("thumb"):
            continue
        start = np.array(quaternion, float)
        end = np.array(R.mat_to_quat(rig.rest[rig.index[name]][:3, :3]), float)
        if start @ end < 0.0:
            end = -end
        angle = np.arccos(np.clip(start @ end, -1.0, 1.0))
        if angle > 1e-6:
            end = (np.sin((1.0 - OPEN_SHARE) * angle) * start + np.sin(OPEN_SHARE * angle) * end) / np.sin(angle)
        out[name] = end.tolist()
    return out


def report(placed, tag):
    hand = placed.hand
    sd = placed.field(hand.points())
    model = placed.rig.model[hand.ids]
    for which, name in enumerate(model_names()):
        line = [f"{part} {sd[idx[model[idx] == which]].min() * 1000.0:.1f}" for part, idx in hand.part.items()]
        own = placed.palm[model[placed.palm] == which]
        line.append(f"palm's own {sd[own].min() * 1000.0:.1f}")
        print(tag, name, ", ".join(line), flush=True)
    print(tag, "wrist bends", np.round(placed.wrist(), 1).tolist(), "hand at", np.round(placed.in_gun[:3, 3], 4).tolist())


def draw(path, tris, hands):
    """The rifle and the hands' skins from the right side, the top and the front, as a picture."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    # Each view: its name, the axes across and up the picture, and whether the first is flipped.
    views = [("right side (muzzle right)", 0, 1, -1), ("left side", 0, 1, 1), ("top", 0, 2, 1), ("from behind", 2, 1, -1)]
    figure, axes = plt.subplots(len(hands), len(views), figsize=(6 * len(views), 5 * len(hands)), squeeze=False)
    colours = {"index": "tab:red", "middle": "tab:orange", "ring": "tab:green", "pinky": "tab:blue", "thumb": "m"}
    for row, (tag, placed) in enumerate(hands):
        hand = placed.hand
        points = hand.points()
        centre = points.mean(axis=0)
        for column, (name, a, b, flip) in enumerate(views):
            ax = axes[row][column]
            depth = 3 - a - b
            near = np.abs(tris[:, :, a] - centre[a]).min(axis=1) < 0.16
            for tri in tris[near]:
                ax.plot(flip * tri[[0, 1, 2, 0], a], tri[[0, 1, 2, 0], b], color="0.6", linewidth=0.3)
            order = np.argsort(points[:, depth])
            ax.scatter(flip * points[order, a], points[order, b], s=1.0, color="0.25")
            for finger, colour in colours.items():
                which = hand.finger_verts[finger]
                ax.scatter(flip * points[which, a], points[which, b], s=1.5, color=colour)
            ax.set_xlim(flip * centre[a] - 0.14, flip * centre[a] + 0.14)
            ax.set_ylim(centre[b] - 0.12, centre[b] + 0.12)
            ax.set_aspect("equal")
            ax.set_title(f"{tag}: {name}")
    figure.tight_layout()
    figure.savefig(path, dpi=110)


def main():
    with open(sys.argv[1], "rb") as file:
        data = json.load(file)
    rigs = {name: R.Rig(model) for name, model in data["models"].items()}
    body = body_option()
    rig = R.merged(rigs["female"], rigs["male"]) if body == "both" else rigs[body]
    if body == "both":
        PALM_TARGET["right"] = PALM_TARGET_BOTH
    SHOULDERS.update(data["shoulders"]["female" if body == "both" else body])
    rifle = data["rifle"]
    tris = np.array(rifle["triangles"]).reshape(-1, 3, 3)
    started = time.time()
    hold_field.WORKERS = 4
    gun = BandField(tris, GRID_LOW, GRID_HIGH, GRID_STEP, sys.argv[1] + ".rifle.npz")
    print("grid", gun.grid.shape, "in %.0f s" % (time.time() - started), flush=True)
    sockets = {name: R.xf(place) for name, place in rifle["sockets"].items()}
    out = {}
    hands = []
    if any(argument.startswith("--only=") for argument in sys.argv):
        # One hand solved again: the others stay as the output file has them.
        try:
            with open(sys.argv[2], "rb") as file:
                out = json.load(file)
        except OSError:
            pass
    fast = "--fast" in sys.argv
    for name, side in (("right", "r"), ("left", "l"), ("magazine", "l")):
        if any(argument.startswith("--only=") and argument[7:] != name for argument in sys.argv):
            continue
        placed = Placed(rig, side, gun, sockets, name)
        params = np.array(option(name, MOVES[name]), float)
        if "--trigger-only" in sys.argv:
            # Only the finger on the trigger again, on the grip the output file has (its `right_angles`).
            if name != "right":
                continue
            for finger, angles in out["right_angles"].items():
                placed.hand.set(finger, angles)
            placed.hand._apply_all()
            placed.place(np.array(out["right_params"], float))
            solve_finger(placed, "index", "trigger")
            out["trigger"] = placed.hand.quaternions(["index"])
            report(placed, "right (trigger)")
            hands.append((name, placed))
            continue
        if f"--search-{name}" in sys.argv or "--search" in sys.argv:
            params = search(placed, params)
        table = finish(placed, params, fast)
        report(placed, name)
        print(name, np.round(params, 4).tolist(), {k: round(v * 1000, 2) for k, v in table.items()})
        print(name, "in %.0f s" % (time.time() - started), flush=True)
        key = {"right": "grip", "left": "support", "magazine": "magazine"}[name]
        out[name + "_params"] = params.tolist()
        out[name + "_hand"] = placed.in_gun.tolist()
        out[key] = placed.hand.quaternions()
        if name == "right":
            out["right_angles"] = {finger: placed.hand.angles[finger].tolist() for finger in FINGERS}
            solve_finger(placed, "index", "trigger", fast)
            out["trigger"] = placed.hand.quaternions(["index"])
            report(placed, "right (trigger)")
        hands.append((name, placed))
    if "support" in out:
        out["open"] = opened(rig, out["support"])
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())
    for argument in sys.argv:
        if argument.startswith("--draw="):
            draw(argument[7:], tris, hands)


if __name__ == "__main__":
    main()
