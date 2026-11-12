"""Build the template's prone reload clip for the pistol, for one body, and export it to glTF (kit #1185).

GDStudio's own animation, made from nothing: the Universal Animation Library's only reload is a standing one, which
folds the arms under a lying chest. One clip, `Prone_Reload_Pistol`, played once over the prone aim from `spine_01`
up. It starts and ends on the first pose of that body's `Prone_Aim_Neutral_Loop` to the bit:

- the body rolls a little onto its firing side, which lifts the left shoulder and frees the left hip;
- the right arm props on its elbow and brings the pistol back in front of the face, the muzzle up and the magazine
  well canted toward the left hand (how a reload is taught: the pistol close, the well canted inboard about 45
  degrees; the sources are in the folder's README);
- the left hand lets go, goes back along the body to the belt at the left hip for the new magazine, comes under the
  grip, pushes the magazine up it with the heel of the palm, and takes its place on the pistol again;
- both arms stretch out to the aim.

One file a body, as the prone aim clips are (`build_prone_aim_clips.py`): `prone_reload.glb` on `form_female` and
`prone_reload_male.glb` on `form_male`, each solved on that body's own skeleton and skin, with its own hold and
from its own aim clip. The first clip, solved on the Quaternius female, played on the prototype bodies with the left
hand 8 and 25 mm off its place, fingers 8 and 18 mm in the pistol and the magazine 25 mm under the floor.

The left hand's times and places are the game's, never typed here: `tools/hold/dump_aim_seat.gd` writes each body's
`MagazineHand` marker, the way its opened hand leaves the weapon, its support, opened and magazine finger poses, and
once the approach under the magazine, the bow of the way back and the four pairs of shares of `WeaponHold`'s Reload
group; `ReloadHold` below is `SupportHandPlan` in Python. Wherever the game's hold has the left hand (on the pistol,
on its way, under the magazine), the clip has the hand's bone on that very place and its fingers in the hold's own
pose, so the hold changes nothing and keeps the clip's elbow; while the hold lets the clip's own arm have the hand,
the clip takes it to the belt and back and closes it on the new magazine. The right hand keeps the hold's grip, the
index finger off the trigger and along the frame from the first frames to the last.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute, once a body:

    blender -b --factory-startup -P build_prone_reload_clip.py -- --body female --model <form_female.glb>
        --hold <aim_seat.json> --idle <prone_form_female.glb> --aim <prone_aim.glb> --out <prone_reload.glb>
    blender -b --factory-startup -P build_prone_reload_clip.py -- --body male --model <form_male.glb>
        --hold <aim_seat.json> --idle <prone_form_male.glb> --aim <prone_aim_male.glb> --out <prone_reload_male.glb>

Blender exits 0 when a script raises, so read the output for `EXPORTED` and check the file's time.

It shares the rig, the solver, the keying and the export of `build_prone_clips.py` and the hold, the trunk and the
measures of `build_prone_aim_clips.py` (same folder), and measures the skin as the game shows it (the wrist turn of
the grip on, the fingers in the hold's poses, the twist bones turned). It fails before it exports when the first or
the last pose is not the prone aim's, a target is missed, the left hand is off the place the game's hold has for it,
the propped elbow slides, the lower body differs from the prone idle's, a hand's or an arm's skin or the pistol goes
under the floor, the muzzle covers the left hand, a wrist is bent too far, an arm is stretched straight, or a part of
the body goes more than 5 mm into another on any frame (the two hands on each other and on the pistol are closed by
the game's hold and measured there: `tests/gameplay/test_prone_reload_hold.gd`).
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
SEAT_KICK = 0.006  # metres the pistol gives up its grip as the magazine seats
BELT_SHARES = (0.215, 0.255)  # the shares of the clip the hand is at the belt
TRIGGER_OFF = 0.06  # the share of the clip over which the index finger leaves the trigger, and comes back to it
WRIST_LIMIT = 75.0  # degrees a wrist may be bent from the forearm's line
PROP_LIMIT = 0.004  # metres the propped elbow may move while the pistol is in the reload's place
PLACE_LIMIT = 0.0005  # metres the left hand's bone may be off the hold's place for it
MUZZLE_CLEAR = 0.05  # metres the left hand stays from the barrel's line ahead of the muzzle
STRETCH_LIMIT = 0.992  # how far of its length an arm may be stretched
ARM_REST = aim.ARM_REST  # metres the propped arm's skin rests over the floor
HAND_FLOOR = -1.0  # millimetres a hand's skin may be under the floor (pressed on it)
ARM_FLOOR = aim.ARM_FLOOR  # millimetres an arm's skin may be
CHEST_FLOOR = -6.0  # millimetres the chest's may be (it rests `aim.CHEST_SINK` in the floor at both ends)
OVERLAP_LIMIT = base.OVERLAP_LIMIT
ARM_PARTS = ("upperarm", "lowerarm")

# What each body's reload is made of. The clip is one-sided by what it is (the right arm props, the left one works),
# and each body has its own numbers where its arms and hands ask for them.
SHARED = {
    "cant": 45.0,  # degrees the magazine well is canted toward the left hand
    "muzzle_up": 24.0,  # degrees the muzzle points up while the pistol is reloaded
    "muzzle_in": 8.0,  # degrees it points to the left of straight ahead
    "forearm_up": 20.0,  # degrees the propped right forearm rises from the floor
    "forearm_in": 22.0,  # degrees it points inward of straight ahead
    "elbow_out": 35.0,  # degrees outward of straight ahead the propped elbow lies from its shoulder
    "roll": 11.0,  # degrees the chest rolls onto the firing side
    "yaw": 4.0,  # degrees it turns toward the firing side with it
    "clav_r": (4.0, 0.0),  # the right collarbone while its arm props
    "clav_l": (14.0, -6.0),  # the left one while its arm works
    "glance": (7.0, -5.0),  # degrees the head tips down and turns toward the magazine well as the magazine goes in
    # The left hand at the belt: its wrist ahead of the left hip joint, out from the skin of the hip beside the
    # hand, and up from the floor.
    "belt": (0.2, 0.08, 0.125),
    # The hand swings round the outside of its own shoulder on its way there and back: the point its path bends
    # toward (ahead, left, up), and how far the hand keeps its own line with the forearm in mid-swing and at the
    # belt, where the forearm comes down to the hip from a raised elbow.
    "belt_swing": (0.55, 0.52, 0.3),
    "swing_loose": 0.6,
    "belt_loose": 0.45,
    "pole_belt": (-0.5, 0.9, 0.7),  # where the left elbow points at the belt: back, out, up
    "pole_magazine": (-0.3, 1.0, -0.35),  # and under the magazine
    # and on the way back onto the pistol, where the hold turns the hand: lower and less far out, which bends the
    # wrist least of the ways that pass through nothing (lifted or tucked back beside the chest, the upper arm
    # passed 26 to 49 mm through the head)
    "pole_return": (-0.4, 0.6, -0.5),
    "grasp": 0.8,  # how far the left hand closes on the new magazine, from its opened pose to its closed one
    # metres the pistol rises as the left hand lets go, so the hand's way off it (which leads down the grip) stays
    # over the floor, and the shares of the clip over which it rises and comes back down into the reload's place
    "let_go_lift": 0.02,
    "let_go_shares": (0.0, 0.055, 0.09, 0.2),
}
BODIES = {
    "female": dict(SHARED),
    "male": dict(SHARED),
}


def clamp01(x):
    return min(max(x, 0.0), 1.0)


def smoothstep(a, b, x):
    return base.smooth((x - a) / (b - a))


def inverse_lerp(a, b, x):
    return (x - a) / (b - a)


class ReloadHold(aim.Hold):
    """A body's hold of the pistol with the left hand's way through a reload, as the game has it."""

    def __init__(self, path, model):
        super().__init__(path, model)
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        body = data["models"][model]
        self.magazine = aim.xf(body["magazine"])
        self.way = np.array(body["way"])
        # The finger poses by name, each bone's turn in its parent: the right hand's grip and trigger finger, the
        # left hand's on the pistol, opened and under the magazine.
        self.poses = {
            name: {bone: aim.quat_matrix(q) for bone, q in pose.items()} for name, pose in body["poses"].items()
        }
        reload = data["reload"]
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
            "opened": across if at_magazine > 0.0 else smoothstep(0.0, UNHOOK, way),
            "magazine_fingers": 1.0 if share >= self.reach[0] and across < 1.0 else 0.0,
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

    def left_fingers(self, plan):
        """The left hand's fingers as the game's hold has them for a plan (`HandPoseModifier`): on the pistol,
        under the magazine by `magazine_fingers`, opened by `opened`."""
        support, magazine, opened = self.poses["support"], self.poses["magazine"], self.poses["open"]
        out = {}
        for bone, turn in support.items():
            turn = base.slerp(turn, magazine.get(bone, turn), plan["magazine_fingers"])
            out[bone] = base.slerp(turn, opened.get(bone, turn), plan["opened"])
        return out

    def right_fingers(self, on_trigger):
        """The right hand's grip, the index finger on the trigger by `on_trigger` and along the frame without."""
        out = dict(self.poses["grip"])
        for bone, turn in self.poses["trigger"].items():
            out[bone] = base.slerp(out.get(bone, turn), turn, on_trigger)
        return out

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
    the turn it is given, and fingers a frame can name (`fingers`: each bone's turn in its parent)."""

    def _arm(self, world, spec, s, sign):
        base.Solver._arm(self, world, spec, s, sign)
        arm = spec["arm"][s]
        turn = arm.get("hand_turn")
        if turn is not None:
            given = turn @ self.rig.rest_rot["hand_" + s]
            world["hand_" + s][:3, :3] = base.slerp(given, world["hand_" + s][:3, :3].copy(), arm.get("hand_free", 0.0))

    def solve(self, spec):
        pose = base.Solver.solve(self, spec)
        for bone, turn in spec.get("fingers", self.hold.fingers).items():
            pose["local"][bone] = turn
        return pose


class Reload:
    """Everything the frames share: the aim the clip joins, the reload's place, the belt."""

    def __init__(self, rig, solver, body, numbers, hold, lower):
        self.rig, self.solver, self.body, self.n, self.hold, self.lower = rig, solver, body, numbers, hold, lower
        self.give_aim = aim.chest_give(rig, solver, body, hold, lower)
        # The aim's first pose, as `build_prone_aim_clips.build_clip` makes it, and the pistol it carries.
        self.aim_pose = aim.build_clip(rig, solver, body, hold, lower, 0.0, self.give_aim)[0]
        self.raised = self.aim_pose["raised"]
        self.pistol_aim = hold.carried(rig, rig.world(self.aim_pose["local"], self.aim_pose["pelvis"]))
        self.give_reload = self.give_aim
        # The roll's sign is the one that lifts the left shoulder.
        self.roll_sign = 1.0
        rolled = self.shoulders(self.trunk(1.0, 0.0))
        if rolled["l"][2] < rolled["r"][2]:
            self.roll_sign = -1.0
        self.belt = self.belt_place()
        # The chest rests on the floor in the reload's place too, the propped arm's skin rests on it, and the prop
        # and the pistol follow from both.
        self.elbow_up = 0.045
        for _ in range(4):
            self.place_reload()
            self.give_reload = self.rest_chest()
            self.place_reload()
            self.elbow_up += ARM_REST - self.arm_low(self.frame(0.5), "r")
        self.place_reload()

    def pole_aim(self, s, sign):
        """Where the aim points an elbow (`aim_spec`)."""
        ahead, out, up = self.body["pole"][s]
        return base.vec(ahead, sign * out, up + self.raised.get(s, 0.0))

    def arm_low(self, pose, s):
        """The lowest skin of an arm, as the game shows the pose, in metres over the floor."""
        skinned = self.rig.skin(aim.shown(self.rig, self.hold, pose))
        return min(self.rig.lowest(skinned, (f"{part}_{s}", f"{part}_twist_01_{s}")) for part in ARM_PARTS)

    def trunk(self, s, glance, give=None):
        """The trunk `s` of the way from the aim to the reload's place: the aim's own turns with the roll onto the
        firing side on top."""
        n = self.n
        if give is None:
            give = mix(self.give_aim, self.give_reload, s)
        spec = aim.trunk_spec(self.body, self.lower, 0.0, 0.0, give)
        roll = self.roll_sign * n["roll"] * s
        for name, share in (("spine_01", 0.3), ("spine_02", 0.65), ("spine_03", 1.0)):
            pitch, yaw, tip = spec["trunk"][name]
            spec["trunk"][name] = (pitch, yaw - n["yaw"] * s * share, tip + roll * share)
        pitch, yaw, tip = spec["trunk"]["neck_01"]
        spec["trunk"]["neck_01"] = (pitch + 0.4 * n["glance"][0] * glance, yaw - n["yaw"] * s, tip + 0.3 * roll)
        pitch, yaw, tip = spec["trunk"]["Head"]
        spec["trunk"]["Head"] = (pitch + n["glance"][0] * glance, yaw + n["glance"][1] * glance, tip)
        spec["clav"]["r"] = tuple(mix(np.array(spec["clav"]["r"]), np.array(n["clav_r"]), s))
        spec["clav"]["l"] = tuple(mix(np.array(spec["clav"]["l"]), np.array(n["clav_l"]), s))
        return spec

    def shoulders(self, spec):
        trunk = self.solver._trunk(spec, np.zeros(2))
        return {s: trunk["upperarm_" + s][:3, 3].copy() for s, _ in base.SIDES}

    def place_reload(self):
        """The propped elbow over the floor, one upper arm from the shoulder, and the pistol at the end of the
        raised forearm."""
        rig, n = self.rig, self.n
        shoulder = self.shoulders(self.trunk(1.0, 0.0))["r"]
        drop = shoulder[2] - self.elbow_up
        length = rig.len["upperarm_r"]
        if drop >= length:
            raise SystemExit(f"the right shoulder is {drop:.3f} m over the elbow's rest, more than the upper arm")
        out = math.sqrt(length**2 - drop**2)
        a = math.radians(n["elbow_out"])
        self.prop = shoulder + base.vec(out * math.cos(a), -out * math.sin(a), -drop)
        up, inward = math.radians(n["forearm_up"]), math.radians(n["forearm_in"])
        along = base.vec(math.cos(up) * math.cos(inward), math.cos(up) * math.sin(inward), math.sin(up))
        wrist = self.prop + rig.len["lowerarm_r"] * along
        turn = self.hold.basis(n["muzzle_up"], n["cant"], n["muzzle_in"])
        self.pistol_reload = self.hold.pistol_for_wrist(wrist, turn)

    def rest_chest(self):
        """Degrees the spine gives so that the rolled chest's skin rests on the floor."""

        def low(give):
            pose = aim.solve_pose(self.rig, self.solver, self.lower, self.spec(0.5, give))
            skinned = self.rig.skin(aim.shown(self.rig, self.hold, pose))
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
        belt = self.n["belt"]
        pose = self.aim_pose
        world = rig.world(pose["local"], pose["pelvis"])
        skinned = rig.skin(world)
        hip = world["thigh_l"][:3, 3]
        ahead = -hip[1] + belt[0]
        band = np.isin(rig.owner, ("pelvis", "spine_01", "thigh_l", "thigh_twist_01_l"))
        band &= (-skinned[:, 1] < ahead) & (-skinned[:, 1] > ahead - 0.2)
        waist = float(skinned[band, 0].max())
        place = base.vec(ahead, waist + belt[1], belt[2])
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
        up, top, down, gone = self.n["let_go_shares"]
        pistol[1, 3] += self.n["let_go_lift"] * smoothstep(up, top, t) * (1.0 - smoothstep(down, gone, t))
        return pistol

    def share(self, t):
        return smoothstep(*PISTOL_IN, t) * (1.0 - smoothstep(*PISTOL_OUT, t))

    def left(self, t, pistol):
        """The left hand at a share of the clip: its bone's place and turn, the way its elbow points, how far the
        hand keeps the forearm's line, and its fingers. Wherever the hold has the hand, the hold's own place and
        fingers; between, the belt and a hand that closes on the new magazine."""
        hold, n = self.hold, self.n
        plan = hold.plan(t)
        held = hold.left_fingers(plan)
        near = hold.hands_of(pistol, hold.left_place(plan))["l"]
        pole_work = mix(self.pole_aim("l", 1.0), base.unit(base.vec(*n["pole_magazine"])), self.share(t))
        returned = inverse_lerp(hold.back[0], hold.back[1], t)
        lifted = smoothstep(0.1, 0.5, returned) * (1.0 - smoothstep(0.85, 1.3, returned))
        pole_work = mix(pole_work, base.unit(base.vec(*n["pole_return"])), lifted)
        gone_at = hold.leave[0] + (hold.leave[1] - hold.leave[0]) * LET_GO_WAY
        if t <= gone_at or t >= hold.reach[1]:
            return near, pole_work, 0.0, held
        belt_place, belt_turn = self.belt
        opened = hold.poses["open"]
        grasp = {bone: base.slerp(opened[bone], turn, n["grasp"]) for bone, turn in hold.poses["support"].items()}
        if t < BELT_SHARES[1]:
            w = smoothstep(gone_at, BELT_SHARES[0], t)
            far = near
            close = smoothstep(BELT_SHARES[0] - 0.04, BELT_SHARES[0] + 0.01, t)
            fingers = {bone: base.slerp(opened[bone], turn, close) for bone, turn in grasp.items()}
        else:
            # Back from the belt to the line under the magazine, where the hold takes the hand again.
            w = 1.0 - smoothstep(BELT_SHARES[1], hold.reach[1], t)
            far = hold.hands_of(pistol, hold.left_place(hold.plan(max(t, hold.reach[0]))))["l"]
            under = smoothstep(hold.reach[0], hold.reach[1], t)
            fingers = {bone: base.slerp(turn, hold.poses["magazine"][bone], under) for bone, turn in grasp.items()}
        place = (1.0 - w) ** 2 * far[0] + 2.0 * w * (1.0 - w) * base.vec(*n["belt_swing"]) + w**2 * belt_place
        turn = base.slerp(far[1], belt_turn, w)
        pole = mix(pole_work, base.unit(base.vec(*n["pole_belt"])), w)
        free = min(n["belt_loose"] * base.smooth(w) + n["swing_loose"] * math.sin(math.pi * w), 0.95)
        return (place, turn), pole, free, fingers

    def spec(self, t, give=None, raised=None):
        """The targets of the frame at a share of the clip; `raised` turns each side's elbow pole up."""
        raised = raised or {}
        hold = self.hold
        s = self.share(t)
        glance = smoothstep(hold.reach[0], hold.insert[0], t) * (1.0 - smoothstep(hold.insert[1], hold.back[0], t))
        spec = self.trunk(s, glance, give)
        pistol = self.pistol(t)
        right = hold.hands_of(pistol, hold.support)["r"]
        left, pole_l, free, fingers = self.left(t, pistol)
        shoulder = self.shoulders(spec)["r"]
        pole_r = mix(self.pole_aim("r", -1.0), base.unit(self.prop - shoulder), s)
        pole_r = pole_r + base.vec(0.0, 0.0, raised.get("r", 0.0))
        pole_l = pole_l + base.vec(0.0, 0.0, raised.get("l", 0.0))
        for side, (place, turn), pole in (("r", right, pole_r), ("l", left, pole_l)):
            spec["arm"][side] = {
                "wrist": place,
                "pole": pole,
                "palm": turn @ np.array([0.0, 0.0, -1.0]),
                "hand_turn": turn,
            }
            spec["leg"][side] = self.lower["leg"]
        spec["arm"]["l"]["hand_free"] = free
        # The index finger is on the trigger only where the clip joins the aim.
        on_trigger = 1.0 - smoothstep(0.0, TRIGGER_OFF, t) * (1.0 - smoothstep(1.0 - TRIGGER_OFF, 1.0, t))
        spec["fingers"] = dict(hold.right_fingers(on_trigger), **fingers)
        return spec

    def frame(self, t):
        """The frame's pose. Where an elbow would dip into the floor (the right one on its way down to its prop and
        back up, the left one as the hand comes back onto the pistol), its pole is turned up until the arm's skin
        rests on the floor, as the aim does."""
        raised = {}
        pose = aim.solve_pose(self.rig, self.solver, self.lower, self.spec(t))
        for s in ("r", "l"):
            if self.arm_low(pose, s) >= ARM_REST - 2e-4:
                continue
            under, over = 0.0, 3.0
            for _ in range(20):
                middle = (under + over) / 2
                pose = aim.solve_pose(self.rig, self.solver, self.lower, self.spec(t, None, dict(raised, **{s: middle})))
                if self.arm_low(pose, s) < ARM_REST:
                    under = middle
                else:
                    over = middle
            raised[s] = over
            pose = aim.solve_pose(self.rig, self.solver, self.lower, self.spec(t, None, raised))
        return pose


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--body", required=True, choices=sorted(BODIES))
    parser.add_argument("--model", required=True)
    parser.add_argument("--hold", required=True)
    parser.add_argument("--idle", required=True, help="the prone library the body plays in the game")
    parser.add_argument("--aim", required=True, help="the body's prone aim file, whose first pose the clip joins")
    parser.add_argument("--out", required=True)
    parser.add_argument("--report")
    parser.add_argument("--keep-blend", help="save the scene with the body and the clip, to render it")
    parser.add_argument("--preview", action="store_true", help="export even when a check fails, to look at it")
    args = parser.parse_args(argv)
    body = aim.BODIES[args.body]

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    joined = base.library_pose(args.aim, AIM_CLIP, 0)
    arm, objects = base.import_glb(args.model)
    # The mesh drawn up close: a prototype body's farther levels of detail lie inside it.
    meshes = [o for o in objects if o.type == "MESH" and o.parent == arm]
    mesh = max(meshes, key=lambda o: len(o.data.vertices))
    for obj in objects:
        if obj.type == "MESH" and obj is not mesh:
            bpy.data.objects.remove(obj)
    rig = base.Rig(arm, mesh)
    hold = ReloadHold(args.hold, body["hold"])
    solver = ReloadSolver(rig, hold)
    lower = aim.read_lower(rig, args.idle)

    failures = []
    rest_off, rest_bone = aim.check_rests(rig, hold)
    if rest_off > 0.05:
        failures.append(f"the rig's rest of {rest_bone} is {rest_off:.3f} degrees off Godot's")
    reload = Reload(rig, solver, body, BODIES[args.body], hold, lower)
    frames = [reload.frame(f / FRAMES) for f in range(FRAMES + 1)]
    numbers = base.clip_numbers(rig, CLIP, frames)
    report = {"body": args.body, "fps": FPS, "clip": CLIP, "numbers": numbers, "frames": []}
    report["chest_give_degrees"] = [round(reload.give_aim, 3), round(reload.give_reload, 3)]
    report["prop"] = [round(float(v), 4) for v in reload.prop]
    report["belt"] = [round(float(v), 4) for v in reload.belt[0]]
    report["waist_left"] = round(reload.waist, 4)

    # The poses it joins: the aim as this build solves it, and the shipped file's first frame.
    for label, pose in (("first", frames[0]), ("last", frames[-1])):
        gap, apart = base.pose_gap(pose, reload.aim_pose)
        # The file holds the keyed bones only: the twist bones are turned for the pose, never keyed.
        in_file = {n: m for n, m in pose["local"].items() if n in joined["local"]}
        keyed = {"local": in_file, "pelvis": pose["pelvis"]}
        file_gap, file_apart = base.pose_gap(keyed, joined)
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
    lowest = {}  # part: [millimetres over the floor, frame]
    held = [f for f in range(FRAMES + 1) if PISTOL_IN[1] <= f / FRAMES <= PISTOL_OUT[0]]
    for f, pose in enumerate(frames):
        t = f / FRAMES
        world = rig.world(pose["local"], pose["pelvis"])
        pistol = hold.carried(rig, world)
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
        # The skin as the game shows it: each hand and each arm over the floor.
        skinned = rig.skin(aim.shown(rig, hold, pose))
        for s, _ in base.SIDES:
            reach = np.linalg.norm(world["hand_" + s][:3, 3] - world["upperarm_" + s][:3, 3])
            entry["stretch_" + s] = round(float(reach / (rig.len["upperarm_" + s] + rig.len["lowerarm_" + s])), 3)
            worst["stretch_" + s] = max(worst["stretch_" + s], entry["stretch_" + s])
            worst["bend_" + s] = max(worst["bend_" + s], entry["bend_" + s])
            mask = np.zeros(len(rig.owner), dtype=bool)
            for part in aim.HAND_PARTS:
                mask |= np.char.startswith(rig.owner, part) & np.char.endswith(rig.owner, "_" + s)
            entry["hand_" + s + "_mm"] = round(float(skinned[mask, 2].min()) * 1e3, 1)
            arm_low = min(rig.lowest(skinned, (f"{part}_{s}", f"{part}_twist_01_{s}")) for part in ARM_PARTS)
            entry["arm_" + s + "_mm"] = round(arm_low * 1e3, 1)
            for part in ("hand_" + s, "arm_" + s):
                if part not in lowest or entry[part + "_mm"] < lowest[part][0]:
                    lowest[part] = [entry[part + "_mm"], f]
        # The chest rests on the floor, pressed a little into it; the legs are the prone idle's and not this clip's.
        entry["chest_mm"] = round(rig.lowest(skinned, ("spine", "clavicle", "neck", "Head")) * 1e3, 1)
        if "chest" not in lowest or entry["chest_mm"] < lowest["chest"][0]:
            lowest["chest"] = [entry["chest_mm"], f]
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
    report["floor_mm"] = lowest
    for part, (up, f) in lowest.items():
        if up < {"hand": HAND_FLOOR, "arm_": ARM_FLOOR, "ches": CHEST_FLOOR}[part[:4]]:
            failures.append(f"the skin of {part} is {-up} mm under the floor at frame {f}")
    if worst["place"] > PLACE_LIMIT:
        failures.append(f"the left hand is {worst['place'] * 1000:.2f} mm off the hold's place for it")
    if worst["prop"] > PROP_LIMIT:
        failures.append(f"the propped elbow moves {worst['prop'] * 1000:.1f} mm while the pistol is reloaded")
    for s in "lr":
        if worst["bend_" + s] > WRIST_LIMIT:
            failures.append(f"the {s} wrist is bent {worst['bend_' + s]:.0f} degrees")
        if worst["stretch_" + s] > STRETCH_LIMIT:
            failures.append(f"the {s} arm cannot reach ({worst['stretch_' + s]:.3f} of its length)")

    action = base.key_clip(arm, rig, CLIP, frames)
    for frame_no in (FRAMES // 4, FRAMES // 2):
        off = base.check_against_blender(arm, mesh, rig, action, frames, frame_no)
        report["skinning_against_blender"] = round(off, 6)
        if off > 0.001:
            failures.append(f"the script's skinning is {off:.4f} m off Blender's at frame {frame_no}")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import limb_overlap

    measured_body = limb_overlap.Body(arm, mesh, args.body)
    entry = limb_overlap.measure(arm, action, range(FRAMES + 1), [measured_body])[args.body]
    # The two hands hold the pistol together: the game's hold closes them and its test measures them.
    hands = {k: v for k, v in entry["pairs"].items() if "hand_l" in k and "hand_r" in k}
    pairs = {k: v for k, v in entry["pairs"].items() if k not in hands and v[0] > 0.0}
    deepest = max((v[0] for v in pairs.values()), default=0.0)
    report["overlap_mm"] = {"deepest": deepest, "pairs": pairs, "hands": hands}
    if deepest > OVERLAP_LIMIT:
        failures.append(f"{pairs} (the limit is {OVERLAP_LIMIT} mm)")
    arm.animation_data.action = None
    print("REPORT", json.dumps(report, indent=1))
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    if args.keep_blend:
        bpy.ops.wm.save_as_mainfile(filepath=args.keep_blend)
    if failures:
        print("BUILD FAILED\n  " + "\n  ".join(failures))
        if not args.preview:
            raise SystemExit(1)
    bpy.data.objects.remove(mesh)
    # The twist bones, sockets and IK targets are not keyed (the game's `MannequinTwist` turns the twist bones
    # after the clip), so the file holds the library's 65 bones, as the body's prone file does.
    base.export(arm, args.out, rig.extra)
    print("EXPORTED", args.out)


if __name__ == "__main__":
    main()
