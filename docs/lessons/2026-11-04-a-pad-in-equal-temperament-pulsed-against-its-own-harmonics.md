---
areas: [audio]
---
# A synthesised pad in equal temperament pulsed against its own harmonics

2026-11-04

- **Saw:** the first render of a menu pad (a held D and A under chords of C, E, F, A in twelve-tone tuning, #979) had a
  loudness curve (400 ms, K-weighted) that swung 5 dB in dips every two to three seconds, a tremolo nobody had put
  there; a menu that stays open
  would be tired of first on that.
- **Cause:** a chord tone's third harmonic missed another voice's fundamental by a few cents (the D's third harmonic is
  440.5 Hz, the equal-tempered A is 440.0 Hz): two near-equal partials beat at the difference, here 0.5 Hz.
- **Fix:** tune every voice of a held chord as a just ratio of one root (the fifth 3/2, the seventh 16/9, the ninth 9/4)
  so each voice's partials sit on the root's harmonic series; keep only the beats that are put there on purpose (two
  sines
  a few cents apart, 0.1 to 0.2 Hz). The pad's loudest 400 ms then stood 1.5 dB over its median, with a 3 dB range
  over the
  76 s loop. Read it from the file's own loudness curve (`menu_music_levels.py files`), not by ear. A loop made of
  sines is
  seamless when each frequency is moved to the nearest whole number of cycles in the loop (under a tenth of a cent), and
  loops of lengths with no common factor never come back together.
- **Docs:** [Audio, Music that holds a long stay](../engines/godot/audio.md#music-that-holds-a-long-stay).
