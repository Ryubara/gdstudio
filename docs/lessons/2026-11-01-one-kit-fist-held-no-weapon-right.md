---
areas: [gameplay, blender]
---
# One kit fist held no weapon right

2026-11-01

- **Saw:** on every Deadnight weapon the fingers went 8-42 mm into the gun or floated 20-80 mm off it, the trigger
  finger through the frame or the cylinder.
- **Cause:** the kit clips never move the fingers (one static fist, made for the kit's guns), and every weapon was
  placed by one copied kit hold; nothing measured the fingers against the weapon.
- **Fix:** hand sockets in each model (`Grip`, `Trigger`, `Support`), a solver that closes each finger to 1 mm from
  the surface, a modifier that applies the solved finger pose, and a test that measures the skin in every pose (no
  part over 2 mm in, every contact within 5 mm).
- **Docs:** [Blender weapons](../tools/blender/weapons.md#hands-on-the-weapon).
