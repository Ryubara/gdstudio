"""Every check against a clip built to break it (`build_own.py self-test`).

A check that has never failed proves nothing. For each check of `checks.py` this builds a clip that passes it and a
copy that is wrong in the one way the check is for, and fails unless the first passes and the second is refused
with that check's name. The clips are test clips, never shipped: a stand, a walk made from a contact plan (which is
also the proof that the plan, the foot paths and the travel work before the gaits' issue builds on them), and a hop.
"""

import copy
import math

import numpy as np

from . import build, checks, maths, overlap, weight
from .maths import FPS
from .build import Clip
from .plan import ContactPlan, Footfall, Travel, standing
from .rig import SIDES
from .solve import stand_spec

WALK_FRAMES = 32
WALK_SPEED = 1.0
WALK_DUTY = 0.62


def stand_clip(rig) -> Clip:
    plan = standing(30, rig, 0.02, 8.0)

    def spec(f: int) -> dict:
        out = stand_spec(rig)
        out["pelvis"]["place"] = rig.rest_pos["pelvis"] - maths.Y * 0.01
        out["chest"] = (1.0 * maths.wave(f, 30), 0.0, 0.0)
        del out["leg"]
        for s, _ in SIDES:
            out.setdefault("arm", {})[s] = {"out": 12.0, "bend": 10.0}
        return out

    return Clip("Stand_Test", 30, plan, spec, kind="stand")


def walk_clip(rig, arms: float = 1.0, lags: dict | None = None) -> Clip:
    """A plain walk from a contact plan: the left foot lands at 0, the right half a cycle later."""
    n, speed = WALK_FRAMES, WALK_SPEED
    stance = WALK_DUTY * n
    reach = 0.5 * speed * stance / FPS
    falls = []
    for s, sign in SIDES:
        land = 0.0 if s == "l" else n / 2.0
        ball = rig.sole[s]["ball"]
        place = (ball[0], ball[2] + speed * land / FPS + reach - 0.05)
        falls.append(Footfall(s, land, land + stance, place, heel_strike=12.0, roll_in=3.0, toe_off=38.0, roll_out=6.0))
    plan = ContactPlan(n, falls, Travel.steady(speed), clearance=0.05)

    def spec(f: int) -> dict:
        root, _ = plan.travel.at(float(f))
        phase = 2.0 * math.pi * f / n
        bob = 0.016 * math.cos(2.0 * (phase - 2.0 * math.pi * 3.0 / n) + math.pi)
        out = {
            "pelvis": {
                "place": rig.rest_pos["pelvis"] + root + maths.Y * (bob - 0.06),
                "turn": (2.0, -5.0 * math.cos(phase), 0.0),
            },
            "chest": (3.0, 5.0 * math.cos(phase), 0.0),
            "arm": {},
        }
        for s, sign in SIDES:
            swing = -sign * arms * 22.0 * math.cos(phase)
            out["arm"][s] = {"swing": swing, "out": 9.0, "bend": 14.0 + 0.4 * swing, "carry": 1.0}
        return out

    chains = overlap.chains_from(lags or {}, {f"lowerarm_{s}": "forearm" for s, _ in SIDES})
    # A plain sine of a walk: a reducer keeps more of it than of a clip with holds, so its share is declared.
    declared = {
        "ranges": {"cadence": (105.0, 120.0), "planted_share": (0.55, 0.65)},
        "distance": speed * n / FPS,
        "keys_kept": 0.55,
    }
    if lags:
        declared["lags"] = {part: value[0] for part, value in lags.items()}
    return Clip("Walk_Test", n, plan, spec, chains=chains, kind="gait", declared=declared)


def hop_built(rig, solver, arc: bool):
    """A stand whose feet leave the floor for frames 8 to 22 while the pelvis rises and falls: on a free fall's arc
    when `arc`, on straight lines when not."""
    clip = stand_clip(rig)
    clip.name, clip.loop, clip.kind = "Hop_Test", False, "action"
    falls = []
    for fall in clip.plan.footfalls:
        falls.append(Footfall(fall.side, 0.0, 7.0, fall.place, fall.yaw))
        falls.append(Footfall(fall.side, 23.0, 30.0, fall.place, fall.yaw))
    built = build.build_clip(rig, solver, clip)
    built.clip.plan = ContactPlan(30, falls, loop=False)
    built.record["contacts"] = {s: built.clip.plan.contacts(s) for s, _ in SIDES}
    built = dense(built)
    pelvis = rig.index["pelvis"]
    air = 16
    rise = 0.5 * weight.G * (air / FPS)
    heights = weight.free_fall(0.0, rise, air + 1) if arc else np.concatenate([np.linspace(0, 0.3, 8), np.linspace(0.3, 0, 9)])
    # The pelvis's translation is in the root's axes, where up is the root's -Z.
    up = rig.rest_rot[rig.parent["pelvis"]].T @ maths.Y
    for k, height in enumerate(heights):
        built.translation[7 + k, pelvis] += up * height
    return built


def dense(built):
    """A copy that keeps every key, so a change to any frame is what the checks play."""
    twin = copy.copy(built)
    twin.rotation, twin.translation = built.rotation.copy(), built.translation.copy()
    every = np.arange(built.rotation.shape[0])
    twin.kept = {
        **built.kept,
        "rotation": {bone: every for bone in built.kept["rotation"]},
        "place": {bone: every for bone in built.kept["place"]},
    }
    twin.record = dict(built.record)
    twin.clip = copy.copy(built.clip)
    twin.clip.declared = {**built.clip.declared, "kb_a_second": 1000.0}
    twin.miss = dict(built.miss)
    return twin


def turned(built, rig, bone: str, frames, degrees: float, axis=maths.X):
    """A copy with a bone turned further on some frames."""
    twin = dense(built)
    i = rig.index[bone]
    for f in frames:
        local = maths.matrix_of(twin.rotation[f, i]) @ maths.axis_angle(axis, degrees)
        twin.rotation[f, i] = maths.quat_of(local)
    return twin


def run(rig, solver, bodies) -> int:
    stand = build.build_clip(rig, solver, stand_clip(rig))
    walk = build.build_clip(rig, solver, walk_clip(rig))
    pelvis = rig.index["pelvis"]
    cases = []

    def case(name: str, check: str, good, bad) -> None:
        cases.append((name, check, good, bad))

    # seam: the last key differs from the first; a jump of speed across the seam.
    case("the last pose is not the first", "seam", walk, turned(walk, rig, "Head", [WALK_FRAMES], 2.0))
    kink = dense(walk)
    kink.translation[[0, -1], pelvis] += np.array([0.0, 0.0, 0.02])
    case("the seam jumps", "seam", walk, kink)
    # floor: the body sunk; a planted sole lifted.
    sunk = dense(stand)
    sunk.translation[:, pelvis] += rig.rest_rot[rig.parent["pelvis"]].T @ (-0.012 * maths.Y)
    case("the feet are under the floor", "floor", stand, sunk)
    # planted: a planted foot slid; the speed in clips.json wrong.
    slid = dense(walk)
    slid.translation[:, pelvis] += np.outer(np.sin(np.arange(WALK_FRAMES + 1) * 2 * math.pi / WALK_FRAMES), [0.02, 0, 0])
    case("a planted foot slides", "planted", walk, slid)
    fast = dense(walk)
    fast.record["speed"] = WALK_SPEED * 1.06
    case("clips.json has another speed", "planted", walk, fast)
    # plants: a planted hand that swings.
    held = dense(stand)
    held.clip.declared["plants"] = [{"bone": "foot_l", "from": 2, "to": 28}]
    swung = dense(walk)
    swung.clip.declared["plants"] = [{"bone": "hand_l", "from": 2, "to": 28}]
    case("a planted hand drifts", "plants", held, swung)
    # gait: arms in step with their own side's legs; a cadence outside the declared range.
    case("the arms swing with their own side's legs", "gait", walk, build.build_clip(rig, solver, walk_clip(rig, arms=-1.0)))
    slow = dense(walk)
    slow.clip.declared["ranges"] = {"cadence": (125.0, 140.0)}
    case("the cadence is outside its range", "gait", walk, slow)
    # overlap: a declared lag the clip does not have; a pop on a landing frame.
    lagged = build.build_clip(rig, solver, walk_clip(rig, lags={"forearm": [2.0, 0.1]}))
    wrong = dense(lagged)
    wrong.clip.declared["lags"] = {"forearm": 5.0}
    case("the forearm does not trail by the declared frames", "overlap", lagged, wrong)
    case("the head pops on a landing frame", "overlap", walk, turned(walk, rig, "Head", [16], 3.0))
    # weight: the centre of mass beside the one foot that is down; a jump on straight lines.
    aside = dense(stand)
    aside.clip.plan = ContactPlan(30, [fall for fall in stand.clip.plan.footfalls if fall.side == "r"])
    case("the centre of mass is outside the feet", "weight", stand, aside)
    case("a jump is not on a free fall's arc", "weight", hop_built(rig, solver, True), hop_built(rig, solver, False))
    # joins: a first pose that is not the pose it joins.
    joined = dense(stand)
    joined.clip.declared["joins"] = {"first": (stand.rotation[0], stand.translation[0]), "first_speed": 0.0}
    apart = dense(stand)
    apart.clip.declared["joins"] = {"first": (stand.rotation[8], stand.translation[8] + 0.004)}
    case("the first pose is not the pose it joins", "joins", joined, apart)
    # travel: a declared distance the root does not travel.
    short = dense(walk)
    short.clip.declared["distance"] = 0.5
    case("the root does not travel the declared distance", "travel", walk, short)
    # limits: a knee bent backward; a jump in a joint's speed.
    case("a knee bends backward", "limits", walk, turned(walk, rig, "calf_l", range(8, 12), 35.0))
    case("a joint jumps", "limits", stand, turned(stand, rig, "upperarm_l", [15], 40.0))
    # cost: noise on every key.
    noisy = dense(stand)
    rng = np.random.default_rng(7)
    for bone in ("upperarm_l", "lowerarm_l", "spine_02"):
        for f in range(1, 30):
            local = maths.matrix_of(noisy.rotation[f, rig.index[bone]]) @ maths.axis_angle(maths.Z, rng.uniform(-3, 3))
            noisy.rotation[f, rig.index[bone]] = maths.quat_of(local)
    noisy.clip.declared["speed_limit"] = 90.0
    case("a reducer can drop nothing", "cost", stand, noisy)
    # reduction: keys dropped that the clip needs.
    thin = copy.copy(walk)
    thin.kept = {**walk.kept, "rotation": {**walk.kept["rotation"], "thigh_l": np.array([0, WALK_FRAMES])}}
    case("the reduced keys stray from the full curve", "reduction", walk, thin)

    failed = 0
    for name, check, good, bad in cases:
        _, good_failures = checks.run(good, bodies)
        _, bad_failures = checks.run(bad, bodies)
        clean = not good_failures
        caught = any(line.startswith(check + ":") for line in bad_failures)
        verdict = "ok" if clean and caught else "WRONG"
        failed += verdict != "ok"
        print(f"SELFTEST {check}: {name}: {verdict}")
        if not clean:
            print(f"   the good clip failed: {good_failures}")
        if not caught:
            print(f"   the broken clip was not refused by `{check}`: {bad_failures}")
    # The frozen list.
    result = build.build_file(rig, [stand], bodies, ["Stand_Test", "Another"])
    caught = any("frozen list" in line for line in result["failures"])
    failed += not caught
    print(f"SELFTEST frozen: a clip the list does not name: {'ok' if caught else 'WRONG'}")
    print(f"SELFTEST {'PASSED' if not failed else f'FAILED ({failed})'}: {len(cases) + 1} cases")
    return 1 if failed else 0
