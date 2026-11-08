---
areas: [tests, web, net]
---
# A quiet tab emulated by refusing its requests measured the refusal, not the tab

2026-11-05

- **Saw:** the browser probe for Deadnight #1188 stopped a host's lobby polls for 20 s to look like a tab in the
  background (the lobby must leave the list, keep its code, and come back with the next poll). With the polls
  `route.abort()`ed the lobby left the list and its code still worked, but after the polls were let through the lobby
  was not listed again for 10 more seconds, and the check failed.
- **Cause:** a tab in the background fails nothing: it does not ask. A refused request is an error (the console showed
  `TypeError: Failed to fetch`), and the game's next poll arrived about 10 s late, which is `HttpJson`'s own timeout:
  the refused request did not complete as a failure before it. The probe measured the game's handling of a network
  error, not a tab that is away.
- **Fix:** the probe holds the polls (the route handler keeps each `GET` of the lobby and lets it through when the host
  is "back") so the page waits as a frozen tab does; the lobby was listed again 0.1 to 0.8 s later. Check for next
  time: to emulate a page that is away, hold its requests; to emulate a network failure, abort them, and read the
  game's recovery from that as a separate case. A probe that also polls a rate-limited route (the list: 20 a 10 s per
  account) polls it every 0.8 s, not 0.5 (the first run read `429` as an assertion failure). Deadnight
  `tools/web_smoke/page_closing.py`.
- **Docs:** [Web export](../engines/godot/web-export.md) (a last request when the page closes).
