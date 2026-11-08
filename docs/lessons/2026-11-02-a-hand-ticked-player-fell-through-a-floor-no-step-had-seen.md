---
areas: [godot, tests]
---
# A hand-ticked body fell through a floor and walked through a ledge no physics step had seen

2026-11-02

- **Saw:** after a suite's ticks were moved from one physics frame each to back-to-back calls, sprint tests never
  sprinted and a ledge was never climbed; the player's position was `y = -0.9` with a vertical speed of -5.5 m/s.
- **Cause:** the physics server indexes a body (the test room's floor, a ledge or beam the test adds) on its next
  step. Hand ticks do not step it, so a query before the first step finds nothing there.
- **Fix:** take one real `await get_tree().physics_frame` after loading the room and after adding any collider, then
  tick by hand; that is one frame per setup, not per tick.
- **Docs:** [Test speed](../engines/godot/test-speed.md).
