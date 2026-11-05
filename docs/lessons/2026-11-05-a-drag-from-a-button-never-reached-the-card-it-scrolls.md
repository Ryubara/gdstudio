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
- **Fix:** a button passes the pointer (`PASS`) only while a scroll area that stops it is above it (decided on
  entering the tree, so a reparent is right), and stops it (`STOP`) everywhere else; the area stops the pointer itself
  and gives a touch that lands on a button a slip before it scrolls (10 CSS px in units at the scale it runs at; a drag
  from anywhere else scrolls at once, as before). Measured on a phone page: slips of 0 to 9 px press and do not scroll,
  12 px and up scroll and do not press; the mouse, the wheel and a controller act as before.
- **Review found the first fix leaked:** it set `PASS` on every button, wherever it sat. A `PASS` button with nothing
  above it that stops the pointer presses once and then lets the click go on to `_unhandled_input` (2 events for a click,
  4 for a tap): the end board's Leave, whose ancestors all ignore the pointer, would have given the player the pointer
  lock as it was clicked. The engine's `ScrollContainer` is itself `PASS`, not `STOP`, so a button under a plain one
  leaked too. My tests had only put buttons inside a card.
- **And a button stayed lit:** the first capture after the fix showed Start in its hover look 1.2 s after the finger
  lifted. A finger that lifts sends no mouse exit, so the engine keeps the button it lifted over hovered; before, a drag
  moved the finger off the button, now the card moves with the finger and it lifts over it (a plain tap always left the
  button lit). The scroll area now takes the hover off its buttons when a touch that scrolled it lifts (the filter set to
  `IGNORE` and back makes the engine send the exit, hiding the button also drops its focus). Measured in the web export
  by the colour of the fill after the lift against after a touch elsewhere (95, 68, 81 lit; 23, 2, 7 resting). Look at
  the capture of the resting state, after the lift, and measure the look: the press that a scroll gave up is not the
  only state a finger leaves behind.
- **And a plain tap stayed lit too (Deadnight #1268):** the same missing exit, in a card or outside one (Copy the link
  after a tap: 70 apart from rest, 2 after the fix). It is fixed from the event that lifted, never from the device: a
  touch release (`InputEventScreenTouch`) takes the hover off after the press spring has settled; a mouse release does
  not, so a desktop mouse keeps its hover; a real mouse motion or a new touch calls it off; the timer holds the
  button's instance id, so a press that frees its own button leaves nothing to resume.
- **Check for next time:** a control whose mouse filter you change is tested where it is NOT used as well as where it
  is (alone under a host that ignores the pointer, as a HUD board is), with the real events through the `Input`
  singleton (a click and a touch tap) and a spy on `_unhandled_input`; the game's own end board is the minimal case.
  A probe of pointer input needs a window as large as the controls it clicks: a headless project's window is 64 x 64,
  and a probe that clicks a button at x = 200 reads "not pressed" for a button that is simply outside the window. A
  touch test that sends `InputEventScreenTouch` and drag steps (headless cannot scroll by touch,
  `DisplayServer.is_touchscreen_available()` is false: test what the card receives and measure the scroll in a web
  probe), and a press that moves a little.
- **Docs:** [UI controls](../godot/ui-controls.md); Deadnight `docs/research/button-drag-scroll.md`.
