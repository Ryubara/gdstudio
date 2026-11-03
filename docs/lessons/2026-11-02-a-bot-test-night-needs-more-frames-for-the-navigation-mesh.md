---
areas: [tests, godot]
---
# An errand test found no errand once, when the navigation mesh had not been taken in

2026-11-02

- **Saw:** Deadnight #229: a night test of three shopping bots passed twice, then failed once with no bot on an errand
  for 90 game seconds; nothing in the code had changed between the runs.
- **Cause (likely, not proven):** the test gave the navigation server 12 physics frames; on a busy machine the mesh was
  not in by then, the errands' probe of the way to each stand failed, and `BotErrands` leaves a stand it cannot reach
  alone for 180 s, so the whole test ran inside that back-off.
- **Fix:** 60 frames (`SETTLE_FRAMES`, as the errand suites' bought-door tests use); a test that depends on a path waits
  for the map before it starts the clock.
- **Docs:** Deadnight `tests/night/test_bot_team.gd`.
