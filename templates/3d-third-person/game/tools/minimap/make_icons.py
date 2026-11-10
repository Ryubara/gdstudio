"""Draws the minimap's six icon shapes into `assets/ui/minimap/` (white on clear, 64 px, edges smoothed by 8x8 sampling).

    uv run --with numpy python tools/minimap/make_icons.py

The shapes are GDStudio's own; a marker tints them. Run it again after changing a shape and commit the PNGs.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

import numpy as np

SIZE = 64
SAMPLES = 8
OUT = Path(__file__).resolve().parents[2] / "assets" / "ui" / "minimap"


def grid() -> tuple[np.ndarray, np.ndarray]:
    """Sample coordinates from -1 to 1 (y down), SAMPLES to a pixel each way."""
    n = SIZE * SAMPLES
    ys, xs = np.mgrid[0:n, 0:n]
    return (xs + 0.5) / n * 2 - 1, (ys + 0.5) / n * 2 - 1


def inside_polygon(x: np.ndarray, y: np.ndarray, points: list[tuple[float, float]]) -> np.ndarray:
    """True where (x, y) is inside the polygon (even-odd rule)."""
    result = np.zeros(x.shape, bool)
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        crosses = ((yi > y) != (yj > y)) & (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi)
        result ^= crosses
        j = i
    return result


def chunk(kind: bytes, data: bytes) -> bytes:
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def save(name: str, mask: np.ndarray) -> None:
    """Writes `mask` (SIZE * SAMPLES square) as a white RGBA PNG with the coverage as alpha."""
    coverage = mask.reshape(SIZE, SAMPLES, SIZE, SAMPLES).mean(axis=(1, 3))
    rgba = np.full((SIZE, SIZE, 4), 255, np.uint8)
    rgba[..., 3] = (coverage * 255 + 0.5).astype(np.uint8)
    raw = b"".join(b"\x00" + rgba[row].tobytes() for row in range(SIZE))
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    (OUT / f"{name}.png").write_bytes(png)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    x, y = grid()
    radius = np.hypot(x, y)
    save("dot", radius <= 0.82)
    save("ring", (radius <= 0.86) & (radius >= 0.55))
    save("square", (np.abs(x) <= 0.72) & (np.abs(y) <= 0.72))
    save("diamond", np.abs(x) + np.abs(y) <= 0.95)
    save("arrow", inside_polygon(x, y, [(0, -0.9), (0.7, 0.8), (0, 0.4), (-0.7, 0.8)]))
    save("triangle", inside_polygon(x, y, [(0, -0.85), (0.8, 0.7), (-0.8, 0.7)]))


if __name__ == "__main__":
    main()
