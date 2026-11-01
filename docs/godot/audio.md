# Audio

Draft for `docs/godot/audio.md` in the kit (from Deadnight's sound design, issue 43). Game specifics are in Deadnight's
`docs/design/audio.md` and `docs/research/audio.md`.

## Making sounds with code

Original, committable sounds: numpy and scipy through `uv run --with numpy --with scipy`, one function per sound, a seeded
`numpy.random.Generator` (seed = CRC of the name and variant number), WAV to the pinned ffmpeg, Ogg Vorbis quality 4 with
`-fflags +bitexact -flags:a +bitexact` so two runs give byte-identical files. Building blocks that cover a lot:

- Gunshot: crack (high-passed noise, ~10 ms) + blast (low-passed noise with a falling cutoff) + body (a falling sine),
  soft-clipped, one slap echo, a decaying darkening noise as the room.
- Struck metal: damped sines at inharmonic ratios (1, 1.58, 2.31, 3.37, 4.9) plus a 3 ms noise transient.
- Voice: a jittery sawtooth through two vowel formant sets, crossfaded, with breath noise and low-passed-noise
  amplitude.
- Loops: make every part a whole number of cycles in the loop length; filter noise in the frequency domain; give hard
  envelopes a 2 ms attack.
- Convert a duration to samples with one rounding helper, not `int()`.

Without ears, check with log spectrogram sheets (`ffmpeg -i a.wav -lavfi showspectrumpic=s=700x180:legend=0:scale=log:fscale=log`),
peak levels and loop seams; judging taste is a human's job.

## Service shape that worked

Pooled `AudioStreamPlayer`/`AudioStreamPlayer3D` (no nodes created while playing); a pure `RefCounted` budget that hands
out slots (group limits, priority, a loudness margin so a voice is not stolen back and forth, per-sound cooldown) and
takes time as an argument so tests need no clock; a seeded generator for variant and pitch; `AudioEffectAmplify` added
to a bus at runtime for ducking (leaves the bus volume to the player's settings; remove it in `_exit_tree`); per-player
`attenuation_filter_cutoff_hz` and `volume_db` for occlusion; a `Callable` probe for what blocks sound.

## Capturing sound

- `--write-movie <absolute folder>/name.png --fixed-fps 10` also writes `name.wav`: 32-bit integer PCM, stereo, 48 kHz.
  The folder must exist. Mux with ffmpeg; analyse by reading `<i4`.
- The headless GdUnit4 run uses the dummy audio driver: players report `playing`, nothing is heard.
- The listener is the current `Camera3D` unless an `AudioListener3D` is current; a high capture camera makes distances
  wrong.
