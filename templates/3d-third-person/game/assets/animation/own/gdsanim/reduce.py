"""Key reduction, checked against the full curve.

A clip is solved on every frame. Most of those keys say nothing a straight line between their neighbours does not:
the reducer drops them, track by track, and the result is then played back and compared with the full curve where
an error shows, at the hands, the feet and the head. When the reduced clip strays further than the limit the
tolerance is halved and the reduction run again, so the limit is met on the body and not only on each bone.
"""

import numpy as np

from . import maths

## The furthest the hands, the head and the feet of the reduced clip may be from the full curve's (m).
LIMIT = 0.001
## The furthest a planted sole point may be (m): a foot on the floor shows a smaller error than a hand in the air.
PLANTED_LIMIT = 0.0003
## The tolerance the reducer starts from (degrees on a rotation, metres on the pelvis's place) and the least it
## goes down to before the clip is written with every key.
START_DEG = 0.2
LEAST_DEG = 0.003
PLACE_TOLERANCE = 0.0001
## Where an error shows.
ENDS = ("hand_l", "hand_r", "middle_03_l", "middle_03_r", "Head", "foot_l", "foot_r", "ball_l", "ball_r")
FEET = ("foot_l", "foot_r", "ball_l", "ball_r")


def continuous(track: np.ndarray) -> np.ndarray:
    """A quaternion track with each key on its neighbour's side (no long way round between two keys)."""
    out = track.copy()
    for f in range(1, len(out)):
        if np.dot(out[f], out[f - 1]) < 0.0:
            out[f] = -out[f]
    return out


def keep_rotation(track: np.ndarray, tolerance_deg: float) -> np.ndarray:
    """The frames of a rotation track a linear reducer keeps: every dropped key is within `tolerance_deg` of the
    line between the kept keys round it."""
    count = len(track)
    kept, start = [0], 0
    while start < count - 1:
        end = start + 1
        while end + 1 < count:
            span = np.arange(start + 1, end + 1)
            share = ((span - start) / (end + 1 - start))[:, None]
            guess = track[start][None] * (1 - share) + track[end + 1][None] * share
            guess /= np.linalg.norm(guess, axis=1, keepdims=True)
            if maths.quat_angle(guess, track[span]).max() > tolerance_deg:
                break
            end += 1
        kept.append(end)
        start = end
    return np.array(kept)


def keep_place(track: np.ndarray, tolerance: float) -> np.ndarray:
    """The same for a place track, the tolerance in metres."""
    count = len(track)
    kept, start = [0], 0
    while start < count - 1:
        end = start + 1
        while end + 1 < count:
            span = np.arange(start + 1, end + 1)
            share = ((span - start) / (end + 1 - start))[:, None]
            guess = track[start][None] * (1 - share) + track[end + 1][None] * share
            if np.linalg.norm(guess - track[span], axis=1).max() > tolerance:
                break
            end += 1
        kept.append(end)
        start = end
    return np.array(kept)


def played(track: np.ndarray, kept: np.ndarray, rotation: bool) -> np.ndarray:
    """A reduced track played back on every frame (straight lines between kept keys, as the audit reads a file)."""
    frames = np.arange(len(track))
    out = np.stack([np.interp(frames, kept, track[kept, k]) for k in range(track.shape[1])], axis=1)
    if rotation:
        out /= np.linalg.norm(out, axis=1, keepdims=True)
    return out


def reduce_clip(rig, rotation: np.ndarray, translation: np.ndarray, tracks: list, places: list, planted: dict) -> dict:
    """Reduce a clip's tracks. `rotation` and `translation` are [frame, node, ...]; `tracks` names the bones whose
    rotation is keyed, `places` those whose place is; `planted` maps a foot bone to the frames it is on the floor
    (a boolean per frame). Returns `{"rotation": {bone: kept frames}, "place": {bone: kept frames}, "tolerance",
    "error_mm", "planted_error_mm"}`."""
    full = rig.world(rotation, translation)
    ends = [rig.index[n] for n in ENDS if n in rig.index]
    feet = [n for n in FEET if n in rig.index]
    tolerance = START_DEG
    while True:
        kept_r = {n: keep_rotation(rotation[:, rig.index[n]], tolerance) for n in tracks}
        kept_p = {n: keep_place(translation[:, rig.index[n]], PLACE_TOLERANCE * tolerance / START_DEG) for n in places}
        rot, pos = rotation.copy(), translation.copy()
        for n, kept in kept_r.items():
            rot[:, rig.index[n]] = played(rotation[:, rig.index[n]], kept, True)
        for n, kept in kept_p.items():
            pos[:, rig.index[n]] = played(translation[:, rig.index[n]], kept, False)
        got = rig.world(rot, pos)
        error = float(np.linalg.norm(got[:, ends][:, :, :3, 3] - full[:, ends][:, :, :3, 3], axis=2).max())
        planted_error = 0.0
        for n in feet:
            mask = planted.get(n)
            if mask is not None and mask.any():
                i = rig.index[n]
                planted_error = max(
                    planted_error, float(np.linalg.norm(got[mask, i, :3, 3] - full[mask, i, :3, 3], axis=1).max())
                )
        if (error <= LIMIT and planted_error <= PLANTED_LIMIT) or tolerance < LEAST_DEG:
            break
        tolerance *= 0.5
    if tolerance < LEAST_DEG:
        every = np.arange(rotation.shape[0])
        kept_r = {n: every for n in tracks}
        kept_p = {n: every for n in places}
        error = planted_error = 0.0
    return {
        "rotation": kept_r,
        "place": kept_p,
        "tolerance": tolerance,
        "error_mm": round(error * 1000, 3),
        "planted_error_mm": round(planted_error * 1000, 3),
    }
