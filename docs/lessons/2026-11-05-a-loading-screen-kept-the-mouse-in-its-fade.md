---
areas: [godot-ui, input, tests]
---
# A loading screen that "let the mouse go" kept catching it for 0.35 s, and 12 clicks in a windowed suite failed

2026-11-05

- **Saw:** `test_night_menu` failed 12 of 13 windowed (every click and tap went nowhere) and `test_nothing_over_a_running_night_catches_the_mouse`
  named a `VBoxContainer`; headless both passed. The first failure (a tap on Resume) made the rest fail, because a
  suite's later tests waited for a menu that was still open.
- **Cause:** `LoadingOverlay.finish()` set the overlay's own `mouse_filter` to `IGNORE` and faded it for 0.35 s, but the
  box inside it was a container (default `PASS`) and the bar a `ColorRect` (default `STOP`); the control under the
  cursor gets the event, so a click in the first frames of a night went to the box. A headless run has no loading
  screen, so CI never had it.
- **Fix:** every control of a screen that has to let the game through is `IGNORE`, not only its root (`ui/screens/
  loading_overlay.gd`). To find the culprit, list the visible controls whose rect holds the point and whose filter is
  not `IGNORE`, then `get_viewport().gui_get_hovered_control()` after a click. When one failure is a click that did
  nothing, find the control that took it before reading the others.
- **Docs:** Deadnight `docs/research/windowed-night-ui-suites.md`.
