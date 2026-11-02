---
areas: [audio, godot]
---
# Every shot and kill hitched the web build: each Ogg start cost about a millisecond

2026-11-01

- **Saw:** a 6 to 8 ms hitch in every frame with a shot or a kill in the single-threaded web build, while the
  resource count stayed flat, so it looked like no leak (Deadnight #387).
- **Cause:** `AudioStreamPlayer.play()` on Ogg Vorbis re-reads the headers and codebooks (about 0.8 ms each, 43 ms for
  a minute of music), and a frame that starts six sounds pays six times. Effects and bodies made and freed per shot
  added node and shader rebuilds on top.
- **Fix:** decode short sounds (up to 2.5 s) once to `AudioStreamWAV` with `AudioStreamPlayback.mix_audio` while
  loading (about 0.3 ms to start); cap sound starts per frame and defer the rest a frame or two; start beds that come
  and go silent and paused, then fade them; pool effects and bodies and build them before the night (Deadnight #402).
- **Check:** at the start of a hitch task, look for objects made inside the frame (lights, meshes, labels, audio
  players) before profiling the GPU: a GdUnit test that counts nodes and objects over a run
  (`Performance.OBJECT_COUNT`, `OBJECT_NODE_COUNT`) fails on an allocation per kill. Measure a hitch by frame kind (a
  shot, a kill) with a probe around each handler.
- **Docs:** [Audio](../godot/audio.md#starting-sounds); Deadnight `docs/research/kill-spike.md`.
