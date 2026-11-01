# Movie Maker's WAV read as noise at twice the length

2026-11-01

- **Saw:** `--write-movie out.png` wrote `out.wav`; read as 16-bit PCM it was 97.2 s of noise for a 48.6 s video.
- **Cause:** The writer produces 32-bit integer PCM stereo at 48 kHz (`ffmpeg -i out.wav` says `pcm_s32le`), not 16-bit.
- **Fix:** Read it as `<i4` (divide by 2**31) or let ffmpeg convert: `ffmpeg -framerate 10 -i out%08d.png -i out.wav
  -shortest ...` to make an mp4 with sound.
- **Docs:** [Audio](../godot/audio.md#capturing-sound)
