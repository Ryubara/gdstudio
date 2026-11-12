"""Solves how the mannequin's hands hold the pistol (kit #1001), from the dump `dump_hold_rig.gd` writes.

    <godot> --headless --path game -s res://tools/hold/dump_hold_rig.gd -- <abs>/rig.json
    uv run --no-project --with numpy --with scipy python tools/hold/solve_pistol_hold.py <abs>/rig.json <abs>/hold.json         --body=female --search-seat --search-left
    <godot> --headless --path game -s res://tools/hold/write_hold.gd -- <abs>/hold.json female

It skins one body's hands (`--body=female` or `--body=male`, the template's two bodies: `CharacterBodies`) on the CPU
as Godot does and measures them against the pistol's closed pieces on a 1 mm grid (and, for the left hand, against
the right hand of the same body). Each body gets a hold of its own (kit #1187): the prototype bodies' hands are a
person's size and differ (0.181 m and 0.195 m), so no one pose closes both; `--body=both` measures two bodies whose
skeletons match from the hands down at once, as the Quaternius pair did. With no option it solves the fingers for the seat and the left hand's place below (the hold the template
ships, about 5 minutes); `--search-seat` and `--search-left` search those again from there (4 to 6 minutes each),
`--seat=` and `--left=` give other starts, and `--scan=` prints a table of seats to choose from. The left hand
under the magazine (kit #1031: where it pushes the magazine in during the reload) is solved next, from its
place on the gun rolled under the magazine's base; `--magazine=` gives another move from that place and
`--magazine-only` solves only it, on the seat and right hand of the output file of an earlier run (a minute).
The left hand's way off the gun and back onto it (kit #1051) is solved last: its fingers opened where it holds,
each as far as it lifts off without passing through anything on the way, and the straight line along which the
opened hand leaves, the clear one nearest the way to the belt; `--way-only` solves only that, on the output
file of an earlier run (five minutes). The new magazine in the left hand (kit #1052) comes after it: the fingers
closed on the magazine from the belt to the grip, and the shares of the way in over which they go from that pose
to the one under the magazine; `--carry-only` solves only that, on the output file of an earlier run (three
minutes a body, a quarter of an hour more the first time its distance grids are made; `--carry_trace` prints how far
off each part of the hand is at every step of the way in, and into what).

The seat is given as a move from `REFERENCE_SEAT` (metres along the pistol's own axes, then degrees about them),
and the hand bone is turned back at the wrist by the same turn, so the barrel keeps the reference's line in the
forearm in every clip and only the wrist bends. The test `tests/gameplay/test_pistol_hold.gd` measures the result
in Godot; the two agree to about 0.4 mm.
"""

import itertools
import json
import sys
import time

import hold_field
import hold_rig as R
import numpy as np
from hold_hand import FINGERS, LIMITS, Hand, local_rotations
from scipy.spatial.transform import Rotation

BASE_POSE = "ual1/Pistol_Aim_Neutral@0.16"
# Both mannequins are measured at once and their skins differ by up to 3.3 mm in the same pose, so the
# nearer skin of the two is pressed 0.8 mm into the surface (the other is then up to 2.5 mm off it).
TARGET = -0.0008  # where the nearer skin should sit off the surface, metres
TOL = 0.0012  # how deep the solver lets skin go (the test allows 2 mm)
# How far off the gun or the other hand the support palm's nearest vertex may lie before each millimetre costs
# `PALM_WEIGHT`: the test reads the palm's vertices and wants a holding part within 5 mm (the male prototype's
# search left them 8.3 mm off while the samples over its faces read 1.7 mm).
PALM_OFF = 0.003
PALM_WEIGHT = 10.0  # at 3 the female prototype's search kept them 6.5 mm off for the cant's sake
# How far off they stay at least: pressed to 0 mm in the aim pose, the male prototype's read 2.0 to 2.4 mm inside in
# the game where the reload ends with the gun carried (2.3 mm off passed).
PALM_NEAR = 0.0012
# How far any point of the right thumb's tip may lie from the left thumb root's vertices (the test allows 12 mm
# from its skin), metres.
THUMB_ROOT_NEAR = 0.011
# Where on each triangle of a frozen hand its skin is sampled for `Hand.finger_depth`, besides the vertices
# (barycentric weights): a low-poly hand's face entered the other hand's finger between its vertices.
FACE_SAMPLES = np.array(
    [
        (1 / 3, 1 / 3, 1 / 3),
        (0.5, 0.5, 0),
        (0, 0.5, 0.5),
        (0.5, 0, 0.5),
        (0.7, 0.15, 0.15),
        (0.15, 0.7, 0.15),
        (0.15, 0.15, 0.7),
    ]
)
# Where the middle of the trigger finger's last bone sits when its pad is on the trigger, in the gun.
TRIGGER_OFF = np.array([-0.010, -0.004, 0.0])
THUMB_AT = np.array([-0.01, 0.070, 0.030])
# Where the right thumb's last bone lies from the left thumb's root joint (`thumb_01_l`) when both hands
# hold: above it and in toward the slide, the furthest forward the thumb reaches from behind the grip.
THUMB_OVER = np.array([0.0, 0.025, -0.016])
THUMB_OVER_OFF = 0.0005  # how far off the support hand its tip stays in this solver's measure, metres
# Where on its way between its two poses the right thumb is measured: at fifths it still passed 2.8 mm nearer the ends.
THUMB_WAY_SHARES = (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9)
THUMB_OVER_Y = 0.10  # how high in the gun the right thumb may lie there, beside the slide, metres
# The left thumb lies ahead of the right one along the frame, above the trigger guard and under the slide.
LEFT_THUMB_AT = np.array([-0.095, 0.074, 0.029])
UNDER_GUARD_Y = 0.006  # the middle of a finger that lies under the trigger guard is no higher
# What a support finger's millimetre off the shooting hand costs, in millimetres of contact; the little finger's
# more: at 0.5 the female prototype's lay 18 mm under the right hand, and at 2 for every finger the male's index
# finger hooked under the trigger guard so far that the opened hand found no way off the gun.
OVER = 0.5
OVER_LITTLE = 2.0
CANT = (30.0, 45.0)  # the support hand's cant the search stays in, degrees (`left_cant`)
REACH_SPARE = 0.010  # how much shorter than the arm the way from the left shoulder to the hand stays, metres
ACROSS_Z = -0.015  # a support finger's last bone is at least this far on the gun's right (-Z), metres
OVER_NEAR = 0.002  # how near the shooting hand's skin a support finger's bone counts as lying on it, metres
WEB_Y = 0.07  # how high on the gun the thumb's root should sit (the web under the tang)
FRAME_Y = 0.079
# How far the middle of the trigger finger's last bone lies from the trigger while it is along the frame: the
# test wants its nearest skin 20 mm off (the middle of the bone is 7 to 10 mm farther), and a smaller hand's
# finger lies lower (kit #1187).
FRAME_TRIGGER_CLEAR = 0.034
# The pistol on `hand_r` as kit #834 seated it (basis columns, then the origin): the barrel line the aim clips
# were captured with, 1.5 degrees up and 3 degrees out in `Pistol_Aim_Neutral`.
REFERENCE_SEAT = [0.0234, -0.9867, 0.1609, -0.0805, 0.1585, 0.9841, -0.9965, -0.036, -0.0757, -0.0264, 0.1234, 0.0091]
# The seat the template ships, as a move from the reference, and the left hand's place as a move from the right
# hand's mirrored across the pistol.
SEAT = [0.022, -0.035, 0.0306, -4.0, -23.5, -15.5]
LEFT = [-0.0097, -0.0322, 0.0131, -11.85, -0.84, 26.56]
# The left hand's place while it pushes the magazine in, as a move from `MAGAZINE_FROM` (about the middle of
# the magazine's base): rolled about the barrel's line until the heel of the palm is under the base.
# `MAGAZINE_FROM` is the right hand's place mirrored and moved, uncanted (where the left hand held before
# kit #1084 canted it): the hand under the magazine is flat, its wrist straight.
MAGAZINE_FROM = [-0.017, -0.03, 0.009, -8.0, 1.5, 0.0]
MAGAZINE = [0.0, 0.0, -0.07, 80.0, 0.0, 0.0]
# How far the thumb of the hand under the magazine stays off every surface, metres: the test in Godot read
# the male thumb's root 1.4 mm deeper than this solver there.
CUP_THUMB_OFF = 0.0005
# The places below the one under the magazine at which the cupped fingers are measured too, metres down the
# magazine's line (`WeaponHold.magazine_approach` is 0.1 m).
CUP_WAY_STEPS = (0.004, 0.008, 0.012, 0.016, 0.02, 0.025, 0.03, 0.035, 0.04, 0.05, 0.07)
# How deep the cupped fingers may go at those places: tighter than `TOL`, since the test in Godot read the male
# thumb 1 mm deeper than this solver on the way.
CUP_WAY_TOL = 0.0004
# The left hand's way off the gun (kit #1051). Its fingers open where the hand holds, then the opened hand
# leaves along a straight line; the game plays both backwards to bring it on again.
OPEN_CLEAR = 0.005  # how far off every surface an opened finger is lifted, where it can be, metres
WAY_TOL = TOL  # how deep any skin may pass on the way, metres (the test allows 2 mm); the held palm itself
# sits up to TOL in, so a smaller one found no clear way for the female prototype body (kit #1187)
WAY_LENGTH = 0.06  # how far the opened hand goes before the clip's arm takes it, metres
WAY_STEPS = 16  # the poses measured between closed and open, and the places between on and off
WAY_GRID = 10.0  # degrees between the directions tried
# The new magazine in the left hand (kit #1052). From the belt to the grip the hand carries it as it is when the
# hand's place is the `MagazineHand` marker (the heel of the palm under its base), so the magazine rides the hand
# bone and one pose of the fingers closed on it holds it all the way. The way in is the grip's own line (the
# `Grip` socket's -Y), the magazine's length and a little, so it starts with its top clear of the well.
CARRY_LENGTH = 0.12  # metres down the grip's line where the magazine starts its way in (its top 1.6 cm clear)
CARRY_STEPS = 40  # the equal parts of the way in that are measured
CARRY_SHARES = 0.1  # the step between the shares of the way in tried for the fingers' change of pose
TRIGGER_STEPS = 20  # the equal parts of the trigger finger's way that are measured (kit #1079)
# The dumped pose in which the reload clip has the left hand at the belt: the way out leans toward it.
BELT_POSE = "ual1/Pistol_Reload@0.40"
MAGAZINE_BASE = np.array([0.003, -0.052, 0.0])
# The grid of the gun's distance: the whole gun (muzzle at -0.207) and a hand's thickness round it.
GRID_LOW = [-0.24, -0.09, -0.075]
GRID_HIGH = [0.08, 0.17, 0.075]
# The grid of a frozen hand's distance, in the gun's space: either hand where it holds, and a finger round it.
HAND_LOW = [-0.17, -0.12, -0.12]
HAND_HIGH = [0.10, 0.16, 0.12]
FAR = 1.0  # what the distance to a hand that is not there reads, metres


def relu(x):
    return np.maximum(x, 0.0)


class Scene:
    def __init__(self, rig, pistol, cache):
        self.rig = rig
        tris = np.array(pistol["triangles"]).reshape(-1, 3, 3)
        self.gun = hold_field.PiecesField(tris, GRID_LOW, GRID_HIGH, 0.001, cache)
        self.sockets = {k: R.xf(v) for k, v in pistol["sockets"].items()}
        self.seat0 = R.xf(REFERENCE_SEAT)
        self.seat = self.seat0.copy()
        self.right = Hand(rig, "r", rig.poses[BASE_POSE])
        self.left = Hand(rig, "l", rig.poses[BASE_POSE])
        # A hand's side and its skin as it holds, a field for each mannequin: a surface for the other hand.
        self.frozen = {}
        # The same hand's vertices as it holds, and whose mannequin each is: measured against the other
        # hand's fingers (`Hand.finger_depth`).
        self.frozen_points = {}
        # The right thumb's angles on the frame while its pose on the support hand is solved.
        self.thumb_from = None

    def gun_global(self):
        return self.right.hand_global() @ self.seat

    def to_gun(self, points):
        g = self.gun_global()
        return (points - g[:3, 3]) @ g[:3, :3]

    def distances(self, hand, points, which=None, model=None):
        """The distances from a hand's points to the gun and to the other hand of the same mannequin as it
        was frozen (`FAR` when it is not): two arrays (`which` picks the hand's vertices the points are,
        all by default; `model` says whose each point is when they are not vertices)."""
        gun = self.gun(self.to_gun(points))
        other = np.full(gun.shape, FAR)
        fields = self.frozen.get("l" if hand.side == "r" else "r")
        if fields:
            if model is None:
                model = self.rig.model[hand.ids if which is None else hand.ids[which]]
            for index, field in enumerate(fields):
                mine = model == index
                other[..., mine] = field(points[..., mine, :])
        return gun, other

    def field(self, hand, points, which=None):
        """The distance from a hand's points to what it holds: the gun and the other hand as frozen."""
        return np.minimum(*self.distances(hand, points, which))

    def palm(self, hand):
        """The distances from all over a hand's palm (`Hand.palm_points`) to the gun and to the other hand."""
        return self.distances(hand, hand.palm_points(), model=hand.palm_model)

    def freeze(self, hand, also=(), without=()):
        """A hand as it holds the gun becomes a surface for the other hand, on a grid in the gun's space.
        `also` lists (finger, angles) pairs: the finger is part of the surface in those poses too (the
        trigger finger along the frame, on the trigger and between), so the other hand clears them all.
        `without` names fingers whose two outer bones are left out (the shooting thumb, which is laid on
        the support hand afterwards)."""
        points = self.to_gun(hand.points())
        left_out = np.zeros(len(hand.tris), bool)
        for finger in without:
            outer = np.isin(self.rig.main[hand.ids], hand.chains[finger][1:])
            left_out |= outer[hand.tris].any(axis=1)
        extra = []
        for finger, angles in also:
            verts = hand.finger_verts[finger]
            moved = np.zeros_like(points)
            moved[verts] = self.to_gun(hand.finger_points(finger, angles)[0])
            extra.append((np.isin(hand.tris, verts).all(axis=1), moved))
        fields = []
        for index in range(self.rig.model.max() + 1):
            # The triangles of this mannequin's hand, as indices into the hand's own points.
            mine = (self.rig.model[hand.ids][hand.tris[:, 0]] == index) & ~left_out
            tris = [points[hand.tris[mine]]] + [moved[hand.tris[mine & whole]] for whole, moved in extra]
            tris.append(wrist_cap(tris[0]))
            grid = hold_field.PiecesField(np.concatenate(tris), HAND_LOW, HAND_HIGH, 0.0015, rays=(0, 1, 2))
            fields.append(lambda at, grid=grid: grid(self.to_gun(at)))
        self.frozen[hand.side] = fields
        # Its vertices and points on its faces: the prototype bodies' fingers are a ring of eight vertices at
        # each end of a bone, and the right ring finger's face lay 2.6 mm in the left one with no vertex in it.
        kept_tris = hand.tris[~left_out]
        all_points, models = hand.points(), self.rig.model[hand.ids]
        kept = np.unique(kept_tris)
        faces = np.einsum("sk,tkd->std", FACE_SAMPLES, all_points[kept_tris]).reshape(-1, 3)
        face_models = np.tile(models[kept_tris[:, 0]], len(FACE_SAMPLES))
        self.frozen_points[hand.side] = (
            np.concatenate([all_points[kept], faces]),
            np.concatenate([models[kept], face_models]),
        )


def wrist_cap(tris):
    """Triangles that close a hand's skin where it is open (the palm ends at the wrist, a finger's bone
    where the skin's selection ends): each ring of edges only one triangle has, joined to its own middle,
    so every piece stays its own closed piece. The forearm goes on at the wrist, so what lies in that
    opening is inside the arm; left open, the rays that count a point inside or out disagree there, and a
    thumb laid in the other wrist read 0.7 mm off it where the game's measure read 8.9 mm in."""
    keys = np.round(tris.reshape(-1, 3) * 1e5).astype(np.int64)
    welded, ids = np.unique(keys, axis=0, return_inverse=True)
    ids = ids.reshape(-1, 3)
    edges = np.concatenate([ids[:, [0, 1]], ids[:, [1, 2]], ids[:, [2, 0]]])
    lone, counts = np.unique(np.sort(edges, axis=1), axis=0, return_counts=True)
    lone = lone[counts == 1]
    if len(lone) == 0:
        return np.empty((0, 3, 3))
    ring = {int(v): int(v) for v in lone.ravel()}

    def find(v):
        while ring[v] != v:
            ring[v] = ring[ring[v]]
            v = ring[v]
        return v

    for a, b in lone:
        ring[find(int(a))] = find(int(b))
    of = np.array([find(int(a)) for a in lone[:, 0]])
    caps = []
    for root in np.unique(of):
        corners = welded[lone[of == root]] * 1e-5
        middle = np.broadcast_to(corners.reshape(-1, 3).mean(axis=0), (len(corners), 1, 3))
        caps.append(np.concatenate([corners, middle], axis=1))
    return np.concatenate(caps)


def finger_cost(scene, hand, finger, angles, mode):
    """The cost of each row of angles for one finger, and what was measured: (K,), dict."""
    pts = hand.finger_points(finger, angles)
    to_gun, to_hand = scene.distances(hand, pts, hand.finger_verts[finger][:: hand.stride])
    sd = np.minimum(to_gun, to_hand)
    base, mid, tip = hand.finger_parts(finger)
    lows = [sd[:, p].min(axis=1) for p in (base, mid, tip)]
    # A search that measures every third vertex keeps 0.4 mm in hand, so the full measure agrees.
    deep = relu(-sd.min(axis=1) - (TOL if hand.stride == 1 else TOL - 0.0004))
    other = scene.frozen_points.get("l" if hand.side == "r" else "r")
    if other is not None:
        # The other hand's skin inside this finger counts as this finger's skin inside the other hand.
        rots = local_rotations(finger, np.atleast_2d(angles))
        deep = np.maximum(deep, relu(hand.finger_depth(finger, rots, *other) - TOL))
    if mode == "cup" and finger == "thumb":
        deep = relu(CUP_THUMB_OFF - sd.min(axis=1))
    cost = 100.0 * deep
    if mode == "cup":
        # The cupped fingers ride the hand up the magazine's line and a little way down it again, so each is
        # measured at places down the line too (kit #1187: a fingertip that hooked round the grip's foot passed
        # 3 to 5 mm through the gun or the right hand on the way, though it lay clear under the magazine).
        down = scene.gun_global()[:3, :3] @ np.array([0.0, -1.0, 0.0])
        which = hand.finger_verts[finger][:: hand.stride]
        for step in CUP_WAY_STEPS:
            moved = scene.field(hand, pts + step * down, which)
            cost += 100.0 * relu(-moved.min(axis=1) - CUP_WAY_TOL)
    a = np.atleast_2d(angles)
    tip_at = scene.to_gun(pts[:, tip].mean(axis=1))
    mid_at = scene.to_gun(pts[:, mid].mean(axis=1))
    touch = [np.abs(low - TARGET) for low in lows]
    if mode == "wrap":
        cost += touch[2] + touch[1] + 0.5 * touch[0] + natural(a)
    elif mode == "over":
        # The support hand's fingers lie over the shooting hand's fingers, never beside them on the gun:
        # the middle and last bones are on the other hand's skin, whatever else they touch.
        cost += touch[2] + touch[1] + 0.5 * touch[0] + natural(a)
        over = OVER_LITTLE if finger == "pinky" else OVER
        cost += over * (relu(to_hand[:, mid].min(axis=1) - OVER_NEAR) + relu(to_hand[:, tip].min(axis=1) - OVER_NEAR))
        # They go round the front of the grip to the gun's far side: a finger curled into its own palm
        # touches the other hand's fingertips too, and holds nothing.
        cost += relu(tip_at[:, 2] - ACROSS_Z)
        if finger == "index":
            # The index finger is pressed up under the trigger guard: its first two bones below the
            # guard's underside, and the finger on the gun there (the other hand covers the grip).
            base_at = scene.to_gun(pts[:, base].mean(axis=1))
            cost += relu(base_at[:, 1] - UNDER_GUARD_Y) + relu(mid_at[:, 1] - UNDER_GUARD_Y)
            cost += 0.5 * np.abs(to_gun.min(axis=1) - TARGET)
    elif mode == "trigger":
        want = scene.sockets["Trigger"][:3, 3] + TRIGGER_OFF
        cost += 0.7 * np.linalg.norm(tip_at - want, axis=1) + 0.5 * touch[2]
        cost += 1e-4 * np.abs(a[:, 3] - 0.65 * a[:, 2])
    elif mode == "frame":
        # Straight along the gun's right side, outside the trigger guard, as high as the knuckle lets it.
        cost += touch[2] + touch[1] + 2e-4 * (a[:, 2] + a[:, 3])
        cost += relu(tip_at[:, 2] + 0.014) + relu(mid_at[:, 2] + 0.014)
        cost += 0.1 * relu(FRAME_Y - tip_at[:, 1])
        trigger = scene.sockets["Trigger"][:3, 3]
        cost += relu(FRAME_TRIGGER_CLEAR - np.linalg.norm(tip_at - trigger, axis=1))
    elif mode == "cup":
        # Under the magazine: the fingers close on whatever is in reach (the grip's foot, the right hand).
        cost += touch[2] + 0.5 * touch[1]
        cost += 2e-4 * relu(a[:, 5] - 45.0) if finger == "thumb" else 3.0 * natural(a) + 2e-4 * np.abs(a[:, 0])
    elif mode == "carry":
        # The new magazine in the hand: every finger closed on it, the thumb on its side, nothing in it.
        if finger == "thumb":
            cost += touch[2] + 0.7 * touch[1] + 2e-4 * relu(a[:, 5] - 45.0)
        else:
            cost += touch[2] + touch[1] + 0.5 * touch[0] + natural(a)
    elif mode == "thumb_over":
        # The shooting thumb while the support hand is on the gun: it rests on the root of the support
        # thumb, which fills the place on the frame it has when the gun is held in one hand, and still
        # points forward, no higher than the slide's foot.
        # Only its last bone lies on that hand, and where it lies counts for more than how closely: asked
        # to lie on the hand with the middle bone too, or pulled to a place it cannot reach, it turned
        # sideways behind the gun and put its tip in the support wrist's opening.
        cost += 0.3 * np.abs(to_hand[:, tip].min(axis=1) - TARGET)
        rig, left = scene.rig, scene.left
        root = scene.to_gun(left.glob[rig.index["thumb_01_l"]][:3, 3][None])[0]
        cost += np.linalg.norm(tip_at - (root + THUMB_OVER), axis=1)
        # Every point of the tip near that root's skin: the test measures from whichever point of the tip
        # is nearest a surface, and a place by the joint alone let the male prototype's thumb lie 17 mm off the
        # skin, by the tip's middle the female's 22 mm.
        skin = left.points()[left.part["thumb_base"]]
        tips = pts[:, tip]
        near = np.linalg.norm(tips[:, :, None, :] - skin[None, None], axis=3).min(axis=2).max(axis=1)
        cost += 2.0 * relu(near - THUMB_ROOT_NEAR)
        # The game's measure reads the male thumb's tip 1.3 mm deeper in that hand than this one does.
        cost += 100.0 * relu(THUMB_OVER_OFF - to_hand[:, tip].min(axis=1))
        # On the way from where it lies on the frame (the game blends the two poses while the support hand
        # is away), it is no deeper in the gun than a finger that holds: measured half-way alone, the
        # prototype bodies' thumbs passed 3.7 to 4.8 mm through it nearer either end.
        if scene.thumb_from is not None:
            for share in THUMB_WAY_SHARES:
                between = hand.finger_points(finger, share * a + (1.0 - share) * scene.thumb_from)
                passing = scene.gun(scene.to_gun(between)).min(axis=1)
                cost += 100.0 * relu(-passing - (TOL - 0.0004))
        # It stays on the gun's left: the left hand's fingertips, round on the gun's right, are skin of
        # that hand too, and a thumb laid on them would have crossed through the gun.
        cost += relu(0.012 - tip_at[:, 2]) + relu(0.012 - mid_at[:, 2])
        # Beside the slide it may lie higher than on the frame (the support thumb's root is under it).
        cost += relu(tip_at[:, 1] - THUMB_OVER_Y) + relu(mid_at[:, 1] - THUMB_OVER_Y)
        # It still points forward, and climbs onto the hand: the tip may be higher than the middle bone.
        cost += 0.3 * relu((tip_at - mid_at)[:, 0] + 0.01)
        cost += 2e-4 * relu(a[:, 5] - 45.0)
    elif mode == "thumb":
        # Both thumbs lie on the gun's left (+Z), the left one ahead of the right one.
        cost += touch[2] + 0.7 * touch[1] + 0.3 * touch[0]
        want = THUMB_AT if hand.side == "r" else LEFT_THUMB_AT
        cost += 0.4 * np.linalg.norm(tip_at - want, axis=1)
        cost += relu(0.012 - tip_at[:, 2])
        # Under the slide, round the back of the grip below the tang, and lying forward: the tip
        # ahead of the middle bone and no higher.
        cost += relu(tip_at[:, 1] - 0.084) + relu(mid_at[:, 1] - 0.08)
        lie = tip_at - mid_at
        cost += 1.0 * relu(lie[:, 0] + 0.01) + 1.0 * relu(lie[:, 1])
        # A thumb that lies on a surface is nearly straight: a hooked tip costs 0.2 mm a degree past 45.
        cost += 2e-4 * relu(a[:, 5] - 45.0)
    return cost, {"base": lows[0], "mid": lows[1], "tip": lows[2], "deep": deep, "tip_at": tip_at}


def natural(a):
    """What a wrapped finger's bends cost for not looking like a hand's: the last joint follows the middle
    one, and every joint is near a closed grip's (45, 70 and 45 degrees). A degree costs 0.03 to 0.1 mm."""
    cost = 1e-4 * np.abs(a[:, 3] - 0.65 * a[:, 2])
    return cost + 3e-5 * (np.abs(a[:, 1] - 45.0) + np.abs(a[:, 2] - 70.0) + np.abs(a[:, 3] - 45.0))


def start_grid(finger, mode):
    if finger == "thumb":
        root = [-30.0, 0.0, 30.0]
        return np.array(list(itertools.product(root, root, root, [0.0], [0, 25, 50], [0, 30, 60])), float)
    if mode in ("trigger", "frame"):
        spreads = [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]
        return np.array(
            list(itertools.product(spreads, range(-10, 91, 10), range(0, 111, 10), range(0, 81, 20))), float
        )
    return np.array(list(itertools.product([0.0], range(-10, 96, 15), range(0, 111, 15), range(0, 81, 20))), float)


def solve_finger(scene, hand, finger, mode, quick=False, start=None, wide=0):
    """The angles of one finger that cost least in `mode`, and that cost: the best of a grid of starts
    (and `start`), refined by steps that halve. `wide` adds that many random starts and refines the best
    four of them all, each on its own: where the grid's best start leads to a pose that only looks
    cheap from there (a thumb laid sideways), another start finds the one that is."""
    limits = LIMITS.get(finger, LIMITS["finger"])
    grid = start_grid(finger, mode)
    if start is not None:
        grid = np.concatenate([grid, np.atleast_2d(start)])
    if wide:
        pool = np.random.default_rng(7).uniform(limits[:, 0], limits[:, 1], size=(wide, len(limits)))
        grid = np.concatenate([grid, pool])
    cost = np.concatenate(
        [finger_cost(scene, hand, finger, grid[first : first + 200], mode)[0] for first in range(0, len(grid), 200)]
    )
    found = [
        refine_finger(scene, hand, finger, mode, quick, grid[k], cost[k]) for k in np.argsort(cost)[: 4 if wide else 1]
    ]
    return min(found, key=lambda entry: entry[1])


def refine_finger(scene, hand, finger, mode, quick, best, best_cost):
    limits = LIMITS.get(finger, LIMITS["finger"])
    dims = len(best)
    rng = np.random.default_rng(1)
    for scale in (8.0, 4.0, 2.0, 1.0) if quick else (8.0, 4.0, 2.0, 1.0, 0.5, 0.25):
        for _ in range(1 if quick else 3):
            steps = np.concatenate(
                [np.eye(dims), -np.eye(dims), rng.integers(-1, 2, size=(60 if quick else 200, dims))]
            )
            cands = np.clip(best + scale * steps, limits[:, 0], limits[:, 1])
            cost, _ = finger_cost(scene, hand, finger, cands, mode)
            if cost.min() < best_cost:
                best_cost = cost.min()
                best = cands[cost.argmin()]
    return best, best_cost


def close_right(scene, quick=False, trigger=True):
    """Closes the right hand on the gun where it sits; returns the total cost and a table."""
    hand = scene.right
    total = 0.0
    table = {}
    modes = {"index": "trigger" if trigger else "frame", "thumb": "thumb"}
    for _ in range(1 if quick else 2):
        total = 0.0
        for finger in FINGERS:
            mode = modes.get(finger, "wrap")
            best, cost = solve_finger(scene, hand, finger, mode, quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
            table[finger] = (mode, best, cost)
    palm = scene.field(hand, hand.points(hand.part["palm"]), hand.part["palm"])
    total += abs(palm.min() - TARGET) + 100.0 * relu(-palm.min() - TOL)
    table["palm"] = palm.min()
    return total, table


def seat_from(scene, params):
    """The seat moved from the old one: metres along the gun's own axes, then degrees about them."""
    d = np.eye(4)
    d[:3, 3] = params[:3]
    d[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    # The hand turns at the wrist by what the seat turned, so the barrel keeps the old seat's line in the forearm.
    r0 = scene.seat0[:3, :3]
    scene.right.wrist = r0 @ d[:3, :3].T @ r0.T
    scene.right._apply_all()
    return scene.seat0 @ d


X, Y, Z = np.eye(3)


def settle(scene, params):
    """Moves the gun across the palm (its own Z) until the palm's skin is TARGET off it; returns the params."""
    params = np.array(params, float)

    def gap(z):
        params[2] = z
        scene.seat = seat_from(scene, params)
        return scene.field(scene.right, scene.right.points(scene.right.part["palm"])).min() - TARGET

    low, high = -0.01, 0.08
    for _ in range(24):
        mid = 0.5 * (low + high)
        if gap(mid) > 0:
            high = mid
        else:
            low = mid
    params[2] = high
    return params


def scan(scene, lists):
    scene.right.stride = 3
    r = scene.rig
    for combo in itertools.product(*lists):
        p = settle(scene, list(combo))
        total, table = seat_score(scene, p)
        row = " ".join(f"{f[:3]} {table[f][2] * 1000:.1f}" for f in FINGERS)
        g = scene.right.glob
        knuckle = scene.to_gun(g[r.index["index_01_r"]][:3, 3][None])[0]
        thumb = scene.to_gun(g[r.index["thumb_01_r"]][:3, 3][None])[0]
        wrist = np.degrees(np.arccos(np.clip((np.trace(scene.right.wrist) - 1) / 2, -1, 1)))
        print(
            "{} dz {:.4f} total {:.1f} | {} | palm {:.1f} | index knuckle {} thumb root {} wrist {:.0f}".format(
                np.round(p[[0, 1, 3, 4, 5]], 3),
                p[2],
                total * 1000,
                row,
                table["palm"] * 1000,
                np.round(knuckle, 3),
                np.round(thumb, 3),
                wrist,
            ),
            flush=True,
        )


def seat_score(scene, params, quick=True):
    scene.seat = seat_from(scene, params)
    for finger in FINGERS:
        scene.right.angles[finger][:] = 0.0
    scene.right._apply_all()
    total, table = close_right(scene, quick)
    r = scene.rig
    root = scene.to_gun(scene.right.glob[r.index["thumb_01_r"]][:3, 3][None])[0]
    total += 0.2 * relu(WEB_Y - root[1])
    # The wrist turns by what the seat turned: past 30 degrees it costs.
    wrist = np.degrees(np.arccos(np.clip((np.trace(scene.right.wrist) - 1) / 2, -1, 1)))
    total += 1e-3 * relu(wrist - 30.0)
    table["wrist"] = wrist
    return total, table


def search_seat(scene, start, rounds, quick=True):
    best = np.array(start, float)
    best_cost, _ = seat_score(scene, best, quick)
    print("seat start", np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    for step_m, step_deg in rounds:
        improved = True
        while improved:
            improved = False
            for k in range(6):
                for sign in (-1.0, 1.0):
                    cand = best.copy()
                    cand[k] += sign * (step_m if k < 3 else step_deg)
                    if k >= 3 and abs(cand[k]) > 40.0:
                        continue
                    cost, _ = seat_score(scene, cand, quick)
                    if cost < best_cost - 1e-6:
                        best, best_cost, improved = cand, cost, True
            print("  step", step_m, step_deg, np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    return best, best_cost


MIRROR_GUN = np.diag([1.0, 1.0, -1.0])
MIRROR_BONE = np.diag([-1.0, 1.0, 1.0])
LEFT_PIVOT = np.array([-0.03, 0.0, 0.0])


def place_left(scene, params):
    """Puts the left hand on the gun: the right hand's place mirrored, then moved by `params` (gun axes)."""
    right_in_gun = np.linalg.inv(scene.seat)
    mirrored = np.eye(4)
    mirrored[:3, :3] = MIRROR_GUN @ right_in_gun[:3, :3] @ MIRROR_BONE
    mirrored[:3, 3] = MIRROR_GUN @ right_in_gun[:3, 3]
    turn = np.eye(4)
    turn[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    turn[:3, 3] = LEFT_PIVOT - turn[:3, :3] @ LEFT_PIVOT + np.array(params[:3])
    in_gun = turn @ mirrored
    hand = scene.left
    hand.move = np.eye(4)
    hand._apply_all()
    hand.move = scene.gun_global() @ in_gun @ np.linalg.inv(hand.hand_global())
    hand._apply_all()
    return in_gun


def close_left(scene, quick=False):
    hand = scene.left
    total = 0.0
    table = {}
    for _ in range(1 if quick else 2):
        total = 0.0
        for finger in FINGERS:
            mode = "thumb" if finger == "thumb" else "over"
            best, cost = solve_finger(scene, hand, finger, mode, quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
            table[finger] = (mode, best, cost)
    # The heel of the palm fills the side of the grip the shooting hand leaves open: the palm is on the
    # gun itself, not only on the other hand's fingertips.
    to_gun, to_hand = scene.palm(hand)
    low = min(to_gun.min(), to_hand.min())
    total += abs(low - TARGET) + 100.0 * relu(-low - TOL) + 0.5 * relu(to_gun.min() - OVER_NEAR)
    idx = hand.part["palm"]
    vertex_low = scene.field(hand, hand.points()[idx], idx).min()
    total += PALM_WEIGHT * (relu(vertex_low - PALM_OFF) + relu(PALM_NEAR - vertex_low))
    table["palm vertices"] = vertex_low
    table["palm"] = low
    table["heel on the gun"] = to_gun.min()
    return total, table


def left_score(scene, params, quick=True):
    in_gun = place_left(scene, params)
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    scene.left._apply_all()
    total, table = close_left(scene, quick)
    cant = left_cant(scene)
    # A degree of cant outside the taught range costs 2 mm (at 0.3 mm the female prototype's search turned the
    # hand to 51 degrees for fingertips that then lay off the right hand), a millimetre of reach the arm lacks
    # a millimetre.
    total += 2e-3 * (relu(CANT[0] - cant) + relu(cant - CANT[1]))
    total += relu(max(over for _, _, over in reach(scene, in_gun)) + REACH_SPARE)
    table["cant"] = cant
    return total, table


def left_cant(scene):
    """How far the left hand is canted, in degrees: the angle of its knuckle line (index to little finger)
    from the gun's own down, toward the gun's back. 0 is a hand held like the right one mirrored; a support
    hand is taught at about 45, its wrist bent forward so that the thumb points at the target."""
    rig, hand = scene.rig, scene.left
    index = scene.to_gun(hand.glob[rig.index["index_01_l"]][:3, 3][None])[0]
    little = scene.to_gun(hand.glob[rig.index["pinky_01_l"]][:3, 3][None])[0]
    return np.degrees(np.arctan2(little[0] - index[0], index[1] - little[1]))


def search_left(scene, start, rounds):
    best = np.array(start, float)
    best_cost, _ = left_score(scene, best)
    print("left start", np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    for step_m, step_deg in rounds:
        improved = True
        while improved:
            improved = False
            for k in range(6):
                for sign in (-1.0, 1.0):
                    cand = best.copy()
                    cand[k] += sign * (step_m if k < 3 else step_deg)
                    cost, _ = left_score(scene, cand)
                    if cost < best_cost - 1e-6:
                        best, best_cost, improved = cand, cost, True
            print("  left step", step_m, step_deg, np.round(best, 4), f"cost {best_cost:.5f}", flush=True)
    return best


def put_left(scene, in_gun):
    """Moves the left hand, as its fingers are, to a place given in the gun."""
    hand = scene.left
    hand.move = np.eye(4)
    hand._apply_all()
    hand.move = scene.gun_global() @ in_gun @ np.linalg.inv(hand.hand_global())
    hand._apply_all()


def place_magazine(scene, support, params):
    """Puts the left hand under the magazine: its place on the gun (`support`, in the gun) turned and moved by
    `params` (gun axes, about the middle of the magazine's base), then pushed up the gun's Y from below until
    the palm's skin is TARGET off a surface."""
    turn = np.eye(4)
    turn[:3, :3] = R.axis_angle(X, params[3]) @ R.axis_angle(Y, params[4]) @ R.axis_angle(Z, params[5])
    turn[:3, 3] = MAGAZINE_BASE - turn[:3, :3] @ MAGAZINE_BASE + np.array(params[:3])
    start = turn @ support
    hand = scene.left
    palm = hand.part["palm"]

    def put(lift):
        in_gun = start.copy()
        in_gun[1, 3] += lift
        put_left(scene, in_gun)
        return in_gun

    def gap(lift):
        put(lift)
        return scene.field(hand, hand.points(palm), palm).min() - TARGET

    # Up from well below in 1 mm steps to the first touch (past the gun the palm is clear again, so no
    # bisection over the whole way), then to the place between the last two steps.
    low = -0.15
    while low < 0.1 and gap(low + 0.001) > 0:
        low += 0.001
    high = low + 0.001
    for _ in range(12):
        mid = 0.5 * (low + high)
        if gap(mid) > 0:
            low = mid
        else:
            high = mid
    return put(low)


def close_magazine(scene, quick=False):
    hand = scene.left
    total = 0.0
    for _ in range(1 if quick else 2):
        total = 0.0
        for finger in FINGERS:
            best, cost = solve_finger(scene, hand, finger, "cup", quick, hand.angles[finger])
            hand.set(finger, best)
            total += cost
    return total


def reach(scene, in_gun):
    """How far past the left arm's length the left hand's place is from the left shoulder, in metres (negative:
    the arm has that much to spare), for each mannequin (their arms differ above the hands) in every dumped
    aim and shoot pose and where the reload clip starts and ends with both hands on the gun. Rows of
    (mannequin, pose, metres). The game does not hold the right arm out (`WeaponHold.carry_arm_out`) while
    a reload plays: that took the gun 13 mm out of the male mannequin's reach."""
    rows = []
    for model, rig in scene.rigs.items():
        arm = np.linalg.norm(rig.rest[rig.index["lowerarm_l"]][:3, 3]) + np.linalg.norm(
            rig.rest[rig.index["hand_l"]][:3, 3]
        )
        hand = rig.index["hand_r"]
        for name, pose in rig.poses.items():
            reload = name.endswith("Pistol_Reload@0.00")
            if "Aim" not in name and "Shoot" not in name and not reload:
                continue
            local = pose.copy()
            local[hand][:3, :3] = local[hand][:3, :3] @ scene.right.wrist
            g = rig.fk(local)
            target = (g[hand] @ scene.seat @ in_gun)[:3, 3]
            shoulder = g[rig.index["upperarm_l"]][:3, 3]
            rows.append((model, name.split("/")[1], np.linalg.norm(target - shoulder) - arm))
    return rows


def report(scene, hand, tag):
    pts = hand.points()
    sd = scene.field(hand, pts)
    model = scene.rig.model[hand.ids]
    for which, name in enumerate(model_names()):
        line = []
        for part, idx in hand.part.items():
            line.append(f"{part} {sd[idx[model[idx] == which]].min() * 1000.0:.1f}")
        print(tag, name, ", ".join(line), flush=True)


def option(name, default):
    """The numbers of `--name=a,b,...` on the command line, or `default`."""
    for argument in sys.argv:
        if argument.startswith(f"--{name}="):
            return [float(value) for value in argument.split("=", 1)[1].split(",")]
    return default


def body_option():
    """The body of `--body=<name>` on the command line (`female` by default), or `both`."""
    for argument in sys.argv:
        if argument.startswith("--body="):
            return argument.split("=", 1)[1]
    return "female"


def model_names():
    """The names of the models the solver's rig carries, in the order of `Rig.model`."""
    body = body_option()
    return ("female", "male") if body == "both" else (body,)


def main():
    rigs, pistol = R.load(sys.argv[1])
    body = body_option()
    rig = R.merged(rigs["female"], rigs["male"]) if body == "both" else rigs[body]
    scene = Scene(rig, pistol, sys.argv[1] + f".{body}.gun.npz")
    scene.rigs = {name: rigs[name] for name in model_names()}
    scene.parts = pistol.get("parts", {})
    started = time.time()
    for argument in sys.argv:
        if argument.startswith("--scan="):
            scan(scene, [[float(v) for v in part.split(",")] for part in argument[7:].split(";")])
            return
    rounds = [(0.008, 4.0), (0.004, 2.0), (0.002, 1.0), (0.001, 0.5)]
    if "--magazine-only" in sys.argv:
        magazine_only(scene, started)
        return
    if "--way-only" in sys.argv:
        way_only(scene, started)
        return
    if "--carry-only" in sys.argv:
        carry_only(scene, started)
        return
    if "--thumb-only" in sys.argv:
        thumb_only(scene, started)
        return
    if "--left-only" in sys.argv:
        out = restore(scene)
    else:
        out = solve_right(scene, rounds, started)
    # The file is written after every stage: a run that is stopped keeps what it solved, and
    # `--magazine-only` and `--way-only` go on from there.
    out.update(solve_left(scene, out, rounds, started))
    save(out)
    out.update(solve_trigger_way(scene, out, started))
    save(out)
    if "--hold-only" not in sys.argv:
        out.update(solve_magazine(scene, out, place_left(scene, MAGAZINE_FROM), started))
        save(out)
        out.update(solve_way(scene, out, started))
        save(out)
        out.update(solve_carry(scene, out, started))
        save(out)


def save(out):
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())


def solve_right(scene, rounds, started):
    """The seat and the right hand: its fingers round the grip, the index finger along the frame and on the
    trigger."""
    best = settle(scene, option("seat", SEAT))
    if "--search-seat" in sys.argv:
        scene.right.stride = 3
        best, _ = search_seat(scene, best, rounds)
        scene.right.stride = 1
    scene.seat = seat_from(scene, best)
    for finger in FINGERS:
        scene.right.angles[finger][:] = 0.0
    scene.right._apply_all()
    total, table = close_right(scene, quick=False, trigger=False)
    grip = scene.right.quaternions()
    angles = {finger: scene.right.angles[finger].tolist() for finger in FINGERS}
    report(scene, scene.right, "right (frame)")
    on_trigger, _ = solve_finger(scene, scene.right, "index", "trigger", False)
    scene.right.set("index", on_trigger)
    trigger = scene.right.quaternions(["index"])
    report(scene, scene.right, "right (trigger)")
    scene.right.set("index", angles["index"])
    for finger, row in table.items():
        print(" ", finger, row)
    print(
        "seat",
        np.round(best, 4).tolist(),
        "right total %.2f mm" % (total * 1000),
        "in %.0f s" % (time.time() - started),
        flush=True,
    )
    return {
        "angles": {"right": angles, "trigger": on_trigger.tolist()},
        "seat_params": best.tolist(),
        "seat": scene.seat.tolist(),
        "wrist": R.mat_to_quat(scene.right.wrist).tolist(),
        "grip": grip,
        "trigger": trigger,
    }


def restore(scene):
    """The seat and the right hand of the solve in the output file, the index finger along the frame."""
    with open(sys.argv[2], "rb") as file:
        out = json.load(file)
    scene.seat = seat_from(scene, np.array(out["seat_params"]))
    for finger in FINGERS:
        scene.right.angles[finger] = np.array(out["angles"]["right"][finger], float)
    scene.right._apply_all()
    return out


def index_poses(out, way=True):
    """The poses of the trigger finger other than along the frame, for `Scene.freeze`: on the trigger and,
    once it is solved, half-way there."""
    poses = [("index", np.array(out["angles"]["trigger"]))]
    if way and "trigger_way" in out["angles"]:
        poses.append(("index", np.array(out["angles"]["trigger_way"])))
    return poses


def solve_left(scene, out, rounds, started):
    """The two hands together (kit #1084). The left hand's place and fingers are solved on the gun and over
    the right hand, whose trigger finger is along the frame or on the trigger and whose thumb is left out;
    the right thumb is then laid on the root of the left one; and the left hand's fingers are closed once
    more on the right hand as it then is. Each hand is measured against the other, not only the left
    against the right."""
    hand = scene.left
    scene.frozen.clear()
    scene.freeze(scene.right, index_poses(out, way=False), without=("thumb",))
    left = np.array(option("left", LEFT))
    if "--search-left" in sys.argv:
        hand.stride = 3
        left = search_left(scene, left, rounds)
        hand.stride = 1
    in_gun = place_left(scene, left)
    for finger in FINGERS:
        hand.angles[finger][:] = 0.0
    hand._apply_all()
    close_left(scene)
    # The right thumb on the left hand, then the left hand once more against the whole right hand.
    carried = scene.right.angles["thumb"].copy()
    over, thumb = solve_thumb_over(scene, carried)
    scene.freeze(scene.right, index_poses(out, way=False))
    total, left_table = close_left(scene)
    report(scene, hand, "left")
    for finger, row in left_table.items():
        print(" ", finger, row)
    scene.freeze(hand)
    report(scene, scene.right, "right (over the left)")
    scene.frozen.pop("l")
    scene.right.set("thumb", carried)
    rows = reach(scene, in_gun)
    worst = max(rows, key=lambda row: row[2])
    print(f"left arm: the least to spare is {-worst[2] * 1000:.1f} mm ({worst[0]}, {worst[1]})")
    print(
        "left",
        np.round(left, 4).tolist(),
        "total %.2f mm" % (total * 1000),
        "in %.0f s" % (time.time() - started),
        flush=True,
    )
    out["angles"]["left"] = {finger: hand.angles[finger].tolist() for finger in FINGERS}
    out["angles"]["thumb_over"] = over.tolist()
    return {
        "left_params": left.tolist(),
        "support_hand": in_gun.tolist(),
        "support": hand.quaternions(),
        "thumb": thumb,
    }


def solve_thumb_over(scene, carried):
    """The right thumb laid on the left hand as it holds (frozen here, then let go): the angles, the bones'
    rotations, and how deep the thumb's blend from `carried` passes through the gun alone (the left hand
    is out at the far end of its way while the thumb moves)."""
    scene.freeze(scene.left)
    scene.thumb_from = carried
    over, _ = solve_finger(scene, scene.right, "thumb", "thumb_over", False, carried, wide=6000)
    scene.thumb_from = None
    shares = np.linspace(0.0, 1.0, TRIGGER_STEPS + 1)
    turned = [
        blended(a[0], b, shares)
        for a, b in zip(local_rotations("thumb", carried), local_rotations("thumb", over[None]), strict=True)
    ]
    passes = -scene.gun(scene.to_gun(scene.right.finger_points_turned("thumb", turned))).min()
    print("right thumb", np.round(carried, 1), "to", np.round(over, 1), "passes the gun %.1f mm" % (passes * 1000))
    scene.right.set("thumb", over)
    thumb = scene.right.quaternions(["thumb"])
    report(scene, scene.right, "right (thumb over)")
    scene.frozen.pop("l")
    return over, thumb


def thumb_only(scene, started):
    """Solves only the right thumb's pose on the left hand, on the two hands of the solve in the output file,
    and adds it to that file; run `--way-only` after it (the way's far end clears the moving thumb)."""
    out = restore(scene)
    hand = scene.left
    held = hand.angles_of(out["support"])
    for finger in FINGERS:
        hand.angles[finger] = held[finger].copy()
    put_left(scene, np.array(out["support_hand"]))
    carried = scene.right.angles["thumb"].copy()
    over, out["thumb"] = solve_thumb_over(scene, carried)
    out["angles"]["thumb_over"] = over.tolist()
    scene.freeze(scene.right, index_poses(out, way=False))
    report(scene, hand, "left")
    scene.right.set("thumb", carried)
    print("thumb in %.0f s" % (time.time() - started), flush=True)
    save(out)


def both_hands(scene, out):
    """Puts the right hand as it is while the left one holds too: the thumb on the left hand."""
    for finger in FINGERS:
        scene.right.angles[finger] = np.array(out["angles"]["right"][finger], float)
    scene.right.angles["thumb"] = np.array(out["angles"]["thumb_over"], float)
    scene.right._apply_all()


def blended(start, ends, shares):
    """Rotations between `start` (3, 3) and each of `ends` (K, 3, 3) at `shares` (S,), the short way round as
    Godot's `Quaternion.slerp` goes: (K * S, 3, 3), a row of `ends` after the other."""
    first = Rotation.from_matrix(start).as_quat()
    last = Rotation.from_matrix(ends).as_quat()
    dot = last @ first
    last = np.where(dot[:, None] < 0.0, -last, last)
    angle = np.arccos(np.clip(np.abs(dot), 0.0, 1.0))[:, None, None]
    share = np.asarray(shares)[None, :, None]
    near = angle < 1e-6
    sine = np.where(near, 1.0, np.sin(angle))
    from_start = np.where(near, 1.0 - share, np.sin((1.0 - share) * angle) / sine)
    from_end = np.where(near, share, np.sin(share * angle) / sine)
    mixed = from_start * first[None, None, :] + from_end * last[:, None, :]
    return Rotation.from_quat(mixed.reshape(-1, 4)).as_matrix()


def open_grid(finger, held):
    """The poses a finger may open to from `held`: the knuckle straighter, the other joints either way."""
    limits = LIMITS.get(finger, LIMITS["finger"])
    if finger == "thumb":
        steps = [-16.0, -8.0, 0.0, 8.0, 16.0]
        grid = [
            held + np.array([a, b, c, 0.0, e, 0.0]) for a in steps for b in steps for c in steps for e in (-10.0, 0.0)
        ]
    else:
        grid = itertools.product(
            held[0] + np.array([-10.0, -5.0, 0.0, 5.0, 10.0]),
            np.arange(held[1] % 5.0 - 15.0, held[1] + 0.1, 5.0),
            np.append(np.arange(held[2] % 15.0, held[2] + 0.1, 15.0), [held[2] + 11.5, held[2] + 23.0]),
            np.append(np.arange(held[3] % 20.0, held[3] + 0.1, 20.0), [held[3] + 20.0]),
        )
    return np.clip(np.array(list(grid), float), limits[:, 0], limits[:, 1])


def open_finger(scene, hand, finger, then=None):
    """Opens one finger of a hand that holds: the pose nearest the held one that lifts it `OPEN_CLEAR` off
    every surface (or as far as it gets) with nothing deeper than `WAY_TOL` in every pose between, the bones
    blended as the game blends them. With `then` (a pose's angles the finger goes on to from the opened one, as the
    carry's fingers go on to the pose under the magazine), the way from the opened pose to it is held to the same
    depth: a pose clear of the way there only left the female body's index fingertip to cross 3.9 mm of the
    magazine's corner on the way on. Returns the angles, the deepest on the way and how far off it ends."""
    held = hand.angles[finger].copy()
    grid = open_grid(finger, held)
    shares = np.linspace(0.0, 1.0, WAY_STEPS + 1)[1:]
    which = hand.finger_verts[finger]
    deepest = np.empty(len(grid))
    clear = np.empty(len(grid))
    # A few hundred poses at a time: every pose is measured at every share on every vertex.
    for first in range(0, len(grid), 400):
        rows = grid[first : first + 400]
        turned = [
            blended(a[0], b, shares)
            for a, b in zip(local_rotations(finger, held), local_rotations(finger, rows), strict=True)
        ]
        off = scene.field(hand, hand.finger_points_turned(finger, turned), which)
        off = off.reshape(len(rows), len(shares), -1)
        deepest[first : first + 400] = off.min(axis=(1, 2))
        clear[first : first + 400] = off[:, -1].min(axis=1)
        if then is not None:
            onward = [
                blended(a[0], b, 1.0 - shares)
                for a, b in zip(local_rotations(finger, then), local_rotations(finger, rows), strict=True)
            ]
            off = scene.field(hand, hand.finger_points_turned(finger, onward), which)
            passing = off.reshape(len(rows), -1).min(axis=1)
            deepest[first : first + 400] = np.minimum(deepest[first : first + 400], passing)
    # A degree of change costs 0.03 mm, so the nearest pose that is clear enough wins.
    cost = 100.0 * relu(-deepest - WAY_TOL) + relu(OPEN_CLEAR - clear) + 3e-5 * np.abs(grid - held).sum(axis=1)
    best = cost.argmin()
    return grid[best], deepest[best], clear[best]


def trigger_grid(frame, trigger):
    """The poses the trigger finger may pass through between `frame` and `trigger`: every lean and bend from
    one to the other and some past them (it may curl in or straighten to get by)."""
    spans = []
    for index, (low, high, step) in enumerate(
        ((0.0, 0.0, 4.0), (10.0, 10.0, 6.0), (10.0, 30.0, 8.0), (0.0, 20.0, 10.0))
    ):
        first, last = sorted((frame[index], trigger[index]))
        spans.append(np.arange(first - low, last + high + 0.1, step))
    limits = LIMITS["index"]
    return np.clip(np.array(list(itertools.product(*spans)), float), limits[:, 0], limits[:, 1])


def trigger_depths(scene, frame, via, trigger, steps=TRIGGER_STEPS):
    """How far off the gun and off the left hand the trigger finger's skin is at each of `steps` equal parts
    of its way from `frame` through each row of `via` to `trigger` (angles), the bones blended as the game
    blends them: two (K, steps + 1, N)."""
    hand = scene.right
    which = hand.finger_verts["index"][:: hand.stride]
    half = np.linspace(0.0, 1.0, steps // 2 + 1)
    gun, other = [], []
    for first in range(0, len(via), 400):
        rows = via[first : first + 400]
        legs = [], []
        for end, shares in ((frame, half), (trigger, half[::-1][1:])):
            turned = [
                blended(a[0], b, shares)
                for a, b in zip(local_rotations("index", end), local_rotations("index", rows), strict=True)
            ]
            both = scene.distances(hand, hand.finger_points_turned("index", turned), which)
            for leg, off in zip(legs, both, strict=True):
                leg.append(off.reshape(len(rows), len(shares), -1))
        gun.append(np.concatenate(legs[0], axis=1))
        other.append(np.concatenate(legs[1], axis=1))
    return np.concatenate(gun), np.concatenate(other)


def solve_trigger_way(scene, out, started):
    """The trigger finger's way between the frame and the trigger (kit #1079), against the gun and the left
    hand where it holds: the pose it passes through half-way. The straight blend leaves the trigger guard on
    the gun's far side, through the left thumb. The way chosen passes no deeper than `WAY_TOL` through the
    left hand at any twentieth, and as little as it can through the gun: the mannequin's finger is as thick
    as the guard's opening is long (20 mm in 21), so on its way in it grazes the guard's front strut
    whichever way it goes (3.6 mm at best, with the knuckle free to 40 degrees back too)."""
    hand = scene.right
    frame = np.array(out["angles"]["right"]["index"])
    trigger = np.array(out["angles"]["trigger"])
    both_hands(scene, out)
    scene.freeze(scene.left)

    def cost(via):
        gun, other = trigger_depths(scene, frame, via, trigger)
        travel = np.abs(via - frame).sum(axis=1) + np.abs(via - trigger).sum(axis=1)
        # The search measures every third vertex and keeps 0.4 mm in hand, as a finger's does. The other
        # hand comes first: a millimetre through it costs ten through the gun.
        through_hand = relu(-other.min(axis=(1, 2)) - (WAY_TOL - 0.0004))
        through_gun = relu(-gun.min(axis=(1, 2)) - (WAY_TOL - 0.0004))
        return 1000.0 * through_hand + 100.0 * through_gun + 3e-5 * travel

    straight = [-off.min() * 1000 for off in trigger_depths(scene, frame, 0.5 * (frame + trigger)[None], trigger)]
    hand.stride = 3
    grid = trigger_grid(frame, trigger)
    costs = cost(grid)
    best, best_cost = grid[costs.argmin()], costs.min()
    rng = np.random.default_rng(1)
    limits = LIMITS["index"]
    for scale in (4.0, 2.0, 1.0, 0.5):
        for _ in range(3):
            steps = np.concatenate([np.eye(4), -np.eye(4), rng.integers(-1, 2, size=(200, 4))])
            cands = np.clip(best + scale * steps, limits[:, 0], limits[:, 1])
            costs = cost(cands)
            if costs.min() < best_cost:
                best, best_cost = cands[costs.argmin()], costs.min()
    hand.stride = 1
    gun, other = trigger_depths(scene, frame, best[None], trigger)
    model = scene.rig.model[hand.ids][hand.finger_verts["index"]]
    models = range(scene.rig.model.max() + 1)
    passes_gun = [float(-gun[0][:, model == index].min()) for index in models]
    passes_hand = [float(-other[0][:, model == index].min()) for index in models]
    hand.set("index", best)
    via = hand.quaternions(["index"])
    for finger in FINGERS:
        hand.set(finger, out["angles"]["right"][finger])
    print(
        "trigger way",
        np.round(frame, 1),
        "by",
        np.round(best, 1),
        "to",
        np.round(trigger, 1),
        "passes ({}) the left hand {} mm, the gun {} mm".format(
            ", ".join(model_names()),
            ", ".join(f"{d * 1000:.1f}" for d in passes_hand),
            ", ".join(f"{d * 1000:.1f}" for d in passes_gun),
        ),
        f"(straight: the left hand {straight[1]:.1f} mm, the gun {straight[0]:.1f} mm)",
        "in %.0f s" % (time.time() - started),
        flush=True,
    )
    out["angles"]["trigger_way"] = best.tolist()
    return {"trigger_way": via, "trigger_way_passes": {"hand": passes_hand, "gun": passes_gun}}


def directions(step):
    """Unit vectors `step` degrees apart over the whole sphere: (D, 3)."""
    out = [[0.0, 1.0, 0.0], [0.0, -1.0, 0.0]]
    for lift in np.radians(np.arange(-90.0 + step, 90.0, step)):
        for turn in np.radians(np.arange(0.0, 360.0, step / max(np.cos(lift), 0.2))):
            out.append([np.cos(lift) * np.cos(turn), np.sin(lift), np.cos(lift) * np.sin(turn)])
    return np.array(out)


def way_out(scene, toward, resting=None):
    """The straight line the opened left hand leaves the gun along, as a unit vector in the gun's space: of the
    directions in which nothing passes deeper than `WAY_TOL` over `WAY_LENGTH` (nor in the directions next
    to it, so a hand a little off the line is clear too), the one nearest `toward`. `resting` is the right
    hand frozen with its thumb everywhere between the frame and the left hand: the line's far end is clear
    of that too, since the thumb moves while the left hand waits there."""
    hand = scene.left
    points = hand.points()
    turn = scene.gun_global()[:3, :3]
    tried = directions(WAY_GRID)
    steps = np.linspace(0.0, WAY_LENGTH, WAY_STEPS + 1)
    deepest = np.empty(len(tried))
    for index, direction in enumerate(tried):
        moved = points[None] + steps[:, None, None] * (turn @ direction)[None, None, :]
        deepest[index] = scene.field(hand, moved).min()
    if resting is not None:
        held = scene.frozen["r"]
        scene.frozen["r"] = resting
        for index, direction in enumerate(tried):
            deepest[index] = min(deepest[index], scene.field(hand, points + WAY_LENGTH * (turn @ direction)).min())
        scene.frozen["r"] = held
    clear = deepest > -WAY_TOL
    near = tried @ tried.T > np.cos(np.radians(1.5 * WAY_GRID))
    safe = np.array([clear[near[index]].all() for index in range(len(tried))])
    if not safe.any():
        raise SystemExit("way_out: the opened hand passes through something in every direction")
    angle = np.degrees(np.arccos(np.clip(tried @ toward, -1.0, 1.0)))
    best = np.where(safe, angle, np.inf).argmin()
    return tried[best], angle[best], deepest[best], int(safe.sum())


def way_depths(scene, held, opened, way):
    """The deepest the left hand passes on its whole way off the gun, per mannequin, in metres: its fingers
    blended from `held` to `opened` (angles) where it holds, then the opened hand moved along `way`."""
    hand = scene.left
    model = scene.rig.model[hand.ids]
    shares = np.linspace(0.0, 1.0, 2 * WAY_STEPS + 1)
    deepest = np.zeros(scene.rig.model.max() + 1)

    def measure(points):
        off = scene.field(hand, points)
        for index in range(len(deepest)):
            deepest[index] = min(deepest[index], off[model == index].min())

    for share in shares:
        for finger in FINGERS:
            turned = [
                blended(a[0], b, [share])
                for a, b in zip(
                    local_rotations(finger, held[finger]), local_rotations(finger, opened[finger]), strict=True
                )
            ]
            for bone, rot in zip(hand.chains[finger], turned, strict=True):
                hand.local[bone][:3, :3] = scene.rig.rest[bone][:3, :3] @ rot[0]
        hand.glob = scene.rig.fk(hand.local)
        for bone in hand.arm:
            hand.glob[bone] = hand.move @ hand.glob[bone]
        measure(hand.points())
    points = hand.points()
    turn = scene.gun_global()[:3, :3]
    for share in shares:
        measure(points + share * WAY_LENGTH * (turn @ way))
    return -deepest


def solve_way(scene, out, started):
    """The left hand's way off the gun and back onto it, against the gun and the right hand with its trigger
    finger wherever it may be (along the frame, on the trigger, between: the hand comes on as the finger
    goes to the trigger): the opened pose and the line the opened hand leaves along."""
    both_hands(scene, out)
    scene.freeze(scene.right, index_poses(out))
    support = np.array(out["support_hand"])
    hand = scene.left
    held = hand.angles_of(out["support"])
    for finger in FINGERS:
        hand.angles[finger] = held[finger].copy()
    put_left(scene, support)
    opened = {}
    for finger in FINGERS:
        opened[finger], deepest, clear = open_finger(scene, hand, finger)
        print(
            "open",
            finger,
            np.round(held[finger], 1),
            "to",
            np.round(opened[finger], 1),
            f"passes {-deepest * 1000:.1f} mm, ends {clear * 1000:.1f} mm off",
            flush=True,
        )
    for finger in FINGERS:
        hand.set(finger, opened[finger])
    report(scene, hand, "open")
    # The way to the belt, from where the hand holds to where the clip has it there, in the gun.
    rig = scene.rig
    local = rig.poses[BELT_POSE].copy()
    local[scene.right.hand][:3, :3] = local[scene.right.hand][:3, :3] @ scene.right.wrist
    posed = rig.fk(local)
    belt = np.linalg.inv(posed[scene.right.hand] @ scene.seat) @ posed[hand.hand]
    toward = belt[:3, 3] - support[:3, 3]
    toward /= np.linalg.norm(toward)
    # The right thumb between the frame and the left hand, in quarters: it moves while the left hand waits
    # at the line's far end.
    carried = np.array(out["angles"]["right"]["thumb"])
    over = np.array(out["angles"]["thumb_over"])
    between = [("thumb", carried + share * (over - carried)) for share in (0.0, 0.25, 0.5, 0.75)]
    held_by = scene.frozen["r"]
    scene.freeze(scene.right, index_poses(out) + between)
    resting = scene.frozen["r"]
    scene.frozen["r"] = held_by
    way, off_line, deepest, count = way_out(scene, toward, resting)
    print(
        "way",
        np.round(way, 4).tolist(),
        "toward the belt",
        np.round(toward, 3).tolist(),
        f"{off_line:.0f} degrees off it, of {count} clear directions; passes {-deepest * 1000:.1f} mm",
    )
    quaternions = hand.quaternions()
    passes = way_depths(scene, held, opened, way)
    print(
        "way passes",
        ", ".join(f"{name} {depth * 1000:.1f} mm" for name, depth in zip(model_names(), passes, strict=False)),
        "in %.0f s" % (time.time() - started),
        flush=True,
    )
    return {"open": quaternions, "way": (WAY_LENGTH * way).tolist(), "way_passes": passes.tolist()}


def solve_magazine(scene, out, support, started):
    """The left hand under the magazine, against the gun and the right hand with its finger off the trigger."""
    for finger in FINGERS:
        scene.right.angles[finger] = np.array(out["angles"]["right"][finger], float)
    scene.right._apply_all()
    scene.freeze(scene.right)
    params = np.array(option("magazine", MAGAZINE))
    for finger in FINGERS:
        scene.left.angles[finger][:] = 0.0
    # The palm's skin near the knuckles follows the fingers: the hand is seated again under the closed fingers
    # and they are closed again there, three times.
    for _ in range(3):
        in_gun = place_magazine(scene, support, params)
        total = close_magazine(scene)
    report(scene, scene.left, "magazine")
    print(
        "magazine",
        np.round(params, 4).tolist(),
        "total %.2f mm" % (total * 1000),
        "in %.0f s" % (time.time() - started),
    )
    return {"magazine_params": params.tolist(), "magazine_hand": in_gun.tolist(), "magazine": scene.left.quaternions()}


def magazine_only(scene, started):
    """Solves only the left hand under the magazine, on the seat and the right hand of the solve in the output
    file, and adds it to that file."""
    out = restore(scene)
    out.update(solve_magazine(scene, out, place_left(scene, MAGAZINE_FROM), started))
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())


def way_only(scene, started):
    """Solves only the left hand's way off the gun, on the hold of the solve in the output file, and adds it
    to that file."""
    out = restore(scene)
    out.update(solve_way(scene, out, started))
    with open(sys.argv[2], "wb") as file:
        file.write(json.dumps(out, indent=1).encode())


def smoothstep(low, high, x):
    """Godot's `smoothstep`: 0 at `low`, 1 at `high`, eased between."""
    t = np.clip((x - low) / (high - low), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def solve_carry(scene, out, started):
    """The new magazine in the left hand (kit #1052): the fingers closed on the magazine where the hand holds it
    (the place under the magazine), measured against the magazine alone (the gun is far while it is carried),
    then the way in: the hand and the magazine up the grip's line together, the fingers going from the carry to
    the pose under the magazine over the latest shares of the way that keep every finger out of the gun, the
    right hand and the magazine on both mannequins."""
    hand = scene.left
    mag = np.array(scene.parts["Magazine"], float).reshape(-1, 3, 3)
    frame = np.concatenate(
        [np.array(tris, float).reshape(-1, 3, 3) for name, tris in scene.parts.items() if name != "Magazine"]
    )
    flat = mag.reshape(-1, 3)
    mag_field = hold_field.PiecesField(
        mag, flat.min(axis=0) - 0.06, flat.max(axis=0) + 0.06, 0.001, sys.argv[1] + ".magazine.npz"
    )
    frame_field = hold_field.PiecesField(frame, GRID_LOW, GRID_HIGH, 0.001, sys.argv[1] + ".frame.npz")
    up = scene.sockets["Grip"][:3, 1]
    approach = -CARRY_LENGTH * up / np.linalg.norm(up)
    in_gun = np.array(out["magazine_hand"], float)
    held = hand.angles_of({bone: np.array(q) for bone, q in out["magazine"].items()})
    if "--carry_trace" in sys.argv:
        print("held", {f: np.round(held[f], 1).tolist() for f in FINGERS}, flush=True)
    # The carry, against the magazine alone.
    kept = scene.gun, scene.frozen, scene.frozen_points
    scene.gun, scene.frozen, scene.frozen_points = mag_field, {}, {}
    for finger in FINGERS:
        hand.angles[finger] = held[finger].copy()
    put_left(scene, in_gun)
    if "--carry-open-only" in sys.argv or option("carry_spans", []):
        for finger in FINGERS:
            hand.set(finger, out["carry_angles"][finger])
    if "--carry-open-only" in sys.argv:
        result = carry_open(scene, hand, held)
        scene.gun, scene.frozen, scene.frozen_points = kept
        return result
    if option("carry_spans", []):
        carry = {finger: np.array(out["carry_angles"][finger]) for finger in FINGERS}
        quaternions = out["carry"]
        opened = {key: out[key] for key in ("carry_open", "carry_open_angles")}
    else:
        # The palm's skin by the knuckles follows the fingers as they close (the first solve pressed it 3.5 mm
        # into the magazine): each finger is measured with the palm's vertices it moves too, for depth only.
        own = dict(hand.finger_verts)
        chains = {finger: hand.chains[finger] for finger in FINGERS}
        for finger in FINGERS:
            moved = (np.isin(scene.rig.vbones[hand.ids], chains[finger]) * scene.rig.vweights[hand.ids]).sum(axis=1)
            palm = np.where((scene.rig.main[hand.ids] == hand.hand) & (moved > 0.05))[0]
            hand.finger_verts[finger] = np.concatenate([own[finger], palm])
        for _ in range(2):
            for finger in FINGERS:
                best, _ = solve_finger(scene, hand, finger, "carry", False, hand.angles[finger], wide=2000)
                hand.set(finger, best)
        hand.finger_verts = own
        report(scene, hand, "carry")
        opened = carry_open(scene, hand, held)
        # A finger hooked round the magazine that cannot let go of it clear on the way to the pose under the
        # magazine (the female prototype's index finger crossed 2.2 to 3.9 mm of the magazine's corner whatever
        # pose it opened to) is closed again with its two end joints as that pose has them, so only its knuckle
        # moves between the two and the curled finger swings off the magazine as one piece.
        stuck = [f for f in FINGERS if f != "thumb" and opened["carry_open_passes"][f] > WAY_TOL]
        for finger in stuck:
            limits = LIMITS.get(finger, LIMITS["finger"])
            rows = np.array(
                [
                    [lean, knuckle, held[finger][2], held[finger][3]]
                    for lean in np.arange(limits[0, 0], limits[0, 1] + 0.1, 2.0)
                    for knuckle in np.arange(limits[1, 0], limits[1, 1] + 0.1, 1.0)
                ]
            )
            cost, _ = finger_cost(scene, hand, finger, rows, "carry")
            hand.set(finger, rows[cost.argmin()])
            print("carry", finger, "closed again from the knuckle:", np.round(hand.angles[finger], 1), flush=True)
        if stuck:
            report(scene, hand, "carry")
            opened = carry_open(scene, hand, held)
        carry = {finger: hand.angles[finger].copy() for finger in FINGERS}
        quaternions = hand.quaternions()
    scene.gun, scene.frozen, scene.frozen_points = kept
    if "--carry-pose-only" in sys.argv:
        return {"carry": quaternions, "magazine_approach": approach.tolist(), **opened}
    # The way in, against the gun without its magazine, the right hand and the magazine as it moves.
    for finger in FINGERS:
        scene.right.angles[finger] = np.array(out["angles"]["right"][finger], float)
    scene.right._apply_all()
    scene.freeze(scene.right)
    model = scene.rig.model[hand.ids]

    part_of = np.empty(len(hand.ids), object)
    for name, index in hand.part.items():
        part_of[index] = name

    loose = {finger: np.array(opened["carry_open_angles"][finger]) for finger in FINGERS}

    def deepest(span, where=None):
        """The deepest any skin passes on the way in with the fingers changing over `span`, per mannequin: they
        open off the magazine over its first half (`carry_open`) and go to the pose under the magazine over the
        second, as the game blends them. `where` (a list) gets the share, the part and what it passes into."""
        worst = np.zeros(model.max() + 1)
        middle = 0.5 * (span[0] + span[1])
        for share in np.linspace(0.0, 1.0, CARRY_STEPS + 1):
            loosened = smoothstep(span[0], middle, share)
            weight = 1.0 - smoothstep(middle, span[1], share)
            for finger in FINGERS:
                turned = [
                    blended(a[0], blended(c[0], o, [loosened]), [weight])
                    for a, c, o in zip(
                        local_rotations(finger, held[finger]),
                        local_rotations(finger, carry[finger]),
                        local_rotations(finger, loose[finger]),
                        strict=True,
                    )
                ]
                for bone, rot in zip(hand.chains[finger], turned, strict=True):
                    hand.local[bone][:3, :3] = scene.rig.rest[bone][:3, :3] @ rot[0]
            place = in_gun.copy()
            place[:3, 3] += approach * (1.0 - share)
            hand.glob = scene.rig.fk(hand.local)
            hand.move = scene.gun_global() @ place @ np.linalg.inv(hand.glob[hand.hand])
            for bone in hand.arm:
                hand.glob[bone] = hand.move @ hand.glob[bone]
            points = hand.points()
            at = scene.to_gun(points)
            into = {
                "frame": frame_field(at),
                "magazine": mag_field(at - approach * (1.0 - share)),
                "right hand": scene.distances(hand, points)[1],
            }
            off = np.minimum.reduce(list(into.values()))
            if "--carry_trace" in sys.argv:
                row = []
                for name in ("index_tip", "index_mid", "middle_tip", "ring_tip", "thumb_tip", "thumb_mid", "palm"):
                    low = hand.part[name][off[hand.part[name]].argmin()]
                    row.append(f"{name} {off[low] * 1e3:.1f} {min(into, key=lambda n, at=low: into[n][at])}")
                print("trace", round(float(share), 3), "; ".join(row), flush=True)
            for index in range(len(worst)):
                mine = np.where(model == index)[0]
                low = mine[off[mine].argmin()]
                if off[low] < worst[index]:
                    worst[index] = off[low]
                    if where is not None:
                        what = min(into, key=lambda name: into[name][low])
                        where.append((index, round(float(share), 3), part_of[low], what, round(off[low] * 1e3, 1)))
        return -worst

    # The spans tried: `--carry_spans=a,b,c,d,...` (pairs, the solve's own as a start), or every pair of shares
    # `CARRY_SHARES` apart.
    listed = option("carry_spans", [])
    spans = [(listed[k], listed[k + 1]) for k in range(0, len(listed) - 1, 2)]
    if not spans:
        steps = np.arange(0.0, 1.0 + 1e-6, CARRY_SHARES)
        spans = [(a, b) for a in steps for b in steps if b > a + 1e-6]
    tried = []
    for start, end in spans:
        where = []
        depth = deepest((start, end), where)
        tried.append(((round(float(start), 2), round(float(end), 2)), depth))
        print("carry way", tried[-1][0], "passes", np.round(depth * 1000.0, 1), "mm; deepest", where[-2:], flush=True)
    # Clear: no deeper than `WAY_TOL`, or than the least of them all (the pose under the magazine itself
    # presses the right hand 1.1 mm at the end of the way, whenever the fingers change).
    floor = min(entry[1].max() for entry in tried)
    clear = [entry for entry in tried if entry[1].max() <= max(WAY_TOL, floor + 0.0001)]
    # The latest change that is clear: the fingers hold the magazine as long as they can.
    if clear:
        span, depth = max(clear, key=lambda entry: (entry[0][1], entry[0][0]))
    else:
        span, depth = min(tried, key=lambda entry: entry[1].max())
    print(
        "carry: the fingers change over",
        span,
        "of the way in, passing",
        np.round(depth * 1000.0, 1),
        "mm deep at most, in %.0f s" % (time.time() - started),
        flush=True,
    )
    return {
        "carry": quaternions,
        "carry_angles": {finger: carry[finger].tolist() for finger in FINGERS},
        "magazine_approach": approach.tolist(),
        "carry_release": list(span),
        "carry_passes": depth.tolist(),
        **opened,
    }


def carry_open(scene, hand, then=None):
    """The hand at the belt opened before it closes on the new magazine (the clip's fist there is closed
    tighter than the carry and would close through it): each finger the nearest pose to the carry that lifts it
    off the magazine with nothing in it on the way, as the game blends it, nor on the way on from it to `then`
    (the pose under the magazine: the magazine is where it was in the hand). The hand's fingers are the carry's
    and the scene measures the magazine alone; they are put back afterwards."""
    carry = {finger: hand.angles[finger].copy() for finger in FINGERS}
    angles = {}
    passes = {}
    for finger in FINGERS:
        angles[finger], deepest, clear = open_finger(scene, hand, finger, None if then is None else then[finger])
        passes[finger] = float(-deepest)
        print(
            "carry open",
            finger,
            np.round(carry[finger], 1),
            "to",
            np.round(angles[finger], 1),
            "passes %.1f mm, ends %.1f mm off" % (-deepest * 1000.0, clear * 1000.0),
            flush=True,
        )
    for finger in FINGERS:
        hand.set(finger, angles[finger])
    quaternions = hand.quaternions()
    for finger in FINGERS:
        hand.set(finger, carry[finger])
    opened = {"carry_open": quaternions, "carry_open_angles": {f: angles[f].tolist() for f in FINGERS}}
    return {**opened, "carry_open_passes": passes}


def carry_only(scene, started):
    """Solves only the new magazine in the left hand, on the hold of the solve in the output file, and adds it
    to that file."""
    out = restore(scene)
    out.update(solve_carry(scene, out, started))
    save(out)


if __name__ == "__main__":
    main()
