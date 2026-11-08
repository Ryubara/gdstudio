---
areas: [audio, blender]
---
# Quitting right after stopping a sound leaks its stream, more often on a busy machine

2026-11-01

- **Saw:** a headless run that stops its audio and quits printed `ObjectDB instances were leaked` and `resources still in
  use` at exit, at random: 0 of 6 on a quiet machine, a few in 20 on a loaded one. The leaked objects were
  `AudioStreamPlayback*`, `OggPacketSequence*` and their streams.
- **Cause:** `AudioStreamPlayer.stop()` only marks the playback for removal; the audio server keeps it, and its stream,
  until the mixer thread has taken a few steps. A fixed real-time wait before `quit()` (0.3 s) is not enough when the
  mixer thread is starved.
- **Fix:** wait on the mixer's own steps, not time: after `stop()`, poll `AudioServer.get_time_since_last_mix()` once
  per frame and count each time it falls, until about four steps have landed (with a poll cap). A test checks a stream's
  `get_reference_count()` returns to its earlier value after the wait.
- **Docs:** [Audio](../engines/godot/audio.md).
