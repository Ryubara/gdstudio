---
areas: [blender, tools]
---
# Cleaned kit clips idled with the arms out

2026-11-01

- **Saw:** the Soldier's arms stood out sideways in clips built on the rig-sharing recipe; in its export, `Idle` keys
  `UpperArm.L` at exactly the rest rotation.
- **Cause:** kit clips key only the bones they move; the rest sit at the glTF node pose, which the recipe's cleared pose
  bones and `export_reset_pose_bones=True` replace with Blender's rest (arms out).
- **Fix:** read the static pose right after the import, key it into every clip for the bones it leaves out, pose it
  before export, `export_reset_pose_bones=False`.
- **Docs:** [Rig sharing (Blender)](../tools/blender/rig-sharing.md).
