---
areas: [audio, godot]
---
# A looping sound still playing at exit leaked its stream

2026-11-01

- **Saw:** CI's "resources still in use at exit" check failed after an ambient bed was added.
- **Cause:** a looping player outlived the scene that owned it and held its stream.
- **Fix:** stop every voice, loops included, when the owning scene ends, and let the audio service drop its streams on
  exit. Related: a Movie Maker wav is 32-bit integer PCM, so convert it before analysing with tools that expect float.
- **Docs:** [Audio](../godot/audio.md); Deadnight `docs/research/audio.md`.
