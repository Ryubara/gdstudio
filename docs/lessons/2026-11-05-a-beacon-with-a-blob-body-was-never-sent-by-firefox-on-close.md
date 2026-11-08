---
areas: [net, web]
---
# A beacon with a Blob body was never sent by Firefox when the tab closed

2026-11-05

- **Saw:** Deadnight #1188 (a lobby whose only player closed the tab stayed listed for the 10-minute backstop) needed a
  request from `pagehide`. The first version of the probe sent `navigator.sendBeacon(url, new Blob([json], {type:
  'text/plain'}))`, the form most examples show, and passed in Chromium and WebKit; in Firefox the lobby was still there
  after 15 s, five closes of five. The same beacon sent from a navigation (`page.goto`) arrived, and so did a `fetch`
  with `keepalive`.
- **Cause:** Firefox reads a Blob body after the page is gone, and closing the tab ends that read; a navigation keeps the
  page long enough. A string body (`sendBeacon(url, json)`, typed `text/plain;charset=UTF-8` by the browser) is read at
  once and arrived 5 of 5. Two more findings on the way: an `application/json` Blob is not a "simple" request, needs a
  CORS preflight and was sent by none of the three engines; and a `fetch` with an `Authorization` header (the #1177
  worry) arrived in all three, in two round trips instead of one, so "cannot be relied on" is not a thing to assume
  either way.
- **Fix:** the page sends `sendBeacon(url, string)` (the token in the body, `text/plain`) and falls back to a
  `keepalive` fetch with the same simple request; the backend route reads the body. Check for next time: a request sent
  while a page closes is proved by closing a real tab (`page.close()`, not a script's `window.close()` or a
  navigation) in Chromium, Firefox and WebKit, over a real network or a proxy that holds each request 150 ms, and the
  table of what arrived, per engine, goes in the design page. Deadnight `tools/web_smoke/page_closing_transport.py`.
- **Docs:** [Web export](../engines/godot/web-export.md) (a last request when the page closes).
