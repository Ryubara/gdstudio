---
areas: [audio, gameplay]
---
# A warning beep vanished behind a wall: the audio service low-passes a sound there and a high tone is gone

2026-11-03

- **Saw:** a grenade's fuse beep (a 2.6 kHz tone, built and unit-tested as playing at the grenade) measured on a real
  recording of a throw into a pack: three beeps heard in the hand and none after, the grenade lying behind a wall at -40
  to -80 dBFS. The service had started every voice (a debug print of the returned player showed `playing`); nothing
  was wrong with the events or the schedule (Deadnight #680).
- **Cause:** every 3D sound that has a wall between it and the listener is 9 dB quieter and low-passed at 1.1 kHz
  (13 dB quieter in the web build, which has no filter), a rule made for gunfire. A tone above the cutoff does not come
  through at all. Tests that assert "a sound was played at the grenade" pass whatever the mix does to it, and a capture
  at 10 frames a second could not show it (see the next lesson).
- **Fix:** a warning that has to carry through cover is built to survive the mix: a lower tone (1.1 kHz with two
  harmonics, which the low-pass lets through) and a per-sound `SoundDef.occlusion_scale` (0.35 for the beep, 1 for
  every other sound) that takes only that share of the dulling. A test asserts the beep keeps more of its level and
  cutoff than a shot behind the same wall, and `tools/audio/beep_report.py` reads the beeps' tone out of the real mix.
  The same recording also showed the first level (-9 dBFS at the ear) as loud as the blast, and fixed that.
- **Docs:** [Audio: warnings that must carry](../engines/godot/audio.md#warnings-that-must-carry-through-cover); check:
  a
  sound the player must act on (a fuse, a siren, a revive call) is recorded through the real service from behind a
  wall and from across the lot, and its level read in the mix, not asserted from the events.
