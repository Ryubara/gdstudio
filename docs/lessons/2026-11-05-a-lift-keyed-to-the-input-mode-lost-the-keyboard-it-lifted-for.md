---
areas: [web, input, godot-ui]
---
# A keypad and a lift keyed to "a finger was used last" never came up on the web

2026-11-05

- **Saw:** on a phone-shaped browser page (Deadnight #1183) the room code's keypad did not open, then the lift that keeps
  a field above the keyboard dropped the scene as soon as the first letter was typed.
- **Cause:** both asked `UIInputMode.touch`. On the web the mouse press the engine makes of a touch
  (`device == InputEvent.DEVICE_ID_EMULATION`) reaches the game before the `InputEventScreenTouch`, so a field that
  takes the focus on that press sees the input mode still on the mouse. And the engine's own keyboard path sends the
  arrow keys that place the caret as key events, so a phone being typed on reads as a keyboard.
- **Fix:** decide "a finger did this" from the press itself (an emulated mouse press or a screen touch just before the
  focus), and let the lift ask only whether something covers the page (`visualViewport` against `innerHeight`, or the
  keypad's own height). The tests print what reached the game (`print` in the handler) before any guess about order.
- **Docs:** [web export](../godot/web-export.md#a-phones-keyboard-in-the-web-build).
