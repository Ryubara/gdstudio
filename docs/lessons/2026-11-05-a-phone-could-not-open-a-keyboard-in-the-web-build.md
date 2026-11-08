---
areas: [web, input, godot-ui]
---
# A phone could not open a keyboard for any text field in the web build

2026-11-05

- **Saw:** the maintainer could not enter a room code on a phone in the Discord Activity (and maybe a phone browser):
  no keyboard opened (Deadnight #1183, 2026-11-05). Every `LineEdit` of Deadnight was dead on a phone.
- **Cause:** the web export had `html/experimental_virtual_keyboard=false`, the switch for the hidden `<input>` the
  engine focuses to raise a phone's keyboard; the page had no input and no `focus()` call. No test could see it: the
  game's tests type with key events, and the browser probes drove the menu with a keyboard. Beyond the switch, the
  engine focuses that input from `touchstart` (iOS wants the lift of the finger), its type is under 16 px (iOS zooms),
  nothing lifts a field above a keyboard that covers half a phone held sideways, and a button press took the keyboard
  away and the scene slid from under the finger.
- **Fix:** the option on; a page layer that makes the focus in the event that lifts the finger and sets the type to
  16 px; a lift of the router's layer that waits for the finger; a keypad for the room code that needs nothing from the
  browser; a browser probe that taps with a finger (`phone_keyboard.py`: it fails on the same build with the option
  off). A real keyboard on a real phone is not shown by an emulated browser: the pull request names that and gives the
  steps.
- **Check for next time:** a feature that takes text is run with a finger on a phone-shaped page before it is called
  done, and a platform's text path (open, type, close, submit) is a line of the plan, like its clipboard.
- **Docs:** [web export](../engines/godot/web-export.md#a-phones-keyboard-in-the-web-build).
