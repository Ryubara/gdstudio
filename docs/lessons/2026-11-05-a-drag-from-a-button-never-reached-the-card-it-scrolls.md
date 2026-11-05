---
areas: [godot-ui, input]
---
# A drag that started on a button never reached the card it should scroll

2026-11-05

- **Saw:** on a phone page a scrolling card (Deadnight's host lobby: Start, Leave, two copy buttons) scrolled from its
  words and margin and from nowhere else: a finger that began on a button moved nothing. Desktop mouse and wheel were
  fine, and the GdUnit suites with their `InputEventMouseButton` clicks all passed.
- **Cause:** `Button` has the mouse filter `STOP`, so every event of a finger that lands on it (the touch, each drag
  step, the lift, and the emulated mouse) goes to the button and to nothing above it; `ScrollContainer` scrolls from
  the touch events that reach it and never saw the finger. Logged in a web export with real touches
  (`Input.dispatchTouchEvent`): from the words the card got 2 touch, 12 drag and 14 mouse events, from a button none.
  Changing only the filter to `PASS` fixed it. And `PASS` alone is a regression: the card's `scroll_deadzone` is 0, so
  the first movement of the finger scrolls the card and takes the button's press (`NOTIFICATION_SCROLL_BEGIN`).
- **Fix:** every button class in a scrolling card sets `PASS`, and each scroll area gives a touch that lands on a button
  a slip before it scrolls (10 CSS px in units at the scale it runs at; a drag from anywhere else scrolls at once, as
  before). Measured on a phone page: slips of 0 to 9 px press and do not scroll, 12 px and up scroll and do not press;
  the mouse, the wheel and a controller act as before. Check for next time: any control that stops the pointer inside a
  scroll area, a touch test that sends `InputEventScreenTouch` and drag steps (headless cannot scroll by touch,
  `DisplayServer.is_touchscreen_available()` is false: test what the card receives and measure the scroll in a web
  probe), and a press that moves a little.
- **Docs:** [UI controls](../godot/ui-controls.md); Deadnight `docs/research/button-drag-scroll.md`.
