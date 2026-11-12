"""`Crouch_Idle`: crouched and still, alive (kit #1160). Replaces `ual1/Crouch_Idle`.

The library's crouch idle is a deep half kneel that breathes and nothing else
(`docs/tools/blender/own-animation.md#audit-clips`), and it reads as a person at ease because no part of it is
lined up with its other side. Ours is a crouch of our own numbers with the same freedom (what each side of the
library's does, and the research, are in `../README.md`). No number here has one value for both sides unless it
says so: a pair is `[left, right]`.

- **A staggered stance.** The left foot stands flat where the standing idle has it; the right foot is a step
  behind on its ball, wider and turned out further, its heel up. One step of the right foot makes the stance, so
  the stance changes step it there and back while the left sole never moves.
- **The knees are apart at different heights.** The left knee is up in front of the chest; the right points
  outward and hangs low, a hand or two off the floor.
- **The weight sits back and to one side.** The pelvis is solved until the centre of mass is over a point between
  the flat foot and the ball of the rear one, turned toward the rear leg and tipped so that leg's hip is lower.
- **The trunk turns and leans against the hips**, the head looks ahead from a little to one side, and the whole
  body stays under the crouched capsule.
- **The arms do different things.** The left forearm lies across the left thigh above the knee, its hand hanging
  loose inside it (`rest`: the arm is lowered until the forearm is on the thigh, on every frame); the right arm
  hangs outside the low knee toward the floor.
- **It lives:** the weight goes between the feet and back once a loop, breath goes through the spine and the
  collarbones, the fingers move (the hanging hand's more), and the head drifts (or looks, holds and looks back).
"""

import numpy as np

from gdsanim import maths, overlap
from gdsanim.build import Clip
from gdsanim.plan import ContactPlan, Footfall
from gdsanim.rig import SIDES

from . import idle

## The crouched capsule's height (`CharacterTuning.crouch_height`): no part of a crouched body is above it.
CEILING = 1.1
## What each number of a style's `crouch_idle` section means, with the values a style starts from. A pair is
## `[left, right]`: each side has its own number.
DEFAULTS = {
    "frames": 240,  # the loop's length
    "fold": 0.535,  # the share of its full length the straighter leg is folded to (hip to ankle): the depth
    "foot_ahead": [0.0, -0.52],  # metres each foot's ball stands ahead of its place in the standing idle
    "foot_wide": [0.0, 0.04],  # metres each foot stands wider than in the standing idle
    "foot_turn": [0.0, 17.0],  # degrees each foot is turned further outward than in the standing idle
    "heel": [0.0, 46.0],  # degrees each heel is held up over its toes
    "knee_out": [3.0, 4.0],  # degrees each knee points outward of its foot
    "knee_down": [0.0, 30.0],  # degrees each knee points under level: a knee that hangs toward the floor
    "share": 0.67,  # the share of the weight on the left (front, flat) foot at rest
    "shift": 0.05,  # how far the share moves to each side over the loop
    "shift_settle": [0.0, 0.0],  # the weight's own spring: frames it trails, and the share it swings past by
    "ahead": 0.45,  # where the weight is between the heel (0) and the toe (1) of the flat foot
    "sway": 0.003,  # metres the weight drifts toward the toes and back, twice a loop
    "pelvis": [12.0, -11.0, -5.0],  # the pelvis's turn: pitch forward, yaw to the left, lean to the left
    "chest": [78.0, 7.0, 4.0],  # the top of the spine's turn, the same three
    "head": [22.0, 5.0, -3.0],  # the head's turn
    "hip_tip": 1.5,  # degrees the pelvis tips further as the weight shifts
    "hip_turn": 2.0,  # degrees it turns with the shift
    "counter": 0.6,  # the chest's lean the other way, as a share of the hip's tip
    "breath_frames": 80,  # frames a breath takes (a crouch is work: quicker than standing)
    "breath_ribs": 1.2,  # degrees the upper spine opens at the top of a breath
    "breath_clavicle": 1.4,  # degrees the collarbones rise
    "breath_arms": 0.6,  # degrees a hanging arm rides out
    "head_yaw": 4.0,  # degrees the head drifts to each side
    "head_sharp": 0.0,  # 0 lets the head drift; toward 1 it looks, holds and looks back
    "arm_swing": [50.0, 10.0],  # degrees each upper arm hangs forward of straight down
    "arm_out": [8.0, 24.0],  # degrees it hangs out from the body
    "arm_twist": [30.0, 0.0],  # degrees it is turned inward about itself: the forearm points across the body
    "elbow": [58.0, 16.0],  # degrees each elbow bends
    "pronate": [36.0, 20.0],  # degrees each forearm turns the thumb inward
    "wrist": [32.0, 5.0],  # degrees each wrist bends toward the palm
    "carry": [0.5, 0.15],  # the share of the chest's tilt each arm takes
    "arm_rest": [0.115, 0.0],  # metres a forearm's line lies from its own thigh's (0: the arm hangs free)
    "hand_rest": [0.075, 0.0],  # metres that hand's line (wrist to knuckles) keeps from the thigh's
    "arm_clear": [0.0, 0.10],  # metres a hanging hand keeps from its thigh's line (0: not asked)
    "thumb_out": [30.0, 38.0],  # degrees each thumb is lifted from under the palm to lie beside it
    "curl": [26.0, 50.0, 58.0, 66.0, 72.0],  # the fingers' curl at rest: thumb, index, middle, ring, little
    "curl_more": [-14.0, 4.0],  # degrees each hand's fingers curl more than that
    "finger_live": [2.5, 5.0],  # degrees each hand's fingers open and close
}
PARTS = idle.PARTS
FINGER_NAMES = idle.FINGER_NAMES
## A pair's index for a side.
AT = {"l": 0, "r": 1}


def feet(rig, style, frames: int, joined=None, loop: bool = True, numbers: dict | None = None) -> ContactPlan:
    """Both feet down where the crouch has them: each from its place in the shipped standing idle (the style's
    own idle without `joined`), moved and turned by its own numbers."""
    n = numbers or (joined.style("Crouch_Idle") if joined else style).numbers("crouch_idle", DEFAULTS)
    stand = (joined.style("Idle") if joined else style).numbers("idle", idle.DEFAULTS)
    falls = []
    for s, sign in SIDES:
        ball = rig.sole[s]["ball"]
        i = AT[s]
        place = (
            ball[0] + sign * (stand["width"] + n["foot_wide"][i]),
            ball[2] + sign * 0.5 * stand["stagger"] + n["foot_ahead"][i],
        )
        yaw = sign * (stand["toe_out"] + n["foot_turn"][i])
        falls.append(Footfall(s, 0.0, float(frames), place, yaw=yaw, heel=n["heel"][i]))
    return ContactPlan(frames, falls, loop=loop)


def knee_way(stand: ContactPlan, side: str, sign: float, out: float, down: float = 0.0):
    """The way a knee points: `out` degrees outward of its foot and `down` degrees under level."""
    fall = next(fall for fall in stand.footfalls if fall.side == side)
    return maths.body_turn(down, fall.yaw + sign * out, 0.0) @ maths.Z


def support(rig, stand: ContactPlan, n: dict, share_left: float, ahead: float) -> tuple:
    """The floor point the weight is over: `share_left` of the way from the right foot's point to the left's.
    A flat foot's point is `ahead` of the way from its heel to its toe; a foot on its ball stands on the ball."""
    points = {}
    for s, _ in SIDES:
        flat = stand.foot(rig, s, 0.0)
        if n["heel"][AT[s]] > 1.0:
            fall = next(fall for fall in stand.footfalls if fall.side == s)
            points[s] = np.array([fall.place[0], 0.0, fall.place[1]])
        else:
            sole = rig.sole[s]
            turn = maths.body_turn(0.0, flat["foot"][1], 0.0)
            ankle = np.asarray(flat["ankle"], dtype=float)
            heel = ankle + turn @ (sole["heel"] - sole["ankle"])
            toe = ankle + turn @ (sole["toe"] - sole["ankle"])
            points[s] = heel + ahead * (toe - heel)
    at = points["r"] + share_left * (points["l"] - points["r"])
    return float(at[0]), float(at[2])


def heel_up(n: dict) -> tuple:
    """The sides whose heel the crouch holds up."""
    return tuple(s for s, _ in SIDES if n["heel"][AT[s]] > 1.0)


def describe(rig, style, name: str = "Crouch_Idle", joined=None) -> Clip:
    n = style.numbers("crouch_idle", DEFAULTS)
    frames = int(n["frames"])
    assert frames % int(n["breath_frames"]) == 0, "a breath's frames must divide the loop's"
    stand = feet(rig, style, frames, joined, numbers=n)

    # The weight: +1 toward the left (front) foot, -1 toward the right, once a loop.
    side = overlap.follow(
        [maths.wave(float(f), frames, 0.0) for f in range(frames + 1)], n["shift_settle"][0], n["shift_settle"][1], True
    )

    def look(f: float) -> float:
        drift = 0.7 * maths.wave(f, frames, 0.3) + 0.3 * maths.wave(f, frames / 2.0, 0.1)
        if n["head_sharp"] <= 0.0:
            return drift
        held = maths.pulse(f, 0.12 * frames, 0.08 * frames, 0.24 * frames, 0.08 * frames, n["head_sharp"])
        other = maths.pulse(f, 0.58 * frames, 0.08 * frames, 0.22 * frames, 0.08 * frames, n["head_sharp"])
        return held - 0.8 * other

    def spec(f: int) -> dict:
        w = side[f]
        breath = idle._breath(f, n["breath_frames"])
        tip, turn = n["hip_tip"] * w, n["hip_turn"] * w
        arms, fingers, legs = {}, {}, {}
        for s, sign in SIDES:
            i = AT[s]
            hangs = n["arm_rest"][i] <= 0.0
            arms[s] = {
                "swing": n["arm_swing"][i] + 0.8 * maths.wave(f, frames / 2.0, 0.3 + 0.2 * sign),
                "out": n["arm_out"][i] + (n["breath_arms"] * breath if hangs else 0.0),
                "twist": n["arm_twist"][i],
                "bend": n["elbow"][i] + 1.5 * maths.wave(f, frames / 3.0, 0.1 + 0.25 * sign),
                "pronate": n["pronate"][i],
                "wrist": n["wrist"][i] + 1.5 * maths.wave(f, frames / 2.0, 0.55 + 0.2 * sign),
                "carry": n["carry"][i],
            }
            if hangs:
                arms[s]["clear"] = n["arm_clear"][i]
            else:
                arms[s]["rest"] = {"on": s, "gap": n["arm_rest"][i], "hand": n["hand_rest"][i]}
            curls = {}
            for k, finger in enumerate(FINGER_NAMES):
                live = 0.6 * maths.wave(f, frames / 2.0, 0.11 * k + 0.23 * sign) + 0.4 * maths.wave(
                    f, frames / 3.0, 0.19 * k - 0.1 * sign
                )
                part = 0.5 if finger == "thumb" else 1.0
                curls[finger] = max(n["curl"][k] + part * (n["curl_more"][i] + n["finger_live"][i] * live), 0.0)
            curls["thumb_out"] = n["thumb_out"][i]
            fingers[s] = curls
            legs[s] = stand.foot(rig, s, 0.0)
            legs[s]["knee"] = knee_way(stand, s, sign, n["knee_out"][i], n["knee_down"][i])
        pitch, yaw, lean = n["pelvis"]
        chest, head = n["chest"], n["head"]
        middle = 0.5 * (stand.footfalls[0].place[1] + stand.footfalls[1].place[1])
        return {
            "pelvis": {
                "place": rig.rest_pos["pelvis"] * (1.0, n["fold"] * 0.8, 1.0) + (0.0, 0.0, middle - 0.1),
                "turn": (pitch, yaw + turn, lean - tip),
            },
            "chest": (
                chest[0] + 0.5 * maths.wave(f, frames / 2.0, 0.2),
                chest[1] - 0.5 * turn,
                chest[2] + n["counter"] * tip,
            ),
            "ribs": n["breath_ribs"] * breath,
            "head": (
                head[0] - 0.4 * breath,
                head[1] + n["head_yaw"] * look(float(f)),
                head[2] + 0.25 * n["counter"] * tip,
            ),
            "clavicle": {s: (n["breath_clavicle"] * breath, 0.0) for s, _ in SIDES},
            "arm": arms,
            "fingers": fingers,
            "leg": legs,
        }

    def balance(f: int, at: dict) -> tuple:
        share = n["share"] + n["shift"] * side[f]
        ahead = n["ahead"] + n["sway"] / 0.25 * maths.wave(f, frames / 2.0, 0.0)
        return support(rig, stand, n, share, ahead)

    # An arm that lies on a thigh is left out of the overlap pass, which would pull it off its place.
    resting = tuple(f"{part}_{s}" for s, _ in SIDES if n["arm_rest"][AT[s]] > 0.0 for part in ("arm", "hand"))
    parts = {bone: part for bone, part in PARTS.items() if not bone.endswith(resting)}
    return Clip(
        name=name,
        frames=frames,
        plan=stand,
        spec=spec,
        balance=balance,
        stretch=n["fold"],
        chains=overlap.chains_from(style.overlap("crouch_idle"), parts),
        kind="stand",
        declared={"ceiling": CEILING, "heel_up": heel_up(n)},
        replaces="ual1/Crouch_Idle",
        style=style.letter,
    )
