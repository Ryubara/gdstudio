"""Build the template's pistol reload clip and export it to glTF (gdstudio #1584).

The Universal Animation Library's `Pistol_Reload` lifts the pistol to the right of the head and turns the head about
45 degrees down and round to it. Since a lean holds the head level through an action (gdstudio #1575, `PeekHold`),
that clip read on a left lean as the gun raised over the head: the trunk's roll lifts the right shoulder, and the
clip takes the gun further right and up from there (14 cm over the `Head` bone, `test_pistol_reload_height.gd`).
This clip is the same reload worked in front of the chest: the right hand brings the pistol in toward the body's
middle and down to the upper chest, tilted as the library tilts it (the magazine well toward the left hand), and the
head stays near the aim pose with a short glance down at the magazine well. It reads the same leaning and upright.

GDStudio's own animation over the library's timing. From the library it takes, frame by frame: how far along its move
the pistol is (its progress from the aim to its station, so every ease, the magazine's drop and the seat's jolt come
at the library's frames and pace), the pistol's turn, the left arm's way to the belt for the new magazine (the hold's
carry fingers were solved on that pose: `tools/hold/solve_pistol_hold.py`, `BELT_POSE`), the pelvis, the legs and the
fingers. It works out new: where the pistol is (`STATION`, the part of the library's move off its main line kept by
`WIGGLE`), the right arm reached to it, the left arm from the belt to the hold's place under the magazine and on with
the gun, the neck and the head (the aim pose's, turned by `HEAD_TURN` on the library's head curve one frame late), the
chest's lean over the gun and the collarbones (`CLAVICLE_KEEP` of the library's move). Its first and last frames are
the library's, which `Pistol_Rack` starts and ends on. The reload's beats (`SupportHandPlan`: the left hand's let-go,
the magazine out, the take at the belt, the reach, the insert and the return) stay at the library's shares, since
the clip has the library's length and timing.

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_pistol_reload.py -- --out <pistol_reload.glb> [--report <numbers.json>]
        [--preview] [--arms-only] [--check]

It fails before it exports when the clip does not start and end on the library's pose, an arm cannot reach, the right
hand rises above `CHIN_DROP` under the head bone, the head turns more than `HEAD_LIMIT` off the aim pose, or a part
of the body goes more than 5 mm into another on either prototype body (`../limb_overlap.py`; the left hand and
forearm are not judged where the game's hold has the left hand, on the grip or under the magazine, which the hold's
own tests measure).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True  # Blender ignores PYTHONDONTWRITEBYTECODE

import build_pistol_rack as rack  # noqa: E402
import hold_files  # noqa: E402  (on the path through build_pistol_rack)

GAME = rack.GAME
FPS = 30
CLIP = "Pistol_Reload"
FRAMES = 50  # the clip's last frame: 1.667 s, the library's
OVERLAP_LIMIT = 5.0

# The reload's beats as shares of the clip (`SupportHandPlan`'s, the game's): the hold has the left hand on the
# support grip until `LEAVE[1]` and from `BACK[1]`, and under the magazine from `REACH[0]` on; between, the clip's.
LEAVE = (0.02, 0.1)
TAKE = 0.25
REACH = (0.3, 0.4)
INSERT = (0.4, 0.54)
BACK = (0.71, 0.88)

# The game's fades of the reload over the aim, as shares of the clip (`WeaponLayers.RELOAD_FADE_IN`, 0.15 s, and
# `RELOAD_FADE_OUT`, 0.2 s, of the pistol's 1.6 s `reload_time`). The aim's own head and the left lean's cross of the
# pistol to the left eye (`LeftShoulderCross`) give way to the clip by the same weight, so what the clip changes to
# meet them is done over these.
FADE_IN = (0.0, 0.094)
FADE_OUT = (0.875, 1.0)

# Where the pistol goes, as a move from the aim pose's place in the character's space (left, up, forward, metres):
# where the library's main line of motion ends (its first stop, frames 13 to 23, 10 cm right, 9 cm up and 20 cm in)
# this clip's pistol is in front of the chest, a little right of the middle and under the chin. The library's
# progress along its line, eased out (`EASE`: the gun leaves the aim sooner), gives the up and forward of the
# pistol's; the move to the middle (`STATION`'s left) is over the fades, so a left lean's cross lets go of a pistol
# that is already coming in (it came back to the right shoulder first, which the lean's roll lifts: 9 mm over the
# head bone at share 0.09 with the library's pace).
STATION = (0.11, -0.085, -0.15)
EASE = 0.6
# On the way back the pistol leaves the middle as it goes out to the aim: an arm across the chest does not reach
# the aim's distance (3 mm short at frames 45 to 47 when the move back to the right waited for the fade out). Out
# beyond this share of the eased progress it is all the way back on the right.
GATHER_REACH = 0.3
# The library's pistol is back at the aim at 0.92, while the game's fade out (and the left lean's cross with it) runs
# to the end: a left lean showed the gun back on the right shoulder, lifted by the roll, before the cross had it
# (the hand 30 mm under the head bone at 0.92, the aimed lean's 70). So from `RETURN_FROM` the pistol follows the
# library's frames later, by the time to the power `RETURN_LATE` (at 0.92 it is where the library's was at 0.86),
# and ends on the library's last frame.
RETURN_FROM = 0.72
RETURN_LATE = 2.0
# How much of the library's move off its main line is kept (the seat's jolt rises 3 cm up and right of it).
WIGGLE = 0.3
# How much of the library's turn of the pistol is kept (muzzle up 48 degrees, canted 40: the magazine well faces
# down and forward to the left hand coming up from the belt, the way the hold's magazine approach runs).
TILT = 0.45
# The neck and the head. Aimed, the game holds the head level on the aim (`AimHeadModifier`, the turn shared
# `NECK_SHARE` to the neck); the library's aim pose under it tips the head 19 degrees down and rolls it 10, which the
# reload showed (36 degrees off the aimed head, upright). So over the fade in the clip turns the head to the level
# look (the rest's, the character facing its aim) the modifier's way and back over the fade out, and between takes
# a glance at the magazine well on the library's head curve one frame late (the head moves after the chest):
# degrees down (about the character's left), to the right (about up) and the roll toward the gun.
NECK_SHARE = 0.4
HEAD_TURN = {"neck_01": (4.0, -2.0, 1.5), "Head": (7.0, -3.0, 2.5)}
# The chest leans over the gun by this much (degrees, each of `spine_02` and `spine_03`) on the same curve.
CHEST_PITCH = 1.5
# How much of the library's collarbone move is kept (it lifted the right shoulder to the high gun).
CLAVICLE_KEEP = {"clavicle_r": 0.4, "clavicle_l": 0.6}
# Where the left elbow points from the take on, in the character's space (out to the left, down, a little ahead),
# blended from the library's own.
LEFT_ELBOW = (0.7, 0.4, 0.15)
# The left hand moves with the pistol's move until `RIDE_UNTIL`, on its way to the belt. From the belt it goes to
# `DEEP` times the magazine's approach under the magazine by `DEEP_AT` and up the line from there (the game blends
# the clip's hand with the hold's place under the magazine from 0.3: a straight way from the belt put the new
# magazine 3.8 mm in the pistol at 0.35).
RIDE_UNTIL = 0.13
DEEP = 1.25
DEEP_AT = 0.35
# The checks.
CHIN_DROP = 0.06  # metres the right hand bone stays under the head bone (the chin is about this far under it)
HEAD_LIMIT = 20.0  # degrees the head may turn off the level look the game draws aimed


def library_frames(path, clip):
    """Every frame of a library clip as each bone's rotation in its parent and the pelvis's place, at `FPS`."""
    arm, objects = rack.import_glb(path)
    action = bpy.data.actions[clip]
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    first, end = (round(f) for f in action.frame_range)
    out = []
    for f in range(first, end + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        local, pelvis = {}, None
        for pb in arm.pose.bones:
            m = np.array((pb.parent.matrix.inverted() @ pb.matrix) if pb.parent else pb.matrix)
            if pb.parent is None:
                m = np.linalg.inv(rack.C) @ m
            local[pb.name] = np.array(Matrix(m[:3, :3].tolist()).to_quaternion().to_matrix())
            if pb.name == "pelvis":
                pelvis = m[:3, 3].copy()
        out.append({"local": local, "pelvis": pelvis})
    for obj in objects:
        bpy.data.objects.remove(obj)
    for each in list(bpy.data.actions):
        bpy.data.actions.remove(each)
    return out


def turn_angle(a, b):
    apart = np.linalg.norm(a - b) / (2.0 * math.sqrt(2.0))
    return math.degrees(2.0 * math.asin(min(apart, 1.0)))


def rotvec_scaled(m, t):
    """The rotation `m` taken `t` of the way from none."""
    return rack.slerp(np.eye(3), m, t)


def elbow_pole(world, side):
    """A point the elbow points at, from a pose: a reach with it as the pole gives that pose's elbow back."""
    shoulder, elbow, wrist = (world[f"{bone}_{side}"][:3, 3] for bone in ("upperarm", "lowerarm", "hand"))
    along = (wrist - shoulder) / np.linalg.norm(wrist - shoulder)
    foot = shoulder + along * ((elbow - shoulder) @ along)
    return elbow + (elbow - foot) * 2.0


class Reload:
    """The clip, worked out on one rig from the library's frames and the hold of the body it is keyed on."""

    def __init__(self, rig, library, hold, held_scene):
        self.rig, self.library = rig, library
        turn = np.eye(4)
        turn[:3, :3] = rack.quat_to_mat(hold["grip"]["turns"]["hand_r"])
        self.to_gun = turn @ hold["seat"]
        self.support = hold["support_hand"]
        self.magazine = held_scene["magazine_hand"]
        self.approach = held_scene["magazine_approach"]
        self.worlds = [rig.world(p) for p in library]
        self.guns = [w["hand_r"] @ self.to_gun for w in self.worlds]
        g0 = self.guns[0]
        moves = np.array([g[:3, 3] - g0[:3, 3] for g in self.guns])
        # The library's main line of motion: where its pistol stops first.
        self.line = moves[13:24].mean(axis=0)
        self.progress = moves @ self.line / (self.line @ self.line)
        self.off_line = moves - np.outer(self.progress, self.line)
        self.turns = [g0[:3, :3].T @ g[:3, :3] for g in self.guns]
        head = [turn_angle(p["local"]["Head"], library[0]["local"]["Head"]) for p in library]
        top = max(head)
        # The level look: the head as it rests, the character facing its aim.
        self.level = rig.world({"local": {n: rig.rest[n][:3, :3] for n in rig.names}, "pelvis": rig.rest["pelvis"][:3, 3]})["Head"]
        # One frame late: the head follows the chest.
        self.busy = [head[max(f - 1, 0)] / top for f in range(len(library))]

    def library_at(self, f):
        """The library's frame (a fraction) whose pistol this frame's follows: the same until `RETURN_FROM`, and
        later from there to the end (by the square of the time), so the way back to the aim comes later and the
        last frame is still the library's."""
        share = f / FRAMES
        if share <= RETURN_FROM:
            return float(f)
        t = (share - RETURN_FROM) / (1.0 - RETURN_FROM)
        return (RETURN_FROM + (1.0 - RETURN_FROM) * t**RETURN_LATE) * FRAMES

    def _sample(self, values, at):
        low = min(int(math.floor(at)), FRAMES)
        high = min(low + 1, FRAMES)
        t = at - low
        return values[low] * (1.0 - t) + values[high] * t

    def gun(self, f):
        """The pistol's place in the character's space on a frame."""
        g0 = self.guns[0]
        at = self.library_at(f)
        low = min(int(math.floor(at)), FRAMES)
        turn = rack.slerp(self.turns[low], self.turns[min(low + 1, FRAMES)], at - low)
        out = np.eye(4)
        out[:3, :3] = g0[:3, :3] @ rotvec_scaled(turn, TILT)
        progress = float(self._sample(self.progress, at))
        eased = 1.0 - (1.0 - min(progress, 1.0)) ** (1.0 / EASE) + max(progress - 1.0, 0.0)
        left, up, forward = STATION
        out[:3, 3] = (
            g0[:3, 3]
            + np.array([left * self.gathered(f, eased), up * eased, forward * eased])
            + WIGGLE * self._sample(self.off_line, at)
        )
        return out

    def gathered(self, f, eased):
        """How far the pistol is moved to the middle: over the fade in, and on the way back no further out than
        its way forward lets the right arm reach across (`GATHER_REACH` of the eased progress)."""
        share = f / FRAMES
        out = rack.smoothstep(*FADE_IN, share)
        if share > 0.5:
            out *= min(1.0 - rack.smoothstep(*FADE_OUT, share), min(eased / GATHER_REACH, 1.0))
        return out

    def faded(self, f):
        """How far the clip has the body over the game's fades: 0 at its ends, 1 between them."""
        share = f / FRAMES
        return rack.smoothstep(*FADE_IN, share) * (1.0 - rack.smoothstep(*FADE_OUT, share))

    def left_goal(self, f, gun):
        """The left hand bone's goal on a frame (a place in the character's space) and how far from the library's
        own place it is (0 the library's, 1 this clip's)."""
        share = f / FRAMES
        own = self.worlds[f]["hand_l"].copy()
        # The library's hand, moved with the pistol while it leaves the support grip (the hold hands it to the
        # clip's arm by 0.1: where the library had it, the gun had come to it, the thumb 2.2 mm in the frame),
        # and the library's own by the time it is at the belt.
        ride = 1.0 - rack.smoothstep(LEAVE[1], RIDE_UNTIL, share)
        own[:3, 3] = own[:3, 3] + (gun[:3, 3] - self.guns[f][:3, 3]) * ride
        under = gun @ rack.moved(self.magazine, self.approach)
        deep = gun @ rack.moved(self.magazine, self.approach * DEEP)
        seated = gun @ self.magazine
        support = gun @ self.support
        if share <= TAKE:
            return own, 0.0
        if share <= DEEP_AT:
            # From the belt to a place further down the magazine's line, so the hand comes up it from below.
            t = rack.smoothstep(TAKE, DEEP_AT, share)
            return rack.between(own, deep, t), t
        if share <= REACH[1]:
            return rack.between(deep, under, rack.smoothstep(DEEP_AT, REACH[1], share)), 1.0
        if share <= INSERT[1]:
            return rack.between(under, seated, rack.smoothstep(INSERT[0], INSERT[1], share)), 1.0
        if share <= BACK[0]:
            return seated, 1.0
        if share <= BACK[1]:
            return rack.between(seated, support, rack.smoothstep(BACK[0], BACK[1], share)), 1.0
        t = 1.0 - rack.smoothstep(BACK[1], 1.0, share)
        return rack.between(own, support, t), t

    def pose(self, f):
        rig = self.rig
        lib = self.library[f]
        aim = self.library[0]
        pose = {"local": dict(lib["local"]), "pelvis": lib["pelvis"]}
        busy = self.busy[f]
        for name, keep in CLAVICLE_KEEP.items():
            pose["local"][name] = rack.slerp(aim["local"][name], lib["local"][name], keep)
        for name in ("spine_02", "spine_03"):
            above = rig.chain(pose, rig.parent[name])[:3, :3]
            pose["local"][name] = above.T @ rack.axis_angle(rack.X, CHEST_PITCH * busy) @ above @ lib["local"][name]
        for name in ("neck_01", "Head"):
            pose["local"][name] = aim["local"][name]
        # The level look, the aim head modifier's way: one turn from where the head is to the rest's look, the
        # neck taking `NECK_SHARE` of it about the same axis, by how far the clip has the body.
        world = rig.world(pose)
        level = rack.slerp(np.eye(3), self.level[:3, :3] @ world["Head"][:3, :3].T, self.faded(f))
        # The neck turns by its share and carries the head; the head takes the rest about the same axis.
        for name, share in (("neck_01", NECK_SHARE), ("Head", 1.0 - NECK_SHARE)):
            above = rig.chain(pose, rig.parent[name])[:3, :3]
            here = rig.chain(pose, name)[:3, :3]
            pose["local"][name] = above.T @ rack.slerp(np.eye(3), level, share) @ here
        for name, (down, right, roll) in HEAD_TURN.items():
            above = rig.chain(pose, rig.parent[name])[:3, :3]
            here = rig.chain(pose, name)[:3, :3]
            turn = (
                rack.axis_angle(rack.Y, right * busy)
                @ rack.axis_angle(rack.X, down * busy)
                @ rack.axis_angle(here[:, 1], roll * busy)
            )
            pose["local"][name] = above.T @ turn @ above @ pose["local"][name]
        gun = self.gun(f)
        short_r = rack.reach(rig, pose, "r", gun @ np.linalg.inv(self.to_gun), elbow_pole(self.worlds[f], "r"))
        goal, mine = self.left_goal(f, gun)
        pole = np.asarray(elbow_pole(self.worlds[f], "l")) * (1.0 - mine) + np.asarray(LEFT_ELBOW) * mine
        short_l = rack.reach(rig, pose, "l", goal, pole)
        world = rig.world(pose)
        pose["numbers"] = {
            "short_r": short_r,
            "short_l": short_l,
            "hand_over_head": float(world["hand_r"][1, 3] - world["Head"][1, 3]),
            "hand_from_head": (world["hand_r"][:3, 3] - world["Head"][:3, 3]).tolist(),
            # Off the level look as the game draws it: the clip's head by the fade's weight over the aim's level one.
            "head_turn": turn_angle(world["Head"][:3, :3], self.level[:3, :3]) * self.faded(f),
            "head_turn_aim_pose": turn_angle(world["Head"][:3, :3], rig.world(aim)["Head"][:3, :3]),
            "gun": gun[:3, 3].tolist(),
        }
        return pose


def held_scene():
    """The magazine marker of the default body's hold and the hold's magazine approach, from the scene files."""
    held = (GAME / "assets" / "weapons" / "pistol" / "pistol_held.tscn").read_text(encoding="utf-8")
    block = held.split('[node name="MagazineHand"', 1)[1].split("[node", 1)[0]
    import re

    place = hold_files._place(re.search(r"transform = Transform3D\(([^)]*)\)", block).group(1))
    hold = (GAME / "gameplay" / "weapon" / "hold" / "weapon_hold.tscn").read_text(encoding="utf-8")
    approach = [float(v) for v in re.search(r"^magazine_approach = Vector3\(([^)]*)\)", hold, re.M).group(1).split(",")]
    return {"magazine_hand": place, "magazine_approach": np.array(approach)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    bodies = GAME / "assets" / "characters" / "prototype"
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=str(bodies / "form_female.glb"), help="the body the clip is keyed on")
    parser.add_argument("--male", default=str(bodies / "form_male.glb"))
    parser.add_argument("--library", default=str(GAME / "assets" / "animation" / "universal" / "ual1.glb"))
    parser.add_argument("--out", required=True)
    parser.add_argument("--report", help="write the numbers per frame (`pistol_reload.json` beside the clip)")
    parser.add_argument("--preview", action="store_true", help="export even when a check fails, to look at it")
    parser.add_argument("--arms-only", action="store_true", help="skip the limb check and the export (tuning)")
    parser.add_argument("--check", action="store_true", help="compare with the file on disk, write nothing")
    args = parser.parse_args(argv)
    sys.path.insert(0, str(HERE.parent))  # clip_check.py, limb_overlap.py
    import clip_check

    checking = clip_check.Check(args.check)
    args.out = checking.file(args.out)
    args.report = checking.file(args.report)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    library = library_frames(args.library, CLIP)
    if len(library) != FRAMES + 1:
        raise SystemExit(f"the library's {CLIP} has {len(library)} frames at {FPS} a second, not {FRAMES + 1}")
    arm, objects = rack.import_glb(args.model)
    for obj in objects:
        if obj is not arm:
            bpy.data.objects.remove(obj)
    rig = rack.Rig(arm)
    library_bones = set(library[0]["local"])
    for pose in library:
        for name in rig.names:
            pose["local"].setdefault(name, rig.rest[name][:3, :3])
    reload = Reload(rig, library, hold_files.read(GAME, "female"), held_scene())
    frames = [reload.pose(f) for f in range(FRAMES + 1)]

    failures = []
    report = {"fps": FPS, "frames": FRAMES, "seconds": round(FRAMES / FPS, 4), "per_frame": []}
    for f, pose in enumerate(frames):
        n = pose["numbers"]
        report["per_frame"].append(
            {
                "frame": f,
                "share": round(f / FRAMES, 3),
                "hand_over_head_mm": round(n["hand_over_head"] * 1000.0, 1),
                "library_hand_over_head_mm": round(
                    (reload.worlds[f]["hand_r"][1, 3] - reload.worlds[f]["Head"][1, 3]) * 1000.0, 1
                ),
                "head_turn_degrees": round(n["head_turn"], 1),
                "right_short_mm": round(n["short_r"] * 1000.0, 2),
                "left_short_mm": round(n["short_l"] * 1000.0, 2),
                "gun": [round(v, 3) for v in n["gun"]],
                "hand_from_head": [round(v, 3) for v in n["hand_from_head"]],
            }
        )
        if max(n["short_r"], n["short_l"]) > 0.0005:
            failures.append(f"frame {f}: an arm stops short of its hand's place")
        if n["hand_over_head"] > -CHIN_DROP:
            failures.append(f"frame {f}: the right hand is {n['hand_over_head'] * 1000:.0f} mm from the head bone")
        if n["head_turn"] > HEAD_LIMIT:
            failures.append(f"frame {f}: the head turns {n['head_turn']:.1f} degrees off the aim")
    joins = {
        "starts on the library's first frame": rack.pose_gap(frames[0], library[0]),
        "ends on the library's last frame": rack.pose_gap(frames[-1], library[-1]),
    }
    report["joins"] = {k: [round(v[0], 4), round(v[1], 5)] for k, v in joins.items()}
    for what, (turn, apart) in joins.items():
        if turn > 0.05 or apart > 0.0005:
            failures.append(f"{what}: off by {turn:.3f} degrees and {apart:.4f} m")
    print("NUMBERS", json.dumps([{k: v for k, v in e.items() if k != "gun"} for e in report["per_frame"]]))
    if args.arms_only:
        print("ARMS failures:", "; ".join(failures) or "none")
        return
    action = rack.key_clip(arm, rig, CLIP, frames, library_bones)

    import limb_overlap

    # Every frame on both bodies, as the game plays the clip on each body's own bone lengths; the left hand and
    # forearm are left out on the frames the hold has the left hand (on the grip, under the magazine and back).
    bodies_ = [limb_overlap.load_body(args.model, "female"), limb_overlap.load_body(args.male, "male")]
    report["overlap_mm"] = {}
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    for body in bodies_:
        judged = {"deepest": 0.0, "frame": None, "pair": None, "hold_owns_left_hand": 0.0}
        report["overlap_mm"][body.name] = judged
        for f in range(FRAMES + 1):
            share = f / FRAMES
            hold_has_it = share < LEAVE[1] or share >= REACH[0]
            bpy.context.scene.frame_set(f)
            body.pose_from(arm)
            for (a, b), (depth, _place) in body.overlaps().items():
                mm = round(depth * 1000.0, 1)
                pair = f"{a} in {b}"
                if hold_has_it and ({a, b} & {"hand_l", "lowerarm_l"}):
                    judged["hold_owns_left_hand"] = max(judged["hold_owns_left_hand"], mm)
                    continue
                if mm > judged["deepest"]:
                    judged.update(deepest=mm, frame=f, pair=pair)
        print(
            f"OVERLAP {CLIP} {body.name}: {judged['deepest']} mm at frame {judged['frame']} ({judged['pair']});"
            f" where the hold has the left hand it reads {judged['hold_owns_left_hand']} mm"
        )
        if judged["deepest"] > OVERLAP_LIMIT:
            failures.append(f"on the {body.name}: {judged['pair']} by {judged['deepest']} mm at frame {judged['frame']}")
        for obj in body.objects:
            bpy.data.objects.remove(obj)
    arm.animation_data.action = None
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8", newline="\n")
    if failures:
        print("BUILD FAILED\n  " + "\n  ".join(failures))
        if not args.preview:
            raise SystemExit(1)
    rack.export(arm, args.out)
    print("EXPORTED", args.out)
    checking.finish()


if __name__ == "__main__":
    main()
