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
- **Fix:** cut the front wherever it comes within 1.5 mm of sinking (measured at edge middles and triangle centres, not
  by edge length) and lift the new corners onto the surface; keep the shape off a crease in the head (a chord over a
  crease sinks however often it is cut: the mouths stop above the jaw's, and the build asserts it); turn a closed shell
  outward once, from one face whose way out is known; smooth-shade the front, or a lamp picks out each dark triangle. A
  Godot test holds every mouth's corners and triangle middles out of every head; corners alone passed with skin
  showing. Look at the Godot capture zoomed in: the Workbench sheet hid what the game's lamp showed.
- **Docs:** [Character variants](../tools/blender/variants.md#closed-and-fitting-in-every-combination).
