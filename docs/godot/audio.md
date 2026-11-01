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

## Layered gunshots and event-timed sounds

- **Split a shot across voices.** Play the report (transient and body, 0.05 to 0.35 s), a long blast and a tail as
  three separate sounds with their own random variants and a few dB of level jitter; the combinations are many even
  with three files each, and a cooldown on the blast and tail of an automatic gun keeps twelve shots a second from
  becoming a wall of tails. Start the tail 40 to 70 ms late: the lot answers late.
- **Time steps to the clip, not the clock.** Read the animation's event frames from its spec (`clips.json`, frames over
  fps) and schedule each step's sound on a clock the owner steps (`advance(delta)`), tagged per player so putting the
  weapon away cancels what is left. A test steps 1 ms either side of each frame and needs no wall time.
- **Stamp a scheduled sound with its due time**, not the step's end: when one big step runs several items, `now()`
  inside an item must be that item's time, or timing assertions see the step size instead of the frame.
- **Hitscan impacts without a hit report:** a pellet that ended short of the weapon's range struck something; the
  zombies' hits arrive in the same batch just after, so queue the world impact for the next step and let each hit
  claim the pellet end nearest its point.
- **Generated sounds (ElevenLabs Sound Effects) vary wildly in level and lead-in.** Peaks from -22 to over 0 dBFS,
  the shot sometimes 0.3 s in, and no seed to repeat one. Trim to where it first rises within 34 dB of its peak,
  normalise to a fixed peak, fade the end, keep loops untrimmed, and keep the prompt with the file.

## A crowd's voices (the dead)

- **Ration at the source, not only in the pool.** A per-zombie random timer plus one gate for the whole horde (one
  idle voice every 0.6 to 1.6 s, from the nearest three that are due) keeps 28 groaning zombies readable; the pool's
  group limit (six voices) is the second guard. Priority puts the cue that matters first: a snarl (65) or a swing (62)
  takes a voice from a groan (30), the boss has a group of its own so it is always heard, and feet are a group of
  their own below the player's steps.
- **Front from back.** Panning cannot tell them apart on two speakers. A low-pass by how far behind the listener a
  sound is (5 kHz at the side to 1.8 kHz straight behind) does: measured, the centre of energy of a horde was 1.2 kHz
  in front and 0.7 kHz behind, with 0 dB of left-right difference either way and about 6 dB at the side.
- **Time a cue to the blow:** start it `windup - lead` after the swing begins, where `lead` is how far into the file
  the effort peaks. Feet: advance the clip's phase at its own cadence (a foot per half cycle) from the same per-id
  phase the view starts the clip at.
- **`unit_size` is a loudness, not a size.** Inverse attenuation is `unit_size / distance`, above 1 inside
  `unit_size`, held only by `max_db` (3 dB): see the lesson on the boss roar that clipped the mix.
- **Analyse a capture per second:** left minus right in dB, centre of energy, peak and clipped samples, against the
  act on screen; a loud case (the boss close by) shows a clip a whole-file peak hides in a long mix.
