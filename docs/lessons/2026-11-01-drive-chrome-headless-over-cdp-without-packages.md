---
areas: [web, godot]
---
# The browser pass had no browser: drive headless Chrome directly

2026-11-01

- **Saw:** the Claude in Chrome tools answered "Browser extension is not connected".
- **Cause:** the extension needs a signed-in Chrome with the same account; a headless session has none.
- **Fix:** start Chrome with `--headless=new --remote-debugging-port=9333` and a throwaway profile (it still uses the
  GPU through ANGLE), and talk to it with Node's built-in `WebSocket` over the DevTools protocol:
  `Page.captureScreenshot`, `Page.startScreencast` for a transition (about 30 frames a second), `Input.dispatchKeyEvent`
  for keys, `Runtime.evaluate` for frame times. No package is downloaded; a gamepad cannot be injected this way.
- **Docs:** [Capture](../studio/capture.md).
