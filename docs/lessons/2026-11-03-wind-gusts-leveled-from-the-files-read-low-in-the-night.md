---
areas: [audio]
---
# Wind gusts leveled from their files stood only 3 to 5 dB over the base in the night

2026-11-03

- **Saw:** the drive-in's wind (Deadnight #782) was leveled from the files' loudness with the catalog's trims (a gust's
  loudest 400 ms -40 LUFS, the base -47), and the first night capture of the Ambience bus read the gusts at -44 to -42
  LUFS against a base at -47: 3 to 5 dB over it, hardly a gust, and the weakest drawn ones would have sat under it.
- **Cause:** a played 3D sound is not its file plus its trim. The gust sat 10 to 16 m off (`unit_size` 10: 0 to -4 dB),
  its
  level was a random draw under the strongest (up to -4 dB) and the night's own roll (-2.5 to +1 dB), and the bus carries
  the pan. Four to six dB went between the table and the stem, and the base (a flat bed) did not lose them.
- **Fix:** set the trims from a capture of the Ambience bus with the wind alone (`--solo`, the other beds stopped), the
  same seed as the run with the beds, and read each gust's momentary peak against the base median and against the beds'
  level a moment before (`tools/audio/wind_levels.py night`); the table of files only gives the starting trim. Pick the
  capture's seed by a probe of the plan (how many gusts, whether a detail falls in the two minutes), so the proof shows
  every part. Also: `Audio.play` returns null in a frame that used its sound starts (the sound plays a frame later), so
  a
  scheduler that reads the length from the returned player must not treat null as dropped and play another.
- **Docs:** Deadnight `docs/research/wind.md#levels`; [Starting sounds](../godot/audio.md#starting-sounds).
