---
areas: [blender]
---
# A decal flat between its outline sank behind the face

2026-11-04

- **Saw:** Deadnight's new wide and tall mouths (#1061) showed skin through them as pale notches that read as teeth,
  on all four faces of the render sheet; the narrow smile of #895 never had them.
- **Cause:** the decal's points followed the face only round its outline. Its front was one n-gon cut into long
  triangles, flat across the head's bulge, which rose past the 4 mm the decal stands out. Then the normals: turning
  each face outward from the shape's middle turned the corners of a wide curved shape the wrong way.
- **Fix:** cut the front's inner edges down to 35 mm and lift the new corners onto the surface; turn a closed shell
  outward once, from one face whose way out is known; smooth-shade the front, or a lamp picks out each dark triangle.
  A Godot test holds every mouth 2 to 8 mm out of every head.
- **Docs:** [Character variants](../blender/variants.md#closed-and-fitting-in-every-combination).
