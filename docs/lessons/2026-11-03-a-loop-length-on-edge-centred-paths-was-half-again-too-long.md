---
areas: [godot, tests]
---
# A loop's length measured on edge-centred paths came out half again too long

2026-11-03

- **Saw:** Deadnight #855 measured kiting loops on the dead's walking mesh, a path from waypoint to waypoint round each
  island. A row of cartons 11.4 by 0.8 m came out at 50 m round, the ticket booths at 66 m against a plan's 45 m.
- **Cause:** the tests' `LotNavigation.path` asks the server with `PATH_POSTPROCESSING_EDGECENTERED`, which goes
  through the middle of every polygon edge it crosses: a zigzag, fine for "can it get there" and wrong for "how far".
  The waypoints were also first set in the middle of each corridor, so the "loop" was a wide lap no pack follows.
- **Fix:** a `shortest` flag that asks for `PATH_POSTPROCESSING_CORRIDORFUNNEL`, and waypoints at the outside corners
  of what the loop circles (0.6 to 0.8 m off): the cartons then measure 30 m, the booths 52 m, the shortest lap a pack
  cuts to. `test_lot_loops.gd` holds each at 40 m and more.
- **Docs:** [Level design, P2](../gamedev/level-design.md#p2-every-opening-adds-a-loop-to-run).
