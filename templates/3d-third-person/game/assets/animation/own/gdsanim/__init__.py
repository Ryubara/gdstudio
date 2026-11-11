"""The clip toolkit: GDStudio's own animation clips, made by script (kit #1154).

A clip is a description (controls in the character's space, a contact plan, a style file) that this package solves
into keys, checks and writes as a glb with a `clips.json` beside it. The plan it serves is
`docs/tools/blender/own-animation.md`; how to use it is `docs/tools/blender/animation.md#toolkit`.

Everything here is numpy only and reads and writes glb files itself, so a build runs anywhere
(`uv run --with numpy python -B build_own.py ...`) and a rebuild writes the same bytes. Blender is used for what
needs a renderer or a mesh query: the review sheet's strip (`review_sheet.py`) and limbs inside limbs
(`../limb_overlap.py`).

Axes are glTF's and Godot's: +Y up, +Z the way the character faces, +X the character's left, metres. Angles in a
description are degrees; time is frames at `FPS`.

| Module | What it holds |
| --- | --- |
| `maths` | rotations, quaternions, eases and curves through keys |
| `rig` | a body read from a glb (and `rig_<body>.json` when it exists): rest, skin, sole points, segment masses |
| `plan` | the contact plan: footfalls to foot paths, contact times, speed, events |
| `solve` | one pose from controls: trunk, two-bone limbs, feet, hands, fingers |
| `overlap` | the overlap pass: a damped spring per chain, closed round a loop |
| `weight` | the centre of mass and what it must do: over the feet, on a free fall's arc, leaning with acceleration |
| `mirror` | a clip for the other side |
| `style` | a variant's numbers, read from a style file over the description's defaults |
| `reduce` | key reduction, checked against the full curve |
| `export` | the glb with a frozen clip list, and `clips.json` |
| `checks` | the checks of `own-animation.md#checks`, each with a self-test |
| `build` | a clip from description to checked keys, and a file from clips |
"""

## The key rate of every clip (the Universal Animation Library's, which our clips play beside).
FPS = 30
