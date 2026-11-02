---
areas: [web, input]
---
# Copy and paste did nothing in the Discord Activity, and "Code copied." was shown anyway

2026-11-02

- **Saw:** "Copy paste doesn't work when in discord activity" (Deadnight #516). Copying the room code left the old
  clipboard text, pasting a code into the Join field did nothing, and the screen said "Code copied."
- **Cause:** two things the engine reports neither of. The Activity is a cross-origin iframe with no `allow=`, so
  `clipboard-read` and `clipboard-write` default to `self` and `navigator.clipboard.writeText/readText` throw
  `NotAllowedError`; Godot's `DisplayServer.clipboard_set/get` are exactly those calls. And Godot's web runtime calls
  `preventDefault()` on every canvas `keydown`, so Ctrl+V never makes the browser's `paste` event (the one that needs
  no permission); its own paste is async `readText`, so even where the API is allowed the first Ctrl+V pastes stale text.
- **Fix:** Deadnight #533: a page layer that exists only inside a frame. Ctrl/Cmd+V is let through to the browser and
  the `paste` event's text goes into the focused field; copy runs from the press (hidden textarea and
  `execCommand("copy")`, then the API) and says "copied" only when the page confirms; when nothing can copy, the text is
  shown selected with "press Ctrl+C"; the SDK's `shareLink` sends the code without the clipboard at all.
- **Check:** any feature that moves text in or out of the game (codes, names, links) is run in the Activity iframe
  harness with a denying policy (`permissions-policy: clipboard-read=(), clipboard-write=()`), and a "done" message is
  shown only after the platform confirms the result.
- **Docs:** [Web export](../godot/web-export.md#discord-activity-copy-and-paste-in-the-frame).
