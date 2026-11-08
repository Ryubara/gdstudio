---
areas: [blender, tests]
---
# A modular body was checked part by part and showed holes, a mask and clipping

2026-11-03

- **Saw:** the maintainer, in the menu: the neck was see-through with some clothes, the mouth was a line running up
  the side of the face so the face read as a mask, and limbs and clothes passed through each other (Deadnight #895).
- **Cause:** the parts were cut from a kit body whose head is an open hood closed only by the vest's collar; open
  collars left it open, and every review render (Workbench, no back-face culling) drew the inside of the head as if it
  were outside. The face was the kit's balaclava rim painted skin. Pose checks were relative (her against him, the
  hand against the weapon), never every combination, from behind, in every clip.
- **Fix:** each part closes itself (a closed head with a neck, lined collars, bridged bare wrists, pushes that move
  every copy of a seam vertex alike); a sweep test over every pair of parts that meet, on both bodies, ray-tests for a
  back face seen first; a clip sampler counts limb and garment vertices inside the body in every clip; review renders
  cull back faces.
- **Docs:** [Closed, and fitting, in every combination](../blender/variants.md#closed-and-fitting-in-every-combination).
