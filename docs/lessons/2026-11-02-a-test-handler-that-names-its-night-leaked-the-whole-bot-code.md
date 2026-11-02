---
areas: [tests, gameplay]
---
# A test handler that named its night leaked 207 objects at exit

2026-11-02

- **Saw:** Deadnight #597 (bot shopping). Every one of 939 tests passed, and CI shard 1 still failed: `207 ObjectDB
  instances were leaked at exit` and `93 resources still in use`, naming the GdUnitTestSuite script and every bot,
  rules and zombie script. A run of the two new night suites alone showed it was one of them.
- **Cause:** a test set `night.on_event = func(event): ... night.server.rules ...`. `night` is a RefCounted
  (`SeatedNight`) that stores the handler, and the handler's lambda holds `night`: a cycle nothing breaks, so the night,
  its server, the bots and the scripts they use stay alive past the test. The older suite that does the same
  (`test_bot_combat.gd`) resets the handler by hand at the end, which is why main had no leak.
- **Fix:** `SeatedNight.dispose()` sets `on_event = Callable()` first, so no test has to remember. Found by running each
  new suite alone and grepping its log for `leaked at exit|still in use`, which names the suite in a minute where the
  shard log (70000 lines) does not.
- **Check for next time:** a handler stored on an object that the handler itself names is a cycle: clear it in the
  object's `dispose()` (or close/free method), not in each test; after adding a suite, run it alone and grep for the leak
  lines before the pull request.
- **Docs:** related: [a lambda cycle](2026-11-01-refcounted-lambda-cycle-leaks-at-exit.md) and [a run that printed
  leaks no test
  reported](2026-11-01-a-gdunit4-run-printed-leaks-at-exit-that-no-test-reported.md).
