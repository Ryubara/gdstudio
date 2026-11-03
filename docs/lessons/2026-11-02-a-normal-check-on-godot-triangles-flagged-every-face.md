---
areas: [godot, blender]
---
# A normal check on Godot's triangles flagged every face

2026-11-02

- **Saw:** chasing dark sandbag tops in a Godot capture (Deadnight #635), a probe compared each index triangle's
  `(p1 - p0).cross(p2 - p0)` with its stored normals: every triangle of every prop disagreed, the table's too.
- **Cause:** Godot's front faces wind clockwise, so on a correct mesh that cross product points inward. The tops were
  dark for two other reasons: the palette was stored linear, and the camera saw the faces turned from the lamp.
- **Fix:** check normals in Blender on the exported file (signed volume per island: positive is outward), and judge
  lighting with one light straight over the piece beside a known-good prop.
- **Docs:** [Modular kits: building props](../blender/modular-kits.md#building-props).
