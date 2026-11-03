---
areas: [audio]
---
# A yard sound came in at the farther of two windows

2026-11-03

- **Saw:** a test of the second map's yard (a loop 25 m beyond a window, a listener 4.6 m inside it, in line) found
  the sound coming from a window 9 m to the side: `way.window` was `start_2`, not `start_1`.
- **Cause:** the windows were ranked by the dB the router still had to add on top of the engine's own fall-off at the
  window (`20 log((unit + near) / (unit + total))`). That number is bigger (less negative) for a window that is
  farther from the listener, because the engine has already taken more off. It says what is left to add, not how
  loud the sound is.
- **Fix:** rank by the loudness of the whole way round (the same number less the engine's fall-off at the window), the
  shortest path first, then add only the remainder to the player's level.
- **Docs:** [Sound through windows](../godot/audio.md#sound-through-windows-not-walls-deadnight-657).
