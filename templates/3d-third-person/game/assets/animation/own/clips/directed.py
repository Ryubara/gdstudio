"""`Walk_Back`, `Walk_Left`, `Walk_Right`, `Jog_Back`, `Jog_Left`, `Jog_Right`: the gaits that do not go the way
the body faces (kit #1159). New clips: the library's Standard files have no strafe and no backpedal, and while it
aims the template's character moves any way under a forward gait, so its feet slide sideways and backward.

Each is the gait of `gait.py` (footfalls first, the centre of mass as the input, the pelvis and the knees solved)
travelling another way (`heading`), with what a body does differently when it does not go where it looks (the
research and its sources are in `../README.md`):

- **In step with the forward gaits.** The cycle is the shipped `Walk`'s or `Jog`'s, the left foot lands at frame 0
  and the right half a cycle later, so the tree can blend a direction with the forward gait in step. The steps are
  shorter than the forward gait's, as a person's are backward and sideways, so each clip has its own speed.
- **A backpedal lands on the ball of the foot.** The foot reaches back toes first, the heel comes down under the
  weight, and in a walk the heel is the last part to leave, with the toes up (a forward walk played backward). The
  run lands and leaves on the ball, sits lower and leans over its toes.
- **A strafe turns the hips a third toward the step and passes its feet in two lanes.** The pelvis, the knees and
  the toes are turned toward the step (`face`, `foot_turn`), so the trailing leg swings across in front of the
  leading one: the leading foot's lane is behind the root's path and the trailing foot's ahead of it (`lane`), and
  no leg goes through the other. The open step is long and the crossed step short (`ahead` per side). The chest
  turns back toward the front, and the head looks where the body faces.
- **A left strafe is not a right strafe flipped.** Each has its own table: the right arm is the one that carries a
  weapon, the hips turn further to the left than to the right, the right strafe opens wider and crosses less.
"""

import math

import numpy as np

from gdsanim import maths, overlap
from gdsanim.build import Clip
from gdsanim.maths import FPS, body_turn
from gdsanim.plan import ContactPlan, Footfall, Travel
from gdsanim.rig import SIDES

from . import gait
from .gait import PARTS, UNEVEN_LIFT, UNEVEN_REACH, Gait

## What a directed gait's section may set beside the numbers of `gait.COMMON`.
EXTRA = {
    "heading": 0.0,  # degrees to the left of the way the body faces that it travels (180: backward, 90: to its left)
    "face": 0.0,  # degrees the pelvis stays turned to the left: a strafe turns the hips toward the step
    "foot_turn": 0.0,  # degrees the feet, and so the knees, are turned to the left (on top of `toe_out`)
    "knee_turn": 0.0,  # degrees a knee points further to the left than its foot (a strafe's knees pass apart)
    "lane": 0.0,  # metres ahead of the root's path a foot's lane lies (a strafe's feet pass in two lanes)
    "pass_wide": 0.0,  # metres a swinging foot goes further from the other foot's lane as it passes it
    "lean_side": 0.0,  # degrees the chest leans to the left (into a left step)
    "pelvis_lean": 0.0,  # degrees the pelvis leans to the left
    "weight_ahead": 0.0,  # metres the centre of mass rides ahead of the root's place, the way the body faces
}
## The numbers a side may have of its own, beside `gait.SIDED`.
SIDED = gait.SIDED + ("foot_turn", "knee_turn", "lane", "pass_wide", "heel_strike", "toe_off", "roll_in")
_WALK = {
    **gait.COMMON,
    **EXTRA,
    # The fluid swing of the shipped walk (`fluidity.py`): the foot leaves from rest, the pelvis answers the
    # limbs with three waves a cycle at most.
    "pelvis_waves": 3,
    "swing_early": 0.0,
    "swing_ease": 1.0,
    "speed_limit": 27.0,
}
_JOG = {**gait.DEFAULTS["jog"], **EXTRA, "pelvis_waves": 3, "swing_early": 0.0, "swing_ease": 1.0, "speed_limit": 36.0}
DEFAULTS = {
    "walk_back": {
        **_WALK,
        "heading": 180.0,
        "speed": 1.3,
        "duty": 16 / 26,
        "ahead": 0.5,
        "width": 0.085,
        "toe_out": 7.0,
        "heel_strike": -16.0,  # the ball of the foot lands, the heel this far up
        "roll_in": 4.5,
        "toe_off": -7.0,  # the heel leaves last, the toes this far up
        "roll_out": 3.5,
        "kick": 0.012,
        "kick_at": 0.4,
        "carry_height": 0.02,
        "carry_at": 0.7,
        "kick_pitch": 6.0,
        "stretch": 0.992,
        "bob": 0.026,
        "sway": 0.02,
        "hip_turn": 3.0,
        "hip_turn_at": 0.0,
        "hip_tip": 2.5,
        "hip_tip_at": 0.16,
        "pelvis_pitch": 2.0,
        "lean": 2.0,
        "lean_live": 0.5,
        "counter_turn": 3.0,
        "head_pitch": 1.0,
        "arm_fore": 11.0,
        "arm_back": 9.0,
        "arm_at": 0.98,
        "arm_out": 8.0,
        "arm_out_back": 2.0,
        "elbow": 22.0,
        "elbow_live": 6.0,
        "wrist_live": 3.0,
        "finger_live": 3.0,
    },
    "walk_left": {
        **_WALK,
        "heading": 90.0,
        "speed": 1.2,
        "duty": 15 / 26,
        "face": 30.0,
        "foot_turn": 30.0,
        "width": 0.0,
        "toe_out": 6.0,
        "heel_strike": -5.0,
        "roll_in": 3.0,
        "toe_off": 34.0,
        "roll_out": 6.0,
        "kick": 0.02,
        "kick_at": 0.35,
        "carry_height": 0.03,
        "carry_at": 0.6,
        "kick_pitch": 22.0,
        "stretch": 0.99,
        "bob": 0.024,
        "sway": 0.02,
        "hip_turn": 4.0,
        "hip_turn_at": 0.5,
        "hip_tip": 3.0,
        "hip_tip_at": 0.12,
        "pelvis_pitch": 1.5,
        "lean": 1.5,
        "lean_side": 2.0,
        "lean_live": 0.5,
        "counter_turn": 3.0,
        "chest_turn_rest": 9.0,
        "arm_fore": 9.0,
        "arm_back": 10.0,
        "arm_out": 9.0,
        "arm_out_back": 3.0,
        "elbow": 20.0,
        "elbow_live": 6.0,
        "wrist_live": 3.0,
        "finger_live": 3.0,
        "arm_at": 0.5,
        # The swinging foot goes round the planted one (`pass_wide`) and the knees pass apart (`knee_turn`): in
        # two straight lanes 0.2 m apart with one turn for both legs, a foot went 36 mm through the other.
        "left": {"ahead": 0.66, "lane": -0.12, "foot_turn": 34.0, "knee_turn": 20.0, "pass_wide": 0.05},
        "right": {"ahead": 0.32, "lane": 0.12, "foot_turn": 25.0, "knee_turn": -12.0, "pass_wide": 0.05},
    },
    "walk_right": {
        **_WALK,
        "heading": -90.0,
        "speed": 1.2,
        "duty": 15 / 26,
        "face": -26.0,
        "foot_turn": -28.0,
        "width": 0.0,
        "toe_out": 6.0,
        "heel_strike": -5.0,
        "roll_in": 3.0,
        "toe_off": 30.0,
        "roll_out": 6.0,
        "kick": 0.02,
        "kick_at": 0.35,
        "carry_height": 0.03,
        "carry_at": 0.6,
        "kick_pitch": 22.0,
        "stretch": 0.99,
        "bob": 0.024,
        "sway": 0.02,
        "hip_turn": 4.0,
        "hip_turn_at": 0.5,
        "hip_tip": 3.0,
        "hip_tip_at": 0.12,
        "pelvis_pitch": 1.5,
        "lean": 1.5,
        "lean_side": -1.5,
        "lean_live": 0.5,
        "counter_turn": 3.0,
        "chest_turn_rest": -6.0,
        "arm_fore": 9.0,
        "arm_back": 10.0,
        "arm_out": 9.0,
        "arm_out_back": 3.0,
        "elbow": 20.0,
        "elbow_live": 6.0,
        "wrist_live": 3.0,
        "finger_live": 3.0,
        "arm_at": 0.5,
        "left": {"ahead": 0.28, "lane": 0.125, "foot_turn": -22.0, "knee_turn": 10.0, "pass_wide": 0.055},
        "right": {"ahead": 0.7, "lane": -0.115, "foot_turn": -33.0, "knee_turn": -22.0, "pass_wide": 0.045},
    },
    "jog_back": {
        **_JOG,
        "heading": 180.0,
        "speed": 3.0,
        "duty": 7 / 20,
        "ahead": 0.5,
        "width": 0.075,
        "toe_out": 6.0,
        "heel_strike": -20.0,
        "roll_in": 2.5,
        "stance_pitch": 5.0,
        "toe_off": 22.0,
        "roll_out": 2.5,
        "kick": 0.05,
        "kick_at": 0.4,
        "carry_height": 0.05,
        "carry_at": 0.65,
        "land_from": 0.03,
        "land_speed": 0.4,
        "kick_pitch": 26.0,
        "stretch": 0.97,
        "bob": 0.05,
        "takeoff_rise": 0.012,
        "sway": 0.012,
        "hip_turn": 4.0,
        "hip_turn_at": 0.0,
        "hip_tip": 3.0,
        "hip_tip_at": 0.17,
        "pelvis_pitch": 7.0,
        "lean": 9.0,
        "lean_live": 1.0,
        "counter_turn": 6.0,
        "head_pitch": -3.0,
        "arm_fore": 16.0,
        "arm_back": 22.0,
        "arm_at": 0.98,
        "arm_out": 14.0,
        "arm_out_back": 6.0,
        "arm_twist": 6.0,
        "elbow": 78.0,
        "elbow_live": 6.0,
    },
    "jog_left": {
        **_JOG,
        "heading": 90.0,
        "speed": 3.0,
        "duty": 6 / 20,
        "face": 34.0,
        "foot_turn": 32.0,
        "width": 0.0,
        "toe_out": 5.0,
        "heel_strike": -8.0,
        "roll_in": 1.5,
        "stance_pitch": 3.0,
        "toe_off": 40.0,
        "roll_out": 3.0,
        "kick": 0.08,
        "kick_at": 0.36,
        "carry_height": 0.06,
        "carry_at": 0.6,
        "land_from": 0.04,
        "land_speed": 0.4,
        "kick_pitch": 40.0,
        "stretch": 0.975,
        "bob": 0.05,
        "takeoff_rise": 0.012,
        "sway": 0.012,
        "hip_turn": 6.0,
        "hip_turn_at": 0.42,
        "hip_tip": 3.5,
        "hip_tip_at": 0.16,
        "pelvis_pitch": 4.0,
        "lean": 5.0,
        "lean_side": 4.0,
        "counter_turn": 6.0,
        "chest_turn_rest": 10.0,
        "arm_fore": 18.0,
        "arm_back": 24.0,
        "arm_at": 0.4,
        "arm_out": 14.0,
        "arm_out_back": 8.0,
        "arm_twist": 8.0,
        "elbow": 80.0,
        "elbow_live": 8.0,
        # The knees pass apart: the leading leg's points on toward the step, the crossing leg's back toward the
        # front (with one turn for both, the thighs met by 50 mm as the crossing foot landed).
        "left": {"ahead": 0.74, "lane": -0.12, "foot_turn": 36.0, "knee_turn": 20.0},
        "right": {"ahead": 0.22, "lane": 0.12, "foot_turn": 28.0, "knee_turn": -12.0},
        "kb_a_second": 28.0,
    },
    "jog_right": {
        **_JOG,
        "heading": -90.0,
        "speed": 3.0,
        "duty": 6 / 20,
        "face": -29.0,
        "foot_turn": -30.0,
        "width": 0.0,
        "toe_out": 5.0,
        "heel_strike": -8.0,
        "roll_in": 1.5,
        "stance_pitch": 3.0,
        "toe_off": 36.0,
        "roll_out": 3.0,
        "kick": 0.08,
        "kick_at": 0.36,
        "carry_height": 0.06,
        "carry_at": 0.6,
        "land_from": 0.04,
        "land_speed": 0.4,
        "kick_pitch": 40.0,
        "stretch": 0.975,
        "bob": 0.05,
        "takeoff_rise": 0.012,
        "sway": 0.012,
        "hip_turn": 6.0,
        "hip_turn_at": 0.42,
        "hip_tip": 3.5,
        "hip_tip_at": 0.16,
        "pelvis_pitch": 4.0,
        "lean": 5.0,
        "lean_side": -3.0,
        "counter_turn": 6.0,
        "chest_turn_rest": -7.0,
        "arm_fore": 18.0,
        "arm_back": 24.0,
        "arm_at": 0.4,
        "arm_out": 14.0,
        "arm_out_back": 8.0,
        "arm_twist": 8.0,
        "elbow": 80.0,
        "elbow_live": 8.0,
        "left": {"ahead": 0.2, "lane": 0.125, "foot_turn": -24.0, "knee_turn": 10.0},
        "right": {"ahead": 0.76, "lane": -0.115, "foot_turn": -35.0, "knee_turn": -22.0},
        "kb_a_second": 28.0,
    },
}
## The forward gait each is in step with, and the ranges its measured numbers are held to: the forward gait's
## cadence (the cycle is the same), a planted share of its own (a backpedal's contact is a longer share of the
## cycle than the forward gait's; `../README.md`), and the pelvis's rise and fall (mm), smaller on shorter steps.
GAITS = {
    "walk_back": ("Walk", {"cadence": (125.0, 140.0), "planted_share": (0.57, 0.66), "bob_mm": (18.0, 45.0)}),
    "walk_left": ("Walk", {"cadence": (125.0, 140.0), "planted_share": (0.55, 0.64), "bob_mm": (15.0, 45.0)}),
    "walk_right": ("Walk", {"cadence": (125.0, 140.0), "planted_share": (0.55, 0.64), "bob_mm": (15.0, 45.0)}),
    "jog_back": ("Jog", {"cadence": (169.0, 187.0), "planted_share": (0.3, 0.4), "bob_mm": (40.0, 95.0)}),
    "jog_left": ("Jog", {"cadence": (169.0, 187.0), "planted_share": (0.27, 0.38), "bob_mm": (40.0, 95.0)}),
    "jog_right": ("Jog", {"cadence": (169.0, 187.0), "planted_share": (0.27, 0.38), "bob_mm": (40.0, 95.0)}),
}


class Directed(Gait):
    """A gait that travels `heading` degrees to the left of the way the body faces."""

    sided = SIDED

    def __init__(self, rig, numbers: dict, lags: dict):
        heading = math.radians(numbers["heading"])
        ## The way the body travels over the floor, in the space it faces +Z in (x to its left).
        self.way = np.array([math.sin(heading), 0.0, math.cos(heading)])
        self.way[np.abs(self.way) < 1e-12] = 0.0
        super().__init__(rig, numbers, lags)
        n = numbers
        falls = []
        for s, sign in SIDES:
            land = self._land(s)
            falls.append(Footfall(s, land, land + self.contact, self._place(s, sign, 0), yaw=self._yaw(s, sign)))
        speed = n["speed"]
        travel = Travel(
            forward=lambda f: speed * float(self.way[2]) * f / FPS, left=lambda f: speed * float(self.way[0]) * f / FPS
        )
        self.plan = ContactPlan(self.frames, falls, travel, tread=False)
        lanes = {s: np.array([sign * self.own(s, "width"), 0.0, self.own(s, "lane")]) for s, sign in SIDES}
        apart = lanes["l"] - lanes["r"]
        ## The way from the right foot's lane to the left's: the weight sways along it.
        self.across = apart / max(float(np.linalg.norm(apart)), 1e-9)

    def _yaw(self, s: str, sign: float) -> float:
        return sign * self.own(s, "toe_out") + self.own(s, "foot_turn")

    def _place(self, s: str, sign: float, cycle: int) -> tuple:
        n = self.n
        reach = self.own(s, "ahead") * self.covered + (UNEVEN_REACH * n["uneven"] if s == "r" else 0.0)
        along = n["speed"] * self._land(s) / FPS + reach + cycle * self.stride
        return (
            sign * self.own(s, "width") + float(self.way[0]) * along,
            self.own(s, "lane") + float(self.way[2]) * along,
        )

    def _stance(self, s: str, sign: float, cycle: int, t: float) -> dict:
        """A planted foot, `t` frames after it landed. The ball lands with the heel up (`heel_strike` under 0)
        or the heel with the toes up; the foot leaves over its toes (`toe_off` over 0) or its heel leaves last
        with the toes up (under 0: a walk backward)."""
        n, rig = self.n, self.rig
        sole = rig.sole[s]
        x, z = self._place(s, sign, cycle)
        ball = np.array([x, sole["floor"], z])
        yaw = self._yaw(s, sign)
        heel = ball + body_turn(0.0, yaw, 0.0) @ (sole["heel"] - sole["ball"])
        strike, off = self.own(s, "heel_strike"), self.own(s, "toe_off")
        roll_in, roll_out = self.own(s, "roll_in"), self.own(s, "roll_out")
        if t < roll_in:
            share = 1.0 - maths.smooth(t / roll_in)
            if strike >= 0.0:
                return self.plan.state(rig, s, "heel", heel, -strike * share, yaw)
            pitch = n["stance_pitch"] + (-strike - n["stance_pitch"]) * share
        elif t > self.contact - roll_out:
            share = maths.smooth((t - (self.contact - roll_out)) / roll_out)
            if off < 0.0:
                return self.plan.state(rig, s, "heel", heel, off * share, yaw)
            pitch = n["stance_pitch"] + (off - n["stance_pitch"]) * share
        else:
            pitch = n["stance_pitch"]
        return self.plan.state(rig, s, "ball", ball, pitch, yaw)

    def _swing(self, s: str, sign: float, cycle: int, u: float) -> dict:
        """A foot in the air, the share `u` of the way from leaving the floor to landing in the next cycle. It
        stays in its lane, so it passes the planted foot beside it and not through it."""
        n, rig = self.n, self.rig
        sole = rig.sole[s]
        a = self._stance(s, sign, cycle, self.contact)
        b = self._stance(s, sign, cycle + 1, 0.0)
        more = 1.0 + (UNEVEN_LIFT * n["uneven"] if s == "r" else 0.0)
        kick, carry = self.own(s, "kick"), self.own(s, "carry_height")
        eased = (1.0 - n["swing_ease"]) * maths.smooth(u) + n["swing_ease"] * maths.smoother(u)
        go = (1.0 - n["swing_early"]) * eased + n["swing_early"] * (1.0 - (1.0 - u) ** 2)
        still = n["land_speed"] * (self.stride - self.covered) / max(float((b["ankle"] - a["ankle"]) @ self.way), 1e-6)
        go = (1.0 - still) * go + still * u
        ankle = a["ankle"] + (b["ankle"] - a["ankle"]) * go
        wide = self.own(s, "pass_wide")
        if wide:
            ankle = ankle + (1.0 if s == "l" else -1.0) * self.across * wide * math.sin(math.pi * u) ** 2
        lift = maths.keyed(
            [(0.0, 0.0), (self.own(s, "kick_at"), kick * more), (n["carry_at"], carry * more), (1.0, 0.0)], u
        )
        ankle[1] += lift
        if n["land_from"] > 0.0:
            swing = self.frames - self.contact
            ankle[1] += n["land_from"] * min(u * swing / n["leave_frames"], 1.0, (1.0 - u) * swing / n["land_frames"])
        pitch_a, pitch_b = a["foot"][0], b["foot"][0]
        pitch = maths.keyed(
            [
                (0.0, pitch_a),
                (self.own(s, "kick_at"), max(n["kick_pitch"], pitch_a)),
                (0.86, 0.6 * pitch_b + 0.4 * max(n["kick_pitch"], pitch_b) if pitch_b > 0.0 else 0.6 * pitch_b),
                (1.0, pitch_b),
            ],
            u,
        )
        yaw = self._yaw(s, sign)
        # The toes straighten as the foot leaves, and bend again before a landing on the ball of the foot.
        toe = a["toe"] * (1.0 - maths.smooth(u / 0.3)) + b["toe"] * maths.smooth((u - 0.55) / 0.45)
        turn = body_turn(pitch, yaw, 0.0)
        hinge = ankle + turn @ (sole["hinge"] - sole["ankle"])
        tip = hinge + body_turn(pitch - toe, yaw, 0.0) @ (sole["toe"] - sole["hinge"])
        heel = ankle + turn @ (sole["heel"] - sole["ankle"])
        ball = ankle + turn @ (sole["ball"] - sole["ankle"])
        margin = 0.006 * maths.smooth(u / 0.15) * maths.smooth((1.0 - u) / 0.1)
        ankle[1] += max(sole["floor"] + margin - min(tip[1], heel[1], ball[1]), 0.0)
        return {"ankle": ankle, "foot": (pitch, yaw, 0.0), "toe": toe}

    def centre(self, f: float) -> tuple:
        """Where the centre of mass is at a frame, in the world: along the way the body travels, swaying toward
        the lane of the foot that carries it."""
        side, height, along = super().centre(f)
        ahead = self.n["weight_ahead"]
        at = self.way * along + self.across * side
        return (float(at[0]), height, float(at[2]) + ahead)

    def spec(self, f: float) -> dict:
        n = self.n
        out = super().spec(f)
        pitch, yaw, lean = out["pelvis"]["turn"]
        out["pelvis"]["turn"] = (pitch, yaw + n["face"], lean + n["pelvis_lean"])
        pitch, yaw, lean = out["chest"]
        out["chest"] = (pitch, yaw, lean + n["lean_side"])
        for s, sign in SIDES:
            more = self.own(s, "knee_turn")
            if more:
                out["leg"][s]["knee"] = body_turn(0.0, self._yaw(s, sign) + more, 0.0) @ maths.Z
        return out


def describe(kind: str, rig, style, name: str) -> Clip:
    n = style.numbers(kind, DEFAULTS[kind])
    # A side's own numbers are laid over the description's for that side, so a style names only what it changes.
    for side in ("left", "right"):
        n[side] = {**DEFAULTS[kind][side], **n[side]}
    lags = style.overlap(kind)
    walk = Directed(rig, n, {part: tuple(value) for part, value in lags.items()})
    walk.settle_height()
    with_gait, ranges = GAITS[kind]
    return Clip(
        name=name,
        frames=walk.frames,
        plan=walk.plan,
        spec=lambda f: walk.spec(float(f)),
        balance=None if walk.fixed else (lambda f, at: walk.centre(float(f))),
        chains=overlap.chains_from(lags, PARTS),
        kind="gait",
        declared={
            "ranges": {key: tuple(n["ranges"].get(key, value)) for key, value in ranges.items()},
            "lags": {
                **{part: round(walk.late(part), 2) for part in ("forearm", "hand") if part in lags},
                **({"chest": lags["chest"][0]} if "chest" in lags else {}),
            },
            "distance": walk.stride,
            "speed_limit": n["speed_limit"],
            "keys_kept": n["keys_kept"],
            "kb_a_second": n["kb_a_second"],
            # The gait checks read each limb's swing in its own plane: a strafe's legs along the way it travels,
            # its arms across the way its hips face; a backpedal's as a forward gait's.
            "facing": n["face"],
            "legs_facing": n["heading"] if abs(n["heading"]) < 135.0 else 0.0,
            # A strafe's open step and crossed step swing the thighs on two shapes: its legs' phase is read
            # where the soles land.
            "legs_by_landing": abs(n["heading"]) < 135.0,
            "says": {"heading": n["heading"], "in_step_with": with_gait},
        },
        replaces="",
        style=style.letter,
    )


def walk_back(rig, style, name: str = "Walk_Back") -> Clip:
    return describe("walk_back", rig, style, name)


def walk_left(rig, style, name: str = "Walk_Left") -> Clip:
    return describe("walk_left", rig, style, name)


def walk_right(rig, style, name: str = "Walk_Right") -> Clip:
    return describe("walk_right", rig, style, name)


def jog_back(rig, style, name: str = "Jog_Back") -> Clip:
    return describe("jog_back", rig, style, name)


def jog_left(rig, style, name: str = "Jog_Left") -> Clip:
    return describe("jog_left", rig, style, name)


def jog_right(rig, style, name: str = "Jog_Right") -> Clip:
    return describe("jog_right", rig, style, name)
