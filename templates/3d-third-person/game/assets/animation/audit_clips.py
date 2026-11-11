"""Measure animation clips the way a reviewer would judge them: contacts, timing, weight, loops, overlap, cost.

The numbers behind the audit of the library clips the template plays (kit #1150,
`docs/tools/blender/own-animation.md#audit`), and the same numbers for a clip of our own, so a replacement is
compared with what it replaces on one scale.

It reads the glb files directly (the glTF JSON and its binary chunk, numpy only), so it runs anywhere and needs no
frame change in Blender:

    uv run --with numpy python audit_clips.py --clips <clips.glb> [--model <mannequin.glb>]
        [--clip <name> ...] [--speed <clip>=<m/s> ...] [--join <from>=<to> ...] [--json <file>] [--markdown]

or with the pinned Blender's own Python (`blender -b --factory-startup -P audit_clips.py -- ...`).

A clip plays on the model as Godot plays it: each bone's rotation from the clip, the pelvis's place from the clip,
every other bone at the model's own length. Without `--model` the body is the one inside the clips' file (the male
mannequin in the Universal Animation Library's files).

What it measures, per clip (the axes are glTF's: Y up, the character faces +Z):

- `frames`, `seconds`, `loop`: the length at the file's key rate and whether the name ends in `_Loop`.
- `kb`, `moving_bones`, `finger_bones`, `keys_kept`: the clip's bytes in the file, the bones whose rotation changes
  by more than half a degree, how many of those are fingers, and the share of rotation keys a linear key reducer
  keeps at half a degree of error (what the clip could weigh).
- `seam_mm`, `seam_step`: for a loop, how far the main joints are on the last frame from the first, and the change
  of speed across the seam as a share of the clip's own largest change of speed (1 or less: the seam is no worse
  than the rest of the cycle).
- `floor_mm`: the lowest vertex of either foot on any frame against the floor (negative is under it).
- `speed`, `speed_spread`, `slide_mm`: the planted sole's mean speed against the body (the ground speed the clip
  covers: contact travel over contact time), its 10th to 90th percentile, and the furthest a planted sole wanders,
  in one contact, on a floor that moves at that one speed. A planted foot is one whose lowest vertex is within a
  fifth of its own lift of the floor (or of its own lowest, when that is higher), and within 25 mm.
- `step_frames`, `cadence`, `duty`, `flight`: frames per step, steps a minute, the share of the cycle a foot is
  planted, and the share with no foot planted (negative: both planted, a walk's double support).
- `pelvis_bob_mm`, `pelvis_sway_mm`, `pelvis_yaw`, `pelvis_roll`, `chest_yaw`, `counter`, `lean`: how far the
  pelvis goes up and down and side to side, how far it turns and tips, how far the chest turns, the correlation of
  the shoulders' turn with the hips' (negative is the counter-rotation of a real gait) and the trunk's mean
  forward lean.
- `lag_forearm`, `lag_hand`, `lag_chest`, `lag_head`: how many frames a part trails the part it hangs from (its
  swing against its parent's, by cross-correlation). Zero everywhere is a body that moves as one piece.
- `mirror`: for a gait, the difference in degrees between the left thigh's swing and the right's half a cycle
  later (0 is a cycle mirrored exactly).
- `arm_leg`: the correlation of the left arm's swing with the right leg's (near 1 in a gait).
- `peak_frame`, `low_frame`: for a clip that plays once, the frame the pelvis moves fastest and the frame it is
  lowest (where the weight lands).
- `--join a=b`: how far the main joints of `a`'s last frame are from `b`'s first, in mm (what a cross-fade hides).
- `--speed clip=v`: the game's speed for the clip; `rate` is what the clip must be played at for its feet to keep
  that speed, and `skate` the share of the ground the feet miss at the clip's own pace.
"""

import argparse
import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

## The key rate both libraries and our own clips are sampled at.
FPS = 30.0
## The joints a pose is compared on (a seam, a join).
MAIN = [
    "pelvis", "spine_03", "Head", "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r",
    "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r",
]  # fmt: skip
FOOT_BONES = {
    "l": ("foot_l", "ball_l", "ball_leaf_l"),
    "r": ("foot_r", "ball_r", "ball_leaf_r"),
}
FINGERS = ("index_", "middle_", "ring_", "pinky_", "thumb_")
## The most a planted sole's lowest vertex is above the floor (m): a fifth of the foot's lift, up to this.
PLANT_BAND = 0.025
## A rotation that changes less than this is a bone that does not move (degrees).
STILL_DEG = 0.5
## The error a reduced rotation track may have (degrees).
REDUCE_DEG = 0.5
_TYPES = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
_SIZES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Glb:
    """A glb's JSON and binary chunk."""

    def __init__(self, path: Path):
        data = path.read_bytes()
        length = struct.unpack_from("<I", data, 12)[0]
        self.json = json.loads(data[20 : 20 + length])
        self.bin = data[20 + length + 8 :]
        self.path = path

    def accessor(self, index: int) -> np.ndarray:
        acc = self.json["accessors"][index]
        view = self.json["bufferViews"][acc["bufferView"]]
        size = _SIZES[acc["type"]]
        dtype = np.dtype(_TYPES[acc["componentType"]])
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", 0)
        if stride and stride != dtype.itemsize * size:
            rows = [np.frombuffer(self.bin, dtype, size, start + stride * row) for row in range(acc["count"])]
            out = np.array(rows)
        else:
            out = np.frombuffer(self.bin, dtype, acc["count"] * size, start).reshape(acc["count"], size)
        return out.astype(np.float64) if dtype.kind == "f" else out

    def accessor_bytes(self, index: int) -> int:
        acc = self.json["accessors"][index]
        return acc["count"] * _SIZES[acc["type"]] * np.dtype(_TYPES[acc["componentType"]]).itemsize


def quat_matrix(q: np.ndarray) -> np.ndarray:
    """Rotation matrices of quaternions (x, y, z, w), any leading shape."""
    q = q / np.linalg.norm(q, axis=-1, keepdims=True)
    x, y, z, w = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    out = np.empty(q.shape[:-1] + (3, 3))
    out[..., 0, 0] = 1 - 2 * (y * y + z * z)
    out[..., 0, 1] = 2 * (x * y - z * w)
    out[..., 0, 2] = 2 * (x * z + y * w)
    out[..., 1, 0] = 2 * (x * y + z * w)
    out[..., 1, 1] = 1 - 2 * (x * x + z * z)
    out[..., 1, 2] = 2 * (y * z - x * w)
    out[..., 2, 0] = 2 * (x * z - y * w)
    out[..., 2, 1] = 2 * (y * z + x * w)
    out[..., 2, 2] = 1 - 2 * (x * x + y * y)
    return out


class Body:
    """The skeleton and the feet's skin of a model file."""

    def __init__(self, glb: Glb):
        nodes = glb.json["nodes"]
        self.names = [node.get("name", str(i)) for i, node in enumerate(nodes)]
        self.index = {name: i for i, name in enumerate(self.names)}
        self.parent = [-1] * len(nodes)
        for i, node in enumerate(nodes):
            for child in node.get("children", []):
                self.parent[child] = i
        self.order = []
        todo = [i for i, parent in enumerate(self.parent) if parent < 0]
        while todo:
            i = todo.pop()
            self.order.append(i)
            todo.extend(nodes[i].get("children", []))
        self.rest_t = np.array([node.get("translation", [0, 0, 0]) for node in nodes], dtype=float)
        self.rest_r = np.array([node.get("rotation", [0, 0, 0, 1]) for node in nodes], dtype=float)
        self.rest_s = np.array([node.get("scale", [1, 1, 1]) for node in nodes], dtype=float)
        skin = glb.json["skins"][0]
        self.joints = skin["joints"]
        self.inverse_bind = glb.accessor(skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        # The feet's vertices, by each vertex's heaviest bone (empty for a file with a stand-in mesh).
        self.foot_skin = {}
        positions, joints, weights = [], [], []
        for mesh in glb.json.get("meshes", []):
            for prim in mesh["primitives"]:
                attrs = prim["attributes"]
                if "JOINTS_0" not in attrs:
                    continue
                positions.append(glb.accessor(attrs["POSITION"]))
                joints.append(glb.accessor(attrs["JOINTS_0"]).astype(int))
                weights.append(glb.accessor(attrs["WEIGHTS_0"]).astype(float))
        if positions and sum(len(p) for p in positions) > 100:
            position, joint, weight = (
                np.concatenate(positions),
                np.concatenate(joints),
                np.concatenate(weights),
            )
            weight = weight / np.maximum(weight.sum(axis=1, keepdims=True), 1e-9)
            heaviest = joint[np.arange(len(joint)), weight.argmax(axis=1)]
            for side, bones in FOOT_BONES.items():
                slots = [self.joints.index(self.index[b]) for b in bones if b in self.index]
                pick = np.isin(heaviest, slots)
                self.foot_skin[side] = (position[pick], joint[pick], weight[pick])

    def world(self, rotation: np.ndarray, translation: np.ndarray) -> np.ndarray:
        """World matrices [frame, node, 4, 4] from local rotations and translations [frame, node, ...]."""
        frames = rotation.shape[0]
        local = np.zeros((frames, len(self.names), 4, 4))
        local[..., :3, :3] = quat_matrix(rotation) * self.rest_s[None, :, None, :]
        local[..., :3, 3] = translation
        local[..., 3, 3] = 1.0
        world = np.empty_like(local)
        for i in self.order:
            parent = self.parent[i]
            world[:, i] = local[:, i] if parent < 0 else world[:, parent] @ local[:, i]
        return world

    def feet(self, world: np.ndarray) -> dict:
        """The feet's skinned vertices [frame, vertex, 3], by side."""
        out = {}
        skin = world[:, self.joints] @ self.inverse_bind[None]
        for side, (position, joint, weight) in self.foot_skin.items():
            rest = np.concatenate([position, np.ones((len(position), 1))], axis=1)
            moved = np.zeros((world.shape[0], len(position), 3))
            for slot in range(joint.shape[1]):
                mats = skin[:, joint[:, slot]]
                moved += weight[None, :, slot, None] * np.einsum("fvij,vj->fvi", mats, rest)[..., :3]
            out[side] = moved
        return out


def sample(glb: Glb, anim: dict, body: Body) -> tuple:
    """A clip's local rotations and translations on `body`, one row a frame at `FPS`."""
    nodes = glb.json["nodes"]
    end = max(glb.json["accessors"][s["input"]]["max"][0] for s in anim["samplers"])
    count = int(round(end * FPS)) + 1
    times = np.arange(count) / FPS
    rotation = np.repeat(body.rest_r[None], count, axis=0)
    translation = np.repeat(body.rest_t[None], count, axis=0)
    for channel in anim["channels"]:
        name = nodes[channel["target"]["node"]].get("name")
        path = channel["target"]["path"]
        if name not in body.index or path == "scale":
            continue
        if path == "translation" and name != "pelvis":
            continue
        sampler = anim["samplers"][channel["sampler"]]
        keys = glb.accessor(sampler["input"])[:, 0]
        values = glb.accessor(sampler["output"])
        if path == "rotation":
            flip = np.sign(np.sum(values[1:] * values[:-1], axis=1))
            values = values * np.concatenate([[1.0], np.cumprod(np.where(flip == 0, 1.0, flip))])[:, None]
        row = np.stack(
            [np.interp(times, keys, values[:, k]) for k in range(values.shape[1])],
            axis=1,
        )
        if path == "rotation":
            rotation[:, body.index[name]] = row / np.linalg.norm(row, axis=1, keepdims=True)
        else:
            translation[:, body.index[name]] = row
    return rotation, translation


def clip_bytes(glb: Glb, anim: dict) -> int:
    seen = set()
    for sampler in anim["samplers"]:
        seen.add(sampler["input"])
        seen.add(sampler["output"])
    return sum(glb.accessor_bytes(index) for index in seen)


def angle_between(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Degrees between quaternions."""
    dot = np.clip(np.abs(np.sum(a * b, axis=-1)), 0.0, 1.0)
    return np.degrees(2.0 * np.arccos(dot))


def keys_kept(track: np.ndarray) -> int:
    """How many keys of a rotation track a greedy linear reducer keeps at `REDUCE_DEG`."""
    count = len(track)
    kept, start = 1, 0
    while start < count - 1:
        end = start + 1
        while end + 1 < count:
            span = np.arange(start + 1, end + 1)
            share = ((span - start) / (end + 1 - start))[:, None]
            a, b = track[start], track[end + 1]
            if np.dot(a, b) < 0:
                b = -b
            guess = a[None] * (1 - share) + b[None] * share
            guess /= np.linalg.norm(guess, axis=1, keepdims=True)
            if angle_between(guess, track[span]).max() > REDUCE_DEG:
                break
            end += 1
        kept += 1
        start = end
    return kept


def lag_frames(parent: np.ndarray, child: np.ndarray, loop: bool) -> float | None:
    """Frames `child` trails `parent` (positive), by the peak of their cross-correlation."""
    a, b = parent - parent.mean(), child - child.mean()
    if np.ptp(a) < math.radians(2.0) or np.ptp(b) < math.radians(2.0) or len(a) < 8:
        return None
    reach = max(2, len(a) // 4)
    shifts = list(range(-reach, reach + 1))
    scores = []
    for shift in shifts:
        if loop:
            moved = np.roll(b, -shift)
            scores.append(float(np.dot(a, moved)))
        elif shift >= 0:
            scores.append(float(np.dot(a[: len(a) - shift], b[shift:])) * len(a) / (len(a) - shift))
        else:
            scores.append(float(np.dot(a[-shift:], b[: len(b) + shift])) * len(a) / (len(a) + shift))
    scores = np.abs(np.array(scores))
    best = int(scores.argmax())
    if scores[best] < 0.6 * float(np.linalg.norm(a) * np.linalg.norm(b)):
        return None
    lag = float(shifts[best])
    if 0 < best < len(shifts) - 1:
        left, mid, right = scores[best - 1], scores[best], scores[best + 1]
        bend = left - 2 * mid + right
        if abs(bend) > 1e-12:
            lag += 0.5 * (left - right) / bend
    return round(lag, 1)


def swing(world: np.ndarray, body: Body, top: str, bottom: str) -> np.ndarray:
    """A segment's swing forward of straight down, radians."""
    way = world[:, body.index[bottom], :3, 3] - world[:, body.index[top], :3, 3]
    return np.unwrap(np.arctan2(way[:, 2], -way[:, 1]))


def turn_of(world: np.ndarray, rest: np.ndarray, body: Body, bone: str) -> tuple:
    """A bone's yaw, forward pitch and roll from its rest, radians."""
    i = body.index[bone]
    turn = world[:, i, :3, :3] @ np.linalg.inv(rest[0, i, :3, :3])
    ahead, up = turn[:, :, 2], turn[:, :, 1]
    yaw = np.unwrap(np.arctan2(ahead[:, 0], ahead[:, 2]))
    pitch = np.arcsin(np.clip(-ahead[:, 1], -1, 1))
    side = np.cross(np.array([0.0, 1.0, 0.0])[None], ahead)
    side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-9)
    over = np.cross(ahead, side)
    roll = np.arctan2(np.sum(up * side, axis=1), np.sum(up * over, axis=1))
    return yaw, pitch, roll


def line_turn(world: np.ndarray, body: Body, left: str, right: str) -> tuple:
    """The yaw and the tilt of the line between two joints (the hips, the shoulders), radians."""
    line = world[:, body.index[left], :3, 3] - world[:, body.index[right], :3, 3]
    yaw = np.unwrap(np.arctan2(-line[:, 2], line[:, 0]))
    return yaw, np.arctan2(line[:, 1], np.hypot(line[:, 0], line[:, 2]))


def correlation(a: np.ndarray, b: np.ndarray) -> float | None:
    if np.ptp(a) < math.radians(1.0) or np.ptp(b) < math.radians(1.0):
        return None
    return round(float(np.corrcoef(a, b)[0, 1]), 2)


def measure_feet(feet: dict, loop: bool, out: dict) -> None:
    """The contacts: the floor, the planted sole's speed, the slide, the timing of the steps."""
    if not feet:
        return
    frames = next(iter(feet.values())).shape[0]
    planted, speeds, slides, lowest = {}, [], [], []
    for side, verts in feet.items():
        height = verts[:, :, 1].min(axis=1)
        lowest.append(height.min())
        lift = np.ptp(height)
        planted[side] = height <= max(height.min(), 0.0) + min(max(0.2 * lift, 0.005), PLANT_BAND)
        # The contact patch: the vertices within a centimetre of the lowest, followed to the next frame.
        velocity = np.zeros((frames, 2))
        for frame in range(frames - 1):
            patch = verts[frame, :, 1] <= height[frame] + 0.01
            step = verts[frame + 1, patch] - verts[frame, patch]
            velocity[frame] = step[:, [0, 2]].mean(axis=0) * FPS
        velocity[-1] = velocity[0] if loop else velocity[-2]
        both = planted[side] & np.roll(planted[side], -1) if loop else planted[side]
        if both.any():
            speeds.append(velocity[both])
        runs, start = [], None
        for frame in range(frames):
            if both[frame] and start is None:
                start = frame
            if not both[frame] and start is not None:
                runs.append((start, frame))
                start = None
        if start is not None:
            runs.append((start, frames))
        planted[side + "_runs"] = runs
        planted[side + "_velocity"] = velocity
    out["floor_mm"] = round(float(min(lowest)) * 1000, 1)
    if not speeds:
        return
    stacked = np.concatenate(speeds)
    mean = stacked.mean(axis=0)
    along = -stacked[:, 1]
    out["speed"] = round(float(np.hypot(*mean)), 2)
    out["speed_spread"] = [
        round(float(np.percentile(along, 10)), 2),
        round(float(np.percentile(along, 90)), 2),
    ]
    for side in feet:
        for start, end in planted[side + "_runs"]:
            drift = np.cumsum(planted[side + "_velocity"][start:end] - mean[None], axis=0) / FPS
            drift = np.concatenate([np.zeros((1, 2)), drift])
            slides.append(float(np.linalg.norm(np.ptp(drift, axis=0))))
    out["slide_mm"] = round(float(max(slides)) * 1000, 1)
    if loop and "l" in feet and "r" in feet:
        cycle = frames - 1
        left, right = planted["l"][:cycle], planted["r"][:cycle]
        out["duty"] = round(float((left.mean() + right.mean()) / 2), 2)
        flight = float((~left & ~right).mean())
        double = float((left & right).mean())
        out["flight"] = round(flight if flight > 0 else -double, 2)


def measure_clip(glb: Glb, anim: dict, body: Body) -> dict:
    name = anim["name"]
    loop = name.endswith("_Loop")
    rotation, translation = sample(glb, anim, body)
    frames = rotation.shape[0]
    world = body.world(rotation, translation)
    rest = body.world(body.rest_r[None], body.rest_t[None])
    out = {
        "clip": name.removesuffix("_Loop"),
        "frames": frames - 1,
        "seconds": round((frames - 1) / FPS, 2),
    }
    out["loop"] = loop
    out["kb"] = round(clip_bytes(glb, anim) / 1024, 1)
    bones = [n for n in body.names if n in body.index and body.index[n] in body.joints]
    moving, kept, total = [], 0, 0
    for bone in bones:
        track = rotation[:, body.index[bone]]
        if angle_between(track, track[:1]).max() > STILL_DEG:
            moving.append(bone)
            kept += keys_kept(track)
            total += frames
    out["moving_bones"] = len(moving)
    out["finger_bones"] = sum(1 for bone in moving if bone.startswith(FINGERS))
    out["keys_kept"] = round(kept / total, 2) if total else 0.0
    main = [body.index[b] for b in MAIN]
    place = world[:, main][:, :, :3, 3]
    out["first_pose"], out["last_pose"] = place[0], place[-1]
    if loop:
        out["seam_mm"] = round(float(np.linalg.norm(place[-1] - place[0], axis=1).max()) * 1000, 1)
        cycle = place[:-1]
        speed = np.roll(cycle, -1, axis=0) - cycle
        change = np.linalg.norm(speed - np.roll(speed, 1, axis=0), axis=2).max(axis=1)
        inner = np.delete(change, [0])
        out["seam_step"] = round(float(change[0] / max(inner.max(), 1e-9)), 2)
    measure_feet(body.feet(world), loop, out)

    pelvis = world[:, body.index["pelvis"], :3, 3]
    out["pelvis_bob_mm"] = round(float(np.ptp(pelvis[:, 1])) * 1000, 1)
    out["pelvis_sway_mm"] = round(float(np.ptp(pelvis[:, 0])) * 1000, 1)
    out["pelvis_travel_mm"] = round(float(np.ptp(pelvis[:, 2])) * 1000, 1)
    yaw, roll = line_turn(world, body, "thigh_l", "thigh_r")
    chest_yaw, _ = line_turn(world, body, "clavicle_l", "clavicle_r")
    head_yaw, head_pitch, _ = turn_of(world, rest, body, "Head")
    trunk = world[:, body.index["neck_01"], :3, 3] - pelvis
    pitch = np.arctan2(trunk[:, 2], trunk[:, 1])
    chest = world[:, body.index["neck_01"], :3, 3] - world[:, body.index["spine_02"], :3, 3]
    chest_pitch = np.arctan2(chest[:, 2], chest[:, 1])
    out["pelvis_yaw"] = round(float(np.degrees(np.ptp(yaw))), 1)
    out["pelvis_roll"] = round(float(np.degrees(np.ptp(roll))), 1)
    out["chest_yaw"] = round(float(np.degrees(np.ptp(chest_yaw))), 1)
    out["head_yaw"] = round(float(np.degrees(np.ptp(head_yaw))), 1)
    out["counter"] = correlation(yaw, chest_yaw)
    out["lean"] = round(float(np.degrees(pitch.mean())), 1)
    cyc = slice(0, frames - 1) if loop else slice(0, frames)
    thigh_l = swing(world, body, "thigh_l", "calf_l")[cyc]
    thigh_r = swing(world, body, "thigh_r", "calf_r")[cyc]
    lags = {}
    for side in ("l", "r"):
        upper = swing(world, body, f"upperarm_{side}", f"lowerarm_{side}")[cyc]
        fore = swing(world, body, f"lowerarm_{side}", f"hand_{side}")[cyc]
        hand = swing(world, body, f"hand_{side}", f"middle_01_{side}")[cyc]
        lags.setdefault("lag_forearm", []).append(lag_frames(upper, fore, loop))
        lags.setdefault("lag_hand", []).append(lag_frames(fore, hand, loop))
    lags["lag_chest"] = [lag_frames(yaw[cyc], chest_yaw[cyc], loop)]
    lags["lag_head"] = [lag_frames(chest_pitch[cyc], head_pitch[cyc], loop)]
    for key, values in lags.items():
        values = [v for v in values if v is not None]
        out[key] = round(float(np.mean(values)), 1) if values else None
    arm_l = swing(world, body, "upperarm_l", "lowerarm_l")[cyc]
    out["arm_leg"] = correlation(arm_l, thigh_r)
    out["thigh_swing"] = round(float(np.degrees(np.ptp(thigh_l))), 1)
    out["arm_swing"] = round(float(np.degrees(np.ptp(arm_l))), 1)
    if loop and np.ptp(thigh_l) > math.radians(10.0):
        # The steps: the left thigh's swing has one period a stride.
        cycle = frames - 1
        spectrum = np.abs(np.fft.rfft(thigh_l - thigh_l.mean()))
        strides = max(1, int(spectrum[1:].argmax()) + 1)
        out["step_frames"] = round(cycle / strides / 2, 1)
        out["cadence"] = round(60.0 * FPS / (cycle / strides / 2))
        half = int(round(cycle / strides / 2))
        out["mirror"] = round(float(np.degrees(np.abs(thigh_l - np.roll(thigh_r, -half)).mean())), 1)
    if not loop:
        speed = np.linalg.norm(np.diff(pelvis, axis=0), axis=1)
        out["peak_frame"] = int(speed.argmax()) if speed.max() > 1e-4 else None
        out["low_frame"] = int(pelvis[:, 1].argmin())
        out["pelvis_drop_mm"] = round(float(pelvis[0, 1] - pelvis[:, 1].min()) * 1000, 1)
    return out


COLUMNS = [
    "clip", "frames", "seconds", "kb", "moving_bones", "finger_bones", "keys_kept", "seam_mm", "seam_step",
    "floor_mm", "speed", "speed_spread", "slide_mm", "rate", "skate", "step_frames", "cadence", "duty", "flight",
    "pelvis_bob_mm", "pelvis_sway_mm", "pelvis_yaw", "pelvis_roll", "chest_yaw", "head_yaw", "counter", "lean",
    "thigh_swing", "arm_swing", "arm_leg", "mirror", "lag_forearm", "lag_hand", "lag_chest", "lag_head",
    "peak_frame", "low_frame", "pelvis_drop_mm",
]  # fmt: skip


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--clips", type=Path, action="append", required=True)
    parser.add_argument("--model", type=Path)
    parser.add_argument("--clip", action="append", default=[])
    parser.add_argument("--speed", action="append", default=[])
    parser.add_argument("--join", action="append", default=[])
    parser.add_argument("--json", type=Path)
    parser.add_argument("--markdown", action="store_true")
    args = parser.parse_args(argv)

    rows = {}
    for path in args.clips:
        glb = Glb(path)
        body = Body(Glb(args.model) if args.model else glb)
        for anim in glb.json.get("animations", []):
            short = anim["name"].removesuffix("_Loop")
            if args.clip and short not in args.clip:
                continue
            rows[short] = measure_clip(glb, anim, body)
    missing = [name for name in args.clip if name not in rows]
    if missing:
        print(f"no clip called {', '.join(missing)}", file=sys.stderr)
        return 1
    for pair in args.speed:
        name, value = pair.split("=")
        row = rows[name]
        if row.get("speed"):
            row["rate"] = round(float(value) / row["speed"], 2)
            row["skate"] = round(1.0 - row["speed"] / float(value), 2)
    joins = []
    for pair in args.join:
        first, second = pair.split("=")
        gap = np.linalg.norm(rows[first]["last_pose"] - rows[second]["first_pose"], axis=1)
        joins.append(
            {
                "from": first,
                "to": second,
                "gap_mm": round(float(gap.max()) * 1000),
                "at": MAIN[int(gap.argmax())],
            }
        )
    for row in rows.values():
        del row["first_pose"], row["last_pose"]
    order = args.clip or list(rows)
    if args.json:
        args.json.write_text(json.dumps({"clips": [rows[n] for n in order], "joins": joins}, indent=1) + "\n")
    if args.markdown:
        used = [c for c in COLUMNS if any(rows[n].get(c) is not None for n in order)]
        print("| " + " | ".join(used) + " |")
        print("|" + " --- |" * len(used))
        for name in order:
            print("| " + " | ".join("" if rows[name].get(c) is None else str(rows[name][c]) for c in used) + " |")
        for join in joins:
            print(f"join {join['from']} -> {join['to']}: {join['gap_mm']} mm at {join['at']}")
    else:
        for name in order:
            print(json.dumps(rows[name]))
        for join in joins:
            print(json.dumps(join))
    return 0


if __name__ == "__main__":
    sys.exit(main())
