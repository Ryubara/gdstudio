---
areas: [gameplay, tests]
---
# A ninth body stood on the first one's start marker

2026-11-05

- **Saw:** a night of 8 people and 7 bots started with each bot at distance 0.00 from a person (bots 101 to 107 on
  people 1 to 7): both Deadnight maps list eight start markers and the start was `markers[count of bodies % 8]`.
  Players do not push each other (their layer is not in their own mask), so nothing separated them. Two more faults sat
  in the markers all along: the lot's 8th marker was inside a parked car, and its 5th was on a car's edge, so the soldier
  was drawn through it. A seat that opened again after a leave took the marker of a body still there, because the slot
  was the count of bodies.
- **Cause:** nobody had ever seated more than eight bodies, and a test of "nobody out of bounds" asked only for
  bounds. A marker was never tested against the body that stands on it.
- **Fix:** a start for every body that can exist (15 markers a map, found by sweeping the map for places with a body's
  room and a way to the others), the lowest free marker for a seat, and a test on every map in the registry: nobody
  inside anybody, on the mesh, with the body's room free of the map, not out of bounds, before and after the bodies
  settle. A test that wants the count of anything on a map reads it from the scene, not from a constant.
- **Docs:** Deadnight `docs/design/map.md` and `docs/design/smallmap.md` (the start markers).
