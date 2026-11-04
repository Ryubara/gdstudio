---
areas: [tests, gameplay]
---
# A crossing test started in the air and passed on another storey's window

2026-11-04

- **Saw:** removing one ground window (`side_1`) from Deadnight's second map failed `test_dead_cross_every_barricade`
  on an upper window, `upper_a1`, on the far side of the wall and one storey up: the dead walked away from the window
  and stood still at (-6.75, 3.45, 0). It looked as if some dead pathing needed the ground window (#994).
- **Cause:** the test put every dead 5 m out at the window's own height, and the upper window's deck is 2.5 m wide, so
  the dead stood in the air over the alley. The walking mesh's nearest point to that spot was the corner of a shed's
  roof, an island of two polygons no dead can reach, and it walked there. With `side_1` in the map it passed by
  accident: on its way it came inside that window's reach, and `ZombieGate` asks depth and along on the flat, so a
  sill 3.4 m below lifted it 0.9 m. Lifted, its nearest mesh was the room over the side room, through the wall, and it
  walked that room and reached the player from inside. `climbing` was true, from the wrong window, so the test passed;
  it had not walked the window under test at 1 m/s since the deck was built. The real dead were never affected: 76
  walks from every real spawn in all eight door sets came in over their own sill.
- **Fix:** the test starts as far out as the walking mesh goes at the window's height and fails if nothing stands
  there; a climb counts only at the barricade's own sill; a new walk goes from every spawn point, so the stair and the
  deck are on the way. No scene or simulation change. The flat gate is its own issue (Deadnight #1030).
- **Check for next time:** a test that places a body asks what is under it first (the mesh's nearest point is beneath
  it, not beside it), and a start that is a fixed distance out breaks on the first deck, roof or balcony. A test that
  reads a flag ("it climbed") also asks where the flag was set. When a change to one place fails a test about another,
  trace the body tick by tick with the change undone as well: the pass is the thing to explain, not only the failure.
