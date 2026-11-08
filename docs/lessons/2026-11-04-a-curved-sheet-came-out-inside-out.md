---
areas: [blender]
---
# A curved sheet came out inside out

2026-11-04

- **Saw:** two rays through a rubber mask at the corners of its mouth (Deadnight #1078); the mouth looked right.
- **Cause:** the sheet's rim faces were turned away from the middle of the rim, which is the wrong way on a curve: the
  middle of the top edge lies under the rim's middle. The same fault as a prism inside out: the eye looks through it.
- **Fix:** wind each rim face by the rim's own order, with no reference point. `gds godot` on the turntable's `--probe`
  puts a red dot on each ray: it found these in one look where the failure line gave only a place.
- **Docs:** [Character variants, clothes that stand off the body](../tools/blender/variants.md).
