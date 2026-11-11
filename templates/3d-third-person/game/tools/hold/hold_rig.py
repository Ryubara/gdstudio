"""The rig the pistol hold solver works on (kit #1001): the dump `dump_hold_rig.gd` writes, forward kinematics
and skinning as Godot does them (a vertex is the weighted sum of bone pose times bind pose times the vertex)."""

import copy
import json

import numpy as np


def xf(a):
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = a[0:3], a[3:6], a[6:9], a[9:12]
    return m


def quat_to_mat(q):  # x y z w
    x, y, z, w = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def mat_to_quat(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    return q / np.linalg.norm(q)


def axis_angle(axis, deg):
    """Rotation matrices about `axis` for an array of angles in degrees: (..., 3, 3)."""
    a = np.radians(np.asarray(deg, dtype=float))
    axis = np.asarray(axis, dtype=float) / np.linalg.norm(axis)
    x, y, z = axis
    k = np.array([[0, -z, y], [z, 0, -x], [-y, x, 0]])
    c, s = np.cos(a)[..., None, None], np.sin(a)[..., None, None]
    return np.eye(3) * c + s * k + (1 - c) * np.outer(axis, axis)


class Rig:
    def __init__(self, data):
        self.names = [b["name"] for b in data["bones"]]
        self.index = {n: i for i, n in enumerate(self.names)}
        self.parent = [b["parent"] for b in data["bones"]]
        self.rest = np.array([xf(b["rest"]) for b in data["bones"]])
        self.poses = {k: np.array([xf(p) for p in v]) for k, v in data["poses"].items()}
        skin = data["skin"]
        self.verts = np.array(skin["vertices"])
        self.vbones = np.array(skin["bones"], dtype=int)
        self.vweights = np.array(skin["weights"])
        self.vweights /= self.vweights.sum(axis=1, keepdims=True)
        self.tris = np.array(skin["triangles"], dtype=int)
        self.bind = np.array(
            [xf(skin["binds"].get(str(i), [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])) for i in range(len(self.names))]
        )
        self.main = self.vbones[np.arange(len(self.verts)), self.vweights.argmax(axis=1)]
        self.share = self.vweights.max(axis=1)
        self.homog = np.concatenate([self.verts, np.ones((len(self.verts), 1))], axis=1)
        self.model = np.zeros(len(self.verts), int)

    def under(self, root):
        r = self.index[root]
        out = []
        for b in range(len(self.names)):
            c = b
            while c >= 0 and c != r:
                c = self.parent[c]
            if c >= 0:
                out.append(b)
        return out

    def fk(self, local):
        """Global transforms (B, 4, 4) from locals (B, 4, 4); parents come first in the list."""
        g = np.empty_like(local)
        for b in range(len(self.names)):
            p = self.parent[b]
            g[b] = local[b] if p < 0 else g[p] @ local[b]
        return g

    def skin(self, glob, which=None):
        """Skinned vertices (N, 3) for global transforms; `which` picks vertices."""
        m = glob @ self.bind  # (B, 4, 4)
        idx = np.arange(len(self.verts)) if which is None else which
        out = np.zeros((len(idx), 3))
        for k in range(4):
            mk = m[self.vbones[idx, k]]  # (n, 4, 4)
            out += self.vweights[idx, k, None] * np.einsum("nij,nj->ni", mk, self.homog[idx])[:, :3]
        return out


def merged(first, second):
    """One rig that carries both models' hands: `first` with the hand vertices of `second` added, so a
    pose is measured on both skins at once. The two skeletons must match from the hands down; a vertex
    of `second` is moved into `first`'s bind space by its hand (`model` says whose a vertex is)."""
    assert first.names == second.names
    out = copy.copy(first)
    count = len(first.verts)
    moved = second.verts.copy()
    keep = np.zeros(len(second.verts), bool)
    for side in ("r", "l"):
        hand = first.index["hand_" + side]
        to_first = np.linalg.inv(first.bind[hand]) @ second.bind[hand]
        for bone in first.under("hand_" + side):
            other = np.linalg.inv(first.bind[bone]) @ second.bind[bone]
            assert np.abs(other - to_first).max() < 2e-4, (first.names[bone], np.abs(other - to_first).max())
        mine = np.isin(second.main, first.under("hand_" + side))
        moved[mine] = second.verts[mine] @ to_first[:3, :3].T + to_first[:3, 3]
        keep |= mine
    tris = second.tris[keep[second.tris].all(axis=1)] + count
    out.verts = np.concatenate([first.verts, moved])
    out.vbones = np.concatenate([first.vbones, second.vbones])
    out.vweights = np.concatenate([first.vweights, second.vweights])
    out.tris = np.concatenate([first.tris, tris])
    out.main = np.concatenate([first.main, np.where(keep, second.main, -1)])
    out.share = np.concatenate([first.share, second.share])
    out.homog = np.concatenate([out.verts, np.ones((len(out.verts), 1))], axis=1)
    out.model = np.concatenate([np.zeros(count, int), np.ones(len(moved), int)])
    return out


def load(path):
    with open(path, "rb") as file:
        data = json.load(file)
    return {name: Rig(m) for name, m in data["models"].items()}, data["pistol"]
