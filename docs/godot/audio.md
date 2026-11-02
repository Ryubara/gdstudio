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

**A stopped voice lingers until the mixer steps.** `AudioStreamPlayer.stop()` only marks the playback for removal; the
audio server holds it and its stream until the mixer thread has run a few times. Quitting soon after (a headless test,
a capture) then reports leaked `AudioStreamPlayback` objects and streams, at random and more often on a busy machine.
Before `quit()`, wait on the mixer, not on time: poll `AudioServer.get_time_since_last_mix()` once per frame and count
each fall, until about four mixes have landed (with a poll cap).

## Capturing sound

- `--write-movie <absolute folder>/name.png --fixed-fps 10` also writes `name.wav`: 32-bit integer PCM, stereo, 48 kHz.
  The folder must exist. Mux with ffmpeg; analyse by reading `<i4`.
- The headless GdUnit4 run uses the dummy audio driver: players report `playing`, nothing is heard.
- The listener is the current `Camera3D` unless an `AudioListener3D` is current; a high capture camera makes distances
  wrong.
- Movie Maker writes only the mix. For per-bus stems (voice against guns against beds), put an `AudioEffectRecord` on
  each bus to measure and save its recording at the end; it works under Movie Maker
  ([lesson](../lessons/2026-11-01-audio-effect-record-gives-per-bus-stems.md)).
- Transcribe generated voice takes with ElevenLabs Scribe to catch audio tags read aloud: performed sounds come back
  in brackets, spoken tags as words; Scribe bills the speech character quota
  ([lesson](../lessons/2026-11-01-speech-to-text-catches-audio-tags-read-aloud.md)). The whole voice pipeline, from
  casting to the game: [Voice lines](../audio/voice-lines.md).

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

## Close and powerful sounds

A gun "sounding distant" is measured on a recording of the real shot through the real buses, not read off the files
(Deadnight #455, [lesson](../lessons/2026-11-02-gun-shots-sounded-distant-by-the-numbers-nobody-took.md)):

- Measure per sound: peak, loudness (LUFS) against the bed it plays over, the share of energy in the first 50 ms,
  band energies, and the spread of pitch and level across a burst. Give every family of sounds one written pitch and
  level rule and pin it in a test.
- A centred sound in an `AudioStreamPlayer3D` is 6 dB under the same file in an `AudioStreamPlayer` (the engine's 3D
  pan law): the player's own gun plays flat.
- A hard-clipped file decodes from Ogg Vorbis up to +1.5 dB over its PCM peak (ffmpeg `astats` on the decoded float):
  leave 2 to 3 dB of headroom in the trim.
- Never put a sound's power in a bus effect: the web build plays samples, which ignore bus effects and the distance
  filter (see [Web: samples or streams](#web-samples-or-streams)).
- ffmpeg's `ebur128=framelog=verbose` prints its momentary values only at `-v verbose`.

## Starting sounds

Measured in Deadnight's web build (Chrome, RTX 5080, #402): starting an Ogg Vorbis `AudioStreamPlayer` costs about
0.8 ms (headers and codebooks are read again on every `play()`), a PCM one about 0.3 ms, and a 40 s Ogg bed 43 ms. A
frame that starts six sounds pays six times. Decode short sounds (up to 2.5 s) to `AudioStreamWAV` with
`AudioStreamPlayback.mix_audio` while loading, cap starts per frame and defer the rest, and start beds silent and
paused, then fade them in ([lesson](../lessons/2026-11-01-ogg-starts-cost-a-millisecond-in-the-browser.md)).

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
- **`AudioStreamPlayer3D` ignores trims up close.** Its inverse-distance attenuation boosts by `unit_size / distance`
  (a gun 1.7 m away with `unit_size` 14 is 18 dB up) and the only ceiling is `max_db`, +3 dB over the file by default.
  So every sound inside a few metres plays at the ceiling whatever its `volume_db`, and three layers of a shot sum past
  full scale. Set `max_db = volume_db + n` per play (0 for "the trim is the level") and leave far sounds alone. Measured:
  a shotgun trimmed to -23 dB still peaked at -5 dBFS in the mix until `max_db` was set. A loop whose level you move
  needs `max_db` moved with it.
- **A level capture needs a listener.** A Movie Maker recording with no `Camera3D` (or `AudioListener3D`) in the tree is
  silent: nothing hears the 3D players.

## Leaks at exit in a test run

- **A passing GdUnit4 run can still print `ObjectDB instances were leaked at exit` and `resources still in use at
  exit`.** Nothing fails, so nobody looks. The lines belong to whichever suite left something alive: a test lambda that
  held itself through an array (a cycle that keeps the test script in use), or a night whose ambience beds only fade
  out when it is freed. Run the test folders one at a time with `--verbose` to see which stream or script it is. Cut
  the cycle at the end of the test, stop the audio after each test that builds a night, wait `Audio.wait_for_mixer()`
  once, and have CI grep the test log for `leaked at exit|still in use`
  ([lesson](../lessons/2026-11-01-a-gdunit4-run-printed-leaks-at-exit-that-no-test-reported.md)).
- **The check can fail a passing run at random.** A process that quits at once (a test run: GdUnit exits itself)
  leaks whatever voice is playing or just stopped, because the audio server frees a playback only after its mixer
  has stepped a few times. A suite cannot wait after the last test, so wait in the audio autoload's `_exit_tree`:
  block the main thread, counting `AudioServer.get_time_since_last_mix()` falls (the mixer has its own thread). A
  child Godot that starts sounds and quits is a deterministic test for it. `--verbose` makes the engine list every
  leaked instance and resource, and CI keeps those lines as an artifact
  ([lesson](../lessons/2026-11-02-the-exit-leak-check-failed-a-passing-test-run-at-random.md)).

## Web: samples or streams

Godot 4.3+ plays an `AudioStreamPlayer` in a web export as a *sample* by default
(`audio/general/default_playback_type.web`): the browser's own `AudioBufferSourceNode`s. Measured on Deadnight's
export (#421) with a tap on the browser's audio output:

| | Samples (default) | Streams |
| --- | --- | --- |
| Bus effect (a -12 dB `AudioEffectAmplify`) | ignored (0.1 dB) | applied (-11.8 dB) |
| Player `attenuation_filter_cutoff_hz` (800 Hz on a bright sound) | ignored (0.0 dB) | applied (-31 dB) |
| Bus volume | works (-11.9 dB) | works (-11.6 dB) |
| 32 positional voices | 3.7 dB lower | reference |
| Main thread stalls 60 ms every 0.5 s, no threads build, 44 voices | no dropped blocks | 4 to 10% of 128-sample blocks dropped (crackle) |

- `audio/driver/output_latency.web` of 100 or 150 ms (default 50) did not stop the streams' crackle. 44 voices cost
  about 0.5 ms a frame either way.
- Anything designed with bus effects (a duck, a low-pass for occlusion) has to be heard in the browser before it is
  called done; with samples it is lost.
- To tap the output, wrap `AudioNode.prototype.connect` so connections to an `AudioDestinationNode` go through a
  `GainNode` feeding an `AudioWorklet` that counts zero blocks and sample jumps
  ([lesson](../lessons/2026-11-01-web-samples-ignore-bus-effects.md)).
