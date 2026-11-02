---
areas: [blender, tools]
---
# An authored clip swung the gun behind the head

2026-11-01

- **Saw:** halfway through an equip clip keyed from two good poses, the Soldier's gun swung behind his head.
- **Cause:** two neighbouring quaternion keys had opposite signs (q and -q, the same rotation); Blender interpolates
  each component, so the path between them is wild, and the exporter samples it.
- **Fix:** keep each key's sign continuous with the previous one (negate when the dot product is negative); flip the
  target before a slerp.
- **Docs:** [Rig sharing (Blender)](../blender/rig-sharing.md).
