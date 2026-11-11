"""One hand of the mannequin as the solver bends it: batched finger poses and their skin."""

import hold_field
import hold_rig as R
import numpy as np

FINGERS = ("index", "middle", "ring", "pinky", "thumb")
# Degrees: spread at the knuckle, then the three bends from the knuckle out.
LIMITS = {
    "finger": np.array([[-12.0, 12.0], [-15.0, 95.0], [0.0, 110.0], [0.0, 80.0]]),
    # The trigger finger leans further: down to the trigger, up to the frame.
    "index": np.array([[-20.0, 20.0], [-15.0, 95.0], [0.0, 110.0], [0.0, 80.0]]),
    # The thumb: its root about its own three axes (from the rest), a sideways lean and a bend
    # at the middle joint, a bend at the tip.
    "thumb": np.array([[-50.0, 50.0], [-50.0, 50.0], [-50.0, 50.0], [-40.0, 40.0], [-15.0, 75.0], [0.0, 85.0]]),
}
X, Y, Z = np.eye(3)


def local_rotations(finger, angles):
    """The three bones' rotations on top of their rests for angles (K, D): three (K, 3, 3)."""
    a = np.atleast_2d(angles)
    if finger == "thumb":
        r1 = R.axis_angle(Y, a[:, 0]) @ R.axis_angle(Z, a[:, 1]) @ R.axis_angle(X, a[:, 2])
        r2 = R.axis_angle(Z, a[:, 3]) @ R.axis_angle(X, a[:, 4])
        r3 = R.axis_angle(X, a[:, 5])
    else:
        r1 = R.axis_angle(Z, a[:, 0]) @ R.axis_angle(X, a[:, 1])
        r2 = R.axis_angle(X, a[:, 2])
        r3 = R.axis_angle(X, a[:, 3])
    return r1, r2, r3


class Hand:
    def __init__(self, rig, side, local_pose):
        self.rig, self.side = rig, side
        self.local = local_pose.copy()
        self.base_hand = None
        self.wrist = np.eye(3)  # a turn of the hand bone on top of the clip (its own axes)
        self.hand = rig.index["hand_" + side]
        self.arm = rig.under("lowerarm_" + side)
        self.chains = {f: [rig.index[f"{f}_0{k}_{side}"] for k in (1, 2, 3)] for f in FINGERS}
        self.angles = {f: np.zeros(6 if f == "thumb" else 4) for f in FINGERS}
        self.stride = 1  # measure every nth vertex of a finger (a quick search)
        self.move = np.eye(4)  # moves the forearm and hand as one piece (the support hand)
        under = rig.under("hand_" + side)
        self.ids = np.where(np.isin(rig.main, under))[0]
        self.remap = -np.ones(len(rig.verts), int)
        self.remap[self.ids] = np.arange(len(self.ids))
        self.tris = self.remap[rig.tris[np.isin(rig.tris, self.ids).all(axis=1)]]
        self.part = {}
        for f in FINGERS:
            for k, tag in enumerate(("base", "mid", "tip")):
                self.part[f + "_" + tag] = np.where(rig.main[self.ids] == self.chains[f][k])[0]
        self.part["palm"] = np.where(rig.main[self.ids] == self.hand)[0]
        self.finger_verts = {f: np.where(np.isin(rig.main[self.ids], self.chains[f]))[0] for f in FINGERS}
        self._apply_all()
        self._sample_palm()

    def _sample_palm(self, spacing=0.003):
        """Points all over the palm's faces, `spacing` apart, as weights of its vertices. The palm is one
        piece of a few large faces (edges up to 5 cm), so its vertices alone miss a fingertip or a corner of
        the gun that enters a face between them; the fingers are meshed finely and need none."""
        points = self.points()
        piece = hold_field.pieces(points[self.tris])
        palm = np.zeros(len(self.tris), bool)
        for index in range(piece.max() + 1):
            mine = piece == index
            if (self.rig.main[self.ids][self.tris[mine]] == self.hand).any():
                palm |= mine
        corners, weights = [], []
        for a, b, c in self.tris[palm]:
            across = max(1, int(np.ceil(np.linalg.norm(points[b] - points[a]) / spacing)))
            down = max(1, int(np.ceil(np.linalg.norm(points[c] - points[a]) / spacing)))
            u, v = np.meshgrid(np.arange(across + 1) / across, np.arange(down + 1) / down)
            keep = u + v <= 1.0 + 1e-9
            u, v = u[keep], v[keep]
            corners.append(np.broadcast_to([a, b, c], (len(u), 3)))
            weights.append(np.stack([1.0 - u - v, u, v], axis=1))
        self.palm_corners = np.concatenate(corners)
        self.palm_weights = np.concatenate(weights)
        # The mannequin each sample belongs to, as `Rig.model` says for a vertex.
        self.palm_model = self.rig.model[self.ids][self.palm_corners[:, 0]]

    def palm_points(self):
        """The palm's sample points as posed: (S, 3), on the faces as they are drawn."""
        points = self.points()
        return np.einsum("sk,skj->sj", self.palm_weights, points[self.palm_corners])

    def _apply_all(self):
        rig = self.rig
        if self.base_hand is None:
            self.base_hand = self.local[self.hand][:3, :3].copy()
        self.local[self.hand][:3, :3] = self.base_hand @ self.wrist
        for f in FINGERS:
            rots = local_rotations(f, self.angles[f])
            for bone, rot in zip(self.chains[f], rots, strict=False):
                self.local[bone][:3, :3] = rig.rest[bone][:3, :3] @ rot[0]
        self.glob = rig.fk(self.local)
        for b in self.arm:
            self.glob[b] = self.move @ self.glob[b]

    def set(self, finger, angles):
        self.angles[finger] = np.array(angles, dtype=float)
        self._apply_all()

    def hand_global(self):
        return self.glob[self.hand]

    def points(self, which=None):
        """Every hand vertex (or the ones `which` picks, by index into the hand's own list) as posed."""
        ids = self.ids if which is None else self.ids[which]
        return self.rig.skin(self.glob, ids)

    def finger_points(self, finger, angles):
        """The finger's vertices for each row of angles: (K, N, 3). Other fingers stay as they are."""
        return self.finger_points_turned(finger, local_rotations(finger, np.atleast_2d(angles)))

    def finger_points_turned(self, finger, rots):
        """The finger's vertices for each row of its three bones' rotations on top of their rests (three
        (K, 3, 3), as `local_rotations` gives them or blended between two poses): (K, N, 3)."""
        rig = self.rig
        chain = self.chains[finger]
        count = len(rots[0])
        parent = self.glob[rig.parent[chain[0]]]
        mats = []
        g = np.broadcast_to(parent, (count, 4, 4))
        for bone, rot in zip(chain, rots, strict=False):
            local = np.broadcast_to(rig.rest[bone], (count, 4, 4)).copy()
            local[:, :3, :3] = rig.rest[bone][:3, :3] @ rot
            g = g @ local
            mats.append(g @ rig.bind[bone])
        vid = self.ids[self.finger_verts[finger][:: self.stride]]
        homog = rig.homog[vid]
        static = np.zeros((len(vid), 3))
        moving = np.zeros((count, len(vid), 3))
        skin_mats = self.glob @ rig.bind
        for k in range(4):
            bones = rig.vbones[vid, k]
            weights = rig.vweights[vid, k]
            fixed = ~np.isin(bones, chain)
            static += (weights * fixed)[:, None] * np.einsum("nij,nj->ni", skin_mats[bones], homog)[:, :3]
            for j, bone in enumerate(chain):
                w = weights * (bones == bone)
                if w.any():
                    moving += w[None, :, None] * np.einsum("kij,nj->kni", mats[j][:, :3, :], homog)
        return static[None] + moving

    def finger_parts(self, finger):
        """For the finger's own vertex list: index arrays of its base, middle and tip bones' vertices."""
        mains = self.rig.main[self.ids[self.finger_verts[finger][:: self.stride]]]
        return [np.where(mains == b)[0] for b in self.chains[finger]]

    def angles_of(self, quaternions):
        """The angles of every finger for a pose given as bone name to Godot's (x, y, z, w), the way
        `quaternions()` writes one: {finger: angles}. Only a pose this solver made reads back exactly."""
        out = {}
        for f in FINGERS:
            first, second, third = (
                self.rig.rest[bone][:3, :3].T @ R.quat_to_mat(quaternions[self.rig.names[bone]])
                for bone in self.chains[f]
            )
            bend = [np.degrees(np.arctan2(m[2, 1], m[2, 2])) for m in (first, second, third)]
            if f == "thumb":
                # The root is Y, then Z, then X; the middle joint Z, then X.
                root = [
                    np.degrees(np.arctan2(-first[2, 0], first[0, 0])),
                    np.degrees(np.arcsin(np.clip(first[1, 0], -1.0, 1.0))),
                    np.degrees(np.arctan2(-first[1, 2], first[1, 1])),
                ]
                lean = np.degrees(np.arctan2(second[1, 0], second[0, 0]))
                out[f] = np.array([*root, lean, bend[1], bend[2]])
            else:
                out[f] = np.array([np.degrees(np.arctan2(first[1, 0], first[0, 0])), *bend])
        return out

    def quaternions(self, fingers=FINGERS):
        """Each finger bone's local rotation as Godot's (x, y, z, w)."""
        out = {}
        for f in fingers:
            for bone in self.chains[f]:
                out[self.rig.names[bone]] = R.mat_to_quat(self.local[bone][:3, :3]).tolist()
        return out
