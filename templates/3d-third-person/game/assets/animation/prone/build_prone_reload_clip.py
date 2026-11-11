"""Build the template's prone reload clip for the pistol and export it to glTF (kit #1185).

GDStudio's own animation, made from nothing on the Quaternius universal rig: the Universal Animation Library's only
reload is a standing one, which folds the arms under a lying chest. One clip, `Prone_Reload_Pistol`, played once over
the prone aim from `spine_01` up. It starts and ends on the first pose of `Prone_Aim_Neutral_Loop` to the bit:

- the body rolls a little onto its firing side, which lifts the left shoulder and frees the left hip;
- the right arm props on its elbow and brings the pistol back in front of the face, the muzzle up and the magazine
  well canted toward the left hand (how a reload is taught: the pistol close, the well canted inboard about 45
  degrees; the sources are in the folder's README);
- the left hand lets go, goes back along the body to the belt at the left hip for the new magazine, comes under the
  grip, pushes the magazine up it with the heel of the palm, and takes its place on the pistol again;
- both arms stretch out to the aim.

The left hand's times are the game's, never typed here: `tools/hold/dump_aim_seat.gd` writes the hold's `MagazineHand`
marker, the hand's way off the weapon and the four pairs of shares of `WeaponHold`'s Reload group, and `ReloadHold`
below is `SupportHandPlan` in Python. Wherever the game's hold has the left hand (on the pistol, on its way, under
the magazine), the clip has the hand's bone on that very place, so the hold's reach changes nothing and keeps the
clip's elbow; while the hold lets the clip's own arm have the hand, the clip takes it to the belt and back.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_prone_reload_clip.py -- --model <mannequin_female.glb>
        --male <mannequin_male.glb> --hold <aim_seat.json> --aim <prone_aim.glb> --out <prone_reload.glb>
        [--report <numbers.json>]

It shares the rig, the solver, the keying and the export of `build_prone_clips.py` and the hold of
`build_prone_aim_clips.py` (same folder), and fails before it exports when the first or the last pose is not the
prone aim's, a target is missed, the left hand is off the place the game's hold has for it, the propped elbow
slides, the lower body differs from the prone idle's, a hand or forearm of the female or the pistol goes under the
floor, the muzzle covers the left hand, a wrist is bent too far, or a part of the body goes more than 5 mm into
another on either mannequin on any frame (the two hands on each other are closed by the game's hold and measured
there).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_prone_aim_clips as aim  # noqa: E402

base = aim.base
FPS = base.FPS
FRAMES = 50  # 1.667 s, the length of the library's standing `Pistol_Reload`: the game stretches both to the weapon's
CLIP = "Prone_Reload_Pistol"
AIM_CLIP = "Prone_Aim_Neutral_Loop"

# `SupportHandPlan`'s constants (gameplay/weapon/hold/support_hand_plan.gd); the Godot test compares the two.
WAY_FROM = 0.6
UNHOOK = 0.45
LET_GO_WAY = 0.55
BACK_DOWN = (0.0, 0.3)
BACK_DOWN_SHARE = 0.4
BACK_ACROSS = (0.12, 0.62)

# The pistol through the clip, as shares of it: it leaves the aim, is in the reload's place, leaves that, aims.
PISTOL_IN = (0.0, 0.22)
PISTOL_OUT = (0.74, 0.96)
CANT = 45.0  # degrees the magazine well is canted toward the left hand
MUZZLE_UP = 24.0  # degrees the muzzle points up while the pistol is reloaded
MUZZLE_IN = 8.0  # degrees it points to the left of straight ahead
FOREARM_UP = 20.0  # degrees the propped right forearm rises from the floor
FOREARM_IN = 22.0  # degrees it points inward of straight ahead
ELBOW_OUT = 35.0  # degrees outward of straight ahead the propped elbow lies from its shoulder
ELBOW_UP = 0.047  # metres the propped elbow's joint is over the floor
SEAT_KICK = 0.006  # metres the pistol gives up its grip as the magazine seats
ROLL = 11.0  # degrees the chest rolls onto the firing side
YAW = 4.0  # degrees it turns toward the firing side with it
CLAV_R = (4.0, 0.0)  # the right collarbone while its arm props (the aim's lift is 22)
CLAV_L = (14.0, -6.0)  # the left one while its arm works
HEAD_GLANCE = (7.0, -5.0)  # degrees the head tips down and turns toward the magazine well as the magazine goes in
# The left hand at the belt: its wrist ahead of the left hip joint, out from the skin of the hip beside the hand, and
# up from the floor.
BELT = (0.2, 0.08, 0.125)
BELT_SHARES = (0.215, 0.255)  # the shares of the clip the hand is at the belt
# The hand swings round the outside of its own shoulder on its way there and back: the point its path bends toward
# (ahead, left, up), and how far the hand keeps its own line with the forearm in mid-swing.
BELT_SWING = (0.55, 0.52, 0.3)
SWING_LOOSE = 0.6
BELT_LOOSE = 0.45  # and at the belt, where the forearm comes down to the hip from a raised elbow
POLE_BELT = (-0.5, 0.9, 0.7)  # where the left elbow points at the belt: back, out, up
POLE_MAGAZINE = (-0.3, 1.0, -0.35)  # and under the magazine
FIST_BELT = 0.6  # how far the left hand is closed on the new magazine (1 is the fist)
FIST_OPEN = 0.25  # and as it reaches for it, and wherever the hold has its fingers
WRIST_LIMIT = 75.0  # degrees a wrist may be bent from the forearm's line
PROP_LIMIT = 0.004  # metres the propped elbow may move while the pistol is in the reload's place
PLACE_LIMIT = 0.0005  # metres the left hand's bone may be off the hold's place for it
MUZZLE_CLEAR = 0.05  # metres the left hand stays from the barrel's line ahead of the muzzle
FLOOR_LIMIT = aim.FLOOR_LIMIT
OVERLAP_LIMIT = base.OVERLAP_LIMIT


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def smoothstep(a, b, x):
    return base.smooth((x - a) / (b - a))


def inverse_lerp(a, b, x):
    return (x - a) / (b - a)


class ReloadHold(aim.Hold):
    """The pistol's hold with the left hand's way through a reload, as the game has it."""

    def __init__(self, path, model="female"):
        super().__init__(path, model)
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        self.magazine = aim.xf(data["magazine"])
        reload = data["reload"]
        self.way = np.array(reload["way"])
        self.approach = np.array(reload["approach"])
        self.clearance = np.array(reload["clearance"])
        self.leave, self.reach, self.insert, self.back = (
            tuple(reload[k]) for k in ("leave", "reach", "insert", "back")
        )

    def plan(self, share):
        """`SupportHandPlan.update(1, 1, share)`: where the left hand is at a share of a reload played while the
        weapon is aimed."""
        on, magazine_arm, at_magazine, down, across = 0.0, 0.0, 0.0, 0.0, 0.0
        if share < self.reach[0]:
            gone = clamp01(inverse_lerp(self.leave[0], self.leave[1], share))
            on = (1.0 + (WAY_FROM - 1.0) * smoothstep(0.0, LET_GO_WAY, gone)) * (
                1.0 - smoothstep(LET_GO_WAY, 1.0, gone)
            )
        else:
            returned = clamp01(inverse_lerp(self.back[0], self.back[1], share))
            inserted = smoothstep(self.insert[0], self.insert[1], share)
            across = smoothstep(BACK_ACROSS[0], BACK_ACROSS[1], returned)
            magazine_arm = smoothstep(self.reach[0], self.reach[1], share)
            at_magazine = 1.0 - across
            down = 1.0 - inserted + BACK_DOWN_SHARE * smoothstep(BACK_DOWN[0], BACK_DOWN[1], returned)
            if across >= 1.0:
                on = WAY_FROM + (1.0 - WAY_FROM) * smoothstep(BACK_ACROSS[1], 1.0, returned)
        way = 1.0 - clamp01(inverse_lerp(WAY_FROM, 1.0, on))
        return {
            "arm": max(clamp01(on / WAY_FROM), magazine_arm),
            "at_magazine": at_magazine,
            "off": smoothstep(UNHOOK, 1.0, way),
            "down": down,
            "across": across,
        }

    def left_place(self, plan):
        """The left hand's bone in the pistol's space for a plan (`WeaponHold.refresh`)."""
        place = self.support.copy()
        place[:3, 3] += self.way * plan["off"]
        if plan["at_magazine"] > 0.0:
            under = self.magazine.copy()
            under[:3, 3] += self.approach * plan["down"]
            mixed = np.eye(4)
            mixed[:3, :3] = base.slerp(place[:3, :3], under[:3, :3], plan["at_magazine"])
            mixed[:3, 3] = place[:3, 3] + (under[:3, 3] - place[:3, 3]) * plan["at_magazine"]
            place = mixed
            place[:3, 3] += self.clearance * math.sin(math.pi * plan["across"])
        return place

    def basis(self, look, cant=0.0, inward=0.0):
        """The pistol's turn in Godot's model space: aimed `look` degrees up and `inward` degrees to the left, and
        canted `cant` degrees (its top to the right, the magazine well to the left)."""
        level = self.pistol(base.vec(0.0, 0.0, 0.0), look)[:3, :3]
        c, y = math.radians(cant), math.radians(inward)
        up, left = level[:, 1].copy(), level[:, 2].copy()
        level[:, 1] = math.cos(c) * up - math.sin(c) * left
        level[:, 2] = math.cos(c) * left + math.sin(c) * up
        turn = np.array([[math.cos(y), 0.0, math.sin(y)], [0.0, 1.0, 0.0], [-math.sin(y), 0.0, math.cos(y)]])
        return turn @ level

    def pistol_for_wrist(self, wrist, basis):
        """The pistol's transform (Godot's model space) with that turn and the right hand's bone at `wrist`
        (Blender's axes)."""
        m = np.eye(4)
        m[:3, :3] = basis
        m[:3, 3] = aim.TO_BLENDER.T @ np.asarray(wrist, dtype=float) - basis @ np.linalg.inv(self.seat)[:3, 3]
        return m

    def hands_of(self, pistol, place):
        """`Hold.hands` for any pistol transform and any place of the left hand in the pistol's space."""
        to_b = aim.TO_BLENDER
        right = pistol @ np.linalg.inv(self.seat)
        left = pistol @ place
        out = {}
        for s, posed, undo in (("r", right, self.turn.T), ("l", left, np.eye(3))):
            turn = posed[:3, :3] @ undo @ self.rest[s].T
            out[s] = (to_b @ posed[:3, 3], to_b @ turn @ to_b.T)
        return out

    def point(self, pistol, marker):
        return aim.TO_BLENDER @ (pistol @ marker)[:3, 3]

    def pistol_of(self, rig, world):
        """The pistol's transform (Godot's model space) a solved pose carries, the game's wrist turn added."""
        to_b = aim.TO_BLENDER
        hand = world["hand_r"]
        posed = np.eye(4)
        posed[:3, :3] = to_b.T @ (hand[:3, :3] @ rig.rest_rot["hand_r"].T) @ to_b @ self.rest["r"] @ self.turn
        posed[:3, 3] = to_b.T @ hand[:3, 3]
        return posed @ self.seat


def mix(a, b, w):
    return a + (b - a) * w


def mix_xf(a, b, w, lift=0.0):
    out = np.eye(4)
    out[:3, :3] = base.slerp(a[:3, :3], b[:3, :3], w)
    out[:3, 3] = mix(a[:3, 3], b[:3, 3], w)
    out[1, 3] += lift * math.sin(math.pi * w)
    return out


class ReloadSolver(aim.AimSolver):
    """The aim's solver with a hand that can be part of the way between the forearm's own line (`hand_free` 1) and
    the turn it is given."""

    def _arm(self, world, spec, s, sign):
        base.Solver._arm(self, world, spec, s, sign)
        arm = spec["arm"][s]
        turn = arm.get("hand_turn")
        if turn is not None:
            given = turn @ self.rig.rest_rot["hand_" + s]
            world["hand_" + s][:3, :3] = base.slerp(given, world["hand_" + s][:3, :3].copy(), arm.get("hand_free", 0.0))


class Reload:
    """Everything the frames share: the aim the clip joins, the reload's place, the belt."""

    def __init__(self, rig, solver, hold, anchor, lower):
        self.rig, self.solver, self.hold, self.anchor, self.lower = rig, solver, hold, anchor, lower
        self.give_aim = aim.chest_give(rig, solver, hold, anchor)
        # The aim's first pose, as `build_prone_aim_clips.build_clip` finds it.
        lift = 0.0
        for _ in range(5):
            spec = aim.aim_spec(rig, solver, hold, anchor, 0.0, 0.0, self.give_aim, None, lift)
            low = self.lowest_hand(solver.solve(spec))
            if low >= aim.HAND_CLEAR - 1e-4:
                break
            lift += aim.HAND_CLEAR - low
        self.grip = spec["grip"]
        self.pistol_aim = hold.pistol(self.grip, 0.0)
        self.aim_pose = self.finish(solver.solve(aim.aim_spec(rig, solver, hold, anchor, 0.0, 0.0, self.give_aim, self.grip)))
        self.give_reload = self.give_aim
        # The roll's sign is the one that lifts the left shoulder.
        self.roll_sign = 1.0
        rolled = self.shoulders(self.trunk(1.0, 0.0))
        if rolled["l"][2] < rolled["r"][2]:
            self.roll_sign = -1.0
        self.belt = self.belt_place()
        # The chest rests on the floor in the reload's place too, and the prop and the pistol follow from it.
        for _ in range(3):
            self.place_reload()
            self.give_reload = self.rest_chest()
        self.place_reload()

    def lowest_hand(self, pose, sides="lr"):
        skinned = self.rig.skin(self.rig.world(pose["local"], pose["pelvis"]))
        parts = [p + "_" for p in ("hand", "index", "middle", "ring", "pinky", "thumb")]
        mask = np.zeros(len(self.rig.owner), dtype=bool)
        for part in parts:
            for s in sides:
                mask |= np.char.startswith(self.rig.owner, part) & np.char.endswith(self.rig.owner, "_" + s)
        return float(skinned[mask, 2].min())

    def finish(self, pose):
        """The lower body is the prone idle's first pose, as in the aim clips."""
        for n in pose["local"]:
            if n.rstrip("_lr").rstrip("_") in aim.LOWER_BODY or n.startswith("ball_leaf"):
                pose["local"][n] = self.lower["local"][n]
        pose["pelvis"] = self.lower["pelvis"].copy()
        return pose

    def trunk(self, s, glance, give=None):
        """The trunk `s` of the way from the aim to the reload's place."""
        if give is None:
            give = mix(self.give_aim, self.give_reload, s)
        spec = aim.trunk_spec(self.anchor, 0.0, 0.0, give)
        roll = self.roll_sign * ROLL * s
        for name, share in (("spine_01", 0.3), ("spine_02", 0.65), ("spine_03", 1.0)):
            pitch, _, _ = spec["trunk"][name]
            spec["trunk"][name] = (pitch, -YAW * s * share, roll * share)
        pitch, yaw, tip = spec["trunk"]["neck_01"]
        spec["trunk"]["neck_01"] = (pitch + 0.4 * HEAD_GLANCE[0] * glance, -YAW * s, 0.3 * roll)
        pitch, yaw, tip = spec["trunk"]["Head"]
        spec["trunk"]["Head"] = (pitch + HEAD_GLANCE[0] * glance, yaw + HEAD_GLANCE[1] * glance, tip)
        spec["clav"]["r"] = tuple(mix(np.array(spec["clav"]["r"]), np.array(CLAV_R), s))
        spec["clav"]["l"] = tuple(mix(np.array(spec["clav"]["l"]), np.array(CLAV_L), s))
        return spec

    def shoulders(self, spec):
        trunk = self.solver._trunk(spec, np.zeros(2))
        return {s: trunk["upperarm_" + s][:3, 3].copy() for s, _ in base.SIDES}

    def place_reload(self):
        """The propped elbow on the floor, one upper arm from the shoulder, and the pistol at the end of the raised
        forearm."""
        rig = self.rig
        shoulder = self.shoulders(self.trunk(1.0, 0.0))["r"]
        drop = shoulder[2] - ELBOW_UP
        length = rig.len["upperarm_r"]
        if drop >= length:
            raise SystemExit(f"the right shoulder is {drop:.3f} m over the elbow's rest, more than the upper arm")
        out = math.sqrt(length**2 - drop**2)
        a = math.radians(ELBOW_OUT)
        self.prop = shoulder + base.vec(out * math.cos(a), -out * math.sin(a), -drop)
        up, inward = math.radians(FOREARM_UP), math.radians(FOREARM_IN)
        along = base.vec(math.cos(up) * math.cos(inward), math.cos(up) * math.sin(inward), math.sin(up))
        wrist = self.prop + rig.len["lowerarm_r"] * along
        self.pistol_reload = self.hold.pistol_for_wrist(wrist, self.hold.basis(MUZZLE_UP, CANT, MUZZLE_IN))

    def rest_chest(self):
        """Degrees the spine gives so that the rolled chest's skin rests on the floor."""

        def low(give):
            pose = self.solver.solve(self.spec(0.5, give))
            skinned = self.rig.skin(self.rig.world(pose["local"], pose["pelvis"]))
            return self.rig.lowest(skinned, ("spine_02", "spine_03", "clavicle")) + aim.CHEST_SINK

        under, over = 30.0, -20.0
        for _ in range(24):
            middle = (under + over) / 2
            if low(middle) < 0.0:
                under = middle
            else:
                over = middle
        return (under + over) / 2

    def belt_place(self):
        """The left hand at the belt: beside the waist at the left hip, the palm to the body, the fingers back."""
        rig = self.rig
        pose = self.aim_pose
        world = rig.world(pose["local"], pose["pelvis"])
        skinned = rig.skin(world)
        hip = world["thigh_l"][:3, 3]
        ahead = -hip[1] + BELT[0]
        band = np.isin(rig.owner, ("pelvis", "spine_01", "thigh_l")) & (-skinned[:, 1] < ahead) & (-skinned[:, 1] > ahead - 0.2)
        waist = float(skinned[band, 0].max())
        place = base.vec(ahead, waist + BELT[1], BELT[2])
        rest_g = base.unit(rig.rest_pos["middle_01_l"] - rig.rest_pos["hand_l"])
        fingers = base.unit(base.vec(-1.0, 0.0, -0.05))
        palm = base.unit(base.vec(0.0, -1.0, -0.15))
        palm = base.unit(palm - fingers * np.dot(fingers, palm))
        turn = base.aim_turn(rest_g, np.array([0.0, 0.0, -1.0]), fingers, palm)
        self.waist = waist
        return place, turn

    def pistol(self, t):
        """The pistol at a share of the clip."""
        s = self.share(t)
        pistol = mix_xf(self.pistol_aim, self.pistol_reload, s)
        # The magazine seats: the pistol gives a little up its own grip and comes back.
        seat = self.hold.insert[1]
        after = max(t - seat, 0.0) / 0.012
        kick = after * math.exp(1.0 - after)
        pistol[:3, 3] += pistol[:3, 1] * SEAT_KICK * kick
        return pistol

    def share(self, t):
        return smoothstep(*PISTOL_IN, t) * (1.0 - smoothstep(*PISTOL_OUT, t))

    def left(self, t, pistol):
        """The left hand's bone at a share of the clip (place, turn), the way its elbow points and how far the hand
        is closed: the hold's own place wherever the hold has the hand, the belt between."""
        hold = self.hold
        plan = hold.plan(t)
        # The hand is open before the hold lets the clip have its fingers, and a fist again at the clip's ends.
        fist = 1.0 - (1.0 - FIST_OPEN) * smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.95, 1.0, t))
        if t >= hold.reach[1]:
            fist = mix(FIST_BELT, fist, smoothstep(hold.reach[1], hold.reach[1] + 0.1, t))
        near = hold.hands_of(pistol, hold.left_place(plan))["l"]
        pole_aim = base.vec(aim.ELBOW_POLE[0], aim.ELBOW_POLE[1], aim.ELBOW_POLE[2])
        pole_work = mix(pole_aim, base.unit(base.vec(*POLE_MAGAZINE)), self.share(t))
        gone_at = hold.leave[0] + (hold.leave[1] - hold.leave[0]) * LET_GO_WAY
        if t <= gone_at or t >= hold.reach[1]:
            return near, pole_work, fist, 0.0
        belt_place, belt_turn = self.belt
        if t < BELT_SHARES[1]:
            w = smoothstep(gone_at, BELT_SHARES[0], t)
            far = near
        else:
            # Back from the belt to the line under the magazine, where the hold takes the hand again.
            w = 1.0 - smoothstep(BELT_SHARES[1], hold.reach[1], t)
            far = hold.hands_of(pistol, hold.left_place(hold.plan(max(t, hold.reach[0]))))["l"]
        place = (1.0 - w) ** 2 * far[0] + 2.0 * w * (1.0 - w) * base.vec(*BELT_SWING) + w**2 * belt_place
        turn = base.slerp(far[1], belt_turn, w)
        pole = mix(pole_work, base.unit(base.vec(*POLE_BELT)), w)
        fist = mix(FIST_OPEN, FIST_BELT, smoothstep(BELT_SHARES[0] - 0.04, BELT_SHARES[0] + 0.01, t))
        free = min(BELT_LOOSE * base.smooth(w) + SWING_LOOSE * math.sin(math.pi * w) ** 2, 0.95)
        return (place, turn), pole, fist, free

    def spec(self, t, give=None):
        """The targets of the frame at a share of the clip."""
        hold = self.hold
        s = self.share(t)
        glance = smoothstep(hold.reach[0], hold.insert[0], t) * (1.0 - smoothstep(hold.insert[1], hold.back[0], t))
        spec = self.trunk(s, glance, give)
        pistol = self.pistol(t)
        right = hold.hands_of(pistol, hold.support)["r"]
        left, pole_l, fist, free = self.left(t, pistol)
        pole_aim = base.vec(aim.ELBOW_POLE[0], -aim.ELBOW_POLE[1], aim.ELBOW_POLE[2])
        shoulder = self.shoulders(spec)["r"]
        pole_r = mix(base.unit(pole_aim), base.unit(self.prop - shoulder), s)
        for side, (place, turn), pole in (("r", right, pole_r), ("l", left, pole_l)):
            spec["arm"][side] = {
                "wrist": place,
                "pole": pole,
                "palm": turn @ np.array([0.0, 0.0, -1.0]),
                "hand_turn": turn,
            }
        spec["arm"]["l"]["hand_free"] = free
        for side, sign in base.SIDES:
            spec["leg"][side] = base.lying_leg(self.rig, sign, self.anchor)
        spec["fist"] = {"l": fist, "r": 1.0}
        return spec

    def frame(self, t):
        return self.finish(self.solver.solve(self.spec(t)))


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--male", required=True)
    parser.add_argument("--hold", required=True)
    parser.add_argument("--aim", required=True, help="prone_aim.glb, whose first pose the clip joins")
    parser.add_argument("--out", required=True)
    parser.add_argument("--report")
    parser.add_argument("--preview", action="store_true", help="export even when a check fails, to look at it")
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    joined = base.library_pose(args.aim, AIM_CLIP, 0)
    arm, objects = base.import_glb(args.model)
    mesh = next(o for o in objects if o.type == "MESH" and o.parent == arm)
    for obj in objects:
        if obj.type == "MESH" and obj.parent is None:
            bpy.data.objects.remove(obj)
    rig = base.Rig(arm, mesh)
    solver = ReloadSolver(rig)
    hold = ReloadHold(args.hold)
    anchor = base.measure_anchor(rig, solver)
    solver.warm = np.zeros(2)
    lower = base.build_idle(rig, solver, anchor)[0]
    anchor = dict(anchor, pelvis_up=lower["pelvis_up"])

    reload = Reload(rig, solver, hold, anchor, lower)
    frames = [reload.frame(f / FRAMES) for f in range(FRAMES + 1)]
    failures = []
    numbers = base.clip_numbers(rig, CLIP, frames)
    report = {"fps": FPS, "clip": CLIP, "numbers": numbers, "frames": []}
    report["chest_give_degrees"] = [round(reload.give_aim, 3), round(reload.give_reload, 3)]
    report["prop"] = [round(float(v), 4) for v in reload.prop]
    report["belt"] = [round(float(v), 4) for v in reload.belt[0]]
    report["waist_left"] = round(reload.waist, 4)

    # The poses it joins: the aim as this build solves it, and the shipped file's first frame.
    for label, pose in (("first", frames[0]), ("last", frames[-1])):
        gap, apart = base.pose_gap(pose, reload.aim_pose)
        file_gap, file_apart = base.pose_gap(pose, joined)
        report[label + "_pose_off_degrees"] = [round(gap, 5), round(file_gap, 4)]
        if gap > 0.01 or apart > 1e-5:
            failures.append(f"the {label} pose is {gap:.3f} degrees off the prone aim's")
        if file_gap > 0.1 or file_apart > 1e-4:
            failures.append(f"the {label} pose is {file_gap:.3f} degrees off the first frame of {AIM_CLIP} in --aim")
    gap = max(
        math.degrees(base.to_quat(pose["local"][n]).rotation_difference(base.to_quat(lower["local"][n])).angle)
        for pose in frames
        for n in lower["local"]
        if n.rstrip("_lr").rstrip("_") in aim.LOWER_BODY
    )
    report["lower_body_off_degrees"] = round(gap, 5)
    if gap > 0.01:
        failures.append(f"the lower body is {gap:.3f} degrees off the prone idle's")
    if numbers["solver_miss"] > 0.001:
        failures.append(f"a target is missed by {numbers['solver_miss']:.4f} m")

    worst = {"place": 0.0, "prop": 0.0, "bend_l": 0.0, "bend_r": 0.0, "stretch_l": 0.0, "stretch_r": 0.0}
    held = [f for f in range(FRAMES + 1) if PISTOL_IN[1] <= f / FRAMES <= PISTOL_OUT[0]]
    for f, pose in enumerate(frames):
        t = f / FRAMES
        world = rig.world(pose["local"], pose["pelvis"])
        pistol = hold.pistol_of(rig, world)
        plan = hold.plan(t)
        want = hold.point(pistol, hold.left_place(plan))
        off = float(np.linalg.norm(want - world["hand_l"][:3, 3]))
        muzzle, foot = hold.point(pistol, hold.muzzle), hold.point(pistol, hold.foot)
        barrel = aim.TO_BLENDER @ -pistol[:3, 0]
        # How near the left hand is to the barrel's line ahead of the muzzle.
        cover = None
        for bone in ("hand_l", "middle_01_l", "lowerarm_l"):
            to = world[bone][:3, 3] - muzzle
            ahead = float(to @ barrel)
            if ahead > 0.0:
                beside = float(np.linalg.norm(to - barrel * ahead))
                cover = beside if cover is None else min(cover, beside)
        entry = {
            "frame": f,
            "share": round(t, 3),
            "hold_arm": round(plan["arm"], 3),
            "left_off_mm": round(off * 1000.0, 3),
            "muzzle_up": round(float(muzzle[2]), 3),
            "foot_up": round(float(foot[2]), 3),
            "elbow_r": [round(float(v), 3) for v in world["lowerarm_r"][:3, 3]],
            "wrist_l": [round(float(v), 3) for v in world["hand_l"][:3, 3]],
            "bend_r": round(aim.bend(rig, world, "r"), 1),
            "bend_l": round(aim.bend(rig, world, "l"), 1),
        }
        for s, _ in base.SIDES:
            reach = np.linalg.norm(world["hand_" + s][:3, 3] - world["upperarm_" + s][:3, 3])
            entry["stretch_" + s] = round(float(reach / (rig.len["upperarm_" + s] + rig.len["lowerarm_" + s])), 3)
            worst["stretch_" + s] = max(worst["stretch_" + s], entry["stretch_" + s])
            worst["bend_" + s] = max(worst["bend_" + s], entry["bend_" + s])
        report["frames"].append(entry)
        if plan["arm"] >= 1.0:
            worst["place"] = max(worst["place"], off)
        if f in held:
            worst["prop"] = max(worst["prop"], float(np.linalg.norm(world["lowerarm_r"][:3, 3] - reload.prop)))
        if cover is not None and cover < MUZZLE_CLEAR:
            failures.append(f"frame {f}: the left hand is {cover * 1000:.0f} mm from the barrel's line, ahead of the muzzle")
        for part, up in (("muzzle", muzzle[2]), ("foot", foot[2])):
            if up < 0.003:
                failures.append(f"frame {f}: the pistol's {part} is {up:.3f} m over the floor")
    report["worst"] = {k: round(v * (1000.0 if k in ("place", "prop") else 1.0), 3) for k, v in worst.items()}
    if worst["place"] > PLACE_LIMIT:
        failures.append(f"the left hand is {worst['place'] * 1000:.2f} mm off the hold's place for it")
    if worst["prop"] > PROP_LIMIT:
        failures.append(f"the propped elbow moves {worst['prop'] * 1000:.1f} mm while the pistol is reloaded")
    for s in "lr":
        if worst["bend_" + s] > WRIST_LIMIT:
            failures.append(f"the {s} wrist is bent {worst['bend_' + s]:.0f} degrees")
        if worst["stretch_" + s] > 0.992:
            failures.append(f"the {s} arm cannot reach ({worst['stretch_' + s]:.3f} of its length)")
    if numbers["lowest"] < -0.02:
        failures.append(f"the mesh goes {-numbers['lowest']:.3f} m under the floor")

    action = base.key_clip(arm, rig, CLIP, frames)
    for frame_no in (FRAMES // 4, FRAMES // 2):
        off = base.check_against_blender(arm, mesh, rig, action, frames, frame_no)
        report["skinning_against_blender"] = round(off, 6)
        if off > 0.001:
            failures.append(f"the script's skinning is {off:.4f} m off Blender's at frame {frame_no}")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import limb_overlap

    male = limb_overlap.load_body(args.male, "male")
    bodies = [limb_overlap.Body(arm, mesh, "female"), male]
    floor = base.floor_numbers(arm, {CLIP: action}, {CLIP: frames}, bodies, [])[CLIP]
    report["floor_mm"] = floor
    for body in floor:
        for part, entry in floor[body].items():
            entry.pop("frames", None)
            if body == "female" and entry["lowest"] < -FLOOR_LIMIT:
                failures.append(f"the female's {part} is {-entry['lowest']} mm under the floor at frame {entry['frame']}")
    measured = limb_overlap.measure(arm, action, range(FRAMES + 1), bodies)
    report["overlap_mm"] = {}
    for body, entry in measured.items():
        # The two hands hold the pistol together: the game's hold closes them and its test measures them.
        pairs = {k: v for k, v in entry["pairs"].items() if not ("hand_l" in k and "hand_r" in k) and v[0] > 0.0}
        deepest = max((v[0] for v in pairs.values()), default=0.0)
        report["overlap_mm"][body] = {
            "deepest": deepest,
            "pairs": pairs,
            "hands": {k: v for k, v in entry["pairs"].items() if "hand_l" in k and "hand_r" in k},
        }
        if deepest > OVERLAP_LIMIT:
            failures.append(f"on the {body}: {pairs} (the limit is {OVERLAP_LIMIT} mm)")
    arm.animation_data.action = None
    for obj in male.objects:
        bpy.data.objects.remove(obj)
    print("REPORT", json.dumps(report, indent=1))
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    if failures:
        print("BUILD FAILED\n  " + "\n  ".join(failures))
        if not args.preview:
            raise SystemExit(1)
    bpy.data.objects.remove(mesh)
    base.export(arm, args.out)
    print("EXPORTED", args.out)


if __name__ == "__main__":
    main()
