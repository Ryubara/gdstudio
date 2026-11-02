---
areas: [godot, tests]
---
# Tests that wait physics frames but read process-driven nodes flake under load

2026-11-01

- **Saw:** a player suite failed one or two cases in about one loaded run in ten (shoulder swap, jump state, aim zoom,
  an animation event), and passed alone.
- **Cause:** a test waited N `physics_frame`s (fixed ticks) and then read a node that eases or animates in `_process`
  on the frame delta (wall time), so on a loaded machine the two drifted. Separately, a clip length rounded in a data
  file (0.333 s for a 0.3333 s event) ended an action one step before its last event.
- **Fix:** switch the node off (`set_process(false)`, `AnimationTree.callback_mode_process = MANUAL`) and step it by
  hand with a fixed delta inside the test's tick helper. Never measure waits with `get_process_delta_time()`. Hold an
  action until its last event, not until the rounded length. Reproduce with busy-loop headless Godots (killed by PID)
  and several suites in parallel.
- **Docs:** Deadnight `docs/research/player-controller.md`.
