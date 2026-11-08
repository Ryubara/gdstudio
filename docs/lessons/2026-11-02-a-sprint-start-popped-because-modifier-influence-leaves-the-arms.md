---
areas: [gameplay, camera, godot]
---
# A sprint start popped because a modifier's influence leaves the arms in its pose

2026-11-02

- **Saw:** "As soon as I start sprinting the torso straightens, the weapon shifts up, then we teleport into the
  sprint" (Deadnight #619). Recording the drawn pose every tick showed the weapon turning 12 degrees in the first tick
  of the carry and 29 degrees, the left upper arm 65 and the left hand 0.7 m in the tick the hands' IK switched off,
  from a stand, a run and the aim, for the player and for a puppet.
- **Cause:** the sprint carry (#525) faded the IK modifier's `influence` linearly and switched it off at 0, as the
  quick strike's fix (#593, kit page "A clip on top of a pose a modifier fades out") did for one clip. A
  `SkeletonModifier3D` blends the chest and hand bones by `influence` but leaves the upper and lower arm bones in its
  pose at any influence, so the arms snapped to the clip's when it went off. The first fix was local to the strike,
  and the page did not say why, so the next fade used the same path.
- **Fix:** the modifier blends itself: `WeaponHandsIK.weight` slerps each bone it turns from the clip's local rotation
  to the solved one, `influence` stays 1, and the player's weight follows the same smoothstep as the carry clip.
  `test_sprint_start_blend.gd` records the bones at `skeleton_updated` for every start and fails on a per-tick turn,
  move or change of turn (it failed first: 72 degrees, 0.71 m).
- **Docs:** [AnimationTree](../engines/godot/animation-tree.md#a-clip-on-top-of-a-pose-a-modifier-fades-out). A fix
  that works
  around an engine behaviour for one clip also goes on the kit page as the behaviour, not only as the workaround.
