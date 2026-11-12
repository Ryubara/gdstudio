"""Plans the rifle's trigger finger's way from along the receiver to the trigger (kit #1283), on the dump
`solve_trigger_way.gd --dump=` writes, and writes the poses between the two ends for `solve_trigger_way.gd --way=`
to check with the game's own measure and write.

    uv run --no-project --with numpy --with scipy python tools/hold/plan_trigger_way.py <abs>/way_female.json \
        <abs>/way_female_out.json [--limit=<mm>]

The game blends each of the finger's three bones from one pose of the way to the next (a slerp, the legs spread
evenly over the raise, `HandPoseModifier.second_way`), so a way is a list of poses and each leg between two of them
must keep the skin out of the rifle. The straight way between the ends goes 20 to 24 mm through the magazine well
and the trigger guard, and a way of two poses between (the finger rolled about its length, then bent) still passed
2.4 to 4.6 mm; this finds one within `--limit` (1.5 mm by default, under the hold's 2 mm, so the grid's error and
the game's own skinning leave room) as a path search over many poses:

- a pose is five angles on top of the bones' rests: the knuckle's spread, bend and roll (`index_01`, turned in that
  order) and the two joints' bends (`index_02`, `index_03`), within `LIMITS`, which keep the roll small: a finger
  does not turn about its own length, so the finger comes off the receiver's side by its knuckle and curls;
- a pose is measured as the game measures it: every vertex of the finger's skin that `HandContact` counts, skinned
  from the bone poses of the hold at the low ready, against the rifle's signed distance on a grid (the rifle's
  closed pieces, inside by a ray along Z, as `HandContact` and `hold_field.PiecesField` count it);
- `plan_way` grows a tree of poses from each end (RRT-connect: Kuffner and LaValle 2000) until they meet, every leg
  measured at steps that move the fingertip at most `STEP_MM`, then shortens the path: from each pose it goes
  straight to the farthest later pose it can reach.

`FingerChain` and `plan_way` know nothing of the rifle: a finger of any held weapon (the pistol's trigger finger,
kit #1272) plans the same way from its own dump and depth function.
"""

import json
import sys

import hold_field
import numpy as np
import solve_rifle_hold
from scipy.spatial.transform import Rotation as Rot

BONES = ("index_01_r", "index_02_r", "index_03_r")
# The grid of poses searched, in degrees: the knuckle's spread (Z), bend (X) and roll (Y), then the middle and
# last joints' bends (X), each from, to and by. The knuckle bends back (negative) up to 35 degrees, as a finger
# lifted off a gun's side does, and turns about its own length by no more than 35 degrees (a finger has a little
# of that turn at the knuckle, not a half turn): with the roll held at 0 no way passed less than 5.5 mm, at -30 one
# passes clear (kit #1283).
AXES = (
    np.arange(-10.0, 35.01, 3.0),
    np.arange(-35.0, 20.01, 3.0),
    np.arange(-35.0, 15.01, 5.0),
    np.arange(-5.0, 110.01, 3.0),
    np.arange(-5.0, 85.01, 3.0),
)
# How far off the surface the way leaves each end before the grid's walk takes over, in metres, and the step of
# how far round it (each way on every angle) and by what step that is searched, in degrees.
ESCAPE_CLEAR = 0.0005
ESCAPE_SPAN = 12.0
ESCAPE_STEP = 1.5
# How far off the surface the walk through the grid keeps, in metres, the first that joins the two ends.
CLEARANCES = (0.002, 0.001, 0.0005, 0.0, -0.0005, -0.001)
# How far the fingertip may move between two measured steps of a leg, in millimetres.
STEP_MM = 0.25
# How far each bone's skin reaches from its joint, in metres: what a degree of it moves the tip.
LEVERS = (0.09, 0.05, 0.025)
# The grid of the rifle's signed distance near the finger, in metres, exact within `GRID_BAND` of the surface
# (`solve_rifle_hold.BandField`; farther off a coarse grid's value stands).
GRID_STEP = 0.0005
GRID_MARGIN = 0.015
GRID_BAND = 0.006


def option(name, default):
    for argument in sys.argv:
        if argument.startswith(f"--{name}="):
            return type(default)(argument.split("=", 1)[1])
    return default


def transform(numbers):
    """A transform as the dump writes it (the basis's columns, then the origin) as a 4 x 4."""
    out = np.eye(4)
    out[:3, 0], out[:3, 1], out[:3, 2], out[:3, 3] = numbers[0:3], numbers[3:6], numbers[6:9], numbers[9:12]
    return out


def slerp(a, b, share):
    """Godot's `Quaternion.slerp` row by row (x, y, z, w; the shorter way round): (..., 4)."""
    dot = np.sum(a * b, axis=-1, keepdims=True)
    b = np.where(dot < 0.0, -b, b)
    dot = np.abs(dot)
    share = np.asarray(share)[..., None]
    angle = np.arccos(np.clip(dot, -1.0, 1.0))
    small = angle < 1e-6
    sine = np.where(small, 1.0, np.sin(angle))
    first = np.where(small, 1.0 - share, np.sin((1.0 - share) * angle) / sine)
    second = np.where(small, share, np.sin(share * angle) / sine)
    return first * a + second * b


class FingerChain:
    """One finger's three bones and their skin, from a dump: poses (K, 3, 4) of quaternions to skinned points in
    the weapon's space (K, N, 3), as the game's `HandContact.pose_chain` and skinning work them out."""

    def __init__(self, dump):
        self.poses = {int(bone): transform(numbers) for bone, numbers in dump["poses"].items()}
        self.chain = dump["chain"]
        self.rests = Rot.from_quat([entry["rest"] for entry in self.chain])
        self.to_weapon = transform(dump["to_weapon"])
        slots = [slot for part in dump["parts"].values() for vertex in part for slot in vertex]
        counts = [len(vertex) for part in dump["parts"].values() for vertex in part]
        self.count = len(counts)
        self.vertex = np.repeat(np.arange(self.count), counts)
        self.bone = np.array([int(slot[0]) for slot in slots])
        self.weight = np.array([slot[1] for slot in slots])
        self.local = np.array([[slot[2], slot[3], slot[4], 1.0] for slot in slots])

    def quaternions(self, angles):
        """The three bones' rotations (K, 3, 4) for rows of the five angles of `LIMITS` (K, 5)."""
        a = np.atleast_2d(angles)
        knuckle = Rot.from_euler("ZXY", a[:, 0:3], degrees=True)
        out = np.empty((len(a), 3, 4))
        out[:, 0] = (self.rests[0] * knuckle).as_quat()
        for k, column in ((1, 3), (2, 4)):
            out[:, k] = (self.rests[k] * Rot.from_euler("X", a[:, column : column + 1], degrees=True)).as_quat()
        return out

    def angles(self, quaternions):
        """The five angles of one pose given as three quaternions (3, 4)."""
        knuckle = (self.rests[0].inv() * Rot.from_quat(quaternions[0])).as_euler("ZXY", degrees=True)
        bends = [(self.rests[k].inv() * Rot.from_quat(quaternions[k])).as_rotvec(degrees=True)[0] for k in (1, 2)]
        return np.array([*knuckle, *bends])

    def points(self, quaternions):
        """The skin's points in the weapon's space for poses (K, 3, 4): (K, N, 3)."""
        count = len(quaternions)
        globals_ = {bone: np.broadcast_to(pose, (count, 4, 4)) for bone, pose in self.poses.items()}
        parent = globals_[self.chain[0]["parent"]]
        for k, entry in enumerate(self.chain):
            local = np.zeros((count, 4, 4))
            local[:, :3, :3] = Rot.from_quat(quaternions[:, k]).as_matrix()
            local[:, :3, 3] = entry["position"]
            local[:, 3, 3] = 1.0
            parent = parent @ local
            globals_[entry["bone"]] = parent
            for child, numbers in entry["children"]:
                globals_[child] = parent @ transform(numbers)
        out = np.zeros((count, self.count, 3))
        for bone in np.unique(self.bone):
            mine = self.bone == bone
            moved = np.einsum("kij,nj->kni", globals_[bone], self.local[mine])[..., :3]
            np.add.at(out, (slice(None), self.vertex[mine]), self.weight[mine][None, :, None] * moved)
        return np.einsum("ij,knj->kni", self.to_weapon[:3, :3], out) + self.to_weapon[:3, 3]


def leg_steps(a, b):
    """How many steps a leg from pose `a` to pose `b` (each (3, 4)) is measured at, so the tip moves at most
    `STEP_MM` between two of them."""
    angles = 2.0 * np.arccos(np.clip(np.abs(np.sum(a * b, axis=-1)), -1.0, 1.0))
    tip = float(np.sum(angles * np.array(LEVERS))) * 1000.0
    return max(2, int(np.ceil(tip / STEP_MM)))


def leg_poses(a, b, steps=None):
    """The poses along the leg from `a` to `b` as the game blends it: (steps + 1, 3, 4)."""
    steps = leg_steps(a, b) if steps is None else steps
    share = np.linspace(0.0, 1.0, steps + 1)
    return slerp(a[None], b[None], share[:, None])


def plan_way(start, goal, depth, axes, sample, limit, clearances=CLEARANCES):
    """A way of poses from `start` to `goal` (angle rows) on which `depth` (poses (K, 3, 4) to the deepest point
    of each, metres) stays within `limit` at every step, or None. `axes` are the grid's values on each angle
    (`sample` turns angle rows into poses). Every node of the grid is measured; the way is the shortest walk from
    node to neighbouring node through the nodes at least a clearance off the surface (the largest of
    `clearances` that joins the two ends' neighbourhoods, so the way keeps away from the surface where it can),
    then shortened: from the start, straight to the farthest pose of the walk it reaches within `limit`, and on
    from there to the goal."""
    shape = tuple(len(a) for a in axes)
    nodes = np.stack(np.meshgrid(*axes, indexing="ij"), axis=-1).reshape(-1, len(axes))
    deep = np.empty(len(nodes))
    for first in range(0, len(nodes), 8000):
        deep[first : first + 8000] = depth(sample(nodes[first : first + 8000]))
    deep = deep.reshape(shape)
    print(f"grid of poses {shape}: {(deep <= limit).mean():.2f} within the limit")

    def node_of(angles):
        return tuple(int(np.argmin(np.abs(a - v))) for a, v in zip(axes, angles, strict=True))

    # Each end sits on the surface (the finger holds there), where the grid's nodes round it are too coarse to
    # leave by: the way first leaves each end by small steps straight off the surface.
    away = [escape(start, depth, sample, limit), escape(goal, depth, sample, limit)]
    if away[0] is None or away[1] is None:
        return None
    ends = [node_of(away[0][-1]), node_of(away[1][-1])]
    # The nodes next to each end are in: the ends themselves sit on the surface, the walk leaves from them.
    open_ = np.zeros(shape, bool)
    for end in ends:
        open_[tuple(slice(max(0, i - 1), i + 2) for i in end)] = True
    walk = None
    for clearance in clearances:
        walk = _walk(open_ | (deep <= -clearance), *ends)
        if walk is not None:
            print(f"a walk of {len(walk)} nodes {clearance * 1e3:.1f} mm off the surface")
            break
    if walk is None:
        return None
    poses = away[0] + [np.array([axes[k][i] for k, i in enumerate(n)]) for n in walk[1:-1]] + away[1][::-1]
    return shorten(poses, depth, sample, limit)


def escape(angles, depth, sample, limit, clear=ESCAPE_CLEAR, span=ESCAPE_SPAN, step=ESCAPE_STEP):
    """The way from the pose `angles` to the nearest pose whose skin is `clear` off the surface, through poses
    within `limit`: a finer grid of poses round it (`span` degrees each way on every angle, by `step`), walked as
    the coarse one is. The poses, the first included; None when no pose of the grid is that far off. An end sits
    wedged on the surface (the straight finger's tip and middle on the magazine well's side and the receiver's),
    where every coarse node next to it goes deeper and a step down the depth's slope turns back and forth between
    the points that hold it."""
    angles = np.array(angles, float)
    axes = [angles[k] + step * np.arange(-span / step, span / step + 0.5) for k in range(len(angles))]
    shape = tuple(len(a) for a in axes)
    nodes = np.stack(np.meshgrid(*axes, indexing="ij"), axis=-1).reshape(-1, len(axes))
    deep = np.concatenate([depth(sample(nodes[k : k + 8000])) for k in range(0, len(nodes), 8000)]).reshape(shape)
    middle = tuple(len(a) // 2 for a in axes)
    free = deep <= limit
    free[middle] = True
    walk = _walk(free, middle, deep <= -clear)
    if walk is None:
        print(f"no pose {clear * 1e3:.1f} mm off within {span} degrees of {np.round(angles, 1).tolist()}")
        return None
    print(f"left {np.round(angles, 1).tolist()} in {len(walk) - 1} steps of {step} degrees")
    return [angles] + [np.array([axes[k][i] for k, i in enumerate(n)]) for n in walk[1:]]


def _walk(free, start, goal):
    """The shortest walk from node `start` of a grid to node `goal` (a tuple) or to the nearest node of `goal` (a
    mask) through the `free` nodes, a step to a node next to it along one axis at a time (a breadth-first search),
    as node indices; None when there is none."""
    shape = np.array(free.shape)
    if isinstance(goal, tuple):
        mask = np.zeros(free.shape, bool)
        mask[goal] = True
        goal = mask
    dist = np.full(free.shape, -1, np.int32)
    dist[start] = 0
    frontier = np.array([start])
    step = 0
    reached = None
    while reached is None and len(frontier):
        step += 1
        found = []
        for axis in range(len(shape)):
            for sign in (-1, 1):
                near = frontier.copy()
                near[:, axis] += sign
                near = near[(near[:, axis] >= 0) & (near[:, axis] < shape[axis])]
                at = tuple(near.T)
                near = near[free[at] & (dist[at] < 0)]
                dist[tuple(near.T)] = step
                found.append(near)
        frontier = np.unique(np.concatenate(found), axis=0)
        hits = frontier[goal[tuple(frontier.T)]] if len(frontier) else frontier
        if len(hits):
            reached = hits[0]
    if reached is None:
        return None
    walk = [reached]
    while dist[tuple(walk[-1])] > 0:
        here = walk[-1]
        for axis in range(len(shape)):
            back = [here + sign * np.eye(len(shape), dtype=int)[axis] for sign in (-1, 1)]
            back = [b for b in back if (b >= 0).all() and (b < shape).all() and dist[tuple(b)] == dist[tuple(here)] - 1]
            if back:
                walk.append(back[0])
                break
    return [tuple(n) for n in walk[::-1]]


def leg_depth(a, b, depth, sample):
    """The deepest the skin goes on the leg from angle row `a` to `b`, as the game blends it."""
    return float(depth(leg_poses(sample(a)[0], sample(b)[0])).max())


def shorten(way, depth, sample, limit):
    """From the start, straight to the farthest later pose of `way` it reaches within `limit`, and on from there.
    None when two poses next to each other do not reach each other."""
    out = [way[0]]
    at = 0
    while at < len(way) - 1:
        far = len(way) - 1
        while far > at and leg_depth(way[at], way[far], depth, sample) > limit:
            far -= 1
        if far == at:
            print(f"no leg within the limit from pose {at} of the walk ({np.round(way[at], 1).tolist()})")
            return None
        out.append(way[far])
        at = far
    return out


def main():
    with open(sys.argv[1], "rb") as file:
        dump = json.load(file)
    chain = FingerChain(dump)
    ends = {key: np.array([dump[key][bone] for bone in BONES]) for key in ("grip", "trigger")}
    start, goal = chain.angles(ends["grip"]), chain.angles(ends["trigger"])
    for key, angles in (("grip", start), ("trigger", goal)):
        assert np.abs(np.abs(np.sum(chain.quaternions(angles)[0] * ends[key], axis=-1)) - 1.0).max() < 1e-4, key
    # The distance grid covers everywhere the finger reaches in the poses searched (every corner of their grid
    # and many poses inside it), `GRID_MARGIN` round, as far as the rifle goes: a point outside it reads the
    # distance at its edge plus the way there, which is never less than the truth by more. A grid round the
    # straight way alone let a way through the receiver above it read 1.6 mm that the game measured at 6 mm.
    rng = np.random.default_rng(1)
    corners = np.array(np.meshgrid(*[(a[0], a[-1]) for a in AXES], indexing="ij")).reshape(len(AXES), -1).T
    inside = rng.uniform([a[0] for a in AXES], [a[-1] for a in AXES], size=(4000, len(AXES)))
    reach = chain.points(chain.quaternions(np.concatenate([corners, inside, [start, goal]]))).reshape(-1, 3)
    triangles = np.array(dump["triangles"]).reshape(-1, 3, 3)
    flat = triangles.reshape(-1, 3)
    low = np.maximum(reach.min(axis=0), flat.min(axis=0)) - GRID_MARGIN
    high = np.minimum(reach.max(axis=0), flat.max(axis=0)) + GRID_MARGIN
    print("distance grid from", np.round(low, 3).tolist(), "to", np.round(high, 3).tolist())
    near = ((triangles.max(axis=1) > low - 0.05) & (triangles.min(axis=1) < high + 0.05)).all(axis=1)
    solve_rifle_hold.BAND = GRID_BAND
    solve_rifle_hold.COARSE_STEP = 0.003
    hold_field.WORKERS = 4
    field = solve_rifle_hold.BandField(triangles[near], low, high, GRID_STEP, sys.argv[1] + ".grid.npz")
    print("grid", field.grid.shape)

    def depth(poses, every=False):
        inside = -field(chain.points(poses))
        return inside if every else inside.max(axis=1)

    for key in ("grip", "trigger"):
        print(f"{key}: {depth(ends[key][None])[0] * 1e3:.2f} mm in")
    straight = depth(leg_poses(ends["grip"], ends["trigger"])).max()
    print(f"straight way: {straight * 1e3:.2f} mm")
    limit = option("limit", 1.5) / 1000.0
    way = plan_way(start, goal, depth, AXES, chain.quaternions, limit)
    if way is None:
        print("no way found")
        sys.exit(1)
    poses = [chain.quaternions(angles)[0] for angles in way]
    deepest = max(depth(leg_poses(poses[k], poses[k + 1])).max() for k in range(len(poses) - 1))
    print(f"{len(way) - 2} poses between, the deepest {deepest * 1e3:.2f} mm on the grid")
    for angles in way:
        print("  ", np.round(angles, 1).tolist())
    out = {"poses": [{bone: pose[k].tolist() for k, bone in enumerate(BONES)} for pose in poses[1:-1]]}
    out["angles"] = [angles.tolist() for angles in way]
    with open(sys.argv[2], "w", encoding="utf-8") as file:
        json.dump(out, file, indent=1)


if __name__ == "__main__":
    main()
