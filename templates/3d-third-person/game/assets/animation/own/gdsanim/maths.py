"""Rotations, quaternions, eases and curves through keys, and the clips' key rate.

Rotations are 3x3 matrices while a pose is solved and quaternions (x, y, z, w, glTF's order) once it is keyed.
"""

import math

import numpy as np

## The key rate of every clip (the Universal Animation Library's, which our clips play beside).
FPS = 30
X = np.array([1.0, 0.0, 0.0])
Y = np.array([0.0, 1.0, 0.0])
Z = np.array([0.0, 0.0, 1.0])


def unit(v: np.ndarray) -> np.ndarray:
    v = np.asarray(v, dtype=float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def square_to(v: np.ndarray, axis: np.ndarray, fallback: np.ndarray = Y) -> np.ndarray:
    """`v` made square to the unit `axis`; `fallback` when `v` lies along it."""
    out = v - axis * np.dot(axis, v)
    if np.linalg.norm(out) < 1e-6:
        out = fallback - axis * np.dot(axis, fallback)
    return unit(out)


def segment_gap(a0: np.ndarray, a1: np.ndarray, b0: np.ndarray, b1: np.ndarray) -> float:
    """The least distance between two line segments."""
    u, v, w = a1 - a0, b1 - b0, a0 - b0
    uu, uv, vv, uw, vw = np.dot(u, u), np.dot(u, v), np.dot(v, v), np.dot(u, w), np.dot(v, w)
    den = uu * vv - uv * uv
    s = float(np.clip((uv * vw - vv * uw) / den, 0.0, 1.0)) if den > 1e-12 else 0.0
    t = float(np.clip((uv * s + vw) / vv, 0.0, 1.0)) if vv > 1e-12 else 0.0
    s = float(np.clip((uv * t - uw) / uu, 0.0, 1.0)) if uu > 1e-12 else 0.0
    return float(np.linalg.norm(w + s * u - t * v))


def axis_angle(axis: np.ndarray, degrees: float) -> np.ndarray:
    """The rotation of `degrees` about `axis` (right-handed)."""
    x, y, z = unit(axis)
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    t = 1.0 - c
    return np.array(
        [
            [t * x * x + c, t * x * y - s * z, t * x * z + s * y],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c],
        ]
    )


def body_turn(pitch: float = 0.0, yaw: float = 0.0, lean: float = 0.0) -> np.ndarray:
    """A turn from the standing rest, in degrees: `lean` to the character's left about the way it faces, then
    `pitch` forward, then `yaw` to its left about the vertical."""
    return axis_angle(Y, yaw) @ axis_angle(X, pitch) @ axis_angle(Z, -lean)


def frame(aim: np.ndarray, side: np.ndarray) -> np.ndarray:
    """An orthonormal basis whose first axis is `aim` and whose second is `side` made square to it."""
    a = unit(aim)
    s = square_to(np.asarray(side, dtype=float), a)
    return np.column_stack([a, s, np.cross(a, s)])


def aim_turn(aim0: np.ndarray, side0: np.ndarray, aim: np.ndarray, side: np.ndarray) -> np.ndarray:
    """The rotation that takes the rest directions (`aim0`, `side0`) to (`aim`, `side`)."""
    return frame(aim, side) @ frame(aim0, side0).T


def quat_of(m: np.ndarray) -> np.ndarray:
    """The quaternion (x, y, z, w) of a rotation matrix, w not negative."""
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0.0:
        s = math.sqrt(t + 1.0) * 2.0
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, 0.25 * s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2.0
        q = [0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2.0
        q = [(m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2.0
        q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s, (m[1, 0] - m[0, 1]) / s]
    q = np.array(q)
    q /= np.linalg.norm(q)
    return -q if q[3] < 0 else q


def matrix_of(q: np.ndarray) -> np.ndarray:
    """Rotation matrices of quaternions (x, y, z, w), any leading shape."""
    q = np.asarray(q, dtype=float)
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


def rotation_vector(m: np.ndarray) -> np.ndarray:
    """A rotation as its axis times its angle in radians."""
    q = quat_of(m)
    s = np.linalg.norm(q[:3])
    if s < 1e-12:
        return np.zeros(3)
    return q[:3] / s * 2.0 * math.atan2(s, q[3])


def from_rotation_vector(v: np.ndarray) -> np.ndarray:
    a = np.linalg.norm(v)
    if a < 1e-12:
        return np.eye(3)
    return axis_angle(v / a, math.degrees(a))


def slerp(a: np.ndarray, b: np.ndarray, w: float) -> np.ndarray:
    """From rotation `a` to `b` by the share `w`, the short way."""
    if w <= 0.0:
        return a
    if w >= 1.0:
        return b
    return a @ from_rotation_vector(rotation_vector(a.T @ b) * w)


def angle_between(a: np.ndarray, b: np.ndarray) -> float:
    """Degrees between two rotation matrices."""
    c = (np.trace(a.T @ b) - 1.0) / 2.0
    return math.degrees(math.acos(min(1.0, max(-1.0, c))))


def quat_angle(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Degrees between quaternions, any leading shape. Read off the chord between them, not the arc cosine of
    their dot product, which loses a twentieth of a degree to rounding when the keys were stored as 32-bit."""
    a = a / np.linalg.norm(a, axis=-1, keepdims=True)
    b = b / np.linalg.norm(b, axis=-1, keepdims=True)
    chord = np.minimum(np.linalg.norm(a - b, axis=-1), np.linalg.norm(a + b, axis=-1))
    return np.degrees(4.0 * np.arcsin(np.clip(chord / 2.0, 0.0, 1.0)))


# ---- eases and curves ------------------------------------------------------------------------------------------


def smooth(x: float) -> float:
    """0 to 1 with no speed at either end."""
    x = min(max(x, 0.0), 1.0)
    return x * x * (3.0 - 2.0 * x)


def smoother(x: float) -> float:
    """0 to 1 with no speed and no acceleration at either end."""
    x = min(max(x, 0.0), 1.0)
    return x * x * x * (x * (6.0 * x - 15.0) + 10.0)


def ease(x: float, sharp: float = 0.0) -> float:
    """0 to 1: `smooth` at `sharp` 0, moving to a snap in the middle as `sharp` nears 1 (a held pose, a quick
    change, a held pose)."""
    x = min(max(x, 0.0), 1.0)
    if sharp <= 0.0:
        return smooth(x)
    width = max(1.0 - sharp, 0.05)
    return smooth((x - 0.5) / width + 0.5)


def wave(frame_no: float, period: float, phase: float = 0.0) -> float:
    """A sine with `period` frames: 0 rising at `phase` (a share of the period)."""
    return math.sin(2.0 * math.pi * (frame_no / period - phase))


def pulse(frame_no: float, start: float, rise: float, hold: float, fall: float, sharp: float = 0.0) -> float:
    """0, up to 1 over `rise` frames from `start`, held for `hold`, back to 0 over `fall`."""
    t = frame_no - start
    if t <= 0.0:
        return 0.0
    if t < rise:
        return ease(t / rise, sharp)
    if t < rise + hold:
        return 1.0
    if t < rise + hold + fall:
        return 1.0 - ease((t - rise - hold) / fall, sharp)
    return 0.0


def keyed(keys: list, frame_no: float, period: float | None = None):
    """A value keyed at frames (`[(frame, value), ...]`, values numbers or arrays), read at `frame_no` on a
    monotone cubic through the keys: no overshoot, and flat between two equal keys, so a planted target stays where
    it is. With `period` the keys repeat every `period` frames (a loop) and the curve is smooth across the seam."""
    xs = [float(k[0]) for k in keys]
    ys = [np.atleast_1d(np.asarray(k[1], dtype=float)) for k in keys]
    scalar = np.ndim(keys[0][1]) == 0
    if period is not None:
        frame_no = xs[0] + (frame_no - xs[0]) % period
        xs = [xs[-1] - period] + xs + [xs[0] + period, xs[1] + period if len(xs) > 1 else xs[0] + 2 * period]
        ys = [ys[-1]] + ys + [ys[0], ys[1] if len(ys) > 1 else ys[0]]
    n = len(xs)
    if n == 1 or frame_no <= xs[0]:
        return float(ys[0][0]) if scalar else ys[0]
    if frame_no >= xs[-1]:
        return float(ys[-1][0]) if scalar else ys[-1]
    d = [(ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) for i in range(n - 1)]
    m = [np.zeros_like(d[0])]
    for i in range(1, n - 1):
        same = d[i - 1] * d[i] > 0
        m.append(np.where(same, 2 * d[i - 1] * d[i] / (d[i - 1] + d[i] + 1e-30), 0.0))
    m.append(np.zeros_like(d[0]))
    i = max(j for j in range(n - 1) if xs[j] <= frame_no)
    h = xs[i + 1] - xs[i]
    t = (frame_no - xs[i]) / h
    t2, t3 = t * t, t * t * t
    out = (
        (2 * t3 - 3 * t2 + 1) * ys[i]
        + (t3 - 2 * t2 + t) * m[i] * h
        + (-2 * t3 + 3 * t2) * ys[i + 1]
        + (t3 - t2) * m[i + 1] * h
    )
    return float(out[0]) if scalar else out
