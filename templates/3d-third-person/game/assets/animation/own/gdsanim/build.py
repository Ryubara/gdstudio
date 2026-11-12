"""A clip from description to checked keys, and a file from clips.

A description module (`clips/idle.py`) returns a `Clip` for a rig and a style. `build_clip` solves it on every
frame, runs the overlap pass, takes the root's travel out, reduces the keys and writes the clip's row of
`clips.json`. `build_file` builds a list of clips, runs every check of `checks.py` on every body and returns the
bytes to write, or the failures. Nothing is written by this module: the caller writes only when there is no
failure, so a failed build leaves the last good file alone and says so.
"""

from dataclasses import dataclass, field

import numpy as np

from . import checks, export, maths, mirror, overlap, reduce, weight
from .maths import FPS
from .plan import ContactPlan, unroot
from .rig import SIDES, Rig
from .solve import Solver


@dataclass
class Clip:
    """A clip's description, ready to solve.

    - `name`: the clip's name in the game (`Idle`), without `_Loop`;
    - `frames`: its length in frames; it has `frames + 1` poses, and a loop's last pose is its first;
    - `plan`: its contact plan (footfalls and the root's travel);
    - `spec`: a function of the frame that returns the solver's spec, in the world (before the travel is taken
      out). The plan's feet are filled in for any leg the spec leaves out;
    - `balance`: a function of the frame and its spec that returns the floor point (x, z) the centre of mass is
      over, or None: the pelvis is then moved level until it is (`weight.settle`);
    - `stretch`: with `balance`, the share of its full length the straighter leg is stretched to: the pelvis's
      height is solved from it, so the leg that carries the weight stays as straight as this says. A number, or
      a function of the frame for a body that goes down or comes up;
    - `meet`: for a clip that joins others, the exact poses its ends must be: `{"first": (pose, frames), "last":
      (pose, frames)}`, each pose a solved clip's own (`Built.frames[k]`, in place) and `frames` how many frames
      the difference is let go over. The description already solves to that pose but for what the overlap pass
      left in the joined clip's bones; this takes the rest out, so the ends are the joined poses to the bit;
    - `chains`: the overlap pass's bones, `{bone: (lag, overshoot)}`;
    - `kind`: `stand`, `gait`, `transition` or `action`, which picks the checks that apply;
    - `declared`: the numbers the checks hold the clip to (`lags`, `ranges`, `joins`, `plants`, `distance`,
      `turn`, `speed_limit`, `ceiling`, `facing`, `legs_facing`, `legs_by_landing`), each read by the check of that name, and what `clips.json` says beside
      the plan: `heel_up` (the sides whose heel the description raises itself, so no frame of theirs is flat)
      and `join_names` (`{"first": "Idle", "last": "Crouch_Idle"}`, the shipped clips whose first poses the
      ends are);
    - `bones`: the bones it keys; None is every bone a clip may key;
    - `replaces`: the library clip it replaces (`ual1/Idle`), for `clips.json` and the review sheet;
    - `events`: events beside the plan's footsteps, `[{"frame", "name"}]`.
    """

    name: str
    frames: int
    plan: ContactPlan
    spec: callable
    loop: bool = True
    balance: callable = None
    stretch: float = None
    meet: dict = None
    chains: dict = field(default_factory=dict)
    kind: str = "stand"
    declared: dict = field(default_factory=dict)
    bones: list = None
    replaces: str = ""
    events: list = field(default_factory=list)
    style: str = ""


@dataclass
class Built:
    """A solved clip: its poses, its keys on the reference body and what was kept of them."""

    clip: Clip
    frames: list
    rotation: np.ndarray
    translation: np.ndarray
    kept: dict
    record: dict
    miss: dict

    def played(self, rig: Rig) -> tuple:
        """The clip as the written file plays it, on every frame, on any body that shares the skeleton: the kept
        keys with straight lines between them, the pelvis's place scaled to the body."""
        reference = self.record["_rig"]
        rotation = np.repeat(rig.body.rest_r[None], self.rotation.shape[0], axis=0)
        translation = np.repeat(rig.body.rest_t[None], self.rotation.shape[0], axis=0)
        for bone, kept in self.kept["rotation"].items():
            if bone in rig.index:
                rotation[:, rig.index[bone]] = reduce.played(self.rotation[:, reference.index[bone]], kept, True)
        for bone, kept in self.kept["place"].items():
            if bone in rig.index:
                place = reduce.played(self.translation[:, reference.index[bone]], kept, False)
                translation[:, rig.index[bone]] = place / reference.motion_scale * rig.motion_scale
        return rotation, translation


def keyed_bones(rig: Rig) -> list:
    """Every bone a clip may key: not the root (clips are in place), not a `_leaf`, a twist bone or a socket."""
    out = []
    for name in rig.bones:
        if name == rig.parent["pelvis"] or "_leaf" in name or "twist" in name or name.startswith("socket_"):
            continue
        out.append(name)
    return out


def solve_frames(rig: Rig, solver: Solver, clip: Clip) -> tuple:
    """The clip's poses in the world, one a frame, and the furthest any target was out of reach."""
    frames, miss = [], {}
    count = clip.frames if clip.loop else clip.frames + 1
    for f in range(count):
        spec = clip.spec(f)
        legs = spec.setdefault("leg", {})
        for s, _ in SIDES:
            if s not in legs:
                legs[s] = clip.plan.foot(rig, s, f)
        if clip.balance is not None:
            stretch = clip.stretch(f) if callable(clip.stretch) else clip.stretch
            pose = weight.settle(solver, spec, clip.balance(f, spec), stretch)
        else:
            pose = solver.solve(spec)
        for key, value in pose["miss"].items():
            miss[key] = max(miss.get(key, 0.0), float(value))
        frames.append(pose)
    return frames, miss


def build_clip(rig: Rig, solver: Solver, clip: Clip) -> Built:
    frames, miss = solve_frames(rig, solver, clip)
    if clip.loop:
        frames.append({**frames[0], "local": dict(frames[0]["local"])})
    overlap.apply(rig, frames, clip.chains, clip.loop)
    for f, pose in enumerate(frames):
        place, yaw = clip.plan.travel.at(float(f))
        unroot(rig, pose, place, yaw)
    if clip.loop:
        frames[-1] = frames[0]
    if clip.meet:
        meet_ends(frames, clip.meet)
    return finish(rig, clip, frames, miss)


def meet_ends(frames: list, meet: dict) -> None:
    """Make a clip's first and last pose the poses it joins (`Clip.meet`), in place. The difference between the
    solved end and the joined pose, bone by bone in the parent's space, is added whole at the end and let go
    over the frames beside it, so the motion between keeps its shape."""
    last = len(frames) - 1
    for end, at, step in (("first", 0, 1), ("last", last, -1)):
        if end not in meet:
            continue
        target, over = meet[end]
        solved = {name: m.copy() for name, m in frames[at]["local"].items()}
        off = np.asarray(target["pelvis"], dtype=float) - frames[at]["pelvis"]
        turns = {
            name: maths.rotation_vector(solved[name].T @ target["local"][name])
            for name in solved
            if name in target["local"]
        }
        for k in range(min(int(over), last) + 1):
            pose = frames[at + step * k]
            share = 1.0 - maths.smoother(k / max(float(over), 1.0)) if k < over else 0.0
            if k == 0:
                share = 1.0
            if share <= 0.0:
                continue
            pose["pelvis"] = pose["pelvis"] + share * off
            for name, turn in turns.items():
                pose["local"][name] = pose["local"][name] @ maths.from_rotation_vector(turn * share)


def finish(rig: Rig, clip: Clip, frames: list, miss: dict) -> Built:
    """Poses to keys: arrays, key reduction and the clip's record."""
    rotation, translation = rig.arrays(frames)
    for i in range(rotation.shape[1]):
        rotation[:, i] = reduce.continuous(rotation[:, i])
    if clip.loop:
        assert np.all(np.sum(rotation[-1] * rotation[0], axis=1) > 0), f"{clip.name}: a bone winds round the loop"
        rotation[-1], translation[-1] = rotation[0], translation[0]
    rotation, translation = rotation.astype(np.float32).astype(float), translation.astype(np.float32).astype(float)
    tracks = [n for n in (clip.bones or keyed_bones(rig)) if not (n.startswith("ik_") and "places" not in frames[0])]
    places = ["pelvis"] + [n for n in tracks if n.startswith("ik_")]
    planted = {}
    for s, _ in SIDES:
        mask = np.array([clip.plan.planted(s, f) for f in range(len(frames))])
        planted[f"foot_{s}"] = planted[f"ball_{s}"] = mask
    kept = reduce.reduce_clip(rig, rotation, translation, tracks, places, planted)
    record = _record(rig, clip, kept)
    return Built(clip, frames, rotation, translation, kept, record, miss)


def _record(rig: Rig, clip: Clip, kept: dict) -> dict:
    plan, travel = clip.plan, clip.plan.travel
    forward = [travel.at(float(f))[0][2] for f in range(clip.frames + 1)]
    left = [travel.at(float(f))[0][0] for f in range(clip.frames + 1)]
    turn = [travel.at(float(f))[1] for f in range(clip.frames + 1)]
    distance = float(sum(np.hypot(np.diff(forward), np.diff(left))))
    curve = reduce.keep_place(np.column_stack([forward, left, np.radians(turn)]), 1e-4)
    return {
        "_rig": rig,
        "loop": clip.loop,
        "frames": clip.frames,
        "seconds": round(clip.frames / FPS, 4),
        "kind": clip.kind,
        "style": clip.style,
        "replaces": clip.replaces,
        "speed": round(distance / (clip.frames / FPS), 4),
        "travel": [[int(f), round(forward[f], 4), round(left[f], 4)] for f in curve],
        "turn": [[int(f), round(turn[f], 3)] for f in curve],
        "contacts": {s: plan.contacts(s) for s, _ in SIDES},
        "flat": {s: plan.flat(s, s in clip.declared.get("heel_up", ())) for s, _ in SIDES},
        "joins": dict(clip.declared.get("join_names", {})),
        "start_foot": plan.first_foot(0.0),
        "end_foot": plan.first_foot(float(clip.frames)),
        "events": plan.events() + list(clip.events),
        "bones": sorted(kept["rotation"]),
        "reduced_to_deg": kept["tolerance"],
        # What a description says of its clip beside the plan (`declared["says"]`): the way a gait travels, the
        # gait it is in step with, what a pose is a difference from.
        **dict(clip.declared.get("says", {})),
    }


def mirrored(rig: Rig, built: Built, name: str, half_cycle: bool = False) -> Built:
    """The clip for the other side, under `name`: a left-and-right pair is one authored clip and this. With
    `half_cycle` a loop is also started half a cycle later, so a mirrored gait keeps the left foot down at 0."""
    frames = mirror.mirror_frames(rig, built.frames)
    clip = built.clip
    if half_cycle:
        frames = mirror.shift_loop(frames, clip.frames // 2)
    plan = clip.plan
    swap = {"l": "r", "r": "l"}
    falls = []
    for fall in plan.footfalls:
        moved = dict(fall.__dict__, side=swap[fall.side], place=(-fall.place[0], fall.place[1]), yaw=-fall.yaw)
        falls.append(type(fall)(**moved))
    twin_plan = type(plan)(plan.frames, falls, plan.travel, plan.loop, plan.clearance, plan.toe_reach)
    twin = Clip(**{**clip.__dict__, "name": name, "plan": twin_plan})
    return finish(rig, twin, frames, dict(built.miss))


def as_export(built: Built) -> dict:
    return {
        "name": built.clip.name,
        "loop": built.clip.loop,
        "rotation": built.rotation,
        "translation": built.translation,
        "kept": built.kept,
    }


def build_file(rig: Rig, builts: list, bodies: list, frozen: list) -> dict:
    """Check clips and make their file. Returns `{"glb": bytes, "clips": the clips.json content, "report":
    numbers per clip and body, "failures": [...]}`; the caller writes nothing when there is a failure."""
    failures, report = [], {}
    names = [built.clip.name for built in builts]
    if names != list(frozen):
        failures.append(f"the build made {names}, and its frozen list is {list(frozen)}")
    for built in builts:
        numbers, failed = checks.run(built, bodies)
        report[built.clip.name] = numbers
        failures += [f"{built.clip.name}: {line}" for line in failed]
    glb = export.glb_bytes(rig, [as_export(built) for built in builts])
    if glb != export.glb_bytes(rig, [as_export(built) for built in builts]):
        failures.append("writing the same clips twice gave different bytes")
    clips = {
        "fps": FPS,
        "rig": rig.path.name,
        "reference_hips": round(rig.hips, 4),
        "frozen": list(frozen),
        "clips": {
            built.clip.name: {k: v for k, v in built.record.items() if not k.startswith("_")} for built in builts
        },
    }
    return {"glb": glb, "clips": clips, "report": report, "failures": failures}
