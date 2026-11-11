"""Turns the captures of `diag.gd` into one number each: the fine-scale contrast inside the arm, which is what a
line along a limb is (kit docs: tools/blender/realistic-characters.md#limb-lines).

    uv run --no-project --with pillow --with numpy python limb_lines.py <folder of diag_*.png>

The number is the mean absolute difference between the picture's luminance and its own 9-pixel box blur, in
thousandths of full scale, over the pixels of the arm that lie at least 12 pixels inside its outline (so the
silhouette does not count). The mesh alone scores 0.5; the first build's arm scored 6.8, the rework's 4.7.
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def score(path):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.float32) / 255
    background = a[2, -3]
    body = Image.fromarray(((np.abs(a - background).sum(2) > 0.08) * 255).astype(np.uint8))
    inside = np.asarray(body.filter(ImageFilter.MinFilter(25))) > 0
    lum = Image.fromarray((a @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32) * 255).astype(np.uint8))
    blur = np.asarray(lum.filter(ImageFilter.BoxBlur(4))).astype(np.float32)
    fine = np.abs(np.asarray(lum).astype(np.float32) - blur) / 255
    return 1000 * float(fine[inside].mean()), int(inside.sum())


for png in sorted(Path(sys.argv[1]).glob("diag_*.png")):
    s, n = score(png)
    print(f"{png.stem:48s} {s:6.2f}   ({n} pixels)")
