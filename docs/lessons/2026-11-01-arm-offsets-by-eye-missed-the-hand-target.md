---
areas: [blender, tests]
---
# Arm offsets by eye missed the hand target

2026-11-01

- **Saw:** a throw authored as Euler offsets leaned the Soldier sideways and the left hand never reached the pin.
- **Cause:** the axis notes were wrong for the pose: on the kit spine Y leans sideways and Z turns the chest, and arm
  axes change meaning with the base pose.
- **Fix:** measure the hand's move per bone axis (30-degree probes, numbers not renders), then solve the arm offsets
  for a target hand position with a small coordinate search in Blender and paste the rounded result into the script.
- **Docs:** [Rig sharing](../blender/rig-sharing.md#posing-by-hand-position).
