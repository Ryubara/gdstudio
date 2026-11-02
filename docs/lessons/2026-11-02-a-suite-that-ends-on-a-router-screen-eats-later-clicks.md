# Slider and toggle click tests failed only when the whole tests/ui folder ran

2026-11-02

- **Saw:** Deadnight's slider and toggle click tests passed alone and failed in the folder run (6 failures on `main`),
  while the key-driven tests of the same widgets passed.
- **Cause:** `test_ui_router.gd` and `test_ui_router_robustness.gd` ended every test with
  `UIRouter.reset(_screen("end"))`, and `test_night_mouse_look.gd` ended on the main menu. That full-rect screen with a
  stopping mouse filter stayed on the router stage (`/root/UIRouter/Stage/end`) and took the clicks of later suites.
  Found by running each suspect suite before the slider suite, then listing the controls under the click point.
- **Fix:** the leaking suites end with `RouterFixture.clear`, and click-driven widget suites also clear the router in
  `before_test` (Deadnight #458). The folder run then passed: 438 cases, 0 failures.
- **Check:** a suite that shows a screen on the router must clear it when it ends, not only the suite that clicks;
  never end a test by resetting the router to a screen.
- **Another case:** a menu left on the shared router answered the bumpers in later
  tests (Deadnight #466): it takes keys and buttons, not only clicks.
- **Docs:** the earlier, receiving-side version of this lesson:
  [UI input test fails only in the folder run](2026-11-01-ui-input-test-fails-only-in-the-folder-run.md).
