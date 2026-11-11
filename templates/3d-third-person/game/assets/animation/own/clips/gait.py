"""`Walk`, `Jog` and `Sprint`: the three gaits (kit #1155). They replace `ual1/Walk`, `ual1/Jog_Fwd` and
`ual1/Sprint`.

The library's gaits do not hold the floor at the speeds the game moves them at, its jog and sprint are bounds, their
arm swing is the chest turning and nothing trails (`docs/tools/blender/own-animation.md#audit-gaits`). Ours are one
description with three sets of numbers, built from how people walk and run (the research and its sources are in
`../README.md`):

- **The footfalls are the input.** The left foot lands at frame 0 and the right half a cycle later in all three, so
  a blend between them stays in step. A foot stands on one place of the floor for its share of the cycle (`duty`)
  while the root travels over it at the game's speed, so cadence, planted share and speed are what the style says
  and the planted sole cannot slide.
- **The body's weight is the input, not the pelvis.** The centre of mass moves at the clip's speed, sways toward the
  foot that carries it and goes up and down as a body's does: in a walk it is highest over the standing leg and
  lowest with both feet down; in a run it falls freely between two contacts and is caught and thrown by the leg in
  between. The pelvis is solved from it on every frame, and the whole curve is set as high as the leg that is
  stretched furthest allows (`stretch`).
- **A foot rolls.** A walk lands on the heel and leaves over the toes; a jog lands nearly flat; a sprint lands on
  the ball of the foot and the heel never comes down. In the air the foot is drawn up behind the body, passes under
  it with the knee leading, and comes back against the ground before it lands, so it meets the floor without speed.
- **The trunk winds against the legs.** The pelvis turns and tips with the legs (in a walk the hip of the landing
  leg is forward, in a run the hip of the knee that drives), the chest turns and leans the other way, the head
  stays level and faces the way the body goes.
- **The arms swing in their sockets**, each with the other side's leg, hanging in a walk and bent in a run; the
  forearm, the hand, the chest and the head take their motion late through the overlap pass, and the fingers open
  and close a little with the swing.
- **The two sides are not mirror images**: a side has its own numbers for its foot, its arm and its hand (`left`,
  `right`), the pelvis, the chest and the head keep a small turn and tilt through the cycle (the `_rest` numbers),
  and one leg reaches and lifts a little more while the other arm swings a little wider (`uneven`).
"""

import math

import numpy as np

from gdsanim import maths, overlap, weight
from gdsanim.build import Clip
from gdsanim.maths import FPS, body_turn
from gdsanim.plan import ContactPlan, Footfall, Travel
from gdsanim.rig import SIDES
from gdsanim.solve import Solver

## What each number of a style's `walk`, `jog` or `sprint` section means. A share of the cycle is 0 as the left foot
## lands and 0.5 as the right does.
COMMON = {
    "frames": 26,  # the cycle's length (two steps); even, so the right foot lands on a whole frame
    "speed": 1.7,  # metres a second the planted feet hold the floor at (the game's speed for the gait)
    "duty": 15 / 26,  # the share of the cycle a foot is on the floor (a whole number of frames reads cleanest)
    "ahead": 0.48,  # where the ball of the foot lands: this share of the ground a contact covers, ahead of the body
    "width": 0.075,  # metres each foot lands from the body's middle line
    "toe_out": 6.0,  # degrees each foot points outward
    "heel_strike": 14.0,  # degrees the toes point up as the heel lands; negative: the heel is up, the ball lands
    "roll_in": 3.0,  # frames the foot takes to come down after landing
    "toe_off": 60.0,  # degrees the heel is up as the toes leave
    "roll_out": 7.5,  # frames it takes to get there
    "stance_pitch": 0.0,  # degrees the heel stays up between the two (a sprint's heel never comes down)
    "kick": 0.03,  # metres the ankle rises over its straight path early in the swing (the heel drawn up behind)
    "kick_at": 0.3,  # the share of the swing where it is highest
    "carry_height": 0.03,  # metres it is still over that path as the foot passes under the body
    "carry_at": 0.62,  # the share of the swing where that is
    "land_from": 0.0,  # metres more the foot is lifted for the whole swing but its ends (a run's foot comes down)
    "leave_frames": 1.5,  # frames it goes up to that over as it leaves, at one speed
    "land_frames": 2.0,  # frames it comes down from it over as it lands, at one speed
    "kick_pitch": 55.0,  # degrees the toes point down at the top of the kick
    "swing_early": 0.3,  # 0: the foot leaves the floor from rest; toward 1 it is flicked off and is quick at once
    "land_speed": 0.0,  # the share of the ground's speed the foot still has over the floor as it lands (0: none)
    "stretch": 0.997,  # the share of its full length the furthest stretched leg is at, anywhere in the cycle
    "bob": 0.036,  # metres the centre of mass goes up and down
    "takeoff_rise": 0.0,  # runs: metres the centre of mass is higher as the foot leaves than as it lands
    "sway": 0.016,  # metres the centre of mass goes toward the carrying foot, each side
    "hip_turn": 4.0,  # degrees the pelvis turns each way about the vertical
    "hip_turn_at": 0.5,  # the share of the cycle where the right hip is furthest forward
    "hip_tip": 3.0,  # degrees the hip of the swinging leg drops
    "hip_tip_at": 0.12,  # the share of the cycle where the right hip is lowest
    "pelvis_pitch": 1.0,  # degrees the pelvis is tipped forward
    "lean": 1.0,  # degrees the chest leans forward
    "lean_live": 0.6,  # degrees it nods, twice a cycle, as each foot takes the weight
    "counter_turn": 4.0,  # degrees the chest turns each way against the pelvis
    "counter_tip": 0.6,  # the chest's lean against the pelvis's tip, as a share of it
    "head_pitch": 0.0,  # degrees the head looks down
    "arm_fore": 18.0,  # degrees the upper arm swings forward of straight down
    "arm_back": 22.0,  # and behind it
    "arm_at": 0.48,  # the share of the cycle where the left arm is furthest forward
    "arm_out": 7.0,  # degrees the arms hang out from the body
    "arm_out_back": 4.0,  # degrees more they go out as they swing back past the hip
    "arm_twist": 0.0,  # degrees the bent forearm is turned in toward the body's middle as it comes forward
    "arm_clear": 0.19,  # metres the hand keeps from the thigh's line (0: not asked for)
    "elbow": 16.0,  # degrees the elbow is bent in the middle of the swing
    "elbow_live": 12.0,  # degrees more it bends as the arm comes forward, and less as it goes back
    "pronate": 14.0,  # degrees the forearm turns the thumb inward
    "wrist": 4.0,  # degrees the wrist bends toward the palm
    "wrist_live": 5.0,  # degrees it gives each way with the swing
    "clavicle": 0.12,  # the collarbone's turn forward, as a share of the arm's swing
    "shrug": 0.0,  # degrees the collarbones are lifted
    "carry": 1.0,  # the share of the chest's tilt the arms take
    "curl": [24.0, 48.0, 58.0, 66.0, 72.0],  # the fingers' curl: thumb, index, middle, ring, little
    "finger_live": 4.0,  # degrees the fingers open as the arm swings back and close as it comes forward
    "thumb_out": 38.0,  # degrees the thumb is lifted from under the palm to lie beside it
    "uneven": 1.0,  # how far the two halves of the cycle differ in reach, lift and swing
    "left": {},  # a side's own number for any key of `SIDED`, over the one both sides share: no body
    "right": {},  # carries its two sides alike (`own-animation.md#feel`, no mirror poses)
    "hip_turn_rest": 0.0,  # degrees the pelvis stays turned to its left through the whole cycle
    "hip_tip_rest": 0.0,  # degrees its right side stays lower
    "chest_turn_rest": 0.0,  # degrees the chest stays turned to its left against the pelvis
    "chest_tip_rest": 0.0,  # degrees the right shoulder stays lower
    "head_turn_rest": 0.0,  # degrees the head stays turned to its left
    "head_tip_rest": 0.0,  # degrees it stays tilted to its right
    "speed_limit": 38.0,  # the largest change of a joint's speed in one frame the clip may have (degrees a frame)
    "keys_kept": 0.4,  # the share of a moving bone's keys a half-degree reducer may keep
    "kb_a_second": 20.0,  # the clip's key bytes for a second of clip (a short cycle has few frames to drop)
    "ranges": {},  # a measured number the variant holds to another range than the gait's, `{"cadence": [low, high]}`
}
DEFAULTS = {
    "walk": dict(COMMON),
    "jog": {
        **COMMON,
        "frames": 20,
        "speed": 4.0,
        "duty": 6 / 20,
        "ahead": 0.46,
        "width": 0.05,
        "toe_out": 4.0,
        "heel_strike": 6.0,
        "roll_in": 1.5,
        "toe_off": 62.0,
        "roll_out": 3.5,
        "kick": 0.18,
        "kick_at": 0.36,
        "carry_height": 0.07,
        "carry_at": 0.6,
        "land_from": 0.06,
        "land_speed": 0.5,
        "kick_pitch": 70.0,
        "swing_early": 0.35,
        "stretch": 0.985,
        "bob": 0.062,
        "takeoff_rise": 0.02,
        "sway": 0.008,
        "hip_turn": 6.0,
        "hip_turn_at": 0.3,
        "hip_tip": 4.0,
        "hip_tip_at": 0.16,
        "pelvis_pitch": 3.0,
        "lean": 4.0,
        "lean_live": 1.0,
        "counter_turn": 10.0,
        "arm_fore": 30.0,
        "arm_back": 42.0,
        "arm_at": 0.24,
        "arm_out": 12.0,
        "arm_out_back": 10.0,
        "arm_clear": 0.12,
        "arm_twist": 14.0,
        "elbow": 82.0,
        "elbow_live": 10.0,
        "pronate": 20.0,
        "wrist": 6.0,
        "wrist_live": 6.0,
        "clavicle": 0.15,
        "curl": [50.0, 150.0, 160.0, 168.0, 174.0],
        "finger_live": 5.0,
        "thumb_out": 30.0,
        "speed_limit": 55.0,
        "keys_kept": 0.75,
        "kb_a_second": 22.0,
    },
    "sprint": {
        **COMMON,
        "frames": 18,
        "speed": 6.5,
        "duty": 4 / 18,
        "ahead": 0.42,
        "width": 0.05,
        "toe_out": 3.0,
        "heel_strike": -14.0,
        "roll_in": 1.5,
        "toe_off": 66.0,
        "roll_out": 2.5,
        "stance_pitch": 5.0,
        "kick": 0.3,
        "kick_at": 0.34,
        "carry_height": 0.06,
        "carry_at": 0.6,
        "land_from": 0.07,
        "land_speed": 0.6,
        "kick_pitch": 78.0,
        "swing_early": 0.35,
        "stretch": 0.985,
        "bob": 0.05,
        "takeoff_rise": 0.02,
        "sway": 0.005,
        "hip_turn": 9.0,
        "hip_turn_at": 0.27,
        "hip_tip": 4.0,
        "hip_tip_at": 0.12,
        "pelvis_pitch": 4.0,
        "lean": 7.0,
        "lean_live": 1.2,
        "counter_turn": 13.0,
        "arm_fore": 46.0,
        "arm_back": 58.0,
        "arm_at": 0.24,
        "arm_out": 12.0,
        "arm_out_back": 10.0,
        "arm_clear": 0.12,
        "arm_twist": -4.0,
        "elbow": 92.0,
        "elbow_live": 20.0,
        "pronate": 18.0,
        "wrist": 4.0,
        "wrist_live": 7.0,
        "clavicle": 0.18,
        "shrug": 2.0,
        "curl": [45.0, 120.0, 130.0, 138.0, 144.0],
        "finger_live": 6.0,
        "thumb_out": 30.0,
        "speed_limit": 80.0,
        "keys_kept": 0.85,
        "kb_a_second": 26.0,
    },
}
## The clip each gait replaces, and the ranges its measured numbers are held to (`own-animation.md#feel`; the
## sources are in the README): steps a minute, the planted share of the cycle and the pelvis's rise and fall (mm).
GAITS = {
    "walk": ("ual1/Walk", {"cadence": (125.0, 140.0), "planted_share": (0.57, 0.62), "bob_mm": (30.0, 50.0)}),
    "jog": ("ual1/Jog_Fwd", {"cadence": (169.0, 187.0), "planted_share": (0.27, 0.36), "bob_mm": (60.0, 95.0)}),
    "sprint": ("ual1/Sprint", {"cadence": (190.0, 215.0), "planted_share": (0.2, 0.27), "bob_mm": (60.0, 100.0)}),
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
## The numbers a side may have of its own (`left`, `right`).
SIDED = (
    "ahead", "width", "toe_out", "kick", "carry_height", "arm_fore", "arm_back", "arm_out", "arm_out_back",
    "arm_twist", "arm_clear", "elbow", "elbow_live", "pronate", "wrist", "wrist_live", "shrug", "curl",
    "finger_live", "thumb_out",
)
FINGER_NAMES = ("thumb", "index", "middle", "ring", "pinky")
## How much further the right side goes than the left where the halves differ, at `uneven` 1: the right foot's
## reach (m), its lift in the swing (a share), the left arm's swing (a share), and a turn the pelvis keeps (degrees).
UNEVEN_REACH = 0.012
UNEVEN_LIFT = 0.1
UNEVEN_ARM = 0.08
UNEVEN_TURN = 1.0
## The bodies a gait's feet are set down for, beside the one it is solved on (`play_on`).
_OTHERS = []


def play_on(bodies: list) -> None:
    """Name every body the gaits play on. Their soles are not one shape (the male mannequin's toes are 24 mm
    longer and its heel is rounder), so a foot is set down where the lowest skin of all of them is nearest the
    floor, and lifted in its swing until the lowest of all of them clears it."""
    _OTHERS[:] = list(bodies)


def _through_spring(lag: float, overshoot: float, frames: int) -> tuple:
    """What the overlap pass's spring does to a swing of one period a cycle: the frames it is late by and the
    share of its size that is left. A description leads and enlarges a swing by these, so the swing that is
    played has the size and the timing the style gives it."""
    if lag <= 0.0:
        return 0.0, 1.0
    stiffness, damping = overlap.spring_numbers(lag, overshoot)
    omega = 2.0 * math.pi * FPS / frames
    real, imaginary = stiffness - omega * omega, damping * omega
    late = math.atan2(imaginary, real) / omega * FPS
    return late, stiffness / math.hypot(real, imaginary)


class Gait:
    """One gait's description for one rig and one set of numbers."""

    def __init__(self, rig, numbers: dict, lags: dict):
        self.rig, self.n = rig, numbers
        n = numbers
        self.frames = int(n["frames"])
        assert self.frames % 2 == 0, "a gait's cycle is an even number of frames"
        self.contact = n["duty"] * self.frames
        self.run = n["duty"] < 0.5
        assert n["roll_in"] + n["roll_out"] <= self.contact, "the foot's two rolls are longer than its contact"
        self.stride = n["speed"] * self.frames / FPS
        self.covered = n["speed"] * self.contact / FPS
        self.lags = lags
        self.base = 0.0
        for name in ("left", "right"):
            unknown = sorted(set(n[name]) - set(SIDED))
            assert not unknown, f"`{name}` sets {unknown}, which a side cannot have of its own"
        ## The pelvis's solved place on each whole frame, from the last pass of `settle_height`: where the
        ## build's own solve starts from.
        self._pelvis = {}
        ## Metres each ankle is raised on each whole frame so that the skin of the sole, as each body's mesh
        ## really bends, is on the floor while planted and over it in the swing (`settle_height`).
        self._set_down = {}
        falls = []
        for s, sign in SIDES:
            land = 0.0 if s == "l" else self.frames / 2.0
            place = self._place(s, sign, 0)
            falls.append(Footfall(s, land, land + self.contact, place, yaw=sign * self.own(s, "toe_out")))
        self.plan = ContactPlan(self.frames, falls, Travel.steady(n["speed"]))
        self._heights = self._height_curve()

    def own(self, s: str, key: str):
        """A number as one side has it: its own (`left`, `right`) or the one both share."""
        return self.n["left" if s == "l" else "right"].get(key, self.n[key])

    def late(self, part: str) -> float:
        """The frames a part of the overlap pass trails the part it hangs from, at this gait's pace."""
        return _through_spring(*self.lags.get(part, (0.0, 0.0)), self.frames)[0]

    # ---- the feet -----------------------------------------------------------------------------------------------

    def _land(self, s: str) -> float:
        return 0.0 if s == "l" else self.frames / 2.0

    def _place(self, s: str, sign: float, cycle: int) -> tuple:
        """Where the ball of a foot stands on the floor (x, z) in its contact of a cycle."""
        n = self.n
        reach = self.own(s, "ahead") * self.covered + (UNEVEN_REACH * n["uneven"] if s == "r" else 0.0)
        return (sign * self.own(s, "width"), n["speed"] * self._land(s) / FPS + reach + cycle * self.stride)

    def _stance(self, s: str, sign: float, cycle: int, t: float) -> dict:
        """A planted foot, `t` frames after it landed."""
        n, rig = self.n, self.rig
        sole = rig.sole[s]
        x, z = self._place(s, sign, cycle)
        ball = np.array([x, sole["floor"], z])
        yaw = sign * self.own(s, "toe_out")
        if t < n["roll_in"]:
            share = 1.0 - maths.smooth(t / n["roll_in"])
            if n["heel_strike"] >= 0.0:
                heel = ball + body_turn(0.0, yaw, 0.0) @ (sole["heel"] - sole["ball"])
                return self.plan.state(rig, s, "heel", heel, -n["heel_strike"] * share, yaw)
            pitch = n["stance_pitch"] + (-n["heel_strike"] - n["stance_pitch"]) * share
        elif t > self.contact - n["roll_out"]:
            share = maths.smooth((t - (self.contact - n["roll_out"])) / n["roll_out"])
            pitch = n["stance_pitch"] + (n["toe_off"] - n["stance_pitch"]) * share
        else:
            pitch = n["stance_pitch"]
        return self.plan.state(rig, s, "ball", ball, pitch, yaw)

    def _swing(self, s: str, sign: float, cycle: int, u: float) -> dict:
        """A foot in the air, the share `u` of the way from leaving the floor to landing in the next cycle."""
        n, rig = self.n, self.rig
        sole = rig.sole[s]
        a = self._stance(s, sign, cycle, self.contact)
        b = self._stance(s, sign, cycle + 1, 0.0)
        more = 1.0 + (UNEVEN_LIFT * n["uneven"] if s == "r" else 0.0)
        kick, carry = self.own(s, "kick"), self.own(s, "carry_height")
        go = (1.0 - n["swing_early"]) * maths.smooth(u) + n["swing_early"] * (1.0 - (1.0 - u) ** 2)
        # A foot brought to rest over the floor before it lands has to reach far past its landing place first
        # (the body goes on under it): a runner's still has some of its speed, and the landing takes it.
        still = n["land_speed"] * (self.stride - self.covered) / max(float(b["ankle"][2] - a["ankle"][2]), 1e-6)
        go = (1.0 - still) * go + still * u
        ankle = a["ankle"] + (b["ankle"] - a["ankle"]) * go
        lift = maths.keyed(
            [(0.0, 0.0), (n["kick_at"], kick * more), (n["carry_at"], carry * more), (1.0, 0.0)], u
        )
        ankle[1] += lift
        if n["land_from"] > 0.0:
            # The last of the way down is at one speed: a runner's foot meets the floor moving down, not level.
            swing = self.frames - self.contact
            ankle[1] += n["land_from"] * min(u * swing / n["leave_frames"], 1.0, (1.0 - u) * swing / n["land_frames"])
        pitch_a, pitch_b = a["foot"][0], b["foot"][0]
        pitch = maths.keyed(
            [(0.0, pitch_a), (n["kick_at"], max(n["kick_pitch"], pitch_a)), (0.86, 0.6 * pitch_b), (1.0, pitch_b)], u
        )
        yaw = sign * self.own(s, "toe_out")
        toe = a["toe"] * (1.0 - maths.smooth(u / 0.3))
        # Nothing of the sole goes under the floor while it swings: the toes hang under a foot whose heel is up.
        turn = body_turn(pitch, yaw, 0.0)
        hinge = ankle + turn @ (sole["hinge"] - sole["ankle"])
        tip = hinge + body_turn(pitch - toe, yaw, 0.0) @ (sole["toe"] - sole["hinge"])
        heel = ankle + turn @ (sole["heel"] - sole["ankle"])
        ball = ankle + turn @ (sole["ball"] - sole["ankle"])
        margin = 0.006 * maths.smooth(u / 0.15) * maths.smooth((1.0 - u) / 0.1)
        ankle[1] += max(sole["floor"] + margin - min(tip[1], heel[1], ball[1]), 0.0)
        return {"ankle": ankle, "foot": (pitch, yaw, 0.0), "toe": toe}

    def leg(self, s: str, sign: float, f: float) -> dict:
        since = f - self._land(s)
        cycle = math.floor(since / self.frames)
        t = since - cycle * self.frames
        if t <= self.contact:
            out = self._stance(s, sign, cycle, t)
        else:
            out = self._swing(s, sign, cycle, (t - self.contact) / (self.frames - self.contact))
        out["ankle"] = out["ankle"] + maths.Y * self._set_down.get((s, f), 0.0)
        return out

    def _sole_gaps(self, pose: dict, s: str) -> list:
        """How far the lowest skin of a foot is over each body's floor in a solved pose (m)."""
        gaps = []
        for body in [self.rig] + [one for one in _OTHERS if one.path != self.rig.path]:
            world = body.world(*body.arrays([pose]))
            skin = body.skin(world, (f"foot_{s}", f"ball_{s}", f"ball_leaf_{s}"))
            gaps.append(float(skin[0, :, 1].min()) - body.sole[s]["floor"])
        return gaps

    # ---- the weight ---------------------------------------------------------------------------------------------

    def _height_curve(self) -> list:
        """The centre of mass's height over one step, a number a tenth of a frame, about its lowest point's
        height plus half its rise and fall (so `base` is the middle of it)."""
        n = self.n
        step = self.frames / 2.0
        count = int(round(step * 10))
        if not self.run:
            # A walk: highest over the standing leg (the middle of a contact), lowest with both feet down.
            top = 0.5 * self.contact
            return [0.5 * n["bob"] * math.cos(2.0 * math.pi * (k / 10.0 - top) / step) for k in range(count)]
        contact, flight = self.contact / FPS, (step - self.contact) / FPS
        rise = n["takeoff_rise"]
        leave = -rise / flight + 0.5 * weight.G * flight
        arrive = leave - weight.G * flight
        assert leave > 0.0, "the take-off rise is more than the flight can fall"

        def height(k: int, sink: float) -> float:
            t = k / 10.0
            if t <= self.contact:
                s = t / self.contact
                s2, s3 = s * s, s * s * s
                caught = (s3 - 2 * s2 + s) * arrive * contact + (-2 * s3 + 3 * s2) * rise + (s3 - s2) * leave * contact
                return caught - sink * math.sin(math.pi * s) ** 2
            air = (t - self.contact) / FPS
            return rise + leave * air - 0.5 * weight.G * air * air

        low, high = 0.0, 0.3
        for _ in range(40):
            sink = 0.5 * (low + high)
            curve = [height(k, sink) for k in range(count)]
            low, high = (sink, high) if max(curve) - min(curve) < n["bob"] else (low, sink)
        assert max(curve) - min(curve) > n["bob"] - 1e-4, "the flight alone rises more than the bob asked for"
        middle = 0.5 * (max(curve) + min(curve))
        return [value - middle for value in curve]

    def centre(self, f: float) -> tuple:
        """Where the centre of mass is at a frame, in the world."""
        n = self.n
        step = self.frames / 2.0
        at = (f % step) * 10.0
        k = int(math.floor(at))
        a, b = self._heights[k % len(self._heights)], self._heights[(k + 1) % len(self._heights)]
        height = self.base + a + (b - a) * (at - k)
        # Over the foot that carries it in the middle of its contact: the left's is at half the contact.
        side = n["sway"] * math.cos(2.0 * math.pi * (f - 0.5 * self.contact) / self.frames)
        return (side, height, n["speed"] * f / FPS)

    # ---- the pose -----------------------------------------------------------------------------------------------

    def spec(self, f: float) -> dict:
        n = self.n
        p = f / self.frames
        turn = n["hip_turn"] * math.cos(2.0 * math.pi * (p - n["hip_turn_at"])) + UNEVEN_TURN * n["uneven"]
        turn += n["hip_turn_rest"]
        tip = n["hip_tip"] * math.cos(2.0 * math.pi * (p - n["hip_tip_at"]))
        nod = n["lean_live"] * math.cos(4.0 * math.pi * (p - 0.5 * n["duty"]) + math.pi)
        side, height, ahead = self.centre(f)
        arms, fingers, clavicle = {}, {}, {}
        late, left = _through_spring(*self.lags.get("upperarm", (0.0, 0.0)), self.frames)
        # The chest's turn trails the hips' by the style's frames. Its three bones pass a part of that on by
        # themselves (each follows the bone under it, which carries the pelvis's turn too); the rest is written.
        against = n["counter_turn"] / max(n["hip_turn"], 1e-6)
        chest_lag = self.lags.get("chest", (0.0, 0.0))[0]
        chest_late = chest_lag * (1.0 - (2.0 * against - 1.0) / (3.0 * against))
        for s, sign in SIDES:
            at = n["arm_at"] + (0.0 if s == "l" else 0.5)
            wide = 1.0 + (UNEVEN_ARM * n["uneven"] if s == "l" else 0.0)
            o = {key: self.own(s, key) for key in SIDED}
            middle = 0.5 * (o["arm_fore"] - o["arm_back"])
            reach = 0.5 * (o["arm_fore"] + o["arm_back"]) * wide
            swing = math.cos(2.0 * math.pi * (p - at) + 2.0 * math.pi * late / self.frames)
            # The elbow and the wrist give with the swing as it is played; the overlap pass makes them late.
            played = math.cos(2.0 * math.pi * (p - at))
            arms[s] = {
                "swing": middle + reach / left * swing,
                "out": o["arm_out"] + o["arm_out_back"] * (0.5 - 0.5 * played),
                # The forearm turns in toward the body's middle as it comes forward, and hangs beside the hip.
                "twist": o["arm_twist"] * (0.5 + 0.5 * played),
                "bend": o["elbow"] + o["elbow_live"] * played,
                "pronate": o["pronate"],
                "wrist": o["wrist"] - o["wrist_live"] * played,
                "carry": n["carry"],
            }
            if o["arm_clear"] > 0.0:
                arms[s]["clear"] = o["arm_clear"]
            clavicle[s] = (o["shrug"], n["clavicle"] * reach * swing)
            curls = {
                finger: o["curl"][i] + o["finger_live"] * played * (0.5 if finger == "thumb" else 1.0)
                for i, finger in enumerate(FINGER_NAMES)
            }
            curls["thumb_out"] = o["thumb_out"]
            fingers[s] = curls
        return {
            "pelvis": {
                "place": self._pelvis.get(f, np.array([side, height - 0.1, ahead - 0.02])).copy(),
                "turn": (n["pelvis_pitch"], turn, -tip - n["hip_tip_rest"]),
            },
            "chest": (
                n["lean"] + nod,
                -n["counter_turn"] * math.cos(2.0 * math.pi * (p - n["hip_turn_at"] - chest_late / self.frames))
                + n["chest_turn_rest"],
                n["counter_tip"] * tip - n["chest_tip_rest"],
            ),
            "head": (n["head_pitch"], n["head_turn_rest"], -n["head_tip_rest"]),
            "clavicle": clavicle,
            "arm": arms,
            "fingers": fingers,
            "leg": {s: self.leg(s, sign, f) for s, sign in SIDES},
        }

    # ---- how high the body rides ---------------------------------------------------------------------------------

    def settle_height(self) -> None:
        """Set `base`, the middle of the centre of mass's rise and fall, as high as the legs allow: the leg that
        is stretched furthest, on any frame, is `stretch` of its full length."""
        rig, n = self.rig, self.n
        solver = Solver(rig)
        self.base = rig.rest_pos["pelvis"][1] + 0.02
        for _ in range(10):
            drop, moved = -math.inf, 0.0
            fixes = dict(self._set_down)
            for f in range(self.frames):
                spec = self.spec(float(f))
                pose = weight.settle(solver, spec, self.centre(float(f)), rounds=6)
                self._pelvis[float(f)] = pose["pelvis"].copy()
                turn = rig.rest_rot[rig.parent["pelvis"]] @ pose["local"]["pelvis"] @ rig.rest_rot["pelvis"].T
                for s, _ in SIDES:
                    hip = pose["pelvis"] + turn @ (rig.rest_pos["thigh_" + s] - rig.rest_pos["pelvis"])
                    to = np.asarray(spec["leg"][s]["ankle"], dtype=float) - hip
                    want = n["stretch"] * (rig.length["thigh_" + s] + rig.length["calf_" + s])
                    level = math.hypot(to[0], to[2])
                    drop = max(drop, 0.08 if level >= want else -math.sqrt(want * want - level * level) - to[1])
                    gaps = self._sole_gaps(pose, s)
                    t = (f - self._land(s)) % self.frames
                    if t <= self.contact:
                        change = -0.5 * (max(gaps) + min(gaps))
                    else:
                        u = (t - self.contact) / (self.frames - self.contact)
                        clear = 0.004 * maths.smooth(u / 0.15) * maths.smooth((1.0 - u) / 0.1)
                        change = max(clear - min(gaps), -fixes.get((s, float(f)), 0.0))
                        change = change if change > 0.0 or fixes.get((s, float(f)), 0.0) > 0.0 else 0.0
                    fixes[(s, float(f))] = fixes.get((s, float(f)), 0.0) + change
                    moved = max(moved, abs(change))
            self._set_down = fixes
            self.base -= drop
            for place in self._pelvis.values():
                place[1] -= drop
            if abs(drop) < 1e-4 and moved < 1e-4:
                break


def describe(kind: str, rig, style, name: str) -> Clip:
    n = style.numbers(kind, DEFAULTS[kind])
    lags = style.overlap(kind)
    gait = Gait(rig, n, {part: tuple(value) for part, value in lags.items()})
    gait.settle_height()
    replaces, ranges = GAITS[kind]
    return Clip(
        name=name,
        frames=gait.frames,
        plan=gait.plan,
        spec=lambda f: gait.spec(float(f)),
        balance=lambda f, at: gait.centre(float(f)),
        chains=overlap.chains_from(lags, PARTS),
        kind="gait",
        declared={
            "ranges": {key: tuple(n["ranges"].get(key, value)) for key, value in ranges.items()},
            "lags": {
                **{part: round(gait.late(part), 2) for part in ("forearm", "hand") if part in lags},
                **({"chest": lags["chest"][0]} if "chest" in lags else {}),
            },
            "distance": gait.stride,
            "speed_limit": n["speed_limit"],
            "keys_kept": n["keys_kept"],
            "kb_a_second": n["kb_a_second"],
        },
        replaces=replaces,
        style=style.letter,
    )


def walk(rig, style, name: str = "Walk") -> Clip:
    return describe("walk", rig, style, name)


def jog(rig, style, name: str = "Jog") -> Clip:
    return describe("jog", rig, style, name)


def sprint(rig, style, name: str = "Sprint") -> Clip:
    return describe("sprint", rig, style, name)
