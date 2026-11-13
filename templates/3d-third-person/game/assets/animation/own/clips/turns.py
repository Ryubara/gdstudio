"""The reversals, the pivots and the turns on the spot (kit #1157). New: the library has none of them.

`Sprint_Turn_180` and `Jog_Turn_180`, each planting on the left (`_L`) and on the right foot (`_R`);
`Jog_Turn_90_L` and `_R`, turning to the left and to the right; `Turn_In_Place_90_L/R` and `Turn_In_Place_180_L/R`.
The game turned the body at `turn_speed` under a looping gait, so a body that reversed out of a sprint spun round
on the spot with its feet still running. These clips are the change of direction itself (the research and its
sources are in `../README.md`):

- **A reversal brakes, plants and pushes back.** It begins on the gait's pose as a foot strikes; the feet brake
  over one or more steps, each further ahead of the body than a steady step, the plant foot (the one the clip is
  named for) lands while the root is slowest, the body swings round it to that foot's side (planting the left
  foot, it turns to the left, so the planted foot ends on the side it began on), and the steps after it speed the
  body up the other way until the last two landings are the gait's own, 180 degrees round.
- **A pivot cuts on the outside foot.** It begins on the jog's pose as the inside foot strikes; that step brakes
  a little, the outside foot plants wide of the body and pushes it round (turning left, the right foot plants),
  and the speed dips and comes back while the root's path bends through 90 degrees. The trunk leans into the
  bend by the acceleration toward its middle.
- **A turn on the spot steps round.** From the idle's first pose, the head turns first, then the chest, then the
  hips; the foot on the side of the turn opens first (the right foot for a right turn), the other follows, and a
  180 needs a third step. No foot turns while it stands on the floor: each lifts, turns in the air and lands, so a
  contact never spins on its heel. The clip ends on the idle's first pose turned by exactly 90 or 180 degrees.
- **The root carries the turn.** The root's place and its yaw are curves (`Travel`), the clip is in place with
  both taken out, and `clips.json` has the travel and the turn for the tree, which plays the clip where its turn
  curve has turned as far as the body (`GaitTransitions`). The body faces the way the root moves.
- **The body leans by its acceleration**, forward and back by the change of speed and to the side by the bend
  (`atan(a / g)` of each, through a spring); the hips go into the bend and come down a little.
- **Left and right are two solves.** The idle and the gaits have a number per side, so neither clip of a pair is
  the other's mirror ([no mirror poses](own-animation.md#feel)).

What a turn takes from the starts and stops (`clips/moves.py`): the foot's stance and swing, the set-down of the
soles on the skin and the lowering of the hips where a leg would be stretched (`Move.settle`).
"""

import math

import numpy as np

from gdsanim import maths, overlap, weight
from gdsanim.build import Clip
from gdsanim.maths import FPS, Y, body_turn
from gdsanim.plan import ContactPlan, Footfall, Travel
from gdsanim.rig import SIDES

from . import gait as gaits
from .moves import AT, OTHER, SIGN, SLOW, Move, Tread, clock, picked_gait
from .stance import mix, plain_arm

## What each number of a style's `turn_in_place_90` or `turn_in_place_180` section means. A pair is the clip that
## turns to the left, then the one that turns to the right.
SPOT = {
    "prep": [9, 7],  # frames from the clip's first frame to the lead foot's lifting
    # Each step: which foot (`lead`, the foot on the side of the turn, or `trail`), the share of the turn the
    # foot lands at, the frames it is in the air, and the frames both feet are down after it lands.
    "steps": [["lead", 0.6, 8, 2], ["trail", 1.0, 9, 2], ["lead", 1.0, 7, 3]],
    "apart": 0.08,  # metres further out from the middle a foot lands on every step but its last
    "settle": 9,  # frames after the last landing: the hips, the trunk and the arms come to rest
    "yaw_early": 6,  # frames before the lead foot lifts the hips begin to turn
    "yaw_late": 2,  # frames after the last landing the hips have turned all the way
    "yaw_turn": 0.45,  # where in its window the turn is fastest (0.5: evenly)
    "chest_lead": 1.5,  # frames the chest's turn is ahead of the hips', before the overlap pass's lag
    "head_lead": 3.0,  # frames the head's turn is ahead of the hips' (the eyes lead)
    "head_more": 6.0,  # degrees the head turns past the hips while the body turns, on top of its lead
    "shift": 0.6,  # the share of the way from between the feet to over the standing foot the hips go
    "shift_soft": 5.0,  # frames over which the weight goes from one foot to the other round a lift or a landing
    "dip": 0.012,  # metres the hips sink while a foot is in the air
    "lift": 0.03,  # metres a stepping foot clears the floor by
    "heel": 3.0,  # degrees a stepping foot lands on its heel by
    "toe_off": 18.0,  # degrees the heel is up as a stepping foot leaves
    "arm_wide": [11.0, 12.0],  # degrees each arm (left, right) opens from the body while the body turns
    "knee_follow": 0.5,  # the share of the way from the foot's yaw to the hips' each knee points
    "arm_clear": [12.0, 10.0],  # degrees an arm opens and goes back while the foot on its side steps
    "stretch": 0.995,  # the share of its length a leg may be stretched to
    "meet": 3,  # frames over which what the overlap pass left in the joined clips is let go
    "speed_limit": 30.0,
    "lean_limit": 5.0,
    "side_lean_limit": 5.0,
    "keys_kept": 0.9,
    "kb_a_second": 40.0,
}
SPOTS = {
    "turn_in_place_90": dict(SPOT),
    "turn_in_place_180": {
        **SPOT,
        "prep": [8, 6],
        "steps": [["lead", 0.4, 8, 2], ["trail", 0.6, 9, 2], ["lead", 1.0, 9, 2], ["trail", 1.0, 8, 3]],
        "settle": 10,
        "head_more": 10.0,
    },
}
## The same for `jog_turn_90` (a pivot) and `jog_turn_180` and `sprint_turn_180` (a reversal). A pivot is named
## for the way it turns and plants the outside foot; a reversal is named for the foot that plants.
MOVING = {
    "plant": 3,  # which landing is the plant (0 is the strike the clip begins on; the one before it is the brake's)
    "steps": [10, 10, 9, 13, 10, 10, 10, 10],  # frames from each landing to the next; the last two are the gait's half cycle
    "air": [-4, -3, 1, -3, -4, -4, -4],  # frames each foot stays down after the next lands, for every landing but the last
    "gait_like": [0.85, 0.6, 0.5, 0.7, 0.85, 0.95],  # how far each landing between the first and the last two is the gait's (0: slow)
    "brake_from": 8,  # the frame the old way's velocity begins to go
    "stop_at": 0.5,  # where in the plant's contact the velocity is half the old way's and half the new (a share)
    "brake_shape": 1.6,  # the brake's power: above 1 it bites harder toward the stop
    "low": 0.8,  # the share of the gait's speed the root dips to on top, at the stop
    "push_end": 0,  # frames before the last landing but one the gait's speed is back the new way
    "lane": 0.0,  # metres the way back is beside the way in, toward the turn (a reversal's sideways shift)
    "side_on": 0.25,  # the share of the turn the hips have made by the plant's landing
    "face_before": 4,  # frames before the brake step lands the hips begin to turn
    "face_late": 2,  # frames after the plant lands they have made `side_on`
    "turn_lead": 3,  # frames before the stop the rest of the turn begins
    "turn_after": 12,  # frames after the stop the body has turned all the way
    "carry": 14.0,  # degrees the trunk leans the old way while the plant brakes (momentum carried over the leg)
    "carry_cut": 0.6,  # the share of the brake's own lean back taken out while it does
    "carry_hold": 2,  # frames after the plant leaves the carried lean is gone
    "plant_out": 0.12,  # metres the plant lands the old way from the root's place at the stop
    "plant_aside": -0.25,  # metres it lands toward the turn's side (less than 0: outside it)
    "brake_wide": 0.0,  # metres toward the turn's side the step before the plant lands, on the floor's axes
    "push_wide": 0.0,  # and the step after it
    "drive": 0.6,  # the share of the acceleration's lean the feet take: they land that far from a steady step
    "lean": 0.6,  # the share of the forward lean the chest takes, as pitch
    "lean_hips": 0.3,
    "lean_head": 0.25,
    "side": 0.7,  # the share of the lean into the bend the chest takes
    "side_hips": 0.5,
    "side_head": 0.3,
    "lean_fore": 0.15,  # the share of the lean the hips take by going toward the acceleration
    "side_fore": 0.25,  # the share of the lean into the bend the hips take by going into it (the feet stay out)
    "lean_low": 0.06,  # and the share by which they come down
    "lean_lag": [2.0, 0.1],  # the lean follows the acceleration through a spring: frames late, share past
    "chest_lead": 1.5,  # frames the chest's turn is ahead of the root's, before the overlap pass's lag
    "head_lead": 3.0,
    "brace": 0.15,  # the share of the way the carriage goes to the idle's while the root is slowest
    "brace_from": 0.1,  # the shares of the clip between which it goes there and back
    "brace_to": 0.8,
    "bob": 0.6,  # the share of the gait's rise and fall the steps that are not the gait's have
    "dip": 0.03,  # metres the hips sink as the plant takes the body
    "arm_wide": [14.0, 16.0],  # degrees each arm opens from the body while the root is slowest or the body leans
    "heel_early": 0.5,  # the share of a contact of the clip's own over which the heel comes up
    "toe_most": 50.0,  # degrees the heel of a step of the clip's own is up at most as the toes leave
    "push_heel": -4.0,  # degrees the toes are up at most as a step that speeds the body up lands
    "reach_fore": 0.45,  # metres ahead of the root a foot lands at most
    "reach_back": 0.42,  # metres behind the root a foot is at most as it leaves
    "reach_side": 0.25,  # metres to the side of where a steady step lands a foot is put at most
    "clear": 0.09,  # metres a foot that swings past the standing one keeps from it, beyond a foot's width
    "foot_turn": 0.3,  # the share of the root's turn over a contact the foot is set turned by as it lands
    "plant_turn": 0.6,  # the same for the plant foot, which the body turns over
    "plant_wide": 0.08,  # metres the plant foot lands further outside the turn than a steady step
    "own_side": 0.07,  # metres from the middle line each foot lands at the least, on its own side
    "stretch": 0.99,
    "meet": 3,
    "speed_limit": 55.0,
    "lean_limit": 18.0,
    "side_lean_limit": 20.0,
    "keys_kept": 0.9,
    "kb_a_second": 40.0,
}
## A reversal (kit #1442): the hips go side-on, the outside foot plants well ahead, the trunk is carried on over it
## while it brakes, and only then does the body turn and push off the new way. A sprint brakes longer and harder.
REVERSAL = {
    **MOVING,
    "low": 1.0,
    "side_on": 0.42,
    "face_before": 0,
    "face_late": -1,
    "turn_lead": 2,
    "plant_aside": -0.15,
    "brake_wide": 0.1,
    "push_wide": -0.1,
    "toe_most": 44.0,
    "foot_turn": 0.4,
    "plant_turn": 0.4,
    "own_side": 0.06,
    "brace": 0.35,
    "dip": 0.03,
    "carry_hold": 3,
}
MOVES = {
    "jog_turn_90": dict(MOVING),
    "jog_turn_180": {
        **REVERSAL,
        "steps": [10, 10, 9, 18, 10, 10, 10, 10],
        "air": [-4, -2, 2, -2, -3, -4, -4],
        "gait_like": [0.75, 0.4, 0.3, 0.5, 0.75, 0.9],
        "brake_from": 8,
        "stop_at": 0.6,
        "brake_shape": 1.8,
        "lane": 0.3,
        "turn_after": 16,
        "carry": 38.0,
        "carry_cut": 0.8,
        "plant_out": 0.12,
        "lean_limit": 30.0,
        "side_lean_limit": 34.0,
    },
    "sprint_turn_180": {
        **REVERSAL,
        "plant": 4,
        "steps": [9, 9, 10, 10, 20, 11, 10, 9, 9, 9],
        "air": [-5, -4, -4, -2, -2, -3, -4, -5, -5],
        "gait_like": [0.8, 0.55, 0.35, 0.3, 0.45, 0.65, 0.85, 0.95],
        "brake_from": 3,
        "stop_at": 0.6,
        "brake_shape": 1.3,
        "lane": 0.35,
        "turn_after": 18,
        "carry": 44.0,
        "carry_cut": 0.85,
        "plant_out": 0.15,
        "reach_fore": 0.5,
        "lean_limit": 36.0,
        "side_lean_limit": 36.0,
        "speed_limit": 80.0,
    },
}
## The gait each moving type leaves and joins, and the angle it turns (degrees, to the left for the `_L` pivot).
GAIT_OF = {"jog_turn_90": ("jog", 90.0), "jog_turn_180": ("jog", 180.0), "sprint_turn_180": ("sprint", 180.0)}
## Tenths of a frame the root's curves are sampled at.
GRID = 10


def _rotate(yaw: float, x: float, z: float) -> np.ndarray:
    """A floor vector (x, z) turned `yaw` degrees to the left."""
    r = math.radians(yaw)
    return np.array([x * math.cos(r) + z * math.sin(r), -x * math.sin(r) + z * math.cos(r)])


def placed(spec: dict, xz: np.ndarray, yaw: float) -> dict:
    """A spec solved with its root at the floor's origin, facing +z, put on the floor at `xz` turned by `yaw`."""
    turn = maths.axis_angle(Y, yaw)
    lift = np.array([xz[0], 0.0, xz[1]])
    out = dict(spec)
    pelvis = spec["pelvis"]
    p_turn = tuple(pelvis["turn"])
    out["pelvis"] = {"place": turn @ np.asarray(pelvis["place"], dtype=float) + lift, "turn": (p_turn[0], p_turn[1] + yaw, p_turn[2])}
    for key in ("chest", "head"):
        if key in spec:
            one = tuple(spec[key])
            out[key] = (one[0], one[1] + yaw, one[2])
    if "leg" in spec:
        legs = {}
        for s, leg in spec["leg"].items():
            foot = tuple(leg["foot"])
            legs[s] = {**leg, "ankle": turn @ np.asarray(leg["ankle"], dtype=float) + lift, "foot": (foot[0], foot[1] + yaw, foot[2])}
            if "knee" in leg:
                legs[s]["knee"] = turn @ np.asarray(leg["knee"], dtype=float)
        out["leg"] = legs
    return out


def _bump(f: float, a: float, b: float, c: float) -> float:
    """0 before `a`, rising to 1 at `b`, falling to 0 at `c`, with no speed at either end or at the top."""
    if f <= a or f >= c:
        return 0.0
    if f <= b:
        return maths.smooth((f - a) / max(b - a, 1e-6))
    return 1.0 - maths.smooth((f - b) / max(c - b, 1e-6))


def _ease(f: float, a: float, b: float) -> float:
    """0 before `a`, 1 after `b`, smooth between."""
    return maths.smooth(min(max((f - a) / max(b - a, 1e-6), 0.0), 1.0))


class Turn(Move):
    """One reversal, pivot or turn on the spot, on one foot or one way, for one rig and one set of numbers."""

    def __init__(self, rig, joined, kind: str, side: str, numbers: dict):
        self.rig, self.n, self.side, self.type = rig, numbers, side, kind
        self.spot = kind.startswith("turn_in_place")
        gait = "walk" if self.spot else GAIT_OF[kind][0]
        self.gait_kind = gait
        self.g, self.lags = picked_gait(rig, joined, gait)
        if self.spot:
            # A turn on the spot trails as the idle does.
            self.lags = joined.style("Idle").overlap("idle")
        g = self.g
        self.cycle, self.half, self.contact = g.frames, g.frames // 2, g.contact
        self.v = 0.0 if self.spot else g.n["speed"]
        self.start = False
        idle = joined.start("Idle")
        self.idle = idle["spec"]
        self.idle_falls = {fall.side: fall for fall in joined.clip("Idle").plan.footfalls}
        self.idle_arms = {s: plain_arm(self.idle["arm"][s]) for s, _ in SIDES}
        self.h = 1.1 * float(rig.rest_pos["pelvis"][1])
        self.ghost = None
        self.set_down = {}
        self._specs = {}
        if self.spot:
            self.angle = (90.0 if kind.endswith("90") else 180.0) * (1.0 if side == "l" else -1.0)
            self._spot_steps()
        else:
            self.rel = np.array(
                [g._pelvis[float(k)] - np.array([0.0, 0.0, self.v * k / FPS]) for k in range(self.cycle)]
            )
            self._middle = float(self.rel[:, 1].mean())
            angle = GAIT_OF[kind][1]
            # Both are named for the way they turn and plant the outside foot (turning left, the right foot). A
            # reversal goes side-on first: turning left, the hips face left and the right leg leads the old way,
            # so the right foot is the one that plants well ahead, and the left one steps off the new way without
            # crossing it (kit #1442: the first reversals turned over the inside foot, early and with no brake).
            self.plant_side = OTHER[side]
            self.angle = angle if side == "l" else -angle
            self._moving_steps()
        self.lower = np.zeros(self.frames + 1)
        self.level = np.zeros(self.frames + 1)

    # ---- the root ------------------------------------------------------------------------------------------------

    def _root_curves(self, speed, heading) -> None:
        """The root's place and yaw on a grid from well before the clip to well after it, from its speed (m/s) and
        heading (degrees) as functions of the frame; past either end it goes on as it is."""
        lo, hi = -(self.cycle * 3 + 4), self.frames + self.cycle * 3 + 4
        t = np.arange(lo * GRID, hi * GRID + 1) / GRID
        s = np.array([speed(x) for x in t])
        th = np.array([heading(x) for x in t])
        r = np.radians(th)
        vx, vz = s * np.sin(r), s * np.cos(r)
        dt = 1.0 / (GRID * FPS)
        px = np.concatenate([[0.0], np.cumsum(0.5 * (vx[1:] + vx[:-1]) * dt)])
        pz = np.concatenate([[0.0], np.cumsum(0.5 * (vz[1:] + vz[:-1]) * dt)])
        at0 = -lo * GRID
        px, pz = px - px[at0], pz - pz[at0]
        self._t, self._s, self._th, self._px, self._pz = t, s, th, px, pz
        self._path = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(px), np.diff(pz)))])
        self._path -= self._path[at0]
        # The acceleration in the root's own frame: along the way it goes, and toward its left.
        self._a_fwd = np.gradient(s) * GRID * FPS
        self._a_left = s * np.radians(np.gradient(th) * GRID * FPS)
        self._lean = self._leans()

    def _leans(self) -> np.ndarray:
        """Pitch and lean (degrees) a frame: the acceleration's, through the spring, nothing of it at the ends."""
        n = self.n
        frames = range(self.frames + 1)
        lag, past = n.get("lean_lag", [2.0, 0.1])
        pitch = [math.degrees(math.atan2(self.a_fwd(float(f)), weight.G)) for f in frames]
        lean = [math.degrees(math.atan2(self.a_left(float(f)), weight.G)) for f in frames]
        carry = getattr(self, "_carry_window", None)
        if carry is not None and n.get("carry", 0.0):
            # Momentum carries the mass on over the planted leg: while the plant brakes, the trunk leans the old
            # way (+z) instead of back against the brake, and most of the brake's own lean is taken out.
            a, b, c = carry
            for f in frames:
                share = _bump(float(f), a, b, c)
                yaw = math.radians(self.root(float(f))[1])
                keep = 1.0 - n["carry_cut"] * share
                pitch[f] = pitch[f] * keep + n["carry"] * share * math.cos(yaw)
                lean[f] = lean[f] * keep - n["carry"] * share * math.sin(yaw)
        out = np.array([overlap.follow(pitch, lag, past, False), overlap.follow(lean, lag, past, False)]).T
        for f in frames:
            out[f] *= maths.smooth(f / 3.0) * maths.smooth((self.frames - f) / 3.0)
        return out

    def root(self, f: float) -> tuple:
        """The root's place on the floor (x, z) and its yaw at a frame."""
        t = self._t
        if f < t[0] or f > t[-1]:
            raise AssertionError(f"frame {f} is outside the root's curves")
        return np.array([np.interp(f, t, self._px), np.interp(f, t, self._pz)]), float(np.interp(f, t, self._th))

    def path(self, f: float) -> float:
        return float(np.interp(f, self._t, self._path))

    def speed(self, f: float) -> float:
        return float(np.interp(f, self._t, self._s))

    def a_fwd(self, f: float) -> float:
        return float(np.interp(f, self._t, self._a_fwd))

    def a_left(self, f: float) -> float:
        return float(np.interp(f, self._t, self._a_left))

    def lean_at(self, f: float) -> tuple:
        frames = np.arange(self.frames + 1)
        return float(np.interp(f, frames, self._lean[:, 0])), float(np.interp(f, frames, self._lean[:, 1]))

    def x(self, f: float) -> float:
        return self.path(f)

    # ---- a turn on the spot --------------------------------------------------------------------------------------

    def _stand(self, s: str, land: float, lift: float, yaw: float, toe_off: float, heel: float, apart=0.0) -> Tread:
        """A foot on its standing place, the idle's, turned with the body by `yaw`, and `apart` metres further out
        from the root's middle."""
        fall = self.idle_falls[s]
        numbers = dict(SLOW)
        numbers.update(heel_strike=heel, roll_in=2.0 if heel > 0 else 0.0, stance_pitch=0.0, toe_off=toe_off)
        room = max(lift - land - numbers["roll_in"], 0.0)
        numbers["roll_out"] = min(3.0, room) if toe_off else 0.0
        numbers["carry_height"] = 0.0
        numbers["kick"] = 0.0
        numbers["clear"] = float(self.n["lift"])
        place = _rotate(yaw, fall.place[0], fall.place[1])
        place = place + apart * place / max(float(np.linalg.norm(place)), 1e-9)
        return Tread(s, land, lift, (float(place[0]), float(place[1])), fall.yaw + yaw, numbers, numbers, 0.0, standing=True)

    def _spot_steps(self) -> None:
        n, A = self.n, self.angle
        lead = self.side
        who = {"lead": lead, "trail": OTHER[lead]}
        f = float(n["prep"][AT[self.side]])
        steps = []
        for name, share, air, rest in n["steps"]:
            steps.append((who[name], float(share), f, f + float(air)))
            f = f + float(air) + float(rest)
        last_land = steps[-1][3]
        self.frames = int(round(last_land + float(n["settle"])))
        F = float(self.frames)
        for s in ("l", "r"):
            assert any(step[0] == s and step[1] == 1.0 for step in steps), "every foot ends on its idle place"
        treads = {"l": [], "r": []}
        at = {"l": (-1000.0, 0.0, 0.0), "r": (-1000.0, 0.0, 0.0)}
        # A foot's last step lands on its idle place; the steps before it land wider (`apart`), so two feet that
        # pass each other round the middle keep a foot's width between them.
        last = {s: max(i for i, step in enumerate(steps) if step[0] == s) for s in ("l", "r")}
        for i, (s, share, lift, land) in enumerate(steps):
            begun, yaw, out = at[s]
            treads[s].append(self._stand(s, begun, lift, yaw, n["toe_off"], n["heel"] if begun > 0 else 0.0, out))
            at[s] = (land, A * share, 0.0 if i == last[s] else n["apart"])
        for s in ("l", "r"):
            begun, yaw, out = at[s]
            treads[s].append(self._stand(s, begun, F + 1000.0, yaw, 0.0, n["heel"] if begun > 0 else 0.0, out))
        self.treads = treads
        self.steps = steps
        first, last = max(steps[0][2] - float(n["yaw_early"]), 1.0), last_land + float(n["yaw_late"])
        assert last <= F - 1.0, "the root stands still on the clip's last frame"
        self.turn_window = (first, last)

        def heading(x: float) -> float:
            u = (x - first) / (last - first)
            return A * maths.smoother(_skew(u, n["yaw_turn"]))

        self._root_curves(lambda x: 0.0, heading)

    def _carry(self, s: str, f: float) -> float:
        """How much of the weight a foot could take at a frame: 1 while it stands, 0 in the air, crossing over
        `shift_soft` frames round each lift and landing."""
        soft = float(self.n["shift_soft"])
        best = 0.0
        for tread in self.treads[s]:
            up = maths.smooth((f - tread.land) / soft + 0.5)
            down = maths.smooth((tread.lift - f) / soft + 0.5)
            best = max(best, min(up, down))
        return best

    def _spot_spec(self, f: float) -> dict:
        n, F = self.n, self.frames
        if f <= 0:
            return placed(self._idle_spec(0.0), np.zeros(2), 0.0)
        if f >= F:
            return placed(self._idle_spec(0.0), np.zeros(2), self.angle)
        xz, yaw = self.root(f)
        local = self._idle_spec(0.0)
        # The hips go over the standing foot, in the world, then back into the root's frame.
        balls = {}
        for s, _ in SIDES:
            tread = self.planted(s, f) or min(self.treads[s], key=lambda t: min(abs(t.land - f), abs(t.lift - f)))
            balls[s] = np.array(tread.place)
        carry = {s: self._carry(s, f) for s, _ in SIDES}
        total = carry["l"] + carry["r"]
        middle = 0.5 * (balls["l"] + balls["r"])
        over = (carry["l"] * balls["l"] + carry["r"] * balls["r"]) / max(total, 1e-9) if total > 1e-9 else middle
        shift = _rotate(-yaw, *(n["shift"] * (over - middle)))
        place = np.asarray(local["pelvis"]["place"], dtype=float).copy()
        place[0] += shift[0]
        place[2] += shift[1]
        up = max(1.0 - carry["l"], 1.0 - carry["r"])
        low = n["dip"] * maths.smooth(up) + float(np.interp(f, np.arange(F + 1), self.lower))
        place[1] += float(np.interp(f, np.arange(F + 1), self.level)) - low
        local["pelvis"] = {"place": place, "turn": tuple(local["pelvis"]["turn"])}
        turning = abs(yaw - self.root(f + 1.0)[1]) + abs(yaw - self.root(f - 1.0)[1])
        chest_by = self.root(f + n["chest_lead"] + self.lags.get("chest", [0.0])[0])[1] - yaw
        head_lag = self.lags.get("chest", [0.0])[0] + self.lags.get("head", [0.0])[0]
        head_by = self.root(f + n["head_lead"] + head_lag)[1] - yaw
        more = n["head_more"] * math.copysign(1.0, self.angle) * maths.smooth(turning / 6.0)
        c, h = tuple(local["chest"]), tuple(local["head"])
        local["chest"] = (c[0], c[1] + chest_by, c[2])
        local["head"] = (h[0], h[1] + head_by + more, h[2])
        wide = maths.smooth(turning / 6.0)
        arms = {}
        for s, _ in SIDES:
            arm = plain_arm(local["arm"][s])
            arm["out"] += n["arm_wide"][AT[s]] * wide
            # A thigh that comes forward as its foot steps is where the hanging hand is (the arm's `clear` reads
            # the thigh as the body stands): the arm on that side opens and goes back while the foot is up.
            up = 1.0 - self._carry(s, f)
            arm["out"] += n["arm_clear"][0] * up
            arm["swing"] -= n["arm_clear"][1] * up
            arms[s] = arm
        local["arm"] = arms
        out = placed({k: v for k, v in local.items() if k != "leg"}, xz, yaw)
        out["leg"] = {}
        for s, _ in SIDES:
            leg = self.leg(s, float(f))
            # A foot not yet turned with the hips would point its knee across the body (the solver's default
            # is the foot's way), into the other thigh: the knee points between the foot's way and the hips'.
            # Not at the ends, where the clip is the idle's own pose.
            fade = maths.smooth(min(abs(yaw), abs(self.angle - yaw)) / 15.0)
            knee = leg["foot"][1] + fade * n["knee_follow"] * (yaw - leg["foot"][1])
            leg["knee"] = np.array([math.sin(math.radians(knee)), 0.0, math.cos(math.radians(knee))])
            out["leg"][s] = leg
        return out

    # ---- a pivot or a reversal -----------------------------------------------------------------------------------

    def _moving_steps(self) -> None:
        n = self.n
        steps = [int(x) for x in n["steps"]]
        m = len(steps)
        assert steps[-1] == self.half and steps[-2] == self.half, "the last two steps are the gait's own"
        assert len(n["air"]) == m - 1, "`air` has a number for every landing but the last"
        assert len(n["gait_like"]) == m - 2, "`gait_like` has a number for every landing between the first and the last two"
        j = int(n["plant"])
        assert 2 <= j <= m - 3, "the plant is a landing of the clip's own, after the step that begins the brake"
        self.lands = [0.0] + [float(x) for x in np.cumsum(steps)]
        self.frames = int(self.lands[-1])
        T = self.plant_side
        self.sides = [T if (i - j) % 2 == 0 else OTHER[T] for i in range(m + 1)]
        self.plant = j
        self.phase = 0 if self.sides[0] == "l" else self.half
        self.end_phase = 0 if self.sides[-1] == "l" else self.half
        lifts = [self.lands[i + 1] + float(n["air"][i]) for i in range(m - 1)]
        self.lifts = lifts
        A, v = self.angle, self.v
        plant_land, plant_lift = self.lands[j], lifts[j]
        # The old way's momentum is spent while the plant foot is down: `stop` is where the velocity is half the
        # old way's and half the new way's (for a reversal, where the body stands still), late in the contact, so
        # the mass is carried on over the planted leg before the body turns.
        stop = plant_land + n["stop_at"] * (plant_lift - plant_land)
        back_at = self.lands[m - 1] - float(n["push_end"])
        brake_from = float(n["brake_from"])
        assert brake_from < stop < back_at, "the root brakes, then goes the new way"
        self.stop = stop
        p = float(n["brake_shape"])
        q = p * (back_at - stop) / (stop - brake_from)

        def w(x: float) -> float:
            """The share of the new way in the velocity: 0 before the brake, a half at the stop, 1 at `back_at`;
            the brake bites harder and harder, and the push starts as hard as the brake ended."""
            if x <= brake_from:
                return 0.0
            if x >= back_at:
                return 1.0
            if x <= stop:
                return 0.5 * ((x - brake_from) / (stop - brake_from)) ** p
            return 1.0 - 0.5 * (1.0 - (x - stop) / (back_at - stop)) ** q

        r = math.radians(A)
        old, new = np.array([0.0, 1.0]), np.array([math.sin(r), math.cos(r)])
        # The way back is beside the way in, toward the turn's side: the body shifts out to that side first.
        out = np.array([math.copysign(1.0, A), 0.0]) if abs(A) >= 180.0 else np.zeros(2)
        lane = float(n["lane"])
        low = float(n["low"])

        def velocity(x: float) -> np.ndarray:
            u = w(x)
            dip = 1.0 - (1.0 - low) * _bump(x, brake_from, stop, back_at)
            side = lane * (_ease(x + 0.05, brake_from, back_at) - _ease(x - 0.05, brake_from, back_at)) / 0.1 * FPS
            return v * dip * ((1.0 - u) * old + u * new) + side * out

        # The hips go side-on to the old way before the plant lands (`side_on` of the turn), hold there while the
        # plant brakes, and turn the rest of the way as the body pushes off it.
        f0 = self.lands[j - 1] - float(n["face_before"])
        f1 = plant_land + float(n["face_late"])
        t0, t1 = stop - float(n["turn_lead"]), stop + float(n["turn_after"])
        assert f0 >= 1.0 and f0 < f1 and t1 <= self.lands[m - 1], "the root turns inside the clip, before its last two landings"
        self.turn_window = (f0, t1)
        side_on = float(n["side_on"])

        def facing(x: float) -> float:
            first = maths.smooth(min(max((x - f0) / (f1 - f0), 0.0), 1.0))
            rest = maths.smooth(min(max((x - t0) / (t1 - t0), 0.0), 1.0))
            return A * (side_on * first + (1.0 - side_on) * rest)

        self._carry_window = (self.lands[j - 1], stop, plant_lift + float(n["carry_hold"]))
        self._root_vectors(velocity, facing)
        self._treads_moving()
        self._clock_moving()

    def _root_vectors(self, velocity, facing) -> None:
        """The root's curves from its velocity (m/s, on the floor) and the way it faces (degrees), which differ
        through a reversal: the body faces side-on and then back while it still travels the old way."""
        lo, hi = -(self.cycle * 3 + 4), self.frames + self.cycle * 3 + 4
        t = np.arange(lo * GRID, hi * GRID + 1) / GRID
        vel = np.array([velocity(x) for x in t])
        th = np.array([facing(x) for x in t])
        dt = 1.0 / (GRID * FPS)
        px = np.concatenate([[0.0], np.cumsum(0.5 * (vel[1:, 0] + vel[:-1, 0]) * dt)])
        pz = np.concatenate([[0.0], np.cumsum(0.5 * (vel[1:, 1] + vel[:-1, 1]) * dt)])
        at0 = -lo * GRID
        px, pz = px - px[at0], pz - pz[at0]
        self._t, self._th, self._px, self._pz = t, th, px, pz
        self._s = np.hypot(vel[:, 0], vel[:, 1])
        self._path = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(px), np.diff(pz)))])
        self._path -= self._path[at0]
        # The acceleration in the way the root faces: ahead, and to its left (as `checks._turning_accel` reads it).
        acc = np.gradient(vel, axis=0) * GRID * FPS
        rad = np.radians(th)
        self._a_fwd = acc[:, 0] * np.sin(rad) + acc[:, 1] * np.cos(rad)
        self._a_left = acc[:, 0] * np.cos(rad) - acc[:, 1] * np.sin(rad)
        self._lean = self._leans()

    def _own(self, s: str, land: float, lift: float | None = None) -> Tread:
        """A contact of the gait itself, landing where the gait would put it with its root where the clip's root
        is at that frame (before the clip, or after it, on the straight way in or out)."""
        g = self.g
        xz, yaw = self.root(land)
        numbers = self._numbers(s, 1.0)
        place = xz + _rotate(yaw, SIGN[s] * g.own(s, "width"), self._reach(s))
        end = land + self.contact if lift is None else lift
        return Tread(s, land, end, (float(place[0]), float(place[1])), SIGN[s] * g.own(s, "toe_out") + yaw, numbers, numbers, self.v)

    def _free(self, s: str, land: float, lift: float, like: float, plant: bool = False, brake: bool = False, push: bool = False) -> Tread:
        """A step of the clip's own: where a steady step would land, moved against the acceleration."""
        g, n = self.g, self.n
        numbers = self._numbers(s, like)
        mid = 0.5 * (land + lift)
        covered = self.path(lift) - self.path(land)
        ahead = g.own(s, "ahead") * covered + (gaits.UNEVEN_REACH * g.n["uneven"] * like if s == "r" else 0.0)
        back = n["drive"] * self.h * self.a_fwd(mid) / weight.G
        out = n["drive"] * self.h * self.a_left(mid) / weight.G
        ahead = min(max(ahead - back, covered - n["reach_back"]), n["reach_fore"])
        idle = self.idle_falls[s]
        wide = abs(idle.place[0]) + (g.own(s, "width") - abs(idle.place[0])) * like
        x = SIGN[s] * wide - max(min(out, n["reach_side"]), -n["reach_side"])
        if plant:
            x -= math.copysign(n["plant_wide"], self.angle)
        # Each foot stays on its own side: a foot that crosses in front of the other folds the thighs into
        # each other (65 mm in the limbs check), and the bend's lean goes to the trunk instead.
        x = SIGN[s] * max(SIGN[s] * x, n["own_side"])
        xz, yaw = self.root(mid)
        place = xz + _rotate(yaw, x, ahead - 0.5 * covered)
        if brake:
            # The step that begins the brake lands wide toward the turn's side, on the floor's axes (the hips are
            # already turning, so their own side points back): the body shifts out over it, and the plant leg
            # swings round in front of it with room (a narrow one put shin in shin, 30 mm).
            place = place + np.array([n["brake_wide"] * math.copysign(1.0, self.angle), 0.0])
        if push:
            # The first step off the plant lands on its own side of the planted leg (less than 0: away from the
            # turn's side, which is the body's other side once it faces the new way).
            place = place + np.array([n["push_wide"] * math.copysign(1.0, self.angle), 0.0])
        if plant:
            # The plant lands well ahead of the body, the old way, where the mass will be carried over it: from
            # the root's place at the stop, `plant_out` metres the old way and `plant_aside` toward the turn.
            at, _ = self.root(self.stop)
            place = at + np.array([n["plant_aside"] * math.copysign(1.0, self.angle), n["plant_out"]])
        toe = idle.yaw + (SIGN[s] * g.own(s, "toe_out") - idle.yaw) * like
        # A foot cannot turn while it stands: it is set down turned a share of the way the root turns over the
        # contact, so the knee above it points neither across the body as it lands nor far out as it leaves.
        first, last = self.root(land)[1], self.root(lift)[1]
        yaw = first + n["plant_turn" if plant else "foot_turn"] * (last - first)
        room = max(lift - land - numbers["roll_in"], 0.0)
        numbers["roll_out"] = min(max(numbers["roll_out"], n["heel_early"] * (lift - land)), room)
        # A foot that leaves a leaning or twisted leg cannot point its toes as far as a straight run's does.
        numbers["toe_off"] = min(numbers["toe_off"], n["toe_most"])
        if land > self._slowest():
            # A step that speeds the body up lands under it, the shin leaning forward: on a flat foot or its
            # ball, not on a heel with the toes drawn up (the ankle would bend past its range).
            numbers["heel_strike"] = min(numbers["heel_strike"], n["push_heel"])
        return Tread(s, land, lift, (float(place[0]), float(place[1])), yaw + toe, numbers, numbers, self.speed(land))

    def _treads_moving(self) -> None:
        n, F = self.n, float(self.frames)
        lands, lifts, sides = self.lands, self.lifts, self.sides
        m = len(lands) - 1
        like = [float(x) for x in n["gait_like"]]
        a, b = sides[0], OTHER[sides[0]]
        treads = {"l": [], "r": []}
        for back in (2, 1):
            treads[a].append(self._own(a, -back * self.cycle))
            treads[b].append(self._own(b, -back * self.cycle - self.half))
        treads[b].append(self._own(b, -float(self.half)))
        strike = self._own(a, 0.0, lift=lifts[0])
        strike.foot = dict(strike.foot)
        slow = self._numbers(a, like[0])
        strike.foot["roll_out"] = min(slow["roll_out"] + 1.0, lifts[0] - strike.foot["roll_in"])
        strike.foot["toe_off"] = slow["toe_off"]
        treads[a].append(strike)
        for i in range(1, m - 1):
            treads[sides[i]].append(self._free(sides[i], lands[i], lifts[i], like[i - 1], i == self.plant, i == self.plant - 1, i == self.plant + 1))
        for i in (m - 1, m):
            treads[sides[i]].append(self._own(sides[i], lands[i]))
        treads[sides[m - 1]].append(self._own(sides[m - 1], F + self.half))
        treads[sides[m]].append(self._own(sides[m], F + self.cycle))
        if self.contact < self.half:
            # A run: the other foot is in the air as the clip begins, on its way to the gait's next landing.
            self.ghost = self._own(b, float(self.half))
        self.treads = treads

    def _clock_moving(self) -> None:
        """The gait's frame the body is at on each frame: through every landing at that foot's frame of the cycle,
        at the gait's pace through a flight and at both ends."""
        half, F = self.half, float(self.frames)
        knots = {land: self.phase + i * half for i, land in enumerate(self.lands)}
        if self.contact < half:
            for s, _ in SIDES:
                for tread in self.treads[s]:
                    if tread.land not in knots or not 0.0 < tread.lift < F:
                        continue
                    after = [land for land in knots if land > tread.lift]
                    if after and min(after) - tread.lift >= 2.0 and self.planted(OTHER[s], tread.lift + 0.5) is None:
                        knots[float(tread.lift)] = max(
                            knots[min(after)] - (min(after) - tread.lift), knots[tread.land] + 0.5 * (tread.lift - tread.land)
                        )
        self._knots = sorted(knots.items())
        reach = 6
        grid = np.arange(-reach * 10, (self.frames + reach) * 10 + 1) / 10.0
        raw = np.array([clock(self._knots, float(x), 1.0, 1.0) for x in grid])
        kernel = np.exp(-0.5 * (np.arange(-45, 46) / 15.0) ** 2)
        self._clock_at = grid[45:-45]
        self._clock_is = np.convolve(raw, kernel / kernel.sum(), mode="valid")

    def _gait_world(self, phase: float, f: float) -> dict:
        """The shipped gait's own spec at a whole frame of its cycle, its root where the clip's is at frame `f`."""
        g = self.g
        k = int(round(phase)) % self.cycle
        spec = g.spec(float(k))
        back = np.array([0.0, 0.0, -self.v * k / FPS])
        spec["pelvis"] = {"place": spec["pelvis"]["place"] + back, "turn": tuple(spec["pelvis"]["turn"])}
        spec["leg"] = {s: {**spec["leg"][s], "ankle": spec["leg"][s]["ankle"] + back} for s, _ in SIDES}
        xz, yaw = self.root(f)
        return placed(spec, xz, yaw)

    def leg(self, s: str, f: float) -> dict:
        """`Move.leg`, but the swing the clip begins inside starts as the shipped gait's own leg, not as a swing
        made from the clip's treads: frame 0 is the gait's spec, and frame 1 must go on the way it went (a swing
        retargeted to the clip's own landing stepped 40 to 130 mm off the gait's in `test_own_turns.gd`)."""
        out = super().leg(s, f)
        ghost = self.ghost
        if self.spot or ghost is None or s != ghost.side or self.planted(s, f) is not None or not 0.0 < f:
            return out
        before = [t for t in self.treads[s] if t.lift < f]
        after = [t for t in self.treads[s] if t.land > f]
        if not (before and after and before[-1].lift < 0.0 < after[0].land):
            return out
        mine = self._swing(before[-1], after[0], f)
        g = self.g
        k = math.fmod(self.phase + f, float(self.cycle))
        spec = g.spec(k)
        leg = spec["leg"][s]
        xz, yaw = self.root(f)
        ankle = np.asarray(leg["ankle"], dtype=float) + np.array([0.0, 0.0, -self.v * k / FPS])
        rest = {"pelvis": {"place": np.zeros(3), "turn": (0.0, 0.0, 0.0)}, "leg": {s: {**leg, "ankle": ankle}}}
        own = placed(rest, xz, yaw)["leg"][s]
        share = maths.smoother(f / after[0].land)
        out = {
            "ankle": own["ankle"] + (mine["ankle"] - own["ankle"]) * share,
            "foot": tuple(x + (y - x) * share for x, y in zip(own["foot"], mine["foot"], strict=True)),
            "toe": own["toe"] + (mine["toe"] - own["toe"]) * share,
        }
        out["ankle"] = out["ankle"] + maths.Y * self.set_down.get((s, f), 0.0)
        return out

    def _moving_spec(self, f: float) -> dict:
        n, F = self.n, self.frames
        if f <= 0:
            return self._gait_world(self.phase + f, float(f))
        if f >= F:
            return self._gait_world(self.end_phase + (f - F), float(f))
        phase = self.gait_frame(float(f))
        own = self.g.spec(phase)
        idle = self.idle
        xz, yaw = self.root(f)
        wb = n["brace"] * _bump(f / F, n["brace_from"], self._slowest() / F, n["brace_to"])
        pitch, lean = self.lean_at(float(f))
        rel = self._pelvis_rel(phase)
        rel[1] = self._middle + (rel[1] - self._middle) * (1.0 + (n["bob"] - 1.0) * self._own_share(float(f)))
        place = mix(rel, np.asarray(idle["pelvis"]["place"], dtype=float), wb)
        place[2] += n["lean_fore"] * self.h * math.tan(math.radians(pitch))
        place[0] += n["side_fore"] * self.h * math.tan(math.radians(lean))
        tilt = min(math.hypot(math.tan(math.radians(pitch)), math.tan(math.radians(lean))), 0.6)
        low = n["lean_low"] * self.h * tilt + n["dip"] * _bump(f, self.lands[self.plant] - 3, self._slowest(), self.lifts[self.plant] + 4)
        low += float(np.interp(f, np.arange(F + 1), self.lower))
        place[1] += float(np.interp(f, np.arange(F + 1), self.level)) - low
        turn = mix(tuple(own["pelvis"]["turn"]), tuple(idle["pelvis"]["turn"]), wb)
        chest = mix(tuple(own["chest"]), tuple(idle["chest"]), wb)
        head = mix(tuple(own["head"]), tuple(idle["head"]), wb)
        chest_by = self.root(f + n["chest_lead"] + self.lags.get("chest", [0.0])[0])[1] - yaw
        head_lag = self.lags.get("chest", [0.0])[0] + self.lags.get("head", [0.0])[0]
        head_by = self.root(f + n["head_lead"] + head_lag)[1] - yaw
        arms = max(self.arms_share(f, wb), min(tilt / 0.4, 1.0))
        local = {
            "pelvis": {"place": place, "turn": (turn[0] + n["lean_hips"] * pitch, turn[1], turn[2] + n["side_hips"] * lean)},
            "chest": (chest[0] + n["lean"] * pitch, chest[1] + chest_by, chest[2] + n["side"] * lean),
            "ribs": idle["ribs"] * wb,
            "head": (head[0] + n["lean_head"] * pitch, head[1] + head_by, head[2] + n["side_head"] * lean),
            "clavicle": {s: mix(tuple(own["clavicle"][s]), tuple(idle["clavicle"][s]), wb) for s, _ in SIDES},
            "arm": {s: self._wide_arm(mix(plain_arm(own["arm"][s]), self.idle_arms[s], wb), s, arms) for s, _ in SIDES},
            "fingers": {s: mix(dict(own["fingers"][s]), dict(idle["fingers"][s]), wb) for s, _ in SIDES},
        }
        out = placed(local, xz, yaw)
        out["leg"] = {s: self.leg(s, float(f)) for s, _ in SIDES}
        return out

    def _slowest(self) -> float:
        return self.stop

    def _own_share(self, f: float) -> float:
        """How far a frame is from the gait's own steps: 0 at both ends, 1 between the first and the last two."""
        first, last = self.lands[1], self.lands[-3]
        return maths.smooth((f - 0.5 * first) / max(0.5 * first, 1.0)) * maths.smooth((last + 0.5 * self.half - f) / (0.5 * self.half))

    def arms_share(self, f: float, wb: float) -> float:
        return min(1.0, wb / max(self.n["brace"], 1e-6))

    def _wide_arm(self, arm: dict, s: str, share: float) -> dict:
        arm["out"] = arm["out"] + self.n["arm_wide"][AT[s]] * maths.smooth(share)
        return arm

    # ---- both ----------------------------------------------------------------------------------------------------

    def spec(self, f: float) -> dict:
        return self._spot_spec(f) if self.spot else self._moving_spec(f)

    def _swing(self, a: Tread, b: Tread, f: float) -> dict:
        """A foot in the air between two contacts: `Move._swing`, its ease measured along the floor whichever way
        the foot goes, carried round a turn on the spot about the root, and kept clear of the standing foot."""
        out = self._moving_swing(a, b, f) if not self.spot else self._spot_swing(a, b, f)
        other = self.planted(OTHER[a.side], f)
        if other is None:
            # A foot that has only just left the floor is still where it stood.
            gone = [t for t in self.treads[OTHER[a.side]] if t.lift <= f <= t.lift + 4.0]
            if not gone:
                return out
            other = gone[-1]
        u = (f - a.lift) / (b.land - a.lift)
        start, end = np.array(a.place), np.array(b.place)
        foot = np.array(other.place)
        # The foot's line from place to place against the standing foot's place: push the swing away from it.
        line = end - start
        length = float(np.linalg.norm(line))
        if length < 1e-6:
            return out
        along = float(np.clip(np.dot(foot - start, line) / (length * length), 0.0, 1.0))
        near = start + along * line
        gap = foot - near
        apart = float(np.linalg.norm(gap))
        want = 0.13 + self.n.get("clear", 0.05)
        if apart >= want:
            return out
        away = -gap / max(apart, 1e-6) if apart > 1e-6 else np.array([-line[1], line[0]]) / length
        push = (want - apart) * math.sin(math.pi * u) ** 2
        if a.lift < 0.0 < f:
            # A swing the clip begins inside is the gait's own on frame 0, with no push: let the push in from there,
            # or the foot jumps sideways between the first two frames (130 mm in `test_own_turns.gd`).
            push *= maths.smoother(f / max(b.land, 1.0))
        elif a.lift < 0.0:
            push = 0.0
        out["ankle"] = out["ankle"] + np.array([away[0], 0.0, away[1]]) * push
        return out

    def _moving_swing(self, a: Tread, b: Tread, f: float) -> dict:
        """`Move._swing` with two changes for a root that turns: the foot's yaw in the air follows the root's
        (offset by what it had as it left, then by what it will have as it lands), so the knee over it points the
        way the hips do and does not sweep across the other leg; and how still the foot lands is measured along
        the floor whichever way it goes."""
        s, n, g = a.side, b.swing, self.g
        sole = self.rig.sole[s]
        frames = b.land - a.lift
        u = (f - a.lift) / frames
        one, two = self._stance(a, a.lift), self._stance(b, b.land)
        more = 1.0 + (gaits.UNEVEN_LIFT * g.n["uneven"] if s == "r" else 0.0)
        eased = (1.0 - n["swing_ease"]) * maths.smooth(u) + n["swing_ease"] * maths.smoother(u)
        go = (1.0 - n["swing_early"]) * eased + n["swing_early"] * (1.0 - (1.0 - u) ** 2)
        gap = max(float(np.linalg.norm((two["ankle"] - one["ankle"])[[0, 2]])), 1e-6)
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
        body = self.root(f)[1]
        off_a = a.yaw - self.root(a.lift)[1]
        off_b = b.yaw - self.root(b.land)[1]
        yaw = body + off_a + (off_b - off_a) * maths.smooth(u)
        toe = one["toe"] * (1.0 - maths.smooth(u / 0.3))
        turn = body_turn(pitch, yaw, 0.0)
        hinge = ankle + turn @ (sole["hinge"] - sole["ankle"])
        tip = hinge + body_turn(pitch - toe, yaw, 0.0) @ (sole["toe"] - sole["hinge"])
        heel = ankle + turn @ (sole["heel"] - sole["ankle"])
        ball = ankle + turn @ (sole["ball"] - sole["ankle"])
        margin = 0.006 * maths.smooth(u / 0.15) * maths.smooth((1.0 - u) / 0.1)
        ankle[1] += max(sole["floor"] + margin - min(tip[1], heel[1], ball[1]), 0.0)
        return {"ankle": ankle, "foot": (pitch, yaw, 0.0), "toe": toe}

    def _spot_swing(self, a: Tread, b: Tread, f: float) -> dict:
        """A stepping foot on the spot: its ball goes round the root's middle, its yaw turns, it lifts by `lift`."""
        rig, s = self.rig, a.side
        sole = rig.sole[s]
        u = (f - a.lift) / (b.land - a.lift)
        go = maths.smoother(u)
        one, two = self._stance(a, a.lift), self._stance(b, b.land)
        pa, pb = np.array(a.place), np.array(b.place)
        ra, rb = float(np.linalg.norm(pa)), float(np.linalg.norm(pb))
        ta, tb = math.atan2(pa[0], pa[1]), math.atan2(pb[0], pb[1])
        if tb - ta > math.pi:
            tb -= 2 * math.pi
        if ta - tb > math.pi:
            tb += 2 * math.pi
        r, th = ra + (rb - ra) * go, ta + (tb - ta) * go
        ball = np.array([r * math.sin(th), sole["floor"], r * math.cos(th)])
        pitch_a, pitch_b = one["foot"][0], two["foot"][0]
        pitch = pitch_a + (pitch_b - pitch_a) * maths.smooth((u - 0.1) / 0.8)
        yaw = a.yaw + (b.yaw - a.yaw) * go
        state = self._state(s, "ball", ball, pitch, yaw)
        state["ankle"][1] += float(self.n["lift"]) * math.sin(math.pi * u) ** 2
        state["toe"] = 0.0
        heel = state["ankle"] + body_turn(pitch, yaw, 0.0) @ (sole["heel"] - sole["ankle"])
        tip = state["ankle"] + body_turn(pitch, yaw, 0.0) @ (sole["toe"] - sole["ankle"])
        margin = 0.004 * maths.smooth(u / 0.15) * maths.smooth((1.0 - u) / 0.1)
        state["ankle"][1] += max(sole["floor"] + margin - min(tip[1], heel[1]), 0.0)
        return state

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
                        float(max(tread.land, -1.0)),
                        float(min(tread.lift, self.frames + 1.0)),
                        tread.place,
                        yaw=tread.yaw,
                        heel_strike=max(n["heel_strike"], 0.0),
                        roll_in=n["roll_in"],
                        toe_off=n["toe_off"],
                        roll_out=n["roll_out"],
                    )
                )
        travel = Travel(
            forward=lambda f: float(self.root(f)[0][1]),
            left=lambda f: float(self.root(f)[0][0]),
            turn=lambda f: float(self.root(f)[1]),
        )
        return ContactPlan(self.frames, falls, travel, loop=False, tread=False)


def _skew(u: float, turn: float) -> float:
    """0 to 1, moving fastest at the share `turn` of the way (0.5: evenly); for an ease on top of it."""
    u = min(max(u, 0.0), 1.0)
    if abs(turn - 0.5) < 1e-9:
        return u
    # A power that puts the curve's middle (a half) at `turn`.
    return u ** (math.log(0.5) / math.log(turn))


def describe(kind: str, side: str, rig, style, name: str, joined) -> Clip:
    assert joined is not None, "a turn needs the clips it joins (`clips.joined.Joined`)"
    spot = kind.startswith("turn_in_place")
    n = style.numbers(kind, (SPOTS if spot else MOVES)[kind])
    turn = Turn(rig, joined, kind, side, n)
    turn.settle()
    F = turn.frames
    if spot:
        idle = joined.built("Idle")
        at = (idle.rotation[0], idle.translation[0])
        joins = {"first": at, "last": at, "first_speed": 0.0, "last_speed": 0.0}
        meet = {"first": (idle.frames[0], n["meet"]), "last": (idle.frames[0], n["meet"])}
        names = {"first": "Idle", "last": "Idle"}
        free = float(turn.steps[-1][3])
        lead = 0
        lags = joined.style("Idle").overlap("idle")
    else:
        gait_name = turn.gait_kind.capitalize()
        own = joined.built(gait_name)
        k0, k1 = turn.phase, turn.end_phase
        joins = {
            "first": (own.rotation[k0], own.translation[k0]),
            "last": (own.rotation[k1], own.translation[k1]),
            "first_speed": turn.v,
            "last_speed": turn.v,
        }
        meet = {"first": (own.frames[k0], n["meet"]), "last": (own.frames[k1], n["meet"])}
        names = {"first": gait_name, "first_frame": k0, "last": gait_name, "last_frame": k1}
        free = float(turn.lands[-2])
        lead = turn.cycle
        lags = turn.lags
    end, _ = turn.root(float(F))
    declared = {
        "joins": joins,
        "distance": round(float(np.hypot(end[0], end[1])), 6),
        "turn": turn.angle,
        "join_names": names,
        "speed_limit": n["speed_limit"],
        "lean_limit": n["lean_limit"],
        "side_lean_limit": n["side_lean_limit"],
        "lean_over": max(turn.half, 6),
        "turn_window": [round(x, 2) for x in turn.turn_window],
        "feet": [
            (t.side, t.land, t.lift, round(t.place[0], 3), round(t.place[1], 3), round(t.yaw, 1), round(turn.path(min(t.lift, F + 20.0)) - turn.path(max(t.land, -20.0)), 2))
            for s, _ in SIDES
            for t in turn.treads[s]
            if -1.0 <= t.lift and t.land <= F + 1.0
        ],
        "lowered": round(float(turn.lower.max()), 3),
        "keys_kept": n["keys_kept"],
        "kb_a_second": n["kb_a_second"],
    }
    return Clip(
        name=name,
        frames=F,
        plan=turn.plan(),
        spec=turn.spec,
        loop=False,
        meet=meet,
        chains=overlap.chains_from(lags, gaits.PARTS),
        kind="transition",
        lead=lead,
        declared=declared,
        # From here the game may cut to new input: the feet are the gait's own, or the turn's last step is down.
        events=[{"frame": free, "name": "free"}],
        style=style.letter,
    )


def family(kind: str) -> list:
    """The clips of one type, `[(name, describe), ...]`: the left one, then the right one."""
    stem = {
        "jog_turn_90": "Jog_Turn_90",
        "jog_turn_180": "Jog_Turn_180",
        "sprint_turn_180": "Sprint_Turn_180",
        "turn_in_place_90": "Turn_In_Place_90",
        "turn_in_place_180": "Turn_In_Place_180",
    }[kind]
    out = []
    for side in ("l", "r"):

        def one(rig, style, name, joined=None, side=side):
            return describe(kind, side, rig, style, name, joined)

        out.append((f"{stem}_{side.upper()}", one))
    return out
