---
areas: [gameplay, godot, tests]
---
# A zombie's first mark made a node in the middle of a night, and the kill-allocations test failed

2026-11-02

- **Saw:** `tests/night/test_kill_allocations.gd` failed in CI: "3 nodes made over 14 kills: { "Node": 3 }".
- **Cause:** the outline component (`Outline`, a bare `Node`) was made the first time a zombie was marked, which is in
  the last round's last kills; the game pools bodies so that nothing is made after the warm-up, and the test says so.
- **Fix:** make the component with the body (`ZombieView.dress`, once per body, so the warm-up makes it) and the
  shaders' materials when `ZombieMarks` is set up; marking only flips a flag. I only ran the outline's own suites
  before pushing: run the neighbours that watch allocations (`tests/night`, `tests/zombies`) when a change touches the
  view pool.
- **Docs:** [Outline through walls](../godot/outline-through-walls.md#pitfalls).
