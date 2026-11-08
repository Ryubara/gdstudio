---
areas: [godot-ui, tests]
---
# A held weapon aimed in the world was left behind by a turn on a stage that never stepped

2026-11-03

- **Saw:** the maintainer: rotating the character on the loadout bugs the arms, and switching the showcase weapon puts
  the arms and the weapon behind the player, through his body (Deadnight #940).
- **Cause:** the arms are posed by a `SkeletonModifier3D` (`WeaponHandsIK`) that aims in the world, from a yaw the view
  has to write (`aim_yaw`). The menu stage wrote it, and stepped the idle clip, only when it was animated. In a still
  (the web's level on a software renderer or a slow frame) and with reduced motion it was not: the manual
  `AnimationPlayer` was never applied once (the arms-out rest pose) and the yaw stayed 0, behind a soldier who faces
  +Z. A turn moved the body, not the aim; a new weapon built a new modifier with yaw 0. The soldier tests ran the
  live stage only, and read the hands after the frame, where the skeleton hands back the clip's pose.
- **Fix:** one `face(yaw)` sets the body and the aim together, a new weapon aims at once, and the stage poses the
  soldier on every step, a step of 0 seconds when it is not animated (Deadnight #940).
- **Check:** a pose a modifier works out from a world value is tested at every level the view can be in (live, still,
  reduced motion), sweeping the turn (every 15 degrees) and every weapon, and read at `skeleton_updated`: hands and
  muzzle in front of the chest plane, outside the body. Run it on the old code first: it must fail in the levels
  that do not step.
- **Docs:** [AnimationTree](../engines/godot/animation-tree.md).
