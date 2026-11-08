---
areas: [audio, godot]
---
# A yard fence counted as a wall for the sound's rays

2026-11-03

- **Saw:** every yard loop behind the second map's windows was heard through the wall (-15 dB, dull) although the
  window was clear: the ray from the window to the source stopped at `FenceS` 15 m out.
- **Cause:** the yard's fences, like the building's walls, are on the physics layers the audio rays read (layer 2 is
  the wall layer on purpose, so a fence blocks a shot and a step). The ray had nothing to tell a fence from a wall.
- **Fix:** keep the ray's layers, and when it hits something under the map's `Outside` group (fences, ground), add that
  hit's `rid` to `exclude` and cast again, up to a dozen times; only a hit on the building is a wall. The window's own
  players-only blocker is excluded the same way.
- **Docs:** [Sound through windows](../engines/godot/audio.md#sound-through-windows-not-walls-deadnight-657).
