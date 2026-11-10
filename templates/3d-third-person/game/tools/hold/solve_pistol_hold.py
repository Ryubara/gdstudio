"""Solves how the mannequin's hands hold the pistol (kit #1001), from the dump `dump_hold_rig.gd` writes.

    <godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
    uv run --no-project --with numpy --with scipy python tools/hold/solve_pistol_hold.py <abs>/rig.json <abs>/hold.json
    <godot> --headless --path game -s res://tools/hold/write_hold.gd -- <abs>/hold.json

It skins both mannequins' hands on the CPU as Godot does and measures them against the pistol's closed pieces on a
1 mm grid (and, for the left hand, against the right hand of the same mannequin), so a pose is right for both at
once. With no option it solves the fingers for the seat and the left hand's place below (the hold the template
ships, about 5 minutes); `--search-seat` and `--search-left` search those again from there (4 to 6 minutes each),
`--seat=` and `--left=` give other starts, and `--scan=` prints a table of seats to choose from.

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
from hold_hand import FINGERS, LIMITS, Hand

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
WEB_Y = 0.07  # how high on the gun the thumb's root should sit (the web under the tang)
FRAME_Y = 0.079
# The pistol on `hand_r` as kit #834 seated it (basis columns, then the origin): the barrel line the aim clips
# were captured with, 1.5 degrees up and 3 degrees out in `Pistol_Aim_Neutral`.
REFERENCE_SEAT = [0.0234, -0.9867, 0.1609, -0.0805, 0.1585, 0.9841, -0.9965, -0.036, -0.0757, -0.0264, 0.1234, 0.0091]
# The seat the template ships, as a move from the reference, and the left hand's place as a move from the right
# hand's mirrored across the pistol.
SEAT = [0.022, -0.035, 0.0306, -4.0, -23.5, -15.5]
LEFT = [-0.017, -0.03, 0.009, -8.0, 1.5, 0.0]
# The grid of the gun's distance: the whole gun (muzzle at -0.207) and a hand's thickness round it.
GRID_LOW = [-0.24, -0.09, -0.075]
GRID_HIGH = [0.08, 0.17, 0.075]


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
        self.other = None  # the right hand's skin as a field, for the left hand

    def gun_global(self):
        return self.right.hand_global() @ self.seat

    def to_gun(self, points):
        g = self.gun_global()
        return (points - g[:3, 3]) @ g[:3, :3]

    def field(self, hand, points, which=None):
        """The distance from a hand's points to what it holds: the gun and, for the left hand, the right
        hand of the same mannequin (`which` picks the hand's vertices the points are, all by default)."""
        d = self.gun(self.to_gun(points))
        if hand is self.left and self.other is not None:
            ids = hand.ids if which is None else hand.ids[which]
            model = self.rig.model[ids]
            for index, other in enumerate(self.other):
                mine = model == index
                d[..., mine] = np.minimum(d[..., mine], other(points[..., mine, :]))
        return d

    def freeze_right(self):
        """The right hand as it holds the gun becomes a surface for the left hand, on a grid in the gun's space."""
        points = self.to_gun(self.right.points())
        self.other = []
        for index in range(self.rig.model.max() + 1):
            # The triangles of this mannequin's right hand, as indices into the hand's own points.
            mine = self.rig.model[self.right.ids][self.right.tris[:, 0]] == index
            grid = hold_field.PiecesField(
                points[self.right.tris[mine]], [-0.17, -0.09, -0.12], [0.10, 0.16, 0.09], 0.0015, rays=(0, 1, 2)
            )
            self.other.append(lambda at, grid=grid: grid(self.to_gun(at)))


def finger_cost(scene, hand, finger, angles, mode):
    """The cost of each row of angles for one finger, and what was measured: (K,), dict."""
    pts = hand.finger_points(finger, angles)
    sd = scene.field(hand, pts, hand.finger_verts[finger][:: hand.stride])
    base, mid, tip = hand.finger_parts(finger)
    lows = [sd[:, p].min(axis=1) for p in (base, mid, tip)]
    # A search that measures every third vertex keeps 0.4 mm in hand, so the full measure agrees.
    deep = relu(-sd.min(axis=1) - (TOL if hand.stride == 1 else TOL - 0.0004))
    cost = 100.0 * deep
    a = np.atleast_2d(angles)
    tip_at = scene.to_gun(pts[:, tip].mean(axis=1))
    mid_at = scene.to_gun(pts[:, mid].mean(axis=1))
    touch = [np.abs(low - TARGET) for low in lows]
    if mode == "wrap":
        cost += touch[2] + touch[1] + 0.5 * touch[0] + natural(a)
        if hand.side == "l" and finger == "index":
            # The support hand's index finger lies under the trigger guard, not beside it.
            cost += relu(mid_at[:, 1] - UNDER_GUARD_Y) + relu(tip_at[:, 1] - UNDER_GUARD_Y)
    elif mode == "trigger":
        want = scene.sockets["Trigger"][:3, 3] + TRIGGER_OFF
        cost += 0.7 * np.linalg.norm(tip_at - want, axis=1) + 0.5 * touch[2]
        cost += 1e-4 * np.abs(a[:, 3] - 0.65 * a[:, 2])
    elif mode == "frame":
        # Straight along the gun's right side, outside the trigger guard, as high as the knuckle lets it.
        cost += touch[2] + touch[1] + 2e-4 * (a[:, 2] + a[:, 3])
        cost += relu(tip_at[:, 2] + 0.014) + relu(mid_at[:, 2] + 0.014)
        cost += 0.1 * relu(FRAME_Y - tip_at[:, 1])
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
            mode = "thumb" if finger == "thumb" else "wrap"
            best, cost = solve_finger(scene, hand, finger, mode, quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
            table[finger] = (mode, best, cost)
    palm = scene.field(hand, hand.points(hand.part["palm"]), hand.part["palm"])
    total += abs(palm.min() - TARGET) + 100.0 * relu(-palm.min() - TOL)
    table["palm"] = palm.min()
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
    report(scene, scene.right, "right (frame)")
    on_trigger, _ = solve_finger(scene, scene.right, "index", "trigger", False)
    scene.right.set("index", on_trigger)
    trigger = scene.right.quaternions(["index"])
    report(scene, scene.right, "right (trigger)")
    for finger, row in table.items():
        print(" ", finger, row)
    print(
        "seat",
        np.round(best, 4).tolist(),
        "right total %.2f mm" % (total * 1000),
        "in %.0f s" % (time.time() - started),
    )
    scene.freeze_right()
    left = np.array(option("left", LEFT))
    if "--search-left" in sys.argv:
        scene.left.stride = 3
        left = search_left(scene, left, rounds)
        scene.left.stride = 1
    in_gun = place_left(scene, left)
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    scene.left._apply_all()
    _, left_table = close_left(scene)
    report(scene, scene.left, "left")
    for finger, row in left_table.items():
        print(" ", finger, row)
    arm, rows = reach(scene, in_gun)
    print(f"left arm {arm:.3f} m;", ", ".join("{} {:.3f}".format(n.split("/")[1], d) for n, d in rows))
    print("left", np.round(left, 4).tolist(), "in %.0f s" % (time.time() - started))
    out = {
        "seat_params": best.tolist(),
        "seat": scene.seat.tolist(),
        "wrist": R.mat_to_quat(scene.right.wrist).tolist(),
        "grip": grip,
        "trigger": trigger,
        "left_params": left.tolist(),
        "support_hand": in_gun.tolist(),
        "support": scene.left.quaternions(),
    }
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())


if __name__ == "__main__":
    main()
