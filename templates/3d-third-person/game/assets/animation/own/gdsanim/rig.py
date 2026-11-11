"""A body read from a glb: its rest skeleton, its skin, where its soles are and what its parts weigh.

A clip is solved on one body (the reference, whose `pelvis` rests 0.9166 m up) and plays on every body that shares
the skeleton's names and rest orientations, as Godot plays it: each bone's rotation in its parent from the clip, the
pelvis's place from the clip, every other bone at the body's own length. So every check that reads a mesh runs on
each body with `Rig.world()` of that body.

When a `rig_<body>.json` lies beside the model (the prototype mannequins write one, kit #1149) its bones are checked
against the glb's and its `motion_scale`, and its `sole` and `masses` when it has them, are used; without the file
the sole points are read off the foot's skin and the masses are the table below.
"""

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import audit_clips  # noqa: E402  (the glb reader and the measures, `assets/animation/audit_clips.py`)

from . import maths  # noqa: E402

SIDES = (("l", 1.0), ("r", -1.0))
TRUNK = ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head")
FINGERS = ("thumb", "index", "middle", "ring", "pinky")
## The height of the reference body's `pelvis` at rest (m): position keys are in this body's metres.
REFERENCE_HIPS = 0.9166

## Each segment's share of the body's mass and where its centre lies from its near joint to its far one (Winter,
## "Biomechanics and Motor Control of Human Movement", the table of Dempster's segment data). A segment is named by
## the bone at its near joint; the trunk's three parts are the pelvis, the abdomen and the thorax.
MASSES = {
    "pelvis": (0.142, "pelvis", "spine_01", 0.5),
    "abdomen": (0.139, "spine_01", "spine_03", 0.5),
    "thorax": (0.216, "spine_03", "neck_01", 0.5),
    "head": (0.081, "neck_01", "Head", 1.6),
    "upperarm_l": (0.028, "upperarm_l", "lowerarm_l", 0.436),
    "upperarm_r": (0.028, "upperarm_r", "lowerarm_r", 0.436),
    "lowerarm_l": (0.016, "lowerarm_l", "hand_l", 0.430),
    "lowerarm_r": (0.016, "lowerarm_r", "hand_r", 0.430),
    "hand_l": (0.006, "hand_l", "middle_01_l", 0.9),
    "hand_r": (0.006, "hand_r", "middle_01_r", 0.9),
    "thigh_l": (0.100, "thigh_l", "calf_l", 0.433),
    "thigh_r": (0.100, "thigh_r", "calf_r", 0.433),
    "calf_l": (0.0465, "calf_l", "foot_l", 0.433),
    "calf_r": (0.0465, "calf_r", "foot_r", 0.433),
    "foot_l": (0.0145, "foot_l", "ball_l", 0.5),
    "foot_r": (0.0145, "foot_r", "ball_r", 0.5),
}


class Rig:
    """A body: the skeleton as arrays, the skin, the sole points and the segment masses."""

    def __init__(self, model: Path, rig_json: Path | None = None):
        self.path = Path(model)
        self.glb = audit_clips.Glb(self.path)
        self.body = audit_clips.Body(self.glb)
        body = self.body
        self.names = list(body.names)
        self.index = dict(body.index)
        self.parent = {n: (body.names[body.parent[i]] if body.parent[i] >= 0 else None) for i, n in enumerate(self.names)}
        joints = {body.names[j] for j in body.joints}
        ## The bones, parents before children.
        self.bones = [body.names[i] for i in body.order if body.names[i] in joints]
        rest = body.world(body.rest_r[None], body.rest_t[None])[0]
        self.rest = {n: rest[i] for i, n in enumerate(self.names)}
        self.rest_rot = {n: m[:3, :3] for n, m in self.rest.items()}
        self.rest_pos = {n: m[:3, 3] for n, m in self.rest.items()}
        self.local_rot = {n: maths.matrix_of(body.rest_r[i]) for i, n in enumerate(self.names)}
        self.local_pos = {n: body.rest_t[i] for i, n in enumerate(self.names)}
        for n in self.bones:
            p = self.parent[n]
            if p not in joints:
                assert np.allclose(self.rest[p], np.eye(4), atol=1e-6), f"{model}: the armature is not at the origin"
        self.length = {}
        for s, _ in SIDES:
            for top, bottom in (("upperarm", "lowerarm"), ("lowerarm", "hand"), ("thigh", "calf"), ("calf", "foot")):
                self.length[f"{top}_{s}"] = float(
                    np.linalg.norm(self.rest_pos[f"{bottom}_{s}"] - self.rest_pos[f"{top}_{s}"])
                )
        self.hips = float(self.rest_pos["pelvis"][1])
        self.motion_scale = self.hips / REFERENCE_HIPS
        self._read_skin()
        self.sole = {s: self._sole(s) for s, _ in SIDES}
        self.masses = dict(MASSES)
        self.extra = {}
        found = rig_json or self._find_rig_json()
        if found:
            self._read_rig_json(Path(found))

    # ---- reading --------------------------------------------------------------------------------------------

    def _read_skin(self) -> None:
        glb, body = self.glb, self.body
        positions, joints, weights, tris, base = [], [], [], [], 0
        for mesh in glb.json.get("meshes", []):
            for prim in mesh["primitives"]:
                attrs = prim["attributes"]
                if "JOINTS_0" not in attrs:
                    continue
                position = glb.accessor(attrs["POSITION"])
                positions.append(position)
                joints.append(glb.accessor(attrs["JOINTS_0"]).astype(int))
                weights.append(glb.accessor(attrs["WEIGHTS_0"]).astype(float))
                if "indices" in prim:
                    tris.append(glb.accessor(prim["indices"]).astype(int).reshape(-1, 3) + base)
                base += len(position)
        self.verts = np.concatenate(positions)
        self.skin_joints = np.concatenate(joints)
        weight = np.concatenate(weights)
        self.skin_weights = weight / np.maximum(weight.sum(axis=1, keepdims=True), 1e-9)
        self.tris = np.concatenate(tris) if tris else np.zeros((0, 3), dtype=int)
        heaviest = self.skin_joints[np.arange(len(weight)), self.skin_weights.argmax(axis=1)]
        ## The bone each vertex follows most.
        self.owner = np.array([body.names[body.joints[slot]] for slot in heaviest])

    def _weight(self, bone: str) -> np.ndarray:
        """Each vertex's weight to a bone."""
        slot = self.body.joints.index(self.index[bone])
        return np.where(self.skin_joints == slot, self.skin_weights, 0.0).sum(axis=1)

    def _sole(self, side: str) -> dict:
        """The heel, the ball and the toe tip of a sole at rest, on the floor, and the ankle over them."""
        pick = np.isin(self.owner, [f"foot_{side}", f"ball_{side}", f"ball_leaf_{side}"])
        verts = self.verts[pick]
        low = verts[verts[:, 1] <= verts[:, 1].min() + 0.012]
        middle = float(np.median(low[:, 0]))
        floor = float(verts[:, 1].min())
        heel = (self.owner == f"foot_{side}") & (self.verts[:, 1] <= floor + 0.05)
        return {
            "heel": np.array([middle, floor, float(low[:, 2].min())]),
            "ball": np.array([middle, floor, float(self.rest_pos[f"ball_{side}"][2])]),
            "toe": np.array([middle, floor, float(low[:, 2].max())]),
            "ankle": self.rest_pos[f"foot_{side}"].copy(),
            "hinge": self.rest_pos[f"ball_{side}"].copy(),
            "floor": floor,
            # The skin of the heel and the arch with its weight to the foot bone, for a foot that rolls on it.
            "skin": self.verts[heel],
            "skin_weight": self._weight(f"foot_{side}")[heel],
        }

    def _find_rig_json(self) -> Path | None:
        body = self.path.stem.rsplit("_", 1)[-1]
        found = self.path.with_name(f"rig_{body}.json")
        return found if found.exists() else None

    def _read_rig_json(self, path: Path) -> None:
        data = json.loads(path.read_text(encoding="utf-8"))
        for bone in data.get("bones", []):
            name = bone["name"]
            assert name in self.index, f"{path.name} names the bone {name}, which {self.path.name} does not have"
            assert self.parent[name] == bone["parent"] or bone["parent"] is None, f"{name}: the parents differ"
        self.motion_scale = float(data.get("motion_scale", self.motion_scale))
        for side, points in data.get("sole", {}).items():
            for key, value in points.items():
                if not key.startswith("skin"):
                    self.sole[side][key] = np.array(value, dtype=float)
        for name, row in data.get("masses", {}).items():
            self.masses[name] = tuple(row)
        self.extra = {k: v for k, v in data.items() if k not in ("bones", "sole", "masses")}

    # ---- poses ----------------------------------------------------------------------------------------------

    def arrays(self, frames: list) -> tuple:
        """Poses (`{"local": {bone: 3x3}, "pelvis": place}`) as the rotation and translation arrays
        [frame, node, ...] of this body: the pelvis's place scales with the body's `motion_scale`."""
        body = self.body
        count = len(frames)
        rotation = np.repeat(body.rest_r[None], count, axis=0)
        translation = np.repeat(body.rest_t[None], count, axis=0)
        for f, pose in enumerate(frames):
            for name, m in pose["local"].items():
                if name in self.index:
                    rotation[f, self.index[name]] = maths.quat_of(m)
            translation[f, self.index["pelvis"]] = self.pelvis_local(pose["pelvis"]) * self.motion_scale
            for name, place in pose.get("places", {}).items():
                if name in self.index:
                    translation[f, self.index[name]] = np.asarray(place) * self.motion_scale
        return rotation, translation

    def pelvis_local(self, place: np.ndarray) -> np.ndarray:
        """The pelvis's world place (the reference body's) as its translation in its parent."""
        parent = self.rest[self.parent["pelvis"]]
        return parent[:3, :3].T @ (np.asarray(place, dtype=float) - parent[:3, 3])

    def world(self, rotation: np.ndarray, translation: np.ndarray) -> np.ndarray:
        """World matrices [frame, node, 4, 4]."""
        return self.body.world(rotation, translation)

    def joint(self, world: np.ndarray, bone: str) -> np.ndarray:
        """A bone's joint place on every frame, [frame, 3]."""
        return world[:, self.index[bone], :3, 3]

    def skin(self, world: np.ndarray, bones: tuple | None = None) -> np.ndarray:
        """The mesh's vertices on every frame, [frame, vertex, 3] (linear blend skinning, as Godot does it); only
        the vertices that follow `bones` most when given."""
        body = self.body
        pick = np.ones(len(self.verts), dtype=bool) if bones is None else np.isin(self.owner, bones)
        mats = world[:, body.joints] @ body.inverse_bind[None]
        rest = np.concatenate([self.verts[pick], np.ones((int(pick.sum()), 1))], axis=1)
        joints, weights = self.skin_joints[pick], self.skin_weights[pick]
        out = np.zeros((world.shape[0], len(rest), 3))
        for slot in range(joints.shape[1]):
            if not weights[:, slot].any():
                continue
            moved = np.einsum("fvij,vj->fvi", mats[:, joints[:, slot], :3, :], rest)
            out += weights[None, :, slot, None] * moved
        return out

    def sole_points(self, world: np.ndarray, side: str) -> dict:
        """The heel, ball and toe of a sole on every frame: the heel rides the foot bone, the toe the toe bone."""
        out = {}
        for key, bone in (("heel", f"foot_{side}"), ("ball", f"foot_{side}"), ("toe", f"ball_{side}")):
            local = np.linalg.inv(self.rest[bone]) @ np.append(self.sole[side][key], 1.0)
            out[key] = (world[:, self.index[bone]] @ local)[:, :3]
        return out

    def centre_of_mass(self, world: np.ndarray) -> np.ndarray:
        """The body's centre of mass on every frame, [frame, 3], from the segment masses."""
        total, out = 0.0, np.zeros((world.shape[0], 3))
        for share, near, far, along in self.masses.values():
            a, b = self.joint(world, near), self.joint(world, far)
            out += share * (a + along * (b - a))
            total += share
        return out / total
