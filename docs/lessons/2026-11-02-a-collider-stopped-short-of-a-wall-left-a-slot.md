---
areas: [gameplay, tests]
---
# A hidden collider stopped 0.4 m short of a wall and a bot sat in the slot

2026-11-02

- **Saw:** in a bot soak (Deadnight #564) one bot stood at about (9.6, 0.2, 4.7) for 61% of its walking time with a
  falling velocity of -40 and alternating wishes, against two colliders at once (100 contact reports on the wall, 57 on
  the soda fountain's block). Put a player-sized capsule in that spot in the lot and no wish moves it (its vertical
  velocity runs to -80 and its position does not change).
- **Cause:** the fountain is drawn by a prop, and the greybox keeps a hidden block for its collision. The block ended at
  x 9.4 and the stand's east wall began at x 9.8: a 0.4 m channel, narrower than the 0.7 m body, so a body in it is
  pressed by both sides and cannot be pushed out by its own wish. The navigation mesh never routes there (agent radius
  0.5), so nothing in the tests walked near it; only a dodge rule that sidestepped bots found it. A layout is placed by
  hand, one box at a time, and nobody looks at the space left between two boxes.
- **Fix:** a scan, not a soak, finds these: read every collision box as a shape on the ground and list each pair of
  faces that face each other for half a metre or more at 0.24 m up to a body's width, with no other collider between
  them (`tests/world/lot_gaps.gd`, `test_lot_gaps.gd`; the test shows the scan finds a 0.4 m channel and ignores a seam,
  a wall in between and a roof). The lot had twelve; the generator now makes the block touch the wall and puts every
  prop touching its wall or a body's width off it. A hidden collider is placed against the thing it fills in, never
  "about there". Run the scan whenever a box moves.
- **Docs:** Deadnight `docs/design/map.md`, "Slots a body wedges in".
