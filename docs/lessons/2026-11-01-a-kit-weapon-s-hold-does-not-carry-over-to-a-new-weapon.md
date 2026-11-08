---
areas: [gameplay, blender]
---
# A kit weapon's hold does not carry over to a new weapon

2026-11-01

- **Saw:** copying the kit AK's transform in the Soldier's hand onto a new gun made it tiny.
- **Cause:** the AK and Sniper copies in the character file carry rescaled mesh data (object scale 0.21-0.42); the
  Shotgun and Shovel copies are unit-scale.
- **Fix:** take the hold from the Shotgun (guns) or the Shovel (melee).
- **Docs:** [Blender weapons](../tools/blender/weapons.md#axes-origin-and-the-hold).
