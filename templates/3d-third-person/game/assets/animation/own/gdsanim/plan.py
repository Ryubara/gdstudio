"""The contact plan: a clip written as its footfalls.

A description names which foot is on the floor, when it lands, when it leaves and where, in the world of a floor
that does not move, with the root travelling over it (`Travel`). Foot paths, contact times, the clip's speed and its
footstep events all come from the plan, so cadence, planted share and speed are inputs and not things that happen.
The build takes the root's travel out again (`unroot`), which leaves the clip in place with the travel as a curve in
`clips.json`.

A planted foot is one place in the world for its whole contact: it rolls in over its heel for `roll_in` frames, lies
flat, and rolls out over the ball of the foot for `roll_out` frames, the toes staying on the floor. Between two
contacts the ball of the foot travels on an eased path with `clearance` under it.
"""

import math
from dataclasses import dataclass, field

import numpy as np

from . import FPS, maths
from .maths import body_turn
from .rig import SIDES, Rig


@dataclass
class Travel:
    """The root's travel over the floor: metres along the way it faces, metres to its left and degrees turned to
    its left, each a function of the frame. A loop at one speed is `Travel.steady(speed)`; a clip that stands is
    `Travel()`."""

    forward: callable = lambda f: 0.0
    left: callable = lambda f: 0.0
    turn: callable = lambda f: 0.0

    @staticmethod
    def steady(speed: float) -> "Travel":
        return Travel(forward=lambda f: speed * f / FPS)

    def at(self, f: float) -> tuple:
        """The root's place (x, z) and yaw in degrees at a frame."""
        return np.array([self.left(f), 0.0, self.forward(f)]), self.turn(f)

    def speed(self, f: float) -> float:
        a, _ = self.at(f - 0.5)
        b, _ = self.at(f + 0.5)
        return float(np.linalg.norm(b - a)) * FPS


@dataclass
class Footfall:
    """One contact of one foot: the frames it lands and leaves, and where the ball of the foot is on the floor
    (x to the left, z ahead, in the world), with the foot's yaw (degrees, toes to the left)."""

    side: str
    land: float
    lift: float
    place: tuple
    yaw: float = 0.0
    ## Degrees the toes point up as the heel lands, the frames the foot takes to come flat, the degrees the heel is
    ## up as the toes leave and the frames it takes to get there.
    heel_strike: float = 0.0
    roll_in: float = 0.0
    toe_off: float = 0.0
    roll_out: float = 0.0


@dataclass
class ContactPlan:
    """The footfalls of a clip. For a loop the footfalls of one cycle repeat every `frames` frames, each repeat
    one stride (the root's travel over a cycle) further on."""

    frames: int
    footfalls: list
    travel: Travel = field(default_factory=Travel)
    loop: bool = True
    ## Metres the ball of the foot clears the floor by at the top of its swing.
    clearance: float = 0.06

    def stride(self) -> np.ndarray:
        """The root's travel over one cycle."""
        a, _ = self.travel.at(0.0)
        b, _ = self.travel.at(float(self.frames))
        return b - a

    def _falls(self, side: str) -> list:
        """A side's footfalls in time order, with the repeats before and after a loop's cycle."""
        own = sorted((fall for fall in self.footfalls if fall.side == side), key=lambda fall: fall.land)
        if not self.loop or not own:
            return [(fall, np.zeros(3)) for fall in own]
        out = []
        for turn in (-1, 0, 1):
            shift = self.stride() * turn
            for fall in own:
                moved = dict(fall.__dict__, land=fall.land + turn * self.frames, lift=fall.lift + turn * self.frames)
                out.append((Footfall(**moved), shift))
        return out

    def contacts(self, side: str) -> list:
        """The frames a foot is on the floor inside the clip, `[[land, lift], ...]`."""
        out = []
        for fall, _ in self._falls(side):
            start, end = max(fall.land, 0.0), min(fall.lift, float(self.frames))
            if end > start:
                out.append([round(start, 3), round(end, 3)])
        return out

    def planted(self, side: str, f: float) -> bool:
        return any(fall.land <= f <= fall.lift for fall, _ in self._falls(side))

    def weight(self, f: float, soften: float = 4.0) -> float:
        """The share of the body's weight the left foot carries: 1 or 0 with one foot down, crossing over
        `soften` frames round a landing, a half with both or neither down for longer."""
        left = self._carry("l", f, soften)
        right = self._carry("r", f, soften)
        return 0.5 if left + right < 1e-9 else left / (left + right)

    def _carry(self, side: str, f: float, soften: float) -> float:
        best = 0.0
        for fall, _ in self._falls(side):
            up = maths.smooth((f - fall.land) / soften + 0.5)
            down = maths.smooth((fall.lift - f) / soften + 0.5)
            best = max(best, min(up, down))
        return best

    def events(self) -> list:
        """A footstep on every landing inside the clip."""
        out = []
        for side, _ in SIDES:
            for fall, _ in self._falls(side):
                whole = fall.land <= 0.0 and fall.lift >= self.frames
                if 0.0 <= fall.land < self.frames and not whole:
                    out.append({"frame": round(fall.land, 3), "name": "footstep", "foot": side})
        return sorted(out, key=lambda event: event["frame"])

    def first_foot(self, f: float) -> str:
        """The foot the body stands on at a frame: `l`, `r`, `both` or `none`; with both down, the one that
        landed last unless they landed together."""
        down = {}
        for side, _ in SIDES:
            lands = [fall.land for fall, _ in self._falls(side) if fall.land <= f <= fall.lift]
            if lands:
                down[side] = max(lands)
        if not down:
            return "none"
        if len(down) == 1:
            return next(iter(down))
        return "both" if abs(down["l"] - down["r"]) < 0.5 else max(down, key=down.get)

    # ---- the foot's path ------------------------------------------------------------------------------------

    def foot(self, rig: Rig, side: str, f: float) -> dict:
        """A leg's `ankle`, `foot` and `toe` at a frame, in the world (before the root is taken out)."""
        falls = self._falls(side)
        assert falls, f"the plan has no footfall for the {side} foot"
        for fall, shift in falls:
            if fall.land <= f <= fall.lift:
                return self._planted(rig, side, fall, shift, f)
        before = [(fall, shift) for fall, shift in falls if fall.lift < f]
        after = [(fall, shift) for fall, shift in falls if fall.land > f]
        if not before:
            return self._planted(rig, side, after[0][0], after[0][1], after[0][0].land)
        if not after:
            return self._planted(rig, side, before[-1][0], before[-1][1], before[-1][0].lift)
        return self._swing(rig, side, before[-1], after[0], f)

    def _state(self, rig: Rig, side: str, pivot: str, at: np.ndarray, pitch: float, yaw: float) -> dict:
        """The leg spec of a foot turned by `pitch` and `yaw` with its sole point `pivot` at `at`."""
        sole = rig.sole[side]
        turn = body_turn(pitch, yaw, 0.0)
        return {
            "ankle": at + turn @ (sole["ankle"] - sole[pivot]),
            "foot": (pitch, yaw, 0.0),
            "toe": max(pitch, 0.0),
        }

    def _ball(self, rig: Rig, side: str, fall: Footfall, shift: np.ndarray) -> np.ndarray:
        return np.array([fall.place[0], rig.sole[side]["floor"], fall.place[1]]) + shift

    def _planted(self, rig: Rig, side: str, fall: Footfall, shift: np.ndarray, f: float) -> dict:
        sole = rig.sole[side]
        ball = self._ball(rig, side, fall, shift)
        yaw_turn = body_turn(0.0, fall.yaw, 0.0)
        if fall.roll_in > 0.0 and f < fall.land + fall.roll_in:
            share = 1.0 - maths.smooth((f - fall.land) / fall.roll_in)
            heel = ball + yaw_turn @ (sole["heel"] - sole["ball"])
            return self._state(rig, side, "heel", heel, -fall.heel_strike * share, fall.yaw)
        if fall.roll_out > 0.0 and f > fall.lift - fall.roll_out:
            share = maths.smooth((f - (fall.lift - fall.roll_out)) / fall.roll_out)
            return self._state(rig, side, "ball", ball, fall.toe_off * share, fall.yaw)
        return self._state(rig, side, "ball", ball, 0.0, fall.yaw)

    def _swing(self, rig: Rig, side: str, before: tuple, after: tuple, f: float) -> dict:
        sole = rig.sole[side]
        (a, shift_a), (b, shift_b) = before, after
        u = (f - a.lift) / (b.land - a.lift)
        go = maths.smooth(u)
        start = self._ball(rig, side, a, shift_a)
        # Where the ball of the foot is as the heel lands with the toes up.
        land_turn = body_turn(-b.heel_strike if b.roll_in > 0.0 else 0.0, b.yaw, 0.0)
        heel = self._ball(rig, side, b, shift_b) + body_turn(0.0, b.yaw, 0.0) @ (sole["heel"] - sole["ball"])
        end = heel + land_turn @ (sole["ball"] - sole["heel"])
        ball = start + (end - start) * go
        ball[1] += self.clearance * math.sin(math.pi * u) ** 2
        pitch_a = a.toe_off if a.roll_out > 0.0 else 0.0
        pitch_b = -b.heel_strike if b.roll_in > 0.0 else 0.0
        # The heel stays up through the first half of the swing, then the toes come up for the landing.
        pitch = pitch_a + (pitch_b - pitch_a) * maths.smooth((u - 0.15) / 0.7)
        yaw = a.yaw + (b.yaw - a.yaw) * go
        out = self._state(rig, side, "ball", ball, pitch, yaw)
        out["toe"] = max(pitch_a, 0.0) * (1.0 - maths.smooth(u / 0.3))
        return out


def standing(frames: int, rig: Rig, width: float = 0.0, toe_out: float = 0.0, stagger: float = 0.0) -> ContactPlan:
    """Both feet down for the whole clip: each `width` wider than the rest stance, turned `toe_out` degrees
    outward, the left foot `stagger` ahead of the right."""
    falls = []
    for s, sign in SIDES:
        ball = rig.sole[s]["ball"]
        place = (ball[0] + sign * width, ball[2] + sign * 0.5 * stagger)
        falls.append(Footfall(s, 0.0, float(frames), place, yaw=sign * toe_out))
    return ContactPlan(frames, falls, loop=True)


def unroot(rig: Rig, pose: dict, place: np.ndarray, yaw: float) -> None:
    """Take the root's travel out of a pose solved in the world: the pelvis's place and turn (and the `ik_`
    targets') become the root's own, so the clip is in place."""
    back = maths.axis_angle(maths.Y, -yaw)
    root = rig.rest_rot[rig.parent["pelvis"]]
    inner = root.T @ back @ root
    pose["pelvis"] = back @ (pose["pelvis"] - place)
    pose["local"]["pelvis"] = inner @ pose["local"]["pelvis"]
    for name in pose.get("places", {}):
        pose["places"][name] = inner @ pose["places"][name] - root.T @ back @ place
        pose["local"][name] = inner @ pose["local"][name]
