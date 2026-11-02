---
areas: [web, input]
---
# The gamepad did nothing in the Discord Activity until the player clicked in it

2026-11-02

- **Saw:** "gamepad support is not working on discord activity" (Deadnight #479), while the same pad worked in the
  browser build. The maintainer later found it working after launching the game, clicking in the window and moving
  the left stick.
- **Cause:** the Activity is an iframe in Discord's client and starts without the keyboard focus
  (`document.hasFocus()` is false). Chromium lists no gamepad to a frame without focus, and lists one only after it
  sees an input. Godot's web runtime catches what `navigator.getGamepads()` throws and lists no pads, so the failure
  is silent. Not the Gamepad permissions policy (allowed) and not Steam Input.
- **Fix:** Deadnight #482: `window.focus()` and the canvas focus on pointerdown and keydown while the frame lacks the
  focus, and a probe line on the Play together screen that says which part fails (policy, focus, a press) with the
  counts the page saw, so a player is told to click once.
- **Check:** an embedded web build is tested from an unfocused start, in a headed browser (headless Chromium reports
  the focus as held), and the pad is proved after a click. A virtual pad proves our code path, not the browser's
  focus rule: say which one a test proved.
- **Docs:** [Web export](../godot/web-export.md#discord-activity-the-proxy-and-the-iframe).
