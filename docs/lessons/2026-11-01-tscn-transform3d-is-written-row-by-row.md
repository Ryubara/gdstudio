---
areas: [godot, tests]
---
# A generated scene turned a node the wrong way

2026-11-01

- **Saw:** a node written into a `.tscn` by a generator with `Transform3D(c, 0, s, 0, 1, 0, -s, 0, c, ...)` had its
  local +Z pointing the opposite way to the one worked out by hand; "how far into the field is this point" read
  inside out, and a test that spawn markers stand outside their gate failed.
- **Cause:** the text form writes the basis row by row, so the rotation about Y by an angle is
  `(c, 0, s, 0, 1, 0, -s, 0, c)` and the node's +Z (the third column) is `(s, 0, c)`, not the third triple read as a
  vector.
- **Fix:** turn by `atan2(dx, dz)` for a wanted +Z of `(dx, 0, dz)`, and test the facing (a point's depth from the node)
  instead of trusting the matrix.
- **Docs:** deadnight's `docs/research/zombies.md`, "The fence's boards".
