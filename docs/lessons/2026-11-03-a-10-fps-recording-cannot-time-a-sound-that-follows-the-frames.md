---
areas: [audio, tests]
---
# A 10 fps Movie Maker recording put a beep every 0.1 s and stacked the quick ones in one frame

2026-11-03

- **Saw:** the grenade's beeps (a chain of timers that shrinks from 0.5 s to 0.09 s) analysed from the PNG movie the
  capture scene made at `--fixed-fps 10`: gaps of 0.4, 0.4, 0.4, 0.3, 0.2, 0.2 ... 0.1, 0.1, and three beeps found in
  all; a beep at the end of the fuse was at -5 dBFS, as loud as the blast (Deadnight #680).
- **Cause:** a sound schedule (`SoundSchedule.advance`) runs on the frames' delta, so at 10 frames a second every beep is
  started on a 0.1 s grid and the ones due inside one frame start together, adding up. The picture capture does not mind;
  the sound is made by the engine the same way, so the recording of it is quantised too. The beep's real timing was
  fine at 60 Hz (the unit test steps the clock by hand).
- **Fix:** time a sound pattern from a recording at the game's own rate with no pictures to encode:
  `--write-movie <abs>/x.avi --fixed-fps 60` (MJPEG, a small resolution), then `ffmpeg -i x.avi -vn -c:a pcm_s32le
  x.wav`; the capture prints the movie frames of the moments to look between, and the analysis reads inside them. Keep
  the 10 or 30 fps PNG movie for the pictures only. A pre-roll that waits for the dead to arrive runs at
  `Engine.time_scale = 10` and is set back to 1 before the part that is measured.
- **Docs:** [Audio: capturing sound](../engines/godot/audio.md#capturing-sound).
