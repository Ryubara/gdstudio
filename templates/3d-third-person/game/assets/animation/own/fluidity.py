"""How fluid a loop is, as numbers, beside the library clip it replaces (kit #1155).

    uv run --with numpy python -B fluidity.py [--json <file>] [--markdown] [--bones]
        [--pair <ours.glb>:<Clip>=<library>/<Clip> ...] [--model <body.glb>]

Every clip is played on one body (the prototype female by default) exactly as its file plays: the kept keys with
straight lines between them, 30 a second. Without `--pair` the shipped gaits are read against the clips they
replaced (`gds/Walk` against `ual1/Walk` and so on).

A gait repeats, so a motion is fluid when a part's turning is made of a few slow waves and choppy when it has
steps, corners and held stretches in it. Per clip:

- `harmonic`: for the body's joints, the square root of (jerk x cycle squared) over (speed x 4 pi squared), both as
  root mean squares over the cycle, weighted by how far each joint turns. A joint that swings as one smooth wave a
  cycle reads 1, one that swings twice a cycle 2; corners, stops and flicks raise it. It does not depend on how
  fast or how far the clip moves, so a 20-frame sprint and a 40-frame walk are read on one scale.
- `accel`: the root mean square of the joints' change of speed, degrees a second squared (the raw number).
- `kick`: the largest change of a joint's speed between two frames, degrees a frame, and where.
- `held`: the share of (joint, frame) pairs where a joint that moves in the clip stands still (under a twentieth
  of its mean speed): a pose held while the rest of the body goes on.
- the same three for the points an eye follows, in the character's space: the pelvis, the head, the hands
  (`point_harmonic`, `point_accel` in m/s2), and `bob_harmonic` for the pelvis's and the head's height alone.
- `keys`: rotation keys in the file for a moving joint, as a share of the frames, and frames a cycle.

`--bones` prints each joint's own harmonic and largest kick.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import audit_clips  # noqa: E402
from gdsanim.rig import Rig  # noqa: E402

ASSETS = HERE.parents[1]
MODEL = ASSETS / "characters/prototype/form_female.glb"
LIBRARIES = {
    "ual1": ASSETS / "animation/universal/ual1.glb",
    "ual2": ASSETS / "animation/universal/ual2.glb",
    "gds": HERE / "locomotion.glb",
}
PAIRS = [("gds/Walk", "ual1/Walk"), ("gds/Jog", "ual1/Jog_Fwd"), ("gds/Sprint", "ual1/Sprint")]
FPS = 30.0
## The joints read: the trunk, the arms and the legs (no fingers, no twist bones).
JOINTS = (
    ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head"]
    + [f"{part}_{s}" for s in "lr" for part in ("clavicle", "upperarm", "lowerarm", "hand", "thigh", "calf", "foot")]
)
POINTS = ("pelvis", "Head", "hand_l", "hand_r")
## A joint that turns less than this over the whole cycle is not read (degrees): its numbers are noise.
MOVES = 1.0


def _rotvec(q_from: np.ndarray, q_to: np.ndarray) -> np.ndarray:
    """The turn from one quaternion (x, y, z, w) to the next, as a rotation vector in degrees, per row."""
    x1, y1, z1, w1 = (-q_from[:, 0], -q_from[:, 1], -q_from[:, 2], q_from[:, 3])
    x2, y2, z2, w2 = (q_to[:, 0], q_to[:, 1], q_to[:, 2], q_to[:, 3])
    w = w2 * w1 - x2 * x1 - y2 * y1 - z2 * z1
    v = np.stack(
        [
            w2 * x1 + x2 * w1 + y2 * z1 - z2 * y1,
            w2 * y1 - x2 * z1 + y2 * w1 + z2 * x1,
            w2 * z1 + x2 * y1 - y2 * x1 + z2 * w1,
        ],
        axis=1,
    )
    flip = np.where(w < 0.0, -1.0, 1.0)
    w, v = w * flip, v * flip[:, None]
    norm = np.linalg.norm(v, axis=1)
    angle = 2.0 * np.arctan2(norm, w)
    scale = np.where(norm > 1e-12, angle / np.maximum(norm, 1e-12), 2.0)
    return np.degrees(v * scale[:, None])


def _rms(a: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.sum(a * a, axis=-1))))


def _harmonic(speed: np.ndarray, seconds: float) -> tuple:
    """A cyclic speed curve's effective harmonic, with its acceleration's and its jerk's root mean squares."""
    accel = (np.roll(speed, -1, axis=0) - speed) * FPS
    jerk = (np.roll(accel, -1, axis=0) - accel) * FPS
    v, j = _rms(speed), _rms(jerk)
    harmonic = math.sqrt(j * seconds * seconds / (v * 4.0 * math.pi**2)) if v > 1e-9 else 0.0
    return harmonic, _rms(accel), j


def read(path: Path, clip: str, rig: Rig) -> tuple:
    glb = audit_clips.Glb(path)
    anim = next(a for a in glb.json["animations"] if a["name"].removesuffix("_Loop") == clip)
    rotation, translation = audit_clips.sample(glb, anim, rig.body)
    keys = {}
    for channel in anim["channels"]:
        if channel["target"]["path"] == "rotation":
            name = glb.json["nodes"][channel["target"]["node"]].get("name")
            keys[name] = glb.json["accessors"][anim["samplers"][channel["sampler"]]["input"]]["count"]
    return rotation, translation, keys


def measure(path: Path, clip: str, rig: Rig) -> dict:
    rotation, translation, keys = read(path, clip, rig)
    # A loop's last pose is its first: the cycle is every frame but the last.
    count = rotation.shape[0] - 1
    seconds = count / FPS
    world = rig.world(rotation, translation)[:count]
    rotation = rotation[:count]
    bones, total, weighted, accel_sq, held, moving_frames = {}, 0.0, 0.0, 0.0, 0, 0
    kick = (0.0, "", 0)
    key_share = []
    for name in JOINTS:
        if name not in rig.index:
            continue
        q = rotation[:, rig.index[name]]
        speed = _rotvec(q, np.roll(q, -1, axis=0)) * FPS
        travelled = float(np.linalg.norm(speed, axis=1).sum() / FPS)
        if travelled < MOVES:
            continue
        harmonic, accel, _ = _harmonic(speed, seconds)
        change = np.linalg.norm(np.roll(speed, -1, axis=0) - speed, axis=1) / FPS
        worst = int(change.argmax())
        bones[name] = {
            "harmonic": round(harmonic, 2),
            "accel": round(accel, 0),
            "kick": round(float(change[worst]), 1),
            "kick_frame": (worst + 1) % count,
            "turns": round(travelled, 1),
        }
        if change[worst] > kick[0]:
            kick = (float(change[worst]), name, (worst + 1) % count)
        total += travelled
        weighted += travelled * harmonic
        accel_sq += accel * accel
        rate = np.linalg.norm(speed, axis=1)
        held += int((rate < 0.05 * rate.mean()).sum())
        moving_frames += count
        if name in keys:
            key_share.append((keys[name] - 1) / count)
    points, point_weight, point_sum, point_accel = {}, 0.0, 0.0, 0.0
    for name in POINTS:
        place = world[:, rig.index[name], :3, 3]
        speed = (np.roll(place, -1, axis=0) - place) * FPS
        harmonic, accel, _ = _harmonic(speed, seconds)
        path_length = float(np.linalg.norm(speed, axis=1).sum() / FPS)
        points[name] = {"harmonic": round(harmonic, 2), "accel": round(accel, 2), "path_m": round(path_length, 3)}
        point_weight += path_length
        point_sum += path_length * harmonic
        point_accel += accel * accel
    bob = []
    for name in ("pelvis", "Head"):
        height = world[:, rig.index[name], 1, 3]
        speed = ((np.roll(height, -1) - height) * FPS)[:, None]
        bob.append(_harmonic(speed, seconds)[0])
    return {
        "frames": count,
        "harmonic": round(weighted / max(total, 1e-9), 2),
        "accel": round(math.sqrt(accel_sq / max(len(bones), 1)), 0),
        "kick": round(kick[0], 1),
        "kick_at": f"{kick[1]} at frame {kick[2]}",
        "held": round(held / max(moving_frames, 1), 3),
        "point_harmonic": round(point_sum / max(point_weight, 1e-9), 2),
        "point_accel": round(math.sqrt(point_accel / len(POINTS)), 2),
        "bob_harmonic": [round(v, 2) for v in bob],
        "keys": round(float(np.mean(key_share)), 2) if key_share else None,
        "bones": bones,
        "points": points,
    }


def _where(name: str) -> tuple:
    library, clip = name.split("/")
    return LIBRARIES[library], clip


ROWS = [
    ("frames", "Frames a cycle"),
    ("harmonic", "Joints' effective harmonic (1 is one smooth wave a cycle)"),
    ("accel", "Joints' change of speed, RMS (degrees/s2)"),
    ("kick", "Largest change of a joint's speed in a frame (degrees)"),
    ("kick_at", "where"),
    ("held", "Share of a moving joint's frames held still"),
    ("point_harmonic", "Pelvis, head and hands: effective harmonic"),
    ("point_accel", "their acceleration, RMS (m/s2)"),
    ("bob_harmonic", "Height of the pelvis and of the head: effective harmonic"),
    ("keys", "Rotation keys in the file, share of the frames"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pair", action="append", help="<ours.glb>:<Clip>=<library>/<Clip>")
    parser.add_argument("--model", type=Path, default=MODEL)
    parser.add_argument("--json")
    parser.add_argument("--markdown", action="store_true")
    parser.add_argument("--bones", action="store_true")
    args = parser.parse_args()
    rig = Rig(args.model)
    pairs = []
    for pair in args.pair or []:
        ours, theirs = pair.split("=")
        path, clip = ours.rsplit(":", 1)
        pairs.append(((Path(path), clip), _where(theirs), f"{clip} | {theirs}"))
    if not pairs:
        pairs = [(_where(ours), _where(theirs), f"{ours} | {theirs}") for ours, theirs in PAIRS]
    out = {}
    for ours, theirs, label in pairs:
        a, b = measure(*ours, rig), measure(*theirs, rig)
        out[label] = {"ours": a, "library": b}
        if args.markdown:
            print(f"| {label} | ours | the library's |\n| --- | --- | --- |")
            for key, words in ROWS:
                print(f"| {words} | {a[key]} | {b[key]} |")
            print()
        else:
            print(label)
            for key, words in ROWS:
                print(f"  {words:66s} {a[key]!s:>28} {b[key]!s:>28}")
        if args.bones:
            for name in JOINTS:
                x, y = a["bones"].get(name), b["bones"].get(name)
                print(
                    f"    {name:12s}"
                    + "".join(
                        f"  {('h %.2f kick %5.1f @%2d turns %6.1f' % (v['harmonic'], v['kick'], v['kick_frame'], v['turns'])) if v else '-':>40}"
                        for v in (x, y)
                    )
                )
            for name in POINTS:
                print(f"    {name:12s}  {a['points'][name]!s:>52}  {b['points'][name]!s:>52}")
    if args.json:
        Path(args.json).write_text(json.dumps(out, indent=1) + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
