"""Solves how the mannequin's hands hold the pistol (kit #1001), from the dump `dump_hold_rig.gd` writes.

    <godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
    uv run --no-project --with numpy --with scipy python tools/hold/solve_pistol_hold.py <abs>/rig.json <abs>/hold.json
    <godot> --headless --path game -s res://tools/hold/write_hold.gd -- <abs>/hold.json

It skins both mannequins' hands on the CPU as Godot does and measures them against the pistol's closed pieces on a
1 mm grid (and, for the left hand, against the right hand of the same mannequin), so a pose is right for both at
once. With no option it solves the fingers for the seat and the left hand's place below (the hold the template
ships, about 5 minutes); `--search-seat` and `--search-left` search those again from there (4 to 6 minutes each),
`--seat=` and `--left=` give other starts, and `--scan=` prints a table of seats to choose from. The left hand
under the magazine (kit #1031: where it pushes the magazine in during the reload) is solved next, from its
place on the gun rolled under the magazine's base; `--magazine=` gives another move from that place and
`--magazine-only` solves only it, on the seat and right hand of the output file of an earlier run (a minute).
The left hand's way off the gun and back onto it (kit #1051) is solved last: its fingers opened where it holds,
each as far as it lifts off without passing through anything on the way, and the straight line along which the
opened hand leaves, the clear one nearest the way to the belt; `--way-only` solves only that, on the output
file of an earlier run (five minutes).

The seat is given as a move from `REFERENCE_SEAT` (metres along the pistol's own axes, then degrees about them),
and the hand bone is turned back at the wrist by the same turn, so the barrel keeps the reference's line in the
forearm in every clip and only the wrist bends. The test `tests/gameplay/test_pistol_hold.gd` measures the result
in Godot; the two agree to about 0.4 mm.
"""

import itertools
import json
import sys
import time

import hold_field
import hold_rig as R
import numpy as np
from hold_hand import FINGERS, LIMITS, Hand, local_rotations
from scipy.spatial.transform import Rotation

BASE_POSE = "ual1/Pistol_Aim_Neutral@0.16"
# Both mannequins are measured at once and their skins differ by up to 3.3 mm in the same pose, so the
# nearer skin of the two is pressed 0.8 mm into the surface (the other is then up to 2.5 mm off it).
TARGET = -0.0008  # where the nearer skin should sit off the surface, metres
TOL = 0.0012  # how deep the solver lets skin go (the test allows 2 mm)
# Where the middle of the trigger finger's last bone sits when its pad is on the trigger, in the gun.
TRIGGER_OFF = np.array([-0.010, -0.004, 0.0])
THUMB_AT = np.array([-0.01, 0.070, 0.030])
# The left thumb lies ahead of the right one and lower, along the frame over the trigger guard.
LEFT_THUMB_AT = np.array([-0.065, 0.060, 0.030])
UNDER_GUARD_Y = 0.006  # the middle of a finger that lies under the trigger guard is no higher
OVER = 0.5  # what a support finger's millimetre off the shooting hand costs, in millimetres of contact
OVER_NEAR = 0.002  # how near the shooting hand's skin a support finger's bone counts as lying on it, metres
WEB_Y = 0.07  # how high on the gun the thumb's root should sit (the web under the tang)
FRAME_Y = 0.079
# The pistol on `hand_r` as kit #834 seated it (basis columns, then the origin): the barrel line the aim clips
# were captured with, 1.5 degrees up and 3 degrees out in `Pistol_Aim_Neutral`.
REFERENCE_SEAT = [0.0234, -0.9867, 0.1609, -0.0805, 0.1585, 0.9841, -0.9965, -0.036, -0.0757, -0.0264, 0.1234, 0.0091]
# The seat the template ships, as a move from the reference, and the left hand's place as a move from the right
# hand's mirrored across the pistol.
SEAT = [0.022, -0.035, 0.0306, -4.0, -23.5, -15.5]
LEFT = [-0.017, -0.03, 0.009, -8.0, 1.5, 0.0]
# The left hand's place while it pushes the magazine in, as a move from its place on the gun (about the middle
# of the magazine's base): rolled about the barrel's line until the heel of the palm is under the base.
MAGAZINE = [0.0, 0.0, -0.07, 80.0, 0.0, 0.0]
# How far the thumb of the hand under the magazine stays off every surface, metres: the test in Godot read
# the male thumb's root 1.4 mm deeper than this solver there.
CUP_THUMB_OFF = 0.0005
# The left hand's way off the gun (kit #1051). Its fingers open where the hand holds, then the opened hand
# leaves along a straight line; the game plays both backwards to bring it on again.
OPEN_CLEAR = 0.005  # how far off every surface an opened finger is lifted, where it can be, metres
WAY_TOL = 0.001  # how deep any skin may pass on the way, metres (the test allows 2 mm)
WAY_LENGTH = 0.06  # how far the opened hand goes before the clip's arm takes it, metres
WAY_STEPS = 16  # the poses measured between closed and open, and the places between on and off
WAY_GRID = 10.0  # degrees between the directions tried
TRIGGER_STEPS = 20  # the equal parts of the trigger finger's way that are measured (kit #1079)
# The dumped pose in which the reload clip has the left hand at the belt: the way out leans toward it.
BELT_POSE = "ual1/Pistol_Reload@0.40"
MAGAZINE_BASE = np.array([0.003, -0.052, 0.0])
# The grid of the gun's distance: the whole gun (muzzle at -0.207) and a hand's thickness round it.
GRID_LOW = [-0.24, -0.09, -0.075]
GRID_HIGH = [0.08, 0.17, 0.075]
# The grid of a frozen hand's distance, in the gun's space: either hand where it holds, and a finger round it.
HAND_LOW = [-0.17, -0.12, -0.12]
HAND_HIGH = [0.10, 0.16, 0.12]
FAR = 1.0  # what the distance to a hand that is not there reads, metres


def relu(x):
    return np.maximum(x, 0.0)


class Scene:
    def __init__(self, rig, pistol, cache):
        self.rig = rig
        tris = np.array(pistol["triangles"]).reshape(-1, 3, 3)
        self.gun = hold_field.PiecesField(tris, GRID_LOW, GRID_HIGH, 0.001, cache)
        self.sockets = {k: R.xf(v) for k, v in pistol["sockets"].items()}
        self.seat0 = R.xf(REFERENCE_SEAT)
        self.seat = self.seat0.copy()
        self.right = Hand(rig, "r", rig.poses[BASE_POSE])
        self.left = Hand(rig, "l", rig.poses[BASE_POSE])
        # A hand's side and its skin as it holds, a field for each mannequin: a surface for the other hand.
        self.frozen = {}

    def gun_global(self):
        return self.right.hand_global() @ self.seat

    def to_gun(self, points):
        g = self.gun_global()
        return (points - g[:3, 3]) @ g[:3, :3]

    def distances(self, hand, points, which=None, model=None):
        """The distances from a hand's points to the gun and to the other hand of the same mannequin as it
        was frozen (`FAR` when it is not): two arrays (`which` picks the hand's vertices the points are,
        all by default; `model` says whose each point is when they are not vertices)."""
        gun = self.gun(self.to_gun(points))
        other = np.full(gun.shape, FAR)
        fields = self.frozen.get("l" if hand.side == "r" else "r")
        if fields:
            if model is None:
                model = self.rig.model[hand.ids if which is None else hand.ids[which]]
            for index, field in enumerate(fields):
                mine = model == index
                other[..., mine] = field(points[..., mine, :])
        return gun, other

    def field(self, hand, points, which=None):
        """The distance from a hand's points to what it holds: the gun and the other hand as frozen."""
        return np.minimum(*self.distances(hand, points, which))

    def palm(self, hand):
        """The distances from all over a hand's palm (`Hand.palm_points`) to the gun and to the other hand."""
        return self.distances(hand, hand.palm_points(), model=hand.palm_model)

    def freeze(self, hand, also=()):
        """A hand as it holds the gun becomes a surface for the other hand, on a grid in the gun's space.
        `also` lists (finger, angles) pairs: the finger is part of the surface in those poses too (the
        trigger finger along the frame, on the trigger and between), so the other hand clears them all."""
        points = self.to_gun(hand.points())
        extra = []
        for finger, angles in also:
            verts = hand.finger_verts[finger]
            moved = np.zeros_like(points)
            moved[verts] = self.to_gun(hand.finger_points(finger, angles)[0])
            extra.append((np.isin(hand.tris, verts).all(axis=1), moved))
        fields = []
        for index in range(self.rig.model.max() + 1):
            # The triangles of this mannequin's hand, as indices into the hand's own points.
            mine = self.rig.model[hand.ids][hand.tris[:, 0]] == index
            tris = [points[hand.tris[mine]]] + [moved[hand.tris[mine & whole]] for whole, moved in extra]
            grid = hold_field.PiecesField(np.concatenate(tris), HAND_LOW, HAND_HIGH, 0.0015, rays=(0, 1, 2))
            fields.append(lambda at, grid=grid: grid(self.to_gun(at)))
        self.frozen[hand.side] = fields


def finger_cost(scene, hand, finger, angles, mode):
    """The cost of each row of angles for one finger, and what was measured: (K,), dict."""
    pts = hand.finger_points(finger, angles)
    to_gun, to_hand = scene.distances(hand, pts, hand.finger_verts[finger][:: hand.stride])
    sd = np.minimum(to_gun, to_hand)
    base, mid, tip = hand.finger_parts(finger)
    lows = [sd[:, p].min(axis=1) for p in (base, mid, tip)]
    # A search that measures every third vertex keeps 0.4 mm in hand, so the full measure agrees.
    deep = relu(-sd.min(axis=1) - (TOL if hand.stride == 1 else TOL - 0.0004))
    if mode == "cup" and finger == "thumb":
        deep = relu(CUP_THUMB_OFF - sd.min(axis=1))
    cost = 100.0 * deep
    a = np.atleast_2d(angles)
    tip_at = scene.to_gun(pts[:, tip].mean(axis=1))
    mid_at = scene.to_gun(pts[:, mid].mean(axis=1))
    touch = [np.abs(low - TARGET) for low in lows]
    if mode == "wrap":
        cost += touch[2] + touch[1] + 0.5 * touch[0] + natural(a)
    elif mode == "over":
        # The support hand's fingers lie over the shooting hand's fingers, never beside them on the gun:
        # the middle and last bones are on the other hand's skin, whatever else they touch.
        cost += touch[2] + touch[1] + 0.5 * touch[0] + natural(a)
        cost += OVER * (relu(to_hand[:, mid].min(axis=1) - OVER_NEAR) + relu(to_hand[:, tip].min(axis=1) - OVER_NEAR))
        if finger == "index":
            # The index finger is pressed up under the trigger guard: its first two bones below the
            # guard's underside, and the finger on the gun there (the other hand covers the grip).
            base_at = scene.to_gun(pts[:, base].mean(axis=1))
            cost += relu(base_at[:, 1] - UNDER_GUARD_Y) + relu(mid_at[:, 1] - UNDER_GUARD_Y)
            cost += 0.5 * np.abs(to_gun.min(axis=1) - TARGET)
    elif mode == "trigger":
        want = scene.sockets["Trigger"][:3, 3] + TRIGGER_OFF
        cost += 0.7 * np.linalg.norm(tip_at - want, axis=1) + 0.5 * touch[2]
        cost += 1e-4 * np.abs(a[:, 3] - 0.65 * a[:, 2])
    elif mode == "frame":
        # Straight along the gun's right side, outside the trigger guard, as high as the knuckle lets it.
        cost += touch[2] + touch[1] + 2e-4 * (a[:, 2] + a[:, 3])
        cost += relu(tip_at[:, 2] + 0.014) + relu(mid_at[:, 2] + 0.014)
        cost += 0.1 * relu(FRAME_Y - tip_at[:, 1])
    elif mode == "cup":
        # Under the magazine: the fingers close on whatever is in reach (the grip's foot, the right hand).
        cost += touch[2] + 0.5 * touch[1]
        cost += 2e-4 * relu(a[:, 5] - 45.0) if finger == "thumb" else 3.0 * natural(a) + 2e-4 * np.abs(a[:, 0])
    elif mode == "thumb":
        # Both thumbs lie on the gun's left (+Z), the left one ahead of the right one.
        cost += touch[2] + 0.7 * touch[1] + 0.3 * touch[0]
        want = THUMB_AT if hand.side == "r" else LEFT_THUMB_AT
        cost += 0.4 * np.linalg.norm(tip_at - want, axis=1)
        cost += relu(0.012 - tip_at[:, 2])
        # Under the slide, round the back of the grip below the tang, and lying forward: the tip
        # ahead of the middle bone and no higher.
        cost += relu(tip_at[:, 1] - 0.084) + relu(mid_at[:, 1] - 0.08)
        lie = tip_at - mid_at
        cost += 1.0 * relu(lie[:, 0] + 0.01) + 1.0 * relu(lie[:, 1])
        # A thumb that lies on a surface is nearly straight: a hooked tip costs 0.2 mm a degree past 45.
        cost += 2e-4 * relu(a[:, 5] - 45.0)
    return cost, {"base": lows[0], "mid": lows[1], "tip": lows[2], "deep": deep, "tip_at": tip_at}


def natural(a):
    """What a wrapped finger's bends cost for not looking like a hand's: the last joint follows the middle
    one, and every joint is near a closed grip's (45, 70 and 45 degrees). A degree costs 0.03 to 0.1 mm."""
    cost = 1e-4 * np.abs(a[:, 3] - 0.65 * a[:, 2])
    return cost + 3e-5 * (np.abs(a[:, 1] - 45.0) + np.abs(a[:, 2] - 70.0) + np.abs(a[:, 3] - 45.0))


def start_grid(finger, mode):
    if finger == "thumb":
        root = [-30.0, 0.0, 30.0]
        return np.array(list(itertools.product(root, root, root, [0.0], [0, 25, 50], [0, 30, 60])), float)
    if mode in ("trigger", "frame"):
        spreads = [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]
        return np.array(
            list(itertools.product(spreads, range(-10, 91, 10), range(0, 111, 10), range(0, 81, 20))), float
        )
    return np.array(list(itertools.product([0.0], range(-10, 96, 15), range(0, 111, 15), range(0, 81, 20))), float)


def solve_finger(scene, hand, finger, mode, quick=False, start=None):
    limits = LIMITS.get(finger, LIMITS["finger"])
    grid = start_grid(finger, mode)
    if start is not None:
        grid = np.concatenate([grid, np.atleast_2d(start)])
    cost, _ = finger_cost(scene, hand, finger, grid, mode)
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
            cost, _ = finger_cost(scene, hand, finger, cands, mode)
            if cost.min() < best_cost:
                best_cost = cost.min()
                best = cands[cost.argmin()]
    return best, best_cost


def close_right(scene, quick=False, trigger=True):
    """Closes the right hand on the gun where it sits; returns the total cost and a table."""
    hand = scene.right
    total = 0.0
    table = {}
    modes = {"index": "trigger" if trigger else "frame", "thumb": "thumb"}
    for _ in range(1 if quick else 2):
        total = 0.0
        for finger in FINGERS:
            mode = modes.get(finger, "wrap")
            best, cost = solve_finger(scene, hand, finger, mode, quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
            table[finger] = (mode, best, cost)
    palm = scene.field(hand, hand.points(hand.part["palm"]), hand.part["palm"])
    total += abs(palm.min() - TARGET) + 100.0 * relu(-palm.min() - TOL)
    table["palm"] = palm.min()
    return total, table


def seat_from(scene, params):
    """The seat moved from the old one: metres along the gun's own axes, then degrees about them."""
    d = np.eye(4)
    d[:3, 3] = params[:3]
    d[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    # The hand turns at the wrist by what the seat turned, so the barrel keeps the old seat's line in the forearm.
    r0 = scene.seat0[:3, :3]
    scene.right.wrist = r0 @ d[:3, :3].T @ r0.T
    scene.right._apply_all()
    return scene.seat0 @ d


X, Y, Z = np.eye(3)


def settle(scene, params):
    """Moves the gun across the palm (its own Z) until the palm's skin is TARGET off it; returns the params."""
    params = np.array(params, float)

    def gap(z):
        params[2] = z
        scene.seat = seat_from(scene, params)
        return scene.field(scene.right, scene.right.points(scene.right.part["palm"])).min() - TARGET

    low, high = -0.01, 0.08
    for _ in range(24):
        mid = 0.5 * (low + high)
        if gap(mid) > 0:
            high = mid
        else:
            low = mid
    params[2] = high
    return params


def scan(scene, lists):
    scene.right.stride = 3
    r = scene.rig
    for combo in itertools.product(*lists):
        p = settle(scene, list(combo))
        total, table = seat_score(scene, p)
        row = " ".join(f"{f[:3]} {table[f][2] * 1000:.1f}" for f in FINGERS)
        g = scene.right.glob
        knuckle = scene.to_gun(g[r.index["index_01_r"]][:3, 3][None])[0]
        thumb = scene.to_gun(g[r.index["thumb_01_r"]][:3, 3][None])[0]
        wrist = np.degrees(np.arccos(np.clip((np.trace(scene.right.wrist) - 1) / 2, -1, 1)))
        print(
            "{} dz {:.4f} total {:.1f} | {} | palm {:.1f} | index knuckle {} thumb root {} wrist {:.0f}".format(
                np.round(p[[0, 1, 3, 4, 5]], 3),
                p[2],
                total * 1000,
                row,
                table["palm"] * 1000,
                np.round(knuckle, 3),
                np.round(thumb, 3),
                wrist,
            ),
            flush=True,
        )


def seat_score(scene, params, quick=True):
    scene.seat = seat_from(scene, params)
    for finger in FINGERS:
        scene.right.angles[finger][:] = 0.0
    scene.right._apply_all()
    total, table = close_right(scene, quick)
    r = scene.rig
    root = scene.to_gun(scene.right.glob[r.index["thumb_01_r"]][:3, 3][None])[0]
    total += 0.2 * relu(WEB_Y - root[1])
    # The wrist turns by what the seat turned: past 30 degrees it costs.
    wrist = np.degrees(np.arccos(np.clip((np.trace(scene.right.wrist) - 1) / 2, -1, 1)))
    total += 1e-3 * relu(wrist - 30.0)
    table["wrist"] = wrist
    return total, table


def search_seat(scene, start, rounds, quick=True):
    best = np.array(start, float)
    best_cost, _ = seat_score(scene, best, quick)
    print("seat start", np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    for step_m, step_deg in rounds:
        improved = True
        while improved:
            improved = False
            for k in range(6):
                for sign in (-1.0, 1.0):
                    cand = best.copy()
                    cand[k] += sign * (step_m if k < 3 else step_deg)
                    if k >= 3 and abs(cand[k]) > 40.0:
                        continue
                    cost, _ = seat_score(scene, cand, quick)
                    if cost < best_cost - 1e-6:
                        best, best_cost, improved = cand, cost, True
            print("  step", step_m, step_deg, np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    return best, best_cost


MIRROR_GUN = np.diag([1.0, 1.0, -1.0])
MIRROR_BONE = np.diag([-1.0, 1.0, 1.0])
LEFT_PIVOT = np.array([-0.03, 0.0, 0.0])


def place_left(scene, params):
    """Puts the left hand on the gun: the right hand's place mirrored, then moved by `params` (gun axes)."""
    right_in_gun = np.linalg.inv(scene.seat)
    mirrored = np.eye(4)
    mirrored[:3, :3] = MIRROR_GUN @ right_in_gun[:3, :3] @ MIRROR_BONE
    mirrored[:3, 3] = MIRROR_GUN @ right_in_gun[:3, 3]
    turn = np.eye(4)
    turn[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    turn[:3, 3] = LEFT_PIVOT - turn[:3, :3] @ LEFT_PIVOT + np.array(params[:3])
    in_gun = turn @ mirrored
    hand = scene.left
    hand.move = np.eye(4)
    hand._apply_all()
    hand.move = scene.gun_global() @ in_gun @ np.linalg.inv(hand.hand_global())
    hand._apply_all()
    return in_gun


def close_left(scene, quick=False):
    hand = scene.left
    total = 0.0
    table = {}
    for _ in range(1 if quick else 2):
        total = 0.0
        for finger in FINGERS:
            mode = "thumb" if finger == "thumb" else "over"
            best, cost = solve_finger(scene, hand, finger, mode, quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
            table[finger] = (mode, best, cost)
    # The heel of the palm fills the side of the grip the shooting hand leaves open: the palm is on the
    # gun itself, not only on the other hand's fingertips.
    to_gun, to_hand = scene.palm(hand)
    low = min(to_gun.min(), to_hand.min())
    total += abs(low - TARGET) + 100.0 * relu(-low - TOL) + 0.5 * relu(to_gun.min() - OVER_NEAR)
    table["palm"] = low
    table["heel on the gun"] = to_gun.min()
    return total, table


def left_score(scene, params, quick=True):
    place_left(scene, params)
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    scene.left._apply_all()
    return close_left(scene, quick)


def search_left(scene, start, rounds):
    best = np.array(start, float)
    best_cost, _ = left_score(scene, best)
    print("left start", np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    for step_m, step_deg in rounds:
        improved = True
        while improved:
            improved = False
            for k in range(6):
                for sign in (-1.0, 1.0):
                    cand = best.copy()
                    cand[k] += sign * (step_m if k < 3 else step_deg)
                    cost, _ = left_score(scene, cand)
                    if cost < best_cost - 1e-6:
                        best, best_cost, improved = cand, cost, True
            print("  left step", step_m, step_deg, np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    return best


def put_left(scene, in_gun):
    """Moves the left hand, as its fingers are, to a place given in the gun."""
    hand = scene.left
    hand.move = np.eye(4)
    hand._apply_all()
    hand.move = scene.gun_global() @ in_gun @ np.linalg.inv(hand.hand_global())
    hand._apply_all()


def place_magazine(scene, support, params):
    """Puts the left hand under the magazine: its place on the gun (`support`, in the gun) turned and moved by
    `params` (gun axes, about the middle of the magazine's base), then pushed up the gun's Y from below until
    the palm's skin is TARGET off a surface."""
    turn = np.eye(4)
    turn[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    turn[:3, 3] = MAGAZINE_BASE - turn[:3, :3] @ MAGAZINE_BASE + np.array(params[:3])
    start = turn @ support
    hand = scene.left
    palm = hand.part["palm"]

    def put(lift):
        in_gun = start.copy()
        in_gun[1, 3] += lift
        put_left(scene, in_gun)
        return in_gun

    def gap(lift):
        put(lift)
        return scene.field(hand, hand.points(palm), palm).min() - TARGET

    # Up from well below in 1 mm steps to the first touch (past the gun the palm is clear again, so no
    # bisection over the whole way), then to the place between the last two steps.
    low = -0.15
    while low < 0.1 and gap(low + 0.001) > 0:
        low += 0.001
    high = low + 0.001
    for _ in range(12):
        mid = 0.5 * (low + high)
        if gap(mid) > 0:
            low = mid
        else:
            high = mid
    return put(low)


def close_magazine(scene, quick=False):
    hand = scene.left
    total = 0.0
    for _ in range(1 if quick else 2):
        total = 0.0
        for finger in FINGERS:
            best, cost = solve_finger(scene, hand, finger, "cup", quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
    return total


def reach(scene, in_gun):
    """How far the left shoulder is from the left hand's place in every dumped aim and shoot pose, metres."""
    r = scene.rig
    arm = np.linalg.norm(r.rest[r.index["lowerarm_l"]][:3, 3]) + np.linalg.norm(r.rest[r.index["hand_l"]][:3, 3])
    rows = []
    for name, pose in r.poses.items():
        if "Aim" not in name and "Shoot" not in name:
            continue
        local = pose.copy()
        local[scene.right.hand][:3, :3] = local[scene.right.hand][:3, :3] @ scene.right.wrist
        g = r.fk(local)
        target = (g[scene.right.hand] @ scene.seat @ in_gun)[:3, 3]
        rows.append((name, np.linalg.norm(target - g[r.index["upperarm_l"]][:3, 3])))
    return arm, rows


def report(scene, hand, tag):
    pts = hand.points()
    sd = scene.field(hand, pts)
    model = scene.rig.model[hand.ids]
    for which, name in enumerate(("female", "male")):
        line = []
        for part, idx in hand.part.items():
            line.append(f"{part} {sd[idx[model[idx] == which]].min() * 1000.0:.1f}")
        print(tag, name, ", ".join(line), flush=True)


def option(name, default):
    """The numbers of `--name=a,b,...` on the command line, or `default`."""
    for argument in sys.argv:
        if argument.startswith(f"--{name}="):
            return [float(value) for value in argument.split("=", 1)[1].split(",")]
    return default


def main():
    rigs, pistol = R.load(sys.argv[1])
    scene = Scene(R.merged(rigs["female"], rigs["male"]), pistol, sys.argv[1] + ".gun.npz")
    started = time.time()
    for argument in sys.argv:
        if argument.startswith("--scan="):
            scan(scene, [[float(v) for v in part.split(",")] for part in argument[7:].split(";")])
            return
    rounds = [(0.008, 4.0), (0.004, 2.0), (0.002, 1.0), (0.001, 0.5)]
    if "--magazine-only" in sys.argv:
        magazine_only(scene, started)
        return
    if "--way-only" in sys.argv:
        way_only(scene, started)
        return
    if "--left-only" in sys.argv:
        out = restore(scene)
    else:
        out = solve_right(scene, rounds, started)
    out.update(solve_left(scene, out, rounds, started))
    out.update(solve_trigger_way(scene, out, started))
    if "--hold-only" not in sys.argv:
        out.update(solve_magazine(scene, out, np.array(out["support_hand"]), started))
        out.update(solve_way(scene, out, started))
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())


def solve_right(scene, rounds, started):
    """The seat and the right hand: its fingers round the grip, the index finger along the frame and on the
    trigger."""
    best = settle(scene, option("seat", SEAT))
    if "--search-seat" in sys.argv:
        scene.right.stride = 3
        best, _ = search_seat(scene, best, rounds)
        scene.right.stride = 1
    scene.seat = seat_from(scene, best)
    for finger in FINGERS:
        scene.right.angles[finger][:] = 0.0
    scene.right._apply_all()
    total, table = close_right(scene, quick=False, trigger=False)
    grip = scene.right.quaternions()
    angles = {finger: scene.right.angles[finger].tolist() for finger in FINGERS}
    report(scene, scene.right, "right (frame)")
    on_trigger, _ = solve_finger(scene, scene.right, "index", "trigger", False)
    scene.right.set("index", on_trigger)
    trigger = scene.right.quaternions(["index"])
    report(scene, scene.right, "right (trigger)")
    scene.right.set("index", angles["index"])
    for finger, row in table.items():
        print(" ", finger, row)
    print(
        "seat",
        np.round(best, 4).tolist(),
        "right total %.2f mm" % (total * 1000),
        "in %.0f s" % (time.time() - started),
        flush=True,
    )
    return {
        "angles": {"right": angles, "trigger": on_trigger.tolist()},
        "seat_params": best.tolist(),
        "seat": scene.seat.tolist(),
        "wrist": R.mat_to_quat(scene.right.wrist).tolist(),
        "grip": grip,
        "trigger": trigger,
    }


def restore(scene):
    """The seat and the right hand of the solve in the output file, the index finger along the frame."""
    with open(sys.argv[2], "rb") as file:
        out = json.load(file)
    scene.seat = seat_from(scene, np.array(out["seat_params"]))
    for finger in FINGERS:
        scene.right.angles[finger] = np.array(out["angles"]["right"][finger], float)
    scene.right._apply_all()
    return out


def index_poses(out, way=True):
    """The poses of the trigger finger other than along the frame, for `Scene.freeze`: on the trigger and,
    once it is solved, half-way there."""
    poses = [("index", np.array(out["angles"]["trigger"]))]
    if way and "trigger_way" in out["angles"]:
        poses.append(("index", np.array(out["angles"]["trigger_way"])))
    return poses


def solve_left(scene, out, rounds, started):
    """The left hand on the gun and over the right hand, whose trigger finger is along the frame or on the
    trigger: its place, then its fingers."""
    scene.frozen.pop("l", None)
    scene.freeze(scene.right, index_poses(out, way=False))
    left = np.array(option("left", LEFT))
    if "--search-left" in sys.argv:
        scene.left.stride = 3
        left = search_left(scene, left, rounds)
        scene.left.stride = 1
    in_gun = place_left(scene, left)
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    scene.left._apply_all()
    total, left_table = close_left(scene)
    report(scene, scene.left, "left")
    for finger, row in left_table.items():
        print(" ", finger, row)
    arm, rows = reach(scene, in_gun)
    print(f"left arm {arm:.3f} m;", ", ".join("{} {:.3f}".format(n.split("/")[1], d) for n, d in rows))
    print(
        "left", np.round(left, 4).tolist(), "total %.2f mm" % (total * 1000), "in %.0f s" % (time.time() - started),
        flush=True,
    )
    out["angles"]["left"] = {finger: scene.left.angles[finger].tolist() for finger in FINGERS}
    return {"left_params": left.tolist(), "support_hand": in_gun.tolist(), "support": scene.left.quaternions()}


def blended(start, ends, shares):
    """Rotations between `start` (3, 3) and each of `ends` (K, 3, 3) at `shares` (S,), the short way round as
    Godot's `Quaternion.slerp` goes: (K * S, 3, 3), a row of `ends` after the other."""
    first = Rotation.from_matrix(start).as_quat()
    last = Rotation.from_matrix(ends).as_quat()
    dot = last @ first
    last = np.where(dot[:, None] < 0.0, -last, last)
    angle = np.arccos(np.clip(np.abs(dot), 0.0, 1.0))[:, None, None]
    share = np.asarray(shares)[None, :, None]
    near = angle < 1e-6
    sine = np.where(near, 1.0, np.sin(angle))
    from_start = np.where(near, 1.0 - share, np.sin((1.0 - share) * angle) / sine)
    from_end = np.where(near, share, np.sin(share * angle) / sine)
    mixed = from_start * first[None, None, :] + from_end * last[:, None, :]
    return Rotation.from_quat(mixed.reshape(-1, 4)).as_matrix()


def open_grid(finger, held):
    """The poses a finger may open to from `held`: the knuckle straighter, the other joints either way."""
    limits = LIMITS.get(finger, LIMITS["finger"])
    if finger == "thumb":
        steps = [-16.0, -8.0, 0.0, 8.0, 16.0]
        grid = [
            held + np.array([a, b, c, 0.0, e, 0.0]) for a in steps for b in steps for c in steps for e in (-10.0, 0.0)
        ]
    else:
        grid = itertools.product(
            held[0] + np.array([-10.0, -5.0, 0.0, 5.0, 10.0]),
            np.arange(held[1] % 5.0 - 15.0, held[1] + 0.1, 5.0),
            np.append(np.arange(held[2] % 15.0, held[2] + 0.1, 15.0), [held[2] + 11.5, held[2] + 23.0]),
            np.append(np.arange(held[3] % 20.0, held[3] + 0.1, 20.0), [held[3] + 20.0]),
        )
    return np.clip(np.array(list(grid), float), limits[:, 0], limits[:, 1])


def open_finger(scene, hand, finger):
    """Opens one finger of a hand that holds: the pose nearest the held one that lifts it `OPEN_CLEAR` off
    every surface (or as far as it gets) with nothing deeper than `WAY_TOL` in every pose between, the bones
    blended as the game blends them. Returns the angles, the deepest on the way and how far off it ends."""
    held = hand.angles[finger].copy()
    grid = open_grid(finger, held)
    shares = np.linspace(0.0, 1.0, WAY_STEPS + 1)[1:]
    which = hand.finger_verts[finger]
    deepest = np.empty(len(grid))
    clear = np.empty(len(grid))
    # A few hundred poses at a time: every pose is measured at every share on every vertex.
    for first in range(0, len(grid), 400):
        rows = grid[first : first + 400]
        turned = [
            blended(a[0], b, shares)
            for a, b in zip(local_rotations(finger, held), local_rotations(finger, rows), strict=True)
        ]
        off = scene.field(hand, hand.finger_points_turned(finger, turned), which)
        off = off.reshape(len(rows), len(shares), -1)
        deepest[first : first + 400] = off.min(axis=(1, 2))
        clear[first : first + 400] = off[:, -1].min(axis=1)
    # A degree of change costs 0.03 mm, so the nearest pose that is clear enough wins.
    cost = 100.0 * relu(-deepest - WAY_TOL) + relu(OPEN_CLEAR - clear) + 3e-5 * np.abs(grid - held).sum(axis=1)
    best = cost.argmin()
    return grid[best], deepest[best], clear[best]


def trigger_grid(frame, trigger):
    """The poses the trigger finger may pass through between `frame` and `trigger`: every lean and bend from
    one to the other and some past them (it may curl in or straighten to get by)."""
    spans = []
    for index, (low, high, step) in enumerate(((0.0, 0.0, 4.0), (10.0, 10.0, 6.0), (10.0, 30.0, 8.0), (0.0, 20.0, 10.0))):
        first, last = sorted((frame[index], trigger[index]))
        spans.append(np.arange(first - low, last + high + 0.1, step))
    limits = LIMITS["index"]
    return np.clip(np.array(list(itertools.product(*spans)), float), limits[:, 0], limits[:, 1])


def trigger_depths(scene, frame, via, trigger, steps=TRIGGER_STEPS):
    """How far off every surface the trigger finger's skin is at each of `steps` equal parts of its way from
    `frame` through each row of `via` to `trigger` (angles), the bones blended as the game blends them:
    (K, steps + 1, N)."""
    hand = scene.right
    which = hand.finger_verts["index"]
    half = np.linspace(0.0, 1.0, steps // 2 + 1)
    out = []
    for first in range(0, len(via), 400):
        rows = via[first : first + 400]
        legs = []
        for end, shares in ((frame, half), (trigger, half[::-1][1:])):
            turned = [
                blended(a[0], b, shares)
                for a, b in zip(local_rotations("index", end), local_rotations("index", rows), strict=True)
            ]
            off = scene.field(hand, hand.finger_points_turned("index", turned), which)
            legs.append(off.reshape(len(rows), len(shares), -1))
        out.append(np.concatenate(legs, axis=1))
    return np.concatenate(out)


def solve_trigger_way(scene, out, started):
    """The trigger finger's way between the frame and the trigger (kit #1079), against the gun and the left
    hand where it holds: the pose it passes through half-way, the nearest to both ends with nothing deeper
    than `WAY_TOL` at any twentieth of the way. The straight blend leaves the guard on the gun's far side,
    through the left thumb."""
    hand = scene.right
    frame = np.array(out["angles"]["right"]["index"])
    trigger = np.array(out["angles"]["trigger"])
    scene.freeze(scene.left)

    def cost(via):
        deepest = trigger_depths(scene, frame, via, trigger).min(axis=(1, 2))
        travel = np.abs(via - frame).sum(axis=1) + np.abs(via - trigger).sum(axis=1)
        return 100.0 * relu(-deepest - WAY_TOL) + 3e-5 * travel

    straight = trigger_depths(scene, frame, 0.5 * (frame + trigger)[None], trigger).min()
    grid = trigger_grid(frame, trigger)
    costs = cost(grid)
    best, best_cost = grid[costs.argmin()], costs.min()
    rng = np.random.default_rng(1)
    limits = LIMITS["index"]
    for scale in (4.0, 2.0, 1.0, 0.5):
        for _ in range(3):
            steps = np.concatenate([np.eye(4), -np.eye(4), rng.integers(-1, 2, size=(200, 4))])
            cands = np.clip(best + scale * steps, limits[:, 0], limits[:, 1])
            costs = cost(cands)
            if costs.min() < best_cost:
                best, best_cost = cands[costs.argmin()], costs.min()
    off = trigger_depths(scene, frame, best[None], trigger)[0]
    model = scene.rig.model[hand.ids][hand.finger_verts["index"]]
    passes = [float(-off[:, model == index].min()) for index in range(scene.rig.model.max() + 1)]
    hand.set("index", best)
    via = hand.quaternions(["index"])
    hand.set("index", frame)
    print(
        "trigger way",
        np.round(frame, 1),
        "by",
        np.round(best, 1),
        "to",
        np.round(trigger, 1),
        "passes",
        ", ".join("%s %.1f mm" % (name, depth * 1000) for name, depth in zip(("female", "male"), passes, strict=False)),
        "(straight: %.1f mm)" % (-straight * 1000),
        "in %.0f s" % (time.time() - started),
        flush=True,
    )
    out["angles"]["trigger_way"] = best.tolist()
    return {"trigger_way": via, "trigger_way_passes": passes}


def directions(step):
    """Unit vectors `step` degrees apart over the whole sphere: (D, 3)."""
    out = [[0.0, 1.0, 0.0], [0.0, -1.0, 0.0]]
    for lift in np.radians(np.arange(-90.0 + step, 90.0, step)):
        for turn in np.radians(np.arange(0.0, 360.0, step / max(np.cos(lift), 0.2))):
            out.append([np.cos(lift) * np.cos(turn), np.sin(lift), np.cos(lift) * np.sin(turn)])
    return np.array(out)


def way_out(scene, toward):
    """The straight line the opened left hand leaves the gun along, as a unit vector in the gun's space: of the
    directions in which nothing passes deeper than `WAY_TOL` over `WAY_LENGTH` (nor in the directions next
    to it, so a hand a little off the line is clear too), the one nearest `toward`."""
    hand = scene.left
    points = hand.points()
    turn = scene.gun_global()[:3, :3]
    tried = directions(WAY_GRID)
    steps = np.linspace(0.0, WAY_LENGTH, WAY_STEPS + 1)
    deepest = np.empty(len(tried))
    for index, direction in enumerate(tried):
        moved = points[None] + steps[:, None, None] * (turn @ direction)[None, None, :]
        deepest[index] = scene.field(hand, moved).min()
    clear = deepest > -WAY_TOL
    near = tried @ tried.T > np.cos(np.radians(1.5 * WAY_GRID))
    safe = np.array([clear[near[index]].all() for index in range(len(tried))])
    if not safe.any():
        raise SystemExit("way_out: the opened hand passes through something in every direction")
    angle = np.degrees(np.arccos(np.clip(tried @ toward, -1.0, 1.0)))
    best = np.where(safe, angle, np.inf).argmin()
    return tried[best], angle[best], deepest[best], int(safe.sum())


def way_depths(scene, held, opened, way):
    """The deepest the left hand passes on its whole way off the gun, per mannequin, in metres: its fingers
    blended from `held` to `opened` (angles) where it holds, then the opened hand moved along `way`."""
    hand = scene.left
    model = scene.rig.model[hand.ids]
    shares = np.linspace(0.0, 1.0, 2 * WAY_STEPS + 1)
    deepest = np.zeros(scene.rig.model.max() + 1)

    def measure(points):
        off = scene.field(hand, points)
        for index in range(len(deepest)):
            deepest[index] = min(deepest[index], off[model == index].min())

    for share in shares:
        for finger in FINGERS:
            turned = [
                blended(a[0], b, [share])
                for a, b in zip(
                    local_rotations(finger, held[finger]), local_rotations(finger, opened[finger]), strict=True
                )
            ]
            for bone, rot in zip(hand.chains[finger], turned, strict=True):
                hand.local[bone][:3, :3] = scene.rig.rest[bone][:3, :3] @ rot[0]
        hand.glob = scene.rig.fk(hand.local)
        for bone in hand.arm:
            hand.glob[bone] = hand.move @ hand.glob[bone]
        measure(hand.points())
    points = hand.points()
    turn = scene.gun_global()[:3, :3]
    for share in shares:
        measure(points + share * WAY_LENGTH * (turn @ way))
    return -deepest


def solve_way(scene, out, started):
    """The left hand's way off the gun and back onto it, against the gun and the right hand with its trigger
    finger wherever it may be (along the frame, on the trigger, between: the hand comes on as the finger
    goes to the trigger): the opened pose and the line the opened hand leaves along."""
    for finger in FINGERS:
        scene.right.angles[finger] = np.array(out["angles"]["right"][finger], float)
    scene.right._apply_all()
    scene.freeze(scene.right, index_poses(out))
    support = np.array(out["support_hand"])
    hand = scene.left
    held = hand.angles_of(out["support"])
    for finger in FINGERS:
        hand.angles[finger] = held[finger].copy()
    put_left(scene, support)
    opened = {}
    for finger in FINGERS:
        opened[finger], deepest, clear = open_finger(scene, hand, finger)
        print(
            "open",
            finger,
            np.round(held[finger], 1),
            "to",
            np.round(opened[finger], 1),
            "passes %.1f mm, ends %.1f mm off" % (-deepest * 1000, clear * 1000),
            flush=True,
        )
    for finger in FINGERS:
        hand.set(finger, opened[finger])
    report(scene, hand, "open")
    # The way to the belt, from where the hand holds to where the clip has it there, in the gun.
    rig = scene.rig
    local = rig.poses[BELT_POSE].copy()
    local[scene.right.hand][:3, :3] = local[scene.right.hand][:3, :3] @ scene.right.wrist
    posed = rig.fk(local)
    belt = np.linalg.inv(posed[scene.right.hand] @ scene.seat) @ posed[hand.hand]
    toward = belt[:3, 3] - support[:3, 3]
    toward /= np.linalg.norm(toward)
    way, off_line, deepest, count = way_out(scene, toward)
    print(
        "way",
        np.round(way, 4).tolist(),
        "toward the belt",
        np.round(toward, 3).tolist(),
        "%.0f degrees off it, of %d clear directions; passes %.1f mm" % (off_line, count, -deepest * 1000),
    )
    quaternions = hand.quaternions()
    passes = way_depths(scene, held, opened, way)
    print(
        "way passes",
        ", ".join("%s %.1f mm" % (name, depth * 1000) for name, depth in zip(("female", "male"), passes, strict=False)),
        "in %.0f s" % (time.time() - started),
        flush=True,
    )
    return {"open": quaternions, "way": (WAY_LENGTH * way).tolist(), "way_passes": passes.tolist()}


def solve_magazine(scene, out, support, started):
    """The left hand under the magazine, against the gun and the right hand with its finger off the trigger."""
    for finger in FINGERS:
        scene.right.angles[finger] = np.array(out["angles"]["right"][finger], float)
    scene.right._apply_all()
    scene.freeze(scene.right)
    params = np.array(option("magazine", MAGAZINE))
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    # The palm's skin near the knuckles follows the fingers: the hand is seated again under the closed fingers
    # and they are closed again there, three times.
    for _ in range(3):
        in_gun = place_magazine(scene, support, params)
        total = close_magazine(scene)
    report(scene, scene.left, "magazine")
    print(
        "magazine", np.round(params, 4).tolist(), "total %.2f mm" % (total * 1000), "in %.0f s" % (time.time() - started)
    )
    return {
        "magazine_params": params.tolist(),
        "magazine_hand": in_gun.tolist(),
        "magazine": scene.left.quaternions(),
    }


def magazine_only(scene, started):
    """Solves only the left hand under the magazine, on the seat and the right hand of the solve in the output
    file, and adds it to that file."""
    out = restore(scene)
    out.update(solve_magazine(scene, out, np.array(out["support_hand"]), started))
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())


def way_only(scene, started):
    """Solves only the left hand's way off the gun, on the hold of the solve in the output file, and adds it
    to that file."""
    out = restore(scene)
    out.update(solve_way(scene, out, started))
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())


if __name__ == "__main__":
    main()
