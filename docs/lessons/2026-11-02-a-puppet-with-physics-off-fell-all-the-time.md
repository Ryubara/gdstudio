---
areas: [net, godot, tests]
---
# A puppet with physics off fell all the time, and its crouch never began

2026-11-02

- **Saw:** showing another player's sprint, crouch and jump (Deadnight #549), the drawn body of the other player never
  showed the crouch and read as falling: `on_floor` was false on every tick.
- **Cause:** (1) `make_puppet` called `set_physics_process(false)`, but the engine turns physics processing back on for
  a node that has a `_physics_process` when it becomes ready, so the puppet simulated with an idle command and, with no
  collision, never found a floor. (2) The body's state machine starts at `Start`, which has no way out of its own; a
  played body leaves it by falling at the spawn, a puppet on the floor never did, so the crouch (reached from the
  locomotion) never started.
- **Fix:** `_physics_process` returns early for a puppet, and the animation starts the machine at the locomotion. The
  tests read the legs' state on a second client's screen over a real socket, so a puppet's pose is the thing asserted.
- **Also:** the stance (sprint, crouch, in the air, rising) travels as one four-bit field per player, delta-coded, and
  the client draws the sample the interpolation clock is at, not the newest, so the carry starts when the body is seen
  to speed up.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#small-things-that-cost-time) and
  [AnimationTree](../engines/godot/animation-tree.md#a-state-machine-that-starts-at-start-and-has-no-way-out).
