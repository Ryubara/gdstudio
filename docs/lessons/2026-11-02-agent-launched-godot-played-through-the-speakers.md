---
areas: [tools, audio]
---
# Agent-launched Godot and browser probes played through the speakers

2026-11-02

- **Saw:** the maintainer heard sound from captures, autopilots and probes that agents ran, although `gds godot` and
  `gds quiet` already hid the window and freed the cursor.
- **Cause:** the wrappers protected the keyboard and mouse only. A windowed Godot opens WASAPI (measured: the driver
  name is `WASAPI`, the three output devices of the machine are listed) and plays; Playwright mutes only a headless
  Chromium (`--mute-audio`), not a headed one or Firefox.
- **Fix:** `gds godot` adds `--audio-driver Dummy` (`--with-audio` opts out), the hook refuses a real driver from a
  session, `--headless` and Movie Maker already force Dummy, and Deadnight's probes add the mute under `GDS_QUIET=1`.
  The Dummy driver still mixes: a bus peak and an `AudioEffectCapture` read the same numbers headless and windowed.
- **Docs:** [Sound](../godot/no-focus.md#sound).
