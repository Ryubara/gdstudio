---
areas: [gameplay, tests]
---
# New breaches tripped two guards that had only ever seen the field's six

2026-11-03

- **Saw:** after the midway, yard, back lot and plaza got boarded breaches like the field's (Deadnight #849), four
  checks went red: `test_kill_allocations.gd` ("6 nodes made over 14 kills": `MeshInstance3D` named `Torn1` to `Torn4`
  under `Midway/BreachPocketEGap`), `test_spawns_wait_for_the_map.gd` (the midway's spawns were in the pool the tick the
  door was bought, before the map had the room), and two tests that counted "6" breaches.
- **Cause:** both guards had passed only because nothing but the field's six breaches ever did the thing. A
  `Barricade` made its pool of torn-board copies the first time a board came off, a node entering the tree in the
  middle of a fight, which the field's breaches did before the warm count began; a bay in the midway tore for the
  first time inside the counted kills. And `NightWorld._walkable` asked a gated spawn only for the way from where the
  dead rise to the inside of the boards: with the door just bought, the area is an island in the old mesh and both
  points are on it, so the answer was yes before the map walked from the field.
- **Fix:** the pool of five copies is made when the breach is built, and `_walkable` also asks for the way from the
  field to the inside of the boards. The counts became the rules' own list.
- **Docs:** Deadnight `docs/research/later-breaches.md`. Check: when something starts doing what only one place did (a
  gate, a first tear, a first spawn), search the tests and the code for "the field's six", for a hard-coded count, and
  for state made on first use, and run the night and bot suites before the pull request, not after.
