"""The starts and the stops of the three gaits (kit #1156). New: the library has neither.

`Idle_To_Walk`, `Idle_To_Jog`, `Idle_To_Sprint`, each stepping off with the left (`_L`) and with the right foot
(`_R`); `Walk_Stop`, `Jog_Stop`, `Sprint_Stop`, each beginning as the left or the right foot strikes. The game
cross-faded for 0.15 s between the idle and a gait, poses 436 to 685 mm apart, so the body snapped into and out of
motion. These clips are the change of speed itself (the research and its sources are in `../README.md`):

- **A start is its footfalls and its speed.** The root's speed rises from nothing to the gait's on a curve whose
  steepest point is the style's; the feet take a few steps of their own lengths and times (short, long on the
  floor and hardly in the air at first), and the last two landings are the gait's own, so the clip ends on the
  shipped gait's pose and speed as one of its feet strikes. Every foot has left its standing place by then: the
  idle's feet stand wider and turned out otherwise than a gait's land.
- **A stop is the same read backward, with its own feet.** It begins on the gait's pose as a foot strikes; the
  feet brake over one to four more landings, each further ahead of the body than a steady step, the last two on
  the idle's own places, and the body settles onto the shipped idle's first pose.
- **The body leans by its acceleration.** While it speeds up the feet land behind where a steady step would put
  them and the trunk pitches forward by a share of `atan(a / g)`; while it brakes they land ahead and the trunk
  comes back. The lean follows the acceleration through a spring, so it arrives late and swings a little past.
- **The carriage goes from the one clip's to the other's.** The pelvis's place over the root, the trunk's wind,
  the arms and the hands are mixed from the shipped idle's first frame to the shipped gait's at the phase the feet
  are in, on the style's own window; the gait's phase is a clock that passes through every landing, so each arm
  still swings with the other side's leg while the steps are not yet the gait's.
- **Left and right are two clips, not one and its mirror.** The gaits and the idle have a number per side, so the
  clip that steps off with the right foot is solved on its own: from the idle, which stands on its left leg, the
  right foot is free at once and the left has to be unloaded first.
- **The feet are set down on the skin** of the bodies the gaits are set down for (`gait.play_on`), frame by
  frame, as a gait's are; the plan's own settle is off (`ContactPlan.tread`).
"""

import math
from dataclasses import dataclass

import numpy as np

from gdsanim import maths, overlap, weight
from gdsanim.build import Clip
from gdsanim.maths import FPS, body_turn
from gdsanim.plan import ContactPlan, Footfall, Travel
from gdsanim.rig import SIDES
from gdsanim.solve import Solver

from . import gait as gaits
from .stance import mix, plain_arm, skewed

SIGN = dict(SIDES)
OTHER = {"l": "r", "r": "l"}
AT = {"l": 0, "r": 1}
## A slow step's foot: what a landing's numbers are mixed from, toward the gait's own, by how far the step is the
## gait's (`gait_like`). The keys are `clips/gait.py`'s.
SLOW = {
    "heel_strike": 8.0,
    "roll_in": 3.0,
    "toe_off": 38.0,
    "roll_out": 5.0,
    "stance_pitch": 0.0,
    "kick": 0.02,
    "kick_at": 0.3,
    "carry_height": 0.025,
    "carry_at": 0.62,
    "land_from": 0.0,
    "leave_frames": 1.5,
    "land_frames": 2.0,
    "kick_pitch": 30.0,
    "swing_early": 0.0,
    "swing_ease": 1.0,
    "land_speed": 0.0,
}
## The fastest the centre of mass may drop with a foot on the floor, as a share of gravity (the check's limit is 1.05).
FALL_MOST = 0.9
## What each number of a style's `idle_to_walk`, `idle_to_jog` or `idle_to_sprint` section means. A pair is the
## clip that steps off with the left foot, then the one that steps off with the right.
START = {
    "prep": [10, 7],  # frames the body gathers before the first foot leaves the floor
    "shift": [0.05, 0.012],  # metres the hips go over the standing foot first
    "swing": 12,  # frames the first foot is in the air
    "steps": [13],  # frames from each landing to the next; the last is the gait's own half cycle
    "air": [2],  # frames each foot stays down after the next has landed; under 0 the body is in the air
    "gait_like": [0.6, 1.0],  # how far each landing's foot is the gait's (0: a slow, flat step)
    "push_from": [3, 1],  # the frame the root begins to move
    "lever": 0.1,  # metres behind the centre of mass the feet come to press (the heels), which starts the fall forward
    "lever_frames": 5,  # frames that takes
    "push_most": 3.0,  # m/s2 the body speeds up by at most (before the curve is scaled to the clip's length)
    "push_end": 2,  # frames after the last landing but one the gait's speed is reached
    "drive": 1.0,  # the share of the acceleration's lean the feet take: they land that far behind a steady step
    "lean": 0.7,  # the share the chest takes, as pitch
    "lean_hips": 0.3,  # and the pelvis
    "lean_head": 0.25,  # and the head
    "lean_fore": 0.1,  # the share of the lean the hips take by going ahead of the root (the feet stay behind)
    "lean_low": 0.08,  # and the share by which they come down, so the legs that push from behind can reach the floor
    "lean_lag": [2.0, 0.1],  # the lean follows the acceleration through a spring: frames late, share past
    "dip": 0.015,  # metres the hips sink as the body gathers
    "bob": 0.6,  # the share of the gait's rise and fall the steps that are not yet the gait's have
    "body": [0.1, 0.9],  # the shares of the clip between which the carriage goes from the idle's to the gait's
    "body_turn": 0.5,  # where in that window it changes fastest (0.5: evenly)
    "arms": [0.05, 0.8],  # the same for the arms and the hands
    "arms_free": 0.0,  # how far the arms' keeping clear of the thighs is let go in the middle of the change
    "first_clear": 0.035,  # metres the first step's foot clears the floor by
    "heel_early": 0.5,  # the share of a contact of the clip's own over which the heel comes up
    "reach_fore": 0.42,  # metres ahead of the root a foot lands at most
    "reach_back": 0.45,  # metres behind the root a foot is at most as it leaves
    "stretch": 0.995,  # the share of its length a leg may be stretched to
    "meet": 3,  # frames over which what the overlap pass left in the joined clips is let go
    "speed_limit": 40.0,  # the largest change of a joint's speed in one frame (degrees a frame)
    "lean_limit": 8.0,  # degrees the lean, averaged over a step, may be from the acceleration's
    "keys_kept": 0.9,
    "kb_a_second": 40.0,
}
STARTS = {
    "walk": dict(START),
    "jog": {
        **START,
        "prep": [6, 4],
        "swing": 9,
        "steps": [10, 9, 10],
        "air": [1, -1, -3],
        "gait_like": [0.3, 0.6, 0.9, 1.0],
        "lean_limit": 12.0,
        "push_most": 4.0,
        "lean_fore": 0.25,
        "lean_low": 0.15,
        "reach_back": 0.4,
        "dip": 0.03,
        "lean": 0.6,
        "speed_limit": 55.0,
    },
    "sprint": {
        **START,
        "prep": [5, 3],
        "swing": 8,
        "steps": [9, 9, 9, 9, 9],
        "air": [1, -2, -4, -5, -5],
        "gait_like": [0.3, 0.5, 0.7, 0.85, 1.0, 1.0],
        "heel_early": 0.6,
        "stretch": 0.99,
        "lean_limit": 20.0,
        "push_most": 5.0,
        "lean_fore": 0.25,
        "lean_low": 0.15,
        "reach_back": 0.4,
        "dip": 0.045,
        "lean": 0.6,
        "body": [0.05, 0.8],
        "arms": [0.02, 0.6],
        "speed_limit": 80.0,
    },
}
## The same for `walk_stop`, `jog_stop` and `sprint_stop`.
STOP = {
    "steps": [11, 11],  # frames from the strike the clip begins on to the next landing, and on to each one after
    "air": [3],  # frames each foot stays down after the next has landed; under 0 the body is in the air
    "gait_like": [0.5, 0.0],  # how far each landing's foot is the gait's (0: a slow, flat step)
    "settle": 10,  # frames after the last landing: the trunk, the arms and the head come to rest
    "brake_from": 1,  # the frame the root begins to slow
    "halt": 4,  # frames after the last landing but one the root is at rest
    "brake_in": 0.2,  # the share of the braking over which it comes on
    "brake_out": 0.45,  # and the share over which it eases to rest
    "drive": 1.0,  # the share of the braking's lean the feet take: they land that far ahead of a steady step
    "lean": 0.4,  # the share the chest takes, as pitch
    "lean_hips": 0.15,
    "lean_head": 0.1,
    "lean_fore": 0.15,  # the share of the lean the hips take by staying behind the root (the feet go ahead)
    "lean_low": 0.12,  # and the share by which they come down
    "lean_lag": [2.0, 0.2],  # the lean follows the braking through a spring: frames late, share past
    "dip": 0.02,  # metres the hips sink as the legs take the stop
    "dip_at": 2,  # frames after the root is at rest the hips are lowest
    "bob": 0.5,  # the share of the gait's rise and fall the steps after the first have
    "body": [0.1, 0.85],  # the shares of the clip between which the carriage goes from the gait's to the idle's
    "body_turn": 0.5,
    "arms": [0.2, 0.95],
    "arms_free": 0.0,
    "close_clear": 0.03,  # metres the last step's foot clears the floor by
    "heel_early": 0.45,
    "reach_fore": 0.5,
    "reach_back": 0.4,
    "stretch": 0.995,
    "meet": 3,
    "speed_limit": 40.0,
    "lean_limit": 8.0,
    "keys_kept": 0.9,
    "kb_a_second": 40.0,
}
STOPS = {
    "walk": {**STOP, "steps": [12, 11], "halt": 6, "lean_limit": 10.0},
    "jog": {
        **STOP,
        "steps": [10, 10, 10, 10],
        "air": [-4, -3, 3],
        "gait_like": [0.8, 0.5, 0.2, 0.0],
        "lean_limit": 17.0,
        "halt": 2,
        "dip": 0.035,
        "speed_limit": 55.0,
    },
    "sprint": {
        **STOP,
        "steps": [9, 9, 9, 10, 10, 10],
        "air": [-5, -5, -4, -2, 3],
        "gait_like": [0.9, 0.75, 0.55, 0.35, 0.15, 0.0],
        "lean_limit": 16.0,
        "stretch": 0.99,
        "halt": 2,
        "dip": 0.05,
        "speed_limit": 80.0,
    },
}


@dataclass
class Tread:
    """One contact of one foot, with the numbers of the swing that lands it."""

    side: str
    land: float
    lift: float
    place: tuple
    yaw: float
    foot: dict
    swing: dict
    ## Metres a second the root travels at as the foot lands.
    ground: float = 0.0
    ## A foot that stands as the idle's does: flat, not set down again by its skin.
    standing: bool = False


def picked_gait(rig, joined, kind: str) -> tuple:
    """The shipped gait as its description (`gait.Gait`, settled) and its overlap numbers, made once."""
    made = joined.__dict__.setdefault("_move_gaits", {})
    if kind not in made:
        one = joined.style(kind.capitalize())
        lags = one.overlap(kind)
        g = gaits.Gait(rig, one.numbers(kind, gaits.DEFAULTS[kind]), {part: tuple(v) for part, v in lags.items()})
        g.settle_height()
        made[kind] = (g, lags)
    return made[kind]


def clock(knots: list, f: float, first: float | None = None, last: float | None = None) -> float:
    """A rising curve through `knots` (`[(frame, value), ...]`) with the slope `first` at its first knot and
    `last` at its last (None: the slope of the nearest span); straight on past either end."""
    xs, ys = [k[0] for k in knots], [k[1] for k in knots]
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(len(xs) - 1)]
    m = [d[0] if first is None else first]
    for i in range(1, len(xs) - 1):
        m.append(0.0 if d[i - 1] * d[i] <= 0.0 else 2.0 * d[i - 1] * d[i] / (d[i - 1] + d[i]))
    m.append(d[-1] if last is None else last)
    if f <= xs[0]:
        return ys[0] + m[0] * (f - xs[0])
    if f >= xs[-1]:
        return ys[-1] + m[-1] * (f - xs[-1])
    i = max(j for j in range(len(xs) - 1) if xs[j] <= f)
    h = xs[i + 1] - xs[i]
    t = (f - xs[i]) / h
    t2, t3 = t * t, t * t * t
    return (
        (2 * t3 - 3 * t2 + 1) * ys[i]
        + (t3 - 2 * t2 + t) * m[i] * h
        + (-2 * t3 + 3 * t2) * ys[i + 1]
        + (t3 - t2) * m[i + 1] * h
    )


def _soft(values: np.ndarray, sigma: float) -> np.ndarray:
    """A curve smoothed over `sigma` frames, its ends held."""
    reach = int(math.ceil(3 * sigma))
    kernel = np.exp(-0.5 * (np.arange(-reach, reach + 1) / sigma) ** 2)
    padded = np.concatenate([np.full(reach, values[0]), values, np.full(reach, values[-1])])
    return np.convolve(padded, kernel / kernel.sum(), mode="valid")


class Move:
    """A start or a stop of one gait, on one foot, for one rig and one set of numbers."""

    def __init__(self, rig, joined, kind: str, start: bool, side: str, numbers: dict):
        self.rig, self.kind, self.start, self.side, self.n = rig, kind, start, side, numbers
        self.g, self.lags = picked_gait(rig, joined, kind)
        g, n = self.g, numbers
        self.cycle, self.half, self.contact, self.v = g.frames, g.frames // 2, g.contact, g.n["speed"]
        idle = joined.start("Idle")
        self.idle = idle["spec"]
        self.idle_falls = {fall.side: fall for fall in joined.clip("Idle").plan.footfalls}
        self.idle_arms = {s: plain_arm(self.idle["arm"][s]) for s, _ in SIDES}
        ## The gait's pelvis over its root on each whole frame of its cycle.
        self.rel = np.array(
            [g._pelvis[float(k)] - np.array([0.0, 0.0, self.v * k / FPS]) for k in range(self.cycle)]
        )
        self._middle = float(self.rel[:, 1].mean())
        steps = [int(x) for x in n["steps"]]
        self.landings = len(steps) + 1 if start else len(steps)
        assert len(n["air"]) == self.landings - 1, "`air` has a number for every foot that leaves the floor again"
        assert len(n["gait_like"]) == self.landings, "`gait_like` has a number for every landing"
        if start:
            assert steps[-1] == self.half, "a start's last step is the gait's own half cycle"
            lift = int(n["prep"][AT[side]])
            self.lands = [lift + int(n["swing"])]
            for step in steps:
                self.lands.append(self.lands[-1] + step)
            self.frames = self.lands[-1]
            self.first_lift = lift
            ## The side that strikes as the clip ends, and the gait's frame there.
            self.strike = side if self.landings % 2 == 1 else OTHER[side]
        else:
            self.lands = list(np.cumsum(steps))
            self.frames = int(self.lands[-1] + int(n["settle"]))
            self.strike = side
        self.phase = 0 if self.strike == "l" else self.half
        self._travel()
        self._treads()
        self._clock()
        ## Metres the pelvis is lowered on each frame so no leg is stretched past `stretch`, and metres each ankle
        ## is raised so the sole's skin is on the floor (`settle`).
        self.lower = np.zeros(self.frames + 1)
        ## Metres the pelvis is moved up or down on each frame so the centre of mass never drops faster than a
        ## body falls while a foot is on the floor (`settle`).
        self.level = np.zeros(self.frames + 1)
        self.set_down = {}
        self._specs = {}

    # ---- the root ------------------------------------------------------------------------------------------------

    def _travel(self) -> None:
        """The root's speed, a number a tenth of a frame, and its travel and acceleration from it.

        A start speeds up as a body can: standing, it can only fall forward over its feet, so its acceleration is
        `g / h` times how far the centre of mass is ahead of where the feet press (`lever` at first, the heels,
        and then as far as it has travelled), up to `push_most`, which stepping feet that land behind the body
        can keep up. That curve is scaled until the gait's speed is reached at `push_end` frames from the last
        landing but one, and its last quarter is eased. A stop brakes at once (the foot that strikes is ahead of
        the body), holds, and eases to rest."""
        n, count = self.n, self.frames * 10 + 1
        t = np.arange(count) / 10.0
        dt = 0.1 / FPS
        self.h = 1.1 * float(self.rig.rest_pos["pelvis"][1])
        if self.start:
            a = float(n["push_from"][AT[self.side]])
            b = float(self.lands[-2] + n["push_end"])
            assert a >= 1.0 and b <= self.frames - 1, "the root is still on the first frame and at speed on the last"
            ease = 0.6

            def run(scale: float) -> np.ndarray:
                raw, x = np.zeros(count), 0.0
                for i in range(1, count):
                    lever = n["lever"] * maths.smooth((t[i] - a) / max(n["lever_frames"], 1e-6))
                    push = min(weight.G / self.h * (x + lever), n["push_most"]) if t[i] > a else 0.0
                    raw[i] = raw[i - 1] + scale * push * dt
                    x += raw[i] * dt
                return raw

            low, high = 0.01, 50.0
            at = int(round(b * 10))
            for _ in range(50):
                scale = 0.5 * (low + high)
                low, high = (scale, high) if run(scale)[at] < (2.0 - ease) * self.v else (low, scale)
            self.push = scale
            y = run(scale) / self.v
            soft = np.where(y < ease, y, y - (y - ease) ** 2 / (4.0 * (1.0 - ease)))
            speed = self.v * np.where(y >= 2.0 - ease, 1.0, soft)
        else:
            a = float(n["brake_from"])
            b = float(self.lands[-2] + n["halt"]) if self.landings > 1 else float(self.lands[-1])
            assert a >= 1.0 and b <= self.frames - 1, "the root is at speed on the first frame and still on the last"
            rise, fall = n["brake_in"], n["brake_out"]
            u = np.clip((t - a) / (b - a), 0.0, 1.0)
            brake = np.array([maths.smooth(x / rise) * maths.smooth((1.0 - x) / fall) for x in u])
            brake[(t <= a) | (t >= b)] = 0.0
            done = np.cumsum(brake)
            speed = self.v * (1.0 - done / done[-1])
            self.halt = b
        self._t, self._speed = t, speed
        self._x = np.concatenate([[0.0], np.cumsum(0.5 * (speed[1:] + speed[:-1])) / (10.0 * FPS)])
        self._accel = np.gradient(speed) * 10.0 * FPS
        lag, past = n["lean_lag"]
        whole = [math.degrees(math.atan2(self.accel(float(f)), weight.G)) for f in range(self.frames + 1)]
        self._lean = np.array(overlap.follow(whole, lag, past, False))
        # Nothing of the lean is left where the clip joins another.
        for f in range(self.frames + 1):
            self._lean[f] *= maths.smooth(f / 3.0) * maths.smooth((self.frames - f) / 3.0)

    def x(self, f: float) -> float:
        """Metres the root has travelled at a frame; before and after the clip it goes on at the speed it has."""
        if f <= 0.0:
            return self._speed[0] * f / FPS
        if f >= self.frames:
            return self._x[-1] + self._speed[-1] * (f - self.frames) / FPS
        return float(np.interp(f, self._t, self._x))

    def speed(self, f: float) -> float:
        return float(np.interp(f, self._t, self._speed))

    def accel(self, f: float) -> float:
        return float(np.interp(f, self._t, self._accel))

    def lean(self, f: float) -> float:
        return float(np.interp(f, np.arange(self.frames + 1), self._lean))

    # ---- the feet ------------------------------------------------------------------------------------------------

    def _numbers(self, s: str, like: float) -> dict:
        """A landing's foot and swing numbers: the gait's own for that side at `like` 1, a slow step's at 0."""
        g = self.g
        own = {key: (g.own(s, key) if key in gaits.SIDED else g.n[key]) for key in SLOW}
        if like >= 1.0:
            return own
        return {key: SLOW[key] + (own[key] - SLOW[key]) * like for key in SLOW}

    def _reach(self, s: str) -> float:
        """Metres ahead of the root the gait lands the ball of a foot."""
        g = self.g
        return g.own(s, "ahead") * g.covered + (gaits.UNEVEN_REACH * g.n["uneven"] if s == "r" else 0.0)

    def _own_tread(self, s: str, land: float, root: float, lift: float | None = None) -> Tread:
        """A contact of the gait itself, landing at a frame where the gait's root would be at `root`."""
        g = self.g
        numbers = self._numbers(s, 1.0)
        place = (SIGN[s] * g.own(s, "width"), root + self._reach(s))
        end = land + self.contact if lift is None else lift
        return Tread(s, land, end, place, SIGN[s] * g.own(s, "toe_out"), numbers, numbers, self.v)

    def _free_tread(self, s: str, land: float, lift: float, like: float) -> Tread:
        """A step of the clip's own: where a steady step at the root's speed would land, moved by the lean."""
        g, n = self.g, self.n
        numbers = self._numbers(s, like)
        covered = self.x(lift) - self.x(land)
        back = n["drive"] * self.h * self.accel(0.5 * (land + lift)) / weight.G
        ahead = g.own(s, "ahead") * covered + (gaits.UNEVEN_REACH * g.n["uneven"] * like if s == "r" else 0.0)
        # No further behind the body as it leaves than a leg reaches, and no further ahead as it lands.
        ahead = min(max(ahead - back, covered - n["reach_back"]), n["reach_fore"])
        back = 0.0
        idle = self.idle_falls[s]
        wide = abs(idle.place[0]) + (g.own(s, "width") - abs(idle.place[0])) * like
        yaw = idle.yaw + (SIGN[s] * g.own(s, "toe_out") - idle.yaw) * like
        # A foot that stays down while the body goes on over it lets its heel come up early: the shin cannot fold
        # forward over a flat foot past what an ankle gives.
        room = max(lift - land - numbers["roll_in"], 0.0)
        numbers["roll_out"] = min(max(numbers["roll_out"], n["heel_early"] * (lift - land)), room)
        return Tread(s, land, lift, (SIGN[s] * wide, self.x(land) + ahead - back), yaw, numbers, numbers, self.speed(land))

    def _idle_tread(self, s: str, land: float, lift: float, root: float, like: float, toe_off: float) -> Tread:
        """A foot on its standing place, the idle's, with the root at `root`."""
        fall = self.idle_falls[s]
        numbers = self._numbers(s, like)
        numbers.update(heel_strike=SLOW["heel_strike"] * (1.0 if land > 0 else 0.0), stance_pitch=0.0, toe_off=toe_off)
        numbers["roll_in"] = SLOW["roll_in"] if land > 0 else 0.0
        room = max(lift - land - numbers["roll_in"], 0.0)
        early = max(numbers["roll_out"] + 1.5, self.n["heel_early"] * (lift - land))
        numbers["roll_out"] = min(early, room) if toe_off else 0.0
        place = (fall.place[0], fall.place[1] + root)
        return Tread(s, land, lift, place, fall.yaw, numbers, numbers, self.speed(max(land, 0.0)), standing=True)

    def _treads(self) -> None:
        n, F = self.n, float(self.frames)
        a, b = self.side, OTHER[self.side]
        like = [float(x) for x in n["gait_like"]]
        air = [float(x) for x in n["air"]]
        treads = {"l": [], "r": []}
        self.ghost = None
        if self.start:
            m = self.landings
            sides = [a if i % 2 == 0 else b for i in range(m)]
            # Where the gait's root would be at a frame, were the clip's last frames the gait's own.
            root = lambda f: self.x(F) + self.v * (f - F) / FPS  # noqa: E731
            first = self._numbers(a, like[0])
            treads[a].append(self._idle_tread(a, 0.0, float(self.first_lift), 0.0, like[0], 0.6 * first["toe_off"]))
            second = self._numbers(b, like[min(1, m - 1)])
            treads[b].append(self._idle_tread(b, 0.0, self.lands[0] + air[0], 0.0, like[0], 0.85 * second["toe_off"]))
            for i in range(m):
                s, land = sides[i], float(self.lands[i])
                if i >= m - 2:
                    tread = self._own_tread(s, land, root(land))
                    tread.swing = self._numbers(s, like[i])
                else:
                    tread = self._free_tread(s, land, self.lands[i + 1] + air[i + 1], like[i])
                treads[s].append(tread)
            # The first step is low: the foot is put forward, not swung.
            treads[a][1].swing = {**treads[a][1].swing, "clear": float(n["first_clear"])}
            # The landing after the clip's end, the gait's own: the foot in the air as the clip ends is on its way to it.
            last = OTHER[self.strike]
            treads[last].append(self._own_tread(last, F + self.half, root(F + self.half)))
            treads[self.strike].append(self._own_tread(self.strike, F + self.cycle, root(F + self.cycle)))
        else:
            m = self.landings
            sides = [b if i % 2 == 0 else a for i in range(m)]
            root = lambda f: self.v * f / FPS  # noqa: E731
            lifts = [self.lands[i] + air[i] for i in range(m - 1)]
            # The contacts the gait is in as the clip begins, and the ones before them (the overlap pass's lead-in).
            for back in (2, 1):
                treads[a].append(self._own_tread(a, -back * self.cycle, root(-back * self.cycle)))
                treads[b].append(self._own_tread(b, -back * self.cycle - self.half, root(-back * self.cycle - self.half)))
            treads[b].append(self._own_tread(b, -self.half, root(-self.half)))
            strike = self._own_tread(a, 0.0, 0.0, lift=float(lifts[0]))
            strike.foot = dict(strike.foot)
            slow = self._numbers(a, like[0])
            strike.foot["roll_out"] = min(slow["roll_out"] + 1.0, lifts[0] - strike.foot["roll_in"])
            strike.foot["toe_off"] = slow["toe_off"]
            treads[a].append(strike)
            end = self.x(F)
            for i in range(m):
                s, land = sides[i], float(self.lands[i])
                if i >= m - 2:
                    tread = self._idle_tread(s, land, F, end, like[i], 0.0)
                else:
                    tread = self._free_tread(s, land, float(lifts[i + 1]), like[i])
                treads[s].append(tread)
            treads[sides[-1]][-1].swing = {**treads[sides[-1]][-1].swing, "clear": float(n["close_clear"])}
            if self.contact < self.half:
                # A run: the other foot is in the air as the clip begins, on its way to the gait's next landing.
                self.ghost = self._own_tread(b, float(self.half), root(float(self.half)))
        self.treads = treads

    def _state(self, s: str, pivot: str, at: np.ndarray, pitch: float, yaw: float) -> dict:
        return self.g.plan.state(self.rig, s, pivot, at, pitch, yaw)

    def _stance(self, tread: Tread, f: float) -> dict:
        """A planted foot at a frame (`gait.Gait._stance`, with the tread's own numbers)."""
        s, n = tread.side, tread.foot
        sole = self.rig.sole[s]
        t, contact = f - tread.land, tread.lift - tread.land
        ball = np.array([tread.place[0], sole["floor"], tread.place[1]])
        if t < n["roll_in"]:
            share = 1.0 - maths.smooth(t / n["roll_in"])
            if n["heel_strike"] >= 0.0:
                heel = ball + body_turn(0.0, tread.yaw, 0.0) @ (sole["heel"] - sole["ball"])
                return self._state(s, "heel", heel, -n["heel_strike"] * share, tread.yaw)
            pitch = n["stance_pitch"] + (-n["heel_strike"] - n["stance_pitch"]) * share
        elif n["roll_out"] > 0.0 and t > contact - n["roll_out"]:
            share = maths.smooth((t - (contact - n["roll_out"])) / n["roll_out"])
            pitch = n["stance_pitch"] + (n["toe_off"] - n["stance_pitch"]) * share
        else:
            pitch = n["stance_pitch"]
        return self._state(s, "ball", ball, pitch, tread.yaw)

    def _swing(self, a: Tread, b: Tread, f: float) -> dict:
        """A foot in the air between two contacts (`gait.Gait._swing`, with the landing's own numbers)."""
        s, n, g = a.side, b.swing, self.g
        sole = self.rig.sole[s]
        frames = b.land - a.lift
        u = (f - a.lift) / frames
        one, two = self._stance(a, a.lift), self._stance(b, b.land)
        more = 1.0 + (gaits.UNEVEN_LIFT * g.n["uneven"] if s == "r" else 0.0)
        eased = (1.0 - n["swing_ease"]) * maths.smooth(u) + n["swing_ease"] * maths.smoother(u)
        go = (1.0 - n["swing_early"]) * eased + n["swing_early"] * (1.0 - (1.0 - u) ** 2)
        gap = max(float(two["ankle"][2] - one["ankle"][2]), 1e-6)
        still = min(n["land_speed"] * (b.ground * frames / FPS) / gap, 0.7)
        go = (1.0 - still) * go + still * u
        ankle = one["ankle"] + (two["ankle"] - one["ankle"]) * go
        lift = maths.keyed(
            [(0.0, 0.0), (n["kick_at"], n["kick"] * more), (n["carry_at"], n["carry_height"] * more), (1.0, 0.0)], u
        )
        ankle[1] += lift
        if n["land_from"] > 0.0:
            ankle[1] += n["land_from"] * min(u * frames / n["leave_frames"], 1.0, (1.0 - u) * frames / n["land_frames"])
        if "clear" in n:
            ankle[1] += n["clear"] * math.sin(math.pi * u) ** 2
        pitch_a, pitch_b = one["foot"][0], two["foot"][0]
        pitch = maths.keyed(
            [(0.0, pitch_a), (n["kick_at"], max(n["kick_pitch"], pitch_a)), (0.86, 0.6 * pitch_b), (1.0, pitch_b)], u
        )
        yaw = a.yaw + (b.yaw - a.yaw) * maths.smooth(u)
        toe = one["toe"] * (1.0 - maths.smooth(u / 0.3))
        turn = body_turn(pitch, yaw, 0.0)
        hinge = ankle + turn @ (sole["hinge"] - sole["ankle"])
        tip = hinge + body_turn(pitch - toe, yaw, 0.0) @ (sole["toe"] - sole["hinge"])
        heel = ankle + turn @ (sole["heel"] - sole["ankle"])
        ball = ankle + turn @ (sole["ball"] - sole["ankle"])
        margin = 0.006 * maths.smooth(u / 0.15) * maths.smooth((1.0 - u) / 0.1)
        ankle[1] += max(sole["floor"] + margin - min(tip[1], heel[1], ball[1]), 0.0)
        return {"ankle": ankle, "foot": (pitch, yaw, 0.0), "toe": toe}

    def planted(self, s: str, f: float) -> Tread | None:
        for tread in self.treads[s]:
            if tread.land - gaits.EDGE <= f <= tread.lift + gaits.EDGE:
                return tread
        return None

    def leg(self, s: str, f: float) -> dict:
        """A leg's `ankle`, `foot` and `toe` at a frame, in the world."""
        tread = self.planted(s, f)
        if tread is not None:
            out = self._stance(tread, min(max(f, tread.land), tread.lift))
        else:
            before = [t for t in self.treads[s] if t.lift < f]
            after = [t for t in self.treads[s] if t.land > f]
            assert before and after, f"the {s} foot has no contact on one side of frame {f}"
            out = self._swing(before[-1], after[0], f)
            if self.ghost is not None and s == self.ghost.side and before[-1].lift < 0.0 < after[0].land:
                # The gait's own swing as the clip begins, let go for the clip's own landing.
                own = self._swing(before[-1], self.ghost, min(f, self.ghost.land))
                share = maths.smoother(f / min(after[0].land, self.ghost.land)) if f > 0.0 else 0.0
                out = {
                    "ankle": own["ankle"] + (out["ankle"] - own["ankle"]) * share,
                    "foot": tuple(x + (y - x) * share for x, y in zip(own["foot"], out["foot"], strict=True)),
                    "toe": own["toe"] + (out["toe"] - own["toe"]) * share,
                }
        out["ankle"] = out["ankle"] + maths.Y * self.set_down.get((s, f), 0.0)
        return out

    # ---- the body ------------------------------------------------------------------------------------------------

    def _clock(self) -> None:
        """The gait's frame the body is at on each frame of the clip: it passes through every landing at that
        foot's own frame of the cycle, and through every foot's leaving for the air at the frame the gait's
        leaves, so the rise and fall the gait has for a flight is played while the clip's feet are in the air."""
        half, F = self.half, float(self.frames)
        first = self.phase + (self.cycle * 4 - (self.landings - 1) * half if self.start else half)
        knots = {float(land): first + i * half for i, land in enumerate(self.lands)}
        if not self.start:
            knots[0.0] = float(self.phase)
        if self.contact < half:
            for s, _ in SIDES:
                for tread in self.treads[s]:
                    if tread.land not in knots or not 0.0 < tread.lift < F:
                        continue
                    after = [land for land in knots if land > tread.lift]
                    # The clock runs at the gait's pace through a flight; one shorter than the gait's is the end of it.
                    if after and min(after) - tread.lift >= 2.0 and self.planted(OTHER[s], tread.lift + 0.5) is None:
                        knots[float(tread.lift)] = max(
                            knots[min(after)] - (min(after) - tread.lift), knots[tread.land] + 0.5 * (tread.lift - tread.land)
                        )
        if self.start:
            swing = self.cycle - self.contact
            knots[float(self.first_lift)] = first - min(swing, half)
            self._slopes = (None, 1.0)
        else:
            knots[F] = first + (self.landings - 1) * half + 0.15 * half
            self._slopes = (1.0, 0.0)
        self._knots = sorted(knots.items())
        # The clock's pace changes at every knot; smoothed over a frame and a half, no arm is jerked on a landing.
        reach = 6
        grid = np.arange(-reach * 10, (self.frames + reach) * 10 + 1) / 10.0
        raw = np.array([clock(self._knots, float(x), *self._slopes) for x in grid])
        kernel = np.exp(-0.5 * (np.arange(-45, 46) / 15.0) ** 2)
        self._clock_at = grid[45:-45]
        self._clock_is = np.convolve(raw, kernel / kernel.sum(), mode="valid")

    def gait_frame(self, f: float) -> float:
        return float(np.interp(f, self._clock_at, self._clock_is))

    def share(self, f: float, key: str) -> float:
        """How far a part of the body is the gait's at a frame (0: the idle's)."""
        n = self.n
        w = skewed((f / self.frames - n[key][0]) / max(n[key][1] - n[key][0], 1e-6), n["body_turn"])
        return w if self.start else 1.0 - w

    def _pelvis_rel(self, phase: float) -> np.ndarray:
        """The gait's pelvis over its root at any frame of its cycle."""
        k = math.floor(phase)
        t = phase - k
        p = [self.rel[(k + j) % self.cycle] for j in (-1, 0, 1, 2)]
        return 0.5 * (
            2 * p[1] + (p[2] - p[0]) * t + (2 * p[0] - 5 * p[1] + 4 * p[2] - p[3]) * t * t
            + (3 * p[1] - p[0] - 3 * p[2] + p[3]) * t * t * t
        )  # fmt: skip

    def _gait_spec(self, phase: float, root: float) -> dict:
        """The shipped gait's own spec at a whole frame of its cycle, with its root at `root`."""
        g = self.g
        k = int(round(phase)) % self.cycle
        spec = g.spec(float(k))
        shift = np.array([0.0, 0.0, root - self.v * k / FPS])
        spec["pelvis"]["place"] = spec["pelvis"]["place"] + shift
        for s, _ in SIDES:
            spec["leg"][s]["ankle"] = spec["leg"][s]["ankle"] + shift
        return spec

    def _idle_spec(self, root: float) -> dict:
        one = self.idle
        shift = np.array([0.0, 0.0, root])
        return {
            "pelvis": {"place": np.asarray(one["pelvis"]["place"], dtype=float) + shift, "turn": tuple(one["pelvis"]["turn"])},
            "chest": tuple(one["chest"]),
            "ribs": one["ribs"],
            "head": tuple(one["head"]),
            "clavicle": {s: tuple(one["clavicle"][s]) for s, _ in SIDES},
            "arm": {s: dict(one["arm"][s]) for s, _ in SIDES},
            "fingers": {s: dict(one["fingers"][s]) for s, _ in SIDES},
            "leg": {s: {**one["leg"][s], "ankle": np.asarray(one["leg"][s]["ankle"], dtype=float) + shift} for s, _ in SIDES},
        }

    def spec(self, f: float) -> dict:
        """The solver's spec at a frame, in the world. The ends are the joined clips' own specs."""
        F, n = self.frames, self.n
        if self.start and f <= 0:
            return self._idle_spec(0.0)
        if not self.start and f >= F:
            return self._idle_spec(self.x(float(F)))
        if self.start and f >= F:
            return self._gait_spec(self.phase + (f - F), self.x(float(f)))
        if not self.start and f <= 0:
            return self._gait_spec(self.phase + f, self.x(float(f)))
        phase = self.gait_frame(float(f))
        own = self.g.spec(phase)
        idle = self.idle
        w, arms = self.share(f, "body"), self.share(f, "arms")
        lean = self.lean(float(f))
        rel = self._pelvis_rel(phase)
        # The gait's rise and fall is a flight's; steps that are longer on the floor than the gait's take a share of it.
        near = (F - f if self.start else f) / self.half
        rel[1] = self._middle + (rel[1] - self._middle) * (1.0 + (n["bob"] - 1.0) * maths.smooth(near - 0.5))
        place = mix(np.asarray(idle["pelvis"]["place"], dtype=float), rel, w)
        place = place + np.array([0.0, 0.0, self.x(float(f))])
        place[0] += self._shift(float(f))
        place[2] += n["lean_fore"] * self.h * math.tan(math.radians(lean))
        place[1] -= n["lean_low"] * self.h * abs(math.tan(math.radians(lean)))
        place[1] -= self._dip(float(f)) + float(np.interp(f, np.arange(F + 1), self.lower))
        place[1] += float(np.interp(f, np.arange(F + 1), self.level))
        turn = mix(tuple(idle["pelvis"]["turn"]), tuple(own["pelvis"]["turn"]), w)
        chest = mix(tuple(idle["chest"]), tuple(own["chest"]), w)
        head = mix(tuple(idle["head"]), tuple(own["head"]), w)
        return {
            "pelvis": {"place": place, "turn": (turn[0] + n["lean_hips"] * lean, turn[1], turn[2])},
            "chest": (chest[0] + n["lean"] * lean, chest[1], chest[2]),
            "ribs": idle["ribs"] * (1.0 - w),
            "head": (head[0] + n["lean_head"] * lean, head[1], head[2]),
            "clavicle": {s: mix(tuple(idle["clavicle"][s]), tuple(own["clavicle"][s]), arms) for s, _ in SIDES},
            "arm": {s: self._arm(mix(self.idle_arms[s], plain_arm(own["arm"][s]), arms), arms) for s, _ in SIDES},
            "fingers": {s: mix(dict(idle["fingers"][s]), dict(own["fingers"][s]), arms) for s, _ in SIDES},
            "leg": {s: self.leg(s, float(f)) for s, _ in SIDES},
        }

    def _arm(self, arm: dict, share: float) -> dict:
        """An arm between the idle's and the gait's. `clear` opens an arm on the frame a thigh passes under it,
        which jerks it while the legs do what neither clip's do; it is let go in the middle of the change."""
        arm["clear"] = arm["clear"] * (1.0 - self.n["arms_free"] * math.sin(math.pi * share) ** 2)
        return arm

    def _shift(self, f: float) -> float:
        """Metres the hips go over the standing foot before a start's first step."""
        if not self.start:
            return 0.0
        n = self.n
        lift, land = float(self.first_lift), float(self.lands[0])
        up = maths.smooth(f / max(lift, 1.0))
        down = 1.0 - maths.smooth((f - lift) / max(land - lift, 1.0))
        return -SIGN[self.side] * n["shift"][AT[self.side]] * up * down

    def _dip(self, f: float) -> float:
        n = self.n
        if self.start:
            lift, land = float(self.first_lift), float(self.lands[0])
            return n["dip"] * maths.smooth(f / max(lift, 1.0)) * (1.0 - maths.smooth((f - lift) / max(land - lift, 1.0)))
        low = self.halt + n["dip_at"]
        return n["dip"] * maths.smooth((f - self.lands[0]) / max(low - self.lands[0], 1.0)) * (
            1.0 - maths.smooth((f - low) / max(self.frames - 2.0 - low, 1.0))
        )

    # ---- the floor and the legs' reach ---------------------------------------------------------------------------

    def settle(self) -> None:
        """Set every sole's skin on the floor on every frame (as `gait.Gait._settle` does for a gait), and lower the
        pelvis where a leg would be stretched past `stretch`."""
        rig, n, g = self.rig, self.n, self.g
        solver = Solver(rig)
        count = self.frames + 1
        for _ in range(16):
            need, moved = np.zeros(count), 0.0
            height = np.zeros(count)
            fixes = dict(self.set_down)
            for f in range(1, self.frames):
                spec = self.spec(float(f))
                pose = solver.solve(spec)
                height[f] = weight.centre_of_mass(rig, pose)[1]
                turn = rig.rest_rot[rig.parent["pelvis"]] @ pose["local"]["pelvis"] @ rig.rest_rot["pelvis"].T
                for s, _ in SIDES:
                    hip = pose["pelvis"] + turn @ (rig.rest_pos["thigh_" + s] - rig.rest_pos["pelvis"])
                    to = np.asarray(spec["leg"][s]["ankle"], dtype=float) - hip
                    want = n["stretch"] * (rig.length["thigh_" + s] + rig.length["calf_" + s])
                    level = math.hypot(to[0], to[2])
                    need[f] = max(need[f], 0.03 if level >= want else -math.sqrt(want * want - level * level) - to[1])
                    gaps = g._sole_gaps(pose, s)
                    key = (s, float(f))
                    tread = self.planted(s, float(f))
                    if tread is not None:
                        change = -0.5 * (max(gaps) + min(gaps))
                        if tread.standing:
                            # A flat foot on its standing place is the idle's, as the idle has it.
                            pitch = abs(spec["leg"][s]["foot"][0])
                            change = change * maths.smooth(pitch / 3.0) - fixes.get(key, 0.0) * (1.0 - maths.smooth(pitch / 3.0))
                    else:
                        before = [t for t in self.treads[s] if t.lift < f]
                        after = [t for t in self.treads[s] if t.land > f]
                        u = (f - before[-1].lift) / (after[0].land - before[-1].lift)
                        clear = 0.004 * maths.smooth(u / 0.15) * maths.smooth((1.0 - u) / 0.1)
                        change = max(clear - min(gaps), -fixes.get(key, 0.0))
                        change = change if change > 0.0 or fixes.get(key, 0.0) > 0.0 else 0.0
                    fixes[key] = fixes.get(key, 0.0) + change
                    moved = max(moved, abs(change))
            self.set_down = fixes
            more = np.maximum(need, 0.0)
            if more.max() > 1e-4:
                wide = np.array([more[max(f - 2, 0) : f + 3].max() for f in range(count)])
                add = np.maximum(_soft(wide, 1.5), more)
                add[0] = add[-1] = 0.0
                self.lower = np.minimum(self.lower + add, 0.3)
                moved = max(moved, float(more.max()))
            # Where the centre of mass drops faster than `FALL_MOST` of gravity with a foot down, its height is
            # smoothed over the frames round it.
            for end, f in ((0, 0.0), (count - 1, float(self.frames))):
                height[end] = weight.centre_of_mass(rig, solver.solve(self.spec(f)))[1]
            drop = np.zeros(count)
            drop[1:-1] = -np.diff(height, 2) * FPS * FPS / weight.G
            down = [any(self.planted(s, float(f)) is not None for s, _ in SIDES) for f in range(count)]
            bad = [f for f in range(1, count - 1) if drop[f] > FALL_MOST and down[f - 1] and down[f] and down[f + 1]]
            if bad:
                soft = _soft(height, 1.2)
                share = np.array([max(maths.smooth(1.0 - abs(f - b) / 4.0) for b in bad) for f in range(count)])
                share[0] = share[-1] = 0.0
                self.level = self.level + share * (soft - height)
                moved = max(moved, float(np.abs(share * (soft - height)).max()))
            if moved < 1e-4:
                break
        self.lower = _soft(self.lower, 1.0) if self.lower.max() > 0.0 else self.lower
        self.lower[0] = self.lower[-1] = 0.0

    # ---- the plan the checks and `clips.json` read ----------------------------------------------------------------

    def plan(self) -> ContactPlan:
        falls = []
        for s, _ in SIDES:
            for tread in self.treads[s]:
                if tread.lift < 0.0 or tread.land > self.frames:
                    continue
                n = tread.foot
                falls.append(
                    Footfall(
                        s,
                        float(tread.land),
                        float(tread.lift),
                        tread.place,
                        yaw=tread.yaw,
                        heel_strike=max(n["heel_strike"], 0.0),
                        roll_in=n["roll_in"],
                        toe_off=n["toe_off"],
                        roll_out=n["roll_out"],
                    )
                )
        return ContactPlan(self.frames, falls, Travel(forward=self.x), loop=False, tread=False)


def describe(kind: str, start: bool, side: str, rig, style, name: str, joined) -> Clip:
    assert joined is not None, "a start or a stop needs the clips it joins (`clips.joined.Joined`)"
    section = f"idle_to_{kind}" if start else f"{kind}_stop"
    n = style.numbers(section, (STARTS if start else STOPS)[kind])
    move = Move(rig, joined, kind, start, side, n)
    move.settle()
    gait_name = kind.capitalize()
    idle, own = joined.built("Idle"), joined.built(gait_name)
    k = move.phase
    at_gait = (own.rotation[k], own.translation[k])
    at_idle = (idle.rotation[0], idle.translation[0])
    F = move.frames
    if start:
        joins = {"first": at_idle, "last": at_gait, "first_speed": 0.0, "last_speed": move.v}
        meet = {"first": (idle.frames[0], n["meet"]), "last": (own.frames[k], n["meet"])}
        names = {"first": "Idle", "last": gait_name, "last_frame": k}
        free = float(move.lands[-2])
        lead = 0
    else:
        joins = {"first": at_gait, "last": at_idle, "first_speed": move.v, "last_speed": 0.0}
        meet = {"first": (own.frames[k], n["meet"]), "last": (idle.frames[0], n["meet"])}
        names = {"first": gait_name, "first_frame": k, "last": "Idle"}
        free = float(move.lands[-1])
        lead = move.cycle

    def spec(f: int) -> dict:
        return move.spec(f)

    return Clip(
        name=name,
        frames=F,
        plan=move.plan(),
        spec=spec,
        loop=False,
        meet=meet,
        chains=overlap.chains_from(move.lags, gaits.PARTS),
        kind="transition",
        lead=lead,
        declared={
            "joins": joins,
            "distance": move.x(float(F)),
            "turn": 0.0,
            "join_names": names,
            "speed_limit": n["speed_limit"],
            "lean_limit": n["lean_limit"],
            "lean_over": move.half,
            "feet": [
                (t.side, t.land, t.lift, round(t.place[1] - move.x(t.land), 3), round(t.place[1] - move.x(t.lift), 3))
                for s, _ in SIDES
                for t in move.treads[s]
            ],
            "lowered": round(float(move.lower.max()), 3),
            "pushed": round(getattr(move, "push", 0.0), 2),
            "keys_kept": n["keys_kept"],
            "kb_a_second": n["kb_a_second"],
        },
        # From here the game may cut to new input: a start is on the gait's own feet, a stop has only its settle left.
        events=[{"frame": free, "name": "free"}],
        style=style.letter,
    )


def family(kind: str, start: bool) -> list:
    """The clips of one type, `[(name, describe), ...]`: the one on the left foot, then the one on the right."""
    stem = f"Idle_To_{kind.capitalize()}" if start else f"{kind.capitalize()}_Stop"
    out = []
    for side in ("l", "r"):

        def one(rig, style, name, joined=None, side=side):
            return describe(kind, start, side, rig, style, name, joined)

        out.append((f"{stem}_{side.upper()}", one))
    return out
