"""The jump: take-offs, the air and landings (kit #1161). They replace `ual1/Jump_Start`, `ual1/Jump` and
`ual1/Jump_Land`; `Jump_Rise`, `Jump_Apex`, the running take-offs, `Land_Hard` and `Land_To_Jog` are new.

The library's take-off crouches on its first frame alone, one pose serves rising and falling, and its landing has
one depth and cannot land into a run (`docs/tools/blender/library-clip-audit.md#audit-clips`). Ours are built from
what the game's controller does and from how people jump and land (the research and its sources are in
`../README.md`):

- **The controller carries the body.** A jump is the capsule's: it leaves the floor on the tick the button is
  pressed, at `jump_speed`, and comes down under `fall_gravity_scale`. No clip has a frame on the floor before
  the take-off, because the game gives none. In the air the centre of mass keeps its place against the root, so
  it flies the arc the capsule flies (`declared["carried"]`), and the pelvis is what the limbs' motion leaves.
- **A take-off is the end of a push.** `Jump_Start` begins on the idle's first pose and `Jump_Start_Run_L` and
  `_R` on the jog's two foot strikes; the legs finish their stretch with the toes the last to leave, the arms
  swing up, and every one of them ends on `Jump_Rise`'s first pose.
- **Three poses of the air**, each a short loop that stays alive, for the tree to blend by the body's vertical
  speed: `Jump_Rise` stretched, `Jump_Apex` gathered, `Jump_Fall` reaching for the floor with the soles at the
  capsule's bottom, so a landing begins on the pose the fall ends on.
- **A landing is caught.** The capsule stops on one tick; the body goes on down, the legs take it over a few
  frames and push it back up no more sharply than gravity allows. `Land_Soft` is for a jump's own fall and gives
  control back inside the game's `land_time`, with its settle after; `Land_Hard` is for a fall from height;
  `Land_To_Jog` lands on one foot with the floor passing under it and ends in the jog's stride.
- **No side is the other's mirror** (`own-animation.md#feel`): every number a side could own is a pair
  `[left, right]`. The left foot is the last to leave and the first to land, the right knee leads in the air,
  the right foot lands a step ahead and later, and each arm has its own height and bend.
"""

import copy
import math

import numpy as np

from gdsanim import checks, maths, overlap, weight
from gdsanim.build import Clip
from gdsanim.maths import FPS, Y, body_turn
from gdsanim.plan import ContactPlan, Footfall, Travel
from gdsanim.rig import SIDES

from . import idle as idle_clip
from .stance import mix, skewed, window

## The controller's jump the clips are made for (`CharacterTuning`'s defaults; `tests/gameplay/test_own_clips.gd`
## fails when they part): metres a jump rises, seconds it rises for, how much stronger gravity is on the way
## down, seconds a landing holds the body, and the fall speed (m/s) from which a landing is played.
JUMP_HEIGHT = 1.25
RISE_TIME = 0.4
FALL_SCALE = 1.35
LAND_TIME = 0.3
LAND_CLIP_SPEED = 4.5
## The frames of the controller's rise: a take-off lasts all of it, so the arms float up while the body flies.
RISE_FRAMES = round(RISE_TIME * FPS)
## The fall speed (m/s) from which the hard landing is the one to play: a fall of 1.9 m under the game's gravity.
HARD_SPEED = 9.0
AT = {"l": 0, "r": 1}
TREAD = True
FINGER_NAMES = idle_clip.FINGER_NAMES
PARTS = idle_clip.PARTS
## The overlap pass's parts in a clip that plays once: the trunk and the head alone. Its arms trail in the
## description instead (`_arm_shares`): the spring's lag adds up along the arm (six frames at the hand in a style
## of two a part), so a 12-frame take-off ended with the hand still on its way, and joining the next clip's first
## pose crushed the rest of the swing into the last three frames (an arm at 500 to 1200 degrees a second).
TRUNK_PARTS = {bone: part for bone, part in PARTS.items() if part in ("chest", "head")}
## Which part of the arm each of its numbers turns: 0 the upper arm (and the collarbone), 1 the forearm, 2 the hand
## (and the fingers). Each part starts and ends its way `arms_lag` frames after the part it hangs from.
ARM_LATE = {"swing": 0, "out": 0, "twist": 0, "clear": 0, "carry": 0, "bend": 1, "pronate": 1, "wrist": 2}
ARM_KEYS = ("swing", "out", "twist", "bend", "pronate", "wrist", "clear", "carry")
## Degrees of forward swing between which an arm's elbow goes from pointing forward to turning with the swing
## (the solver's `raise`): an arm over level needs the second, a hanging one the first.
RAISE = (55.0, 80.0)

## A pose of the body in the air: every number a side could own is `[left, right]`.
POSE = {
    "pelvis": [0.0, 0.0, 0.0],  # the pelvis's turn: pitch forward, yaw to the left, lean to the left (degrees)
    "chest": [0.0, 0.0, 0.0],  # the chest's
    "head": [0.0, 0.0, 0.0],  # the head's
    "thigh": [0.0, 0.0],  # degrees each thigh is forward of straight down
    "spread": [4.0, 4.0],  # degrees each thigh is out from the body
    "knee": [10.0, 10.0],  # degrees each knee is bent
    "knee_out": [4.0, 4.0],  # degrees each knee points outward
    "point": [20.0, 20.0],  # degrees each foot's toes are pointed down from square to its shin
    "toe_out": [6.0, 6.0],  # degrees each foot is turned outward
    "toes": [0.0, 0.0],  # degrees each foot's toes bend up
    "arm_swing": [20.0, 20.0],  # degrees each upper arm is forward of straight down (over 90 is over level)
    "arm_out": [15.0, 15.0],  # degrees each is out from the body
    "arm_twist": [0.0, 0.0],  # degrees each bent forearm is turned in toward the body's middle
    "elbow": [40.0, 40.0],  # degrees each elbow is bent
    "pronate": [20.0, 20.0],  # degrees each forearm turns its thumb inward
    "wrist": [0.0, 0.0],  # degrees each wrist bends toward the palm
    "shrug": [0.0, 0.0],  # degrees each collarbone is lifted
    "reach": [0.0, 0.0],  # degrees each collarbone is brought forward
    "curl": [[20.0, 34.0, 40.0, 46.0, 52.0], [30.0, 58.0, 66.0, 72.0, 78.0]],  # each hand's fingers, thumb first
    "thumb_out": [38.0, 38.0],  # degrees each thumb is lifted from under the palm
}
## What the feet of a pose that reaches for the floor add (`jump_fall`): they are placed, and the knees are what
## the weight's height leaves.
FEET = {
    "ahead": [0.0, 0.14],  # metres each foot is ahead of where the standing idle has it
    "wide": [0.0, 0.02],  # metres each is wider than it
    "lift": [0.0, 0.055],  # metres the ball of each is over the floor the capsule's bottom is on
    "heel": [14.0, 24.0],  # degrees each heel is up over its toes
    "toe_out": [9.0, 16.0],  # degrees each foot is turned outward
    "knee_out": [4.0, 10.0],  # degrees each knee points outward of its foot
}
RISE = {
    **POSE,
    "frames": 36,  # the loop's length
    "live": 1.0,  # how much the limbs drift through the loop (1: a few degrees)
    "from": 21.0,  # the frame of that drift the loop begins on: one where the limbs turn least sharply
    "pelvis": [-3.0, 4.0, -2.0],
    "chest": [-4.0, -5.0, 2.0],
    "head": [-6.0, -2.0, 0.0],
    "thigh": [-6.0, 24.0],
    "spread": [5.0, 7.0],
    "knee": [14.0, 46.0],
    "knee_out": [4.0, 8.0],
    "point": [38.0, 26.0],
    "toe_out": [6.0, 12.0],
    # The arms of the three poses of the air lie within about 10 degrees of each other: the game blends between
    # them in 0.15 s, and an arm that swings 80 degrees in that blend snaps (gdstudio #1369's review).
    "arm_swing": [48.0, 26.0],
    "arm_out": [26.0, 38.0],
    "arm_twist": [10.0, 0.0],
    "elbow": [52.0, 58.0],
    "pronate": [20.0, 24.0],
    "wrist": [5.0, 10.0],
    "shrug": [4.0, 3.0],
    "reach": [4.0, 2.0],
}
APEX = {
    **POSE,
    "frames": 36,
    "live": 1.0,
    "from": 21.0,
    "pelvis": [6.0, 5.0, -3.0],
    "chest": [10.0, -6.0, 3.0],
    "head": [6.0, -3.0, 0.0],
    "thigh": [30.0, 58.0],
    "spread": [8.0, 10.0],
    "knee": [70.0, 96.0],
    "knee_out": [6.0, 10.0],
    "point": [18.0, 12.0],
    "toe_out": [8.0, 14.0],
    "arm_swing": [52.0, 24.0],
    "arm_out": [32.0, 44.0],
    "elbow": [54.0, 60.0],
    "pronate": [24.0, 28.0],
    "wrist": [0.0, 8.0],
    "shrug": [3.0, 2.5],
}
FALL = {
    **{key: value for key, value in POSE.items() if key not in ("thigh", "spread", "knee", "point")},
    **FEET,
    "frames": 36,
    "live": 1.0,
    "from": 21.0,
    "pelvis": [8.0, 3.0, -2.0],
    "chest": [14.0, -4.0, 2.0],
    "head": [4.0, -2.0, 0.0],
    "arm_swing": [44.0, 18.0],
    "arm_out": [36.0, 48.0],
    "elbow": [56.0, 60.0],
    "pronate": [26.0, 32.0],
    "wrist": [-5.0, 5.0],
    "shrug": [1.0, 1.5],
}
## `jump_start`: the standing take-off. It lasts the controller's whole rise (`RISE_FRAMES`): the legs and the trunk
## push in its first `frames` and then drift with the rise's pose, while the arms float up over all of it. A
## window is the shares of the push a part starts and stops moving at.
START = {
    "frames": 6,  # the push: the frames the legs and the trunk take from the idle to the rise's pose
    # The stretch the take-off passes through, as a pose of the air: what `PUSH` gives, with a style's own over it.
    # It sets no arm: the arms swing once, from the idle to the rise's pose, and do not stop at the stretch.
    "push": {},
    "legs_out": [0.0, 0.42],  # the legs' way to the stretch
    "legs_in": [0.5, 1.0],  # and from it to the rise's pose
    "trunk_out": [0.0, 0.5],  # the pelvis, the chest and the head
    "trunk_in": [0.5, 1.0],
    # The frames the arms start and finish their swing up at: a frame behind the legs, which they hang from, and
    # on to the top of the rise, eased in and out with no jump in their acceleration (`maths.smoother`). The
    # window is the upper arm's: the forearm follows it `arms_lag` frames later and the hand as much again.
    "arms": [0.25, 10.75],
    "arms_lag": 0.6,  # frames each part of the arm starts and ends after the part it hangs from
    # Frames over which the joined clips' overlap is let go at each end. The idle's arms keep clear of the
    # thighs (`clear`), the take-off's leave that to their own numbers: the few degrees between are let go over
    # six frames, not three.
    "meet": 6,
    "speed_limit": 60.0,  # the largest change of a joint's speed in one frame (degrees a frame)
}
PUSH = {
    **POSE,
    "pelvis": [-4.0, 2.0, -1.0],
    "chest": [-7.0, -3.0, 1.0],
    "head": [-8.0, -1.0, 0.0],
    "thigh": [-8.0, 2.0],
    "spread": [3.0, 4.0],
    "knee": [5.0, 12.0],
    "point": [50.0, 44.0],
    "toe_out": [7.0, 10.0],
    "toes": [-6.0, -4.0],
}
## `jump_start_run`: the two running take-offs, from the jog's left foot strike and from its right.
START_RUN = {
    "frames": 6,  # the push, as the standing take-off's; the clip lasts the whole rise
    "legs": [0.0, 1.0],  # the legs' way from the stride to the rise's pose, as shares of the push
    "trunk": [0.0, 0.8],
    # The frames the arms float up between: from the first, since the jog's arms are already on their way.
    "arms": [0.0, 11.0],
    "arms_lag": 0.5,
    "drive": [0.05, 0.03],  # metres the leading knee's foot is drawn up more in the middle (struck left, right)
    "trail": [0.06, 0.03],  # metres the pushing foot goes down and back more in the middle
    "pump": [4.0, 3.0],  # degrees the arm opposite the leading knee swings up more in the middle of its way
    # The jog's arms carry its overlap pass and ours do not: the difference at the first frame is let go over
    # all of the clip, or it is crushed into three frames (an arm at 480 degrees a second); at the last, over six.
    "meet": [12, 6],
    "speed_limit": 70.0,
}
## `land_soft` and `land_hard`. Frames are whole; a pair is `[left, right]`.
LAND = {
    "frames": 22,  # the clip's length
    "control": 9,  # the frame the game may take the body back at (`land_time`); what follows is the settle
    "keep": 4.0,  # m/s of the fall's speed the body still has on the first frame (the capsule takes the rest)
    "dip": 0.2,  # metres the centre of mass goes down
    "bottom": 3,  # the frame it is lowest at
    "hold": 0,  # frames it stays there
    "up": 12,  # frames the rise back takes
    "push": 0.35,  # the share of the rise at which it is fastest (under a half: a push, then a coast)
    "right_lands": 2,  # the frame the right foot lands on, a step ahead of where the idle has it
    "stagger": 0.17,  # metres that step is
    "wide": 0.02,  # metres wider
    "toe_out": 16.0,  # degrees the right foot is turned out as it lands
    "heel_down": [2, 2],  # frames each heel takes to come down
    "step": [11, 17],  # the frames the right foot leaves and lands at as it is drawn back beside the left
    "step_clear": 0.035,  # metres its ball clears the floor by
    "toe_off": 18.0,  # degrees its heel is up as it leaves
    "share": [0.58, 0.86],  # the share of the weight on the left foot at the bottom, and as the right foot steps
    "ahead": 0.42,  # where the weight is between the heels and the toes at the bottom
    "knee_out": [5.0, 20.0],  # degrees each knee points outward of its foot at the bottom
    # The body at the bottom: the trunk's fold, and each arm.
    "pelvis": [16.0, 8.0, -6.0],
    "chest": [30.0, -7.0, 5.0],
    "head": [10.0, -3.0, 0.0],
    # The arms come down from the fall's pose by no more than about 30 degrees and reach theirs late: the weight
    # is caught by the legs, and the arms follow it down after it, eased, and float back up.
    "arm_swing": [20.0, 10.0],
    "arm_out": [28.0, 36.0],
    "arm_twist": [0.0, 0.0],
    "elbow": [36.0, 52.0],
    "pronate": [26.0, 34.0],
    "wrist": [4.0, 8.0],
    "shrug": [3.0, 2.0],
    "reach": [0.0, 0.0],
    "curl": [[24.0, 40.0, 48.0, 54.0, 60.0], [30.0, 58.0, 66.0, 72.0, 78.0]],
    "thumb_out": [38.0, 38.0],
    "trunk_down": [0.0, 1.0],  # the trunk's fold, as shares of the way to the bottom (it may go on past it)
    "trunk_late": 1.0,  # frames the trunk reaches its fold after the weight is lowest
    "arms_from": 1.0,  # the frame the arms start down at: they keep the fall's pose a moment after the foot lands
    "arms_late": 6.0,  # frames the arms reach theirs after the weight is lowest (smoothly, `maths.smoother`)
    "trunk_up": [0.1, 0.9],  # the trunk's way back, as shares of the frames from the bottom to the end
    "head_up": [0.0, 0.6],
    "arms_up": [0.4, 1.0],  # the arms' way back up, as the trunk's: they start once they are down
    "arms_lag": 1.0,  # frames each part of the arm starts and ends after the part it hangs from
    "meet": 6,  # the idle's arms keep clear of the thighs and the landing's do not: see `START`
    "speed_limit": 60.0,
}
HARD = {
    **LAND,
    "frames": 38,
    "control": 20,
    "keep": 5.2,
    "dip": 0.36,
    "bottom": 5,
    "hold": 3,
    "up": 15,
    "push": 0.4,
    "right_lands": 2,
    "stagger": 0.22,
    "wide": 0.05,
    "toe_out": 20.0,
    "heel_down": [2, 3],
    "step": [14, 21],  # while the legs are still bent: a straight leg does not reach a foot this far ahead
    "share": [0.48, 0.86],
    "knee_out": [12.0, 20.0],
    "pelvis": [24.0, 5.0, -4.0],
    "chest": [52.0, -7.0, 4.0],
    "head": [18.0, -3.0, 0.0],
    # The right arm is held out past its knee: at 22 degrees out its hand went 37 to 62 mm into the thigh under it.
    "arm_swing": [16.0, 24.0],
    "arm_out": [34.0, 50.0],
    "elbow": [40.0, 46.0],
    "arms_up": [0.5, 1.0],  # the arms come back once the thighs are down
    "trunk_late": 2.0,
    "arms_late": 8.0,
    "speed_limit": 70.0,
}
## `land_to_jog`: a landing on the left foot that ends on the jog's right foot strike.
TO_JOG = {
    "contact": 4,  # frames the left foot is on the floor: the jog's own contact, joined two frames in
    "keep": 3.0,  # m/s of the fall's speed the body still has on the first frame
    "sink": 0.03,  # metres more the centre of mass goes down than the curve between its two ends does
    "heel": [1.5, 3.0],  # the left heel: the frame it is lowest at, and degrees up it still is there
    "toe_off": 58.0,  # degrees it is up as the toes leave
    "fold": 8.0,  # degrees more the chest folds as the leg takes the weight
    "upper": [0.0, 0.75],  # the trunk's way to the jog's, as shares of the clip
    "arms": [0.0, 1.0],  # the arms', eased with no jump in their acceleration: they float into the jog's swing
    "arms_lag": 0.0,  # frames each part of the arm starts and ends after the part it hangs from (none: 7 frames)
    # The gait whose arm speeds bound this clip's (`Air.arm_bounds`): its arms end in the jog's own swing seven
    # frames after the foot lands, a stride's work in a third of a second, and swing as a runner's do.
    "arms_like": "Sprint",
    "right": [0.0, 0.7],  # the right foot's way from the fall's pose to the jog's swing
    "meet": 7,  # as the running take-offs': at most the clip's length
    "speed_limit": 75.0,
}


def arc(frames: int) -> list:
    """The root's height over the floor on each frame of the controller's jump, from the tick it leaves."""
    gravity = 2.0 * JUMP_HEIGHT / (RISE_TIME * RISE_TIME)
    speed = 2.0 * JUMP_HEIGHT / RISE_TIME
    out = []
    for f in range(frames + 1):
        t = f / FPS
        if t <= RISE_TIME:
            out.append(speed * t - 0.5 * gravity * t * t)
        else:
            out.append(max(JUMP_HEIGHT - 0.5 * gravity * FALL_SCALE * (t - RISE_TIME) ** 2, 0.0))
    return out


def fall_speed() -> float:
    """The speed (m/s) the controller's own jump lands at on level ground."""
    return math.sqrt(2.0 * JUMP_HEIGHT * FALL_SCALE * 2.0 * JUMP_HEIGHT / (RISE_TIME * RISE_TIME))


# ---- poses ------------------------------------------------------------------------------------------------------


def plain_arm(arm: dict) -> dict:
    """A hanging arm's numbers alone, every one present, so two of them mix."""
    out = {key: float(arm.get(key, 0.0)) for key in ARM_KEYS}
    out["carry"] = float(arm.get("carry", 0.3))
    return out


def upper_of(p: dict, carry: float = 1.0) -> dict:
    """The trunk, the head, the arms and the hands of a pose's numbers, as the solver's spec has them (the
    pelvis's turn under `turn`)."""
    arms, fingers, clavicle = {}, {}, {}
    for s, _ in SIDES:
        i = AT[s]
        arms[s] = {
            "swing": p["arm_swing"][i],
            "out": p["arm_out"][i],
            "twist": p["arm_twist"][i],
            "bend": p["elbow"][i],
            "pronate": p["pronate"][i],
            "wrist": p["wrist"][i],
            "clear": 0.0,
            "carry": carry,
        }
        fingers[s] = {**dict(zip(FINGER_NAMES, p["curl"][i], strict=True)), "thumb_out": p["thumb_out"][i]}
        clavicle[s] = (p["shrug"][i], p["reach"][i])
    return {
        "turn": tuple(p["pelvis"]),
        "chest": tuple(p["chest"]),
        "ribs": 0.0,
        "head": tuple(p["head"]),
        "clavicle": clavicle,
        "arm": arms,
        "fingers": fingers,
    }


def upper_from(spec: dict) -> dict:
    """The same of a solver's spec (another clip's frame)."""
    return {
        "turn": tuple(spec["pelvis"].get("turn", (0.0, 0.0, 0.0))),
        "chest": tuple(spec.get("chest", (0.0, 0.0, 0.0))),
        "ribs": float(spec.get("ribs", 0.0)),
        "head": tuple(spec.get("head", (0.0, 0.0, 0.0))),
        "clavicle": {s: tuple(spec.get("clavicle", {}).get(s, (0.0, 0.0))) for s, _ in SIDES},
        "arm": {s: plain_arm(spec.get("arm", {}).get(s, {})) for s, _ in SIDES},
        "fingers": {s: dict(spec.get("fingers", {}).get(s, {})) for s, _ in SIDES},
    }


def knee_way(foot: tuple, sign: float, out: float = 0.0) -> np.ndarray:
    """The way a knee points: the way its foot does, turned `out` degrees outward."""
    ahead = body_turn(*foot) @ maths.Z
    yaw = math.degrees(math.atan2(ahead[0], ahead[2])) + sign * out
    return np.array([math.sin(math.radians(yaw)), 0.0, math.cos(math.radians(yaw))])


def legs_from(spec: dict) -> dict:
    """A spec's legs against its pelvis: the ankles as offsets from the pelvis's place, the knees' ways filled
    in, so the legs of two poses mix and ride with the pelvis."""
    place = np.asarray(spec["pelvis"]["place"], dtype=float)
    out = {}
    for s, sign in SIDES:
        leg = spec["leg"][s]
        foot = tuple(leg.get("foot", (0.0, 0.0, 0.0)))
        out[s] = {
            "ankle": np.asarray(leg["ankle"], dtype=float) - place,
            "foot": foot,
            "toe": float(leg.get("toe", 0.0)),
            "knee": np.asarray(leg.get("knee", knee_way(foot, sign)), dtype=float),
        }
    return out


def legs_of(rig, p: dict) -> dict:
    """The legs of a pose's numbers against the pelvis: each thigh's and knee's angles made an ankle's place."""
    turn = body_turn(*p["pelvis"])
    out = {}
    for s, sign in SIDES:
        i = AT[s]
        a, o, b, k = (math.radians(p[key][i]) for key in ("thigh", "spread", "knee", "knee_out"))
        fore = np.array([sign * math.sin(k), 0.0, math.cos(k)])
        aside = np.array([sign * math.cos(k), 0.0, -math.sin(k)])
        thigh = math.cos(o) * (-Y * math.cos(a) + fore * math.sin(a)) + math.sin(o) * aside
        back = -Y * math.sin(a) - fore * math.cos(a)
        calf = maths.unit(math.cos(b) * thigh + math.sin(b) * back)
        hip = turn @ (rig.rest_pos["thigh_" + s] - rig.rest_pos["pelvis"])
        out[s] = {
            "ankle": hip + rig.length["thigh_" + s] * thigh + rig.length["calf_" + s] * calf,
            "foot": (p["knee"][i] - p["thigh"][i] + p["point"][i], sign * p["toe_out"][i], 0.0),
            "toe": p["toes"][i],
            "knee": -back,
        }
    return out


def to_spec(upper: dict, legs: dict, place, against: bool) -> dict:
    """The solver's spec of an upper body and legs with the pelvis at `place`; `against`: the ankles are offsets
    from it."""
    place = np.asarray(place, dtype=float)
    arms = {}
    for s, _ in SIDES:
        arm = dict(upper["arm"][s])
        arm["raise"] = maths.smooth((arm["swing"] - RAISE[0]) / (RAISE[1] - RAISE[0]))
        arms[s] = arm
    return {
        "pelvis": {"place": place.copy(), "turn": tuple(upper["turn"])},
        "chest": tuple(upper["chest"]),
        "ribs": upper["ribs"],
        "head": tuple(upper["head"]),
        "clavicle": {s: tuple(upper["clavicle"][s]) for s, _ in SIDES},
        "arm": arms,
        "fingers": {s: dict(upper["fingers"][s]) for s, _ in SIDES},
        "leg": {
            s: {
                "ankle": np.asarray(legs[s]["ankle"], dtype=float) + (place if against else 0.0),
                "foot": tuple(legs[s]["foot"]),
                "toe": legs[s]["toe"],
                "knee": maths.unit(np.asarray(legs[s]["knee"], dtype=float)),
            }
            for s, _ in SIDES
        },
    }


def carried_spec(solver, upper: dict, legs: dict, centre) -> dict:
    """The spec of a body in the air whose centre of mass is at `centre`: the legs ride with the pelvis, so the
    whole body is moved until it is."""
    centre = np.asarray(centre, dtype=float)
    place = centre - Y * 0.11
    for _ in range(2):
        spec = to_spec(upper, legs, place, True)
        place = place + centre - weight.centre_of_mass(solver.rig, solver.solve(spec))
    return to_spec(upper, legs, place, True)


def standing_spec(solver, spec: dict, centre, most: float = 0.994) -> dict:
    """Solve a spec whose feet are placed until its centre of mass is at `centre`, or as high under it as the
    straighter leg allows (`most` of its length): a trunk still folded carries its weight low, and legs asked to
    hold that weight at standing height would be asked past their length."""
    centre = np.array(centre, dtype=float)
    for _ in range(4):
        pose = weight.settle(solver, spec, tuple(centre), rounds=8)
        over = weight._stretch_miss(solver.rig, spec, pose, most)
        if over > -1e-4:
            break
        centre[1] += over
    return spec


def alive(p: dict, f: float, frames: int, live: float) -> dict:
    """A pose's numbers with the drift of a body that hangs in the air: each limb on a period of its own that
    divides the loop, no two alike."""
    out = {key: (list(value) if isinstance(value, list) else value) for key, value in p.items()}

    def add(key: str, i: int, size: float, period: float, phase: float) -> None:
        out[key][i] = out[key][i] + live * size * maths.wave(f, frames / period, phase)

    add("arm_swing", 0, 3.0, 1, 0.08)
    add("arm_swing", 1, 2.2, 1, 0.47)
    add("arm_out", 0, 2.0, 1, 0.31)
    add("arm_out", 1, 2.8, 1, 0.74)
    add("elbow", 0, 4.0, 1, 0.21)
    add("elbow", 1, 3.0, 2, 0.6)
    add("wrist", 0, 3.0, 2, 0.4)
    add("wrist", 1, 2.0, 1, 0.9)
    add("chest", 0, 0.8, 1, 0.15)
    add("chest", 1, 1.0, 1, 0.55)
    add("head", 1, 1.2, 1, 0.35)
    for key, sizes in (("thigh", (1.6, 2.2)), ("knee", (2.6, 3.4)), ("point", (2.0, 3.0))):
        if key in out:
            add(key, 0, sizes[0], 1, 0.62)
            add(key, 1, sizes[1], 1, 0.18)
    out["curl"] = [
        [
            curl + live * 2.5 * maths.wave(f, frames, 0.13 * k + 0.4 * i) * (0.5 if k == 0 else 1.0)
            for k, curl in enumerate(hand)
        ]
        for i, hand in enumerate(p["curl"])
    ]
    return out


class Air:
    """What every clip of the jump shares: the rig, the solver, the idle it leaves and returns to, and where the
    centre of mass is against the root while the controller carries the body."""

    def __init__(self, rig, joined):
        assert joined is not None, "a jump's clips need the clips they join (`clips.joined.Joined`)"
        self.rig, self.joined, self.solver = rig, joined, joined.solver
        self.idle = joined.start("Idle")
        spec = self.idle["spec"]
        self.idle_upper = upper_from(spec)
        self.idle_legs = legs_from(spec)
        self.idle_place = np.asarray(spec["pelvis"]["place"], dtype=float)
        ## The centre of mass of the standing idle's first pose: where it stays against the root in the air.
        stood = self.solver.solve(to_spec(self.idle_upper, self.idle_legs, self.idle_place, True))
        self.home = weight.centre_of_mass(rig, stood)
        self.feet = {fall.side: fall for fall in joined.clip("Idle").plan.footfalls}
        self._open = None

    def open_idle_upper(self) -> dict:
        """The idle's upper body with arms that ride the chest and no longer look for the thigh (`carry` 1,
        `clear` 0), each opened from the body by what the thigh search gave the idle's own arm (`out`): the pose a
        take-off leaves and a landing comes back to, with no search left in it. A search kept in a moving clip
        jolts the arm wherever the thigh crosses its limit (150 to 220 thousand degrees a second cubed); left out
        with the idle's `out` as written, the hand went 8 to 34 mm into the thigh as the landing stood up."""
        if self._open is None:
            spec = copy.deepcopy(self.idle["spec"])
            want = self.solver.solve(spec)["local"]
            upper = upper_from(spec)
            for s, _ in SIDES:
                arm = {**upper["arm"][s], "carry": 1.0, "clear": 0.0}
                bone = f"upperarm_{s}"

                def off(out: float) -> float:
                    trial = copy.deepcopy(spec)
                    trial["arm"][s] = {**trial["arm"][s], **arm, "out": out}
                    return maths.angle_between(self.solver.solve(trial)["local"][bone], want[bone])

                tries = [arm["out"] + 0.5 * k for k in range(101)]
                arm["out"] = min(tries, key=off)
                upper["arm"][s] = arm
            self._open = upper
        return self._open

    def arm_bounds(self, like: str = "Jog") -> dict:
        """What every arm joint of the jump is held under (`checks.check_arms`), read off the shipped gaits: each
        joint no faster than the same joint of the gait `like` at its fastest (the jog's: an arm in the air
        floats, it does not swing like a running arm), and none with a sharper change of acceleration than the
        sharpest arm joint of the walk, the jog and the sprint. That one is the whole arm's: a collarbone that
        turns 4 degrees in a quarter of a second already changes its acceleration more sharply than the gaits'
        collarbones, which hardly move, and no eye sees it."""
        gaits = {name: self.joined.built(name) for name in ("Walk", "Jog", "Sprint")}
        numbers = {name: checks.arm_numbers(b.played(self.rig)[0], self.rig, True) for name, b in gaits.items()}
        sharpest = max(jerk for one in numbers.values() for _, jerk in one.values())
        return {part: [numbers[like][part][0], sharpest] for part in checks.ARM_PARTS}

    def numbers(self, kind: str) -> dict:
        """The picked variant's numbers of an air pose (`Jump_Rise`, `Jump_Fall`)."""
        defaults = {"Jump_Rise": RISE, "Jump_Apex": APEX, "Jump_Fall": FALL}[kind]
        return self.joined.style(kind).numbers(kind.lower(), defaults)

    def posed(self, n: dict, f: float) -> dict:
        """The spec of a pose of the air given as angles (`RISE`, `APEX`, a take-off's stretch) at a frame."""
        p = alive(n, f + n.get("from", 0.0), int(n.get("frames", 36)), n.get("live", 0.0))
        return carried_spec(self.solver, upper_of(p), legs_of(self.rig, p), self.home)

    def fall_feet(self, n: dict) -> dict:
        """Where each foot of the fall's pose is: its ball's place, its heel and its turn."""
        out = {}
        for s, sign in SIDES:
            i = AT[s]
            x, z = self.feet[s].place
            ball = np.array([x + sign * n["wide"][i], self.rig.sole[s]["floor"] + n["lift"][i], z + n["ahead"][i]])
            out[s] = {"ball": ball, "heel": n["heel"][i], "yaw": sign * n["toe_out"][i], "knee_out": n["knee_out"][i]}
        return out

    def fall_legs(self, n: dict) -> dict:
        plan = ContactPlan(1, [], loop=False)
        legs = {}
        for s, sign in SIDES:
            foot = self.fall_feet(n)[s]
            legs[s] = plan.state(self.rig, s, "ball", foot["ball"], foot["heel"], foot["yaw"])
            legs[s]["knee"] = knee_way(legs[s]["foot"], sign, foot["knee_out"])
        return legs

    def falling(self, n: dict, f: float) -> dict:
        """The spec of the fall's pose at a frame: the feet where the floor will be, the centre of mass at home,
        the knees what that leaves."""
        p = alive(n, f + n["from"], int(n["frames"]), n["live"])
        spec = to_spec(upper_of(p), self.fall_legs(n), self.home - Y * 0.12, False)
        weight.settle(self.solver, spec, tuple(self.home), rounds=8)
        return spec


def _loop(rig, style, name: str, joined, kind: str, replaces: str, risen: float) -> Clip:
    air = Air(rig, joined)
    section = kind.lower()
    n = style.numbers(section, {"Jump_Rise": RISE, "Jump_Apex": APEX, "Jump_Fall": FALL}[kind])
    frames = int(n["frames"])
    made = {}

    def spec(f: int) -> dict:
        if f not in made:
            made[f] = air.falling(n, float(f)) if kind == "Jump_Fall" else air.posed(n, float(f))
        return mix(made[f], made[f], 0.0)

    return Clip(
        name=name,
        frames=frames,
        plan=ContactPlan(frames, [], loop=True),
        spec=spec,
        chains=overlap.chains_from(style.overlap(section), PARTS),
        kind="stand",
        # A short loop in which every limb drifts has few keys a reducer can drop.
        declared={
            "carried": [risen] * (frames + 1),
            "record": {"carried": True},
            "kb_a_second": 20.0,
            "arm_bounds": air.arm_bounds(),
        },
        replaces=replaces,
        style=style.letter,
    )


def describe_rise(rig, style, name: str = "Jump_Rise", joined=None) -> Clip:
    return _loop(rig, style, name, joined, "Jump_Rise", "", 0.5)


def describe_apex(rig, style, name: str = "Jump_Apex", joined=None) -> Clip:
    return _loop(rig, style, name, joined, "Jump_Apex", "", JUMP_HEIGHT)


def describe_fall(rig, style, name: str = "Jump_Fall", joined=None) -> Clip:
    # Nothing of the fall's pose is under the capsule's bottom: it is the pose a landing begins on.
    return _loop(rig, style, name, joined, "Jump_Fall", "ual1/Jump", 0.0)


# ---- take-offs --------------------------------------------------------------------------------------------------


def _blend(a: dict, b: dict, legs: float, trunk: float, arms) -> dict:
    """Two bodies (`{"upper", "legs"}`) mixed part by part. `arms` is one share for the whole arm, or three
    (`_arm_shares`): the upper arm's and the collarbone's, the forearm's, the hand's and the fingers'."""
    ua, ub = a["upper"], b["upper"]
    upper, fore, hand = arms if isinstance(arms, tuple) else (arms, arms, arms)
    by_part = (upper, fore, hand)
    arm = {
        s: {key: mix(value, ub["arm"][s][key], by_part[ARM_LATE.get(key, 0)]) if key in ub["arm"][s] else value
            for key, value in ua["arm"][s].items()}
        for s in ua["arm"]
    }  # fmt: skip
    return {
        "upper": {
            "turn": mix(ua["turn"], ub["turn"], trunk),
            "chest": mix(ua["chest"], ub["chest"], trunk),
            "ribs": mix(ua["ribs"], ub["ribs"], trunk),
            "head": mix(ua["head"], ub["head"], trunk),
            "clavicle": mix(ua["clavicle"], ub["clavicle"], upper),
            "arm": arm,
            "fingers": mix(ua["fingers"], ub["fingers"], hand),
        },
        "legs": mix(a["legs"], b["legs"], legs),
    }


def _body(spec: dict) -> dict:
    return {"upper": upper_from(spec), "legs": legs_from(spec)}


def _take_off(air: Air, style, name: str, section: str, n: dict, first: str, at: int, body_at, speed: float) -> Clip:
    """A take-off from the pose of `first` at its frame `at` to the rise's first pose; `body_at(f)` is the body
    on each frame, and the centre of mass goes from the one pose's to the rise's at one speed."""
    rig, joined = air.rig, air.joined
    frames = RISE_FRAMES
    assert int(n["frames"]) < frames, f"{name}: a push of {n['frames']} frames does not fit the rise's {frames}"
    built_a, built_b = joined.built(first), joined.built("Jump_Rise")
    meet = n["meet"] if isinstance(n["meet"], list) else [n["meet"], n["meet"]]
    start = weight.centre_of_mass(rig, built_a.frames[at])
    made = {}

    def spec(f: int) -> dict:
        if f not in made:
            body = body_at(f)
            for s, _ in SIDES:
                # A leg that is asked past its length is asked for its length.
                hip = body_turn(*body["upper"]["turn"]) @ (rig.rest_pos["thigh_" + s] - rig.rest_pos["pelvis"])
                to = body["legs"][s]["ankle"] - hip
                most = 0.992 * (rig.length["thigh_" + s] + rig.length["calf_" + s])
                if np.linalg.norm(to) > most:
                    body["legs"][s]["ankle"] = hip + to * most / np.linalg.norm(to)
            centre = start + (air.home - start) * (f / frames)
            # The spec is in the world, which the root travels over.
            centre = centre + maths.Z * speed * f / FPS
            made[f] = carried_spec(air.solver, body["upper"], body["legs"], centre)
        return mix(made[f], made[f], 0.0)

    declared = {
        "joins": {
            "first": (built_a.rotation[at], built_a.translation[at]),
            "last": (built_b.rotation[0], built_b.translation[0]),
            "first_speed": speed,
        },
        "distance": speed * frames / FPS,
        "turn": 0.0,
        "join_names": {"first": first, "last": "Jump_Rise"},
        "carried": arc(frames),
        "record": {
            "carried": True,
            "join_frames": {"first": at, "last": 0},
            "made_for": {"jump_height": JUMP_HEIGHT, "jump_rise_time": RISE_TIME, "fall_gravity_scale": FALL_SCALE},
        },
        "speed_limit": n["speed_limit"],
        "keys_kept": 0.95,
        "kb_a_second": 60.0,
        "arm_bounds": air.arm_bounds(),
    }
    return Clip(
        name=name,
        frames=frames,
        plan=ContactPlan(frames, [], Travel.steady(speed), loop=False),
        spec=spec,
        loop=False,
        meet={"first": (built_a.frames[at], meet[0]), "last": (built_b.frames[0], meet[1])},
        chains=overlap.chains_from(style.overlap(section), TRUNK_PARTS),
        kind="transition",
        declared=declared,
        replaces="ual1/Jump_Start" if first == "Idle" else "",
        style=style.letter,
    )


def _rising(air: Air) -> callable:
    """The rise's pose on each frame of a take-off: the rise's own loop, run so that the take-off's last frame
    is its first. A take-off's legs and trunk drift with it once they have pushed, and its arms float to it."""
    n = air.numbers("Jump_Rise")
    made = {}

    def at(f: int) -> dict:
        if f not in made:
            made[f] = _body(air.posed(n, float(f - RISE_FRAMES)))
        return made[f]

    return at


def _carried_arms(upper: dict) -> dict:
    """An upper body whose arms ride with the chest (`carry` 1, as the poses of the air carry them) and no longer
    look for the thigh (`clear` 0). An idle arm keeps its hand a few centimetres from the thigh's line by moving
    out, and the take-off's push moves the thighs from its first frame: the upper arm jolted there, before it
    had begun to swing, at 150 to 220 thousand degrees a second cubed."""
    return {**upper, "arm": {s: {**arm, "carry": 1.0, "clear": 0.0} for s, arm in upper["arm"].items()}}


def _arm_shares(f: float, span: list, lag: float) -> tuple:
    """How far each part of an arm is on its way at a frame: the upper arm from the first frame of `span` to its
    last, eased in and out with no jump in its acceleration (`maths.smoother`), the forearm `lag` frames after
    it and the hand `lag` after that: the overlap, as each part starts after the part it hangs from."""
    return tuple(maths.smoother((f - k * lag - span[0]) / max(span[1] - span[0], 1e-6)) for k in range(3))


def _arms_fit(name: str, span: list, lag: float, frames: int) -> None:
    assert span[1] + 2 * lag <= frames + 1e-9, (
        f"{name}: the upper arm ends its way on frame {span[1]} and the hand {2 * lag} frames later, after the "
        f"clip's {frames}"
    )


## The numbers of a pose that belong to its arms: a take-off's stretch sets none of them.
ARM_POSE = ("arm_swing", "arm_out", "arm_twist", "elbow", "pronate", "wrist", "shrug", "reach", "curl", "thumb_out")


def describe_start(rig, style, name: str = "Jump_Start", joined=None) -> Clip:
    air = Air(rig, joined)
    n = style.numbers("jump_start", START)
    unknown = sorted(set(n["push"]) - set(POSE))
    assert not unknown, f"{style.path.name}: `jump_start.push` sets {unknown}, which a pose does not have"
    arms = sorted(set(n["push"]) & set(ARM_POSE))
    assert not arms, f"{style.path.name}: `jump_start.push` sets {arms}: the arms swing once, from the idle to the rise"
    push_frames = int(n["frames"])
    stand = {"upper": air.open_idle_upper(), "legs": air.idle_legs}
    push = _body(air.posed({**PUSH, **n["push"]}, 0.0))
    rise = _rising(air)

    _arms_fit(name, n["arms"], n["arms_lag"], RISE_FRAMES)

    def body_at(f: int) -> dict:
        u = f / push_frames
        out = _blend(stand, push, window(u, n["legs_out"]), window(u, n["trunk_out"]), 0.0)
        out = _blend(out, rise(f), window(u, n["legs_in"]), window(u, n["trunk_in"]), 0.0)
        return _blend(out, rise(f), 0.0, 0.0, _arm_shares(f, n["arms"], n["arms_lag"]))

    return _take_off(air, style, name, "jump_start", n, "Idle", 0, body_at, 0.0)


def _start_run(rig, style, name: str, joined, struck: str) -> Clip:
    air = Air(rig, joined)
    n = style.numbers("jump_start_run", START_RUN)
    push_frames = int(n["frames"])
    jog = joined.clip("Jog")
    at = 0 if struck == "l" else jog.frames // 2
    speed = joined.built("Jog").record["speed"]
    stride = _body(_frame_of(air, "Jog", at))
    stride["upper"] = _carried_arms(stride["upper"])
    rise = _rising(air)
    i = AT[struck]
    # The rise's pose leads with the right knee and trails the left leg, whichever foot struck.
    lead, trail = "r", "l"

    _arms_fit(name, n["arms"], n["arms_lag"], RISE_FRAMES)

    def body_at(f: int) -> dict:
        u = min(f / push_frames, 1.0)
        arms = _arm_shares(f, n["arms"], n["arms_lag"])
        out = _blend(stride, rise(f), window(u, n["legs"]), window(u, n["trunk"]), arms)
        middle = math.sin(math.pi * u) ** 2
        out["legs"][lead]["ankle"] = out["legs"][lead]["ankle"] + Y * n["drive"][i] * middle
        out["legs"][trail]["ankle"] = out["legs"][trail]["ankle"] - (Y + 0.6 * maths.Z) * n["trail"][i] * middle
        out["upper"]["arm"]["l"]["swing"] += n["pump"][i] * math.sin(math.pi * arms[0]) ** 2
        return out

    return _take_off(air, style, name, "jump_start_run", n, "Jog", at, body_at, speed)


def describe_start_run_l(rig, style, name: str = "Jump_Start_Run_L", joined=None) -> Clip:
    return _start_run(rig, style, name, joined, "l")


def describe_start_run_r(rig, style, name: str = "Jump_Start_Run_R", joined=None) -> Clip:
    return _start_run(rig, style, name, joined, "r")


def _frame_of(air: Air, name: str, at: int) -> dict:
    """A shipped clip's frame as a solved spec, in place: the root's travel taken out of the pelvis and the
    ankles."""
    clip = air.joined.clip(name)
    spec = clip.spec(at)
    legs = spec.setdefault("leg", {})
    for s, _ in SIDES:
        if s not in legs:
            legs[s] = clip.plan.foot(air.rig, s, at)
    if clip.balance is not None:
        stretch = clip.stretch(at) if callable(clip.stretch) else clip.stretch
        weight.settle(air.solver, spec, clip.balance(at, spec), stretch)
    place, yaw = clip.plan.travel.at(float(at))
    assert abs(yaw) < 1e-9, "a joined frame of a clip that turns is not handled"
    spec["pelvis"]["place"] = np.asarray(spec["pelvis"]["place"], dtype=float) - place
    for s, _ in SIDES:
        spec["leg"][s]["ankle"] = np.asarray(spec["leg"][s]["ankle"], dtype=float) - place
    return spec


# ---- landings ---------------------------------------------------------------------------------------------------


def _hermite(s: float, a: float, slope_a: float, b: float, slope_b: float) -> float:
    s2, s3 = s * s, s * s * s
    return (2 * s3 - 3 * s2 + 1) * a + (s3 - 2 * s2 + s) * slope_a + (-2 * s3 + 3 * s2) * b + (s3 - s2) * slope_b


def _landing(rig, style, name: str, joined, section: str, defaults: dict, speeds: tuple, replaces: str) -> Clip:
    air = Air(rig, joined)
    n = style.numbers(section, defaults)
    frames, bottom, hold, up = int(n["frames"]), int(n["bottom"]), int(n["hold"]), int(n["up"])
    top = bottom + hold + up
    assert top <= frames, "the landing's rise ends after the clip does"
    assert n["arms_from"] < bottom + n["arms_late"], f"{name}: the arms reach their low pose before they start down"
    # The arms' ways down and back up, in frames, the upper arm's (the forearm and the hand follow it, `lag`).
    lag = n["arms_lag"]
    down_span = [n["arms_from"], bottom + n["arms_late"]]
    after = frames - bottom - hold
    up_span = [bottom + hold + n["arms_up"][0] * after, bottom + hold + n["arms_up"][1] * after - 2 * lag]
    _arms_fit(name, up_span, lag, frames)
    took = bottom / FPS
    assert n["keep"] * took / 3.0 <= n["dip"] <= 2.0 * n["keep"] * took / 3.0, (
        f"{name}: a dip of {n['dip']} m in {bottom} frames from {n['keep']} m/s speeds up on the way down or "
        "turns before the bottom"
    )
    fall_n = air.numbers("Jump_Fall")
    fall = air.falling(fall_n, 0.0)
    fall_upper = upper_from(fall)
    feet = air.fall_feet(fall_n)
    low = upper_of(n)
    # The right foot lands a step ahead and is drawn back beside the left once the body is up.
    lands, (leaves, back) = int(n["right_lands"]), (int(n["step"][0]), int(n["step"][1]))
    assert lands >= 1 and leaves > lands + n["heel_down"][1] and back <= frames
    right = air.feet["r"]
    ahead = (right.place[0] - n["wide"], right.place[1] + n["stagger"])
    falls = [
        Footfall("l", 0.0, float(frames), air.feet["l"].place, yaw=air.feet["l"].yaw, roll_in=n["heel_down"][0]),
        Footfall("r", float(lands), float(leaves), ahead, yaw=-n["toe_out"], roll_in=n["heel_down"][1],
                 toe_off=n["toe_off"], roll_out=min(3.0, leaves - lands - n["heel_down"][1])),
        Footfall("r", float(back), float(frames), right.place, yaw=right.yaw),
    ]  # fmt: skip
    plan = ContactPlan(frames, falls, loop=False, clearance=n["step_clear"], toe_reach=0.026)
    floor = rig.sole["l"]["floor"]

    def legs_at(f: int) -> dict:
        legs = {}
        # The left foot is down from the first frame, on its ball, and its heel comes down.
        heel = feet["l"]["heel"] * (1.0 - maths.smooth(f / max(n["heel_down"][0], 1e-6)))
        legs["l"] = plan.state(rig, "l", "ball", np.array([falls[0].place[0], floor, falls[0].place[1]]), heel, falls[0].yaw)
        ball = np.array([ahead[0], floor, ahead[1]])
        if f < lands:
            # The right foot comes down from where the fall's pose has it.
            go = f / lands
            a, b = fall["leg"]["r"], plan.state(rig, "r", "ball", ball, feet["r"]["heel"], falls[1].yaw)
            legs["r"] = {"ankle": mix(np.asarray(a["ankle"]), b["ankle"], go), "foot": mix(a["foot"], b["foot"], go),
                         "toe": mix(a["toe"], b["toe"], go)}  # fmt: skip
        elif f < lands + n["heel_down"][1]:
            heel = feet["r"]["heel"] * (1.0 - maths.smooth((f - lands) / n["heel_down"][1]))
            legs["r"] = plan.state(rig, "r", "ball", ball, heel, falls[1].yaw)
        else:
            legs["r"] = plan.foot(rig, "r", float(f))
        # The knees open over the feet at the bottom and close again.
        deep = _deep(f)
        for s, sign in SIDES:
            out = feet[s]["knee_out"] + (n["knee_out"][AT[s]] - feet[s]["knee_out"]) * deep
            out *= 1.0 - window(f / frames, [top / frames, 1.0])
            legs[s]["knee"] = knee_way(legs[s]["foot"], sign, out)
        return legs

    def _deep(f: float) -> float:
        """0 on the first frame, 1 while the body is lowest, 0 again once it is up."""
        if f <= bottom:
            return maths.smooth(f / bottom)
        return 1.0 - skewed((f - bottom - hold) / up, n["push"])

    def height(f: float) -> float:
        """The centre of mass's height: caught over the frames to the bottom, held, pushed back up."""
        if f <= bottom:
            return _hermite(f / bottom, air.home[1], -n["keep"] * took, air.home[1] - n["dip"], 0.0)
        return air.home[1] - n["dip"] * (1.0 - skewed((f - bottom - hold) / up, n["push"]))

    def over(f: int, legs: dict) -> tuple:
        share = maths.keyed(
            [(0.0, n["share"][0]), (float(bottom), n["share"][0]), (float(leaves), n["share"][1]),
             (float(back), n["share"][1]), (float(frames), 0.5)], float(f))  # fmt: skip
        ahead_of = maths.keyed([(0.0, n["ahead"]), (float(top), n["ahead"]), (float(frames), 0.34)], float(f))
        between = np.array(weight.support_point(rig, legs, share, ahead_of))
        # It leaves the place the fall had it at and ends on the idle's.
        at = mix(np.array([air.home[0], air.home[2]]), between, window(f, [0.0, bottom + 1.0]))
        return mix(at, np.array(air.idle["over"]), window(f, [float(leaves), float(frames)]))

    def upper_at(f: int) -> dict:
        def down(late: float) -> float:
            span = n["trunk_down"]
            return window(f / (bottom + late), span)

        def back_up(span: list) -> float:
            return window((f - bottom - hold) / (frames - bottom - hold), span)

        # The arms follow the weight down after it and come back up, each way eased with no jump in its
        # acceleration (`maths.smoother`): a quadratic ease's steps in acceleration are what read as a snap.
        arms_down = _arm_shares(f, down_span, lag)
        arms_up = _arm_shares(f, up_span, lag)
        folded = {"upper": fall_upper, "legs": {}}
        folded = _blend(folded, {"upper": low, "legs": {}}, 0.0, down(n["trunk_late"]), arms_down)
        stood = _blend(folded, {"upper": air.open_idle_upper(), "legs": {}}, 0.0, back_up(n["trunk_up"]), arms_up)
        stood["upper"]["head"] = mix(folded["upper"]["head"], air.idle_upper["head"], back_up(n["head_up"]))
        return stood["upper"]

    made = {}

    def spec(f: int) -> dict:
        if f not in made:
            legs = legs_at(f)
            at = over(f, legs)
            start = air.home - Y * 0.12 if f == 0 else made[f - 1]["pelvis"]["place"] if f - 1 in made else air.idle_place
            one = to_spec(upper_at(f), legs, start, False)
            made[f] = standing_spec(air.solver, one, (at[0], height(float(f)), at[1]))
        return mix(made[f], made[f], 0.0)

    built_a, built_b = joined.built("Jump_Fall"), joined.built("Idle")
    declared = {
        "joins": {
            "first": (built_a.rotation[0], built_a.translation[0]),
            "last": (built_b.rotation[0], built_b.translation[0]),
            "last_speed": 0.0,
        },
        "distance": 0.0,
        "turn": 0.0,
        "join_names": {"first": "Jump_Fall", "last": "Idle"},
        "record": {
            "fall_speed": {"from": speeds[0], "to": speeds[1]},
            "control": int(n["control"]),
            "made_for": {"land_time": LAND_TIME, "land_clip_speed": LAND_CLIP_SPEED},
        },
        "speed_limit": n["speed_limit"],
        "keys_kept": 0.9,
        "kb_a_second": 40.0,
        "arm_bounds": air.arm_bounds(),
    }
    return Clip(
        name=name,
        frames=frames,
        plan=plan,
        spec=spec,
        loop=False,
        meet={"first": (built_a.frames[0], n["meet"]), "last": (built_b.frames[0], n["meet"])},
        chains=overlap.chains_from(style.overlap(section), TRUNK_PARTS),
        kind="transition",
        declared=declared,
        replaces=replaces,
        events=[
            {"frame": 0, "name": "footstep", "foot": "l"},
            {"frame": bottom, "name": "lowest"},
            {"frame": int(n["control"]), "name": "control"},
        ],
        style=style.letter,
    )


def describe_land_soft(rig, style, name: str = "Land_Soft", joined=None) -> Clip:
    return _landing(rig, style, name, joined, "land_soft", LAND, (LAND_CLIP_SPEED, HARD_SPEED), "ual1/Jump_Land")


def describe_land_hard(rig, style, name: str = "Land_Hard", joined=None) -> Clip:
    return _landing(rig, style, name, joined, "land_hard", HARD, (HARD_SPEED, None), "")


def describe_land_to_jog(rig, style, name: str = "Land_To_Jog", joined=None) -> Clip:
    air = Air(rig, joined)
    n = style.numbers("land_to_jog", TO_JOG)
    jog, built_jog = joined.clip("Jog"), joined.built("Jog")
    speed = built_jog.record["speed"]
    contact = int(n["contact"])
    # The left foot's contact is the jog's own, joined late: the clip's frame `f` is the jog's `f + into`, and it
    # ends as the jog's right foot strikes.
    lift = int(round(built_jog.record["contacts"]["l"][0][1]))
    into = lift - contact
    last = jog.frames // 2
    frames = last - into
    assert into >= 0 and frames > contact + 2, "the landing's contact does not fit the jog's"
    fall_n = air.numbers("Jump_Fall")
    fall = air.falling(fall_n, 0.0)
    feet = air.fall_feet(fall_n)
    fall_upper = upper_from(fall)
    strides = {f: _frame_of(air, "Jog", f + into) for f in range(frames + 1)}
    world = rig.world(built_jog.rotation, built_jog.translation)
    centres = rig.centre_of_mass(world)
    floor = rig.sole["l"]["floor"]
    left = air.feet["l"]
    strike = next(fall for fall in jog.plan.footfalls if fall.side == "r")
    plan = ContactPlan(
        frames,
        [
            Footfall("l", 0.0, float(contact), left.place, yaw=left.yaw, toe_off=n["toe_off"], roll_out=contact - n["heel"][0]),
            Footfall("r", float(frames), float(frames + 6), (strike.place[0], strike.place[1] - speed * into / FPS), yaw=strike.yaw),
        ],
        Travel.steady(speed),
        loop=False,
        tread=TREAD,
    )  # fmt: skip
    ball = np.array([left.place[0], floor, left.place[1]])
    travel = lambda f: maths.Z * speed * f / FPS  # noqa: E731

    def left_leg(f: float) -> dict:
        heel = maths.keyed([(0.0, feet["l"]["heel"]), (n["heel"][0], n["heel"][1]), (float(contact), n["toe_off"])], f)
        return plan.state(rig, "l", "ball", ball, heel, left.yaw)

    gone = left_leg(float(contact))
    jog_gone = strides[contact]["leg"]["l"]

    def legs_at(f: int) -> dict:
        legs = {}
        stride = strides[f]["leg"]
        if f <= contact:
            legs["l"] = left_leg(float(f))
        else:
            # It leaves from its own place and joins the jog's swing: what set the two apart is let go.
            keep = 1.0 - maths.smooth((f - contact) / (frames - contact))
            legs["l"] = {
                "ankle": np.asarray(stride["l"]["ankle"]) + travel(f) + keep * (gone["ankle"] - np.asarray(jog_gone["ankle"]) - travel(contact)),
                "foot": mix(tuple(stride["l"]["foot"]), tuple(np.add(stride["l"]["foot"], np.subtract(gone["foot"], jog_gone["foot"]))), keep),
                "toe": stride["l"].get("toe", 0.0) + keep * (gone["toe"] - jog_gone.get("toe", 0.0)),
            }  # fmt: skip
        go = window(f / frames, n["right"])
        a, b = fall["leg"]["r"], stride["r"]
        legs["r"] = {
            "ankle": mix(np.asarray(a["ankle"]) + travel(f), np.asarray(b["ankle"]) + travel(f), go),
            "foot": mix(tuple(a["foot"]), tuple(b["foot"]), go),
            "toe": mix(float(a.get("toe", 0.0)), float(b.get("toe", 0.0)), go),
        }
        # The knees leave the way the fall's pose points them over the contact.
        keep = 1.0 - maths.smooth(f / contact)
        for s, sign in SIDES:
            legs[s]["knee"] = knee_way(legs[s]["foot"], sign, feet[s]["knee_out"] * keep)
        return legs

    # The centre of mass: caught and thrown by the left leg, then on the jog's own flight.
    leave = centres[lift]
    rate = (centres[lift + 1][1] - centres[lift - 1][1]) / 2.0

    def centre(f: int) -> np.ndarray:
        if f >= contact:
            return centres[f + into] + travel(f)
        s = f / contact
        height = _hermite(s, air.home[1], -n["keep"] * contact / FPS, leave[1], rate * contact)
        height -= n["sink"] * math.sin(math.pi * s) ** 2
        level = mix(np.array([air.home[0], air.home[2]]), np.array([leave[0], leave[2]]), maths.smooth(s))
        return np.array([level[0], height, level[1]]) + travel(f)

    made = {}
    arms_span = [n["arms"][0] * frames, n["arms"][1] * frames - 2 * n["arms_lag"]]
    _arms_fit(name, arms_span, n["arms_lag"], frames)

    def spec(f: int) -> dict:
        if f not in made:
            share = window(f / frames, n["upper"])
            arms = _arm_shares(f, arms_span, n["arms_lag"])
            upper = _blend({"upper": fall_upper, "legs": {}}, {"upper": _carried_arms(upper_from(strides[f])), "legs": {}}, 0.0, share, arms)["upper"]
            fold = n["fold"] * math.sin(math.pi * min(f / contact, 1.0)) ** 2
            upper["chest"] = (upper["chest"][0] + fold, upper["chest"][1], upper["chest"][2])
            start = air.home - Y * 0.12 if f == 0 else made[f - 1]["pelvis"]["place"] + travel(1) if f - 1 in made else air.idle_place + travel(f)
            one = to_spec(upper, legs_at(f), start, False)
            weight.settle(air.solver, one, tuple(centre(f)), rounds=8)
            made[f] = one
        return mix(made[f], made[f], 0.0)

    built_a = joined.built("Jump_Fall")
    declared = {
        "joins": {
            "first": (built_a.rotation[0], built_a.translation[0]),
            "last": (built_jog.rotation[last], built_jog.translation[last]),
            "last_speed": speed,
        },
        "distance": speed * frames / FPS,
        "turn": 0.0,
        "join_names": {"first": "Jump_Fall", "last": "Jog"},
        "heel_up": ("l",),
        "record": {
            "fall_speed": {"from": LAND_CLIP_SPEED, "to": HARD_SPEED},
            "control": 0,
            "join_frames": {"first": 0, "last": last},
        },
        "speed_limit": n["speed_limit"],
        "keys_kept": 0.95,
        "kb_a_second": 60.0,
        "arm_bounds": air.arm_bounds(n["arms_like"]),
    }
    return Clip(
        name=name,
        frames=frames,
        plan=plan,
        spec=spec,
        loop=False,
        meet={"first": (built_a.frames[0], min(n["meet"], frames)), "last": (built_jog.frames[last], min(n["meet"], frames))},
        # The arms keep the overlap pass here: they end in the jog's swing, whose arms carry the pass too, and a
        # solved arm would be moved the jog's lag (15 to 25 degrees) in the clip's seven frames to join it.
        chains=overlap.chains_from(style.overlap("land_to_jog"), PARTS),
        kind="transition",
        declared=declared,
        events=[{"frame": 0, "name": "footstep", "foot": "l"}],
        style=style.letter,
    )
