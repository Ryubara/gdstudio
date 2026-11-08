---
areas: [gameplay, tests]
---
# A window opened over a stairwell, and its dead walked 10 m outside to the next window

2026-11-03

- **Saw:** on Deadnight's second map the upper floor's window `upper_b1` was never torn. A dead that rose there walked
  10 m along the outside to `upper_b2` and came in by that one, even with a person standing right behind `upper_b1`:
  the way from its spawn to 1.5 m inside was 21.8 m for 8.5 m straight. It hid until the dead tore the boards of the
  window they stood at, not of the gate they were assigned (Deadnight #817, #824).
- **Cause:** the window was placed on the wall at x -1, over the side stair's well (the stair 2 m below the floor
  there). The floor behind it was the well's opening, so the walking mesh had no polygon inside the window and nobody
  could stand behind it. The suite asked each window's spawn for a path to the hall, which the next window gave, so a
  window that was no way in passed.
- **Fix:** the generator moved the window 3.4 m west, onto the floor between a rack and the well's parapet (a 2.4 m
  throat with the room open behind it); a landing over the well had 1.4 to 2.1 m of headroom over the stair. A test asks
  each window's dead the way from their spawn to 1.5 m behind their own window and fails a way more than 2 m longer than
  the straight line; a capture (`window_hold.tscn`) films one window held from the player's camera until a dead is in.
- **Check:** a path to a far room proves the map is joined, not that an opening is used. For every opening, ask the way
  from its own spawn to a point just inside it and compare it with the straight line, and look at the floor behind
  every window on the plan before it is built: a stairwell, a prop or a parapet there takes the opening away.
- **Docs:** [Map review: spawns](../engines/godot/map-review.md#3-spawns-and-how-the-dead-arrive),
  [Level design P6](../gamedev/level-design.md#p6-the-dead-arrive-out-of-sight-through-an-opening-the-player-can-see);
  Deadnight `docs/design/smallmap.md`, "The windows".
