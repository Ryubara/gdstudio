---
areas: [web, godot]
---
# A cached answer was asked of the page again and again, because `eval` handed back an int

2026-11-04

- **Saw:** `GamepadProbe.in_frame()` is meant to ask the page once (`static var _framed`), yet a plain page saw its
  `eval` about 5 times a second (188 in 40 s, Deadnight #983).
- **Cause:** the web runtime hands a script's `true` back as the integer 1 (`typeof(...)` is `TYPE_INT`), and
  `framed == true` on an `int` is an invalid operation. A release build ends the function there without printing
  anything and returns null, so the line that stores the answer never ran. Found by logging with a second `eval`
  (`console.log`) after each statement: the last log that appeared named the line. The same function also never
  said "in a frame" in a Discord Activity, since it never got past the comparison.
- **Fix:** read the answer with `bool(answer)` (and `answer != null`), never `== true`; a script's number is read with
  `int(...)` the same way. A static function turns the answer into a bool and a test feeds it 1, true, 0, false and
  null.
- **Check for next time:** a cache that "does not hold" on the web: log after each statement of the filling code before
  guessing at the engine; compare a `JavaScriptBridge` answer with `bool()`/`int()`, not with `true`.
- **Docs:** [Web export](../engines/godot/web-export.md).
