---
areas: [tests, net, gameplay]
---
# A rule added to a picker broke a net suite that had only ever been skipped

2026-11-04

- **Saw:** `godot (4)` failed on a level-lock pull request: `test_lobby_settings_reach_the_night` ended with
  `Nonexistent function 'to_dict' in base 'Nil'` (the guest read no rules after the host sent them). The author's local
  run of `tests/net` had passed.
- **Cause:** the suite picks the back rooms (now level 10) through the real lobby picker with a fresh level-1 account, so
  the picker rightly refused the card, the host's map stayed the lot and the settings never changed. The suite needs
  Node 24 and `npm ci` in `spikes/backend` and is skipped without them (`PASSED 0ms`), so the local run never ran it;
  only CI has Node. The at-once case of the same suite had no "the move changed nothing" check, so it passed with
  nothing moved.
- **Fix:** the suite gives the host the level the map needs (`PlayerLevel.use(MapRegistry.find(SECOND_MAP).unlock_level)`,
  reset in `after_test`) and both cases fail when a move changed nothing. The code was right: a host below a map's level
  must not pick it.
- **Check:** before reporting a net change, `npm ci` in `spikes/backend` and read the suite's statistics line for
  `0 skipped`; a green run with skips is not a run of those tests. After a merge of main, import again
  (`godot --headless --import`) or new `class_name`s read as undeclared.
- **Docs:** Deadnight's `docs/design/maps.md#levels-open-maps` (the level lock); the node-backed suites are in
  [a skipped suite still waited for its backend](2026-11-04-a-skipped-suite-still-waited-for-its-backend.md).
