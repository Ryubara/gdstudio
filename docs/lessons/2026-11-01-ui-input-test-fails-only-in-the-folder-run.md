---
areas: [input, tests]
---
# A UI input test passes alone and fails in the folder run

2026-11-01

- **Saw:** Deadnight's settings tests (#346) and `test_touch_player` failed on CI and when the whole `tests/ui` folder
  ran, and passed alone.
- **Cause:** earlier suites left the main menu on the shared router. A full-rect Control with `MOUSE_FILTER_STOP` took
  every click and every touch-look motion before the code under test saw it. Keyboard tests passed, because key events
  skip mouse hit-testing.
- **Fix:** a test that sends mouse or touch input, or needs input to reach `_unhandled_input`, clears the router first
  (`await RouterFixture.clear(get_tree())`); suites that show screens clear it after each test.
- **Check:** run a new UI input test inside its whole folder before opening the pull request; on a CI-only failure,
  look first for what an earlier suite left behind.
