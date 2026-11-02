---
areas: [input, godot]
---
# Keys sent to a Godot web page do nothing, or are spent on focus

2026-11-01

- **Saw:** `page.keyboard.press("Escape")` went back, but the next `Enter` did not press Play; a quick tap sometimes
  did nothing.
- **Cause:** Godot reads input once per frame, so a press and release inside one frame can be lost. After a screen is
  popped nothing has focus, and the UI router uses the first arrow or accept key only to give focus.
- **Fix:** hold keys for about 150 ms in the test, and after Back press a focus key (Down, Up, Up) before Enter.
- **Docs:** Deadnight `docs/research/web-export.md`.
