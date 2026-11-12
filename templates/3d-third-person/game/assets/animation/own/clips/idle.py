"""`Idle`: standing still, alive (kit #1154). Replaces `ual1/Idle`.

The library's idle breathes and nothing else: 17 bones move, the pelvis 8.5 mm, no weight shift, no fingers
(`docs/tools/blender/own-animation.md#audit-clips`). Ours is built from what a standing person does (the research
and its sources are in `../README.md`):

- **The weight is on one leg, and moves.** The clip stands on its left leg, shifts onto the right and comes back,
  once a loop. The shift is written as the share of the weight the left foot carries; the pelvis is solved from it
  (the centre of mass is put over that point between the feet), so the body is always in balance.
- **The hips tip and the shoulders answer.** The hip of the leg that carries nothing drops, that knee softens, the
  pelvis turns a little toward it, and the chest leans the other way so the head stays over the feet.
- **Breath goes through the spine and the collarbones**: the upper spine opens, the collarbones rise, the arms
  ride out a little. In is quicker than out and there is a pause after out.
- **The hands live**: the fingers hang in a relaxed curl that deepens from the index to the little finger, and
  each finger opens and closes a few degrees on its own slow period.
- **The head drifts** on periods of its own, and the arms, the hands, the chest and the head take all of it late,
  through the overlap pass.

Every period divides the loop, so the loop closes without a key being placed for it.
"""

from gdsanim import maths, overlap, plan, weight
from gdsanim.build import Clip
from gdsanim.rig import SIDES

## What each number of a style's `idle` section means, with the values a style starts from.
DEFAULTS = {
    "frames": 300,  # the loop's length
    "width": 0.02,  # metres each foot stands wider than the rest stance
    "toe_out": 9.0,  # degrees each foot points outward
    "stagger": 0.0,  # metres the left foot stands ahead of the right
    "leg_stretch": 0.997,  # the share of its full length the straighter leg is stretched to (1 locks the knee)
    "share": 0.66,  # the share of the weight on the carrying foot when the shift is done (0.5 is none)
    "hold_left": 0.25,  # the share of the loop spent on the left leg before the shift to the right starts
    "hold_right": 0.30,  # and on the right leg before the shift back
    "shift_frames": 60,  # frames a shift takes
    "shift_sharp": 0.0,  # 0 eases the shift over all its frames; toward 1 it holds, snaps and holds
    "shift_settle": [0.0, 0.0],  # the weight's own spring: frames it trails, and the share it swings past by
    "hip_tip": 3.0,  # degrees the free leg's hip drops when the shift is done
    "hip_turn": 2.0,  # degrees the pelvis turns toward the free leg
    "counter": 0.6,  # the chest's lean the other way, as a share of the hip's tip
    "ahead": 0.34,  # where the weight is between the heel (0) and the toe (1): a standing body's is just ahead of the ankle
    "sway": 0.004,  # metres the weight drifts toward the toes and back, twice a loop
    "breath_frames": 100,  # frames a breath takes
    "breath_ribs": 1.0,  # degrees the upper spine opens at the top of a breath
    "breath_clavicle": 1.2,  # degrees the collarbones rise
    "breath_arms": 0.6,  # degrees the arms ride out
    "head_yaw": 3.0,  # degrees the head drifts to each side
    "head_pitch": 1.0,  # degrees it nods with its drift
    "head_sharp": 0.0,  # 0 lets the head drift; toward 1 it looks, holds and looks back
    "arm_out": 7.0,  # degrees the arms hang out from the body
    "arm_swing": 1.5,  # degrees they hang forward
    "thumb_out": 38.0,  # degrees the thumb is lifted from under the palm to lie beside it
    "arm_clear": 0.127,  # metres the wrist, the knuckles and the fingertips keep from the thigh's line, on every body
    "elbow": 12.0,  # degrees the elbows bend
    "pronate": 12.0,  # degrees the forearm turns the thumb inward
    "wrist": 6.0,  # degrees the wrist bends toward the palm
    "carry": 0.35,  # the share of the chest's tilt the arms take
    "curl": [26.0, 52.0, 62.0, 70.0, 76.0],  # the fingers' curl at rest: thumb, index, middle, ring, little
    "finger_live": 4.0,  # degrees each finger opens and closes
}
## The bones the overlap pass moves, and the style's part each takes its numbers from.
PARTS = {
    "spine_01": ("chest", 1 / 3),
    "spine_02": ("chest", 1 / 3),
    "spine_03": ("chest", 1 / 3),
    "neck_01": ("head", 0.5),
    "Head": ("head", 0.5),
    "upperarm_l": "upperarm",
    "upperarm_r": "upperarm",
    "lowerarm_l": "forearm",
    "lowerarm_r": "forearm",
    "hand_l": "hand",
    "hand_r": "hand",
}
FINGER_NAMES = ("thumb", "index", "middle", "ring", "pinky")


def _breath(f: float, period: float) -> float:
    """0 to 1 and back: in for 38 % of the breath, out for 47 %, a pause for the rest."""
    p = (f / period) % 1.0
    if p < 0.38:
        return maths.smooth(p / 0.38)
    if p < 0.85:
        return 1.0 - maths.smooth((p - 0.38) / 0.47)
    return 0.0


def describe(rig, style, name: str = "Idle") -> Clip:
    n = style.numbers("idle", DEFAULTS)
    frames = int(n["frames"])
    assert frames % int(n["breath_frames"]) == 0, "a breath's frames must divide the loop's"
    stand = plan.standing(frames, rig, n["width"], n["toe_out"], n["stagger"])
    legs = {s: stand.foot(rig, s, 0.0) for s, _ in SIDES}

    # The weight: +1 on the left leg, -1 on the right, a number a frame, then through its own spring.
    shift, sharp = float(n["shift_frames"]), n["shift_sharp"]
    go_right = n["hold_left"] * frames
    go_left = go_right + shift + n["hold_right"] * frames
    assert go_left + shift <= frames, "the holds and the two shifts are longer than the loop"

    def raw(f: float) -> float:
        if f < go_right:
            return 1.0
        if f < go_right + shift:
            return 1.0 - 2.0 * maths.ease((f - go_right) / shift, sharp)
        if f < go_left:
            return -1.0
        if f < go_left + shift:
            return -1.0 + 2.0 * maths.ease((f - go_left) / shift, sharp)
        return 1.0

    side = overlap.follow([raw(float(f)) for f in range(frames + 1)], n["shift_settle"][0], n["shift_settle"][1], True)

    def look(f: float) -> float:
        """The head's drift, -1 to 1: two periods layered, or a look that is held."""
        drift = 0.7 * maths.wave(f, frames, 0.12) + 0.3 * maths.wave(f, frames / 2.0, 0.4)
        if n["head_sharp"] <= 0.0:
            return drift
        held = maths.pulse(f, 0.18 * frames, 0.1 * frames, 0.22 * frames, 0.1 * frames, n["head_sharp"])
        other = maths.pulse(f, 0.62 * frames, 0.1 * frames, 0.2 * frames, 0.1 * frames, n["head_sharp"])
        return held - 0.7 * other

    def spec(f: int) -> dict:
        w = side[f]
        breath = _breath(f, n["breath_frames"])
        tip, turn = n["hip_tip"] * w, n["hip_turn"] * w
        gaze = look(float(f))
        arms, fingers = {}, {}
        for s, sign in SIDES:
            arms[s] = {
                "swing": n["arm_swing"] + 0.6 * maths.wave(f, frames / 2.0, 0.3 + 0.2 * sign),
                "out": n["arm_out"] + n["breath_arms"] * breath,
                "clear": n["arm_clear"],
                "bend": n["elbow"] + 1.0 * maths.wave(f, frames / 3.0, 0.1 + 0.25 * sign),
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
        return {
            "pelvis": {
                "place": rig.rest_pos["pelvis"].copy(),
                "turn": (0.0, turn, -tip),
            },
            "chest": (0.4 * maths.wave(f, frames / 2.0, 0.2), -0.5 * turn, n["counter"] * tip),
            "ribs": n["breath_ribs"] * breath,
            "head": (
                n["head_pitch"] * maths.wave(f, frames / 2.0, 0.05) - 0.4 * breath,
                n["head_yaw"] * gaze,
                0.25 * n["counter"] * tip,
            ),
            "clavicle": {s: (n["breath_clavicle"] * breath, 0.0) for s, _ in SIDES},
            "arm": arms,
            "fingers": fingers,
            "leg": {s: dict(legs[s]) for s, _ in SIDES},
        }

    def balance(f: int, at: dict) -> tuple:
        share = 0.5 + (n["share"] - 0.5) * side[f]
        ahead = n["ahead"] + n["sway"] / 0.25 * maths.wave(f, frames / 2.0, 0.0)
        return weight.support_point(rig, at["leg"], share, ahead)

    numbers = style.overlap("idle")
    return Clip(
        name=name,
        frames=frames,
        plan=stand,
        spec=spec,
        balance=balance,
        stretch=n["leg_stretch"],
        chains=overlap.chains_from(numbers, PARTS),
        kind="stand",
        declared={},
        replaces="ual1/Idle",
        style=style.letter,
    )
