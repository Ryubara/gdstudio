"""Turns the shine captures of `diag.gd` into numbers (kit docs: tools/blender/realistic-characters.md#shine).

    uv run --no-project --with pillow --with numpy python shine.py <folder>

Each capture is compared, pixel by pixel, with the `all_off` capture of the same renderer and light (no coat, no
specular, no reflected sky, skin roughness 0.7): what is left is what the highlights add. Two numbers come out:
"added" is the mean luminance the highlights add over the character, in percent of what the matt surface shows;
"outshone" is the share of her pixels where the highlight is brighter than half the surface under it.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

LUM = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32) / 255


for base_png in sorted(Path(sys.argv[1]).glob("shine_*_all_off.png")):
    stem = base_png.stem[: -len("all_off")]
    base = load(base_png)
    body = np.abs(base - base[2, -3]).sum(2) > 0.08
    body[int(base.shape[0] * 0.62):] = False  # the floor's band of the frame
    matt = (base @ LUM)[body]
    for png in sorted(Path(sys.argv[1]).glob(stem + "*.png")):
        lum = (load(png) @ LUM)[body]
        extra = np.clip(lum - matt, 0, None)
        print(f"{png.stem:46s} added {100 * float(extra.mean() / matt.mean()):5.1f} %   outshone {100 * float((extra > 0.5 * matt).mean()):5.2f} %")
