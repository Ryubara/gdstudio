---
areas: [gameplay, tests, godot]
---
# A night stepped by hand never took a bought door's mesh in, and the dead stood at the wall

2026-11-02

- **Saw:** in a soak of four bots, three to six dead stood still at (-2, -3) and (9, -3) beside the concession door from
  round 2 on, chasing, with no breach, and the round never ended. A fresh path query from one of them to a bot on the
  field ended at its own feet (the inner face of the door's wall, z -3.25).
- **Cause:** the soak ran `night.tick()` in a loop and never gave the engine a physics frame. The navigation server takes
  a region's new mesh into the map only on a physics frame, so after the concession was bought the map stayed as baked
  with the door shut, while the night had already opened the midway's spawn points: the dead rose on an island with no
  way out and walked to its nearest point to their target. `map_force_update` does not shorten it.
- **Fix:** the night lets the dead rise in an area only once a path from the field reaches its spawn points
  (`NightWorld.take_in_areas`, asked every 15 ticks), and a harness that buys doors gives the engine its frames. A test
  of a bought door waits for the map's answer, never for the purchase.
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md#a-night-stepped-by-hand-has-a-stale-map).
