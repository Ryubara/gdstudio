---
areas: [tests, godot]
---
# A probe between the suites of a real shard order named what each suite left for the next

2026-11-05

- **Saw:** a hang reported on `test_night_menu` after `test_menu_grips` could not be reproduced: the pair passed 13 of
  13 three times, and the one reproduced cause (a server left in `NightScreen.join_url`) came from a suite that was not
  in that pair. Reading suites for leaks found one at a time, by luck.
- **Cause:** GdUnit runs a shard in one process, so every `static var`, held input action and node under the root is
  inherited by the next suite; only the shard's own order shows it, and which suite leaves what is not written anywhere.
- **Fix:** a throwaway suite (never committed) between each two suites of the real shard order, from
  `tools/ci_test_shards.py --shard N`, that appends what changed since the last one to a file: the public `static var`
  lines of every global class (read from `script.source_code`, then `script.get(name)`; `get_script_property_list` does
  not list statics), `Engine.time_scale`, `paused`, the mouse mode, the window mode, the root's children and the held
  actions. Nine shards, about 150 entries each, listed every leaker by position (a leaked `join_map`, `return_lobby` and
  three held `ui_*` actions) in one run each; the hang order was not among them once `join_url` was cleared.
- **Check for next time:** to settle an order-dependent hang or failure, run the whole shard order with the probe and
  read the deltas before the suite that fails; "the pair passes" proves only that the pair is clean.
- **Docs:** the game's `docs/research/input-tests.md`, "What the orders that hung were".
