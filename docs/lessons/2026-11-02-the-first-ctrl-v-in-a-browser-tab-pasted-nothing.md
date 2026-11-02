---
areas: [web, input]
---
# The first Ctrl+V in a browser tab pasted nothing, because the fix for the Activity left tabs alone

2026-11-02

- **Saw:** in a plain browser tab, Ctrl+V into a text field of the game did not paste the first time (Deadnight #534);
  the Activity frame, fixed a day before, pasted at once. `activity.py --embed none --clipboard` showed an empty field.
- **Cause:** Godot's web runtime cancels every canvas `keydown`, so the browser never fires `paste`, and the engine's own
  paste is the asynchronous `navigator.clipboard.readText()`: the first press reads the old clipboard, the next one the
  new text. The Activity fix was written for "the frame" because the frame is where the API is denied, and it kept a tab
  unchanged on purpose; but the stale first press is a tab's problem too, and the `paste` event needs no permission.
- **Fix:** install the paste half of the page layer everywhere on the web (Ctrl/Cmd+V is let through to the browser, its
  `paste` text goes into the focused field) and keep copy the engine's in a tab. The probe also lost its counted key
  presses (Down, Down, Down) for a walk to a control by its name (`window.deadnight.focus`): the lobby had gained a rules
  panel and a row of two copy buttons, and the counts pointed at the wrong button.
- **Check:** a fix scoped to one host (an iframe, a platform) says in its note what the other hosts do and why; a web
  input fix is run in a tab and in the frame; a probe never counts key presses to reach a control.
- **Docs:** [Web export](../godot/web-export.md#discord-activity-copy-and-paste-in-the-frame).
