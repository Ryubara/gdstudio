---
areas: [tests, godot-ui, input]
---
# A suite opened the night through the Play screen, and the guard for the drop never saw it

2026-11-06

- **Saw:** `test_night_tap_targets` failed in the first scheduled windowed run of Deadnight (issue 1348) with
  `screen.touch_active()` false, three times, and it failed the same way in a window on a GPU. Headless it passed.
  Three days earlier a guard test had been written for exactly this (a suite that opens a night must say whether the
  helicopter drop is due), and it was green.
- **Cause:** a window plays the drop and the touch layer is the show's until it ends. The guard scanned for a push or
  reset of the night scene or of `NIGHT`, and this suite (like the credits and the report suites) reaches the night by
  `UIRouter.reset(PLAY)` and `play.start()`, so no line in the file names the night.
- **Fix:** each suite sets `NightScreen.arrival_enabled = false` and restores it, and the guard also reads
  `play.start()` (its scan test says what is and is not a start). A scan of source is only as good as the ways in it
  knows: when a check is written for "every suite that does X", list the ways X is reached in the game's own flow
  (here the router and the Play screen's Start), not the one the first suite used. Once the layer was up the suite's
  own check ran for the first time: every touch hit area is 44 CSS px or more, so the game was right.
- **Docs:** Deadnight `docs/research/windowed-ui-ci.md` ("The headless guard") and
  `docs/research/windowed-vs-headless-tests.md` ("The first scheduled run").
