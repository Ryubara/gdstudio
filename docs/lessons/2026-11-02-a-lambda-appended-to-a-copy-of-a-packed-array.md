---
areas: [godot, tests]
---
# A navigation mesh built in a lambda came out empty

2026-11-02

- **Saw:** a test built a small navigation mesh from squares (Deadnight #226) with `var corner := func(x, z): ...
  vertices.append(...)` and `vertices` a `PackedVector3Array` declared outside. The mesh had 21 vertices in the lambda's
  eyes and none in the `NavigationMesh`: every path was `[]` and `map_get_closest_point` answered (0, 0, 0).
- **Cause:** a lambda captures a packed array by value, so the `append` went to a copy.
- **Fix:** a method on the object with member variables (`_vertices`, `_index`). The same goes for any packed array a
  lambda is meant to fill; a plain `Array` or `Dictionary` is captured by reference and works.
- **Docs:** [Navigation in tests](../godot/navigation-in-tests.md).
