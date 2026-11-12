"""`Stand_To_Crouch` and `Crouch_To_Stand`: the stance changes (kit #1160). New: the library has neither.

The game cross-faded between the standing idle and the library's crouch, two poses 719 mm apart at the head whose
feet stand in different places. These two clips are the move itself (the research and its sources are in
`../README.md`):

- **They begin and end on the shipped idles' first poses**, to the bit: every control is mixed from the one
  idle's first frame to the other's, each on its own timing, and what the overlap pass left in the joined clips'
  bones is taken out at the ends (`Clip.meet`).
- **One step makes the stance.** The left sole never moves. Going down, the right foot leaves over its toes as
  the hips let go, travels back and out and lands on its ball, turned out, as the body arrives over it; coming
  up it leaves from its ball once the legs have begun to push and lands flat beside the left.
- **Each side on its own.** The crouch's two arms do different things, so each arm's numbers are mixed from the
  standing idle's to its own; the arm that lies on a thigh in the crouch folds with the trunk, the one that hangs
  moves on the arms' own time, and each opens round its thigh by its own amount.
- **Going down is a fall that is caught.** The hips let go, the body drops no faster than gravity allows and the
  legs brake it at the bottom; the pelvis tips forward early and the spine and the knees finish the fold, the
  order a squat's joints reach their ends in.
- **Coming up is a push.** The legs drive first with the trunk still folded, the trunk unfolds after, the head
  comes up to the horizon last, and the rise ends no more sharply than gravity stops a body.
- **The weight stays over the feet**: the centre of mass is solved over a point that moves from the one idle's to
  the other's.
"""

import math

import numpy as np

from gdsanim import maths, overlap
from gdsanim.build import Clip
from gdsanim.plan import ContactPlan, Footfall
from gdsanim.rig import SIDES

from . import crouch_idle

## What each number of a style's `stand_to_crouch` section means, with the values a style starts from. A window is
## the shares of the clip a control starts and stops moving at.
DOWN = {
    "frames": 16,  # the clip's length
    "drop": [0.0, 0.94],  # the fold of the legs, from standing to crouched
    "fall": 0.62,  # the share of the drop spent falling before the legs brake (0.5 is even; more falls longer)
    "pelvis": [0.0, 0.62],  # the pelvis's tip and turn: early, as a squat's is
    "chest": [0.1, 1.0],  # the trunk's fold
    "head": [0.2, 1.0],  # the head
    "arms": [0.0, 0.55],  # the arms' carriage: forward of the thighs before the thighs come up under them
    "step": [0.2, 0.64],  # the foot that steps back: the shares of the clip it leaves the floor and lands at
    "step_clear": 0.05,  # metres the ball of that foot clears the floor by
    "toe_off": 20.0,  # degrees its heel is up as its toes leave
    "weight": [0.0, 0.8],  # the weight's place between the feet
    "arm_wide": [6.0, 12.0],  # degrees each arm (left, right) opens from the body in the middle of its move
    "arm_fore": [0.0, 0.0],  # degrees each arm is carried further forward in the middle of its move, over a thigh
    "meet": 4,  # frames over which the joined clips' overlap is let go at each end
}
## The same for `crouch_to_stand`.
UP = {
    "frames": 16,
    "drop": [0.04, 0.96],
    "fall": 0.42,  # under a half: the legs push early and the rise coasts to its top
    "pelvis": [0.2, 0.9],
    "chest": [0.18, 1.0],
    "head": [0.0, 0.7],
    "arms": [0.45, 1.0],  # late: the arms hang back beside the thighs once the thighs are down
    "step": [0.36, 0.88],  # the foot that steps up beside the other: it leaves once the legs have begun to push
    "step_clear": 0.05,
    "toe_off": 0.0,  # it leaves from its ball: the heel is already up
    "weight": [0.1, 0.9],
    "arm_wide": [6.0, 12.0],
    "arm_fore": [0.0, 0.0],
    "meet": 4,
}
PARTS = crouch_idle.PARTS
## Metres the male mannequin's toes are longer than the reference body's: a stepping foot clears the floor for them.
TOE_REACH = 0.026


def skewed(x: float, turn: float) -> float:
    """0 to 1 with no speed at either end, the fastest at the share `turn` of the way through: speeding up until
    then and slowing after, each at one rate (0.5 is an even ease)."""
    x = min(max(x, 0.0), 1.0)
    if x < turn:
        return x * x / turn
    return 1.0 - (1.0 - x) ** 2 / (1.0 - turn)


def window(u: float, span: list, turn: float = 0.5) -> float:
    start, stop = span
    return skewed((u - start) / max(stop - start, 1e-6), turn)


def mix(a, b, t: float):
    """A spec value between two: numbers, tuples, arrays and tables of them, by the share `t`."""
    if isinstance(a, dict):
        return {key: mix(a[key], b[key], t) if key in b else a[key] for key in a}
    if isinstance(a, (tuple, list)):
        return type(a)(mix(x, y, t) for x, y in zip(a, b, strict=True))
    if isinstance(a, np.ndarray):
        return a + (np.asarray(b) - a) * t
    return a + (b - a) * t


ARM_NUMBERS = ("swing", "out", "twist", "bend", "pronate", "wrist", "clear", "carry")


def plain_arm(arm: dict) -> dict:
    """A hanging arm's numbers alone, so two of them mix: a forearm that rests on a thigh (`rest`) becomes the
    swing the rest gave it."""
    out = {key: float(arm.get(key, 0.0)) for key in ARM_NUMBERS}
    out["swing"] += float(arm.get("rest_by", 0.0))
    return out


def stance_plan(rig, frames: int, a_plan, b_plan, step: list, toe_off: float, clearance: float) -> tuple:
    """The feet of a stance change: a foot that stands on the same place in both clips stays down for the whole
    clip; one that does not takes one step, leaving at the share `step[0]` of the clip and landing at `step[1]`.
    Returns the plan and the sides that step."""
    falls, stepping = [], []
    for s, _ in SIDES:
        one = next(fall for fall in a_plan.footfalls if fall.side == s)
        other = next(fall for fall in b_plan.footfalls if fall.side == s)
        moved = math.hypot(one.place[0] - other.place[0], one.place[1] - other.place[1])
        if moved < 1e-4 and abs(one.yaw - other.yaw) < 0.01 and abs(one.heel - other.heel) < 0.01:
            falls.append(Footfall(s, 0.0, float(frames), one.place, yaw=one.yaw, heel=one.heel))
            continue
        lift, land = step[0] * frames, step[1] * frames
        # A flat foot leaves over its toes; one that stands on its ball already has its heel up.
        roll = lift if one.heel <= 0.0 else 0.0
        falls.append(Footfall(s, 0.0, lift, one.place, yaw=one.yaw, heel=one.heel, toe_off=toe_off, roll_out=roll))
        falls.append(Footfall(s, land, float(frames), other.place, yaw=other.yaw, heel=other.heel))
        stepping.append(s)
    plan = ContactPlan(frames, falls, loop=False, clearance=clearance, toe_reach=TOE_REACH)
    return plan, tuple(stepping)


def _between(rig, style, name: str, joined, section: str, defaults: dict, first: str, last: str) -> Clip:
    assert joined is not None, "a stance change needs the clips it joins (`clips.joined.Joined`)"
    n = style.numbers(section, defaults)
    frames = int(n["frames"])
    a, b = joined.start(first), joined.start(last)
    down = last == "Crouch_Idle"
    c = joined.style("Crouch_Idle").numbers("crouch_idle", crouch_idle.DEFAULTS)
    a_plan, b_plan = joined.clip(first).plan, joined.clip(last).plan
    stand, stepping = stance_plan(rig, frames, a_plan, b_plan, n["step"], n["toe_off"], n["step_clear"])
    knees = {
        end: {
            s: np.asarray(start["spec"]["leg"][s].get("knee", crouch_idle.knee_way(plan, s, sign, 0.0)))
            for s, sign in SIDES
        }
        for end, start, plan in (("a", a, a_plan), ("b", b, b_plan))
    }
    arms = {end: {s: plain_arm(start["spec"]["arm"][s]) for s, _ in SIDES} for end, start in (("a", a), ("b", b))}
    # An arm that lies on a thigh in the crouch folds with the trunk; one that hangs moves on the arms' own time.
    rests = tuple(s for s, _ in SIDES if c["arm_rest"][crouch_idle.AT[s]] > 0.0)

    def shares(f: int) -> dict:
        u = f / frames
        return {
            "drop": window(u, n["drop"], n["fall"]),
            "pelvis": window(u, n["pelvis"]),
            "chest": window(u, n["chest"]),
            "head": window(u, n["head"]),
            "arms": window(u, n["arms"]),
            "weight": window(u, n["weight"]),
        }

    def spec(f: int) -> dict:
        t = shares(f)
        one, other = a["spec"], b["spec"]
        legs = {}
        for s, _ in SIDES:
            legs[s] = stand.foot(rig, s, float(f))
            legs[s]["knee"] = maths.unit(mix(knees["a"][s], knees["b"][s], t["drop"]))
        out = {
            "pelvis": {
                "place": mix(np.asarray(one["pelvis"]["place"]), np.asarray(other["pelvis"]["place"]), t["drop"]),
                "turn": mix(tuple(one["pelvis"]["turn"]), tuple(other["pelvis"]["turn"]), t["pelvis"]),
            },
            "chest": mix(tuple(one["chest"]), tuple(other["chest"]), t["chest"]),
            "ribs": mix(one["ribs"], other["ribs"], t["chest"]),
            "head": mix(tuple(one["head"]), tuple(other["head"]), t["head"]),
            "clavicle": mix(one["clavicle"], other["clavicle"], t["arms"]),
            "arm": {s: mix(arms["a"][s], arms["b"][s], t["chest" if s in rests else "arms"]) for s, _ in SIDES},
            "fingers": mix(one["fingers"], other["fingers"], t["arms"]),
            "leg": legs,
        }
        for s, _ in SIDES:
            middle = math.sin(math.pi * t["chest" if s in rests else "arms"])
            out["arm"][s]["out"] += n["arm_wide"][crouch_idle.AT[s]] * middle
            out["arm"][s]["swing"] += n["arm_fore"][crouch_idle.AT[s]] * middle
        return out

    def balance(f: int, at: dict) -> tuple:
        return mix(tuple(a["over"]), tuple(b["over"]), shares(f)["weight"])

    def stretch(f: int) -> float:
        return mix(a["stretch"], b["stretch"], shares(f)["drop"])

    built_a, built_b = joined.built(first), joined.built(last)
    declared = {
        "joins": {
            "first": (built_a.rotation[0], built_a.translation[0]),
            "last": (built_b.rotation[0], built_b.translation[0]),
            "first_speed": 0.0,
            "last_speed": 0.0,
        },
        "distance": 0.0,
        "turn": 0.0,
        "join_names": {"first": first, "last": last},
        # A stance change is all motion: a reducer keeps most of its few frames.
        "keys_kept": 0.9,
        "kb_a_second": 40.0,
    }
    low = int(round(frames * (n["drop"][1] if down else n["drop"][0])))
    return Clip(
        name=name,
        frames=frames,
        plan=stand,
        spec=spec,
        loop=False,
        balance=balance,
        stretch=stretch,
        meet={"first": (built_a.frames[0], n["meet"]), "last": (built_b.frames[0], n["meet"])},
        chains=overlap.chains_from(style.overlap(section), PARTS),
        kind="transition",
        declared=declared,
        events=[{"frame": low, "name": "crouched" if down else "rising"}],
        style=style.letter,
    )


def describe_down(rig, style, name: str = "Stand_To_Crouch", joined=None) -> Clip:
    return _between(rig, style, name, joined, "stand_to_crouch", DOWN, "Idle", "Crouch_Idle")


def describe_up(rig, style, name: str = "Crouch_To_Stand", joined=None) -> Clip:
    return _between(rig, style, name, joined, "crouch_to_stand", UP, "Crouch_Idle", "Idle")
