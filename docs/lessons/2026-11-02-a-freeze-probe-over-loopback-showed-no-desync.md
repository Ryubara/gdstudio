---
areas: [net, web, tests]
---
# The freeze probe passed on the broken build, because loopback has no round trip

2026-11-02

- **Saw:** the browser probe that stalls the page (Deadnight #502) was first run on a client built without the #483
  fix, against a server on the same machine, and every stall came back within 1.2 m of the server: a probe that
  could not fail.
- **Cause:** the desync of #483 is a feedback loop that only runs away when the round trip is a few frames; loopback is
  under 2 ms. Chrome's network throttling does not apply to WebSockets, so the probe had no way to add a delay.
- **Fix:** a TCP relay in the probe holds every chunk back 100 ms each way, in order; the same old client then flew off
  to 10^22 m and the fixed one stayed within 0.03 m. Run any "does it come back" probe on a build known to be broken
  first, and give it the link conditions the bug needs.
- **Docs:** [Multiplayer](../godot/multiplayer.md#the-same-in-the-browser-deadnight-502).
