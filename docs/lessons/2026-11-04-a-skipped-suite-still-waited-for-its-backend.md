---
areas: [tests, net]
---
# A whole-folder net run looked stalled while skipped suites waited for a backend

2026-11-04

- **Saw:** a run of `tests/net` ended with exit 124 (the outer `timeout`) with the log stopped inside
  `test_night_revive_online`, so it was reported as a stall of that suite. Alone, that suite passes 5 of 5 in 37 s on the
  branch and on `origin/main`. A second whole-folder run printed `test_lobby_online` tests as skipped (`PASSED 0ms`,
  "needs node 24 and npm ci in spikes/backend") yet advanced about a test a minute.
- **Cause:** the folder is 55 suites and takes longer than a 10 minute cap on a loaded machine; and the node-backed
  online suites do their `_start_stack()` (node plus a 90 s wait for `/health`) in `before_test`, before the skip is
  reported, so a worktree without `npm ci` pays the wait per skipped test (#1049). A timed-out run also leaves the
  children it started (a `bots_soak` Godot) alive.
- **Fix:** do not call a timeout a stall: run the named suite alone on the branch and on main and compare; run a big
  folder in chunks with a long timeout in the background; stop leftover children by PID after a timeout.
- **Docs:** none beyond this lesson.
