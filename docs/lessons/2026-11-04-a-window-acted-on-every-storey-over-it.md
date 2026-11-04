---
areas: [gameplay, godot]
---
# A window acted on every storey over it

2026-11-04

- **Saw:** on the second map (two floors, 3.4 m apart) a dead walking the upper floor over a torn ground window was
  drawn climbing for 319 of 400 ticks and floated 0.46 m over its floor; with the boards up it did not. Another time a
  dead 3.4 m over a window was lifted 0.9 m through a wall, and a test that walks every barricade passed on the wrong
  window.
- **Cause:** a gate (`ZombieGate`) was written for the flat lot, where every question is "where along the wall and how
  far in" (`depth_of`, `along_of`, `spans`, `is_at`, `climbs`) and a point has no height. A map with floors reuses the
  same code; its ground window's sill, boards and jambs then reach every storey over it.
- **Fix:** a height band on the gate (`on_storey`, from the sill's foot to a metre over its top) used by `spans`,
  `climbs` and `keep_in_opening`, and a test that walks a dead on the upper floor over a torn ground window and reads
  `climbing` false and its height unchanged. Check for next time: when a map gains a second floor, every query on
  something fixed to the ground (a gate, a zone, a trigger) asks for the height as well as the flat position, and the
  test for it puts a body one storey off.
- **Docs:** [Zombies](https://github.com/Ryubara/deadnight/blob/main/docs/research/zombies.md) (a gate acts on its own
  storey).
