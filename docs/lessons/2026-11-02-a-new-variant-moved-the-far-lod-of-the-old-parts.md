---
areas: [blender]
---
# A new variant moved the far level of detail of the old parts

2026-11-02

- **Saw:** adding the female Soldier's parts (Deadnight #678), the far decimation ratio went from 0.333 to 0.299, which
  would have rebuilt every far mesh of the male looks; and Godot then counted 4-14 fewer triangles on her far heads
  than `parts.json` said.
- **Cause:** the ratio is solved for the heaviest look, and her looks were heavier. Her face pieces (lashes,
  freckles, a mouth) were joined into the head before the collapse, which cut them to slivers that the glTF round trip
  dropped.
- **Fix:** solve the ratio over the looks that shipped, and assert every look, old and new, against the far budget.
  Decimate her head and its features only, then join the small pieces whole into the far mesh (they are a few dozen
  triangles, and the lashes keep their shape at range).
- **Docs:** [Character variants](../blender/variants.md#a-second-body-on-the-same-parts).
