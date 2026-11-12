"""One pose from controls.

A description gives, for a frame, a `spec`: where the pelvis is and how it is turned, how the chest and the head are
turned, where each ankle is and how its foot lies, how each arm hangs or where its wrist is, how far the fingers
curl. `Solver.solve` turns that into every bone's rotation in its parent. Nothing is posed bone by bone: a limb is a
two-bone solve about the rig's own hinge, the spine is spread between the pelvis's turn and the chest's.

Every turn is a turn from the standing rest in the character's space (`maths.body_turn`: pitch forward, yaw to the
left, lean to the left, degrees), so a description never touches a bone's own axes, which a glTF rig leaves
arbitrary.

The spec (every key but `pelvis` and `leg` may be left out):

| Key | Value |
| --- | --- |
| `pelvis` | `{"place": (x, y, z), "turn": (pitch, yaw, lean)}`: the pelvis joint and its turn |
| `chest` | `(pitch, yaw, lean)`: the turn of the top of the spine; the two bones under it are spread from the pelvis's turn |
| `ribs` | degrees the chest lifts with a breath (the upper spine opens backward, on top of `chest`) |
| `head` | `(pitch, yaw, lean)`: the head's turn; the neck goes `neck` of the way (default a half) from the chest |
| `clavicle` | per side `(lift, forward)` degrees from the chest |
| `arm` | per side, a hanging arm: `swing` forward, `out` from the body, `twist` inward about the upper arm, `bend` of the elbow, `pronate` (the thumb turned inward about the forearm), `wrist` flexed toward the palm, `clear` (metres the wrist, the knuckles and the curled fingers' tips keep from the thigh's line, on every body: `out` grows until they do) and `carry`, the share of the chest's tilt the arm takes (0 hangs straight down whatever the chest does, 1 is fixed to the chest); or a placed hand: `wrist_at` (a point), `pole` (the way the elbow points) and `palm` (the way the palm faces) |
| `leg` | per side: `ankle` (the ankle joint), `foot` `(pitch, yaw, lean)` (pitch puts the toes down), `toe` (degrees the toes bend up), `knee` (the way the knee points; default the way the foot does) |
| `fingers` | per side, degrees each finger curls over its three joints together: `{"index": 60, ..., "thumb": 20}`, each joint taking the share in `FINGER_SHARE`; `thumb_out` lifts the thumb from under the palm (where the rest pose has it, 47 degrees down) toward the palm's own plane |
"""

import math

import numpy as np

from . import maths
from .maths import X, Y, Z, aim_turn, axis_angle, body_turn, square_to, unit
from .rig import FINGERS, SIDES, Rig

## The share of a finger's curl each of its three joints takes (the knuckle most, as a relaxed hand curls).
FINGER_SHARE = (0.45, 0.35, 0.20)
## The length of a finger from its knuckle to its tip (m), for keeping a curled hand clear of the thigh.
FINGER_LENGTH = 0.085
## The furthest a two-bone limb reaches, as a share of its length: past it the joint snaps straight.
REACH = 0.9995


def _yaw_only(turn: np.ndarray) -> np.ndarray:
    ahead = turn @ Z
    return axis_angle(Y, math.degrees(math.atan2(ahead[0], ahead[2])))


class Solver:
    """Solves poses on one rig. `miss` of a solved pose says how far each target was out of reach (m)."""

    def __init__(self, rig: Rig, bodies: list | None = None):
        """`bodies` are the other rigs the clips play on: an arm told to keep clear of the thigh (`clear`) keeps
        every body's wrist and knuckles clear, the longer arms too."""
        self.rig = rig
        self._arms = {}
        for s, _ in SIDES:
            self._arms[s] = [
                (
                    body.local_pos["upperarm_" + s],
                    body.length["upperarm_" + s],
                    body.length["lowerarm_" + s],
                    float(np.linalg.norm(body.rest_pos["middle_01_" + s] - body.rest_pos["hand_" + s])),
                )
                for body in [rig] + list(bodies or [])
            ]
        self._finger_hinge = {}
        for s, sign in SIDES:
            for finger in FINGERS:
                for joint in ("01", "02", "03"):
                    name = f"{finger}_{joint}_{s}"
                    rest = rig.rest_rot[name]
                    # A finger curls toward the palm, which faces the floor in the rest pose; the thumb closes
                    # toward the index finger, in the palm's plane.
                    hinge = sign * Y if finger == "thumb" else unit(np.cross(rest[:, 1], -Y))
                    self._finger_hinge[name] = rest.T @ hinge

    def _place(self, world: dict, name: str, rot: np.ndarray) -> None:
        rig = self.rig
        p = rig.parent[name]
        m = np.eye(4)
        m[:3, :3] = rot
        m[:3, 3] = world[p][:3, :3] @ rig.local_pos[name] + world[p][:3, 3]
        world[name] = m

    # ---- the trunk ------------------------------------------------------------------------------------------

    def _trunk(self, spec: dict, world: dict, turns: dict) -> None:
        rig = self.rig
        pelvis = spec["pelvis"]
        turn_p = body_turn(*pelvis.get("turn", (0.0, 0.0, 0.0)))
        turn_c = body_turn(*spec.get("chest", (0.0, 0.0, 0.0)))
        ribs = spec.get("ribs", 0.0)
        turns["pelvis"] = turn_p
        turns["spine_01"] = maths.slerp(turn_p, turn_c, 1.0 / 3.0)
        turns["spine_02"] = maths.slerp(turn_p, turn_c, 2.0 / 3.0) @ axis_angle(X, -0.5 * ribs)
        turns["spine_03"] = turn_c @ axis_angle(X, -ribs)
        turn_h = body_turn(*spec.get("head", (0.0, 0.0, 0.0)))
        turns["neck_01"] = maths.slerp(turns["spine_03"], turn_h, spec.get("neck", 0.5))
        turns["Head"] = turn_h
        root = rig.parent["pelvis"]
        world[root] = rig.rest[root].copy()
        for name in ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head"):
            self._place(world, name, turns[name] @ rig.rest_rot[name])
            if name == "pelvis":
                world[name][:3, 3] = np.asarray(pelvis["place"], dtype=float)

    # ---- an arm ---------------------------------------------------------------------------------------------

    def _arm(self, spec: dict, world: dict, turns: dict, s: str, sign: float, miss: dict) -> None:
        rig = self.rig
        chest = turns["spine_03"]
        lift, forward = spec.get("clavicle", {}).get(s, (0.0, 0.0))
        clav = chest @ axis_angle(Z, sign * lift) @ axis_angle(Y, -sign * forward)
        self._place(world, "clavicle_" + s, clav @ rig.rest_rot["clavicle_" + s])
        upper, lower, hand = "upperarm_" + s, "lowerarm_" + s, "hand_" + s
        self._place(world, upper, world["clavicle_" + s][:3, :3])  # the place only; turned below
        shoulder = world[upper][:3, 3]
        arm = spec.get("arm", {}).get(s, {})
        len_u, len_f = rig.length[upper], rig.length[lower]
        if "wrist_at" in arm:
            to = np.asarray(arm["wrist_at"], dtype=float) - shoulder
            far = np.linalg.norm(to)
            dist = min(far, (len_u + len_f) * REACH)
            miss["wrist_" + s] = far - dist
            along = unit(to)
            a = (len_u**2 - len_f**2 + dist**2) / (2 * dist)
            pole = square_to(np.asarray(arm.get("pole", -Z), dtype=float), along)
            elbow = shoulder + a * along + math.sqrt(max(len_u**2 - a**2, 0.0)) * pole
            aim_u = unit(elbow - shoulder)
            aim_f = unit(shoulder + dist * along - elbow)
            bend_dir = square_to(aim_f, aim_u, fallback=-pole)
            palm = np.asarray(arm.get("palm", -Y), dtype=float)
            thumb = unit(sign * np.cross(square_to(palm, aim_f), aim_f))
            thumb_f = thumb
        else:
            base = maths.slerp(_yaw_only(chest), chest, arm.get("carry", 0.3))
            flex = math.radians(arm.get("wrist", 0.0))

            curls = spec.get("fingers", {}).get(s, {})
            # Where a curled finger's tip is from its knuckle: about two thirds of its curl along the way.
            curl = math.radians(0.65 * max((curls.get(finger, 0.0) for finger in FINGERS[1:]), default=0.0))

            def hang(out_deg: float) -> tuple:
                swing, out = math.radians(arm.get("swing", 0.0)), math.radians(out_deg)
                way = [sign * math.sin(out), -math.cos(out) * math.cos(swing), math.cos(out) * math.sin(swing)]
                aim_u = base @ unit(np.array(way))
                bend_dir = axis_angle(aim_u, sign * arm.get("twist", 0.0)) @ square_to(base @ Z, aim_u, base @ Y)
                bend = math.radians(arm.get("bend", 0.0))
                aim_f = math.cos(bend) * aim_u + math.sin(bend) * bend_dir
                neutral = square_to(bend_dir, aim_f, fallback=-aim_u)
                pronate = arm.get("pronate", 0.0)
                thumb_f = axis_angle(aim_f, sign * 0.5 * pronate) @ neutral
                thumb = axis_angle(aim_f, sign * pronate) @ neutral
                return aim_u, bend_dir, aim_f, thumb_f, thumb

            def gap(out_deg: float) -> float:
                """The least distance of the wrist and the knuckles from the thigh's line, on every body."""
                aim_u, _, aim_f, _, thumb = hang(out_deg)
                palm = sign * np.cross(aim_f, thumb)
                fingers = math.cos(flex) * aim_f + math.sin(flex) * palm
                palm = palm - fingers * np.dot(palm, fingers)
                hip, knee = world["thigh_" + s][:3, 3], world["calf_" + s][:3, 3]
                least = math.inf
                for offset, upper_len, fore_len, hand_len in self._arms[s]:
                    wrist = world["clavicle_" + s][:3, :3] @ offset + world["clavicle_" + s][:3, 3]
                    wrist = wrist + upper_len * aim_u + fore_len * aim_f
                    knuckles = wrist + hand_len * fingers
                    tip = knuckles + FINGER_LENGTH * (math.cos(curl) * fingers + math.sin(curl) * palm)
                    for point in (wrist, knuckles, tip):
                        along = float(np.clip(np.dot(point - hip, knee - hip) / np.dot(knee - hip, knee - hip), 0, 1))
                        least = min(least, float(np.linalg.norm(point - hip - along * (knee - hip))))
                return least

            out_deg = arm.get("out", 0.0)
            clear = arm.get("clear", 0.0)
            if clear > 0.0 and gap(out_deg) < clear:
                low, high = out_deg, out_deg + 50.0
                for _ in range(14):
                    middle = 0.5 * (low + high)
                    low, high = (middle, high) if gap(middle) < clear else (low, middle)
                out_deg = high
            aim_u, bend_dir, aim_f, thumb_f, thumb = hang(out_deg)
        rest_u = unit(rig.rest_pos[lower] - rig.rest_pos[upper])
        rest_f = unit(rig.rest_pos[hand] - rig.rest_pos[lower])
        rest_g = unit(rig.rest_pos["middle_01_" + s] - rig.rest_pos[hand])
        self._place(world, upper, aim_turn(rest_u, Z, aim_u, bend_dir) @ rig.rest_rot[upper])
        self._place(world, lower, aim_turn(rest_f, Z, aim_f, thumb_f) @ rig.rest_rot[lower])
        flex = math.radians(arm.get("wrist", 0.0))
        palm_way = sign * np.cross(aim_f, thumb)
        fingers = math.cos(flex) * aim_f + math.sin(flex) * palm_way
        self._place(world, hand, aim_turn(rest_g, Z, fingers, thumb) @ rig.rest_rot[hand])

    # ---- a leg ----------------------------------------------------------------------------------------------

    def _leg(self, spec: dict, world: dict, s: str, miss: dict) -> None:
        rig = self.rig
        leg = spec["leg"][s]
        thigh, calf, foot, ball = "thigh_" + s, "calf_" + s, "foot_" + s, "ball_" + s
        self._place(world, thigh, world["pelvis"][:3, :3])  # the place only; turned below
        hip = world[thigh][:3, 3]
        len_t, len_c = rig.length[thigh], rig.length[calf]
        turn_f = body_turn(*leg.get("foot", (0.0, 0.0, 0.0)))
        to = np.asarray(leg["ankle"], dtype=float) - hip
        far = np.linalg.norm(to)
        dist = min(far, (len_t + len_c) * REACH)
        miss["ankle_" + s] = far - dist
        along = unit(to)
        a = (len_t**2 - len_c**2 + dist**2) / (2 * dist)
        pole = square_to(np.asarray(leg.get("knee", _yaw_only(turn_f) @ Z), dtype=float), along)
        knee = hip + a * along + math.sqrt(max(len_t**2 - a**2, 0.0)) * pole
        aim_t = unit(knee - hip)
        aim_c = unit(hip + dist * along - knee)
        hinge = unit(np.cross(along, pole))
        rest_t = unit(rig.rest_pos[calf] - rig.rest_pos[thigh])
        rest_c = unit(rig.rest_pos[foot] - rig.rest_pos[calf])
        self._place(world, thigh, aim_turn(rest_t, -X, aim_t, hinge) @ rig.rest_rot[thigh])
        self._place(world, calf, aim_turn(rest_c, -X, aim_c, hinge) @ rig.rest_rot[calf])
        self._place(world, foot, turn_f @ rig.rest_rot[foot])
        toes = axis_angle(turn_f @ X, -leg.get("toe", 0.0)) @ turn_f
        self._place(world, ball, toes @ rig.rest_rot[ball])

    # ---- the whole pose -------------------------------------------------------------------------------------

    def solve(self, spec: dict) -> dict:
        """The pose: `local` (every bone's rotation in its parent), `pelvis` (its place), `miss` (m out of reach
        per target) and, for a rig that has them, `places` of the `ik_` targets in the root."""
        rig = self.rig
        world, turns, miss = {}, {}, {}
        self._trunk(spec, world, turns)
        for s, sign in SIDES:
            self._leg(spec, world, s, miss)
            self._arm(spec, world, turns, s, sign, miss)
        local = {}
        fingers = spec.get("fingers", {})
        root = rig.parent["pelvis"]
        for name in rig.bones:
            p = rig.parent[name]
            if name == root:
                local[name] = rig.local_rot[name]
                continue
            if name in world:
                local[name] = world[p][:3, :3].T @ world[name][:3, :3]
                continue
            rot = rig.local_rot[name]
            if name in self._finger_hinge:
                finger, joint, side = name.rsplit("_", 2)
                curl = fingers.get(side, {}).get(finger, 0.0)
                lay = fingers.get(side, {}).get("thumb_out", 0.0)
                if finger == "thumb" and joint == "01" and lay:
                    # The rest thumb points under the palm; a relaxed one lies beside it.
                    rot = rig.rest_rot[p].T @ axis_angle(X, -lay) @ rig.rest_rot[name]
                if curl:
                    rot = rot @ axis_angle(self._finger_hinge[name], curl * FINGER_SHARE[int(joint) - 1])
            local[name] = rot
            self._place(world, name, world[p][:3, :3] @ rot)
        pose = {"local": local, "pelvis": np.asarray(spec["pelvis"]["place"], dtype=float), "miss": miss}
        self._ik_targets(pose, world)
        return pose

    def _ik_targets(self, pose: dict, world: dict) -> None:
        """The `ik_foot` and `ik_hand` bones (children of the root on the prototype rig) ride the limb's end."""
        rig = self.rig
        places = {}
        for s, _ in SIDES:
            for limb in ("foot", "hand"):
                name = f"ik_{limb}_{s}"
                if name not in rig.index:
                    continue
                parent = world[rig.parent[name]]
                end = world[f"{limb}_{s}"]
                places[name] = parent[:3, :3].T @ (end[:3, 3] - parent[:3, 3])
                pose["local"][name] = parent[:3, :3].T @ end[:3, :3]
        if places:
            pose["places"] = places


def stand_spec(rig: Rig) -> dict:
    """The standing rest as a spec: the feet where the rig has them, everything else at its defaults (arms down)."""
    return {
        "pelvis": {"place": rig.rest_pos["pelvis"].copy(), "turn": (0.0, 0.0, 0.0)},
        "leg": {s: {"ankle": rig.rest_pos["foot_" + s].copy()} for s, _ in SIDES},
    }
