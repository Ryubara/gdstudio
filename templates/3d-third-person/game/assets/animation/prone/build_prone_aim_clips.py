"""Build the template's prone aim clips and export them to glTF (kit #1111).

GDStudio's own animation, made from nothing on the Quaternius universal rig, because neither the Universal Animation
Library nor the prone clips of kit #1009 hold a weapon lying down. Three poses of a body that lies on its belly and
aims the pistol with both hands, by how far it looks up or down: the elbows stay planted on the floor ahead of the
shoulders, the forearms carry the pistol in front of the face, and the chest rides on the elbows. The pelvis and the
legs are the prone idle's first pose to the bit, so the game lays these clips over the prone idle and the crawl from
`spine_01` up. Each clip is a slow breath that leaves the pistol still.

The hands are placed from the hold the game uses, never from a typed number: `tools/hold/dump_aim_seat.gd` writes the
pistol's seat on `hand_r`, the left hand's `SupportHand` marker and the wrist turn of the grip pose, and this script
puts the right hand's bone where that seat carries the pistol along the aim and the left hand's bone on the marker
(the game's `HoldArm` then finds the left hand where the clip already has it).

Run it with the pinned Blender, headless (`gds tool path blender`), every path absolute:

    blender -b --factory-startup -P build_prone_aim_clips.py -- --model <mannequin_female.glb>
        --male <mannequin_male.glb> --hold <aim_seat.json> --out <prone_aim.glb> [--report <numbers.json>]

It shares the rig, the solver, the keying and the export of `build_prone_clips.py` (same folder), and fails before it
exports when a loop does not close, a target is missed, the pistol is off its line, the lower body differs from the
prone idle's, a forearm or a hand of the female goes under the floor, or a part of the body goes more than 5 mm into
another on either mannequin (the two hands on each other are closed by the game's hold and measured there).
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_prone_clips as base  # noqa: E402

FPS = base.FPS
FRAMES = 90  # one breath, the prone idle's length
# The clips and the look each is made for, in degrees (up is positive). The game blends them by the look.
CLIPS = {
    "Prone_Aim_Down_Loop": -25.0,
    "Prone_Aim_Neutral_Loop": 0.0,
    "Prone_Aim_Up_Loop": 20.0,
}
LOWER_BODY = ("root", "pelvis", "thigh", "calf", "foot", "ball")
EXTEND = 0.93  # how far the right arm is stretched toward the pistol (1 is locked straight)
GRIP_RIGHT = 0.005  # metres the pistol's grip is to the right of the body's middle: in front of the right eye
HEAD_LEAN = (6.0, 8.0)  # degrees the head turns and tips to the left, the right eye behind the sights
CLEAR = {"foot": 0.006, "muzzle": 0.04}  # metres the grip's foot and the muzzle stay over the floor
GRIP_UP = {20.0: 0.15}  # the grip over the floor for a look that lifts the pistol off it
ELBOW_POLE = (-0.2, 0.5, -1.0)  # where the elbows point: ahead (negative is back), out to the side, up
HAND_CLEAR = 0.002  # metres the hands' skin stays over the floor
CHEST_SINK = 0.003  # metres the chest's skin presses into the floor
TRUNK = {  # each trunk bone's pitch from standing (90 lies face down); the spine then gives until the chest rests
    "pelvis": 89.0,
    "spine_01": 86.0,
    "spine_02": 79.0,
    "spine_03": 71.0,
    "neck_01": 54.0,
    "Head": 30.0,
}
HEAD_FOLLOW = (0.2, 0.45)  # the share of the look the neck and the head follow
CLAV = (22.0, 0.0)  # degrees the collarbones lift toward the head and push toward the chest, arms ahead
FLOOR_LIMIT = 5.0  # millimetres a hand or forearm of the female may be under the floor
LINE_LIMIT = 0.3  # degrees the barrel may be off the look, and millimetres/10 a hand may be off its place
OVERLAP_LIMIT = base.OVERLAP_LIMIT

# Godot's axes (x left, y up, z ahead) to Blender's (x left, y back, z up).
TO_BLENDER = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])


def xf(numbers):
    """A transform written as twelve numbers (the basis' columns, then the origin) as a 4x4 matrix."""
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = (
        numbers[0:3],
        numbers[3:6],
        numbers[6:9],
        numbers[9:12],
    )
    return m


def quat_matrix(q):
    x, y, z, w = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


class Hold:
    """The pistol's hold as the game has it (`dump_aim_seat.gd`), and where it puts the two hand bones."""

    def __init__(self, path, model="female"):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        self.seat = xf(data["seat"])
        self.support = xf(data["support"])
        self.muzzle = xf(data["muzzle"])
        self.foot = xf(data["foot"])
        self.turn = quat_matrix(data["turn"])
        self.rest = {
            "r": xf(data["models"][model]["hand_r"])[:3, :3],
            "l": xf(data["models"][model]["hand_l"])[:3, :3],
        }

    def pistol(self, grip, look):
        """The pistol's transform in Godot's model space with its grip at `grip` (Blender's axes), aimed `look`
        degrees up from straight ahead. The pistol's own axes: the muzzle along -X, up +Y, its left +Z."""
        a = math.radians(look)
        ahead = np.array([0.0, math.sin(a), math.cos(a)])
        left = np.array([1.0, 0.0, 0.0])
        m = np.eye(4)
        m[:3, 0], m[:3, 1], m[:3, 2] = -ahead, np.cross(ahead, left), left
        m[:3, 3] = TO_BLENDER.T @ np.asarray(grip, dtype=float)
        return m

    def hands(self, grip, look):
        """For each side, the hand bone's place and its world turn from the rest, in Blender's axes: the right hand
        where the seat carries the pistol (less the wrist turn the game's grip pose adds after the clip), the left
        hand on the support marker."""
        pistol = self.pistol(grip, look)
        right = pistol @ np.linalg.inv(self.seat)
        left = pistol @ self.support
        out = {}
        for s, posed, undo in (("r", right, self.turn.T), ("l", left, np.eye(3))):
            turn = posed[:3, :3] @ undo @ self.rest[s].T
            out[s] = (TO_BLENDER @ posed[:3, 3], TO_BLENDER @ turn @ TO_BLENDER.T)
        return out

    def measure(self, rig, world, look):
        """What a solved pose does to the pistol: degrees the barrel is off the look and metres the left hand's
        bone is off the support marker."""
        hand = world["hand_r"]
        turn = TO_BLENDER.T @ (hand[:3, :3] @ rig.rest_rot["hand_r"].T) @ TO_BLENDER
        posed = np.eye(4)
        posed[:3, :3] = turn @ self.rest["r"] @ self.turn
        posed[:3, 3] = TO_BLENDER.T @ hand[:3, 3]
        pistol = posed @ self.seat
        a = math.radians(look)
        barrel = -pistol[:3, 0]
        off = math.degrees(
            math.acos(
                min(1.0, float(barrel @ np.array([0.0, math.sin(a), math.cos(a)])))
            )
        )
        marker = TO_BLENDER @ (pistol @ self.support)[:3, 3]
        muzzle = TO_BLENDER @ (pistol @ self.muzzle)[:3, 3]
        foot = TO_BLENDER @ (pistol @ self.foot)[:3, 3]
        return off, float(np.linalg.norm(marker - world["hand_l"][:3, 3])), muzzle, foot


class AimSolver(base.Solver):
    """The prone solver with a hand that takes its turn from the weapon, not from the forearm."""

    def _arm(self, world, spec, s, sign):
        super()._arm(world, spec, s, sign)
        turn = spec["arm"][s].get("hand_turn")
        if turn is not None:
            world["hand_" + s][:3, :3] = turn @ self.rig.rest_rot["hand_" + s]


def trunk_spec(anchor, look, phase, give):
    """The lying body without its arms: the trunk's arch, flattened by `give` degrees so the chest rests, with a
    slow breath, and the head following the look."""
    breath = math.sin(2 * math.pi * phase)
    late = math.sin(2 * math.pi * (phase - 0.12))
    spec = base.prone_base(anchor["pelvis_up"])
    spec["comply"] = False
    trunk = spec["trunk"]
    trunk["pelvis"] = (TRUNK["pelvis"], 0.0, 0.0)
    trunk["spine_01"] = (TRUNK["spine_01"] + give / 3 - 0.3 * breath, 0.0, 0.0)
    trunk["spine_02"] = (TRUNK["spine_02"] + 2 * give / 3 - 0.6 * breath, 0.0, 0.0)
    trunk["spine_03"] = (TRUNK["spine_03"] + give - 0.8 * breath, 0.0, 0.0)
    trunk["neck_01"] = (TRUNK["neck_01"] - HEAD_FOLLOW[0] * look - 0.5 * late, 0.0, 0.0)
    trunk["Head"] = (TRUNK["Head"] - HEAD_FOLLOW[1] * look - 0.6 * late, HEAD_LEAN[0], HEAD_LEAN[1])
    for s, _ in base.SIDES:
        spec["clav"][s] = (CLAV[0] + 0.6 * breath, CLAV[1])
    return spec


def grip_up(hold, look):
    """The grip's height that rests the pistol as low as the floor lets it (the grip's foot and the muzzle keep
    `CLEAR`), or the height typed for a look that lifts it."""
    if look in GRIP_UP:
        return GRIP_UP[look]
    pistol = hold.pistol(base.vec(0.0, 0.0, 0.0), look)
    low = [
        CLEAR[part] - (TO_BLENDER @ (pistol @ point)[:3, 3])[2]
        for part, point in (("foot", hold.foot), ("muzzle", hold.muzzle))
    ]
    return max(low)


def grip_place(rig, hold, shoulders, look, up):
    """Where the pistol's grip is, `up` over the floor and `GRIP_RIGHT` to the right of the body's middle (in
    front of the right eye), so that the right wrist is `EXTEND` of the arm's length from its shoulder: one
    unknown (how far ahead), bisected. Returns the place and how far the left arm is stretched (1 is straight)."""

    def reach(ahead, s):
        hands = hold.hands(base.vec(ahead, -GRIP_RIGHT, up), look)
        return np.linalg.norm(hands[s][0] - shoulders[s]) / (rig.len["upperarm_" + s] + rig.len["lowerarm_" + s])

    near, far = -shoulders["r"][1], -shoulders["r"][1] + 1.0
    for _ in range(50):
        middle = (near + far) / 2
        if reach(middle, "r") < EXTEND:
            near = middle
        else:
            far = middle
    return base.vec(near, -GRIP_RIGHT, up), float(reach(near, "l"))


def aim_spec(rig, solver, hold, anchor, look, phase, give, grip=None, lift=0.0):
    """The targets of one frame: the trunk, and both arms stretched to the hands on the pistol. The pistol is
    placed from the shoulders once (`grip` none) and stays there through the breath."""
    spec = trunk_spec(anchor, look, phase, give)
    miss = 0.0  # how far the left arm is stretched
    if grip is None:
        trunk = solver._trunk(spec, np.zeros(2))
        shoulders = {s: trunk["upperarm_" + s][:3, 3].copy() for s, _ in base.SIDES}
        grip, miss = grip_place(rig, hold, shoulders, look, grip_up(hold, look) + lift)
    hands = hold.hands(grip, look)
    for s, sign in base.SIDES:
        place, turn = hands[s]
        spec["arm"][s] = {
            "wrist": place,
            "pole": base.vec(ELBOW_POLE[0], sign * ELBOW_POLE[1], ELBOW_POLE[2]),
            "palm": turn @ np.array([0.0, 0.0, -1.0]),
            "hand_turn": turn,
        }
        spec["leg"][s] = base.lying_leg(rig, sign, anchor)
    spec["grip"] = grip
    spec["left_reach"] = miss
    return spec


def chest_give(rig, solver, hold, anchor):
    """Degrees the spine flattens so that the chest's skin rests on the floor (pressed `CHEST_SINK` into it)."""

    def low(give):
        pose = solver.solve(aim_spec(rig, solver, hold, anchor, 0.0, 0.0, give))
        skinned = rig.skin(rig.world(pose["local"], pose["pelvis"]))
        return rig.lowest(skinned, ("spine_02", "spine_03", "clavicle")) + CHEST_SINK

    under, over = 30.0, -20.0  # the chest in the floor, and off it
    for _ in range(30):
        middle = (under + over) / 2
        if low(middle) < 0.0:
            under = middle
        else:
            over = middle
    return (under + over) / 2


def build_clip(rig, solver, hold, anchor, look, give, lower):
    frames = []
    # The hands rest on the floor with the pistol: lifted until their skin, fingers closed, is `HAND_CLEAR` over it.
    lift = 0.0
    for _ in range(5):
        grip = aim_spec(rig, solver, hold, anchor, look, 0.0, give, None, lift)
        pose = solver.solve(grip)
        skinned = rig.skin(rig.world(pose["local"], pose["pelvis"]))
        low = rig.lowest(skinned, ("hand", "index", "middle", "ring", "pinky", "thumb"))
        if low >= HAND_CLEAR - 1e-4:
            break
        lift += HAND_CLEAR - low
    for f in range(FRAMES):
        spec = aim_spec(rig, solver, hold, anchor, look, f / FRAMES, give, grip["grip"])
        pose = solver.solve(spec)
        pose["left_reach"] = grip["left_reach"]
        for n in pose["local"]:
            if n.rstrip("_lr").rstrip("_") in LOWER_BODY or n.startswith("ball_leaf"):
                pose["local"][n] = lower["local"][n]
        pose["pelvis"] = lower["pelvis"].copy()
        frames.append(pose)
    return frames + [frames[0]]


def bend(rig, world, s):
    """Degrees the wrist is bent: the hand's turn from the forearm, less the turn it has at rest."""
    rest = rig.rest_rot["lowerarm_" + s].T @ rig.rest_rot["hand_" + s]
    now = world["lowerarm_" + s][:3, :3].T @ world["hand_" + s][:3, :3]
    return math.degrees(base.to_quat(rest.T @ now).angle)


def pose_numbers(rig, hold, pose, look):
    world = rig.world(pose["local"], pose["pelvis"])
    skinned = rig.skin(world)
    off, apart, muzzle, foot = hold.measure(rig, world, look)
    out = {
        "barrel_off_degrees": round(off, 4),
        "left_hand_off_mm": round(apart * 1000.0, 3),
        "muzzle_up": round(float(muzzle[2]), 3),
        "foot_up": round(float(foot[2]), 3),
        "muzzle_ahead": round(float(-muzzle[1]), 3),
        "head_top": round(float(skinned[np.char.startswith(rig.owner, "Head"), 2].max()), 3),
        "head_ahead": round(float(-world["Head"][1, 3]), 3),
        "head_up": round(float(world["Head"][2, 3]), 3),
    }
    for s, _ in base.SIDES:
        out["shoulder_up_" + s] = round(float(world["upperarm_" + s][2, 3]), 3)
        out["elbow_" + s] = [round(float(v), 3) for v in world["lowerarm_" + s][:3, 3]]
        out["wrist_" + s] = [round(float(v), 3) for v in world["hand_" + s][:3, 3]]
        out["wrist_bend_" + s] = round(bend(rig, world, s), 1)
    for part in ("spine", "clavicle", "upperarm", "lowerarm", "hand", "neck", "Head"):
        extra = ("index", "middle", "ring", "pinky", "thumb") if part == "hand" else ()
        out["lowest_" + part] = round(rig.lowest(skinned, (part,) + extra), 4)
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--male", required=True)
    parser.add_argument("--hold", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--report")
    parser.add_argument("--preview", action="store_true", help="export even when a check fails, to look at it")
    args = parser.parse_args(argv)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    arm, objects = base.import_glb(args.model)
    mesh = next(o for o in objects if o.type == "MESH" and o.parent == arm)
    for obj in objects:
        if obj.type == "MESH" and obj.parent is None:
            bpy.data.objects.remove(obj)
    rig = base.Rig(arm, mesh)
    solver = AimSolver(rig)
    hold = Hold(args.hold)
    anchor = base.measure_anchor(rig, solver)
    # The prone idle's first pose: the lower body every aim clip keeps.
    solver.warm = np.zeros(2)
    lower = base.build_idle(rig, solver, anchor)[0]
    anchor = dict(anchor, pelvis_up=lower["pelvis_up"])

    give = chest_give(rig, solver, hold, anchor)
    report = {"fps": FPS, "clips": {}, "chest_give_degrees": round(give, 3)}
    failures = []
    clips = {}
    for name, look in CLIPS.items():
        clips[name] = build_clip(rig, solver, hold, anchor, look, give, lower)
    for name, frames in clips.items():
        look = CLIPS[name]
        numbers = base.clip_numbers(rig, name, frames)
        numbers["look"] = look
        numbers["seam_degrees"] = round(base.seam(frames), 5)
        numbers["pose"] = pose_numbers(rig, hold, frames[0], look)
        numbers["left_arm_stretch"] = round(frames[0]["left_reach"], 4)
        if frames[0]["left_reach"] > 0.992:
            failures.append(f"{name}: the left arm cannot reach the pistol ({frames[0]['left_reach']:.3f} of its length)")
        worst_line, worst_hand, stray = 0.0, 0.0, 0.0
        first = rig.world(frames[0]["local"], frames[0]["pelvis"])
        for pose in frames:
            world = rig.world(pose["local"], pose["pelvis"])
            off, apart, _, _ = hold.measure(rig, world, look)
            worst_line, worst_hand = max(worst_line, off), max(worst_hand, apart)
            for bone in ("hand_l", "hand_r"):
                stray = max(stray, float(np.linalg.norm(world[bone][:3, 3] - first[bone][:3, 3])))
        numbers["barrel_off_degrees"] = round(worst_line, 4)
        numbers["left_hand_off_mm"] = round(worst_hand * 1000.0, 3)
        numbers["arms_stray_mm"] = round(stray * 1000.0, 3)
        gap = max(
            math.degrees(
                base.to_quat(frames[0]["local"][n]).rotation_difference(base.to_quat(lower["local"][n])).angle
            )
            for n in lower["local"]
            if n.rstrip("_lr").rstrip("_") in LOWER_BODY
        )
        numbers["lower_body_off_degrees"] = round(gap, 5)
        report["clips"][name] = numbers
        if numbers["solver_miss"] > 0.001:
            failures.append(f"{name}: a target is missed by {numbers['solver_miss']:.4f} m")
        if numbers["seam_degrees"] > 0.01:
            failures.append(f"{name}: the loop does not close")
        if worst_line > LINE_LIMIT or worst_hand * 1000.0 > LINE_LIMIT * 10:
            failures.append(
                f"{name}: the barrel is {worst_line:.3f} degrees off the look, the left hand"
                f" {worst_hand * 1000:.2f} mm off its marker"
            )
        if stray > 0.0005:
            failures.append(f"{name}: a wrist moves {stray * 1000:.2f} mm in the breath")
        if gap > 0.01:
            failures.append(f"{name}: the lower body is {gap:.3f} degrees off the prone idle's")
        if numbers["lowest"] < -0.02:
            failures.append(f"{name}: the mesh goes {-numbers['lowest']:.3f} m under the floor")
        for part in ("muzzle_up", "foot_up"):
            if numbers["pose"][part] < 0.003:
                failures.append(f"{name}: the pistol's {part[:-3]} is {numbers['pose'][part]} m over the floor")

    actions = {name: base.key_clip(arm, rig, name, frames) for name, frames in clips.items()}
    for name, frames in clips.items():
        off = base.check_against_blender(arm, mesh, rig, actions[name], frames, FRAMES // 3)
        report["clips"][name]["skinning_against_blender"] = round(off, 6)
        if off > 0.001:
            failures.append(f"{name}: the script's skinning is {off:.4f} m off Blender's")
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    import limb_overlap

    male = limb_overlap.load_body(args.male, "male")
    bodies = [limb_overlap.Body(arm, mesh, "female"), male]
    floor_failures = []
    report["floor_mm"] = base.floor_numbers(arm, actions, clips, bodies, floor_failures)
    for name in clips:
        for part, entry in report["floor_mm"][name]["female"].items():
            entry.pop("frames", None)
            if entry["lowest"] < -FLOOR_LIMIT:
                failures.append(f"{name}: the female's {part} is {-entry['lowest']} mm under the floor")
        for entry in report["floor_mm"][name]["male"].values():
            entry.pop("frames", None)
    report["overlap_mm"] = {}
    for name, frames in clips.items():
        measured = limb_overlap.measure(arm, actions[name], range(0, len(frames), 15), bodies)
        report["overlap_mm"][name] = {}
        for body, entry in measured.items():
            # The two hands hold the pistol together: the game's hold closes them and its test measures them.
            pairs = {
                k: v[0] for k, v in entry["pairs"].items() if not ("hand_l" in k and "hand_r" in k) and v[0] > 0.0
            }
            deepest = max(pairs.values(), default=0.0)
            report["overlap_mm"][name][body] = {"deepest": deepest, "pairs": pairs, "hands": {k: v[0] for k, v in entry["pairs"].items() if "hand_l" in k and "hand_r" in k}}
            if deepest > OVERLAP_LIMIT:
                failures.append(f"{name} on the {body}: {pairs} (the limit is {OVERLAP_LIMIT} mm)")
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
