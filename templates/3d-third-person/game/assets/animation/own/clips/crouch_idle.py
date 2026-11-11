"""`Crouch_Idle`: crouched and still, alive (kit #1160). Replaces `ual1/Crouch_Idle`.

The library's crouch idle is a deep half kneel, one foot 0.67 m ahead of the other, that breathes and nothing else
(`docs/tools/blender/own-animation.md#audit-clips`). A body cannot get there from standing without stepping, so the
game cross-fades between two poses whose feet are in different places. Ours is the crouch a standing body drops
into (the research and its sources are in `../README.md`):

- **The feet are where the standing idle has them.** Both soles stay on their places through `Stand_To_Crouch`
  and back, so the crouch stands on the standing idle's feet, whichever variant of it is shipped.
- **The left foot is flat, the right is on its ball.** A squat this deep (the capsule is 1.1 m tall) takes more
  bend than an ankle has with the heel down, so one heel comes up: the right knee drops lower and further forward
  than the left, which is also the knee that leaves first when the body goes on to lie down.
- **The weight is an input.** The pelvis is solved until the centre of mass is over a point between the feet
  (a little toward the flat foot) and the flat foot's leg is folded to a share of its length, so the body
  balances on every frame by construction.
- **The trunk folds over the thighs, the head looks ahead**, and the whole body stays under the crouched capsule.
- **It lives:** the weight goes from foot to foot and back once a loop, breath goes through the spine and the
  collarbones, the fingers move, and the head drifts (or looks, holds and looks back).
"""

from gdsanim import maths, overlap, plan, weight
from gdsanim.build import Clip
from gdsanim.rig import SIDES

from . import idle

## The crouched capsule's height (`CharacterTuning.crouch_height`): no part of a crouched body is above it.
CEILING = 1.1
## What each number of a style's `crouch_idle` section means, with the values a style starts from.
DEFAULTS = {
    "frames": 240,  # the loop's length
    "fold": 0.45,  # the share of its full length the flat foot's leg is folded to (hip to ankle): the depth
    "heel": 26.0,  # degrees the right heel is held up over its toes
    "knee_out": 18.0,  # degrees each knee points outward of its foot
    "share": 0.56,  # the share of the weight on the flat (left) foot at rest
    "shift": 0.07,  # how far the share moves to each side over the loop
    "shift_settle": [0.0, 0.0],  # the weight's own spring: frames it trails, and the share it swings past by
    "ahead": 0.5,  # where the weight is between the heel (0) and the toe (1) of the flat foot
    "sway": 0.003,  # metres the weight drifts toward the toes and back, twice a loop
    "pelvis_pitch": 12.0,  # degrees the pelvis tips forward
    "chest_pitch": 78.0,  # degrees the top of the spine leans forward
    "head_pitch": 12.0,  # degrees the head looks down from level
    "hip_tip": 2.0,  # degrees the lighter leg's hip drops as the weight shifts
    "hip_turn": 2.0,  # degrees the pelvis turns toward the lighter leg
    "counter": 0.6,  # the chest's lean the other way, as a share of the hip's tip
    "breath_frames": 80,  # frames a breath takes (a crouch is work: quicker than standing)
    "breath_ribs": 1.2,  # degrees the upper spine opens at the top of a breath
    "breath_clavicle": 1.4,  # degrees the collarbones rise
    "breath_arms": 0.6,  # degrees the arms ride out
    "head_yaw": 4.0,  # degrees the head drifts to each side
    "head_sharp": 0.0,  # 0 lets the head drift; toward 1 it looks, holds and looks back
    "arm_swing": 8.0,  # degrees the upper arms hang forward of straight down
    "arm_out": 4.0,  # degrees they hang out from the body
    "arm_clear": 0.10,  # metres the wrist, the knuckles and the fingertips keep from the thigh's line
    "elbow": 42.0,  # degrees the elbows bend: the hands hang ahead of the knees
    "pronate": 30.0,  # degrees the forearm turns the thumb inward
    "wrist": 8.0,  # degrees the wrist bends toward the palm
    "carry": 0.15,  # the share of the chest's tilt the arms take
    "thumb_out": 38.0,  # degrees the thumb is lifted from under the palm to lie beside it
    "curl": [26.0, 50.0, 58.0, 66.0, 72.0],  # the fingers' curl at rest: thumb, index, middle, ring, little
    "finger_live": 4.0,  # degrees each finger opens and closes
}
PARTS = idle.PARTS
FINGER_NAMES = idle.FINGER_NAMES


def feet(rig, style, frames: int, joined=None, loop: bool = True) -> plan.ContactPlan:
    """Both feet down where the shipped standing idle has them (the style's own idle without `joined`)."""
    stand = (joined.style("Idle") if joined else style).numbers("idle", idle.DEFAULTS)
    out = plan.standing(frames, rig, stand["width"], stand["toe_out"], stand["stagger"])
    out.loop = loop
    return out


def knee_way(stand: plan.ContactPlan, side: str, sign: float, out: float):
    """The way a knee points: `out` degrees outward of its foot."""
    fall = next(fall for fall in stand.footfalls if fall.side == side)
    return maths.body_turn(0.0, fall.yaw + sign * out, 0.0) @ maths.Z


def support(rig, stand: plan.ContactPlan, share_left: float, ahead: float) -> tuple:
    """The floor point between the two soles' places, whatever the heels do: `share_left` of the way from the
    right foot to the left, `ahead` of the way from each heel to its toe."""
    flat = {s: stand.foot(rig, s, 0.0) for s, _ in SIDES}
    return weight.support_point(rig, flat, share_left, ahead)


def describe(rig, style, name: str = "Crouch_Idle", joined=None) -> Clip:
    n = style.numbers("crouch_idle", DEFAULTS)
    frames = int(n["frames"])
    assert frames % int(n["breath_frames"]) == 0, "a breath's frames must divide the loop's"
    stand = feet(rig, style, frames, joined)

    # The weight: +1 toward the flat (left) foot, -1 toward the foot on its ball, once a loop.
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
            arms[s] = {
                "swing": n["arm_swing"] + 0.8 * maths.wave(f, frames / 2.0, 0.3 + 0.2 * sign),
                "out": n["arm_out"] + n["breath_arms"] * breath,
                "clear": n["arm_clear"],
                "bend": n["elbow"] + 1.5 * maths.wave(f, frames / 3.0, 0.1 + 0.25 * sign),
                "pronate": n["pronate"],
                "wrist": n["wrist"] + 1.5 * maths.wave(f, frames / 2.0, 0.55 + 0.2 * sign),
                "carry": n["carry"],
            }
            curls = {}
            for i, finger in enumerate(FINGER_NAMES):
                live = 0.6 * maths.wave(f, frames / 2.0, 0.11 * i + 0.23 * sign) + 0.4 * maths.wave(
                    f, frames / 3.0, 0.19 * i - 0.1 * sign
                )
                curls[finger] = n["curl"][i] + n["finger_live"] * live * (0.5 if finger == "thumb" else 1.0)
            curls["thumb_out"] = n["thumb_out"]
            fingers[s] = curls
            legs[s] = stand.raised(rig, s, 0.0, n["heel"] if s == "r" else 0.0)
            legs[s]["knee"] = knee_way(stand, s, sign, n["knee_out"])
        return {
            "pelvis": {
                "place": rig.rest_pos["pelvis"] * (1.0, n["fold"], 1.0),
                "turn": (n["pelvis_pitch"], turn, -tip),
            },
            "chest": (n["chest_pitch"] + 0.5 * maths.wave(f, frames / 2.0, 0.2), -0.5 * turn, n["counter"] * tip),
            "ribs": n["breath_ribs"] * breath,
            "head": (n["head_pitch"] - 0.4 * breath, n["head_yaw"] * look(float(f)), 0.25 * n["counter"] * tip),
            "clavicle": {s: (n["breath_clavicle"] * breath, 0.0) for s, _ in SIDES},
            "arm": arms,
            "fingers": fingers,
            "leg": legs,
        }

    def balance(f: int, at: dict) -> tuple:
        share = n["share"] + n["shift"] * side[f]
        ahead = n["ahead"] + n["sway"] / 0.25 * maths.wave(f, frames / 2.0, 0.0)
        return support(rig, stand, share, ahead)

    return Clip(
        name=name,
        frames=frames,
        plan=stand,
        spec=spec,
        balance=balance,
        stretch=n["fold"],
        chains=overlap.chains_from(style.overlap("crouch_idle"), PARTS),
        kind="stand",
        declared={"ceiling": CEILING},
        replaces="ual1/Crouch_Idle",
        style=style.letter,
    )
