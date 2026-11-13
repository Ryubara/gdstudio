"""The checks a clip passes before its file is written (`docs/tools/blender/own-animation.md#checks`).

`run(built, bodies)` measures a solved clip as the written file plays it (the kept keys, straight lines between
them) on every body's own skeleton and skinned mesh, and returns the numbers and the failures. Each check is one
function here, with its limits beside it; `selftest.py` builds a clip to break each one and proves the check fails
on it. Limbs inside limbs need a mesh query and run in Blender (`../limb_overlap.py`, called by `build_own.py` on
the file before it is put in place).

A body whose legs are not the reference body's cannot keep a planted foot on its place from rotations alone: the
game plants it with the `ik_foot` targets. For such a body the floor and planted-foot numbers are reported with
`needs_ik` and not held to the limits.

A body whose toes do not rest where the reference body's do cannot stand on the ball of its foot at the reference's
height: the prototype bodies' toes curl 7 mm up off the floor at rest and the Quaternius mannequins' lie on it, so
a raised heel solved for one leaves the other that far over or under the floor. Such a body's floor limits
and its planted sole's wander (the patch of sole that touches moves as the foot sinks) are wider by the difference
(`toes_off_mm` in its numbers); the reference body and every body shaped like it keep the limits as they are.
"""

import math

import numpy as np

from . import maths, reduce, weight
from .maths import FPS
from .rig import FINGERS, SIDES, Rig, audit_clips

## Loop seam: the change of speed across the seam against the largest elsewhere in the cycle, and the least change
## (m a frame, squared) that counts, under which a clip is as good as still at its seam.
SEAM_STEP = 1.0
SEAM_FLOOR = 2e-5
## Floor: a planted sole's lowest vertex against the floor, and the lowest any vertex may go (m).
SOLE_BAND = 0.002
UNDER = 0.005
## Floor: the least difference between a body's toes at rest and the reference body's that widens its limits (m).
TOES_SAME = 0.002
## Planted feet: the furthest a planted sole wanders in one contact (m), and how far the planted sole's measured
## speed may be from the speed `clips.json` gives, as a share.
WANDER = 0.005
## The least share of a sole vertex's weight that is the foot's and the toes' for it to count as the planted sole.
FIRM = 0.95
SPEED_SHARE = 0.02
## Planted hands, forearms and knees: the furthest one drifts in the world while planted (m).
PLANT_DRIFT = 0.001
## Gait: the legs' phases against half a cycle (frames), the least correlation of an arm with the other side's leg.
HALF_CYCLE = 1.0
ARM_LEG = 0.7
## Overlap: how far a part's measured lag may be from the declared one (frames), and the most a part may turn on a
## landing frame beyond its own motion round it while its parent does not (degrees).
LAG = 0.5
POP = 0.5
## Weight: the centre of mass off a free fall's arc (m), the lean against the acceleration's (degrees), and how far
## inside the feet's support the centre of mass must be while standing (m; 0 is on its edge).
ARC = 0.015
LEAN = 5.0
SUPPORT = 0.0
## Weight: the hardest the centre of mass may accelerate downward while a foot is on the floor, as a share of
## gravity (a body that stands on the floor cannot fall faster than it would with nothing under it; the share over
## 1 is what a second difference of 32-bit keys at 30 a second cannot tell from it).
FALL = 1.05
## Joins: a transition's first and last pose against the poses it joins (m, degrees), and its speed there (share).
JOIN_PLACE = 0.001
JOIN_TURN = 0.5
## Targets: the furthest an `ik_` target may be from the end of the limb it is the target of (m): the reducer's
## limit on each of the two, and the few millimetres the ends of a joined clip are moved by (`Clip.meet`).
TARGET = 0.004
## Limits: hinges in degrees (straight is 0), the furthest a joint turns from its standing rest (degrees), and the
## largest change of a joint's speed in one frame (degrees a frame, per frame).
HINGES = {"elbow": (-5.0, 150.0), "knee": (-5.0, 140.0)}
CONES = {"spine_01": 30.0, "spine_02": 30.0, "spine_03": 30.0, "neck_01": 45.0, "Head": 45.0, "clavicle": 35.0,
         "hand": 75.0, "foot": 55.0, "thigh": 125.0, "ball": 70.0, "finger": 100.0}  # fmt: skip
SPEED_CHANGE = 30.0
## Cost: the share of a moving bone's rotation keys a reducer keeps at half a degree, and the clip's key bytes for a
## second of clip (the budget's imported size is measured in Godot; this stops a clip that could never meet it).
KEYS_KEPT = 0.40
KB_A_SECOND = 16.0
## Arms: the joints of an arm read by `check_arms`, each with its other side's; a clip that declares `arm_bounds`
## (the jump's, read off the shipped gait) holds each one's fastest turn and its sharpest change of acceleration
## under that bound (degrees a second, degrees a second cubed).
ARM_PARTS = ("clavicle", "upperarm", "lowerarm", "hand")
MAIN = audit_clips.MAIN


class Played:
    """A clip as the file plays it on one body."""

    def __init__(self, built, rig: Rig):
        self.rig = rig
        self.rotation, self.translation = built.played(rig)
        self.world = rig.world(self.rotation, self.translation)
        reference = built.record["_rig"]
        legs = ("thigh_l", "calf_l")
        self.same_legs = (
            all(abs(rig.length[b] - reference.length[b]) < 1e-3 for b in legs) and abs(rig.hips - reference.hips) < 1e-3
        )
        # How far this body's toes rest from where the reference body's do (m): the floor limits' allowance.
        self.toes_off = max(abs(rig.sole[s]["toes_up"] - reference.sole[s]["toes_up"]) for s, _ in SIDES)
        if self.toes_off < TOES_SAME:
            self.toes_off = 0.0
        self._feet = {}

    def foot(self, side: str) -> np.ndarray:
        if side not in self._feet:
            bones = (f"foot_{side}", f"ball_{side}", f"ball_leaf_{side}")
            self._feet[side] = self.rig.skin(self.world, bones)
        return self._feet[side]

    def firm(self, side: str) -> np.ndarray:
        """Which of `foot(side)`'s vertices follow the foot and the toes alone. The skin of the heel is shared
        with the shin, which swings over a planted foot (25 degrees a frame in a run) and drags that skin a
        millimetre a frame over the floor while no bone of the foot moves."""
        rig = self.rig
        bones = (f"foot_{side}", f"ball_{side}", f"ball_leaf_{side}")
        share = sum(rig._weight(bone) for bone in bones if bone in rig.index)
        return share[np.isin(rig.owner, bones)] >= FIRM


def _travel(built, count: int) -> tuple:
    travel = built.clip.plan.travel
    places = np.array([travel.at(float(f))[0] for f in range(count)])
    yaws = np.array([travel.at(float(f))[1] for f in range(count)])
    return places, yaws


def _carried(built) -> np.ndarray | None:
    """The root's height over the floor on every frame of a clip the controller carries through the air
    (`declared["carried"]`, a jump on the game's own arc), or None for a clip whose root stays on the floor."""
    heights = built.clip.declared.get("carried")
    if heights is None:
        return None
    heights = np.asarray(heights, dtype=float)
    assert len(heights) == built.rotation.shape[0], f"{built.clip.name}: `carried` needs a height for every frame"
    return heights


def _in_world(points: np.ndarray, places: np.ndarray, yaws: np.ndarray) -> np.ndarray:
    """Points [frame, n, 3] of a clip in place, put back on the floor the root travels over."""
    out = np.empty_like(points)
    for f in range(points.shape[0]):
        out[f] = points[f] @ maths.axis_angle(maths.Y, yaws[f]).T + places[f]
    return out


def _contact_frames(built, side: str) -> list:
    """The whole frames of each of a foot's contacts."""
    out = []
    for land, lift in built.record["contacts"][side]:
        first, last = int(math.ceil(land - 1e-6)), int(math.floor(lift + 1e-6))
        if last > first:
            out.append((first, last))
    return out


# ---- the checks ---------------------------------------------------------------------------------------------


def check_seam(built, played: dict) -> tuple:
    """A loop's last pose is its first to the bit, and the seam's change of speed is no more than the largest in
    the cycle."""
    if not built.clip.loop:
        return {}, []
    failures = []
    reference = built.record["_rig"]
    for kind, values in (("rotation", built.rotation), ("place", built.translation)):
        for bone, kept in built.kept[kind].items():
            i = reference.index[bone]
            first = values[kept[0], i].astype(np.float32).tobytes()
            last = values[kept[-1], i].astype(np.float32).tobytes()
            if kept[0] != 0 or kept[-1] != values.shape[0] - 1 or first != last:
                failures.append(f"seam: {bone}'s last {kind} key is not its first")
                break
    rig = next(iter(played.values())).rig
    world = next(iter(played.values())).world
    place = world[:, [rig.index[b] for b in MAIN]][:, :, :3, 3]
    cycle = place[:-1]
    speed = np.roll(cycle, -1, axis=0) - cycle
    change = np.linalg.norm(speed - np.roll(speed, 1, axis=0), axis=2).max(axis=1)
    inner = float(np.delete(change, [0]).max())
    step = float(change[0] / max(inner, 1e-12))
    numbers = {"seam_step": round(step, 2)}
    if change[0] > SEAM_FLOOR and step > SEAM_STEP:
        failures.append(f"seam: the change of speed across the seam is {step:.2f} of the largest in the cycle")
    return numbers, failures


def check_floor(built, played: dict) -> tuple:
    """A planted sole's lowest vertex is within `SOLE_BAND` of the floor, and no vertex goes more than `UNDER`
    under it on any frame, on every body; with `declared["ceiling"]` (m; a crouched capsule's height) no vertex
    is above that either. A clip the controller carries through the air (`declared["carried"]`) is measured from
    the floor the root has left: toes that point down under the root as a jump begins are over it."""
    numbers, failures = {}, []
    carried = _carried(built)
    for name, body in played.items():
        rig = body.rig
        lowest, highest, off = math.inf, -math.inf, 0.0
        for start in range(0, body.world.shape[0], 16):
            heights = rig.skin(body.world[start : start + 16])[:, :, 1]
            if carried is not None:
                heights = heights + carried[start : start + 16, None]
            lowest, highest = min(lowest, float(heights.min())), max(highest, float(heights.max()))
        for s, _ in SIDES:
            floor = rig.sole[s]["floor"]
            height = body.foot(s)[:, :, 1].min(axis=1)
            for first, last in _contact_frames(built, s):
                gap = height[first : last + 1] - floor
                off = max(off, float(np.abs(gap).max()))
        numbers[name] = {"lowest_mm": round(lowest * 1000, 1), "sole_off_mm": round(off * 1000, 1)}
        ceiling = built.clip.declared.get("ceiling")
        if ceiling is not None:
            numbers[name]["highest_mm"] = round(highest * 1000, 1)
            if highest > ceiling:
                failures.append(
                    f"floor: a vertex is {highest * 1000:.0f} mm up on {name}, over the declared ceiling of "
                    f"{ceiling * 1000:.0f}"
                )
        if not body.same_legs:
            numbers[name]["needs_ik"] = True
            continue
        if body.toes_off:
            numbers[name]["toes_off_mm"] = round(body.toes_off * 1000, 1)
        if off > SOLE_BAND + body.toes_off:
            failures.append(f"floor: a planted sole is {off * 1000:.1f} mm off the floor on {name}")
        if lowest < -(UNDER + body.toes_off):
            failures.append(f"floor: a vertex is {-lowest * 1000:.1f} mm under the floor on {name}")
    return {"floor": numbers}, failures


def check_planted(built, played: dict) -> tuple:
    """A planted sole wanders at most `WANDER` in a contact on the floor the root travels over, and the speed in
    `clips.json` is the planted sole's measured speed within `SPEED_SHARE`."""
    numbers, failures = {}, []
    count = built.rotation.shape[0]
    places, yaws = _travel(built, count)
    for name, body in played.items():
        worst, speeds = 0.0, []
        for s, _ in SIDES:
            local = body.foot(s)[:, body.firm(s)]
            verts = _in_world(local, places * body.rig.motion_scale, yaws)
            for first, last in _contact_frames(built, s):
                drift = [np.zeros(2)]
                for f in range(first, last):
                    # The patch that is on the floor on both frames: skin that a rising heel takes off the
                    # floor between them is not planted, and a run's heel rises 20 degrees a frame.
                    patch = (verts[f, :, 1] <= verts[f, :, 1].min() + 0.01) & (
                        verts[f + 1, :, 1] <= verts[f + 1, :, 1].min() + 0.01
                    )
                    step = (verts[f + 1, patch] - verts[f, patch])[:, [0, 2]].mean(axis=0)
                    drift.append(drift[-1] + step)
                    speeds.append(
                        float(np.linalg.norm((local[f + 1, patch] - local[f, patch])[:, [0, 2]].mean(axis=0))) * FPS
                    )
                worst = max(worst, float(np.linalg.norm(np.ptp(np.array(drift), axis=0))))
        measured = float(np.mean(speeds)) if speeds else 0.0
        numbers[name] = {"wander_mm": round(worst * 1000, 2), "planted_speed": round(measured, 3)}
        if not body.same_legs:
            numbers[name]["needs_ik"] = True
            continue
        if worst > WANDER + body.toes_off:
            failures.append(f"planted: a planted sole wanders {worst * 1000:.1f} mm in a contact on {name}")
        declared = built.record["speed"]
        steady = built.clip.kind == "gait"
        if steady and abs(measured - declared) > SPEED_SHARE * max(declared, 1e-9):
            failures.append(
                f"planted: the sole's speed is {measured:.3f} m/s on {name}, clips.json says {declared:.3f}"
            )
    return {"planted": numbers}, failures


def check_plants(built, played: dict) -> tuple:
    """A planted hand, forearm or knee (`declared["plants"]`: `{"bone", "from", "to"}`) drifts at most
    `PLANT_DRIFT` in the world while planted, on the reference body."""
    plants = built.clip.declared.get("plants", [])
    if not plants:
        return {}, []
    body = next(iter(played.values()))
    places, yaws = _travel(built, built.rotation.shape[0])
    failures, worst = [], 0.0
    for plant in plants:
        joint = body.rig.joint(body.world, plant["bone"])[:, None, :]
        path = _in_world(joint, places, yaws)[int(plant["from"]) : int(plant["to"]) + 1, 0]
        drift = float(np.linalg.norm(path - path[0], axis=1).max())
        worst = max(worst, drift)
        if drift > PLANT_DRIFT:
            failures.append(f"plants: {plant['bone']} drifts {drift * 1000:.2f} mm while planted")
    return {"plant_drift_mm": round(worst * 1000, 2)}, failures


def gait_numbers(body: Played, loop: bool) -> dict:
    """The audit's gait measures on a played clip."""
    rig, world = body.rig.body, body.world
    cyc = slice(0, world.shape[0] - 1) if loop else slice(0, world.shape[0])
    thigh_l = audit_clips.swing(world, rig, "thigh_l", "calf_l")[cyc]
    thigh_r = audit_clips.swing(world, rig, "thigh_r", "calf_r")[cyc]
    arm_l = audit_clips.swing(world, rig, "upperarm_l", "lowerarm_l")[cyc]
    arm_r = audit_clips.swing(world, rig, "upperarm_r", "lowerarm_r")[cyc]
    hips, _ = audit_clips.line_turn(world, rig, "thigh_l", "thigh_r")
    chest, _ = audit_clips.line_turn(world, rig, "clavicle_l", "clavicle_r")
    out = {
        "arm_leg": audit_clips.correlation(arm_l, thigh_r),
        "arm_leg_other": audit_clips.correlation(arm_r, thigh_l),
        "counter": audit_clips.correlation(hips[cyc], chest[cyc]),
        "bob_mm": round(float(np.ptp(world[cyc, rig.index["pelvis"], 1, 3])) * 1000, 1),
    }
    count = len(thigh_l)
    if np.ptp(thigh_l) > math.radians(10.0):
        spectrum = np.abs(np.fft.rfft(thigh_l - thigh_l.mean()))
        strides = max(1, int(spectrum[1:].argmax()) + 1)
        half = count / strides / 2.0
        out["cadence"] = round(60.0 * FPS / half, 1)
        best = max(
            range(count),
            key=lambda shift: float(np.dot(thigh_l - thigh_l.mean(), np.roll(thigh_r - thigh_r.mean(), -shift))),
        )
        out["half_cycle_off"] = round(
            min(
                abs(((best - half) + count / 2) % count - count / 2),
                abs(((best + half) + count / 2) % count - count / 2),
            ),
            2,
        )
    return out


def check_gait(built, played: dict) -> tuple:
    """A gait's legs are half a cycle apart, each arm swings with the other side's leg, the shoulders turn
    against the hips, and cadence, planted share and bob are inside the declared ranges."""
    if built.clip.kind != "gait":
        return {}, []
    body = next(iter(played.values()))
    numbers = gait_numbers(body, built.clip.loop)
    cycle = built.clip.frames
    duty = float(np.mean([sum(lift - land for land, lift in built.record["contacts"][s]) / cycle for s, _ in SIDES]))
    numbers["planted_share"] = round(duty, 3)
    failures = []
    if numbers.get("half_cycle_off", 0.0) > HALF_CYCLE:
        failures.append(f"gait: the legs are {numbers['half_cycle_off']} frames off half a cycle apart")
    for key in ("arm_leg", "arm_leg_other"):
        if numbers[key] is not None and numbers[key] < ARM_LEG:
            failures.append(f"gait: an arm swings with the other side's leg by only {numbers[key]} ({key})")
    if numbers["counter"] is not None and numbers["counter"] > 0.0:
        failures.append(f"gait: the shoulders turn with the hips ({numbers['counter']}), not against them")
    for key, (low, high) in built.clip.declared.get("ranges", {}).items():
        value = numbers.get(key)
        if value is not None and not low <= value <= high:
            failures.append(f"gait: {key} is {value}, outside {low} to {high}")
    return {"gait": numbers}, failures


def lag_numbers(body: Played, loop: bool) -> dict:
    """How many frames the forearm, hand, chest and head trail the part they hang from (the audit's measure)."""
    rig, world = body.rig.body, body.world
    cyc = slice(0, world.shape[0] - 1) if loop else slice(0, world.shape[0])
    rest = rig.world(rig.rest_r[None], rig.rest_t[None])
    out = {}
    fore, hand = [], []
    for s, _ in SIDES:
        upper = audit_clips.swing(world, rig, f"upperarm_{s}", f"lowerarm_{s}")[cyc]
        lower = audit_clips.swing(world, rig, f"lowerarm_{s}", f"hand_{s}")[cyc]
        tip = audit_clips.swing(world, rig, f"hand_{s}", f"middle_01_{s}")[cyc]
        fore.append(audit_clips.lag_frames(upper, lower, loop))
        hand.append(audit_clips.lag_frames(lower, tip, loop))
    hips, _ = audit_clips.line_turn(world, rig, "thigh_l", "thigh_r")
    chest, _ = audit_clips.line_turn(world, rig, "clavicle_l", "clavicle_r")
    _, head_pitch, _ = audit_clips.turn_of(world, rest, rig, "Head")
    spine = world[:, rig.index["neck_01"], :3, 3] - world[:, rig.index["spine_02"], :3, 3]
    chest_pitch = np.arctan2(spine[:, 2], spine[:, 1])
    for key, values in (("forearm", fore), ("hand", hand)):
        values = [v for v in values if v is not None]
        out[key] = round(float(np.mean(values)), 1) if values else None
    out["chest"] = audit_clips.lag_frames(hips[cyc], chest[cyc], loop)
    out["head"] = audit_clips.lag_frames(chest_pitch[cyc], head_pitch[cyc], loop)
    return out


def check_overlap(built, played: dict) -> tuple:
    """Each part trails its parent by the declared frames (`declared["lags"]`, where the motion is large enough
    to measure), and nothing pops on a landing frame while its parent does not."""
    body = next(iter(played.values()))
    numbers = {"lags": lag_numbers(body, built.clip.loop)}
    failures = []
    for part, want in built.clip.declared.get("lags", {}).items():
        got = numbers["lags"].get(part)
        if got is not None and abs(got - want) > LAG:
            failures.append(f"overlap: the {part} trails by {got} frames, declared {want}")
    rig = body.rig
    count = body.rotation.shape[0]
    worst = 0.0
    for event in built.record["events"]:
        f = int(round(event["frame"]))
        if event["name"] != "footstep" or f < 2 or f > count - 3:
            continue
        for bone in built.kept["rotation"]:
            if bone.startswith(("thigh", "calf", "foot", "ball", "pelvis", "ik_")):
                continue
            own, above = _kick(body, bone, f), _kick(body, rig.parent[bone], f)
            if own > POP and above < POP:
                worst = max(worst, own)
                failures.append(f"overlap: {bone} turns {own:.2f} degrees on the landing frame {f} by itself")
    numbers["landing_pop_deg"] = round(worst, 2)
    return {"overlap": numbers}, failures


def _kick(body: Played, bone: str, f: int) -> float:
    """How much more sharply a bone's turn changes at frame `f` than on the frames beside it (degrees). The
    change at a frame is half the difference between the turn into it and the turn out of it; a swing that
    reverses changes as much on the frames beside, a pose that jumps for one frame does not."""
    if bone not in body.rig.index:
        return 0.0
    world = body.world[:, body.rig.index[bone], :3, :3]
    steps = [maths.rotation_vector(world[k + 1] @ world[k].T) for k in range(f - 2, f + 2)]
    change = [float(np.linalg.norm(0.5 * (steps[k] - steps[k + 1]))) for k in range(3)]
    return math.degrees(max(change[1] - 0.5 * (change[0] + change[2]), 0.0))


def check_weight(built, played: dict) -> tuple:
    """Standing, the centre of mass is over the feet; in the air it is on a free fall's arc (in the clip's own
    space, or, for a clip the controller carries, `declared["carried"]`, on the arc the controller flies: it keeps
    one speed against the root); where the root changes speed the body leans by the acceleration; a body that
    goes down with a foot on the floor drops no faster than gravity."""
    body = next(iter(played.values()))
    rig, world = body.rig, body.world
    count = world.shape[0]
    com = rig.centre_of_mass(world)
    places, yaws = _travel(built, count)
    plan = built.clip.plan
    numbers, failures = {}, []
    down = [[s for s, _ in SIDES if plan.planted(s, float(f))] for f in range(count)]
    speed = np.array([plan.travel.speed(float(f)) for f in range(count)])
    if built.clip.kind == "stand":
        margin = math.inf
        for f in range(count):
            if down[f] and speed[f] < 0.05:
                hull = weight.support_polygon(rig, world, tuple(down[f]), f)
                margin = min(margin, weight.inside_margin(hull, (com[f, 0], com[f, 2])))
        if margin < math.inf:
            numbers["support_margin_mm"] = round(margin * 1000, 1)
            if margin < SUPPORT:
                failures.append(f"weight: the centre of mass is {-margin * 1000:.1f} mm outside the feet")
    air = [f for f in range(count) if not down[f]]
    carried = _carried(built) is not None
    runs, start = [], None
    for f in range(count + 1):
        flying = f < count and not down[f]
        if flying and start is None:
            start = f
        if not flying and start is not None:
            runs.append((start, f - 1))
            start = None
    off = 0.0
    for first, last in runs:
        if last - first < 3:
            continue
        t = np.arange(first, last + 1) / FPS
        # A clip the controller carries is played on the game's own arc, which is a free fall's: the centre of
        # mass is on one too when it moves at one speed in the clip's own space, the root's.
        height = com[first : last + 1, 1] + (0.0 if carried else 0.5 * weight.G * t * t)
        line = np.polyfit(t, height, 1)
        off = max(off, float(np.abs(height - np.polyval(line, t)).max()))
    if air:
        numbers["arc_off_mm"] = round(off * 1000, 1)
        if off > ARC:
            failures.append(f"weight: in the air the centre of mass is {off * 1000:.1f} mm off a free fall's arc")
    if count > 2 and built.clip.kind in ("transition", "action"):
        drop = -np.diff(com[:, 1], 2) * FPS * FPS
        held = [f for f in range(1, count - 1) if down[f - 1] and down[f] and down[f + 1]]
        if held:
            fall = float(drop[np.array(held) - 1].max()) / weight.G
            numbers["fall_g"] = round(fall, 2)
            if fall > FALL:
                failures.append(
                    f"weight: the centre of mass drops at {fall:.2f} of gravity with a foot on the floor, over {FALL}"
                )
    accel = np.gradient(speed) * FPS
    if np.abs(accel).max() > 0.5 and built.clip.kind == "transition":
        worst = 0.0
        for f in range(1, count - 1):
            if not down[f] or abs(accel[f]) < 0.5:
                continue
            feet = np.mean([rig.sole_points(world[f : f + 1], s)["ball"][0] for s in down[f]], axis=0)
            lean = math.degrees(math.atan2(com[f, 2] - feet[2], com[f, 1] - feet[1]))
            worst = max(worst, abs(lean - weight.lean_for(accel[f])))
        numbers["lean_off_deg"] = round(worst, 1)
        limit = built.clip.declared.get("lean_limit", LEAN)
        if worst > limit:
            failures.append(f"weight: the lean is {worst:.1f} degrees from the acceleration's")
    return {"weight": numbers}, failures


def pose_gap(rig: Rig, world_a: np.ndarray, world_b: np.ndarray) -> tuple:
    """The furthest any bone of one pose is from the same bone of another: metres, and degrees."""
    bones = [rig.index[n] for n in rig.bones]
    apart = float(np.linalg.norm(world_a[bones, :3, 3] - world_b[bones, :3, 3], axis=1).max())
    turn = max(maths.angle_between(world_a[i, :3, :3], world_b[i, :3, :3]) for i in bones)
    return apart, turn


def check_joins(built, played: dict) -> tuple:
    """A transition's first and last pose are the poses it joins (`declared["joins"]`: `{"first": (rotation,
    translation), "last": ..., "first_speed", "last_speed"}`, each pose one row of a body's arrays)."""
    joins = built.clip.declared.get("joins", {})
    if not joins:
        return {}, []
    body = next(iter(played.values()))
    rig = body.rig
    numbers, failures = {}, []
    for end, frame_no in (("first", 0), ("last", -1)):
        if end in joins:
            rotation, translation = joins[end]
            want = rig.world(rotation[None], translation[None])[0]
            apart, turn = pose_gap(rig, body.world[frame_no], want)
            numbers[end] = {"mm": round(apart * 1000, 2), "deg": round(turn, 2)}
            if apart > JOIN_PLACE or turn > JOIN_TURN:
                failures.append(
                    f"joins: the {end} pose is {apart * 1000:.2f} mm and {turn:.2f} degrees from the pose it joins"
                )
        key = end + "_speed"
        if key in joins:
            f = 0.5 if end == "first" else built.clip.frames - 0.5
            got = built.clip.plan.travel.speed(f)
            numbers[key] = round(got, 3)
            if abs(got - joins[key]) > SPEED_SHARE * max(joins[key], 0.05):
                failures.append(f"joins: the {end} speed is {got:.3f} m/s, the joined clip's is {joins[key]:.3f}")
    return {"joins": numbers}, failures


def check_travel(built, played: dict) -> tuple:
    """The root's travel is the distance and the turn the description declares."""
    failures = []
    travel = built.record["travel"]
    forward, left = travel[-1][1] - travel[0][1], travel[-1][2] - travel[0][2]
    turn = built.record["turn"][-1][1] - built.record["turn"][0][1]
    numbers = {"distance": round(math.hypot(forward, left), 4), "turn": round(turn, 2)}
    declared = built.clip.declared
    if "distance" in declared and abs(numbers["distance"] - declared["distance"]) > 0.002:
        failures.append(f"travel: the root travels {numbers['distance']} m, declared {declared['distance']}")
    if "turn" in declared and abs(numbers["turn"] - declared["turn"]) > 0.2:
        failures.append(f"travel: the root turns {numbers['turn']} degrees, declared {declared['turn']}")
    return {"travel": numbers}, failures


def check_targets(built, played: dict) -> tuple:
    """Each `ik_` target a clip keys is where its limb's end is (`ik_foot_l` at `foot_l`'s joint) on every frame,
    within `TARGET`, on the reference body."""
    body = next(iter(played.values()))
    rig, worst, where = body.rig, 0.0, ""
    for bone in built.kept["place"]:
        if not bone.startswith("ik_") or bone[3:] not in rig.index:
            continue
        gap = np.linalg.norm(rig.joint(body.world, bone) - rig.joint(body.world, bone[3:]), axis=1)
        if gap.max() > worst:
            worst, where = float(gap.max()), f"{bone} at frame {int(gap.argmax())}"
    if not where:
        return {}, []
    failures = []
    if worst > TARGET:
        failures.append(f"targets: {where} is {worst * 1000:.1f} mm from its limb's end")
    return {"target_off_mm": round(worst * 1000, 2)}, failures


def hinge_angles(body: Played) -> dict:
    """The elbows' and knees' bend on every frame, degrees (0 is straight, negative bends backward)."""
    rig, world = body.rig, body.world
    out = {}
    for s, _ in SIDES:
        for name, top, mid, end, sense in (
            ("elbow", "upperarm", "lowerarm", "hand", 1.0),
            ("knee", "thigh", "calf", "foot", -1.0),
        ):
            a, b, c = (rig.joint(world, f"{bone}_{s}") for bone in (top, mid, end))
            first = (b - a) / np.linalg.norm(b - a, axis=1, keepdims=True)
            second = (c - b) / np.linalg.norm(c - b, axis=1, keepdims=True)
            turn = world[:, rig.index[f"{top}_{s}"], :3, :3] @ rig.rest_rot[f"{top}_{s}"].T
            ahead = sense * (turn @ maths.Z)
            bend = np.degrees(np.arctan2(np.sum(second * ahead, axis=1), np.sum(second * first, axis=1)))
            rest_a, rest_b, rest_c = (rig.rest_pos[f"{bone}_{s}"] for bone in (top, mid, end))
            rest_bend = math.degrees(
                math.atan2(
                    np.dot(maths.unit(rest_c - rest_b), sense * maths.Z),
                    np.dot(maths.unit(rest_c - rest_b), maths.unit(rest_b - rest_a)),
                )
            )
            out[f"{name}_{s}"] = bend - rest_bend
    return out


def check_limits(built, played: dict) -> tuple:
    """No joint past a person's range, no elbow or knee bending backward, no jump in a joint's speed."""
    body = next(iter(played.values()))
    rig = body.rig
    numbers, failures = {}, []
    for name, bend in hinge_angles(body).items():
        low, high = HINGES[name[:-2]]
        numbers[name] = [round(float(bend.min()), 1), round(float(bend.max()), 1)]
        if bend.min() < low or bend.max() > high:
            failures.append(
                f"limits: {name} bends {bend.min():.1f} to {bend.max():.1f} degrees, outside {low} to {high}"
            )
    local = maths.matrix_of(body.rotation)
    limit = built.clip.declared.get("speed_limit", SPEED_CHANGE)
    worst_change, worst_bone = 0.0, ""
    for bone in built.kept["rotation"]:
        i = rig.index[bone]
        stem = bone[:-2] if bone[-2:] in ("_l", "_r") else bone
        cone = CONES.get(stem, CONES["finger"] if stem.startswith(FINGERS) else None)
        if cone is not None:
            rest = rig.local_rot[bone]
            reach = max(maths.angle_between(rest, local[f, i]) for f in range(local.shape[0]))
            if reach > cone:
                failures.append(f"limits: {bone} turns {reach:.1f} degrees from its rest, over {cone}")
        steps = np.array([maths.rotation_vector(local[f + 1, i] @ local[f, i].T) for f in range(local.shape[0] - 1)])
        if built.clip.loop:
            steps = np.concatenate([steps, steps[:1]])
        change = np.degrees(np.linalg.norm(np.diff(steps, axis=0), axis=1)) if len(steps) > 1 else np.zeros(1)
        if change.max() > worst_change:
            worst_change, worst_bone = float(change.max()), bone
    numbers["speed_change_deg"] = round(worst_change, 2)
    if worst_change > limit:
        failures.append(
            f"limits: {worst_bone}'s speed changes {worst_change:.1f} degrees a frame in one frame, over {limit}"
        )
    for key, value in built.miss.items():
        if value > 1e-6:
            failures.append(f"limits: {key} was {value * 1000:.1f} mm out of reach")
    return {"limits": numbers}, failures


def arm_numbers(rotation: np.ndarray, rig: Rig, loop: bool) -> dict:
    """Each arm joint's fastest turn (degrees a second) and sharpest change of acceleration (degrees a second
    cubed) over a clip's local rotations, `[frame, bone, 4]`, the two sides' larger: `{part: [speed, jerk]}`. A
    loop is read round its seam; a clip that plays once from its first frame to its last."""
    out = {}
    for part in ARM_PARTS:
        worst = [0.0, 0.0]
        for s, _ in SIDES:
            q = rotation[:, rig.index[f"{part}_{s}"]]
            m = maths.matrix_of(q[:-1] if loop else q)
            ahead = np.roll(m, -1, axis=0) if loop else m[1:]
            here = m if loop else m[:-1]
            speed = np.array([maths.rotation_vector(b @ a.T) for a, b in zip(here, ahead, strict=True)])
            speed = np.degrees(speed) * FPS
            if loop:
                accel = (np.roll(speed, -1, axis=0) - speed) * FPS
                jerk = (np.roll(accel, -1, axis=0) - accel) * FPS
            else:
                jerk = np.diff(speed, n=2, axis=0) * FPS * FPS
            worst[0] = max(worst[0], float(np.linalg.norm(speed, axis=1).max()))
            if len(jerk):
                worst[1] = max(worst[1], float(np.linalg.norm(jerk, axis=1).max()))
        out[part] = [round(worst[0], 1), round(worst[1], 0)]
    return out


def check_arms(built, played: dict) -> tuple:
    """An arm that floats: no arm joint of a clip that declares `arm_bounds` turns faster, or changes its
    acceleration more sharply, than the bound (`{part: [speed, jerk]}`), on the curve the file plays."""
    bounds = built.clip.declared.get("arm_bounds")
    if not bounds:
        return {}, []
    body = next(iter(played.values()))
    numbers = arm_numbers(body.rotation, body.rig, built.clip.loop)
    failures = []
    for part, (speed, jerk) in numbers.items():
        most_speed, most_jerk = bounds[part]
        if speed > most_speed:
            failures.append(f"arms: {part} turns {speed:.0f} degrees a second, over the {most_speed:.0f} of the bound")
        if jerk > most_jerk:
            failures.append(
                f"arms: {part}'s acceleration changes {jerk:.0f} degrees a second cubed, over the {most_jerk:.0f} "
                "of the bound"
            )
    return {"arms": numbers}, failures


def cost_numbers(built) -> dict:
    """Bones moved, the share of their keys a half-degree reducer keeps, and the clip's key bytes a second."""
    reference = built.record["_rig"]
    moving, kept, total = [], 0, 0
    for bone in built.kept["rotation"]:
        track = built.rotation[:, reference.index[bone]]
        if maths.quat_angle(track, track[:1]).max() > audit_clips.STILL_DEG:
            moving.append(bone)
            kept += audit_clips.keys_kept(track)
            total += len(track)
    times = {tuple(k) for kind in ("rotation", "place") for k in built.kept[kind].values()}
    size = sum(4 * len(t) for t in times)
    size += sum(16 * len(k) for k in built.kept["rotation"].values()) + sum(
        12 * len(k) for k in built.kept["place"].values()
    )
    written = sum(len(k) for k in built.kept["rotation"].values())
    return {
        "moving_bones": len(moving),
        "finger_bones": sum(1 for bone in moving if bone.startswith(FINGERS)),
        "keys_kept": round(kept / total, 3) if total else 0.0,
        "keys_written": round(written / (len(built.kept["rotation"]) * built.rotation.shape[0]), 3),
        "kb": round(size / 1024, 1),
        "kb_a_second": round(size / 1024 / max(built.record["seconds"], 1e-9), 2),
    }


def check_cost(built, played: dict) -> tuple:
    numbers = cost_numbers(built)
    failures = []
    limit = built.clip.declared.get("keys_kept", KEYS_KEPT)
    if numbers["keys_kept"] > limit:
        failures.append(
            f"cost: a half-degree reducer keeps {numbers['keys_kept']:.0%} of the moving bones' keys, over {limit:.0%}"
        )
    most = built.clip.declared.get("kb_a_second", KB_A_SECOND)
    if numbers["kb_a_second"] > most:
        failures.append(f"cost: the clip's keys are {numbers['kb_a_second']} KB a second, over {most}")
    return {"cost": numbers}, failures


def check_reduction(built, played: dict) -> tuple:
    """The written keys play back within the reducer's limits of the full curve: the hands, the head and the feet
    within `reduce.LIMIT`, a planted foot within `reduce.PLANTED_LIMIT`."""
    body = next(iter(played.values()))
    rig = body.rig
    reference = built.record["_rig"]
    full = reference.world(built.rotation, built.translation)
    ends = [n for n in reduce.ENDS if n in rig.index]
    mine = body.world[:, [rig.index[n] for n in ends]][:, :, :3, 3]
    gap = np.linalg.norm(mine - full[:, [reference.index[n] for n in ends]][:, :, :3, 3], axis=2)
    error, planted = float(gap.max()), 0.0
    for k, name in enumerate(ends):
        if name in reduce.FEET:
            mask = np.array([built.clip.plan.planted(name[-1], float(f)) for f in range(gap.shape[0])])
            if mask.any():
                planted = max(planted, float(gap[mask, k].max()))
    numbers = {"reduce_error_mm": round(error * 1000, 3), "reduce_planted_mm": round(planted * 1000, 3)}
    failures = []
    if error > reduce.LIMIT * 1.001 or planted > reduce.PLANTED_LIMIT * 1.001:
        failures.append(
            f"reduction: the written keys stray {error * 1000:.2f} mm from the full curve ({planted * 1000:.2f} mm at a planted foot)"
        )
    return numbers, failures


CHECKS = [
    check_seam,
    check_floor,
    check_planted,
    check_plants,
    check_gait,
    check_overlap,
    check_weight,
    check_joins,
    check_travel,
    check_targets,
    check_limits,
    check_arms,
    check_cost,
    check_reduction,
]


def run(built, bodies: list) -> tuple:
    """Every check on a solved clip. `bodies` are the rigs it must play on, the reference body first. Returns the
    numbers and the failures."""
    played = {rig.path.stem: Played(built, rig) for rig in bodies}
    numbers, failures = {}, []
    for check in CHECKS:
        got, failed = check(built, played)
        numbers.update(got)
        failures += failed
    return numbers, failures
