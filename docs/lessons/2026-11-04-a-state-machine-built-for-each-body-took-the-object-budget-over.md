---
areas: [godot, ci, general]
---
# Two states added to a state machine built for every body took the late-round object budget over its limit

2026-11-04

- **Saw:** Deadnight #1038 (the climb clips) failed the autopilot budget: `objects peaked at 21237, over its limit
  20500` (main's passing run: 19983). The change had added two states and four transitions to the zombies' machine and
  no node; nothing in its tests counts objects.
- **Cause:** `ZombieRig.attach` called `_build_state_machine()` for every body, so each zombie owned a whole machine
  (about 40 resources): 46 objects an `attach` (probe: `OBJECT_COUNT` before and after), and every state added to the
  machine was paid again for each body. A tree keeps its own playback and parameters, so the machine need not be per
  body.
- **Fix:** one static machine, cleared with the library in `release()`: 3 objects an `attach`. The same local run of
  the CI command: 20 839 objects with a machine each, 15 589 shared (limit unchanged). A test checks that two views
  share the `tree_root` and keep their own state. Teeth: the objects peak is the CI step; run it locally
  (`--autopilot --rounds=12 --startround=12 ...` and `check_budget.py`) for any change that adds to what a body builds.
- **Docs:** [AnimationTree](../godot/animation-tree.md), "Build the state machine once, share it between trees".
