---
areas: [audio, tests]
---
# A close sound's solo peak was read with the next sound in the window

2026-11-03

- **Saw:** leveling the loudest close sounds (Deadnight #753) from a recording of every file played alone, 0.8 s apart.
  The dead's voices read 0.0 dBFS at the engine's ceiling, which suggested the file's peak went to the mix unchanged,
  so the caps were set 3 dB too deep; a 70 ms impact read -0.6 dBFS one run and -16.7 the next.
- **Cause:** the window of each sound ran to the next one's start plus 0.2 s, and the voices (up to 3 s) overlapped the
  next play: a long sound's window held its successor's onset and a short one's held the blast that followed it. The
  gap between sounds was a constant, not the length of the file.
- **Fix:** the capture leaves each variant its file's length and 0.2 s (`--close`), and `close_levels.py` ends a
  window exactly at the next play. Measured again, a sound dead ahead is 2.5 to 3 dB under its file's peak and a click
  is 10 to 14 dB under it. The pinned table (`tests/core/close_sound_levels.json`) comes from that clean run, with the
  caps it was measured at, so a cap moved without measuring again fails a test.
- **Docs:** [Audio: a negative near cap](../godot/audio.md). Check: when a recording is cut into one window per sound,
  the windows cannot overlap another sound: print each window's start and end, and make the gap the length of the
  longest file, not a constant; read one sound twice (alone, then with the others) before trusting a table of them.
