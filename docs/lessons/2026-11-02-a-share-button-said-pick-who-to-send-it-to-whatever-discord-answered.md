---
areas: [net, web]
---
# Share in Discord said "Pick who to send it to" and Discord opened nothing

2026-11-02

- **Saw:** "Share in Discord didn't pop up the discord window" (Deadnight #627). The lobby said "Pick who to send it
  to in Discord's window." and no window came. The button had been added with a harness whose stand-in bridge answered
  `Promise.resolve(true)`, so the real client's answer was never seen.
- **Cause:** the game fired the Embedded App SDK's `shareLink` (a fire-and-forget `JavaScriptBridge.eval`) and showed
  its hint on the next line, so the sentence said nothing about Discord. The bridge turned every failure into `false`
  and logged `String(error)`, but the SDK rejects with the client's own `{code, message}` object (`[object Object]`), and
  a reply it cannot parse (`handleFrame` logs `Failed to parse` and returns) leaves the promise pending for ever, which
  looks exactly like an open window. `shareLink` also answers when its window is **closed**, not when it opens, so
  there is no "opened" signal at all: a command not refused after a second is the nearest sign.
- **Fix:** Deadnight #627: `deploy/web/discord-share.js` keeps the real answer (error, `success`, the raw frame from the
  page's `message` events, the `openInviteDialog` fallback) as a verdict; the lobby shows the hint only while Discord has
  not refused, says "did not open" and points to Copy the code on a refusal, and a probe line quotes the answer.
- **Check:** a message that promises something happened ("Pick who to send it to in Discord's window") is shown only
  after the platform's answer says it did, and a call into a host (the SDK, the clipboard, a permission) is read through
  a seam that keeps the host's own error and raw reply; a harness stands in for the host with answers a client can
  give (refused, an error object, silence, an unreadable frame), runs the shipped bridge code, and fails before the fix.
- **Docs:** Deadnight `docs/research/web-export.md`, "Share in Discord: what Discord answered (#627)".
