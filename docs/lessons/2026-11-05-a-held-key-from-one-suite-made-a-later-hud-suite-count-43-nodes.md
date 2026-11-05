---
areas: [tests, godot-ui]
---
# A key one suite held and never released made a later suite count 43 nodes, and only in one shard split

2026-11-05

- **Saw:** `test_hud_refresh` (a break's countdown must make no nodes) failed with `Expecting: 0 but was 43` in CI on
  two unrelated pull requests, passed on `main`, alone, and as a pair with the suite before it in the shard.
- **Cause:** a CI shard runs its suites one after another in one process, and `Input.action_press` stays down until
  something releases it. `test_level_tags_online` held the scoreboard key for two tests and never let it go; the HUD
  reads that key every frame, so a later suite's HUD showed its scoreboard, which rebuilds its grid on the break's tick
  (a heading row and four player rows, 43 nodes). Adding suites moved the shard split and put the two in one process
  with nothing between that releases the key. Logging `node_added`'s path and class under the HUD named the scoreboard
  at once; the pair `[leaker, victim]` reproduced it in two minutes, where the whole shard took ten.
- **Fix:** the leaking suite releases the action in `after_test` (a release at the end of a test is skipped by a failed
  assert), and a scan test (`tests/core/test_input_left_clean.gd`) fails a suite that presses an action in a function
  that does not release it and has no hook that does. The assertion stayed as it was.
- **Check:** a CI-only count or state that is wrong by "something is on" is global state an earlier suite left: input
  actions held, a static, a router screen, a setting. Take the failing shard's suite list from its log, bisect to the
  pair, and print what the count is made of before forming a theory. A suite that presses an action releases it in
  `after_test`.
- **Docs:** the game's `docs/research/input-tests.md`, "A held action outlives its suite".
