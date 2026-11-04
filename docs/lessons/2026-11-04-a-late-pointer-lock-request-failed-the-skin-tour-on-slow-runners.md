---
areas: [web, tests, ci]
---
# A late pointer lock request failed the skin tour on slow runners

2026-11-04

- **Saw:** Deadnight's `web` job failed the step "Tour the skin shaders in the browser" with `[pageerror] A user
  gesture is required to request Pointer Lock.` on #982, #1025 and main (#1027), and passed on some reruns.
- **Cause:** the tour ends by starting a night, and the mouse grip asks for the lock when the night has loaded. On a
  slow runner the request comes too long after the last key press, so the browser refuses it. `skin_tour.py` counts
  every page error as a problem. This is read from the code; throttled local runs did not reproduce it.
- **Fix:** Deadnight #1028 stubs `requestPointerLock` in the tour, as `activity.py` and `bot_wheel.py` already did.
- **Check for next time:** a browser probe that fails on any page error stubs what needs a user gesture when the probe
  is not testing it. When the same error fails a second pull request, file it then instead of rerunning: it had been
  listed as a known flake, and nothing tracked it.
