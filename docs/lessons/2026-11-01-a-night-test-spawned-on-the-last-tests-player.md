# A night test failed only after another night test: the last test's level was still standing

2026-11-01

- **Saw:** a grenade test (`the thrower is hurt once`) failed in CI after other night tests and passed alone.
- **Cause:** the suites built a whole level (Deadnight's `Night`) per test and never freed it, so the next test's
  player spawned on the old player's body and heard its grenades.
- **Fix:** a test that builds a level, or anything that owns bodies or players, frees it in `after_test`; a rerun
  would only have hidden it (Deadnight #356).
- **Docs:** [A leftover screen timer took the focus](2026-11-01-a-leftover-screen-timer-took-the-focus-only-under-load.md).
