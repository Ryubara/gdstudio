---
areas: [godot, tests]
---
# A moved lamp went over the light budget next door

2026-11-03

- **Saw:** after Deadnight's prize crane lamp moved 1.2 m forward and up to light the new prize board (#830),
  `test_the_crane_at_any_of_its_spots_keeps_the_lot_within_the_budget` failed: the concession stand's roof, then its
  floor, were lit by 7 lights where the lot keeps 6 for a fight.
- **Cause:** an `OmniLight3D` counts on every mesh its range touches, not on what it is meant to light. Moving it
  changes which neighbours it reaches; the light-cap test was not in the suites run after the move.
- **Fix:** keep the lamp just in front of the board and cut its range from 5 m to 4.6 m; run the lot's light-cap test
  after any change to a light's position or range, not only to its count.
- **Docs:** Deadnight's `docs/research/night-environment.md` (the crane's lamp) and
  [Compatibility lighting](../engines/godot/compat-lighting.md#dynamic-lights).
