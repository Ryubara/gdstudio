---
areas: [blender, gameplay]
---
# An IK that turned one palm bone tore the hand

2026-11-01

- **Saw:** in the aim pose the Soldier's right hand was stretched and torn round the gun; in reloads (no IK) it was
  whole.
- **Cause:** the kit hand is four bones from the wrist (`Index1`, `Middle1`, `Pinky1`, `Thumb1`); the arm IK set only
  `Index1.R`, the bone the weapon rides, and the other three stayed with the forearm.
- **Fix:** turn the other three by the same rotation off their rest (they share the parent and the pivot), every frame
  after the IK.
- **Docs:** [Blender weapons](../tools/blender/weapons.md#hands-on-the-weapon).
