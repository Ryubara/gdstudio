"""`Lean_Left`, `Lean_Right`, `Lean_Fwd`, `Lean_Back` and their reference `Lean_Ref`: the lean as poses (kit #1159).

A body that starts, stops or turns leans by its acceleration, `atan(a / g)` (the kit's
`docs/tools/blender/own-animation.md#feel`). The tree adds that lean over any gait as a difference between two
poses: a lean pose and the reference it leans from. Each clip here is one held pose:

- **`Lean_Ref`** is the shipped standing idle's first frame (its feet, its weight, its trunk) with the arms
  carried by the chest. It is the same in every variant.
- **A lean pose** is the reference with the centre of mass moved `degrees` off the upright, measured from the
  floor point the reference's weight is over, both soles flat where they stand. The pelvis is solved from that
  (`weight.settle`), so the ankles take what the trunk does not: the body bends from the ankles through the hips,
  the spine and the neck, each by its share (`hips`, `chest`, `head`), and a knee gives where a leg would
  otherwise be too short or too long.
- **The difference is the lean.** It moves the pelvis, the spine, the neck, the head and the legs, and each
  upper arm by the little that keeps it hanging along the body's line with its hand off its thigh (a chest that
  bends further than the body leans does not take the arms with it); the forearms, the hands and the fingers
  are the reference's, so a gait's arm swing is left alone. At full weight on the reference the feet are the
  lean pose's: flat, within 2 mm of the floor (the build's floor check, on every body).
- **No side is the other flipped.** Left and right have their own shares, turns and degrees: the right shoulder
  carries the weapon arm and drops less, the hips swing out further to the left.

`locomotion.json` says of each lean pose its `lean` (the way it leans, degrees to the left of ahead, and how many
degrees of lean the full pose is) and its `reference`, so the tree's weight is `atan(a / g)` over those degrees.
"""

import copy
import math

import numpy as np

from gdsanim import weight
from gdsanim.build import Clip, keyed_bones
from gdsanim.plan import ContactPlan, Footfall

## What each number of a style's `lean_left`, `lean_right`, `lean_fwd` or `lean_back` section means.
COMMON = {
    "way": 0.0,  # degrees to the left of ahead the body leans
    "degrees": 10.0,  # how far the centre of mass is off the upright over the feet at the full pose
    "hips": 0.7,  # the pelvis's lean, as a share of `degrees` (the ankles take the rest of what the weight needs)
    "chest": 1.0,  # the chest's lean, as a share of `degrees`
    "head": 0.4,  # the head's lean, as a share of `degrees` (0 keeps it level)
    "hips_turn": 0.0,  # degrees the pelvis turns to the left as it leans
    "chest_turn": 0.0,  # degrees the chest turns to the left
    "head_turn": 0.0,  # degrees the head turns to the left
    "nod": 0.0,  # degrees the head looks down more
    "stretch": 0.995,  # the share of its full length the straighter leg is at
}
DEFAULTS = {
    "lean_left": {**COMMON, "way": 90.0, "degrees": 10.0, "hips": 0.55, "chest": 1.1, "head": 0.35, "hips_turn": 2.0},
    "lean_right": {
        **COMMON,
        "way": -90.0,
        "degrees": 10.0,
        "hips": 0.9,
        "chest": 0.6,
        "head": 0.2,
        "hips_turn": -1.5,
        "chest_turn": -3.0,
    },
    "lean_fwd": {**COMMON, "way": 0.0, "degrees": 12.0, "hips": 0.8, "chest": 1.3, "head": 0.5, "chest_turn": 1.5},
    "lean_back": {
        **COMMON,
        "way": 180.0,
        "degrees": 8.0,
        "hips": 0.5,
        "chest": 1.2,
        "head": 0.2,
        "nod": 3.0,
        "chest_turn": -1.5,
    },
}
REFERENCE = "Lean_Ref"
## A held pose's length in frames: its first and last key are the one pose.
FRAMES = 2
## The bones a lean moves; the rest of the body is the reference's and stays out of the difference.
MOVED = ("pelvis", "spine_", "neck_", "Head", "thigh_", "calf_", "foot_", "ball_", "upperarm_")


def _reference(joined) -> tuple:
    """The reference's spec, the floor point its weight is over and its legs' stretch: the shipped idle's first
    frame with each arm carried whole by the chest, so an arm's turn in its shoulder does not change with the
    chest's lean."""
    assert joined is not None, "a lean pose needs the shipped idle (`clips.joined.Joined`)"
    start = joined.start("Idle")
    spec = copy.deepcopy(start["spec"])
    for arm in spec["arm"].values():
        arm["carry"] = 1.0
    return spec, start["over"], start["stretch"]


def _held(name: str, joined, spec: dict, over: tuple, stretch: float, style_letter: str, says: dict) -> Clip:
    rig = joined.rig
    # The idle's feet, for the pose's own two frames.
    stand = joined.clip("Idle").plan
    falls = [Footfall(fall.side, 0.0, float(FRAMES), fall.place, yaw=fall.yaw) for fall in stand.footfalls]
    return Clip(
        name=name,
        frames=FRAMES,
        plan=ContactPlan(FRAMES, falls, loop=True),
        spec=lambda f: copy.deepcopy(spec),
        loop=True,
        balance=lambda f, at: over,
        stretch=stretch,
        kind="action",
        # A held pose is two keys a bone: its cost is the clip's 1.6 KB, which a rate per second says nothing of.
        declared={"says": {"pose": True, **says}, "keys_kept": 1.0, "kb_a_second": 30.0},
        bones=[name for name in keyed_bones(rig) if not name.startswith("ik_")],
        style=style_letter,
    )


def reference(rig, style, name: str = REFERENCE, joined=None) -> Clip:
    spec, over, stretch = _reference(joined)
    return _held(name, joined, spec, over, stretch, "", {})


def describe(kind: str, rig, style, name: str, joined) -> Clip:
    n = style.numbers(kind, DEFAULTS[kind])
    spec, over, stretch = _reference(joined)
    upright = weight.settle(joined.solver, copy.deepcopy(spec), over, stretch)
    high = float(weight.centre_of_mass(rig, upright)[1])
    way = math.radians(n["way"])
    toward = np.array([math.sin(way), math.cos(way)])
    reach = high * math.tan(math.radians(n["degrees"]))
    # A lean to the left is a turn about the way ahead; a lean forward is a pitch.
    side, fore = float(toward[0]) * n["degrees"], float(toward[1]) * n["degrees"]
    pitch, yaw, lean = spec["pelvis"]["turn"]
    spec["pelvis"]["turn"] = (pitch + n["hips"] * fore, yaw + n["hips_turn"], lean + n["hips"] * side)
    pitch, yaw, lean = spec["chest"]
    spec["chest"] = (pitch + n["chest"] * fore, yaw + n["chest_turn"], lean + n["chest"] * side)
    pitch, yaw, lean = spec["head"]
    spec["head"] = (pitch + n["head"] * fore + n["nod"], yaw + n["head_turn"], lean + n["head"] * side)
    # The arms hang along the body's line, not the chest's: a chest that bends further than the body leans does
    # not take them with it. Each still keeps its hand off its thigh, on every body.
    for arm in spec["arm"].values():
        arm["carry"] = min(1.0, 1.0 / max(n["chest"], 1e-6))
    leaned = (over[0] + reach * float(toward[0]), over[1] + reach * float(toward[1]))
    says = {"lean": {"way": n["way"], "degrees": n["degrees"]}, "reference": REFERENCE}
    return _held(name, joined, spec, leaned, n["stretch"], style.letter, says)


def moved(bone: str) -> bool:
    """Whether a lean's difference from its reference may move a bone."""
    return bone.startswith(MOVED)


def lean_left(rig, style, name: str = "Lean_Left", joined=None) -> Clip:
    return describe("lean_left", rig, style, name, joined)


def lean_right(rig, style, name: str = "Lean_Right", joined=None) -> Clip:
    return describe("lean_right", rig, style, name, joined)


def lean_fwd(rig, style, name: str = "Lean_Fwd", joined=None) -> Clip:
    return describe("lean_fwd", rig, style, name, joined)


def lean_back(rig, style, name: str = "Lean_Back", joined=None) -> Clip:
    return describe("lean_back", rig, style, name, joined)
